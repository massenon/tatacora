import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/stock_en_attente.dart';
import 'package:tatacora_flutter/features/stocks/presentation/widgets/table_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/providers_stocks.dart';

/// RG-05 (21/10/2026) : ce que les ventes du bar ENCORE EN FILE sortiront du
/// stock — dit à côté du stock, jamais soustrait ni écrit (le serveur sort le
/// stock à la réception ; un mouvement local serait compté deux fois).
void main() {
  group('la formule du serveur (stockConsommePour + arrondirQuantite)', () {
    test('un facteur lu en dix-millièmes, ou refusé', () {
      expect(facteurEnDixMilliemes('24.0000'), 240000);
      expect(facteurEnDixMilliemes('1'), 10000);
      expect(facteurEnDixMilliemes('0.5'), 5000);
      expect(facteurEnDixMilliemes(null), isNull);
      expect(facteurEnDixMilliemes('0.0000'), isNull);
      expect(facteurEnDixMilliemes('abc'), isNull);
    });

    test(
      '1/24 = 0,0417 -> 0,04 ; 24/24 -> 1,00 ; 5/24 -> 0,21 ; 3/2 -> 1,50',
      () {
        int sortie(int vendue, String facteur) => stockSortiEnCentiemes(
          quantiteVendue: vendue,
          facteur: facteurEnDixMilliemes(facteur)!,
        );
        expect(sortie(1, '24.0000'), 4);
        expect(sortie(24, '24.0000'), 100);
        expect(sortie(5, '24.0000'), 21); // 0,2083 -> 0,21
        expect(sortie(3, '2.0000'), 150);
        expect(sortie(1, '1.0000'), 100);
      },
    );

    test('les textes affichés', () {
      expect(TextesStockEnAttente.sortie(250), "−2,50 en attente d'envoi");
      expect(TextesStockEnAttente.sortie(4), "−0,04 en attente d'envoi");
    });
  });

  group('le fournisseur lit la file', () {
    late AppDatabase db;
    late ProviderContainer c;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await db.customStatement('SELECT 1');
      c = ProviderContainer(
        overrides: [baseLocaleProvider.overrideWithValue(db)],
      );
      for (final (id, article, facteur) in [
        ('b-flag', 'a-biere', '24.0000'),
        ('b-sans-facteur', 'a-jus', null),
        ('b-sans-lien', '', '1.0000'),
      ]) {
        await db.customStatement(
          'INSERT INTO cartes_boisson_local (id, article_id, libelle, categorie, '
          'prix_vente, unites_vendables) VALUES (?, ?, ?, ?, ?, ?)',
          [id, article, id, 'locale', 600, facteur],
        );
      }
    });

    tearDown(() async {
      c.dispose();
      await db.close();
    });

    var n = 0;
    Future<void> operation(String statut, List<Map<String, Object?>> lignes) =>
        db.customStatement(
          'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
          'entite_id, type, payload, horodatage_client, statut, cree_le) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, 0)',
          [
            'op-${n++}',
            'ventes',
            'v-$n',
            'creation',
            jsonEncode({'lignes': lignes}),
            '2026-10-21T08:00:00.000Z',
            statut,
          ],
        );

    Map<String, Object?> ligne(String boisson, int q, {String module = 'M5'}) =>
        {'module_source': module, 'code_article': boisson, 'quantite': q};

    test(
      'seules les ventes encore en file comptent, boissons seulement',
      () async {
        await operation('en_attente', [
          ligne('b-flag', 12),
          ligne('p-plat', 3, module: 'M4'),
        ]);
        await operation('bloque', [ligne('b-flag', 12)]);
        await operation('synchronise', [
          ligne('b-flag', 240),
        ]); // déjà chez le serveur
        await operation('rejete', [ligne('b-flag', 240)]); // n'y entrera jamais
        await operation('en_attente', [
          ligne('b-sans-facteur', 5),
          ligne('b-sans-lien', 5),
        ]);

        final att = await c.read(stockEnAttenteProvider.future);

        expect(att.pour('a-biere'), 100); // 24 / 24 = 1,00
        expect(att.pour('a-jus'), 0);
        expect(
          att.nonConvertibles,
          1,
          reason: 'facteur absent : dit, pas inventé',
        );
        expect(att.parArticle.keys, ['a-biere']);

        // Rien n'a été ÉCRIT : aucun mouvement de stock local.
        expect(await db.select(db.mouvementsStockLocal).get(), isEmpty);
      },
    );

    test('file vide : rien à dire', () async {
      final att = await c.read(stockEnAttenteProvider.future);
      expect(att.parArticle, isEmpty);
      expect(att.nonConvertibles, 0);
    });
  });

  testWidgets('la mention est sous le stock de l’article concerné seulement', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(2400, 1200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    LigneStock ligne(String id) => LigneStock(
      id: id,
      libelle: id,
      categorie: null,
      uniteMesure: 'u',
      seuilAlerte: '5.00',
      coutMoyenPondere: '0',
      stock: '10.00',
      valeurStock: '0',
      portee: 'tous',
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
      pointLibelle: null,
      prixAchat: null,
      deriveCmp: null,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TableStocks(
              lignes: [ligne('a-biere'), ligne('a-jus')],
              enAttente: const StockEnAttente(
                parArticle: {'a-biere': 250},
                nonConvertibles: 0,
              ),
              onFiche: (_) {},
              onMouvement: (_) {},
              onModifier: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('stocks-en-attente-a-biere')), findsOneWidget);
    expect(find.text("−2,50 en attente d'envoi"), findsOneWidget);
    expect(find.byKey(const Key('stocks-en-attente-a-jus')), findsNothing);
    // Le stock lui-même n'est pas soustrait.
    expect(find.text('10.00'), findsNWidgets(2));
  });
}
