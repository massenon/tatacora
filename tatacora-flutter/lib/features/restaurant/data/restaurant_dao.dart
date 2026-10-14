import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../stocks/data/stocks_dao.dart';
import '../../stocks/domain/calcul_stock.dart';
import '../../stocks/domain/entities/etat_stock.dart' show SuiviArticle;
import '../domain/calcul_restaurant.dart';
import '../domain/entities/plat.dart';
import '../domain/messages_restaurant.dart';

/// Un refus du DAO : une règle que la base ne peut pas porter seule (une clé
/// étrangère inconnue, un identifiant introuvable…) ou une saisie illisible.
/// Il porte la phrase écrite pour l'exploitant, par champ quand il y en a.
final class RefusRestaurant implements Exception {
  const RefusRestaurant(this.motif, {this.erreurs = const {}});

  /// La phrase d'ensemble.
  final String motif;

  /// Les phrases PAR CHAMP : `libelle`, `prix_vente`, `menu_id`,
  /// `lignes.<rang>.article_id`… N'en garder qu'une obligerait à deviner lequel
  /// des champs a été rejeté.
  final Map<String, String> erreurs;

  @override
  String toString() => 'RefusRestaurant($motif)';
}

/// Un article de stock proposé à la composition d'une fiche.
final class ArticleChoix {
  const ArticleChoix({
    required this.id,
    required this.libelle,
    required this.uniteMesure,
    required this.suivi,
  });

  final String id;
  final String libelle;
  final String uniteMesure;
  final SuiviArticle suivi;
}

/// Ce qu'il faut pour calculer la carte : les plats et leur composition
/// valorisée, plus le point cuisine retenu.
final class DonneesCarte {
  const DonneesCarte({required this.plats, required this.pointCuisineId});

  final List<PlatCalcule> plats;
  final String? pointCuisineId;
}

/// Accès Drift à M4 — **local pur**, et UNIQUE point d'écriture des quatre
/// tables du restaurant.
///
/// ## Aucun mixin généré
///
/// Comme `StocksDao` : on passe par `attachedDatabase.<table>`, sans
/// `@DriftAccessor` ni `part`.
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend une classe de ligne Drift. Les montants sont des
/// francs entiers, les quantités des millièmes ; la conversion en chaîne du
/// serveur (« 4500.00 », « 0.300 ») se fait ICI, une fois.
///
/// ## Rien ne part en file de synchronisation
///
/// Aucune de ces tables n'a de `statut_sync`, et le poste ne parle plus à aucun
/// serveur : annoncer « en attente » serait affirmer une attente sans fin.
///
/// ## Ce que l'écriture garantit
///
///  * le menu, la fiche et l'article d'une ligne sont de VRAIES clés étrangères,
///    vérifiées avant l'écriture avec la phrase du serveur ;
///  * la fiche et sa composition s'écrivent dans UNE transaction, la
///    composition est REMPLACÉE jamais fusionnée (sans quoi un ingrédient
///    retiré à l'écran continuerait de décrémenter) ;
///  * le plat porte son auteur (RG-15) ; « corrigé à la main » est DÉDUIT
///    (`prixCorrigeMainApres`), jamais une case ;
///  * aucune écriture comptable : poser un menu, une fiche ou un plat n'est pas
///    un mouvement d'argent.
class RestaurantDao extends DatabaseAccessor<AppDatabase> {
  RestaurantDao(
    super.db, {
    required this._stocks,
    Uuid? uuid,
    DateTime Function()? maintenant,
  }) : _uuid = uuid ?? const Uuid(),
       _maintenant = maintenant ?? DateTime.now;

  final StocksDao _stocks;
  final Uuid _uuid;
  final DateTime Function() _maintenant;

  /// L'instant que ce DAO utilise — la carte est arrêtée à ce moment.
  DateTime maintenant() => _maintenant();

  /* ================================================================== */
  /* Lecture des calculs                                                 */
  /* ================================================================== */

