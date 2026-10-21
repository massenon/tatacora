import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
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

/// L'historique d'un client — ses encaissements, du plus récent au plus ancien
/// (`ClientsCreances::historiqueClient()`). Les relances n'y sont pas : ce poste
/// n'en détient aucune (voir [composerHistoriqueClient]).
final historiqueClientProvider = FutureProvider.autoDispose
    .family<List<MouvementClient>, String>((ref, clientId) async {
      final paiements = await ref.watch(paiementsFactureProvider.future);
      final creances = await ref.watch(creancesProvider.future);
      return composerHistoriqueClient(
        clientId: clientId,
        paiements: paiements,
        creances: creances,
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
