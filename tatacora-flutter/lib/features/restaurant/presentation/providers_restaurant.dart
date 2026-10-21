/// Les providers de M4 — Carte du restaurant et Catalogue de plats.
///
/// ## Tous en `autoDispose`, et c'est la même raison qu'en M6 et M7
///
/// Quitter l'écran doit **oublier** la réponse. La garder ferait réafficher, au
/// retour, une carte qui date de la visite précédente — sur l'écran où l'on
/// décide de ce qu'on sert ce midi. M4 est LOCAL depuis le 09/10/2026 (schéma
/// v14) : chaque lecture relit la base, et une écriture invalide les
/// providers concernés.
///
/// ## Les filtres sont appliqués par le DAO, jamais sur les lignes affichées
///
/// Pour le catalogue, c'est une nécessité : la liste est paginée, et un filtre
/// qui ne verrait que la page affichée dirait « Aucun résultat » sur un
/// catalogue qui contient le plat cherché. Pour la carte, non paginée, c'est un
/// choix de cohérence : la carte rend `filtres_appliques`, et c'est elle que
/// l'export cite (PA-119).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/di/providers.dart';
import '../../../core/fichiers/enregistrement_export.dart';
import '../../../core/impression/entete_parametree.dart';
import '../../../core/rbac/garde_acces.dart';
import '../../pos/data/dto/catalogue_dto.dart' show IndisponibiliteDistante;
import '../../stocks/presentation/providers_stocks.dart';
import '../data/restaurant_api.dart';
import '../data/retraits_plats.dart';
import '../data/restaurant_dao.dart';
import '../domain/entities/carte_restaurant.dart';
import '../domain/entities/plat.dart';
import '../impression/etat_carte_restaurant.dart';

/// M4 sur la base LOCALE du poste. Les droits et l'auteur sont lus À CHAQUE
/// appel (jamais capturés à la construction) : une session qui change entre
/// deux gestes ne doit pas écrire sous l'identité de la précédente (RG-15).
/// Le retrait et la remise d'un plat (v31, 21/10/2026).
final retraitsPlatsProvider = Provider<RetraitsPlats>(
  (ref) => RetraitsPlats(ref.watch(baseLocaleProvider)),
);

final restaurantDaoProvider = Provider<RestaurantDao>(
  (ref) => RestaurantDao(
    ref.watch(baseLocaleProvider),
    stocks: ref.watch(stocksDaoProvider),
  ),
);

final restaurantApiProvider = Provider<RestaurantApi>(
  (ref) => RestaurantApi(
    dao: ref.watch(restaurantDaoProvider),
    peutLire: () =>
        ref.read(droitsProvider).peutLire(ModuleTatacora.m4Restaurant),
    peutEcrire: () =>
        ref.read(droitsProvider).peutEcrire(ModuleTatacora.m4Restaurant),
    auteurId: () => ref.read(sessionProvider)?.utilisateurId,
  ),
);

/* ====================================================================== */
/* Les filtres — un provider par contrôle du maître                        */
/* ====================================================================== */

/// La recherche de la carte — `m4-restaurant-carte.html` l.60,
/// « Rechercher un article… ».
final rechercheCarteRestaurantProvider =
    NotifierProvider<_TexteNotifier, String>(_TexteNotifier.new);

/// Le sélecteur de catégorie de la carte — l.63.
final categorieCarteRestaurantProvider =
    NotifierProvider<_CategorieNotifier, CategoriePlat?>(
      _CategorieNotifier.new,
    );

/// Le sélecteur d'état de la carte — l.64-71.
final etatCarteRestaurantProvider =
    NotifierProvider<_EtatNotifier, EtatArticleCarte>(_EtatNotifier.new);

/// L'onglet actif de la carte. `carte-module.js` l.35 : `ongletActif = 'carte'`
/// — « Carte du jour » est l'onglet par défaut du maître.
final ongletCarteRestaurantProvider =
    NotifierProvider<_OngletNotifier, OngletCarte>(_OngletNotifier.new);

