import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../pos/data/indisponibilites_carte_dao.dart';
import '../../stocks/data/stocks_dao.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
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

  /// Le lien direct d'un plat, valorisé au point cuisine, ou `null` : pas de
  /// lien, ou un article que ce poste n'a pas (encore) reçu — on ne l'invente
  /// pas, le plat retombe sur sa fiche.
  LienDirectCalcule? _lien(
    PlatsLocalData p,
    ({
      String? pointId,
      Map<String, ArticleCalcul> articles,
      Map<String, int> stockAuPoint,
      Map<String, int> cmp,
    })
    stock,
  ) {
    final articleId = p.articleId;
    final unites = p.unitesVendables == null
        ? null
        : lireDixMilliemes(p.unitesVendables!);
    if (articleId == null || unites == null || unites <= 0) return null;
    final a = stock.articles[articleId];
    if (a == null) return null;
    return LienDirectCalcule(
      articleId: a.id,
      libelle: a.libelle,
      uniteMesure: a.uniteMesure,
      suivi: a.suivi,
      unitesVendables: ecrireDixMilliemes(unites),
      unitesDixMilliemes: unites,
      stockCentiemes: stock.stockAuPoint[a.id] ?? 0,
      seuilCentiemes: a.seuilCentiemes,
    );
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

    final retraits = await IndisponibilitesCarteDao(
      attachedDatabase,
    ).platsRetires();

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
            indisponibilite: retraits[l.readTable(p).id],
            lien: _lien(l.readTable(p), stock),
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
          compositionProvisoire: r.compositionProvisoire == true,
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
        await _enfilerMenu(nouveau, avant: null);
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
      await _enfilerMenu(cible, avant: existant);
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
      // Lot F1 : le document AVANT l'écriture, pour n'envoyer que ce qui
      // change (`null` = création).
      final avant = cible == null ? null : await _chargeRecette(cible);
      // La marque « composition provisoire » (v35) : posée par le serveur (ses
      // fiches semées), elle TOMBE d'elle-même quand la composition est
      // réenregistrée (`CompositionRecetteService::remplacerComposition`, seul
      // auteur) — c'est le geste de la lever depuis « Fiches techniques ».
      final etaitProvisoire =
          cible != null &&
          (await (select(
                    attachedDatabase.recettesLocal,
                  )..where((r) => r.id.equals(cible))).getSingleOrNull())
                  ?.compositionProvisoire ==
              true;
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
            // Une composition réenregistrée n'est plus « posée, jamais pesée ».
            // Une fiche laissée sans ingrédient n'a rien relevé : sa marque
            // reste ce qu'elle était.
            compositionProvisoire: lue.lignes.isEmpty
                ? const Value.absent()
                : const Value(false),
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
      final apres = (await _chargeRecette(recetteId))!;
      // Lever la marque d'une fiche provisoire demande au serveur de REMPLACER
      // la composition, même inchangée : la modification porte donc `lignes`
      // (sinon le serveur garderait la marque que ce poste vient de lever).
      final leve = etaitProvisoire && lue.lignes.isNotEmpty;
      final differences = avant == null ? apres : champsModifies(avant, apres);
      await _file.enfiler(
        table: TableSynchronisee.recettes,
        entiteId: recetteId,
        type: avant == null
            ? TypeOperationSync.creation
            : TypeOperationSync.modification,
        payload: leve && avant != null
            ? {...differences, 'lignes': apres['lignes']}
            : differences,
      );
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
        await _enfilerPlat(nouveau, avant: null);
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
      await _enfilerPlat(existant.id, avant: existant);
      return existant.id;
    });

    return (await plat(id))!;
  }

  /* ================================================================== */
  /* « Lier au stock » (v36) — le lien DIRECT d'un plat à un article      */
  /* ================================================================== */

  /// Les articles que « Lier au stock » propose : actifs ET en suivi
  /// PERMANENT (la phrase de la vue : un article en achat journalier n'est pas
  /// suivi, le rattacher ne décrémenterait rien).
  Future<List<ArticleChoix>> articlesLiables() async =>
      [
        for (final a in await _stocks.articles())
          if (a.actif && a.suivi == SuiviArticle.permanent)
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

  /// Le solde de [articleId] au point cuisine, en centièmes ; `null` quand
  /// aucun point cuisine n'existe (on ne sait pas, ce n'est pas zéro).
  Future<int?> stockCuisineDe(String articleId) async {
    final stock = await _stockDesIngredients();
    return stock.pointId == null ? null : (stock.stockAuPoint[articleId] ?? 0);
  }

  /// Le lien enregistré d'un plat : l'article et le conditionnement (texte
  /// décimal), ou `null`.
  Future<({String articleId, String unitesVendables})?> lienDe(
    String platId,
  ) async {
    final p = await (select(
      attachedDatabase.platsLocal,
    )..where((x) => x.id.equals(platId))).getSingleOrNull();
    if (p == null || p.articleId == null || p.unitesVendables == null) {
      return null;
    }
    return (articleId: p.articleId!, unitesVendables: p.unitesVendables!);
  }

  /// `CartePlatMenuService::lierAuStock` : l'article ET son conditionnement
  /// vont ENSEMBLE ; le lien se REMPLACE. Le conditionnement est strictement
  /// positif, l'article existe. Enfilé (modification du plat) dans la même
  /// transaction.
  Future<Plat> lierAuStock({
    required String platId,
    required String articleId,
    required String conditionnement,
    required String? auteurId,
  }) async {
    _exigerAuteur(auteurId);

    await transaction(() async {
      final existant = await (select(
        attachedDatabase.platsLocal,
      )..where((p) => p.id.equals(platId))).getSingleOrNull();
      if (existant == null) {
        throw const RefusRestaurant(MessagesRestaurant.platIntrouvable);
      }

      final erreurs = <String, String>{};
      if (articleId.trim().isEmpty) {
        erreurs['article_stock_id'] = MessagesRestaurant.articleLienObligatoire;
      } else if (await (select(
            attachedDatabase.articlesLocal,
          )..where((a) => a.id.equals(articleId))).getSingleOrNull() ==
          null) {
        erreurs['article_stock_id'] = MessagesRestaurant.articleLienInconnu;
      }

      final texte = conditionnement.trim();
      final unites = lireDixMilliemes(texte);
      if (texte.isEmpty) {
        erreurs['unites_vendables'] = MessagesRestaurant.conversionRequise(
          existant.libelle,
        );
      } else if (unites == null) {
        erreurs['unites_vendables'] = MessagesRestaurant.conversionIllisible;
      } else if (unites <= 0) {
        erreurs['unites_vendables'] = MessagesRestaurant.conversionInvalide(
          existant.libelle,
        );
      }
      if (erreurs.isNotEmpty) {
        throw RefusRestaurant(erreurs.values.first, erreurs: erreurs);
      }

      await (update(
        attachedDatabase.platsLocal,
      )..where((p) => p.id.equals(platId))).write(
        PlatsLocalCompanion(
          articleId: Value(articleId),
          unitesVendables: Value(ecrireDixMilliemes(unites!)),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      await _enfilerPlat(platId, avant: existant);
    });

    return (await plat(platId))!;
  }

  /// `CartePlatMenuService::delierDuStock` : les DEUX colonnes partent
  /// ensemble (un taux de conversion sur un plat qui ne décrémente plus rien
  /// par ce chemin serait faux). Sans lien : rien n'est écrit.
  Future<Plat> delierDuStock({
    required String platId,
    required String? auteurId,
  }) async {
    _exigerAuteur(auteurId);

    await transaction(() async {
      final existant = await (select(
        attachedDatabase.platsLocal,
      )..where((p) => p.id.equals(platId))).getSingleOrNull();
      if (existant == null) {
        throw const RefusRestaurant(MessagesRestaurant.platIntrouvable);
      }
      if (existant.articleId == null) return;
      await (update(
        attachedDatabase.platsLocal,
      )..where((p) => p.id.equals(platId))).write(
        PlatsLocalCompanion(
          articleId: const Value(null),
          unitesVendables: const Value(null),
          modifieLe: Value(_maintenant()),
          modifiePar: Value(auteurId),
        ),
      );
      await _enfilerPlat(platId, avant: existant);
    });

    return (await plat(platId))!;
  }

  /* ================================================================== */
  /* La file d'envoi (lot F1, 15/10/2026)                                */
  /* ================================================================== */

  /// Son propre générateur d'UUID : celui de ce DAO peut être injecté.
  OperationsSyncDao get _file => OperationsSyncDao(attachedDatabase);

  static Map<String, Object?> _chargeMenu(MenusLocalData m) => chargeMenu(
    libelle: m.libelle,
    type: m.type,
    dateDebut: m.dateDebut,
    dateFin: m.dateFin,
  );

  /// Enfile la création ([avant] nul) ou les champs changés du menu [id],
  /// relu après écriture — dans la transaction de l'appelant.
  Future<void> _enfilerMenu(String id, {required MenusLocalData? avant}) async {
    final apres = await (select(
      attachedDatabase.menusLocal,
    )..where((m) => m.id.equals(id))).getSingle();
    await _file.enfiler(
      table: TableSynchronisee.menus,
      entiteId: id,
      type: avant == null
          ? TypeOperationSync.creation
          : TypeOperationSync.modification,
      payload: avant == null
          ? _chargeMenu(apres)
          : champsModifies(_chargeMenu(avant), _chargeMenu(apres)),
    );
  }

  /// Le document `recettes` (fiche + composition entière), ou `null` si la
  /// fiche n'existe pas. Composition triée par article : l'ordre de saisie
  /// n'est pas stocké, et une comparaison avant/après doit être stable.
  Future<Map<String, Object?>?> _chargeRecette(String id) async {
    final r = await (select(
      attachedDatabase.recettesLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    final lignes =
        await (select(attachedDatabase.ingredientsRecetteLocal)
              ..where((l) => l.recetteId.equals(id))
              ..orderBy([(l) => OrderingTerm.asc(l.articleId)]))
            .get();
    return chargeRecette(
      libelle: r.libelle,
      lignes: [
        for (final l in lignes)
          (articleId: l.articleId, milliemes: l.quantiteMilliemes),
      ],
    );
  }

  static Map<String, Object?> _chargePlat(PlatsLocalData p) => chargePlat(
    libelle: p.libelle,
    menuId: p.menuId,
    recetteId: p.recetteId,
    prixVenteFrancs: p.prixVente,
    prixProvisoire: p.prixProvisoire,
    prixCorrigeMain: p.prixCorrigeMain,
    articleId: p.articleId,
    unitesVendables: p.unitesVendables,
  );

  /// Les deux colonnes du lien, retirées : elles repartent en `null`
  /// EXPLICITE (`champsModifies` ne voit que les clés présentes après).
  static Map<String, Object?> _differences(
    PlatsLocalData avant,
    PlatsLocalData apres,
  ) {
    final d = champsModifies(_chargePlat(avant), _chargePlat(apres));
    if (avant.articleId != null && apres.articleId == null) {
      d['article_id'] = null;
      d['unites_vendables_par_unite_stock'] = null;
    }
    return d;
  }

  Future<void> _enfilerPlat(String id, {required PlatsLocalData? avant}) async {
    final apres = await (select(
      attachedDatabase.platsLocal,
    )..where((p) => p.id.equals(id))).getSingle();
    await _file.enfiler(
      table: TableSynchronisee.plats,
      entiteId: id,
      type: avant == null
          ? TypeOperationSync.creation
          : TypeOperationSync.modification,
      payload: avant == null ? _chargePlat(apres) : _differences(avant, apres),
    );
  }
}
