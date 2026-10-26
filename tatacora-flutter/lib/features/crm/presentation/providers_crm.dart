import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart';
import '../../achats/domain/messages_achats.dart' show MessagesAchats;
import '../../parametres/presentation/providers_options_systeme.dart';
import '../data/archivage_clients.dart';
import '../data/relances_clients_dao.dart';
import '../domain/entities/relance.dart';
import '../domain/messages_archivage_client.dart';
import '../domain/messages_relance.dart';
import '../domain/regles_relance.dart';
import '../domain/historique_client.dart';
import '../impression/etat_clients.dart';
import '../impression/releve_client.dart';

import '../../facturation/presentation/providers_paiements.dart';
import '../../hebergement/presentation/providers_hebergement.dart'
    show clientDaoProvider;
import '../domain/entities/registre_clients.dart';

/// Le registre des clients : les clients du poste et leurs créances.
///
/// Le solde est celui du SERVEUR (`SoldeClientService::registre()`) : la somme du
/// reste dû de leurs factures impayées, par la formule UNIQUE de `creances.dart`
/// que lit aussi le tableau de bord. Aucune requête SQL dédiée : une jointure
/// serait plus rapide et **dupliquerait la formule** — le jour où elle changerait,
/// l'écran Clients et le tableau de bord afficheraient deux dettes différentes
/// pour la même personne (PA-121).
///
/// `autoDispose`, comme les lectures de M11 : un registre gardé d'une visite à
/// l'autre montrerait le solde d'avant le dernier encaissement.
final registreClientsProvider = FutureProvider.autoDispose<List<LigneClient>>((
  ref,
) async {
  final clients = await ref.watch(clientDaoProvider).clients();
  final creances = await ref.watch(creancesProvider.future);

  return composerRegistre(clients: clients, creances: creances);
});

final rechercheClientProvider =
    NotifierProvider<_RechercheClientNotifier, String>(
      _RechercheClientNotifier.new,
    );

final class _RechercheClientNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final etatCreanceProvider = NotifierProvider<_EtatCreanceNotifier, EtatCreance>(
  _EtatCreanceNotifier.new,
);

final class _EtatCreanceNotifier extends Notifier<EtatCreance> {
  @override
  EtatCreance build() => EtatCreance.tous;

  void definir(EtatCreance etat) => state = etat;
}

/// Le registre **tel que l'écran l'affiche**, filtres appliqués.
///
/// C'est cette liste-là que les exports emportent : « l'export porte sur ce
/// qui est affiché » (PA-119).
final registreFiltreProvider = FutureProvider.autoDispose<List<LigneClient>>((
  ref,
) async {
  final lignes = await ref.watch(registreClientsProvider.future);

  return filtrerRegistre(
    lignes,
    terme: ref.watch(rechercheClientProvider),
    etat: ref.watch(etatCreanceProvider),
  );
});

/// L'export PDF du registre, exposé comme **action injectable** — enregistré
/// par la fenêtre « Enregistrer sous » (14/10/2026), rend le CHEMIN écrit,
/// `null` : annulé.
///
/// Jamais un `Printing.layoutPdf` ni une écriture de fichier recopiés dans un
/// écran : un test de widget n'a pas de greffon natif, et il doit exister un
/// seul endroit où le document est produit.
final exporterRegistreClientsPdfProvider =
    Provider<Future<String?> Function(List<LigneClient>, String)>(
      (ref) =>
          (lignes, filtre) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'registre_clients',
                type: TypeFichierEnregistre.pdf,
                octets: await EtatClients.pdf(
                  lignes,
                  filtre: filtre,
                  entete: await ref.read(lireEnteteEtablissementProvider)(),
                ),
              ),
    );

/// L'export tableur — rend le **chemin** du fichier écrit, `null` : annulé.
///
/// Un export silencieux est un export que personne ne retrouve.
///
/// Fichier **CSV**, pas XLSX : convention serveur RG-19, écart nommé en PA-111.
final exporterRegistreClientsProvider =
    Provider<Future<String?> Function(List<LigneClient>, String)>(
      (ref) =>
          (lignes, filtre) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'registre_clients',
                type: TypeFichierEnregistre.csv,
                octets: EtatClients.csvOctets(lignes, filtre: filtre),
              ),
    );

