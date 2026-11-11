import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/bar/presentation/ecran_carte_bar.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// 26/10/2026 — le PO : « je n'arrive pas à ENREGISTRER une boisson et à la
/// LIER AU STOCK en local ».
///
/// Deux causes, une par couche :
///
///  - la modale « Nouvelle boisson » n'offrait AUCUN sélecteur d'article : la
///    boisson naissait sans lien, que le serveur rejetait à l'envoi
///    (`article_id` requis) ;
///  - `BoissonsApi.lierAuStock` refusait TOUJOURS (`lienSansColonne`) alors que
///    `cartes_boisson_local.unites_vendables` existe depuis la v30, et la modale
///    « Lier au stock » ne rendait qu'un message.
///
/// Chaque cas passe par le chemin de l'écran (modale -> fournisseur ->
/// `BoissonsApi` -> `CatalogueDao`) et RELIT la base et la file d'envoi : un
/// test qui ne lirait que l'état de la modale ne protégerait rien (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late BoissonsApi api;
  late OperationsSyncDao file;

  Future<void> semerArticle(
    String id,
    String libelle, {
    String unite = 'casier',
    String suivi = 'permanent',
    bool actif = true,
  }) => db
      .into(db.articlesLocal)
      .insert(
        ArticlesLocalCompanion.insert(
          id: id,
          libelle: libelle,
          categorie: 'Boissons',
          uniteMesure: unite,
          seuilAlerte: 2,
          suivi: Value(suivi),
          actif: Value(actif),
        ),
      );

  setUp(() async {
    db = AppDatabase.enMemoire();
    api = BoissonsApi(CatalogueDao(db));
    file = OperationsSyncDao(db);
    await semerArticle('art-casier', 'Casier Béninoise', unite: 'casier');
    await semerArticle('art-fut', 'Fût Flag', unite: 'fût');
  });

  tearDown(() => db.close());

  Future<List<OperationSync>> operations() async => [
    for (final o in await file.operations())
      if (o.table == TableSynchronisee.cartesBoisson) o,
  ];

  Future<CartesBoissonLocalData> ligne(String libelle) => (db.select(
    db.cartesBoissonLocal,
  )..where((b) => b.libelle.equals(libelle))).getSingle();

  Future<Boisson> creerSansLien() async {
    final r = await api.enregistrer(
      const SaisieBoisson(
        libelle: 'Béninoise 33 cl',
        categorie: CategorieBoisson.locale,
        prixVente: '500',
      ),
    );
    return (r as BarRecu<Boisson>).donnees;
  }

  group('BoissonsApi — le chemin de l’écran', () {
    test('« Nouvelle boisson » écrit l’article ET le facteur, et les met en '
        'file', () async {
      final r = await api.enregistrer(
        const SaisieBoisson(
          libelle: 'Béninoise 33 cl',
          categorie: CategorieBoisson.locale,
          prixVente: '500',
          articleId: 'art-casier',
          unitesVendablesParUniteStock: '24',
        ),
      );
      expect(
        r,
        isA<BarRecu<Boisson>>(),
        reason: r is BarRefuse<Boisson> ? '${r.motif} ${r.erreurs}' : null,
      );

      final l = await ligne('Béninoise 33 cl');
      expect([l.articleId, l.unitesVendables], ['art-casier', '24']);

      // Relue par une instance NEUVE : c'est dans Drift, pas dans un champ.
      final relue = await BoissonsApi(CatalogueDao(db)).boisson(l.id);
      final b = (relue as BarRecu<Boisson>).donnees;
      expect(
        [b.articleId, b.unitesVendablesParUniteStock],
        ['art-casier', '24'],
      );

      final ops = await operations();
      expect(ops.single.type, TypeOperationSync.creation);
      final charge = jsonDecode(ops.single.payload) as Map<String, Object?>;
      expect(charge['article_id'], 'art-casier');
      expect(charge['unites_vendables_par_unite_stock'], '24');
    });

    test(
      'l’API admet un article SANS conditionnement (import), comme le '
      'service du serveur : rien n’est inventé, la colonne reste vide',
      () async {
        final r = await api.enregistrer(
          const SaisieBoisson(
            libelle: 'Béninoise 33 cl',
            categorie: CategorieBoisson.locale,
            prixVente: '500',
            articleId: 'art-casier',
          ),
        );
        expect(r, isA<BarRecu<Boisson>>());
        final l = await ligne('Béninoise 33 cl');
        expect([l.articleId, l.unitesVendables], ['art-casier', null]);
        final charge =
            jsonDecode((await operations()).single.payload)
                as Map<String, Object?>;
        expect(charge.containsKey('unites_vendables_par_unite_stock'), isFalse);
      },
    );

    test('un article absent de ce poste est refusé', () async {
      final r = await api.enregistrer(
        const SaisieBoisson(
          libelle: 'Béninoise 33 cl',
          categorie: CategorieBoisson.locale,
          prixVente: '500',
          articleId: 'art-inconnu',
          unitesVendablesParUniteStock: '24',
        ),
      );
      expect((r as BarRefuse<Boisson>).erreurs.keys, ['article_id']);
      expect(await db.select(db.cartesBoissonLocal).get(), isEmpty);
    });

    test('un conditionnement sans article est refusé', () async {
      final r = await api.enregistrer(
        const SaisieBoisson(
          libelle: 'Béninoise 33 cl',
          categorie: CategorieBoisson.locale,
          prixVente: '500',
          unitesVendablesParUniteStock: '24',
        ),
      );
      expect((r as BarRefuse<Boisson>).erreurs.keys, [
        'unites_vendables_par_unite_stock',
      ]);
    });

    test('« Lier au stock » écrit l’article ET le facteur : une modification '
        'les porte', () async {
      final b = await creerSansLien();

      final r = await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '24',
      );
      expect(
        r,
        isA<BarRecu<Boisson>>(),
        reason: r is BarRefuse<Boisson> ? r.motif : null,
      );

      final l = await ligne('Béninoise 33 cl');
      expect([l.articleId, l.unitesVendables], ['art-casier', '24']);
      final ops = await operations();
      expect(ops, hasLength(2));
      expect(ops.last.type, TypeOperationSync.modification);
      expect(jsonDecode(ops.last.payload), {
        'article_id': 'art-casier',
        'unites_vendables_par_unite_stock': '24',
      });
    });

    test('« Modifier le lien » : le facteur seul, puis l’article et le '
        'facteur (décimale gardée)', () async {
      final b = await creerSansLien();
      await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '24',
      );

      await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '12',
      );
      expect(jsonDecode((await operations()).last.payload), {
        'unites_vendables_par_unite_stock': '12',
      });

      await api.lierAuStock(
        id: b.id,
        articleId: 'art-fut',
        unitesVendablesParUniteStock: '66,5',
      );
      expect(jsonDecode((await operations()).last.payload), {
        'article_id': 'art-fut',
        'unites_vendables_par_unite_stock': '66.5',
      });
      final l = await ligne('Béninoise 33 cl');
      expect([l.articleId, l.unitesVendables], ['art-fut', '66.5']);
    });

    test(
      'un facteur vide, nul ou illisible est refusé : le lien reste',
      () async {
        final b = await creerSansLien();
        await api.lierAuStock(
          id: b.id,
          articleId: 'art-casier',
          unitesVendablesParUniteStock: '24',
        );
        final avant = (await operations()).length;

        for (final facteur in ['', '0', '-3', 'abc']) {
          final r = await api.lierAuStock(
            id: b.id,
            articleId: 'art-fut',
            unitesVendablesParUniteStock: facteur,
          );
          expect((r as BarRefuse<Boisson>).erreurs.keys, [
            'unites_vendables_par_unite_stock',
          ], reason: 'facteur « $facteur »');
        }
        final r = await api.lierAuStock(
          id: b.id,
          articleId: 'art-inconnu',
          unitesVendablesParUniteStock: '24',
        );
        expect((r as BarRefuse<Boisson>).erreurs.keys, ['article_id']);

        final l = await ligne('Béninoise 33 cl');
        expect([l.articleId, l.unitesVendables], ['art-casier', '24']);
        expect(await operations(), hasLength(avant));
      },
    );

    test('le CRUD du catalogue (libellé, catégorie, prix) garde le lien et son '
        'facteur', () async {
      final b = await creerSansLien();
      await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '24',
      );
      final r = await api.enregistrer(
        SaisieBoisson(
          id: b.id,
          libelle: 'Béninoise 33 cl bis',
          categorie: CategorieBoisson.importee,
          prixVente: '700',
          articleId: 'art-casier',
        ),
      );
      expect(r, isA<BarRecu<Boisson>>());
      final l = await ligne('Béninoise 33 cl bis');
      expect([l.articleId, l.unitesVendables], ['art-casier', '24']);
    });

    test('changer le PRIX ou le libellé ne perd jamais le facteur', () async {
      final b = await creerSansLien();
      await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '24',
      );

      await api.modifierPrix(b.id, '650');
      await api.modifier(
        b.id,
        libelle: 'Béninoise 33 cl bis',
        categorie: CategorieBoisson.importee,
      );

      final l = await ligne('Béninoise 33 cl bis');
      expect(
        [l.articleId, l.unitesVendables, l.prixVente],
        ['art-casier', '24', 650],
      );
    });

    test(
      'les articles proposés : suivi permanent, non archivés, filtrés',
      () async {
        await semerArticle('art-huile', 'Huile', suivi: 'journalier');
        await semerArticle('art-vieux', 'Casier ancien', actif: false);
        final dao = CatalogueDao(db);

        expect(
          [for (final a in await dao.articlesDeStockLiables()) a.libelle],
          ['Casier Béninoise', 'Fût Flag'],
        );
        expect(
          [
            for (final a in await dao.articlesDeStockLiables(terme: 'FUT'))
              a.id,
          ],
          ['art-fut'],
        );
      },
    );
  });

  /* ================================================================== */
  group('Carte du bar — les deux modales, montées pour de vrai', () {
    Future<void> monter(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(2400, 1600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            droitsProvider.overrideWithValue(
              GardeAcces.depuisJson(const {'M5': 'C', 'M6': 'C'}),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranCarteBar()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> choisir(
      WidgetTester tester,
      String prefixe,
      String libelle,
    ) async {
      await tester.tap(find.byKey(Key('$prefixe-liste')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(libelle).last);
      await tester.pumpAndSettle();
    }

    testWidgets('« Nouvelle boisson » : l’article choisi et le facteur saisi '
        'sont ENREGISTRÉS, et la colonne « Article de stock » les dit', (
      tester,
    ) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('carte-nouvelle-boisson')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('nouvelle-boisson-libelle')),
        'Béninoise 33 cl',
      );
      await tester.enterText(
        find.byKey(const Key('nouvelle-boisson-prix')),
        '500',
      );
      await choisir(tester, 'nouvelle-boisson-article', 'Casier Béninoise');
      await tester.enterText(
        find.byKey(const Key('nouvelle-boisson-conversion')),
        '24',
      );
      await tester.tap(find.byKey(const Key('nouvelle-boisson-confirmer')));
      await tester.pumpAndSettle();

      final l = await ligne('Béninoise 33 cl');
      expect([l.articleId, l.unitesVendables], ['art-casier', '24']);
      expect(find.byKey(const Key('nouvelle-boisson-creee')), findsOneWidget);
      // La carte relit : liée, avec l’article et le conditionnement en clair.
      expect(
        find.descendant(
          of: find.byKey(Key('carte-article-stock-${l.id}')),
          matching: find.text('Casier Béninoise'),
        ),
        findsOneWidget,
      );
      expect(find.text('24 par casier'), findsOneWidget);
    });

    testWidgets('« Nouvelle boisson » sans article ou sans facteur : refusée '
        'sous le champ, rien n’est écrit', (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('carte-nouvelle-boisson')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('nouvelle-boisson-libelle')),
        'Béninoise 33 cl',
      );
      await tester.enterText(
        find.byKey(const Key('nouvelle-boisson-prix')),
        '500',
      );
      await tester.tap(find.byKey(const Key('nouvelle-boisson-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesCatalogueLocal.articleObligatoire),
        findsOneWidget,
      );

      await choisir(tester, 'nouvelle-boisson-article', 'Casier Béninoise');
      await tester.tap(find.byKey(const Key('nouvelle-boisson-confirmer')));
      await tester.pumpAndSettle();
      expect(
        find.text(TextesCatalogueLocal.conversionRequise('Béninoise 33 cl')),
        findsOneWidget,
      );
      expect(await db.select(db.cartesBoissonLocal).get(), isEmpty);
    });

    testWidgets('« Lier au stock » : article + facteur écrits, aperçu '
        'affiché, bouton devenu « Modifier le lien »', (tester) async {
      final b = await creerSansLien();
      await monter(tester);

      expect(find.text('Lier au stock'), findsWidgets);
      // Le tableau défile à l'horizontale (`overflow-x-auto`, l.310) : le
      // bouton de fin de ligne est amené à l'écran comme le ferait la souris.
      await tester.ensureVisible(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();

      await choisir(tester, 'lien-stock-article', 'Casier Béninoise — casier');
      await tester.enterText(
        find.byKey(const Key('lien-stock-conversion')),
        '24',
      );
      await tester.pumpAndSettle();
      // 1 / 24 tronqué au dix-millième (bcdiv) : 0.0416 casier par bouteille vendue.
      expect(find.byKey(const Key('lien-stock-apercu')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('lien-stock-decrement'))).data,
        '0.0416 casier',
      );

      await tester.tap(find.byKey(const Key('lien-stock-enregistrer')));
      await tester.pumpAndSettle();

      final l = await ligne('Béninoise 33 cl');
      expect([l.articleId, l.unitesVendables], ['art-casier', '24']);
      expect(find.byKey(const Key('lien-stock-enregistre')), findsOneWidget);
      expect(find.text('Modifier le lien'), findsOneWidget);
      expect(find.text('24 par casier'), findsOneWidget);
    });

    testWidgets('« Modifier le lien » repart du facteur ENREGISTRÉ, pas de 1', (
      tester,
    ) async {
      final b = await creerSansLien();
      await api.lierAuStock(
        id: b.id,
        articleId: 'art-casier',
        unitesVendablesParUniteStock: '24',
      );
      await monter(tester);

      // Le tableau défile à l'horizontale (`overflow-x-auto`, l.310) : le
      // bouton de fin de ligne est amené à l'écran comme le ferait la souris.
      await tester.ensureVisible(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('lien-stock-conversion')))
            .controller!
            .text,
        '24',
      );
    });

    testWidgets('« Lier au stock » avec un facteur nul : le refus est sous le '
        'champ, le lien n’est pas écrit', (tester) async {
      final b = await creerSansLien();
      await monter(tester);

      // Le tableau défile à l'horizontale (`overflow-x-auto`, l.310) : le
      // bouton de fin de ligne est amené à l'écran comme le ferait la souris.
      await tester.ensureVisible(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('carte-lien-${b.id}')));
      await tester.pumpAndSettle();
      await choisir(tester, 'lien-stock-article', 'Casier Béninoise — casier');
      await tester.enterText(
        find.byKey(const Key('lien-stock-conversion')),
        '0',
      );
      await tester.tap(find.byKey(const Key('lien-stock-enregistrer')));
      await tester.pumpAndSettle();

      expect(
        find.text(TextesCatalogueLocal.conversionInvalide('Béninoise 33 cl')),
        findsOneWidget,
      );
      final l = await ligne('Béninoise 33 cl');
      expect(l.articleId, isEmpty);
      expect(l.unitesVendables, isNull);
    });
  });
}
