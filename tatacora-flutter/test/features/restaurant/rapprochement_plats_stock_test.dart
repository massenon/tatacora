import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/presentation/providers_stocks.dart'
    show stocksDaoProvider;
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/modale_lien_stock_plat.dart'
    show TextesLienPlat;
import 'package:tatacora_flutter/features/transverse/data/importeurs_locaux.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_import_export.dart';

import '../transverse/support/outils_import.dart';

/// « Lier au stock » vide et « Stock vendable : non suivi » sur les 81 plats
/// importés (PO, 09/11/2026) — le pendant poste de
/// `RapprochementPlatsStockTest` (PHP).
///
/// CAUSE : l'import des trois modèles ne créait aucun article de cuisine (m6
/// ne portait que les neuf boissons) et m4 ne reliait aucun plat. Au bar,
/// l'article est obligatoire ; pour un plat, aucun lien n'est obligatoire.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProviderContainer conteneur;
  late MoteurImportLocal moteur;

  setUp(() async {
    db = await baseImport();
    conteneur = conteneurImport(db);
    moteur = conteneur.read(moteurImportProvider);
  });
  tearDown(() async {
    conteneur.dispose();
    await db.close();
  });

  List<int> fichier(String cle) =>
      File('../docs/data/modele_import_$cle.xlsx').readAsBytesSync();

  ImporteurLocal importeur(String cle) =>
      conteneur.read(importeursLocauxProvider).singleWhere((i) => i.cle == cle);

  Future<ResultatImport> importer(String cle) =>
      moteur.appliquer(importeur(cle), fichier(cle));

  Future<int> compter(String clause) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $clause').getSingle())
          .read<int>('n');

  /// L'état du PO : plats importés SANS lien, ni article de cuisine, ni point.
  Future<void> etatDuPo() async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DELETE FROM mouvements_stock_local');
    await db.customStatement('DELETE FROM ingredients_recette_local');
    await db.customStatement('DELETE FROM articles_local');
    await db.customStatement('DELETE FROM points_stockage_local');
    final r = await importer('m4-restaurant');
    if (r is ImportNonConforme) {
      fail(r.rapport.erreurs.take(3).map((e) => e.message).join('|'));
    }
    expect(r, isA<ImportFait>());
    await db.customStatement(
      'UPDATE plats_local SET article_id = NULL, unites_vendables = NULL',
    );
    await db.customStatement('DELETE FROM articles_local');
    await db.customStatement('DELETE FROM points_stockage_local');
    expect(await compter('plats_local WHERE article_id IS NOT NULL'), 0);
    expect(await compter('articles_local'), 0);
  }

  test('après m6 puis m4, chaque plat est relié à l’article de cuisine de '
      'même nom, à 1 par unité, sans prix ni mouvement', () async {
    expect(await importer('m6-stocks'), isA<ImportFait>());
    final issue = await importer('m4-restaurant');

    expect((issue as ImportFait).bilan, '81 plats rapprochés du stock.');
    expect(await compter('plats_local WHERE article_id IS NOT NULL'), 81);
    expect(await compter('mouvements_stock_local'), 0);
    final ligne = await db
        .customSelect(
          'SELECT a.libelle AS l, p.unites_vendables AS u, a.suivi AS s, '
          'pt.type AS t FROM plats_local p '
          'JOIN articles_local a ON a.id = p.article_id '
          'JOIN points_stockage_local pt ON pt.id = a.point_stockage_id '
          "WHERE p.libelle = 'Akassa'",
        )
        .getSingle();
    expect(ligne.read<String>('l'), 'Akassa');
    expect(ligne.read<String>('s'), 'permanent');
    expect(ligne.read<String>('t'), 'cuisine');
    expect(double.parse(ligne.read<String>('u')), 1.0);
  });

  test(
    'sans le modèle Stocks, l’import m4 crée l’article de cuisine et relie le '
    'plat',
    () async {
      final issue = await importer('m4-restaurant');

      expect(
        (issue as ImportFait).bilan,
        startsWith('81 plats rapprochés du stock.'),
      );
      expect(issue.bilan, contains('81 articles de stock créés au point'));
      expect(await compter('plats_local WHERE article_id IS NOT NULL'), 81);
      expect(
        await compter('articles_local WHERE prix_achat_reference IS NOT NULL'),
        0,
        reason: 'aucune valeur d’achat inventée',
      );
      expect(await compter('mouvements_stock_local'), 0);
    },
  );

  /// Un fichier d'essai : l'en-tête, puis les lignes (point-virgule).
  List<int> csv(String entete, List<String> lignes) =>
      utf8.encode('${[entete, ...lignes].join('\r\n')}\r\n');

  Future<String?> valeurDe(String libelle) async =>
      (await db
              .customSelect(
                'SELECT prix_achat_reference AS v FROM articles_local '
                'WHERE libelle = ?',
                variables: [Variable.withString(libelle)],
              )
              .getSingle())
          .data['v']
          ?.toString();

  test('m6 : « Point Stock », « Seuil » et « Valeur d’achat » sont lus, vide '
      '= « — », jamais une quantité', () async {
    await db.customStatement(
      "INSERT INTO points_stockage_local (id, libelle, type) "
      "VALUES ('p-mag', 'Magasin général', 'magasin')",
    );
    final issue = await moteur.appliquer(
      importeur('m6-stocks'),
      csv(
        'Désignation de l’article;Catégorie;Unité de mesure;Seuil;Point Stock;'
        'Valeur d’achat',
        ['Riz;Denrées;kg;5;Magasin général;650', 'Sel;Denrées;kg;;;'],
      ),
    );

    if (issue is ImportNonConforme) {
      fail(
        issue.rapport.erreurs
            .map((e) => '${e.colonne}: ${e.message}')
            .join(' | '),
      );
    }
    expect(issue, isA<ImportFait>(), reason: '$issue');
    expect(await valeurDe('Riz'), '6500000');
    expect(await valeurDe('Sel'), isNull);
    expect(
      await compter(
        "articles_local WHERE libelle = 'Riz' AND point_stockage_id = 'p-mag'",
      ),
      1,
    );
    expect(await compter('mouvements_stock_local'), 0);
  });

  test(
    'm6 : un ancien fichier sans les nouvelles colonnes reste valide',
    () async {
      final issue = await moteur.appliquer(
        importeur('m6-stocks'),
        csv('nom;categorie;unite_mesure;seuil_alerte', ['Farine;Denrées;kg;2']),
      );
      expect(issue, isA<ImportFait>(), reason: '$issue');
      expect(await valeurDe('Farine'), isNull);
    },
  );

  test('m5 sans article : reprend l’article de même nom ou le crée, complète '
      'sans jamais écraser', () async {
    await db.customStatement(
      "INSERT INTO points_stockage_local (id, libelle, type) "
      "VALUES ('p-bar', 'Bar', 'bar')",
    );
    await db.customStatement(
      "INSERT INTO articles_local (id, libelle, categorie, unite_mesure, "
      "seuil_alerte, suivi, prix_achat_reference) "
      "VALUES ('a-pils', 'BIÈRE Pils', 'Boissons', 'unité', 7, 'permanent', 5000000)",
    );

    final issue = await moteur.appliquer(
      importeur('m5-bar'),
      csv(
        'Nom de la boisson;Catégorie;Prix de vente (FCFA);Point Stock;Seuil;'
        'Valeur d’achat',
        [
          'Bière Pils;locale;1000;Bar;99;900',
          'Jus de gingembre;maison;500;;3;150',
        ],
      ),
    );

    expect(issue, isA<ImportFait>(), reason: '$issue');
    expect(
      await compter(
        "articles_local WHERE libelle LIKE '%ils' OR libelle LIKE 'Jus de g%'",
      ),
      2,
      reason: 'la bière reprend l’article existant : aucun doublon',
    );
    expect(await valeurDe('BIÈRE Pils'), '5000000', reason: 'jamais écrasée');
    expect(
      await compter("articles_local WHERE id = 'a-pils' AND seuil_alerte = 7"),
      1,
      reason: 'le seuil posé n’est jamais écrasé',
    );
    expect(
      await compter(
        "articles_local WHERE id = 'a-pils' AND point_stockage_id = 'p-bar'",
      ),
      1,
      reason: 'le point VIDE est complété',
    );
    expect(await valeurDe('Jus de gingembre'), '1500000');
    expect(
      await compter(
        "articles_local WHERE libelle = 'Jus de gingembre' AND point_stockage_id = 'p-bar' AND seuil_alerte = 3 AND categorie = 'Boissons'",
      ),
      1,
    );
    expect(
      await compter(
        'cartes_boisson_local c JOIN articles_local a ON a.id = c.article_id '
        "WHERE c.libelle = 'Jus de gingembre' AND a.libelle = 'Jus de gingembre'",
      ),
      1,
    );
  });

  test('un point déjà posé n’est jamais remplacé par un import', () async {
    await db.customStatement(
      "INSERT INTO points_stockage_local (id, libelle, type) "
      "VALUES ('p-mag', 'Magasin général', 'magasin'), ('p-bar', 'Bar', 'bar')",
    );
    await db.customStatement(
      "INSERT INTO articles_local (id, libelle, categorie, unite_mesure, "
      "seuil_alerte, suivi, point_stockage_id) "
      "VALUES ('a-lim', 'Limonade', 'Boissons', 'unité', 0, 'permanent', 'p-mag')",
    );

    final issue = await moteur.appliquer(
      importeur('m5-bar'),
      csv('Nom de la boisson;Catégorie;Prix de vente (FCFA);Point Stock', [
        'Limonade;locale;500;Bar',
      ]),
    );

    expect(issue, isA<ImportFait>(), reason: '$issue');
    expect(
      await compter(
        "articles_local WHERE id = 'a-lim' AND point_stockage_id = 'p-mag'",
      ),
      1,
    );
  });

  test('m6 seul : 81 articles de cuisine au point Cuisine, aucun plat, aucune '
      'valeur ni quantité', () async {
    await importer('m6-stocks');
    expect(
      await compter(
        'articles_local WHERE point_stockage_id IN '
        "(SELECT id FROM points_stockage_local WHERE type = 'cuisine')",
      ),
      81,
    );
    expect(await compter('plats_local'), 0);
    expect(await compter('mouvements_stock_local'), 0);
    expect(
      await compter('articles_local WHERE prix_achat_reference IS NOT NULL'),
      0,
    );
  });

  test(
    'm4 avec les colonnes de stock : article au bon point, seuil et valeur',
    () async {
      final issue = await moteur.appliquer(
        importeur('m4-restaurant'),
        csv('Nom du plat;Catégorie;Prix de vente (FCFA);Seuil;Valeur d’achat', [
          'Brochette;plats;1500;4;700',
          'Igname;plats;;;',
        ]),
      );

      expect(issue, isA<ImportFait>(), reason: '$issue');
      expect(await valeurDe('Brochette'), '7000000');
      expect(await valeurDe('Igname'), isNull);
      expect(
        await compter(
          'plats_local p JOIN articles_local a ON a.id = p.article_id '
          'JOIN points_stockage_local t ON t.id = a.point_stockage_id '
          "WHERE p.libelle = 'Brochette' AND a.seuil_alerte = 4 AND t.type = 'cuisine'",
        ),
        1,
      );
    },
  );

  test('la « Valeur d’achat » importée s’affiche dans Stocks, le CMP reste '
      'calculé des entrées', () async {
    final issue = await moteur.appliquer(
      importeur('m6-stocks'),
      csv('nom;categorie;unite_mesure;valeur_achat', ['Huile;Denrées;L;1200']),
    );
    if (issue is ImportNonConforme) {
      fail(issue.rapport.erreurs.map((e) => e.message).join(' | '));
    }
    final etat = await conteneur.read(stocksDaoProvider).etat();
    final huile = etat.lignes.singleWhere((l) => l.libelle == 'Huile');

    expect(huile.prixAchatAffiche, '1200.0000');
    expect(huile.prixAchat, isNull, reason: 'aucune entrée valorisée');
    expect(huile.cmpInconnu, isTrue, reason: 'le CMP reste « — »');
    expect(huile.deriveCmp, isNull);
  });

  test('le point « Cuisine » est créé par l’import m6 quand il manque, jamais '
      'en double', () async {
    await db.customStatement('DELETE FROM points_stockage_local');
    await importer('m6-stocks');
    expect(await compter("points_stockage_local WHERE type = 'cuisine'"), 1);
    // Une seconde importation (nouveaux articles) ne recrée rien.
    await importer('m6-stocks');
    expect(await compter("points_stockage_local WHERE type = 'cuisine'"), 1);
  });

  test('le rattrapage relie une base déjà importée, sans rien écraser, avec '
      'bilan, et il est idempotent', () async {
    await etatDuPo();
    final rattrapage = conteneur.read(rapprochementPlatsStockProvider);

    // Un plat déjà relié à la main (conditionnement 4), un plat à fiche composée.
    final dao = conteneur.read(restaurantDaoProvider);
    await db.customStatement(
      "INSERT INTO articles_local (id, libelle, categorie, unite_mesure, "
      "seuil_alerte, suivi) VALUES ('a-farine', 'Farine spéciale', 'Denrées', "
      "'kg', 0, 'permanent')",
    );
    final aileron = (await (db.select(
      db.platsLocal,
    )..where((p) => p.libelle.equals('Aileron'))).getSingle());
    await dao.lierAuStock(
      platId: aileron.id,
      articleId: 'a-farine',
      conditionnement: '4',
      auteurId: auteurImport,
    );
    final akassa = (await (db.select(
      db.platsLocal,
    )..where((p) => p.libelle.equals('Akassa'))).getSingle());
    await db.customStatement(
      "INSERT INTO ingredients_recette_local (recette_id, article_id, "
      "quantite_milliemes) VALUES ('${akassa.recetteId}', 'a-farine', 500)",
    );

    final bilan = await rattrapage.rapprocher(auteurId: auteurImport);

    expect(bilan.rapproches, 79);
    expect(bilan.articlesCrees, 79);
    expect(bilan.dejaLies, 1);
    expect(bilan.avecFiche, 1);
    expect(bilan.pointCree, isTrue);
    final apres = await (db.select(
      db.platsLocal,
    )..where((p) => p.id.equals(aileron.id))).getSingle();
    expect(
      apres.articleId,
      'a-farine',
      reason: 'un lien posé n’est jamais remplacé',
    );
    expect(double.parse(apres.unitesVendables!), 4.0);
    expect(
      (await (db.select(
        db.platsLocal,
      )..where((p) => p.id.equals(akassa.id))).getSingle()).articleId,
      isNull,
      reason: 'un plat décomposé en ingrédients garde sa fiche',
    );
    expect(await compter("points_stockage_local WHERE type = 'cuisine'"), 1);
    expect(await compter('mouvements_stock_local'), 0);

    final second = await rattrapage.rapprocher(auteurId: auteurImport);
    expect(second.rapproches, 0);
    expect(second.articlesCrees, 0);
    expect(await compter('articles_local'), 1 + 79);
  });

  test('le rattrapage reprend l’article de même nom (casse et accents '
      'ignorés) au lieu d’en créer un', () async {
    await importer('m6-stocks');
    await db.customStatement("DELETE FROM plats_local");
    await importer('m4-restaurant');
    await db.customStatement(
      'UPDATE plats_local SET article_id = NULL, unites_vendables = NULL',
    );
    final avant = await compter('articles_local');

    final bilan = await conteneur
        .read(rapprochementPlatsStockProvider)
        .rapprocher(auteurId: auteurImport);

    expect(bilan.rapproches, 81);
    expect(bilan.articlesCrees, 0);
    expect(await compter('articles_local'), avant);
  });

  test('« Lier au stock » propose les articles de la cuisine, et son état '
      'vide dit comment en avoir', () async {
    await importer('m6-stocks');
    final choix = await conteneur.read(restaurantDaoProvider).articlesLiables();
    expect(choix.map((a) => a.libelle), containsAll(['Aileron', 'Akassa']));
    expect(choix.length, greaterThanOrEqualTo(81));

    expect(
      TextesLienPlat.aucunArticleCuisine,
      'Aucun article de stock en cuisine : importez le modèle Stocks (point '
      "Cuisine) ou créez l'article dans Stocks.",
    );
  });

  test('le provider du bouton rend la phrase du bilan', () async {
    await etatDuPo();
    final phrase = await conteneur.read(rapprocherLesPlatsProvider)();
    expect(
      phrase,
      startsWith('Rapprochement terminé. 81 plats rapprochés du stock.'),
    );
    expect(phrase, contains('81 articles de stock créés au point Cuisine.'));
  });
}