/// Les TROIS onglets de la carte, dans l'ordre de la vue
/// (`pwa/carte/corps.blade.php` l.212-226).
///
/// Le troisième, « Ventes du Restaurant », est l'onglet que le Product Owner a
/// ajouté à la vue le 03/09/2026 ; il était absent de ce client. Il est rendu
/// avec sa raison, jamais avec un tableau vide (voir `ecran_carte_restaurant`).
enum OngletCarte {
  carteDuJour('carte', 'Carte du jour'),
  couvertureDuStock('couverture', 'Couverture du stock'),

  /// `carte_pwa.restaurant.onglet_ventes`.
  ventes('ventes', 'Ventes du Restaurant');

  const OngletCarte(this.cle, this.libelle);

  final String cle;
  final String libelle;
}

/// La recherche du catalogue — `m4-restauration.html` l.62,
/// « Rechercher un plat... ».
final rechercheRestaurationProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

/// Le filtre « Toutes les catégories » du catalogue — l.66-76.
final categorieRestaurationProvider =
    NotifierProvider<_CategorieNotifier, CategoriePlat?>(
      _CategorieNotifier.new,
    );

/// La page courante du catalogue. Elle revient à 1 dès qu'un filtre change —
/// c'est ce que fait le maître (`crud-engine.js` l.89, `pageActuelle = 1`) :
/// rester en page 4 après un filtre qui n'en rend qu'une afficherait une page
/// vide sous un total non nul.
final pageRestaurationProvider = NotifierProvider<_PageNotifier, int>(
  _PageNotifier.new,
);

/// La sélection du catalogue — `selection` de la vue (cases à cocher), par
/// identifiant de plat. Elle revient à vide dès qu'un filtre ou une page change,
/// comme `updated()` de la vue (`$this->selection = []`) : une sélection
/// survivante serait invisible.
final selectionPlatsProvider =
    NotifierProvider<SelectionPlatsNotifier, Set<String>>(
      SelectionPlatsNotifier.new,
    );

final class SelectionPlatsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void definir(Set<String> valeur) => state = valeur;
  void basculer(String id, {required bool coche}) =>
      state = coche ? {...state, id} : ({...state}..remove(id));
  void vider() => state = const {};
}

/// Les retraits de la carte en cours, par plat (`indisponibilites_carte_local`)
/// : la colonne « Disponible » et la carte « Retirés de la carte ».
final platsRetiresProvider =
    FutureProvider.autoDispose<Map<String, IndisponibiliteDistante>>(
      (ref) => ref.watch(retraitsPlatsProvider).retires(),
    );

/// La recherche de l'onglet des fiches techniques.
final rechercheFichesProvider = NotifierProvider<_TexteNotifier, String>(
  _TexteNotifier.new,
);

/// « Fiches vides seulement » : le filtre qui rend le blocage praticable.
final videsSeulementProvider = NotifierProvider<_BoolNotifier, bool>(
  _BoolNotifier.new,
);

/// La page courante de l'onglet des fiches.
final pageFichesProvider = NotifierProvider<_PageNotifier, int>(
  _PageNotifier.new,
);

final class _BoolNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void definir(bool valeur) => state = valeur;
}

final class _TexteNotifier extends Notifier<String> {
  @override
  String build() => '';

  void definir(String valeur) => state = valeur;
}

final class _CategorieNotifier extends Notifier<CategoriePlat?> {
  @override
  CategoriePlat? build() => null;

  void definir(CategoriePlat? valeur) => state = valeur;
}

final class _EtatNotifier extends Notifier<EtatArticleCarte> {
  @override
  EtatArticleCarte build() => EtatArticleCarte.tous;

  void definir(EtatArticleCarte valeur) => state = valeur;
}

final class _OngletNotifier extends Notifier<OngletCarte> {
  @override
  OngletCarte build() => OngletCarte.carteDuJour;

