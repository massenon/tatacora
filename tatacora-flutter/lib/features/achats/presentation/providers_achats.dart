/// Les providers de M7 — Approvisionnement et Fournisseurs.
///
/// ## Tous en `autoDispose`, et c'est la même raison qu'en M6
///
/// Quitter l'écran doit **oublier** la réponse : la relire de la base à
/// l'ouverture coûte une requête locale, et ne laisse jamais un registre de
/// commandes qui date de la visite précédente sur l'écran où l'on décide de
/// réceptionner une livraison.
///
/// ## M7 est LOCAL (09/10/2026)
///
/// Les cinq tables d'achats sont écrites par le seul `AchatsDao` et ne partent
/// nulle part (zéro réseau) : voir `core/database/tables/achats_tables.dart`.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../parametres/presentation/providers_options_systeme.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../../stocks/data/stocks_api.dart';
import '../../stocks/domain/entities/etat_stock.dart';
import '../../stocks/presentation/providers_stocks.dart';
import '../data/achats_api.dart';
import '../data/achats_dao.dart';
import '../data/reglements_fournisseur_dao.dart';
import '../domain/entities/bon_reception.dart';
import '../domain/dettes_fournisseurs.dart';
import '../domain/entities/archivage_fournisseur.dart';
import '../domain/entities/commande_achat.dart';
import '../domain/entities/fournisseur.dart';
import '../impression/etat_liste_achats.dart';

/// M7 sur la base LOCALE du poste. Les droits et l'auteur sont lus À CHAQUE
/// appel (jamais capturés à la construction) : une session qui change entre
/// deux gestes ne doit pas écrire sous l'identité de la précédente (RG-15).
final achatsDaoProvider = Provider<AchatsDao>(
  (ref) => AchatsDao(
    ref.watch(baseLocaleProvider),
    stocks: ref.watch(stocksDaoProvider),
  ),
);

/// Le DAO des règlements, branché sur le moteur comptable réel : le règlement et
/// sa pièce s'écrivent dans la même transaction (règle du 31/08/2026).
final reglementsFournisseurDaoProvider = Provider<ReglementsFournisseurDao>(
  (ref) => ReglementsFournisseurDao(
    ref.watch(baseLocaleProvider),
    moteur: () => ref.read(moteurComptableProvider.future),
  ),
);

final achatsApiProvider = Provider<AchatsApi>(
  (ref) => AchatsApi(
    dao: ref.watch(achatsDaoProvider),
    reglements: ref.watch(reglementsFournisseurDaoProvider),
    // La règle d'archivage, relue À CHAQUE geste depuis la base : la bascule peut
    // se refermer entre l'ouverture de la confirmation et le clic.
    // La bascule passe par son lecteur DÉCLARÉ (`lireSuppressionActive`),
    // jamais par une seconde lecture de la clé (R-C, D284).
    peutArchiver: () async => peutArchiver(
      droits: ref.read(droitsProvider),
      module: ModuleTatacora.m7Achats,
      role: ref.read(sessionProvider)?.role,
      suppressionActive: await lireSuppressionActive(
        ref.read(baseLocaleProvider),
      ),
    ),
    peutLire: () => ref.read(droitsProvider).peutLire(ModuleTatacora.m7Achats),
    peutEcrire: () =>
        ref.read(droitsProvider).peutEcrire(ModuleTatacora.m7Achats),
    auteurId: () => ref.read(sessionProvider)?.utilisateurId,
  ),
);

/* ====================================================================== */
/* Les filtres — un provider par contrôle du maître                        */
/* ====================================================================== */

/// La recherche du registre des commandes — `m7-approvisionnement.html` l.338,
/// « Fournisseur, n° de commande… ».
///
/// Envoyée au SERVEUR (`?recherche=`), pas appliquée sur les lignes reçues : la
/// liste est paginée, et un filtre local ne verrait que la page affichée — il
/// dirait « aucune commande » sur un registre qui en contient une.
final rechercheCommandeProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

final statutCommandeProvider =
    NotifierProvider<_StatutNotifier, StatutCommande?>(_StatutNotifier.new);

// PA-185 (11/09/2026) — `conformiteReceptionProvider` est RETIRÉ : l'onglet
// Réceptions de la vue Blade (`pwa/achats/approvisionnement.blade.php`) n'a
// aucun filtre de conformité, seulement une colonne. Le filtre était un ajout
// de ce client (Article 1, interdit n° 07). `AchatsApi.receptions` garde son
// paramètre `conformite` : le serveur le sert, rien ne l'appelle plus.

final rechercheFournisseurProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

