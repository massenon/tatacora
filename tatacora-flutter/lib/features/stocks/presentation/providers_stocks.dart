import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../../core/impression/export_etat_a4.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../../core/rbac/regle_archivage.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart';
import '../../parametres/presentation/providers_options_systeme.dart'
    show lireSuppressionActive;
import '../data/stocks_api.dart';
import '../data/stocks_dao.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/calcul_inventaire.dart';
import '../domain/entities/etat_stock.dart';
import '../domain/stock_en_attente.dart';
import '../domain/entities/fiche_stock.dart';
import '../impression/etat_fiche_stock.dart';
import '../impression/etat_inventaire.dart';
import '../impression/etat_stocks.dart';

/// M6 sur la base LOCALE du poste. Les droits et l'auteur sont lus À CHAQUE
/// appel (jamais capturés à la construction) : une session qui change entre
/// deux gestes ne doit pas écrire sous l'identité de la précédente (RG-15).
final stocksDaoProvider = Provider<StocksDao>(
  (ref) => StocksDao(ref.watch(baseLocaleProvider)),
);

final stocksApiProvider = Provider<StocksApi>(
  (ref) => StocksApi(
    dao: ref.watch(stocksDaoProvider),
    peutLire: () => ref.read(droitsProvider).peutLire(ModuleTatacora.m6Stocks),
    peutEcrire: () =>
        ref.read(droitsProvider).peutEcrire(ModuleTatacora.m6Stocks),
    auteurId: () => ref.read(sessionProvider)?.utilisateurId,
    roleUtilisateur: () => ref.read(sessionProvider)?.role,
    // La règle d'archivage, relue À CHAQUE geste depuis la base : la bascule
    // peut se refermer entre l'ouverture de la confirmation et le clic. Elle
    // passe par son lecteur DÉCLARÉ (`lireSuppressionActive`).
    peutArchiver: () async => peutArchiver(
      droits: ref.read(droitsProvider),
      module: ModuleTatacora.m6Stocks,
      role: ref.read(sessionProvider)?.role,
      suppressionActive: await lireSuppressionActive(
        ref.read(baseLocaleProvider),
      ),
    ),
  ),
);

/// Le point de stockage consulté — `null` = tous points confondus.
final pointStockProvider = NotifierProvider<_PointNotifier, String?>(
  _PointNotifier.new,
);

final class _PointNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? id) => state = id;
}

final etatFiltreProvider = NotifierProvider<_EtatNotifier, EtatStockFiltre>(
  _EtatNotifier.new,
);

final class _EtatNotifier extends Notifier<EtatStockFiltre> {
  @override
  EtatStockFiltre build() => EtatStockFiltre.tous;

  void definir(EtatStockFiltre etat) => state = etat;
}

/// La recherche et la catégorie, appliquées **localement sur les lignes
/// calculées**.
///
/// L'état consolidé ne les prend pas en paramètre : les ajouter relancerait le
/// calcul de tout le référentiel à chaque frappe. Le filtrage porte donc sur les
/// lignes déjà là — **et les compteurs d'alarme, eux, restent ceux du
/// référentiel entier** (`calculerEtat`).
final rechercheStockProvider = NotifierProvider<_RechercheNotifier, String>(
  _RechercheNotifier.new,
);

final class _RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

final categorieStockProvider = NotifierProvider<_CategorieNotifier, String?>(
  _CategorieNotifier.new,
);

final class _CategorieNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? categorie) => state = categorie;
}

/// Le filtre « Tous les suivis » du maître (l.52-56). `null` : tous.
///
/// Appliqué sur les lignes déjà calculées, comme la recherche : le suivi ne
/// change pas la PORTÉE du calcul (un article journalier n'a pas de stock), il
/// ne fait que choisir ce qu'on affiche. Les compteurs d'alarme et la
/// répartition « gros / petit stock » restent ceux du référentiel entier.
final suiviStockProvider = NotifierProvider<_SuiviNotifier, SuiviArticle?>(
  _SuiviNotifier.new,
);

final class _SuiviNotifier extends Notifier<SuiviArticle?> {
  @override
  SuiviArticle? build() => null;

  void definir(SuiviArticle? suivi) => state = suivi;
}

/// La consultation elle-même.
///
/// `autoDispose` : quitter l'écran doit oublier la réponse. La garder ferait
/// réafficher, au retour, un stock qui date de la visite précédente — sur un
/// écran où l'on décide de commander.
final etatStockProvider = FutureProvider.autoDispose<ResultatStock>(
  (ref) => ref
      .watch(stocksApiProvider)
      .etat(
        pointId: ref.watch(pointStockProvider),
        etat: ref.watch(etatFiltreProvider),
      ),
);