  /// Toutes les compositions, groupées par fiche et triées par article, comme
  /// le serveur (`orderBy('article_id')`).
  Future<Map<String, List<LigneCompositionLue>>> _compositions() async {
    final lignes = await select(attachedDatabase.ingredientsRecetteLocal).get();
    final parFiche = <String, List<LigneCompositionLue>>{};
    for (final l in lignes) {
      parFiche
          .putIfAbsent(l.recetteId, () => [])
          .add(
            LigneCompositionLue(
              articleId: l.articleId,
              milliemes: l.quantiteMilliemes,
            ),
          );
    }
    for (final liste in parFiche.values) {
      liste.sort((a, b) => a.articleId.compareTo(b.articleId));
    }
    return parFiche;
  }

  /// Le point cuisine, le stock de chaque ingrédient À CE POINT et son coût
  /// moyen pondéré — relus des mouvements de M6, jamais stockés.
  Future<
    ({
      String? pointId,
      Map<String, ArticleCalcul> articles,
      Map<String, int> stockAuPoint,
      Map<String, int> cmp,
    })
  >
  _stockDesIngredients() async {
    final points = await _stocks.points();
    final pointId = choisirPointCuisine([
      for (final p in points) (id: p.id, libelle: p.libelle, type: p.type),
    ]);

    final articles = {for (final a in await _stocks.articles()) a.id: a};

    final parArticle = <String, List<MouvementCalcul>>{};
    for (final m in await _stocks.mouvementsCalcul()) {
      parArticle.putIfAbsent(m.articleId, () => []).add(m);
    }

    return (
      pointId: pointId,
      articles: articles,
      stockAuPoint: {
        for (final e in parArticle.entries)
          e.key: pointId == null ? 0 : stockDe(e.value, pointId: pointId),
      },
      cmp: {
        for (final e in parArticle.entries) e.key: coutMoyenPondereDe(e.value),
      },
    );
  }

  List<IngredientCalcule> _ingredients(
    List<LigneCompositionLue> lignes,
    ({
      String? pointId,
      Map<String, ArticleCalcul> articles,
      Map<String, int> stockAuPoint,
      Map<String, int> cmp,
    })
    stock,
  ) {
    final resultat = <IngredientCalcule>[];
    for (final l in lignes) {
      final a = stock.articles[l.articleId];
      // La clé étrangère l'interdit ; si cela arrive, c'est une anomalie
      // d'intégrité et non un ingrédient gratuit : on ne l'invente pas.
      if (a == null) {
        throw StateError(
          'Ingrédient ${l.articleId} introuvable dans les articles : '
          "la composition n'est plus lisible.",
        );
      }
      resultat.add(
        IngredientCalcule(
          articleId: a.id,
          libelle: a.libelle,
          uniteMesure: a.uniteMesure,
          quantiteMilliemes: l.milliemes,
          suivi: a.suivi,
          seuilCentiemes: a.seuilCentiemes,
          stockCentiemes: stock.stockAuPoint[a.id] ?? 0,
          cmpDixMilliemes: stock.cmp[a.id] ?? 0,
        ),
      );
    }
    return resultat;
  }

  /// Les plats, leur composition valorisée et le point cuisine : tout ce que
  /// `calculerCarte` consomme.
  Future<DonneesCarte> donneesCarte() async {
    final stock = await _stockDesIngredients();
    final compositions = await _compositions();
    final libellesFiches = {
      for (final r in await select(attachedDatabase.recettesLocal).get())
        r.id: r.libelle,
    };

    final p = attachedDatabase.platsLocal;
    final m = attachedDatabase.menusLocal;
    final lignes = await select(
      p,
    ).join([innerJoin(m, m.id.equalsExp(p.menuId))]).get();

    return DonneesCarte(
      pointCuisineId: stock.pointId,
      plats: [
        for (final l in lignes)
          PlatCalcule(
            id: l.readTable(p).id,
            libelle: l.readTable(p).libelle,
            menuId: l.readTable(p).menuId,
            menuType: l.readTable(m).type,
            recetteId: l.readTable(p).recetteId,
            recetteLibelle: libellesFiches[l.readTable(p).recetteId],
            prixFrancs: l.readTable(p).prixVente,
            prixProvisoire: l.readTable(p).prixProvisoire,
            prixCorrigeMain: l.readTable(p).prixCorrigeMain,
            composition: _ingredients(
              compositions[l.readTable(p).recetteId] ?? const [],
              stock,
            ),
          ),
      ],
    );
  }

