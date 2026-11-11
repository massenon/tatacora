/// L'ARTICLE DE STOCK d'une ligne de carte importée (m4 restaurant, m5 bar) —
/// le pendant poste de `ImportReferentielsService::articleDeLaBoisson` et de
/// `ReferentielArticleService::completer` du serveur (PO, 09/11/2026).
///
/// Colonnes facultatives des modèles : « Point Stock », « Seuil », « Valeur
/// d'achat ». Doctrine : l'article de MÊME NOM (sans casse ni accents) est
/// repris, créé à défaut ; un article repris n'est que COMPLÉTÉ — point s'il est
/// vide, valeur d'achat de référence si elle est vide — JAMAIS écrasé (ni point,
/// ni valeur d'achat, ni seuil). Aucune quantité, aucun mouvement.
///
/// Écrivains uniques respectés : `StocksApi.enregistrerArticle` (création et
/// complément du point, enfilé), `StocksApi.creerPoint`,
/// `StocksApi.poserValeurAchatReference`.
library;

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../domain/calcul_stock.dart' show ecrireCentiemes, lireCout;
import '../domain/entities/etat_stock.dart' show SuiviArticle, TypePoint;
import '../domain/entities/mouvement_stock.dart' show SaisieArticle;
import 'stocks_api.dart';

/// Ce qu'une ligne de carte demande de son article — toutes facultatives.
typedef ParametresArticle = ({String? pointId, String? seuil, String? valeur});

/// Valeur convertie d'un point « Cuisine » qui n'existe pas encore — créé à
/// l'écriture (jamais au contrôle), comme `POINT_CUISINE_A_CREER` du serveur.
const String pointCuisineACreer = '@cuisine-a-creer';

final class ArticlesDeCarte {
  ArticlesDeCarte(this._base, this._stocks);

  final AppDatabase _base;
  final StocksApi _stocks;

  static const _uuid = Uuid();

  /// Le libellé du point créé quand aucun point cuisine n'existe.
  static const String libellePointCuisine = 'Cuisine';

  /// Le point cuisine existant (type `cuisine`, par libellé puis identifiant).
  Future<String?> pointCuisine() async => _premierPoint('cuisine');

  Future<String?> pointBar() async => _premierPoint('bar');

  Future<String?> _premierPoint(String type) async {
    final points =
        [
          for (final p in await _base.select(_base.pointsStockageLocal).get())
            if (p.type == type) p,
        ]..sort((a, b) {
          final c = cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle));
          return c != 0 ? c : a.id.compareTo(b.id);
        });
    return points.isEmpty ? null : points.first.id;
  }

  /// Le point cuisine, créé par `StocksApi.creerPoint` s'il n'existe pas.
  ///
  /// @throws StateError le poste n'a pas pu l'écrire
  Future<String> pointCuisineOuCree() async {
    final existant = await pointCuisine();
    if (existant != null) return existant;
    final r = await _stocks.creerPoint(
      libelle: libellePointCuisine,
      type: TypePoint.cuisine,
    );
    return switch (r) {
      PointEnregistre(:final point) => point.id,
      PointRefuse(:final motif) => throw StateError(motif),
    };
  }

  /// La valeur d'une colonne « Point Stock » : l'identifiant du point, ou
  /// `null` ; le point « Cuisine » encore absent est créé ici.
  Future<String?> resoudrePoint(String? valeur) async =>
      valeur == pointCuisineACreer ? pointCuisineOuCree() : valeur;

  /// Les références du champ « Point Stock » pour le contrôle : libellé exact →
  /// identifiant, et « Cuisine » accepté même absent (créé à l'import).
  Future<Map<String, String>> referencesDesPoints() async {
    final points = {
      for (final p in await _base.select(_base.pointsStockageLocal).get())
        p.libelle: p.id,
    };
    if (!points.containsKey(libellePointCuisine)) {
      points[libellePointCuisine] = await pointCuisine() ?? pointCuisineACreer;
    }
    return points;
  }

  /// L'article actif en suivi permanent de même nom (premier par libellé).
  Future<ArticlesLocalData?> trouverParNom(String libelle) async {
    final cle = cleDeComparaison(libelle);
    final tous =
        [
          for (final a in await _base.select(_base.articlesLocal).get())
            if (a.suivi == 'permanent' && a.actif != false) a,
        ]..sort(
          (a, b) => cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle)),
        );
    return tous.where((a) => cleDeComparaison(a.libelle) == cle).firstOrNull;
  }

  /// L'article de [libelle] : repris, ou créé ([categorie], unité « unité »,
  /// suivi permanent, [pointParDefaut] quand la ligne n'en nomme aucun).
  /// Complète ensuite, sans jamais écraser.
  ///
  /// @throws StateError la création est refusée
  Future<String> trouverOuCreer({
    required String libelle,
    required String categorie,
    required ParametresArticle voulu,
    String? pointParDefaut,
  }) async {
    final existant = await trouverParNom(libelle);
    if (existant != null) {
      await completer(existant, voulu);
      return existant.id;
    }
    final id = _uuid.v4();
    final r = await _stocks.enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: categorie,
        uniteMesure: 'unité',
        seuilAlerte: _seuil(voulu.seuil),
        suivi: SuiviArticle.permanent,
        pointStockageId: voulu.pointId ?? pointParDefaut,
      ),
    );
    if (r is! ArticleEnregistre) {
      throw StateError(r is ArticleRefuse ? r.motif : 'Article non écrit.');
    }
    await _poserValeur(id, voulu.valeur);
    return id;
  }

  /// Complète un article REPRIS : point s'il est vide, valeur d'achat de
  /// référence si elle est vide. Le seuil n'est jamais touché.
  Future<void> completer(
    ArticlesLocalData article,
    ParametresArticle voulu,
  ) async {
    final pointId = voulu.pointId;
    if (pointId != null && article.pointStockageId == null) {
      final r = await _stocks.enregistrerArticle(
        SaisieArticle(
          id: article.id,
          libelle: article.libelle,
          categorie: article.categorie.isEmpty ? null : article.categorie,
          uniteMesure: article.uniteMesure,
          seuilAlerte: ecrireCentiemes((article.seuilAlerte * 100).round()),
          suivi:
              SuiviArticle.depuisCode(article.suivi) ?? SuiviArticle.permanent,
          pointStockageId: pointId,
        ),
        modification: true,
      );
      if (r is! ArticleEnregistre) {
        throw StateError(r is ArticleRefuse ? r.motif : 'Article non écrit.');
      }
    }
    await _poserValeur(article.id, voulu.valeur);
  }

  Future<void> _poserValeur(String articleId, String? valeur) async {
    final lu = valeur == null || valeur.trim().isEmpty
        ? null
        : lireCout(valeur.trim());
    if (lu != null) await _stocks.poserValeurAchatReference(articleId, lu);
  }

  /// Le seuil d'une ligne : vide ou illisible = « 0 » (jamais inventé).
  static String _seuil(String? brut) =>
      brut == null || brut.trim().isEmpty ? '0' : brut.trim();
}
