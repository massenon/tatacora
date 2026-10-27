import '../../../core/format/cle_comparaison.dart';
import '../domain/calcul_restaurant.dart';
import '../domain/entities/carte_restaurant.dart';
import '../domain/entities/plat.dart';
import '../domain/messages_restaurant.dart';
import '../../bar/domain/entities/trace_prix.dart';
import 'restaurant_dao.dart';

export 'restaurant_dao.dart' show ArticleChoix, RefusRestaurant;

/// Ce qu'un appel de M4 peut rendre — **trois issues distinctes, toujours**.
///
/// Même famille scellée générique que M7, et pour la même raison : une douzaine
/// d'appels ici, autant de familles de trois classes seraient trente-six
/// déclarations que rien ne distinguerait, et la dernière finirait par oublier
/// l'issue « injoignable ».
///
/// ⚠ [RestaurantInjoignable] n'est plus produite par personne depuis le
/// 14/09/2026 : il n'y a plus de serveur à joindre, et une base locale n'est
/// pas hors connexion. Le type est **conservé** parce que les écrans le
/// traitent déjà. Ne le rétablissez pas comme issue d'une lecture locale :
/// « injoignable » enverrait l'exploitant réessayer une liaison qui n'existe
/// pas.
sealed class ResultatRestaurant<T> {
  const ResultatRestaurant();
}

final class RestaurantRecu<T> extends ResultatRestaurant<T> {
  const RestaurantRecu(this.donnees);
  final T donnees;
}

final class RestaurantRefuse<T> extends ResultatRestaurant<T> {
  const RestaurantRefuse({
    required this.motif,
    this.erreurs = const {},
    this.code,
  });

  final String motif;

  /// Les messages **par champ**, affichés tels quels. N'en garder que le
  /// premier obligerait l'utilisateur à deviner lequel de ses champs a été
  /// rejeté.
  final Map<String, String> erreurs;

  final int? code;
}

final class RestaurantInjoignable<T> extends ResultatRestaurant<T> {
  const RestaurantInjoignable();
}

/// Une page, avec le total que le FILTRE retient.
///
/// Sans [total], une page pleine se lirait comme « c'est tout ». Le maître
/// affiche d'ailleurs ce total au mot près : « Affichage de 1-10 **sur 43** »
/// (`crud-engine.js` l.254).
final class PageRestaurant<T> {
  const PageRestaurant({
    required this.elements,
    required this.total,
    required this.page,
    required this.derniere,
    required this.parPage,
  });

  final List<T> elements;
  final int total;
  final int page;
  final int derniere;
  final int parPage;

  /// Le rang du premier élément affiché, à partir de 1 — « Affichage de **1**-10 ».
  /// `0` sur une page vide, comme le maître (`total === 0 ? 0 : debut + 1`).
  int get premier => total == 0 ? 0 : (page - 1) * parPage + 1;

  /// Le rang du dernier — « Affichage de 1-**10** ».
  int get dernier => (page - 1) * parPage + elements.length;
}

/// Les compteurs du catalogue des plats (quatre cartes de la vue).
///
/// Comptés sur le catalogue ENTIER, jamais sur la page affichée : « 3 sans
/// fiche » sur une page filtrée laisserait croire que le reste est composé.
final class CompteursCatalogue {
  const CompteursCatalogue({required this.total, required this.avecFiche});

  final int total;

  /// Les plats dont la fiche porte au moins un ingrédient.
  final int avecFiche;

  int get sansFiche => total - avecFiche;
}

/// Les compteurs de l'onglet des fiches (trois cartes de la vue) — comptés sur
/// le référentiel ENTIER.
final class CompteursFiches {
  const CompteursFiches({
    required this.total,
    required this.vides,
    this.provisoires = 0,
  });

  final int total;

  /// Les fiches dont la composition est PROVISOIRE (`recettes.
  /// composition_provisoire`) : quantités posées, jamais pesées.
  final int provisoires;

  /// Les fiches sans aucun ingrédient : celles dont la vente ne décrémenterait
  /// rien.
  final int vides;
}