  /// Toutes les fiches, avec leur composition valorisée et les plats qui s'en
  /// servent.
  Future<List<FicheCalculee>> fiches() async {
    final stock = await _stockDesIngredients();
    final compositions = await _compositions();

    final plats = await select(attachedDatabase.platsLocal).get();
    final platsParFiche = <String, List<String>>{};
    for (final pl in plats) {
      platsParFiche.putIfAbsent(pl.recetteId, () => []).add(pl.libelle);
    }
    for (final liste in platsParFiche.values) {
      liste.sort((a, b) => cleDeComparaison(a).compareTo(cleDeComparaison(b)));
    }

    final lignes = await select(attachedDatabase.recettesLocal).get();
    return [
      for (final r in lignes)
        FicheCalculee(
          id: r.id,
          libelle: r.libelle,
          composition: _ingredients(compositions[r.id] ?? const [], stock),
          platsServis: platsParFiche[r.id] ?? const [],
        ),
    ];
  }

  /// Une fiche, ou `null` si elle n'existe pas.
  Future<FicheCalculee?> fiche(String id) async =>
      (await fiches()).where((f) => f.id == id).firstOrNull;

  /* ================================================================== */
  /* Lecture des référentiels                                            */
  /* ================================================================== */

  Plat _plat(PlatsLocalData p, MenusLocalData m, RecettesLocalData r) => Plat(
    id: p.id,
    libelle: p.libelle,
    prixVente: ecrirePrix(p.prixVente),
    menuId: p.menuId,
    menuLibelle: m.libelle,
    categorieBrute: m.type,
    recetteId: p.recetteId,
    recetteLibelle: r.libelle,
    prixProvisoire: p.prixProvisoire,
    prixCorrigeMain: p.prixCorrigeMain,
  );

  /// Les plats du catalogue, filtrés puis triés (libellé sans accent, puis
  /// identifiant). Le filtre porte sur le catalogue ENTIER : une liste paginée
  /// filtrée page par page dirait « aucun résultat » sur un catalogue qui
  /// contient le plat cherché.
  Future<List<Plat>> plats({
    String? recherche,
    String? categorie,
    String? menuId,
  }) async {
    final p = attachedDatabase.platsLocal;
    final m = attachedDatabase.menusLocal;
    final r = attachedDatabase.recettesLocal;
    final lignes = await select(p).join([
      innerJoin(m, m.id.equalsExp(p.menuId)),
      innerJoin(r, r.id.equalsExp(p.recetteId)),
    ]).get();

    final terme = cleDeComparaison((recherche ?? '').trim());
    final plats = [
      for (final l in lignes)
        if ((categorie == null ||
                categorie.isEmpty ||
                l.readTable(m).type == categorie) &&
            (menuId == null || l.readTable(p).menuId == menuId) &&
            (terme.isEmpty ||
                cleDeComparaison(l.readTable(p).libelle).contains(terme)))
          _plat(l.readTable(p), l.readTable(m), l.readTable(r)),
    ]..sort(_comparerLibelles);
    return plats;
  }

  Future<Plat?> plat(String id) async {
    final p = attachedDatabase.platsLocal;
    final m = attachedDatabase.menusLocal;
    final r = attachedDatabase.recettesLocal;
    final l = await (select(p).join([
      innerJoin(m, m.id.equalsExp(p.menuId)),
      innerJoin(r, r.id.equalsExp(p.recetteId)),
    ])..where(p.id.equals(id))).getSingleOrNull();
    return l == null
        ? null
        : _plat(l.readTable(p), l.readTable(m), l.readTable(r));
  }

