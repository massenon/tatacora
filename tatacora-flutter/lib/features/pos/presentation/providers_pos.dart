import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../hebergement/domain/entities/reservation.dart';
import '../../comptabilite/presentation/providers_comptabilite.dart';
import '../../hebergement/presentation/providers_hebergement.dart';
import '../data/catalogue_dao.dart';
import '../data/tables_pos_dao.dart';
import '../data/panier_dao.dart';
import '../data/panier_repository_local.dart';
import '../domain/entities/article_vendable.dart';
import '../domain/entities/mode_reglement.dart';
import '../domain/entities/panier.dart';
import '../domain/entities/reference_catalogue.dart';
import '../domain/entities/table_pos.dart';
import '../domain/repositories/panier_repository.dart';
import '../domain/usecases/gerer_panier.dart';

/// Providers des deux points de vente — Riverpod exclusivement.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée**
/// (`docs/PROPOSITION_MODELE_PANIER_POS.md`, Q1/Q2/Q3).
///
/// ## Un seul jeu de providers pour les deux POS
///
/// Parce qu'il n'y a qu'un seul panier. Deux jeux dupliqueraient la logique de
/// rattachement des consommations, et c'est cette duplication qui produit
/// ensuite les divergences de comportement entre le bar et la réception.
///
/// ## Les écrans ne voient ni DAO ni table
///
/// Comme pour M1 : ils ne connaissent que [GererPanier] et les contrats de
/// dépôt. La provenance de la donnée reste invisible à l'interface.

/// Le DAO des paniers, BRANCHÉ sur le moteur comptable : clôturer un panier passe
/// la pièce de la vente dans la même transaction (règle du PO du 31/08/2026).
/// Le moteur arrive par un résolveur — `moteurComptableProvider` attend
/// l'installation du référentiel — et sans lui clôturer lève.
final panierDaoProvider = Provider<PanierDao>(
  (ref) => PanierDao(
    ref.watch(baseLocaleProvider),
    moteur: () => ref.read(moteurComptableProvider.future),
  ),
);

final depotPanierProvider = Provider<PanierRepository>(
  (ref) => PanierRepositoryLocal(ref.watch(panierDaoProvider)),
);

/// Le referentiel des tables de salle.
final tablesPosDaoProvider = Provider<TablesPosDao>(
  (ref) => TablesPosDao(ref.watch(baseLocaleProvider)),
);

/// L'etat de la salle — espaces, tables, et occupation DEDUITE des paniers.
///
/// Depend de [paniersProvider] : la salle se redessine des qu'un panier
/// s'ouvre ou se cloture. Sans cette dependance, une table encaissee resterait
/// affichee occupee jusqu'au prochain rechargement de l'ecran — un indicateur
/// qui affirme un etat qu'il n'a pas verifie.
final salleProvider = FutureProvider<List<RayonSalle>>((ref) async {
  ref.watch(paniersProvider);
  return ref.watch(tablesPosDaoProvider).salle(inclureFermees: true);
});

final catalogueProvider = Provider<CatalogueRepository>(
  (ref) => ref.watch(catalogueDaoProvider),
);

/// Le DAO lui-meme — exposé pour l'ALIGNEMENT descendant (PA-129), qui écrit
/// les trois catalogues répliqués. Le contrat `CatalogueRepository` ne porte
/// que la lecture : c'est ce qui interdit à un écran d'écrire le catalogue.
final catalogueDaoProvider = Provider<CatalogueDao>(
  (ref) => CatalogueDao(ref.watch(baseLocaleProvider)),
);