/// M4 Restaurant — **source LOCALE** (décision du Product Owner, 09/10/2026).
///
/// @see EF-M4-01 Gestion des menus et cartes
/// @see EF-M4-02 Fiches techniques (ingrédients, quantités, coût matière)
///
/// ⚠ Le nom `RestaurantApi` est historique : ce n'était qu'un client HTTP de
/// dix-huit routes, vidé de son corps le 14/09/2026 (zéro réseau), et la
/// classe n'appelle aucun serveur. Il est conservé pour ne pas rouvrir les
/// écrans qui la consomment ; c'est désormais le cas d'usage de M4, devant
/// [RestaurantDao].
///
/// ## Ce que cette classe décide, et ce qu'elle laisse au DAO
///
///  * **Les droits** — `M4` en lecture pour consulter, en écriture pour toute
///    saisie. Un écran qui masque un bouton ne protège rien.
///  * **La traduction des refus** — le DAO lève [RefusRestaurant] ; ici il
///    devient l'issue que les écrans traitent depuis toujours.
///
/// ## Ce que ce module ne fait PAS, et le dit
///
///  * **Aucune sortie de stock à la vente (RG-05)** : la fiche relie bien un
///    plat à des articles (de vraies clés étrangères), mais la clôture d'un
///    panier et l'émission de la facture sont deux écritures distinctes, et la
///    question de rupture (RG-06) n'a pas de place dans le point de vente. Les
///    portions affichées sont donc celles des mouvements enregistrés, pas
///    celles d'après les ventes — la carte le dit
///    ([MessagesRestaurant.stockSansLesVentes]).
///  * **Aucune écriture comptable** : poser un menu, une fiche ou un plat n'est
///    pas un mouvement d'argent. La VENTE d'un plat, elle, passe par le point
///    de vente et sa facture — une écriture d'argent sans pièce comptable sur
///    ce poste, qui n'en tient pas : décision du PO à prendre, remontée.
///  * **L'historique des prix et « Prix » existent depuis la v38**
///    ([historiquePrix], [modifierPrix]). Le lien direct plat -> article existe
///    depuis la v36 ([lierAuStock]).
///  * **Aucune suppression** : un plat est cité par les lignes de panier et de
///    facture déjà saisies ; le « D » de CRUD n'existe nulle part ici.
final class RestaurantApi {
  RestaurantApi({
    required this._dao,
    required this._peutLire,
    required this._peutEcrire,
    required this._auteurId,
  });

  final RestaurantDao _dao;
  final bool Function() _peutLire;
  final bool Function() _peutEcrire;
  final String? Function() _auteurId;

  /// Pagination d'AFFICHAGE du maître (`crud-engine.js` l.21) : dix lignes.
  static const int platsParPage = 10;

  static ResultatRestaurant<T> _refusLecture<T>() => RestaurantRefuse<T>(
    motif: MessagesRestaurant.droitLectureRefuse,
    code: 403,
  );

  static ResultatRestaurant<T> _refusDroitEcriture<T>() => RestaurantRefuse<T>(
    motif: MessagesRestaurant.droitEcritureRefuse,
    code: 403,
  );

  static ResultatRestaurant<T> _introuvable<T>(String phrase) =>
      RestaurantRefuse<T>(motif: phrase, code: 404);

  /// Exécute une écriture en traduisant les refus du DAO.
  Future<ResultatRestaurant<T>> _ecrire<T>(
    Future<T> Function() ecriture,
  ) async {
    if (!_peutEcrire()) return _refusDroitEcriture<T>();
    try {
      return RestaurantRecu<T>(await ecriture());
    } on RefusRestaurant catch (e) {
      return RestaurantRefuse<T>(motif: e.motif, erreurs: e.erreurs, code: 422);
    }
  }

  static PageRestaurant<T> _page<T>(List<T> tous, int page, int parPage) {
    final par = parPage < 1 ? 1 : parPage;
    final derniere = tous.isEmpty ? 1 : (tous.length + par - 1) ~/ par;
    final numero = page < 1 ? 1 : (page > derniere ? derniere : page);
    final debut = (numero - 1) * par;
    final fin = debut + par > tous.length ? tous.length : debut + par;
    return PageRestaurant<T>(
      elements: tous.sublist(debut, fin),
      total: tous.length,
      page: numero,
      derniere: derniere,
      parPage: par,
    );
  }

  static int _parLibelle(String a, String b) =>
      cleDeComparaison(a).compareTo(cleDeComparaison(b));

  /* ================================================================== */
  /* La carte                                                            */
  /* ================================================================== */

  /// La carte entière, calculée des plats, des fiches et du stock du point
  /// cuisine. [categorie] est le type du menu porteur (`local`, `europeen`,
  /// `special`).
  Future<ResultatRestaurant<CarteRestaurant>> carte({
    String? recherche,
    CategoriePlat? categorie,
    EtatArticleCarte? etat,
  }) async {
    if (!_peutLire()) return _refusLecture();
    final donnees = await _dao.donneesCarte();
    return RestaurantRecu(
      calculerCarte(
        plats: donnees.plats,
        pointCuisineId: donnees.pointCuisineId,
        arreteAu: _dao.maintenant().toIso8601String(),
        recherche: recherche,
        categorie: categorie?.code,
        etat: etat ?? EtatArticleCarte.tous,
      ),
    );
  }