  static int _comparerLibelles(Plat a, Plat b) {
    final c = cleDeComparaison(
      a.libelle,
    ).compareTo(cleDeComparaison(b.libelle));
    return c != 0 ? c : a.id.compareTo(b.id);
  }

  /// Les menus, avec le nombre de plats COMPTÉ des plats.
  Future<List<MenuRestaurant>> menus({String? recherche, String? type}) async {
    final comptes = <String, int>{};
    for (final pl in await select(attachedDatabase.platsLocal).get()) {
      comptes[pl.menuId] = (comptes[pl.menuId] ?? 0) + 1;
    }

    final terme = cleDeComparaison((recherche ?? '').trim());
    final lignes = await select(attachedDatabase.menusLocal).get();

    return [
      for (final m in lignes)
        if ((type == null || type.isEmpty || m.type == type) &&
            (terme.isEmpty || cleDeComparaison(m.libelle).contains(terme)))
          _menu(m, comptes[m.id] ?? 0),
    ]..sort((a, b) {
      final c = cleDeComparaison(
        a.libelle,
      ).compareTo(cleDeComparaison(b.libelle));
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  }

  MenuRestaurant _menu(MenusLocalData m, int nbPlats) => MenuRestaurant(
    id: m.id,
    libelle: m.libelle,
    typeBrut: m.type,
    dateDebut: m.dateDebut,
    dateFin: m.dateFin,
    nbPlats: nbPlats,
  );

  Future<MenuRestaurant?> menu(String id) async =>
      (await menus()).where((m) => m.id == id).firstOrNull;

  /// Les articles du stock, triés par libellé sans accent — le sélecteur de la
  /// composition. De VRAIES clés étrangères : jamais du texte libre.
  Future<List<ArticleChoix>> articlesChoix() async {
    final articles = await _stocks.articles();
    final choix =
        [
          for (final a in articles)
            ArticleChoix(
              id: a.id,
              libelle: a.libelle,
              uniteMesure: a.uniteMesure,
              suivi: a.suivi,
            ),
        ]..sort((a, b) {
          final c = cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle));
          return c != 0 ? c : a.id.compareTo(b.id);
        });
    return choix;
  }

  /// La composition d'une fiche telle qu'elle s'ÉDITE : les quantités à trois
  /// décimales (« 0.400 », jamais « 0.4 »), pour que l'enregistrement suivant
  /// réécrive la quantité qui est affichée.
  Future<List<({String articleId, String quantite})>> compositionEditable(
    String recetteId,
  ) async {
    final lignes =
        await (select(attachedDatabase.ingredientsRecetteLocal)
              ..where((l) => l.recetteId.equals(recetteId))
              ..orderBy([(l) => OrderingTerm.asc(l.articleId)]))
            .get();
    return [
      for (final l in lignes)
        (
          articleId: l.articleId,
          quantite: ecrireMilliemes(l.quantiteMilliemes),
        ),
    ];
  }

  /* ================================================================== */
  /* Écriture — seul auteur des quatre tables                            */
  /* ================================================================== */

  void _exigerAuteur(String? auteurId) {
    if (auteurId == null) {
      // RG-15 : une écriture sans auteur rend l'historique inopposable.
      throw const RefusRestaurant(MessagesRestaurant.auteurInconnu);
    }
  }