/// Ce que les ventes du bar ENCORE EN FILE sortiront du stock (RG-05,
/// 21/10/2026) — à DIRE à côté du stock, jamais à y soustraire : le serveur
/// sort le stock à la réception de la vente, et ces sorties redescendent ; un
/// mouvement local serait compté deux fois. Voir `stock_en_attente.dart`.
///
/// Les ventes `en_attente`, `en_cours` et `bloque` comptent ; `synchronise`
/// et `rejete` non (la première est chez le serveur, la seconde n'y entrera
/// jamais). Une boisson sans facteur reçu n'est pas estimée et est comptée à
/// part.
final stockEnAttenteProvider = FutureProvider.autoDispose<StockEnAttente>((
  ref,
) async {
  final db = ref.watch(baseLocaleProvider);
  // Par le SEUL auteur de la file : la lire en direct y ferait un second
  // point d'accès (garde `ecrivains_file_envoi_test`).
  final operations = [
    for (final o in await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.ventes))
      if (o.type == TypeOperationSync.creation &&
          const [
            StatutOperationSync.enAttente,
            StatutOperationSync.enCours,
            StatutOperationSync.bloque,
          ].contains(o.statut))
        o,
  ];
  if (operations.isEmpty) return StockEnAttente.vide;

  final ventes = <({String boissonId, int quantite})>[];
  for (final o in operations) {
    final Object? charge;
    try {
      charge = jsonDecode(o.payload);
    } on FormatException {
      continue;
    }
    final lignes = charge is Map ? charge['lignes'] : null;
    if (lignes is! List) continue;
    for (final l in lignes) {
      if (l is Map && l['module_source'] == 'M5' && l['quantite'] is int) {
        ventes.add((
          boissonId: '${l['code_article']}',
          quantite: l['quantite'] as int,
        ));
      }
    }
  }

  final boissons = {
    for (final b in await db.select(db.cartesBoissonLocal).get())
      b.id: (articleId: b.articleId, facteur: b.unitesVendables),
  };
  return agregerStockEnAttente(ventes: ventes, boissons: boissons);
});

/// Les points de stockage de CE poste. Une liste vide est la vérité (aucun point
/// n'a été créé), pas une donnée manquante : le sélecteur dit comment en créer
/// un. À invalider après chaque création.
final pointsStockProvider = FutureProvider<List<PointStockage>>(
  (ref) => ref.watch(stocksApiProvider).points(),
);

/// Les lignes **telles que l'écran les affiche** — recherche et catégorie
/// appliquées. C'est cette liste que les exports emportent (PA-119).
List<LigneStock> filtrerLignes(
  List<LigneStock> lignes, {
  String terme = '',
  String? categorie,
  SuiviArticle? suivi,
  EtatStockFiltre etat = EtatStockFiltre.tous,
}) {
  final recherche = terme.trim().toLowerCase();

  return lignes
      .where((l) {
        if (recherche.isNotEmpty &&
            !l.libelle.toLowerCase().contains(recherche)) {
          return false;
        }
        if (categorie != null && l.categorie != categorie) return false;
        if (suivi != null && l.suivi != suivi) return false;

        return switch (etat) {
          EtatStockFiltre.tous => true,
          // `calculerEtat` a déjà écarté les articles sains quand `sous_seuil`
          // est demandé ; ce second passage ne retire rien de plus. Il compte
          // pour « en rupture », que l'état consolidé ne filtre pas.
          EtatStockFiltre.sousSeuil => l.sousSeuil || l.enRupture,
          EtatStockFiltre.rupture => l.enRupture,
        };
      })
      .toList(growable: false);
}

/// Les catégories réellement présentes, dérivées des lignes reçues.
///
/// Jamais figées : une catégorie créée au bureau apparaîtrait dans les articles
/// sans apparaître au filtre, et on la croirait vide.
final categoriesStockProvider = Provider.family<List<String>, List<LigneStock>>(
  (ref, lignes) {
    final vues = lignes
        .map((l) => l.categorie)
        .whereType<String>()
        .where((c) => c.isNotEmpty)
        .toSet();
    return vues.toList()..sort();
  },
);

/* ====================================================================== */
/* La FICHE de stock — `m6-inventaires.html`, onglet « Fiche de stock »    */
/* ====================================================================== */