/// L'historique d'un client — ses encaissements, du plus récent au plus ancien,
/// puis ses relances (`ClientsCreances::historiqueClient()`, la vue boucle les
/// paiements puis les relances).
final historiqueClientProvider = FutureProvider.autoDispose
    .family<List<MouvementClient>, String>((ref, clientId) async {
      final paiements = await ref.watch(paiementsFactureProvider.future);
      final creances = await ref.watch(creancesProvider.future);
      final relances = await ref.watch(
        relancesDuClientProvider(clientId).future,
      );
      return composerHistoriqueClient(
        clientId: clientId,
        paiements: paiements,
        creances: creances,
        relances: relances,
      );
    });

/// « Imprimer PDF » de l'historique d'un client : le relevé, enregistré par la
/// fenêtre « Enregistrer sous » (la vue le télécharge, `streamDownload`), rend le
/// CHEMIN écrit, `null` : annulé.
///
/// Une action injectable : un test de widget n'a pas de greffon natif, et il doit
/// exister un seul endroit où le document est produit.
final exporterReleveClientProvider =
    Provider<Future<String?> Function(ReleveClient)>(
      (ref) =>
          (releve) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'releve_client',
                type: TypeFichierEnregistre.pdf,
                octets: await releve
                    .avecEntete(
                      await ref.read(lireEnteteEtablissementProvider)(),
                    )
                    .pdf(),
              ),
    );

/* ====================================================================== */
/* Les relances (EF-M3-03)                                                */
/* ====================================================================== */

/// L'horloge est celle des créances (`horlogeCreancesProvider`) : la date d'une
/// relance et l'ancienneté d'une dette se lisent sur la MÊME horloge.
final relancesClientsDaoProvider = Provider<RelancesClientsDao>(
  (ref) => RelancesClientsDao(
    ref.watch(baseLocaleProvider),
    maintenant: ref.watch(horlogeCreancesProvider),
  ),
);

/// Toutes les relances, SANS plafond : la dernière relance de chaque client en
/// est tirée (`MAX(date_relance)` du serveur ne connaît pas le plafond du
/// journal).
final toutesLesRelancesProvider = FutureProvider.autoDispose<List<Relance>>(
  (ref) => ref.watch(relancesClientsDaoProvider).toutes(),
);

/// « Historique des relances » : les plus récentes d'abord, 200 au plus.
final historiqueRelancesProvider = FutureProvider.autoDispose<List<Relance>>(
  (ref) => ref.watch(relancesClientsDaoProvider).historique(),
);

/// Les relances d'UN client — pour sa modale « Historique » et son relevé.
final relancesDuClientProvider = FutureProvider.autoDispose
    .family<List<Relance>, String>(
      (ref, clientId) =>
          ref.watch(relancesClientsDaoProvider).deClient(clientId),
    );

/// « Clients à relancer » : les débiteurs sans relance depuis 30 jours.
final clientsARelancerProvider =
    FutureProvider.autoDispose<List<ClientARelancer>>((ref) async {
      final registre = await ref.watch(registreClientsProvider.future);
      final relances = await ref.watch(toutesLesRelancesProvider.future);
      return clientsARelancer(
        registre: registre,
        relances: relances,
        maintenant: ref.watch(horlogeCreancesProvider)(),
      );
    });

/// La saisie de la modale « Tracer une relance ».
typedef SaisieRelance = ({
  String clientId,
  String clientNom,
  String canal,
  String? montant,
  DateTime? promesse,
  String? commentaire,
});

