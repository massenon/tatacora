import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/carte_bar.dart';
import 'package:tatacora_flutter/features/bar/presentation/ecran_carte_bar.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/cadre_ventes_carte.dart';

import '../../support/vue_blade.dart';

/// L'écran Carte du bar, monté pour de vrai — Phase 2, 08/10/2026.
///
/// ## Ce que ces cas protègent
///
/// L'ORDRE et la PLACE des blocs de la vue (`pwa/carte/corps.blade.php`) :
/// jusqu'à cette date, « Exporter » et « Imprimer la fiche des prix » étaient
/// posés au-dessus du tableau et le bandeau au-dessus des onglets. Les
/// mesures de géométrie (`geometrie_blade_test.dart`) le disent en pixels ;
/// ces cas le disent en termes que la revue lit sans ouvrir un relevé.
void main() {
  Future<AppDatabase> monter(
    WidgetTester tester, {
    Map<String, String> droits = const {'M5': 'C', 'M6': 'C'},
    Future<void> Function(AppDatabase db)? avant,
  }) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    if (avant != null) await avant(db);
    tester.view
      ..physicalSize = const Size(1383, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(GardeAcces.depuisJson(droits)),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranCarteBar()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('les boutons d’en-tête sont ceux de la vue, dans son ordre', (
    tester,
  ) async {
    await monter(tester);

    // `corps.blade.php` l.86-120 : liens, puis Exporter, la fiche des prix,
    // enfin Nouvelle boisson — tous AU-DESSUS des onglets.
    final cles = [
      'carte-lien-pos',
      'carte-lien-stocks',
      'carte-exporter',
      'carte-fiche-prix',
      'carte-nouvelle-boisson',
    ];
    var gauche = -1.0;
    for (final cle in cles) {
      final boite = tester.getRect(find.byKey(Key(cle)));
      expect(boite.left, greaterThan(gauche), reason: cle);
      gauche = boite.left;
      expect(
        boite.bottom,
        lessThan(
          tester.getRect(find.byKey(const Key('onglet-carte-bar-carte'))).top,
        ),
        reason: '$cle doit précéder les onglets',
      );
    }
  });

  testWidgets('un rôle en lecture ne voit pas « Nouvelle boisson »', (
    tester,
  ) async {
    await monter(tester, droits: const {'M5': 'L'});

    expect(find.byKey(const Key('carte-nouvelle-boisson')), findsNothing);
    // Les liens et les documents restent offerts : ce sont des lectures.
    expect(find.byKey(const Key('carte-exporter')), findsOneWidget);
    expect(find.byKey(const Key('carte-lien-pos')), findsOneWidget);
  });

  testWidgets('le bandeau est SOUS les filtres, pas au-dessus des onglets', (
    tester,
  ) async {
    await monter(tester);

    final onglets = tester.getRect(
      find.byKey(const Key('onglet-carte-bar-carte')),
    );
    final filtres = tester.getRect(find.byKey(const Key('carte-recherche')));
    final bandeau = tester.getRect(find.byKey(const Key('carte-bandeau')));

    expect(onglets.top, lessThan(filtres.top));
    expect(filtres.bottom, lessThan(bandeau.top));
  });

  testWidgets(
    'la bande compte SIX cartes, sur une seule rangée en grand écran',
    (tester) async {
      await monter(tester);

      const cles = [
        'carte-kpi-articles',
        'carte-kpi-retires',
        'carte-kpi-lies',
        'carte-kpi-sans-lien',
        'carte-kpi-rupture',
        'carte-kpi-provisoires',
      ];
      final hauts = {
        for (final c in cles) tester.getRect(find.byKey(Key(c))).top,
      };
      expect(hauts, hasLength(1), reason: '`lg:grid-cols-6` : une rangée');
    },
  );

  testWidgets('l’accordéon replie la bande sans retirer le titre', (
    tester,
  ) async {
    await monter(tester);

    expect(find.byKey(const Key('carte-kpi-articles')), findsOneWidget);
    await tester.tap(find.byKey(const Key('carte-kpis-accordeon')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('carte-kpi-articles')), findsNothing);
    expect(find.text('Indicateurs de la carte'), findsOneWidget);
  });

  testWidgets('le filtre de catégorie offre le REGISTRE, même carte vide', (
    tester,
  ) async {
    await monter(tester);

    // La carte est vide : une liste dérivée des lignes n'offrirait rien.
    await tester.tap(find.byKey(const Key('carte-filtre-categorie')));
    await tester.pumpAndSettle();

    for (final c in CategorieBoisson.values) {
      expect(find.text(c.libelle), findsWidgets, reason: c.code);
    }
  });

  testWidgets('les trois onglets sont cliquables et changent le panneau', (
    tester,
  ) async {
    await monter(tester);

    // Carte vide : l'état vide de la vue.
    expect(find.byKey(const Key('carte-vide')), findsOneWidget);

    await tester.tap(find.byKey(const Key('onglet-carte-bar-couverture')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('carte-vide')), findsNothing);
    expect(find.text('TOTAL'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onglet-carte-bar-ventes')));
    await tester.pumpAndSettle();
    // L'export est UN bouton d'en-tête, et sa clé dit l'onglet qu'il exporte.
    expect(find.byKey(const Key('ventes-bar-exporter')), findsOneWidget);
    expect(find.byKey(const Key('carte-exporter')), findsNothing);
  });

  testWidgets(
    'l’onglet Ventes garde le CADRE de la vue quand le poste n’a aucune vente',
    (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('onglet-carte-bar-ventes')));
      await tester.pumpAndSettle();

      // Les ventes se calculent sur ce poste : sans vente, la vue dit « aucune
      // ligne », avec son cadre — jamais « information non disponible ».
      expect(find.byKey(const Key('ventes-bar-refuse')), findsNothing);
      expect(find.byKey(const Key('ventes-bar-vide')), findsOneWidget);
      for (final c in colonnesVentesCarte) {
        expect(
          find.text(c.titre.toUpperCase()),
          findsOneWidget,
          reason: c.titre,
        );
      }
      expect(find.text('TOTAL DE LA PAGE'), findsOneWidget);
      expect(find.textContaining('0 ligne(s)'), findsOneWidget);
    },
  );

  testWidgets(
    '« Couverture complète. » : le titre et le texte sont deux éléments, sur une ligne',
    (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('onglet-carte-bar-couverture')));
      await tester.pumpAndSettle();

      // Les mots de la vue (`couverture_complete_titre`, `…_texte`), relus de
      // la langue servie par la PWA.
      final titre = VueBlade.libelle(
        'carte_pwa.commun.couverture_complete_titre',
      )!;
      final texte = VueBlade.libelle(
        'carte_pwa.commun.couverture_complete_texte',
      )!;
      final boiteTitre = tester.getRect(find.text(titre));
      final boiteTexte = tester.getRect(find.text(texte));

      expect(boiteTexte.left, greaterThan(boiteTitre.right));
      expect((boiteTexte.top - boiteTitre.top).abs(), lessThan(1));
    },
  );

  testWidgets(
    'la couverture d’une carte vide rend les catégories du registre',
    (tester) async {
      await monter(tester);

      await tester.tap(find.byKey(const Key('onglet-carte-bar-couverture')));
      await tester.pumpAndSettle();

      // Comme la vue : une catégorie sans article est une ligne à zéro.
      for (final c in CategorieBoisson.values) {
        expect(
          find.byKey(Key('couverture-bar-${c.code}')),
          findsOneWidget,
          reason: c.code,
        );
        expect(find.text(c.libelle), findsWidgets);
      }
    },
  );

  testWidgets('le stock inconnu ne devient jamais « 0 en rupture »', (
    tester,
  ) async {
    await monter(tester);

    // Sans réponse de stock, la carte « En rupture de stock » dit « — ».
    final carte = find.byKey(const Key('carte-kpi-rupture'));
    expect(
      find.descendant(of: carte, matching: find.text('—')),
      findsOneWidget,
    );
    expect(find.descendant(of: carte, matching: find.text('0')), findsNothing);
  });

  testWidgets('« Rendre indispo. » écrit le retrait, la ligne passe en '
      '« retirée », « Remettre » la rend à la carte', (tester) async {
    await monter(
      tester,
      avant: (db) => CatalogueDao(db).enregistrerBoisson(
        const BoissonDistante(
          id: 'b-1',
          articleId: null,
          libelle: 'Béninoise 33 cl',
          categorie: 'locale',
          prixVente: 500,
          stockDisponible: null,
        ),
      ),
    );

    // Le tableau défile à l'horizontale : l'action peut être hors fenêtre.
    await tester.ensureVisible(find.byKey(const Key('carte-retirer-b-1')));
    await tester.tap(find.byKey(const Key('carte-retirer-b-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modale-retrait-carte')), findsOneWidget);
    // Plus aucun refus « faute de colonne » : un formulaire, qui écrit.
    expect(find.byKey(const Key('retrait-carte-sans-colonne')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('retrait-carte-commentaire')),
      'livraison jeudi',
    );
    await tester.tap(find.byKey(const Key('retrait-carte-confirmer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-retrait-carte')), findsNothing);
    expect(find.byKey(const Key('carte-remettre-b-1')), findsOneWidget);
    expect(find.byKey(const Key('carte-retirer-b-1')), findsNothing);

    // Le tableau défile à l'horizontale : l'action peut être hors fenêtre.
    await tester.ensureVisible(find.byKey(const Key('carte-remettre-b-1')));
    await tester.tap(find.byKey(const Key('carte-remettre-b-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('carte-retirer-b-1')), findsOneWidget);
    expect(find.byKey(const Key('carte-remettre-b-1')), findsNothing);
  });

  testWidgets('« Modifier » ouvre la modale de la vue, change le libellé '
      'sans toucher au prix, et dit « est à jour »', (tester) async {
    final db = await monter(
      tester,
      avant: (db) => CatalogueDao(db).enregistrerBoisson(
        const BoissonDistante(
          id: 'b-1',
          articleId: null,
          libelle: 'Béninoise 33 cl',
          categorie: 'locale',
          prixVente: 500,
          stockDisponible: null,
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('carte-modifier-b-1')));
    await tester.tap(find.byKey(const Key('carte-modifier-b-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modale-modifier-boisson')), findsOneWidget);
    expect(find.text('Modifier la boisson — Béninoise 33 cl'), findsOneWidget);
    expect(find.text('Enregistrer la boisson'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('modifier-boisson-libelle')),
      'Béninoise 50 cl',
    );
    await tester.tap(find.byKey(const Key('modifier-boisson-confirmer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-modifier-boisson')), findsNothing);
    expect(find.text('« Béninoise 50 cl » est à jour.'), findsOneWidget);
    final ligne = await (db.select(
      db.cartesBoissonLocal,
    )..where((b) => b.id.equals('b-1'))).getSingle();
    expect(ligne.libelle, 'Béninoise 50 cl');
    expect(ligne.prixVente, 500, reason: 'le prix reste celui de la boisson');
  });

  test('le registre des catégories est celui de la base, dans son ordre', () {
    // Relu depuis le modèle serveur, pas recopié ici : une liste écrite des
    // deux côtés ne vérifierait que la copie (piège 12).
    final php = File(
      '../tatacora-api/app/Domain/Bar/Models/CarteBoisson.php',
    ).readAsStringSync();
    final bloc = RegExp(
      r'const CATEGORIES = \[(.*?)\];',
      dotAll: true,
    ).firstMatch(php);
    expect(bloc, isNotNull, reason: 'CATEGORIES introuvable : garde vide');
    final codes = RegExp(
      r"'(\w+)'\s*=>",
    ).allMatches(bloc!.group(1)!).map((m) => m.group(1)).toList();
    expect(codes, isNotEmpty);

    expect(CategorieBoisson.values.map((c) => c.code), codes);
    expect(
      couvertureParCategorie(const <LigneCarte>[]).map((c) => c.categorie),
      codes,
    );
  });

  testWidgets('le lien « Boissons » hors vue mène au catalogue', (
    tester,
  ) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    tester.view
      ..physicalSize = const Size(1383, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final routeur = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: EcranCarteBar()),
        ),
        GoRoute(
          path: '/bar/boissons',
          builder: (_, _) => const Scaffold(body: Text('catalogue-boissons')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson(const {'M5': 'C', 'M6': 'C'}),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('carte-vers-boissons')));
    await tester.pumpAndSettle();
    expect(find.text('catalogue-boissons'), findsOneWidget);
  });
}
