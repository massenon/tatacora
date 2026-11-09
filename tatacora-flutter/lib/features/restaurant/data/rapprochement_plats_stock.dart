/// Le RAPPROCHEMENT des plats et du stock de la cuisine — le pendant exact de
/// `RapprochementPlatsStockService` du serveur (PO, 09/11/2026).
///
/// ## Le défaut
///
/// Après l'import des trois modèles, les 81 plats affichaient « Article de
/// stock » vide, « Stock vendable : non suivi » et « Lier au stock » ne
/// proposait rien d'utile : l'import m4 ne posait aucun lien, et m6 ne portait
/// aucun article de cuisine. Au bar, la boisson est reliée parce que
/// l'article est OBLIGATOIRE ; un plat n'a aucun lien obligatoire.
///
/// ## La doctrine (celle du bar)
///
/// Un plat vendu EN L'ÉTAT se relie à l'article de stock DE MÊME NOM, au point
/// « Cuisine » : suivi permanent, UNE unité vendable par unité de stock, solde
/// à ZÉRO tant qu'aucune entrée n'est saisie. Un plat décomposé en INGRÉDIENTS
/// garde sa fiche et n'est jamais relié ici. Aucun prix, aucune quantité,
/// aucun ingrédient n'est inventé.
///
/// Jamais : remplacer un lien existant ; écrire un prix ou un mouvement ;
/// rapprocher à un article du bar ou du magasin (seuls les articles du point
/// cuisine ou sans point sont candidats, et jamais un article déjà vendu par
/// une boisson ou un autre plat) ; créer un doublon. IDEMPOTENT.
///
/// Écrivains uniques respectés : le lien passe par `RestaurantDao.lierAuStock`,
/// l'article par `StocksApi.enregistrerArticle`, le point par
/// `StocksApi.creerPoint` — jamais une insertion directe.
///
/// @see RG-05 Sortie de stock automatique
library;

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../stocks/data/stocks_api.dart';
import '../../stocks/domain/entities/etat_stock.dart' show SuiviArticle;
import '../../stocks/domain/entities/mouvement_stock.dart' show SaisieArticle;
import '../../stocks/data/articles_de_carte.dart';
import 'restaurant_dao.dart';

/// Les phrases du bilan — celles du serveur (`lang/fr/imports.php`,
/// `rapprochement`), au mot.
abstract final class TextesRapprochement {
  static const String bouton = 'Rapprocher les plats du stock';
  static const String boutonAide =
      // ignore: prefer_single_quotes
      "Relie chaque plat sans lien à l'article de stock de même nom au point Cuisine (créé s'il manque). Aucun prix ni aucune quantité n'est écrit.";
  static String fait(String bilan) => 'Rapprochement terminé. $bilan';
  static const String droitManquant =
      "Votre rôle n'autorise pas l'écriture sur le restaurant et sur le stock.";
}

/// Ce que le rapprochement a fait.
final class BilanRapprochement {
  const BilanRapprochement({
    this.rapproches = 0,
    this.articlesCrees = 0,
    this.dejaLies = 0,
    this.avecFiche = 0,
    this.sansArticle = 0,
    this.pointCree = false,
    this.examines = 0,
  });

  final int rapproches;
  final int articlesCrees;
  final int dejaLies;
  final int avecFiche;
  final int sansArticle;
  final bool pointCree;
  final int examines;

  /// La phrase du bilan, partagée par l'import, le bouton et les tests.
  String get phrase {
    final morceaux = <String>[
      switch (rapproches) {
        0 => 'Aucun plat rapproché du stock.',
        1 => '1 plat rapproché du stock.',
        _ => '$rapproches plats rapprochés du stock.',
      },
    ];
    if (articlesCrees > 0) {
      morceaux.add(
        articlesCrees == 1
            ? '1 article de stock créé au point Cuisine.'
            : '$articlesCrees articles de stock créés au point Cuisine.',
      );
    }
    if (dejaLies > 0) {
      morceaux.add('$dejaLies déjà relié(s), laissé(s) tel(s) quel(s).');
    }
    if (avecFiche > 0) {
      morceaux.add(
        '$avecFiche plat(s) décomposé(s) en ingrédients, laissé(s) à leur '
        'fiche technique.',
      );
    }
    if (sansArticle > 0) {
      const suite =
          'sans article de même nom : importez le modèle Stocks (point '
          'Cuisine) ou utilisez « Rapprocher les plats du stock ».';
      morceaux.add(
        sansArticle == 1 ? '1 plat $suite' : '$sansArticle plats $suite',
      );
    }
    return morceaux.join(' ');
  }
}

final class RapprochementPlatsStock {
  RapprochementPlatsStock(
    this._base, {
    required this._restaurant,
    required this._stocks,
    required this._articles,
  });

  final AppDatabase _base;
  final RestaurantDao _restaurant;
  final StocksApi _stocks;
  final ArticlesDeCarte _articles;

  static const _uuid = Uuid();

  /// Le libellé du point créé quand aucun point cuisine n'existe.
  static const String libellePoint = 'Cuisine';

  /// Une assiette vendue = une unité de stock : la seule valeur qui n'invente
  /// rien.
  static const String conversion = '1';