  /// Un plat de la carte, avec sa couverture de stock.
  Future<ResultatRestaurant<LigneCarteRestaurant>> plat(String id) async {
    if (!_peutLire()) return _refusLecture();
    final donnees = await _dao.donneesCarte();
    final carte = calculerCarte(
      plats: donnees.plats,
      pointCuisineId: donnees.pointCuisineId,
      arreteAu: _dao.maintenant().toIso8601String(),
    );
    final ligne = carte.lignes.where((l) => l.id == id).firstOrNull;
    return ligne == null
        ? _introuvable(MessagesRestaurant.platIntrouvable)
        : RestaurantRecu(ligne);
  }

  /* ================================================================== */
  /* Le catalogue des plats                                              */
  /* ================================================================== */

  Future<ResultatRestaurant<PageRestaurant<Plat>>> plats({
    String? recherche,
    CategorieCarte? categorie,
    String? menuId,
    int page = 1,
    int parPage = platsParPage,
  }) async {
    if (!_peutLire()) return _refusLecture();
    return RestaurantRecu(
      _page(
        await _dao.plats(
          recherche: recherche,
          categorie: categorie?.code,
          menuId: menuId,
        ),
        page,
        parPage,
      ),
    );
  }

  /// Les compteurs du catalogue. Le droit de lecture manquant est un REFUS,
  /// pas un zéro : « 0 plat » se lirait « le catalogue est vide ».
  Future<ResultatRestaurant<CompteursCatalogue>> compteursCatalogue() async {
    if (!_peutLire()) return _refusLecture();
    final donnees = await _dao.donneesCarte();
    return RestaurantRecu(
      CompteursCatalogue(
        total: donnees.plats.length,
        avecFiche: donnees.plats.where((p) => p.composition.isNotEmpty).length,
      ),
    );
  }

  /// Crée ou modifie un plat. [SaisiePlat.id] désigne le plat à modifier quand
  /// [modification] est vrai.
  Future<ResultatRestaurant<Plat>> enregistrerPlat(
    SaisiePlat saisie, {
    required bool modification,
  }) => _ecrire(
    () => _dao.enregistrerPlat(
      saisie,
      modification: modification,
      auteurId: _auteurId(),
    ),
  );

  /* ================================================================== */
  /* « Lier au stock » (v36)                                             */
  /* ================================================================== */

  /// Les articles que « Lier au stock » propose (suivi permanent). `null` sans
  /// droit de lecture : « aucun article » se lirait « le stock est vide ».
  Future<List<ArticleChoix>?> articlesPourLien() async {
    if (!_peutLire()) return null;
    return _dao.articlesLiables();
  }

  /// Le solde de l'article au point cuisine, en centièmes (`null` : aucun
  /// point cuisine, ou pas de droit de lecture — on ne sait pas).
  Future<int?> stockCuisineDe(String articleId) async =>
      _peutLire() ? _dao.stockCuisineDe(articleId) : null;

  /// Le lien enregistré du plat (article, conditionnement), ou `null`.
  Future<({String articleId, String unitesVendables})?> lienDe(
    String platId,
  ) async => _peutLire() ? _dao.lienDe(platId) : null;

  /// « Enregistrer le lien » : l'article ET son conditionnement.
  Future<ResultatRestaurant<Plat>> lierAuStock({
    required String platId,
    required String articleId,
    required String conditionnement,
  }) => _ecrire(
    () => _dao.lierAuStock(
      platId: platId,
      articleId: articleId,
      conditionnement: conditionnement,
      auteurId: _auteurId(),
    ),
  );

  /// « Retirer le lien » : les deux colonnes repartent ensemble.
  Future<ResultatRestaurant<Plat>> delierDuStock(String platId) =>
      _ecrire(() => _dao.delierDuStock(platId: platId, auteurId: _auteurId()));

  /* ================================================================== */
  /* « Prix » et « Historique des prix » (v38)                           */
  /* ================================================================== */

  /// « Enregistrer le prix » — le prix SEUL, tracé dans l'historique et enfilé
  /// en modification du plat (`RestaurantDao.modifierPrix`).
  Future<ResultatRestaurant<Plat>> modifierPrix({
    required String platId,
    required String prix,
  }) => _ecrire(
    () => _dao.modifierPrix(platId: platId, prix: prix, auteurId: _auteurId()),
  );

  /// L'historique des prix d'UN plat, du plus récent au plus ancien. Une
  /// LECTURE : le droit d'écriture n'est pas exigé (un cuisinier en lecture
  /// vérifie depuis quand un tarif a changé), le droit de lecture si.
  Future<ResultatRestaurant<List<TracePrix>>> historiquePrix(
    String platId,
  ) async {
    if (!_peutLire()) return _refusLecture();
    return RestaurantRecu(await _dao.historiquePrix(platId));
  }