/// Le référentiel d'articles, pour le sélecteur — `null` quand le droit de
/// lecture manque (jamais une liste vide, qui se lirait « aucun article »).
///
/// `autoDispose` : un article créé pendant que l'écran était fermé doit être
/// proposé au retour, et un sélecteur gardé en mémoire ne le verrait pas.
final articlesFicheProvider = FutureProvider.autoDispose<List<ArticleFiche>?>(
  (ref) => ref.watch(stocksApiProvider).articles(),
);

/// La demande en cours — article, période, point.
///
/// Un seul état plutôt que trois providers : les trois partent **ensemble** au
/// calcul, et les séparer le relancerait à chaque champ rempli.
final class DemandeFiche {
  const DemandeFiche({this.articleId, this.debut, this.fin, this.pointId});

  final String? articleId;
  final DateTime? debut;
  final DateTime? fin;
  final String? pointId;

  /// Le calcul exige les trois (article, début, fin) : sans elles il refuserait.
  /// On ne demande donc rien tant que le formulaire est incomplet — plutôt que
  /// d'inventer une période par défaut, qui produirait une fiche dont personne
  /// ne saurait sur quoi elle porte.
  bool get estComplete => articleId != null && debut != null && fin != null;

  DemandeFiche copyWith({
    String? articleId,
    DateTime? debut,
    DateTime? fin,
    String? pointId,
    bool effacerArticle = false,
    bool effacerPoint = false,
  }) => DemandeFiche(
    articleId: effacerArticle ? null : (articleId ?? this.articleId),
    debut: debut ?? this.debut,
    fin: fin ?? this.fin,
    pointId: effacerPoint ? null : (pointId ?? this.pointId),
  );
}

final demandeFicheProvider = NotifierProvider<_DemandeNotifier, DemandeFiche>(
  _DemandeNotifier.new,
);

final class _DemandeNotifier extends Notifier<DemandeFiche> {
  /// La période par défaut couvre TRENTE jours, bornes comprises (`Inventaires::
  /// mount`, PA-135) : « 30 jours » inclut aujourd'hui, sinon le cumul en
  /// couvrirait trente et un et contredirait le libellé du raccourci. Sans
  /// article, la vue ouvre sur « Tous les articles » : la fiche consolidée
  /// exige une période, donc la période est posée d'emblée.
  @override
  DemandeFiche build() {
    final (debut, fin) = RaccourciPeriode.trenteJours.bornes(DateTime.now());
    return DemandeFiche(debut: debut, fin: fin);
  }

  /// `null` : « Tous les articles » (la valeur VIDE de la vue, PO 06/09/2026) —
  /// un choix, pas une absence de choix.
  void article(String? id) =>
      state = state.copyWith(articleId: id, effacerArticle: id == null);

  void point(String? id) =>
      state = state.copyWith(pointId: id, effacerPoint: id == null);

  void periode(DateTime debut, DateTime fin) =>
      state = state.copyWith(debut: debut, fin: fin);

  /// Applique un raccourci du maître, depuis une date **injectée**.
  ///
  /// L'horloge n'est pas lue ici : une fonction qui la lit ne se teste pas deux
  /// fois de la même façon.
  void raccourci(RaccourciPeriode r, DateTime aujourdhui) {
    final (debut, fin) = r.bornes(aujourdhui);
    periode(debut, fin);
  }
}

/// La fiche elle-même, `null` tant que la demande est incomplète.
///
/// `autoDispose` : quitter l'écran doit oublier la fiche. La garder ferait
/// réafficher, au retour, un justificatif calculé sur une autre période.
final ficheStockProvider = FutureProvider.autoDispose<ResultatFiche?>((
  ref,
) async {
  final demande = ref.watch(demandeFicheProvider);
  if (!demande.estComplete) return null;

  return ref
      .watch(stocksApiProvider)
      .fiche(
        articleId: demande.articleId!,
        debut: demande.debut!,
        fin: demande.fin!,
        pointId: demande.pointId,
      );
});

/// La fiche CONSOLIDÉE (« Tous les articles »), `null` tant qu'un article est
/// choisi : la fiche unitaire est alors celle de [ficheStockProvider].
final ficheConsolideeProvider =
    FutureProvider.autoDispose<ResultatFicheConsolidee?>((ref) async {
      final demande = ref.watch(demandeFicheProvider);
      if (demande.articleId != null ||
          demande.debut == null ||
          demande.fin == null) {
        return null;
      }

      return ref
          .watch(stocksApiProvider)
          .ficheConsolidee(
            debut: demande.debut!,
            fin: demande.fin!,
            pointId: demande.pointId,
          );
    });