  void definir(OngletCarte valeur) => state = valeur;
}

final class _PageNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void definir(int valeur) => state = valeur < 1 ? 1 : valeur;
  void premiere() => state = 1;
}

/* ====================================================================== */
/* Les lectures                                                            */
/* ====================================================================== */

/// L'écran de carte entier, d'un seul appel.
final carteRestaurantProvider =
    FutureProvider.autoDispose<ResultatRestaurant<CarteRestaurant>>((ref) {
      final terme = ref.watch(rechercheCarteRestaurantProvider).trim();
      final etat = ref.watch(etatCarteRestaurantProvider);

      return ref
          .watch(restaurantApiProvider)
          .carte(
            recherche: terme.isEmpty ? null : terme,
            categorie: ref.watch(categorieCarteRestaurantProvider),
            etat: etat,
          );
    });

/// Le catalogue de plats, paginé.
final platsProvider =
    FutureProvider.autoDispose<ResultatRestaurant<PageRestaurant<Plat>>>((ref) {
      final terme = ref.watch(rechercheRestaurationProvider).trim();

      return ref
          .watch(restaurantApiProvider)
          .plats(
            recherche: terme.isEmpty ? null : terme,
            categorie: ref.watch(categorieRestaurationProvider),
            page: ref.watch(pageRestaurationProvider),
          );
    });

/// Le référentiel des menus — la source du sélecteur « Menu » du formulaire.
///
/// `null` = le serveur n'a rien pu dire. Le formulaire le distingue d'un
/// référentiel vide : « on ne sait pas » et « il n'y en a aucun » n'appellent
/// pas la même correction.
final menusProvider = FutureProvider.autoDispose<List<MenuRestaurant>?>(
  (ref) => ref.watch(restaurantApiProvider).tousLesMenus(),
);

/// Le référentiel des fiches techniques — sélecteur « Fiche technique ».
final recettesProvider = FutureProvider.autoDispose<List<Recette>?>(
  (ref) => ref.watch(restaurantApiProvider).toutesLesRecettes(),
);

/// Les fiches techniques, une page de dix, avec leur coût et leur état.
final fichesProvider =
    FutureProvider.autoDispose<ResultatRestaurant<PageRestaurant<Recette>>>((
      ref,
    ) {
      final terme = ref.watch(rechercheFichesProvider).trim();

      return ref
          .watch(restaurantApiProvider)
          .recettes(
            recherche: terme.isEmpty ? null : terme,
            videsSeulement: ref.watch(videsSeulementProvider),
            page: ref.watch(pageFichesProvider),
          );
    });

/// Les menus, tous (la vue les rend sans pagination).
final menusListeProvider =
    FutureProvider.autoDispose<
      ResultatRestaurant<PageRestaurant<MenuRestaurant>>
    >((ref) => ref.watch(restaurantApiProvider).menus());

/// Les quatre cartes du catalogue, comptées sur le catalogue entier.
final compteursCatalogueProvider =
    FutureProvider.autoDispose<ResultatRestaurant<CompteursCatalogue>>(
      (ref) => ref.watch(restaurantApiProvider).compteursCatalogue(),
    );

/// Les trois cartes de l'onglet des fiches.
final compteursFichesProvider =
    FutureProvider.autoDispose<ResultatRestaurant<CompteursFiches>>(
      (ref) => ref.watch(restaurantApiProvider).compteursFiches(),
    );

/// Les articles de stock offerts à la composition d'une fiche. `null` = on ne
/// sait pas (droit manquant), jamais « aucun article ».
final articlesFichesProvider = FutureProvider.autoDispose<List<ArticleChoix>?>(
  (ref) => ref.watch(restaurantApiProvider).articlesPourFiches(),
);

/// La composition d'une fiche, prête à être rééditée.
final compositionEditableProvider = FutureProvider.autoDispose
    .family<List<({String articleId, String quantite})>?, String>(
      (ref, id) => ref.watch(restaurantApiProvider).compositionEditable(id),
    );