  /// Relie les plats [platIds] (tous quand `null`). [creerLesArticles] :
  /// `true` pour le rattrapage, `false` pour l'import m4 (ne relie qu'à un
  /// article déjà présent).
  ///
  /// @throws StateError le poste n'a pas pu écrire (droit ou refus du module)
  Future<BilanRapprochement> rapprocher({
    Iterable<String>? platIds,
    required String? auteurId,
    bool creerLesArticles = true,
    Map<String, ParametresArticle> parametres = const {},
  }) => _base.transaction(() async {
    final voulus = platIds?.toSet();
    final plats =
        [
          for (final p in await _base.select(_base.platsLocal).get())
            if (voulus == null || voulus.contains(p.id)) p,
        ]..sort(
          (a, b) => cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle)),
        );

    var rapproches = 0;
    var crees = 0;
    var dejaLies = 0;
    var avecFiche = 0;
    var sansArticle = 0;
    var pointCree = false;

    var pointId = await _pointCuisine();
    final candidats = await _candidats(pointId, [
      for (final p in parametres.values) ?p.pointId,
    ]);
    final pris = await _articlesDejaVendus();
    final fichesComposees = {
      for (final i in await _base.select(_base.ingredientsRecetteLocal).get())
        i.recetteId,
    };

    for (final plat in plats) {
      if (plat.articleId != null && plat.unitesVendables != null) {
        dejaLies++;
        continue;
      }
      if (fichesComposees.contains(plat.recetteId)) {
        avecFiche++;
        continue;
      }

      final cle = cleDeComparaison(plat.libelle);
      var articleId = candidats[cle];
      if (articleId == null || pris.contains(articleId)) {
        if (!creerLesArticles) {
          sansArticle++;
          continue;
        }
        if (pointId == null) {
          pointId = await _articles.pointCuisineOuCree();
          pointCree = true;
        }
        final voulu = parametres[plat.id];
        final id = _uuid.v4();
        final r = await _stocks.enregistrerArticle(
          SaisieArticle(
            id: id,
            libelle: plat.libelle,
            categorie: 'Denrées',
            uniteMesure: 'unité',
            seuilAlerte: voulu?.seuil?.trim().isNotEmpty ?? false
                ? voulu!.seuil!.trim()
                : '0',
            suivi: SuiviArticle.permanent,
            pointStockageId: voulu?.pointId ?? pointId,
          ),
        );
        if (r is! ArticleEnregistre) {
          throw StateError(
            r is ArticleRefuse ? r.motif : TextesRapprochement.droitManquant,
          );
        }
        articleId = id;
        candidats[cle] = id;
        crees++;
      }

      // Un article repris : seuls ses champs VIDES sont complétés.
      final voulu = parametres[plat.id];
      if (voulu != null) {
        final ligneArticle = await (_base.select(
          _base.articlesLocal,
        )..where((a) => a.id.equals(articleId!))).getSingle();
        await _articles.completer(ligneArticle, voulu);
      }

      await _restaurant.lierAuStock(
        platId: plat.id,
        articleId: articleId,
        conditionnement: conversion,
        auteurId: auteurId,
      );
      pris.add(articleId);
      rapproches++;
    }

    return BilanRapprochement(
      rapproches: rapproches,
      articlesCrees: crees,
      dejaLies: dejaLies,
      avecFiche: avecFiche,
      sansArticle: sansArticle,
      pointCree: pointCree,
      examines: plats.length,
    );
  });

  /// Le point cuisine : le premier de type `cuisine`, par libellé puis
  /// identifiant (le choix de `choisirPointCuisine`).
  Future<String?> _pointCuisine() async {
    final points =
        [
          for (final p in await _base.select(_base.pointsStockageLocal).get())
            if (p.type == 'cuisine') p,
        ]..sort((a, b) {
          final c = cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle));
          return c != 0 ? c : a.id.compareTo(b.id);
        });
    return points.isEmpty ? null : points.first.id;
  }

  /// Les articles qu'un plat peut reprendre, par nom normalisé : permanents,
  /// actifs, au point cuisine ou sans point. Le point cuisine l'emporte.
  Future<Map<String, String>> _candidats(
    String? pointId,
    List<String> autresPoints,
  ) async {
    final points = {?pointId, ...autresPoints};
    final articles =
        [
          for (final a in await _base.select(_base.articlesLocal).get())
            if (a.suivi == 'permanent' &&
                a.actif != false &&
                (a.pointStockageId == null ||
                    points.contains(a.pointStockageId)))
              a,
        ]..sort(
          (a, b) => cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle)),
        );

    final parNom = <String, ArticlesLocalData>{};
    for (final a in articles) {
      final cle = cleDeComparaison(a.libelle);
      final actuel = parNom[cle];
      if (actuel == null ||
          (pointId != null &&
              a.pointStockageId == pointId &&
              actuel.pointStockageId != pointId)) {
        parNom[cle] = a;
      }
    }
    return {for (final e in parNom.entries) e.key: e.value.id};
  }

  /// Les articles déjà vendus par une boisson ou un plat.
  Future<Set<String>> _articlesDejaVendus() async => {
    for (final b in await _base.select(_base.cartesBoissonLocal).get())
      if (b.articleId.isNotEmpty) b.articleId,
    for (final p in await _base.select(_base.platsLocal).get())
      if (p.articleId != null) p.articleId!,
  };
}