/// ⚠ **La descente des trois catalogues a été SUPPRIMÉE le 14/09/2026.**
///
/// `CatalogueApi` et `alignementCatalogueProvider` demandaient au serveur les
/// boissons, les circuits et les véhicules, puis les écrivaient par
/// [CatalogueDao.alignerCatalogue] (PA-129). Le poste est zéro réseau : il n'y
/// a plus de descente.
///
/// **PA-129 n'est donc pas refermée, elle est déplacée** — et c'est le point
/// ouvert le plus lourd de cette bascule. `cartes_boisson_local`,
/// `circuits_local` et `vehicules_local` sont lues partout et écrites par un
/// seul auteur restant : l'amorçage de démonstration
/// (`core/dev/mode_demo.dart`). Sur un poste d'exploitation neuf, **le point
/// de vente n'a rien à vendre**, et la fiche de réservation propose quatre
/// rayons vides sur cinq (PA-110).
///
/// Le livrable qui referme ce point est un **CRUD local du catalogue**, saisi
/// au poste. Tant qu'il n'existe pas, ne rétablissez pas un chiffre par
/// défaut ni un catalogue codé en dur « en attendant » : un référentiel a un
/// seul auteur, et un second auteur est le défaut que ce dépôt a rencontré
/// cinq fois.
const bool catalogueDescenduDuServeur = false;

final gererPanierProvider = Provider<GererPanier>(
  (ref) => GererPanier(ref.watch(depotPanierProvider)),
);

/// Le mode de règlement choisi pour la vente en cours.
///
/// **Il vit dans l'interface, pas dans le panier**, et c'est délibéré : tant
/// que la vente n'est pas clôturée, rien n'est décidé. C'est `cloturer()` qui
/// le fige, en même temps que le montant — les deux vont ensemble, et un mode
/// persisté avant la clôture affirmerait un règlement qui n'a pas eu lieu.
///
/// Remis à [ModeReglement.parDefaut] après chaque clôture : sans quoi un
/// « Porté sur la note de chambre » choisi pour un client resterait armé pour
/// le suivant, qui paierait comptant sans que rien ne l'encaisse.
final class ModeReglementNotifier extends Notifier<ModeReglement> {
  @override
  ModeReglement build() => ModeReglement.parDefaut;

  void definir(ModeReglement mode) => state = mode;

  void reinitialiser() => state = ModeReglement.parDefaut;
}

final modeReglementProvider =
    NotifierProvider<ModeReglementNotifier, ModeReglement>(
      ModeReglementNotifier.new,
    );

/* ====================================================================== */
/* Catalogue — l'AFFICHAGE                                                 */
/* ====================================================================== */

final rayonsProvider = FutureProvider<List<RayonCatalogue>>(
  (ref) => ref.watch(catalogueProvider).rayons(),
);

/// Le rayon affiché — **filtre d'AFFICHAGE, jamais la caisse**.
///
/// ## Le défaut à ne pas réintroduire (PA-79)
///
/// Le POS confondait le filtre de catalogue et la caisse : changer de filtre
/// changeait de poste, donc **vidait le panier** — ce qui interdisait une
/// addition mêlant bar et restaurant, exactement ce que le client a demandé.
///
/// **Le poste dit où se trouve l'argent, pas ce qui est vendu.** Ici, la
/// séparation est structurelle et pas seulement documentaire : ce provider ne
/// touche à aucun panier, et le panier courant vit en base sous son propre
/// identifiant. Changer de filtre ne peut donc **pas** l'atteindre, quand bien
/// même quelqu'un le voudrait.
///
/// `null` signifie « tous les rayons ».
final rayonAfficheProvider = NotifierProvider<RayonAfficheNotifier, String?>(
  RayonAfficheNotifier.new,
);

final class RayonAfficheNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// Change le rayon affiché. Ne touche **rien** d'autre, délibérément.
  void definir(String? codeModule) => state = codeModule;
}

/// Terme de recherche — l'AFFICHAGE lui aussi.
final rechercheProvider = NotifierProvider<RechercheNotifier, String>(
  RechercheNotifier.new,
);

final class RechercheNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String terme) => state = terme;
}