/// L'export PDF de la fiche, exposé comme **action injectable** — enregistré
/// par la fenêtre « Enregistrer sous » (14/10/2026), rend le CHEMIN écrit,
/// `null` : annulé.
///
/// Jamais un `Printing.layoutPdf` ni une écriture de fichier recopiés dans un
/// écran : un test de widget n'a pas de greffon natif, et il doit exister un
/// seul endroit où le document est produit.
final exporterFicheStockPdfProvider =
    Provider<Future<String?> Function(FicheStock, String?)>(
      (ref) =>
          (fiche, pointLibelle) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'fiche_stock',
                type: TypeFichierEnregistre.pdf,
                octets: await EtatFicheStock.pdf(
                  fiche,
                  pointLibelle: pointLibelle,
                  entete: await ref.read(lireEnteteEtablissementProvider)(),
                ),
              ),
    );

/// L'export tableur — rend le **chemin** du fichier écrit, `null` : annulé.
final exporterFicheStockProvider =
    Provider<Future<String?> Function(FicheStock, String?)>(
      (ref) =>
          (fiche, pointLibelle) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'fiche_stock',
                type: TypeFichierEnregistre.csv,
                octets: EtatFicheStock.csvOctets(
                  fiche,
                  pointLibelle: pointLibelle,
                ),
              ),
    );

/* ====================================================================== */
/* Le JOURNAL des mouvements — `GET /stocks/mouvements`, EF-M6-06          */
/* ====================================================================== */

/// Le journal d'un article, tel que la modale de mouvement l'affiche.
///
/// `autoDispose` : fermer la modale doit oublier la liste. La garder ferait
/// réafficher, à la réouverture, un historique antérieur au mouvement qu'on
/// vient d'enregistrer — c'est-à-dire ferait croire qu'il n'est pas passé, et
/// inviterait à le ressaisir. Un double mouvement ne se corrige que par un
/// mouvement inverse : `mouvements_stock` est en ajout seul.
final journalArticleProvider = FutureProvider.autoDispose
    .family<ResultatJournal, String>(
      (ref, articleId) =>
          ref.watch(stocksApiProvider).mouvements(articleId: articleId),
    );

/* ====================================================================== */
/* L'export tableur de l'état — la modale partagée, puis le fichier         */
/* ====================================================================== */

/// L'export tableur du référentiel — rend le **chemin** du fichier écrit,
/// `null` : annulé dans la fenêtre « Enregistrer sous » (14/10/2026).
///
/// Action injectable, comme `exporterParcProvider` : un test de widget n'a pas
/// de greffon natif, et il doit exister un seul endroit où ce fichier est
/// écrit. Un export silencieux est un export que personne ne retrouve — le
/// toast commun dit le nom du fichier.
final exporterStocksProvider = Provider<Future<String?> Function(EtatStocks)>(
  (ref) =>
      (etat) => ref
          .read(enregistrementExportProvider)
          .exporter(
            base: EtatStocks.prefixeFichier,
            type: TypeFichierEnregistre.csv,
            octets: etat.csvOctets(),
          ),
);

/// L'export « PDF Officiel A4 Imprimable » des articles affichés — mêmes
/// colonnes, mêmes lignes que le CSV, en-tête lu des paramètres.
final exporterStocksPdfProvider =
    Provider<Future<String?> Function(EtatStocks)>(
      (ref) =>
          (etat) => enregistrerEtatA4(
            ref,
            etat.etatA4(),
            base: EtatStocks.prefixeFichier,
          ),
    );

/* ====================================================================== */
/* L'INVENTAIRE physique — le comptage en cours, la feuille, l'historique   */
/* ====================================================================== */

/// L'inventaire OUVERT sur ce poste, `null` tant qu'aucun ne court.
///
/// ## Pourquoi en mémoire, et ce que cela coûte
///
/// Le comptage n'est écrit qu'à la clôture (inventaire, lignes et mouvements en
/// UNE transaction) : le schéma ne porte aucun statut d'inventaire (PA-150), une
/// ligne écrite avant la clôture ne se distinguerait pas d'un inventaire clos.
/// Le prix : FERMER la fenêtre avant de clôturer abandonne le comptage — l'écran
/// le dit. Ce provider n'est PAS `autoDispose` : quitter l'écran Inventaires
/// (pour une fiche, un mouvement) ne perd rien.
final inventaireEnCoursProvider =
    NotifierProvider<_InventaireEnCoursNotifier, InventaireEnCours?>(
      _InventaireEnCoursNotifier.new,
    );