  /* ================================================================== */
  /* Les menus                                                           */
  /* ================================================================== */

  /// Les menus, sans pagination au sens du serveur : la vue les rend tous
  /// (`Menu::query()->…->get()`). [page] n'est donc pas lue, et `total` vaut
  /// exactement le nombre d'éléments rendus.
  Future<ResultatRestaurant<PageRestaurant<MenuRestaurant>>> menus({
    String? recherche,
    CategoriePlat? type,
    int page = 1,
  }) async {
    if (!_peutLire()) return _refusLecture();
    final tous = await _dao.menus(recherche: recherche, type: type?.code);
    return RestaurantRecu(
      PageRestaurant(
        elements: tous,
        total: tous.length,
        page: 1,
        derniere: 1,
        parPage: tous.isEmpty ? 1 : tous.length,
      ),
    );
  }

  /// `null` — « on ne sait pas », jamais une liste vide — quand le droit de
  /// lecture manque : une liste vide se lirait « aucun menu », et le sélecteur
  /// s'afficherait vide sous un formulaire qui semble fonctionner (PA-129).
  Future<List<MenuRestaurant>?> tousLesMenus({int pagesMax = 20}) async {
    if (!_peutLire()) return null;
    return _dao.menus();
  }

  Future<ResultatRestaurant<MenuRestaurant>> enregistrerMenu(
    SaisieMenu saisie,
  ) => _ecrire(() => _dao.enregistrerMenu(saisie, auteurId: _auteurId()));

  /* ================================================================== */
  /* Les fiches techniques                                               */
  /* ================================================================== */

  /// Les fiches, une page de dix, triées par libellé sans accent.
  /// [videsSeulement] isole celles dont la vente ne décrémenterait rien.
  Future<ResultatRestaurant<PageRestaurant<Recette>>> recettes({
    String? recherche,
    bool videsSeulement = false,
    int page = 1,
    int parPage = platsParPage,
  }) async {
    if (!_peutLire()) return _refusLecture();
    final terme = cleDeComparaison((recherche ?? '').trim());
    final fiches =
        [
          for (final f in await _dao.fiches())
            if ((terme.isEmpty ||
                    cleDeComparaison(f.libelle).contains(terme)) &&
                (!videsSeulement || f.composition.isEmpty))
              versRecette(f),
        ]..sort((a, b) {
          final c = _parLibelle(a.libelle, b.libelle);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
    return RestaurantRecu(_page(fiches, page, parPage));
  }

  Future<ResultatRestaurant<CompteursFiches>> compteursFiches() async {
    if (!_peutLire()) return _refusLecture();
    final fiches = await _dao.fiches();
    return RestaurantRecu(
      CompteursFiches(
        total: fiches.length,
        vides: fiches.where((f) => f.composition.isEmpty).length,
        provisoires: fiches.where((f) => f.compositionProvisoire).length,
      ),
    );
  }

  Future<List<Recette>?> toutesLesRecettes({int pagesMax = 20}) async {
    if (!_peutLire()) return null;
    return [for (final f in await _dao.fiches()) versRecette(f)]..sort((a, b) {
      final c = _parLibelle(a.libelle, b.libelle);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  /// La fiche et sa composition ligne à ligne.
  Future<ResultatRestaurant<RecetteDetail>> recette(String id) async {
    if (!_peutLire()) return _refusLecture();
    final fiche = await _dao.fiche(id);
    if (fiche == null) {
      return _introuvable(MessagesRestaurant.recetteInexistante);
    }
    return RestaurantRecu(
      RecetteDetail(
        recette: versRecette(fiche),
        composition: versLignes(fiche.composition),
      ),
    );
  }

  /// Crée ou compose une fiche, entête et composition dans une transaction.
  Future<ResultatRestaurant<Recette>> enregistrerRecette(SaisieFiche saisie) =>
      _ecrire(() => _dao.enregistrerRecette(saisie, auteurId: _auteurId()));

  /// Les articles de stock offerts à la composition. `null` sans droit de
  /// lecture : « aucun article » se lirait « le stock est vide ».
  Future<List<ArticleChoix>?> articlesPourFiches() async {
    if (!_peutLire()) return null;
    return _dao.articlesChoix();
  }

  /// La composition d'une fiche, prête à être rééditée (trois décimales).
  Future<List<({String articleId, String quantite})>?> compositionEditable(
    String recetteId,
  ) async {
    if (!_peutLire()) return null;
    return _dao.compositionEditable(recetteId);
  }
}