/// Les articles réellement affichés, filtre et recherche appliqués.
///
/// La recherche **ignore le filtre de rayon** : chercher « Béninoise » depuis
/// l'onglet Tourisme doit la trouver, sans quoi il faut deviner l'onglet.
final articlesAffichesProvider = Provider<List<ArticleVendable>>((ref) {
  final List<RayonCatalogue> rayons =
      ref.watch(rayonsProvider).value ?? const <RayonCatalogue>[];
  final terme = ref.watch(rechercheProvider).trim().toLowerCase();
  final rayonActif = ref.watch(rayonAfficheProvider);

  if (terme.isNotEmpty) {
    return rayons
        .expand((RayonCatalogue r) => r.articles)
        .where((ArticleVendable a) => a.libelle.toLowerCase().contains(terme))
        .toList(growable: false);
  }

  return rayons
      .where(
        (RayonCatalogue r) => rayonActif == null || r.module.code == rayonActif,
      )
      .expand((RayonCatalogue r) => r.articles)
      .toList(growable: false);
});

/* ====================================================================== */
/* Paniers — l'ARGENT                                                      */
/* ====================================================================== */

final paniersProvider = FutureProvider<List<Panier>>(
  (ref) => ref.watch(depotPanierProvider).paniers(),
);

final kpisPanierProvider = FutureProvider<KpisPanier>(
  (ref) => KpisPanier.calculer(ref.watch(depotPanierProvider)),
);

/// Le panier de l'écran courant, par identifiant.
///
/// L'identifiant, pas l'objet : le panier vit en base, et le garder en mémoire
/// ferait diverger l'écran de la base à la première écriture concurrente.
final panierActifProvider = NotifierProvider<PanierActifNotifier, String?>(
  PanierActifNotifier.new,
);

final class PanierActifNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? panierId) => state = panierId;
}

final panierCourantProvider = FutureProvider<Panier?>((ref) {
  final id = ref.watch(panierActifProvider);
  if (id == null) return Future.value(null);
  return ref.watch(depotPanierProvider).parId(id);
});

/// Les séjours en cours, pour le POS clients hébergés.
///
/// Un panier de séjour n'a de sens que pour un client **présent** : une
/// réservation annulée ou terminée n'en ouvre pas.
final sejoursEnCoursProvider = FutureProvider<List<Reservation>>((ref) async {
  final toutes = await ref.watch(depotReservationProvider).reservations();
  return toutes
      .where(
        (r) =>
            r.statut == StatutReservation.enCours ||
            r.statut == StatutReservation.confirmee,
      )
      .toList(growable: false);
});

/// Le panier ouvert d'un séjour, s'il existe.
///
/// ⚠ **Q2** — c'est la lecture qui alimente le badge « panier ouvert » de la
/// liste des séjours, et la même que la garde de `ouvrir`.
final panierOuvertPourProvider = FutureProvider.family<Panier?, String>(
  (ref, reservationId) =>
      ref.watch(depotPanierProvider).panierOuvertPour(reservationId),
);

/// Le séjour SÉLECTIONNÉ dans la colonne « Séjours en cours » du point de vente
/// clients hébergés (`heberges.blade.php` l.97, `selectedReservationId`).
///
/// Il ne désigne **pas** un panier : un séjour sans panier est sélectionnable,
/// et c'est le premier article ajouté qui ouvre le sien (l.152,
/// `ajouterAuPanier`). Le panier se retrouve par [paniersDesSejoursProvider],
/// jamais en le gardant ici — il vit en base.
final sejourSelectionneProvider =
    NotifierProvider<SejourSelectionneNotifier, String?>(
      SejourSelectionneNotifier.new,
    );

final class SejourSelectionneNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void definir(String? reservationId) => state = reservationId;
}

/// Le panier OUVERT de chaque séjour en cours, par identifiant de réservation.
///
/// Une seule lecture pour toute la page, comme la vue
/// (`paniersOuvertsDesSejours`, « UNE requête pour tous les séjours affichés »)
/// : la liste, les deux indicateurs de l'en-tête et le panneau de droite
/// lisent la MÊME réponse, donc ne peuvent pas se contredire.
///
/// Il dépend de [paniersProvider] sans en lire la valeur : invalider celui-ci
/// (`rafraichirPaniers`) relit aussi cette carte, sans qu'un écran ait à
/// connaître un second provider.
final paniersDesSejoursProvider = FutureProvider<Map<String, Panier>>((
  ref,
) async {
  ref.watch(paniersProvider);
  final sejours = await ref.watch(sejoursEnCoursProvider.future);
  final depot = ref.watch(depotPanierProvider);
  final paniers = <String, Panier>{};
  for (final sejour in sejours) {
    final ouvert = await depot.panierOuvertPour(sejour.id);
    if (ouvert != null) paniers[sejour.id] = ouvert;
  }
  return paniers;
});