final evaluationFournisseurProvider =
    NotifierProvider<_EvaluationNotifier, EvaluationFournisseur?>(
      _EvaluationNotifier.new,
    );

/// La page courante du registre des fournisseurs — `Achats::PAR_PAGE` (25) de
/// la vue, ses liens « ← Précédent » / « Suivant → ». Revient à 1 à chaque
/// changement de filtre : rester à la page 3 d'une liste qui n'en a plus que
/// deux afficherait « Aucun résultat » sur un registre qui en contient.
final pageFournisseurProvider = NotifierProvider<_PageNotifier, int>(
  _PageNotifier.new,
);

/// Les trois contrôles de l'onglet « Commandes d'achat » de
/// `pwa/achats/achats.blade.php` — DISTINCTS de ceux de l'onglet « Commandes »
/// de l'Approvisionnement : un filtre posé sur l'un ne doit pas se retrouver
/// sur l'autre (les providers ne sont pas `autoDispose`, l'état survit à la
/// navigation). Ajoutés le 09/10/2026.
final rechercheCommandesAchatsProvider =
    NotifierProvider<_TexteNotifier, String>(_TexteNotifier.new);

final statutCommandesAchatsProvider =
    NotifierProvider<_StatutNotifier, StatutCommande?>(_StatutNotifier.new);

final pageCommandesAchatsProvider = NotifierProvider<_PageNotifier, int>(
  _PageNotifier.new,
);

final class _PageNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void definir(int valeur) => state = valeur < 1 ? 1 : valeur;
}

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

final class _StatutNotifier extends Notifier<StatutCommande?> {
  @override
  StatutCommande? build() => null;

  void definir(StatutCommande? valeur) => state = valeur;
}

final class _EvaluationNotifier extends Notifier<EvaluationFournisseur?> {
  @override
  EvaluationFournisseur? build() => null;

  void definir(EvaluationFournisseur? valeur) => state = valeur;
}

/// L'instant de référence de l'ancienneté d'une dette (« 12 j »). **Injectable** :
/// un test qui lit l'horloge réelle échoue le jour où elle passe minuit, et la
/// comparaison au serveur (qui fige son temps) ne tiendrait pas.
final horlogeApproProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/* ====================================================================== */
/* Les deux bandeaux de la page Approvisionnement                          */
/* ====================================================================== */

/// Ce que la page dit entre son en-tête et ses cartes : le message de succès
/// (`session('pwa-succes')`) et l'erreur `selection` du composant.
final class BandeauAppro {
  const BandeauAppro({this.succes, this.erreurSelection});

  final String? succes;
  final String? erreurSelection;
}

final bandeauApproProvider =
    NotifierProvider.autoDispose<_BandeauApproNotifier, BandeauAppro>(
      _BandeauApproNotifier.new,
    );

final class _BandeauApproNotifier extends Notifier<BandeauAppro> {
  @override
  BandeauAppro build() => const BandeauAppro();

  void succes(String message) => state = BandeauAppro(succes: message);

  void erreurSelection(String message) =>
      state = BandeauAppro(erreurSelection: message);

  void effacer() => state = const BandeauAppro();
}

/* ====================================================================== */
/* Les listes                                                              */
/* ====================================================================== */

final commandesProvider = FutureProvider.autoDispose
    .family<ResultatAchats<PageAchats<CommandeAchat>>, void>((ref, _) {
      final terme = ref.watch(rechercheCommandeProvider).trim();

      return ref
          .watch(achatsApiProvider)
          .commandes(
            recherche: terme.isEmpty ? null : terme,
            statut: ref.watch(statutCommandeProvider),
          );
    });

final receptionsProvider = FutureProvider.autoDispose
    .family<ResultatAchats<PageAchats<BonReception>>, void>(
      // Sans filtre : la vue n'en offre aucun sur cet onglet (PA-185).
      (ref, _) => ref.watch(achatsApiProvider).receptions(),
    );

final fournisseursProvider = FutureProvider.autoDispose
    .family<ResultatAchats<PageAchats<Fournisseur>>, void>((ref, _) {
      final terme = ref.watch(rechercheFournisseurProvider).trim();

      return ref
          .watch(achatsApiProvider)
          .fournisseurs(
            recherche: terme.isEmpty ? null : terme,
            evaluation: ref.watch(evaluationFournisseurProvider),
            page: ref.watch(pageFournisseurProvider),
          );
    });