  /// Crée ou modifie un menu. [SaisieMenu.id] désigne le menu à MODIFIER ;
  /// `null` = création.
  Future<MenuRestaurant> enregistrerMenu(
    SaisieMenu saisie, {
    required String? auteurId,
  }) async {
    _exigerAuteur(auteurId);

    final lue = verifierMenu(saisie);
    if (lue.erreurs.isNotEmpty) {
      throw RefusRestaurant(lue.erreurs.values.first, erreurs: lue.erreurs);
    }

    final id = await transaction(() async {
      final cible = saisie.id;
      if (cible == null) {
        final nouveau = _uuid.v4();
        await into(attachedDatabase.menusLocal).insert(
          MenusLocalCompanion.insert(
            id: nouveau,
            libelle: lue.libelle,
            type: lue.type,
            dateDebut: Value(lue.dateDebut),
            dateFin: Value(lue.dateFin),
            creeLe: _maintenant(),
            creePar: auteurId!,
          ),
        );
        return nouveau;
      }

      final existant = await (select(
        attachedDatabase.menusLocal,
      )..where((m) => m.id.equals(cible))).getSingleOrNull();
      if (existant == null) {
        throw const RefusRestaurant(MessagesRestaurant.menuInexistant);
      }
      await (update(
        attachedDatabase.menusLocal,
      )..where((m) => m.id.equals(cible))).write(
        MenusLocalCompanion(
          libelle: Value(lue.libelle),
          type: Value(lue.type),
          // `null` écrit explicitement : vider une date est un geste, pas un
          // oubli (la saison redevient permanente).
          dateDebut: Value(lue.dateDebut),
          dateFin: Value(lue.dateFin),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      return cible;
    });

    return (await menu(id))!;
  }

  /// Crée ou compose une fiche technique : l'entête ET la composition, dans UNE
  /// transaction. Un refus sur la seconde moitié laisserait une fiche
  /// ORPHELINE, sans ingrédient, indiscernable d'une fiche volontairement vide
  /// — elle apparaîtrait au sélecteur du plat et ne décrémenterait jamais rien.
  ///
  /// La composition est REMPLACÉE, jamais fusionnée : ce que l'écran affiche EST
  /// la fiche après enregistrement.
  Future<Recette> enregistrerRecette(
    SaisieFiche saisie, {
    required String? auteurId,
  }) async {
    _exigerAuteur(auteurId);

    final lue = verifierFiche(saisie);
    if (lue.erreurs.isNotEmpty) {
      throw RefusRestaurant(lue.erreurs.values.first, erreurs: lue.erreurs);
    }

    final id = await transaction(() async {
      // Les articles sont de vraies clés étrangères : la phrase du serveur,
      // posée sur la ligne SAISIE fautive (le rang inclut les lignes vides
      // retirées, pour que l'écran désigne la bonne).
      final connus = {
        for (final a in await select(attachedDatabase.articlesLocal).get())
          a.id,
      };
      final erreurs = <String, String>{};
      var rang = 0;
      for (final l in saisie.lignes) {
        final article = l.articleId.trim();
        if (article.isEmpty && l.quantite.trim().isEmpty) {
          rang++;
          continue;
        }
        if (!connus.contains(article)) {
          erreurs['lignes.$rang.article_id'] =
              MessagesRestaurant.articleInexistant;
        }
        rang++;
      }
      if (erreurs.isNotEmpty) {
        throw RefusRestaurant(erreurs.values.first, erreurs: erreurs);
      }

      final cible = saisie.id;
      late final String recetteId;
      if (cible == null) {
        recetteId = _uuid.v4();
        await into(attachedDatabase.recettesLocal).insert(
          RecettesLocalCompanion.insert(
            id: recetteId,
            libelle: lue.libelle,
            creeLe: _maintenant(),
            creePar: auteurId!,
          ),
        );
      } else {
        final existante = await (select(
          attachedDatabase.recettesLocal,
        )..where((r) => r.id.equals(cible))).getSingleOrNull();
        if (existante == null) {
          throw const RefusRestaurant(MessagesRestaurant.recetteInexistante);
        }
        recetteId = cible;
        await (update(
          attachedDatabase.recettesLocal,
        )..where((r) => r.id.equals(cible))).write(
          RecettesLocalCompanion(
            libelle: Value(lue.libelle),
            modifieLe: Value(_maintenant()),
            modifiePar: Value(auteurId),
          ),
        );
      }

      await (delete(
        attachedDatabase.ingredientsRecetteLocal,
      )..where((l) => l.recetteId.equals(recetteId))).go();
      for (final l in lue.lignes) {
        await into(attachedDatabase.ingredientsRecetteLocal).insert(
          IngredientsRecetteLocalCompanion.insert(
            recetteId: recetteId,
            articleId: l.articleId,
            quantiteMilliemes: l.milliemes,
          ),
        );
      }
      return recetteId;
    });

    return versRecette((await fiche(id))!);
  }

  /// Crée ou modifie un plat. [modification] est vrai quand [SaisiePlat.id]
  /// désigne un plat existant.
  ///
  /// Le menu et la fiche sont de VRAIES clés étrangères, vérifiées avec la
  /// phrase du serveur. « Corrigé à la main » est DÉDUIT (jamais soumis) :
  /// changer le prix d'un plat qui portait un tarif provisoire EST la
  /// correction manuelle.
  Future<Plat> enregistrerPlat(
    SaisiePlat saisie, {
    required bool modification,
    required String? auteurId,
  }) async {
    _exigerAuteur(auteurId);

    final lue = verifierPlat(saisie);
    if (lue.erreurs.isNotEmpty) {
      throw RefusRestaurant(lue.erreurs.values.first, erreurs: lue.erreurs);
    }

    final id = await transaction(() async {
      final erreurs = <String, String>{};
      final menu = await (select(
        attachedDatabase.menusLocal,
      )..where((m) => m.id.equals(saisie.menuId))).getSingleOrNull();
      if (menu == null) erreurs['menu_id'] = MessagesRestaurant.menuInexistant;
      final fiche = await (select(
        attachedDatabase.recettesLocal,
      )..where((r) => r.id.equals(saisie.recetteId))).getSingleOrNull();
      if (fiche == null) {
        erreurs['recette_id'] = MessagesRestaurant.recetteInexistante;
      }
      if (erreurs.isNotEmpty) {
        throw RefusRestaurant(erreurs.values.first, erreurs: erreurs);
      }

      if (!modification) {
        final nouveau = saisie.id ?? _uuid.v4();
        if (saisie.id != null &&
            await (select(
                  attachedDatabase.platsLocal,
                )..where((p) => p.id.equals(nouveau))).getSingleOrNull() !=
                null) {
          throw const RefusRestaurant(
            'Cet identifiant est déjà utilisé par un autre plat.',
          );
        }
        await into(attachedDatabase.platsLocal).insert(
          PlatsLocalCompanion.insert(
            id: nouveau,
            menuId: saisie.menuId,
            recetteId: saisie.recetteId,
            libelle: lue.libelle,
            prixVente: lue.prixFrancs,
            prixProvisoire: Value(saisie.prixProvisoire),
            creeLe: _maintenant(),
            creePar: auteurId!,
          ),
        );
        return nouveau;
      }

      final cible = saisie.id;
      final existant = cible == null
          ? null
          : await (select(
              attachedDatabase.platsLocal,
            )..where((p) => p.id.equals(cible))).getSingleOrNull();
      if (existant == null) {
        throw const RefusRestaurant('Ce plat ne figure pas au catalogue.');
      }

      await (update(
        attachedDatabase.platsLocal,
      )..where((p) => p.id.equals(existant.id))).write(
        PlatsLocalCompanion(
          menuId: Value(saisie.menuId),
          recetteId: Value(saisie.recetteId),
          libelle: Value(lue.libelle),
          prixVente: Value(lue.prixFrancs),
          prixProvisoire: Value(saisie.prixProvisoire),
          prixCorrigeMain: Value(
            prixCorrigeMainApres(
              corrigeActuel: existant.prixCorrigeMain,
              provisoireActuel: existant.prixProvisoire,
              prixActuelFrancs: existant.prixVente,
              prixSoumisFrancs: lue.prixFrancs,
            ),
          ),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      return existant.id;
    });

    return (await plat(id))!;
  }
}