/// Les pastilles de catégorie du catalogue des séjours
/// (`heberges.blade.php` l.132 ; `lang/fr/pos_pwa.php` `heberges.categorie_*`).
///
/// ⚠ ÉCART DÉLIBÉRÉ — `ComposePanier::categoriesDuCatalogue()` (l.210-223).
/// La vue : une pastille par catégorie d'ARTICLE (catégories de boisson, de
/// plat), plus « Tourisme & location » pour les prestations. Ici : une pastille
/// par RAYON (Bar, Restauration, Tourisme & location). Raison (09/10/2026,
/// relue contre `CatalogueDao`) : `ArticleVendable.categorie` porte le CODE
/// brut de la catégorie (`locale`, `Nature`…), pas son libellé français, et les
/// libellés de la vue (`CarteBoisson::CATEGORIES`) n'existent pas sur ce poste.
/// Les afficher bruts serait le défaut corrigé côté serveur le 02/09/2026.
enum CategorieHeberges {
  tout('Tout'),
  bar('Bar'),
  restauration('Restauration'),
  prestations('Tourisme & location');

  const CategorieHeberges(this.libelle);

  /// Le libellé de la pastille, au mot de la vue.
  final String libelle;

  /// Cette catégorie contient-elle les articles de ce module ?
  bool accepte(ModuleVendable module) => switch (this) {
    CategorieHeberges.tout => true,
    CategorieHeberges.bar => module == ModuleVendable.m5Bar,
    CategorieHeberges.restauration => module == ModuleVendable.m4Restaurant,
    CategorieHeberges.prestations =>
      module == ModuleVendable.m8Vehicules ||
          module == ModuleVendable.m9Tourisme,
  };
}

/// La pastille active — filtre d'AFFICHAGE, jamais la caisse (PA-79) : elle ne
/// touche aucun panier.
final categorieHebergesProvider =
    NotifierProvider<CategorieHebergesNotifier, CategorieHeberges>(
      CategorieHebergesNotifier.new,
    );

final class CategorieHebergesNotifier extends Notifier<CategorieHeberges> {
  @override
  CategorieHeberges build() => CategorieHeberges.tout;

  void definir(CategorieHeberges categorie) => state = categorie;
}

/// Les articles affichés par le POS des séjours : la pastille ET la recherche
/// s'appliquent ensemble (`filtrerCatalogue()`, `ComposePanier.php` l.176-201).
///
/// Distinct de [articlesAffichesProvider], dont la recherche IGNORE le rayon :
/// c'est la règle du POS au comptant, pas celle de cette vue.
final articlesHebergesProvider = Provider<List<ArticleVendable>>((ref) {
  final List<RayonCatalogue> rayons =
      ref.watch(rayonsProvider).value ?? const <RayonCatalogue>[];
  final terme = ref.watch(rechercheProvider).trim().toLowerCase();
  final categorie = ref.watch(categorieHebergesProvider);

  return rayons
      .where((RayonCatalogue r) => categorie.accepte(r.module))
      .expand((RayonCatalogue r) => r.articles)
      .where((ArticleVendable a) => a.libelle.toLowerCase().contains(terme))
      .toList(growable: false);
});

/// Recharge tout ce qui dépend d'un panier, après une écriture.
///
/// Une seule fonction plutôt qu'un `invalidate` recopié dans chaque écran :
/// oublier d'invalider une liste laisse une consommation absente de l'écran
/// alors qu'elle est en base, et le barman la ressaisit.
void rafraichirPaniers(WidgetRef ref) {
  ref
    ..invalidate(paniersProvider)
    ..invalidate(kpisPanierProvider)
    ..invalidate(panierCourantProvider)
    ..invalidate(panierOuvertPourProvider);
}