/// Le registre de l'onglet « Commandes d'achat » de `achats.blade.php` : mêmes
/// lignes que l'Approvisionnement, d'autres filtres et une autre pagination.
final commandesAchatsProvider = FutureProvider.autoDispose
    .family<ResultatAchats<PageAchats<CommandeAchat>>, void>((ref, _) {
      final terme = ref.watch(rechercheCommandesAchatsProvider).trim();

      return ref
          .watch(achatsApiProvider)
          .commandes(
            recherche: terme.isEmpty ? null : terme,
            statut: ref.watch(statutCommandesAchatsProvider),
            page: ref.watch(pageCommandesAchatsProvider),
            // `Achats::PAR_PAGE` : 25 par page sur cet écran, là où
            // l'Approvisionnement montre jusqu'à 200 lignes sans pagination.
            parPage: 25,
          );
    });

/// Le référentiel ENTIER, pour le sélecteur de la modale de commande.
///
/// `null` quand le serveur n'a rien pu dire : la modale refuse alors de
/// s'ouvrir sur un sélecteur vide, qui se lirait comme « aucun fournisseur
/// enregistré ». `fournisseur_id` est une vraie clé étrangère — sans liste, il
/// n'y a pas de commande possible, et il vaut mieux le dire.
final tousLesFournisseursProvider =
    FutureProvider.autoDispose<List<Fournisseur>?>(
      (ref) => ref.watch(achatsApiProvider).tousLesFournisseurs(),
    );

/* ====================================================================== */
/* L'onglet « Besoins » — servi par M6, pas par M7                         */
/* ====================================================================== */

/// Les articles sous leur seuil — `GET /stocks/etat?sous_seuil=1`.
///
/// ## Aucune route M7 ne les rend, et c'est voulu
///
/// L'onglet « Besoins » liste ce que `ConsultationStockService` calcule déjà.
/// Le dupliquer sous M7 ferait **deux chemins de calcul pour le même chiffre**,
/// exactement ce que PA-121 interdit : le jour où l'un des deux prédicats
/// changerait, l'écran Stocks et l'écran Approvisionnement afficheraient deux
/// vérités sur le même article.
///
/// Le rôle `achats` porte `M6 = 'L'` à la matrice : il y accède.
final besoinsProvider = FutureProvider.autoDispose<ResultatStock>(
  (ref) => ref.watch(stocksApiProvider).etat(etat: EtatStockFiltre.sousSeuil),
);

/* ====================================================================== */
/* La bande d'indicateurs — cinq cartes du maître, TROIS servies           */
/* ====================================================================== */

/// Les cinq indicateurs de `m7-approvisionnement.html` l.95-100.
///
/// ## Les deux dernières sont chiffrées depuis le règlement fournisseur (D66)
///
/// « Fournisseurs à payer » et « Total dû » se lisent des commandes de la liste
/// FILTRÉE de l'onglet Commandes (statut, recherche) et des règlements actifs
/// (`composerIndicateursDettes`) : le serveur les somme sur la même liste
/// (D262). Sans le droit de lecture M7, la liste n'a pas été obtenue et les deux
/// cartes rendent « — » — jamais zéro, qui se lirait « aucune dette ».
final class KpisApprovisionnement {
  const KpisApprovisionnement({
    required this.articlesSousSeuil,
    required this.commandesEnAttente,
    required this.receptionsPartielles,
    required this.fournisseursAPayer,
    required this.totalDuCentimes,
  });

  /// `null` = « non consulté », jamais zéro. Chaque indicateur porte sa propre
  /// issue : le stock peut répondre pendant que M7 est refusé, et l'inverse.
  final int? articlesSousSeuil;
  final int? commandesEnAttente;
  final int? receptionsPartielles;
  final int? fournisseursAPayer;
  final int? totalDuCentimes;
}

final kpisApprovisionnementProvider =
    FutureProvider.autoDispose<KpisApprovisionnement>((ref) async {
      final api = ref.watch(achatsApiProvider);

      final stock = await ref.watch(besoinsProvider.future);
      // La vue compte `brouillon` ET `envoyee` (`whereIn`) : un brouillon est
      // une commande qui attend.
      final attente = await api.compterCommandesEnAttente();
      final partielles = await api.compterCommandes(
        StatutCommande.receptionneePartiellement,
      );
      // La liste FILTRÉE de l'onglet Commandes : le serveur somme ses dettes sur
      // elle (D262).
      final liste = await ref.watch(commandesProvider(null).future);
      final dettes = switch (liste) {
        AchatsRecu(:final donnees) => composerIndicateursDettes(
          donnees.elements,
        ),
        _ => null,
      };

      return KpisApprovisionnement(
        // Le compteur d'alarme du SERVEUR, qui porte sur tout le référentiel —
        // jamais le nombre de lignes affichées : masquer les articles sains ne
        // change pas le nombre d'articles à réapprovisionner.
        articlesSousSeuil: switch (stock) {
          StockRecu(:final etat) => etat.kpis.sousSeuil,
          _ => null,
        },
        commandesEnAttente: switch (attente) {
          AchatsRecu(:final donnees) => donnees,
          _ => null,
        },
        receptionsPartielles: switch (partielles) {
          AchatsRecu(:final donnees) => donnees,
          _ => null,
        },
        fournisseursAPayer: dettes?.fournisseursAPayer,
        totalDuCentimes: dettes?.totalDuCentimes,
      );
    });