final class _InventaireEnCoursNotifier extends Notifier<InventaireEnCours?> {
  /// Le comptage appartient à la SESSION qui l'a ouvert : un autre compte qui se
  /// connecte ne clôture jamais (sous son nom, RG-15) l'inventaire d'un
  /// collègue — `build` est relancé quand l'utilisateur change, et le brouillon
  /// repart de zéro.
  @override
  InventaireEnCours? build() {
    ref.watch(sessionProvider.select((s) => s?.utilisateurId));
    return null;
  }

  void ouvrir(InventaireEnCours inventaire) => state = inventaire;

  /// Un second comptage du même article ÉCRASE le premier (correction d'une
  /// erreur de saisie) et refige son théorique.
  void compter(String articleId, ComptageBrouillon comptage) =>
      state = state?.avecComptage(articleId, comptage);

  void clore() => state = null;
}

/// La feuille de comptage, `null` sans inventaire ouvert.
///
/// `autoDispose` : la rouvrir doit relire les mouvements — un théorique non
/// compté qui date de la visite précédente fausserait l'écart au comptage.
final feuilleComptageProvider = FutureProvider.autoDispose<FeuilleComptage?>((
  ref,
) async {
  final enCours = ref.watch(inventaireEnCoursProvider);
  if (enCours == null) return null;
  return ref.watch(stocksApiProvider).feuilleDeComptage(enCours);
});

/// L'onglet « Inventaires clôturés » — `null` quand le droit de lecture manque.
final inventairesClosProvider =
    FutureProvider.autoDispose<List<InventaireClos>?>(
      (ref) => ref.watch(stocksApiProvider).inventairesClos(),
    );

/// Le « Dernier inventaire » de chaque point (`AAAA-MM-JJ`) pour le cycle.
final dernierInventaireParPointProvider =
    FutureProvider.autoDispose<Map<String, String>>(
      (ref) => ref.watch(stocksApiProvider).dernierInventaireParPoint(),
    );

/* ====================================================================== */
/* L'archivage des articles — actions INJECTABLES                          */
/* ====================================================================== */

/// L'OUVERTURE de la confirmation (`confirmerArchivageArticle`) : le droit
/// d'archiver exigé dès ici, puis le lot composé (verrous, états bloqué /
/// partiel / nominal). Action injectable, comme les exports.
final preparerArchivageArticlesProvider =
    Provider<Future<ResultatStocks<LotArchivage>> Function(List<String>)>(
      (ref) => ref.watch(stocksApiProvider).preparerArchivage,
    );

/// « Supprimer » de la modale (`archiverArticles`) : il ARCHIVE
/// (`articles.actif = false`), il n'efface rien.
final archiverArticlesProvider =
    Provider<Future<ResultatStocks<ResultatArchivage>> Function(List<String>)>(
      (ref) => ref.watch(stocksApiProvider).archiverArticles,
    );

/// « Restaurer » (`restaurerArticle`) : remet `actif = true`. Seul le droit
/// d'écriture est exigé.
final restaurerArticleProvider =
    Provider<Future<ResultatStocks<String>> Function(String)>(
      (ref) => ref.watch(stocksApiProvider).restaurerArticle,
    );

/// L'export tableur du rapport d'inventaire — rend le **chemin** écrit, `null` :
/// annulé dans la fenêtre « Enregistrer sous ». Action injectable, comme les
/// autres exports.
final exporterInventaireProvider =
    Provider<Future<String?> Function(EtatInventaire)>(
      (ref) =>
          (etat) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: EtatInventaire.prefixeFichier,
                type: TypeFichierEnregistre.csv,
                octets: etat.csvOctets(),
              ),
    );

/// L'export « PDF Officiel A4 Imprimable » du rapport d'inventaire — ses visas
/// sont ceux du gabarit serveur (`pdf/inventaire-rapport.blade.php`).
final exporterInventairePdfProvider =
    Provider<Future<String?> Function(EtatInventaire)>(
      (ref) =>
          (etat) => enregistrerEtatA4(
            ref,
            etat.etatA4(),
            base: EtatInventaire.prefixeFichier,
          ),
    );