/// Relit tout ce que montre M4 après une écriture : la carte, le catalogue, ses
/// compteurs, les fiches, les menus et les sélecteurs. Un écran qui garderait
/// l'ancienne réponse afficherait un état qui n'existe plus.
void invaliderRestaurant(WidgetRef ref) {
  ref
    ..invalidate(carteRestaurantProvider)
    ..invalidate(platsProvider)
    ..invalidate(menusProvider)
    ..invalidate(recettesProvider)
    ..invalidate(fichesProvider)
    ..invalidate(menusListeProvider)
    ..invalidate(compteursCatalogueProvider)
    ..invalidate(compteursFichesProvider)
    ..invalidate(articlesFichesProvider)
    ..invalidate(platsRetiresProvider);
}

/// La fiche détail d'un plat — ce que la modale « Détail » du maître affiche.
final ficheePlatProvider = FutureProvider.autoDispose
    .family<ResultatRestaurant<LigneCarteRestaurant>, String>(
      (ref, id) => ref.watch(restaurantApiProvider).plat(id),
    );

/// La composition d'une fiche technique — ce qui remplit, pour de vrai, la
/// ligne « Ingrédients principaux » de la modale « Détail ».
final compositionProvider = FutureProvider.autoDispose
    .family<ResultatRestaurant<RecetteDetail>, String>(
      (ref, id) => ref.watch(restaurantApiProvider).recette(id),
    );

/* ====================================================================== */
/* Les trois documents de la carte — actions INJECTABLES                   */
/*                                                                         */
/* Jamais un `Printing.layoutPdf` recopie dans un ecran : un test de widget */
/* n'a pas de greffon natif, et il doit exister un seul endroit ou          */
/* l'impression est declenchee.                                            */
/* ====================================================================== */

/// Le tableau de gestion en PDF — « Générer & Télécharger », format PDF.
/// Enregistré par la fenêtre « Enregistrer sous » (14/10/2026) ; rend le
/// CHEMIN écrit, `null` : annulé.
final exporterCarteRestaurantPdfProvider =
    Provider<Future<String?> Function(List<LigneCarteRestaurant>, String)>(
      (ref) =>
          (lignes, filtre) async => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'carte_restaurant',
                type: TypeFichierEnregistre.pdf,
                octets: await EtatCarteRestaurant.pdf(
                  lignes,
                  filtre: filtre,
                  entete: await ref.read(lireEnteteEtablissementProvider)(),
                ),
              ),
    );

/// La fiche des prix — bouton « Imprimer la fiche des prix » (l.45).
///
/// Rend le **nombre de plats ecartes** faute de tarif : l'ecran le dit, avec
/// les mots du maitre.
final imprimerFichePrixRestaurantProvider =
    Provider<Future<int> Function(List<LigneCarteRestaurant>)>(
      (ref) => (lignes) async {
        final (octets, ecartes) = await EtatCarteRestaurant.ficheDesPrix(
          lignes,
          entete: await ref.read(lireEnteteEtablissementProvider)(),
        );
        await Printing.layoutPdf(
          onLayout: (_) => octets,
          name: EtatCarteRestaurant.titreFiche,
          format: PdfPageFormat.a4,
        );
        return ecartes;
      },
    );

/// L'export tableur — « Générer & Télécharger », format tableur. Rend le
/// **chemin** du fichier, `null` : annulé.
///
/// `utf8.encode` (dans `csvOctets`) : le BOM (U+FEFF) devient EF BB BF.
final exporterCarteRestaurantProvider =
    Provider<Future<String?> Function(List<LigneCarteRestaurant>, String)>(
      (ref) =>
          (lignes, filtre) => ref
              .read(enregistrementExportProvider)
              .exporter(
                base: 'carte_restaurant',
                type: TypeFichierEnregistre.csv,
                octets: EtatCarteRestaurant.csvOctets(lignes, filtre: filtre),
              ),
    );