/* ====================================================================== */
/* Le rapprochement — EF-M7-04                                             */
/* ====================================================================== */

final rapprochementProvider = FutureProvider.autoDispose
    .family<ResultatAchats<Rapprochement>, String>(
      (ref, commandeId) => ref.watch(achatsApiProvider).rapprocher(commandeId),
    );

/// Le détail d'une commande — ce que consomme la modale « Réception ».
final detailCommandeProvider = FutureProvider.autoDispose
    .family<ResultatAchats<CommandeAchatDetail>, String>(
      (ref, id) => ref.watch(achatsApiProvider).commande(id),
    );

/* ====================================================================== */
/* L'archivage des fournisseurs — actions INJECTABLES                      */
/* ====================================================================== */

/// L'OUVERTURE de la confirmation d'archivage (`confirmerArchivageFournisseur`) :
/// le droit d'archiver exigé dès ici, puis le lot composé (verrous, états
/// bloqué / partiel / nominal). Exposée comme action injectable, comme les
/// exports.
final preparerArchivageProvider =
    Provider<Future<ResultatAchats<LotArchivage>> Function(List<String>)>(
      (ref) => ref.watch(achatsApiProvider).preparerArchivage,
    );

/// « Supprimer » de `pwa/achats/achats.blade.php` : il ARCHIVE
/// (`fournisseurs.actif = false`, `ReferentielFournisseurService`) — un vrai
/// geste depuis le 12/10/2026 (D63). Exposé comme action injectable, comme les
/// exports : un test peut ainsi prouver la branche « archivé » de l'écran sans
/// toucher la base.
final archiverFournisseursProvider =
    Provider<Future<ResultatAchats<ResultatArchivage>> Function(List<String>)>(
      (ref) => ref.watch(achatsApiProvider).archiverFournisseurs,
    );

/// « Restaurer » (même vue, l.259) : remet `actif = true`. Seul le droit
/// d'écriture est exigé.
final restaurerFournisseurProvider =
    Provider<Future<ResultatAchats<Fournisseur>> Function(String)>(
      (ref) => ref.watch(achatsApiProvider).restaurerFournisseur,
    );

/* ====================================================================== */
/* Les exports — actions INJECTABLES                                       */
/* ====================================================================== */

/// L'impression, exposée comme **action injectable**.
///
/// Jamais un `Printing.layoutPdf` recopié dans un écran : un test de widget n'a
/// pas de greffon natif, et il doit exister un seul endroit où l'impression est
/// déclenchée.
final imprimerListeAchatsProvider =
    Provider<Future<void> Function(ListeAchats)>(
      (ref) => (liste) async {
        final octets = await pdfListeAchats(liste);
        await Printing.layoutPdf(
          onLayout: (_) => octets,
          name: liste.titre,
          format: PdfPageFormat.a4,
        );
      },
    );

/// Le dossier où s'écrit l'export tableur. **Injectable** : un test d'export
/// de bout en bout écrit dans un dossier temporaire, jamais dans les documents
/// de la machine, et relit les octets réellement écrits (BOM compris).
final dossierExportAchatsProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationDocumentsDirectory,
);

/// L'export tableur — rend le **chemin** du fichier écrit.
final exporterListeAchatsProvider =
    Provider<Future<String> Function(ListeAchats)>(
      (ref) => (liste) async {
        final dossier = await ref.read(dossierExportAchatsProvider)();
        final m = DateTime.now();
        final horodatage =
            '${m.year}'
            '${m.month.toString().padLeft(2, '0')}'
            '${m.day.toString().padLeft(2, '0')}-'
            '${m.hour.toString().padLeft(2, '0')}'
            '${m.minute.toString().padLeft(2, '0')}'
            '${m.second.toString().padLeft(2, '0')}';
        final fichier = File(p.join(dossier.path, 'achats-$horodatage.csv'));
        await fichier.writeAsBytes(csvOctetsListeAchats(liste));
        return fichier.path;
      },
    );