/// `ClientsCreances::enregistrerRelance` : le droit d'écrire sur M3, la
/// validation du montant (`required|numeric|min:0`), puis le service. Rend le
/// message de succès ; lève [RefusRelance] — la saisie reste, le refus se dit
/// sous le montant.
final enregistrerRelanceProvider =
    Provider<Future<String> Function(SaisieRelance)>(
      (ref) => (saisie) async {
        if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.m3Crm)) {
          throw const RefusRelance(MessagesRelance.droitManquant);
        }
        final montant = lireMontantRelance(saisie.montant);
        if (montant.refus != null) throw RefusRelance(montant.refus!);
        await ref
            .read(relancesClientsDaoProvider)
            .enregistrer(
              clientId: saisie.clientId,
              canal: saisie.canal,
              montantReclameCentimes: montant.centimes!,
              promesse: saisie.promesse,
              commentaire: saisie.commentaire,
              auteurLogin: ref.read(sessionProvider)?.login,
            );
        ref
          ..invalidate(toutesLesRelancesProvider)
          ..invalidate(historiqueRelancesProvider)
          ..invalidate(relancesDuClientProvider(saisie.clientId))
          ..invalidate(clientsARelancerProvider)
          ..invalidate(historiqueClientProvider(saisie.clientId));
        return MessagesRelance.succes(saisie.clientNom);
      },
    );

/* ====================================================================== */
/* L'archivage des clients (EF-M3-01)                                      */
/* ====================================================================== */

final archivageClientsProvider = Provider<ArchivageClients>(
  (ref) => ArchivageClients(
    ref.watch(baseLocaleProvider),
    creances: () => lireCreances(ref.read),
    maintenant: ref.watch(horlogeCreancesProvider),
  ),
);

/// `$peutArchiver` de la vue : la règle UNIQUE de `regle_archivage.dart` sur M3.
/// L'écran la reçoit ; il ne la recalcule jamais.
final peutArchiverClientsProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(peutArchiverProvider(ModuleTatacora.m3Crm)),
);

/// La sélection de la liste (cases de la colonne « Client »).
final selectionClientsProvider =
    NotifierProvider<_SelectionClientsNotifier, Set<String>>(
      _SelectionClientsNotifier.new,
    );

final class _SelectionClientsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void basculer(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  }

  void vider() => state = const {};
}

/// `exigerArchivage()` : le droit d'archiver, relu À CHAQUE geste (la bascule
/// peut se refermer entre l'ouverture de la confirmation et le clic).
Future<void> _exigerArchivage(Ref ref) async {
  final autorise = peutArchiver(
    droits: ref.read(droitsProvider),
    module: ModuleTatacora.m3Crm,
    role: ref.read(sessionProvider)?.role,
    suppressionActive: await lireSuppressionActive(
      ref.read(baseLocaleProvider),
    ),
  );
  if (!autorise) throw const RefusArchivageClient(MessagesAchats.refusBascule);
}

/// L'OUVERTURE de la confirmation (`confirmerArchivageClient`) : le droit
/// d'archiver exigé dès ici, puis le lot composé (verrous, bloqué / partiel /
/// nominal). Les motifs datent de l'ouverture et ne protègent rien : le verrou
/// qui tranche est recontrôlé à l'exécution.
final preparerArchivageClientsProvider =
    Provider<Future<LotArchivage> Function(List<String>)>(
      (ref) => (ids) async {
        await _exigerArchivage(ref);
        return ref.read(archivageClientsProvider).composerLot(ids);
      },
    );

/// L'EXÉCUTION (`archiverClients`) : le droit est exigé de nouveau, puis chaque
/// client du lot est archivé — un refus n'empêche pas les autres.
final archiverClientsProvider =
    Provider<Future<ResultatArchivage> Function(List<String>)>(
      (ref) => (ids) async {
        await _exigerArchivage(ref);
        final resultat = await ref
            .read(archivageClientsProvider)
            .archiverLot(ids);
        ref
          ..invalidate(registreClientsProvider)
          ..invalidate(clientsARelancerProvider)
          ..read(selectionClientsProvider.notifier).vider();
        return resultat;
      },
    );

/// « Restaurer » : seul le droit d'écrire sur M3 est exigé, JAMAIS la règle
/// d'archivage. Rend le message de succès.
final restaurerClientProvider = Provider<Future<String> Function(String)>(
  (ref) => (id) async {
    if (!ref.read(droitsProvider).peutEcrire(ModuleTatacora.m3Crm)) {
      throw const RefusArchivageClient(MessagesRelance.droitManquant);
    }
    final nom = await ref.read(archivageClientsProvider).restaurer(id);
    ref.invalidate(registreClientsProvider);
    return MessagesArchivageClient.restaure(nom);
  },
);
