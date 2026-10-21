import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/fiche_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/import_articles.dart';
import 'package:tatacora_flutter/features/stocks/impression/etat_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_inventaires.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/providers_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/widgets/table_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/widgets/vue_fiche_stock.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import '../../support/selecteur_essai.dart';
import '../../support/vue_blade.dart';

/// L'écran Gestion des Stocks, monté sur une **vraie base locale** — le chemin
/// que l'exploitant emprunte : clic, modale, `StocksApi`, `StocksDao`, base,
/// relecture. Aucun faux au milieu (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late SelecteurEssai selecteur;

  setUp(() async {
    db = AppDatabase.enMemoire();
    selecteur = SelecteurEssai();

    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'essai',
            nom: 'Aïcha',
            role: 'magasinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> monter(
    WidgetTester tester, {
    String niveau = 'C',
    String role = 'magasinier',
    Widget ecran = const EcranStocks(),
    Size taille = const Size(1600, 1400),
    List<Override> surcharges = const [],
  }) async {
    tester.view
      ..physicalSize = taille
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final droits = GardeAcces({'M6': niveau});
    final session = Session(
      utilisateurId: 'u-essai',
      login: 'essai',
      nom: 'Aïcha',
      role: role,
      droits: droits,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild((ref, notifier) => session),
          // Un test de widget n'a pas de greffon natif : la fenêtre
          // « Enregistrer sous » est remplacée, le VRAI chemin d'export
          // (`exporterStocksProvider` → `enregistrementExportProvider`) est
          // emprunté jusqu'à elle (14/10/2026).
          ...selecteur.surcharges,
          ...surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StocksApi api() => StocksApi(
    dao: StocksDao(db),
    peutLire: () => true,
    peutEcrire: () => true,
    auteurId: () => 'u-essai',
  );

  Future<String> semerPoint(String libelle, {TypePoint? type}) async {
    final r = await api().creerPoint(libelle: libelle, type: type);
    return (r as PointEnregistre).point.id;
  }

  Future<void> semerArticle(
    String id,
    String libelle, {
    String? pointId,
    String seuil = '5',
    SuiviArticle suivi = SuiviArticle.permanent,
    String? ouverture,
    String? cout,
    String categorie = 'Denrées',
    String unite = 'sac',
  }) async {
    final r = await api().enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: categorie,
        uniteMesure: unite,
        seuilAlerte: seuil,
        suivi: suivi,
        pointStockageId: pointId,
        stockOuverture: ouverture ?? '',
        valeurAchat: cout ?? '',
      ),
    );
    expect(r, isA<ArticleEnregistre>(), reason: '$r');
  }

  Future<void> toucher(WidgetTester tester, Key cle) async {
    final cible = find.byKey(cle);
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, Key cle, String texte) async {
    final cible = find.byKey(cle);
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.enterText(cible, texte);
    await tester.pumpAndSettle();
  }

  Future<void> choisir(WidgetTester tester, Key liste, String libelle) async {
    await toucher(tester, liste);
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  String texteDe(WidgetTester tester, Key cle) =>
      (tester.widget(find.byKey(cle)) as Text).data!;

  Text texteWidget(WidgetTester tester, Key cle) =>
      tester.widget<Text>(find.byKey(cle));

  group('Un poste neuf : la structure de la vue, des zéros VRAIS', () {
    testWidgets('titre, cinq cartes, état vide, et les limites dites', (
      tester,
    ) async {
      await monter(tester);

      expect(find.text('Gestion des Stocks'), findsOneWidget);
      expect(find.text('RÉFÉRENCES'), findsOneWidget);
      expect(find.text('0 suivies · 0 journalières'), findsOneWidget);
      expect(find.text('0 FCFA'), findsOneWidget);
      expect(find.text('0 / 0'), findsOneWidget);
      expect(find.text('Aucun résultat'), findsOneWidget);
      expect(find.text('0 article(s)'), findsOneWidget);

      // Les deux limites sont DITES, en clair, même sur un poste neuf : le
      // chiffre exact en apparence est le défaut de ce dépôt.
      expect(
        texteDe(tester, const Key('stocks-limite-ventes')),
        TextesStocks.ventesSansSortie,
      );
      expect(
        texteDe(tester, const Key('stocks-limite-comptabilite')),
        TextesStocks.sansComptabilite,
      );
      expect(find.byKey(const Key('stocks-limite-valorisation')), findsNothing);
    });

    testWidgets('aucun texte ne parle de serveur ni de connexion', (
      tester,
    ) async {
      await monter(tester);

      final tout = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .join('\n')
          .toLowerCase();
      expect(tout, isNot(contains('serveur')));
      expect(tout, isNot(contains('connexion')));
      expect(tout, isNot(contains('en attente de synchronisation')));
    });

    testWidgets('sans droit de lecture, un refus — et aucun chiffre', (
      tester,
    ) async {
      await monter(tester, niveau: '-');

      expect(find.byKey(const Key('stocks-refus')), findsOneWidget);
      expect(find.text(refusLectureStocks), findsOneWidget);
      expect(find.byKey(const Key('stocks-kpi-references')), findsNothing);
    });
  });

  group('Le parcours complet : point, article, entrée, sortie, rupture', () {
    testWidgets('créer un point DEPUIS la modale d’article, puis l’article '
        'avec son stock d’ouverture', (tester) async {
      await monter(tester);

      await toucher(tester, const Key('stocks-nouvel-article'));
      expect(find.byKey(const Key('modale-article')), findsOneWidget);
      // Aucun point : la modale le DIT et offre le geste.
      expect(find.byKey(const Key('article-sans-point')), findsOneWidget);

      await toucher(tester, const Key('article-nouveau-point'));
      await saisir(tester, const Key('point-libelle'), 'Magasin général');
      await choisir(tester, const Key('point-type'), 'Magasin');
      await toucher(tester, const Key('point-creer'));

      // Le point créé est SÉLECTIONNÉ dans la modale d'article.
      expect(find.byKey(const Key('modale-point')), findsNothing);
      expect(find.byKey(const Key('article-sans-point')), findsNothing);
      expect(find.text('Magasin général'), findsWidgets);

      await saisir(
        tester,
        const Key('article-libelle'),
        'Riz local (sac 50 kg)',
      );
      await saisir(tester, const Key('article-valeur-achat'), '1250,50');
      await saisir(tester, const Key('article-seuil'), '5');
      await saisir(tester, const Key('article-stock-ouverture'), '10');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.byKey(const Key('modale-article')), findsNothing);
      expect(
        find.text('Article « Riz local (sac 50 kg) » créé.'),
        findsOneWidget,
      );

      // La base : un point typé, un article rattaché, UNE entrée d'ouverture.
      final point = await db.select(db.pointsStockageLocal).getSingle();
      expect(point.libelle, 'Magasin général');
      expect(point.type, 'magasin');
      final article = await db.select(db.articlesLocal).getSingle();
      expect(article.pointStockageId, point.id);
      expect(article.suivi, 'permanent');
      final mouvement = await db.select(db.mouvementsStockLocal).getSingle();
      expect(mouvement.motif, "Stock d'ouverture");
      expect(mouvement.statutSync, 'local');
      expect(mouvement.utilisateurId, 'u-essai');

      // L'écran : le tableau, avec les VRAIES valeurs.
      final id = article.id;
      expect(texteDe(tester, Key('stocks-stock-$id')), '10.00');
      expect(find.text('12 505 FCFA'), findsWidgets, reason: 'valeur du stock');
      expect(find.text('1 suivies · 0 journalières'), findsOneWidget);
      expect(find.text('1 / 0'), findsOneWidget);
      expect(find.text('Magasin général'), findsWidgets);
      expect(find.text('Permanent'), findsOneWidget);
    });

    testWidgets('sans point, la création est REFUSÉE avant tout envoi', (
      tester,
    ) async {
      await monter(tester);

      await toucher(tester, const Key('stocks-nouvel-article'));
      await saisir(tester, const Key('article-libelle'), 'Riz');
      await toucher(tester, const Key('article-enregistrer'));

      expect(
        find.textContaining('Choisissez le point de stockage'),
        findsOneWidget,
      );
      expect(await db.select(db.articlesLocal).get(), isEmpty);
    });

    testWidgets('une sortie, puis une sortie en RUPTURE : confirmation, '
        'annulation, forçage tracé', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await monter(tester);

      // Sortie ordinaire de 3 : 10 -> 7.
      await toucher(tester, const Key('stocks-mouvement-riz'));
      expect(find.byKey(const Key('modale-mouvement')), findsOneWidget);
      // Le point proposé est celui de rattachement.
      expect(find.text('Magasin'), findsWidgets);
      await choisir(
        tester,
        const Key('mouvement-type'),
        'Sortie (consommation, vente)',
      );
      await saisir(tester, const Key('mouvement-quantite'), '3');
      await saisir(tester, const Key('mouvement-motif'), 'Cuisine');
      await toucher(tester, const Key('mouvement-enregistrer'));

      expect(find.byKey(const Key('modale-mouvement')), findsNothing);
      expect(
        find.text('Sortie de 3.00 sac enregistrée sur ce poste.'),
        findsOneWidget,
      );
      expect(texteDe(tester, const Key('stocks-stock-riz')), '7.00');

      // Sortie de 20 : RUPTURE -> confirmation, rien d'écrit.
      await toucher(tester, const Key('stocks-mouvement-riz'));
      await choisir(
        tester,
        const Key('mouvement-type'),
        'Sortie (consommation, vente)',
      );
      await saisir(tester, const Key('mouvement-quantite'), '20');
      await saisir(tester, const Key('mouvement-motif'), 'Banquet');
      await toucher(tester, const Key('mouvement-enregistrer'));

      expect(find.byKey(const Key('mouvement-rupture')), findsOneWidget);
      expect(
        find.text(
          'Stock insuffisant : 7.00 disponible, 20.00 demandé. '
          'Une validation explicite est requise pour forcer la sortie.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('rupture forcée'), findsOneWidget);
      expect(await db.select(db.mouvementsStockLocal).get(), hasLength(2));

      // Annuler : la modale reste, RIEN n'est écrit.
      await toucher(tester, const Key('rupture-annuler'));
      expect(await db.select(db.mouvementsStockLocal).get(), hasLength(2));
      expect(find.byKey(const Key('modale-mouvement')), findsOneWidget);

      // Forcer : le stock passe NÉGATIF, la décision est tracée.
      await toucher(tester, const Key('mouvement-enregistrer'));
      await toucher(tester, const Key('rupture-forcer'));
      expect(find.byKey(const Key('modale-mouvement')), findsNothing);
      expect(find.text('Sortie forcée enregistrée et tracée.'), findsOneWidget);

      expect(texteDe(tester, const Key('stocks-stock-riz')), '-13.00');
      // Rouge gras : la vue lit l'état sur le stock lui-même.
      final style = texteWidget(tester, const Key('stocks-stock-riz')).style!;
      expect(style.color, PaletteMaitre.rouge600);
      expect(style.fontWeight, FontWeight.w600);

      final forcee = await (db.select(
        db.mouvementsStockLocal,
      )..where((m) => m.ruptureForcee.equals(true))).getSingle();
      expect(forcee.utilisateurId, 'u-essai');
      expect(forcee.quantite, 20.0);
      expect(forcee.motif, 'Banquet');
    });

    testWidgets('un point créé depuis la modale de mouvement est proposé', (
      tester,
    ) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester);

      await toucher(tester, const Key('stocks-mouvement-riz'));
      expect(find.byKey(const Key('mouvement-sans-point')), findsOneWidget);
      expect(
        find.textContaining("Aucun point de stockage n'est défini"),
        findsOneWidget,
      );

      await toucher(tester, const Key('mouvement-nouveau-point'));
      await saisir(tester, const Key('point-libelle'), 'Bar');
      await toucher(tester, const Key('point-creer'));

      expect(find.byKey(const Key('mouvement-sans-point')), findsNothing);
      await saisir(tester, const Key('mouvement-quantite'), '12');
      await saisir(tester, const Key('mouvement-cout'), '600');
      await saisir(tester, const Key('mouvement-motif'), 'Réception');
      await toucher(tester, const Key('mouvement-enregistrer'));

      expect(texteDe(tester, const Key('stocks-stock-riz')), '12.00');
    });

    testWidgets('un article journalier : « non suivi », « — », et le refus '
        'de la vue au lieu d’une modale', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'tom',
        'Tomates',
        pointId: magasin,
        suivi: SuiviArticle.journalier,
        unite: 'kg',
      );
      await monter(tester);

      expect(find.byKey(const Key('stocks-non-suivi-tom')), findsOneWidget);
      expect(find.text('non suivi'), findsOneWidget);
      expect(find.text('Journalier'), findsOneWidget);
      // Aucune alarme : ni sous seuil ni rupture, bien que son solde soit zéro.
      expect(find.text('0 / 1'), findsOneWidget);
      final carte = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('stocks-kpi-sous-seuil')),
          matching: find.text('0'),
        ),
      );
      expect(carte.style!.color, PaletteMaitre.emeraude600);

      await toucher(tester, const Key('stocks-mouvement-tom'));
      expect(find.byKey(const Key('modale-mouvement')), findsNothing);
      expect(
        find.text(
          "« Tomates » est en suivi journalier : son stock n'est pas suivi.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('modifier : le bloc calculé est en lecture seule, l’unité se '
        'verrouille avec l’historique', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1250,50',
      );
      await monter(tester);

      await toucher(tester, const Key('stocks-modifier-riz'));
      expect(find.byKey(const Key('article-bloc-calcule')), findsOneWidget);
      expect(find.text('10.00 sac'), findsOneWidget);
      expect(
        find.text('1 251 FCFA'),
        findsWidgets,
        reason: 'dernier prix, CMP',
      );
      expect(find.text('12 505 FCFA'), findsWidgets);
      // Ni valeur d'achat ni stock d'ouverture à saisir en modification.
      expect(find.byKey(const Key('article-valeur-achat')), findsNothing);
      expect(find.byKey(const Key('article-stock-ouverture')), findsNothing);

      await choisir(tester, const Key('article-unite'), 'kg');
      await toucher(tester, const Key('article-enregistrer'));
      expect(find.byKey(const Key('article-refus')), findsOneWidget);
      expect(find.textContaining('1 mouvement(s)'), findsWidgets);

      // Remettre l'unité, changer le nom : accepté.
      await choisir(tester, const Key('article-unite'), 'sac');
      await saisir(tester, const Key('article-libelle'), 'Riz parfumé');
      await toucher(tester, const Key('article-enregistrer'));
      expect(find.text('Article « Riz parfumé » mis à jour.'), findsOneWidget);
    });
  });

  group('Les filtres, les compteurs et la valeur « inconnue »', () {
    Future<void> semerParc() async {
      final magasin = await semerPoint('Magasin', type: TypePoint.magasin);
      final bar = await semerPoint('Bar', type: TypePoint.bar);
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await semerArticle(
        'biere',
        'Béninoise 66 cl (casier 12)',
        pointId: bar,
        seuil: '4',
        ouverture: '3',
        cout: '5000',
        categorie: 'Boissons',
        unite: 'casier',
      );
      await semerArticle(
        'sel',
        'Sel',
        pointId: magasin,
        seuil: '2',
        ouverture: '4',
      );
      await semerArticle(
        'tom',
        'Tomates',
        pointId: magasin,
        suivi: SuiviArticle.journalier,
        unite: 'kg',
        categorie: 'Denrées',
      );
    }

    testWidgets('les compteurs portent sur tout le référentiel', (
      tester,
    ) async {
      await semerParc();
      await monter(tester);

      expect(find.text('4'), findsWidgets);
      expect(find.text('3 suivies · 1 journalières'), findsOneWidget);
      expect(find.text('3 / 1'), findsOneWidget);
      // Béninoise : 3,00 <= 4,00 (sous seuil). Sel : 4,00 > 2,00 (sain). Riz
      // 10 > 5. Tomates : journalier, exclu.
      final sousSeuil = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('stocks-kpi-sous-seuil')),
          matching: find.text('1'),
        ),
      );
      expect(sousSeuil.style!.color, PaletteMaitre.rouge600);
      // 10 000 + 15 000 (+ sel sans coût, + tomates).
      expect(find.text('25 000 FCFA'), findsOneWidget);
    });

    testWidgets('du stock SANS COÛT : « — » avec sa raison, jamais zéro, et '
        'le compteur le dit', (tester) async {
      await semerParc();
      await monter(tester);

      // Le sel a 4,00 en stock et aucune entrée valorisée.
      expect(
        find.byKey(const Key('stocks-valeur-inconnue-sel')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('stocks-valeur-sel')), findsNothing);
      expect(find.byKey(const Key('stocks-prix-absent-sel')), findsOneWidget);
      expect(
        texteDe(tester, const Key('stocks-limite-valorisation')),
        TextesStocks.sansValorisation(1),
      );
      // Un article valorisé, lui, montre son montant.
      expect(find.byKey(const Key('stocks-valeur-riz')), findsOneWidget);
      expect(texteDe(tester, const Key('stocks-valeur-riz')), '10 000 FCFA');
    });

    testWidgets('un CMP sans coût connu est « — » partout : colonne, modales, '
        'jamais « 0 »', (tester) async {
      await semerParc();
      await monter(tester);

      // Le sel : 4,00 en stock, aucune entrée valorisée -> CMP inconnu.
      expect(
        texteWidget(
          tester,
          const Key('stocks-cmp-sel'),
        ).textSpan!.toPlainText(),
        '—',
      );
      // Le riz : 10,00 à 1 000 F -> CMP connu.
      expect(
        texteWidget(
          tester,
          const Key('stocks-cmp-riz'),
        ).textSpan!.toPlainText(),
        '1 000 FCFA',
      );

      // La modale de mouvement du sel.
      await toucher(tester, const Key('stocks-mouvement-sel'));
      final contexte = find.byKey(const Key('mouvement-contexte'));
      expect(
        find.descendant(of: contexte, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: contexte, matching: find.textContaining('FCFA')),
        findsNothing,
      );
      await toucher(tester, const Key('modale-stock-annuler'));

      // Le récapitulatif de la modale d'article.
      await toucher(tester, const Key('stocks-modifier-sel'));
      final bloc = find.byKey(const Key('article-bloc-calcule'));
      expect(
        find.descendant(
          of: bloc,
          matching: find.text('aucune entrée valorisée'),
        ),
        findsOneWidget,
      );
      // Valeur d'achat absente, CMP inconnu, valeur inconnue : trois « — » ou
      // mentions, aucun « 0 FCFA ».
      expect(
        find.descendant(of: bloc, matching: find.text('0 FCFA')),
        findsNothing,
      );
    });

    testWidgets('recherche, catégorie, suivi et état filtrent l’affichage', (
      tester,
    ) async {
      await semerParc();
      await monter(tester);

      expect(find.text('4 article(s)'), findsOneWidget);

      await saisir(tester, const Key('stocks-recherche'), 'béninoise');
      expect(find.text('1 article(s)'), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-biere')), findsOneWidget);
      await saisir(tester, const Key('stocks-recherche'), '');

      await choisir(tester, const Key('stocks-filtre-categorie'), 'Boissons');
      expect(find.text('1 article(s)'), findsOneWidget);
      await choisir(
        tester,
        const Key('stocks-filtre-categorie'),
        'Toutes catégories',
      );

      await choisir(
        tester,
        const Key('stocks-filtre-suivi'),
        'Petit stock (journalier)',
      );
      expect(find.text('1 article(s)'), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-tom')), findsOneWidget);
      await choisir(
        tester,
        const Key('stocks-filtre-suivi'),
        'Tous les suivis',
      );

      await choisir(tester, const Key('stocks-filtre-etat'), 'Sous seuil');
      expect(find.text('1 article(s)'), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-biere')), findsOneWidget);
      // Les compteurs d'alarme et de suivi ne bougent PAS avec le filtre.
      expect(find.text('3 suivies · 1 journalières'), findsOneWidget);
    });

    testWidgets('un point recalcule le stock de CE point', (tester) async {
      await semerParc();
      await monter(tester);

      // Le riz est au magasin : 10 ; au bar : 0.
      expect(texteDe(tester, const Key('stocks-stock-riz')), '10.00');
      await choisir(tester, const Key('stocks-filtre-point'), 'Bar');
      expect(texteDe(tester, const Key('stocks-stock-riz')), '0.00');
      expect(texteDe(tester, const Key('stocks-stock-biere')), '3.00');
    });

    testWidgets('une fenêtre étroite passe à la ligne sans déborder', (
      tester,
    ) async {
      await semerParc();
      await monter(tester, taille: const Size(900, 1200));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('stocks-exporter')), findsOneWidget);
    });
  });

  group('Importer, Modèle, Exporter', () {
    // Import et modèle PORTÉS le 14/10/2026 (D436) : le test « ne sont pas
    // portés » est remplacé par le geste réel, sélecteur natif injecté.
    testWidgets('Importer CRÉE les articles du fichier ; Modèle écrit le CSV '
        'vide aux colonnes attendues', (tester) async {
      selecteur = SelecteurEssai(
        lu: FichierLu(
          nom: 'articles.csv',
          octets: Uint8List.fromList(
            utf8.encode(
              '${colonnesImportArticles.join(';')}\n'
              'Huile;Denrées;litre;900;2;;permanent;0\n',
            ),
          ),
        ),
      );
      await monter(tester);

      await toucher(tester, const Key('stocks-importer'));
      expect(find.byKey(const Key('modale-import-articles')), findsOneWidget);
      await toucher(tester, const Key('import-choisir-fichier'));
      expect(texteDe(tester, const Key('import-nom-fichier')), 'articles.csv');
      await toucher(tester, const Key('import-valider'));
      expect(find.byKey(const Key('modale-import-articles')), findsNothing);
      expect(find.text(TextesImportArticles.bilan(1)), findsOneWidget);
      expect(
        (await StocksDao(db).articles()).map((a) => a.libelle),
        contains('Huile'),
      );

      ScaffoldMessenger.of(
        tester.element(find.byType(EcranStocks)),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      await toucher(tester, const Key('stocks-modele'));
      expect(selecteur.dernier.nom, TextesImportArticles.nomModele);
      // `utf8.decode` retire le BOM : on compare les OCTETS.
      expect(selecteur.dernier.octets, modeleImportArticlesOctets());
      expect(selecteur.dernier.octets.take(3), [0xEF, 0xBB, 0xBF]);
      expect(find.byKey(const Key('stocks-modele-enregistre')), findsOneWidget);
    });

    testWidgets('Exporter : le tableur écrit les lignes AFFICHÉES, le filtre '
        'dit, l’inconnu en « — »', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1250,50',
      );
      await semerArticle('sel', 'Sel', pointId: magasin, ouverture: '4');
      await semerArticle(
        'tom',
        'Tomates',
        suivi: SuiviArticle.journalier,
        unite: 'kg',
      );
      // Un article d'une AUTRE catégorie : il est masqué par le filtre, donc
      // absent du fichier (sinon l'export porterait sur tout, pas sur l'affiché).
      await semerArticle(
        'biere',
        'Béninoise 66 cl',
        pointId: magasin,
        categorie: 'Boissons',
        unite: 'casier',
      );
      await monter(tester);

      await choisir(tester, const Key('stocks-filtre-categorie'), 'Denrées');
      await toucher(tester, const Key('stocks-exporter'));
      // D434 : le PDF est présélectionné partout ; le tableur se CHOISIT.
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      // Par la fenêtre « Enregistrer sous », sous un nom lisible en .csv.
      expect(selecteur.ecrits, hasLength(1));
      final ecrit = selecteur.ecrits.single;
      expect(ecrit.type, TypeFichierEnregistre.csv);
      expect(ecrit.nom, startsWith('${EtatStocks.prefixeFichier}_'));
      expect(ecrit.nom, endsWith('.csv'));
      expect(ecrit.octets.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8');
      final csv = ecrit.texte;

      expect(csv, contains('Filtre appliqué : Catégorie : Denrées'));
      expect(csv, contains(EtatStocks.entetes.join(';')));
      // Le riz : stock, seuil, dernier prix, CMP, valeur — des nombres BRUTS.
      expect(
        csv,
        contains(
          'Riz local;Denrées;sac;Magasin;Permanent;10.00;5.00;'
          '1250.5000;1250.5000;12505',
        ),
      );
      // Le sel : du stock sans coût -> valeur « — », pas zéro.
      expect(
        csv,
        contains('Sel;Denrées;sac;Magasin;Permanent;4.00;5.00;—;—;—'),
      );
      // Le journalier : « non suivi », jamais « 0 ».
      expect(
        csv,
        contains('Tomates;Denrées;kg;—;Journalier;non suivi;—;—;—;—'),
      );
      expect(csv, isNot(contains('Béninoise')));
      expect(csv, contains('Aucune écriture comptable n\'est produite'));
      // La phrase fausse (le poste tient une comptabilité depuis le 10/10/2026)
      // ne revient pas.
      expect(csv, isNot(contains('ne tient pas de comptabilité')));
      expect(csv, contains("n'y écrivent aucune sortie"));
      expect(find.byKey(const Key('stocks-export-fait')), findsOneWidget);
    });

    testWidgets('le PDF est offert comme dans la vue, et PRODUIT : un état '
        'A4 enregistré en .pdf, le toast le dit', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester);

      await toucher(tester, const Key('stocks-exporter'));
      await tester.tap(find.text('PDF Officiel A4 Imprimable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(selecteur.ecrits, hasLength(1));
      final ecrit = selecteur.ecrits.single;
      expect(ecrit.type, TypeFichierEnregistre.pdf);
      expect(ecrit.nom, startsWith('${EtatStocks.prefixeFichier}_'));
      expect(ecrit.nom, endsWith('.pdf'));
      expect(ecrit.estUnPdf, isTrue);
      expect(find.byKey(const Key('stocks-export-fait')), findsOneWidget);
    });

    testWidgets('une liste vide se REFUSE : pas de fichier', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester);

      await saisir(tester, const Key('stocks-recherche'), 'introuvable');
      await toucher(tester, const Key('stocks-exporter'));
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(find.text(EtatStocks.refusVide), findsOneWidget);
      expect(selecteur.ecrits, isEmpty);
    });
  });

  group('Les droits : un bouton affiché ne protège rien', () {
    testWidgets('en lecture seule, la création est refusée dans la modale', (
      tester,
    ) async {
      final magasin = await semerPoint('Magasin');
      await monter(tester, niveau: 'L');

      await toucher(tester, const Key('stocks-nouvel-article'));
      await saisir(tester, const Key('article-libelle'), 'Riz');
      await choisir(tester, const Key('article-point'), 'Magasin');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.text(refusEcritureStocks), findsOneWidget);
      expect(await db.select(db.articlesLocal).get(), isEmpty);
      expect(magasin, isNotEmpty);
    });
  });

  group('La fiche de stock, par l’écran Inventaires', () {
    testWidgets('« Par », la rupture forcée et les valeurs exactes', (
      tester,
    ) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      final r = await api().enregistrerMouvement(
        SaisieMouvement(
          articleId: 'riz',
          pointId: magasin,
          type: TypeMouvement.sortie,
          quantite: '14',
          motif: 'Banquet',
          validationRupture: true,
        ),
      );
      expect((r as MouvementEnregistre).mouvement.ruptureForcee, isTrue);

      await monter(tester, ecran: const EcranInventaires());

      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(EcranInventaires)),
      );
      final aujourdhui = DateTime.now();
      conteneur.read(demandeFicheProvider.notifier)
        ..article('riz')
        ..periode(
          DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day),
          DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day),
        );
      await tester.pumpAndSettle();

      expect(texteDe(tester, const Key('fiche-initial')), '0.00 sac');
      expect(texteDe(tester, const Key('fiche-entrees')), '10.00 sac');
      expect(texteDe(tester, const Key('fiche-sorties')), '14.00 sac');
      expect(texteDe(tester, const Key('fiche-theorique')), '-4.00 sac');
      // -4,00 × 1 000 F = -4 000 F.
      expect(texteDe(tester, const Key('fiche-valeur')), '-4 000 FCFA');
      expect(find.byKey(const Key('fiche-incoherente')), findsNothing);

      // La colonne « Par » existe et porte l'auteur ; la note qui disait
      // qu'elle n'était pas rendue a disparu.
      expect(find.text('Par'), findsOneWidget);
      expect(find.text('Aïcha'), findsNWidgets(2));
      expect(find.byKey(const Key('fiche-colonne-par-absente')), findsNothing);
      // La confirmation promettait « tracé dans la fiche » : c'est vrai.
      expect(find.text('Sortie — rupture forcée'), findsOneWidget);
      expect(find.byKey(const Key('fiche-rupture-1')), findsOneWidget);
    });
  });

  group('Le formulaire d’article : les aides de la vue et l’entrée de la fiche', () {
    const aides = [
      "Le petit stock n'est ni décrémenté à la vente, ni inventorié, ni alerté : seule la dépense d'achat est constatée.",
      "Elle valorise le stock d'ouverture et fixe le premier coût moyen pondéré. Sans elle, l'article entre au bilan pour zéro et la variation de stock — donc le résultat — est fausse.",
      "Un paramètre, pas un état : il déclenche l'alerte de sous-stock.",
      "Enregistré comme un MOUVEMENT d'entrée, pas comme une colonne : c'est ce qui le rend visible en fiche de stock.",
      "Point de rattachement principal de l'article, et point d'imputation de son stock d'ouverture. Il ne limite pas le stock : un article peut être détenu en plusieurs endroits, et le total se calcule point par point.",
    ];

    testWidgets('« Nouvel article » rend les CINQ aides, sous leur champ, et '
        'jamais le bloc d’entrée', (tester) async {
      await semerPoint('Magasin');
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-nouvel-article'));

      for (final aide in aides) {
        expect(find.text(aide), findsOneWidget, reason: aide);
      }
      // L'entrée de la fiche n'existe qu'en MODIFICATION.
      expect(find.byKey(const Key('article-bloc-entree')), findsNothing);
      expect(find.text('Faire entrer du stock'), findsNothing);
    });

    testWidgets('en suivi journalier, les aides du stock disparaissent avec '
        'leurs champs', (tester) async {
      await semerPoint('Magasin');
      await monter(tester);

      await toucher(tester, const Key('stocks-nouvel-article'));
      await choisir(
        tester,
        const Key('article-suivi'),
        'Petit stock — acheté au jour le jour (tomates, laitue…)',
      );

      // Le seuil et le stock d'ouverture n'ont pas de sens sans stock tenu.
      expect(find.text(aides[2]), findsNothing);
      expect(find.text(aides[3]), findsNothing);
      // L'aide du suivi, elle, reste.
      expect(find.text(aides[0]), findsOneWidget);
    });

    testWidgets('l’ADMINISTRATEUR fait entrer du stock depuis la fiche : un '
        'MOUVEMENT d’entrée valorisé, jamais une valeur écrasée', (
      tester,
    ) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-modifier-riz'));
      expect(find.byKey(const Key('article-bloc-entree')), findsOneWidget);
      expect(find.text('Faire entrer du stock'), findsOneWidget);
      expect(find.text('Quantité à faire entrer'), findsOneWidget);
      expect(find.text('Point de stockage qui reçoit'), findsOneWidget);
      expect(find.text('Coût unitaire de cette entrée (FCFA)'), findsOneWidget);
      expect(
        texteDe(tester, const Key('article-entree-aide')),
        startsWith('Ajoute au stock, sans jamais l’écraser'),
      );

      await saisir(tester, const Key('article-entree-quantite'), '3');
      await saisir(tester, const Key('article-entree-cout'), '2000');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.byKey(const Key('modale-article')), findsNothing);
      // Le message de la vue (`entree_enregistree`), pas « mis à jour ».
      expect(
        find.text('Entrée enregistrée : 3 sac sur « Riz local ».'),
        findsOneWidget,
      );

      final mouvements = await db.select(db.mouvementsStockLocal).get();
      final entree = mouvements.singleWhere(
        (m) => m.motif == 'Entrée depuis la fiche article',
      );
      expect(entree.typeMouvement, 'entree');
      expect(entree.quantite, 3);
      expect(entree.pointId, magasin);
      expect(entree.utilisateurId, 'u-essai');
      // 2 000 F = 20 000 000 dix-millièmes : l'entrée VALORISE.
      expect(entree.coutUnitaireDixMilliemes, 20000000);
      // 10 + 3 : le stock est la SOMME des mouvements.
      expect(texteDe(tester, const Key('stocks-stock-riz')), '13.00');
    });

    testWidgets('quantité vide : la fiche s’enregistre SANS toucher au '
        'stock, et le dit comme avant', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-modifier-riz'));
      await saisir(tester, const Key('article-seuil'), '7');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.text('Article « Riz local » mis à jour.'), findsOneWidget);
      final mouvements = await db.select(db.mouvementsStockLocal).get();
      expect(
        mouvements,
        hasLength(1),
        reason: 'le seul mouvement : l’ouverture',
      );
    });

    testWidgets('une quantité à zéro n’est pas une entrée : refus de saisie, '
        'rien d’écrit', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-modifier-riz'));
      await saisir(tester, const Key('article-entree-quantite'), '0');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.byKey(const Key('modale-article')), findsOneWidget);
      expect(await db.select(db.mouvementsStockLocal).get(), hasLength(1));
    });

    testWidgets('un poste SANS aucun point : l’entrée est refusée AVANT '
        'd’écrire quoi que ce soit', (tester) async {
      await semerArticle('riz', 'Riz local', ouverture: '', cout: '');
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-modifier-riz'));
      await saisir(tester, const Key('article-entree-quantite'), '3');
      await saisir(tester, const Key('article-libelle'), 'Riz local bis');
      await toucher(tester, const Key('article-enregistrer'));

      expect(find.byKey(const Key('article-refus')), findsOneWidget);
      expect(
        find.text(
          'Choisissez le point de stockage qui reçoit la marchandise : une '
          'quantité sans destination n’est pas une livraison.',
        ),
        findsOneWidget,
      );
      // Ni la fiche ni le stock n'ont bougé : la vue enregistrerait d'abord la
      // fiche puis refuserait l'entrée.
      final articles = await db.select(db.articlesLocal).get();
      expect(articles.single.libelle, 'Riz local');
      expect(await db.select(db.mouvementsStockLocal).get(), isEmpty);
    });

    testWidgets('un MAGASINIER ne voit pas le bloc, et l’API le refuse '
        'quand même (l’ouverture d’un bloc ne protège rien)', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await monter(tester);

      await toucher(tester, const Key('stocks-modifier-riz'));
      expect(find.byKey(const Key('article-bloc-entree')), findsNothing);
      expect(find.text('Faire entrer du stock'), findsNothing);

      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(EcranStocks)),
      );
      final refus = await conteneur
          .read(stocksApiProvider)
          .faireEntrerDepuisFiche(
            articleId: 'riz',
            pointId: magasin,
            quantite: '3',
          );
      expect(refus, isA<MouvementRefuse>());
      expect(
        (refus as MouvementRefuse).motif,
        startsWith('Faire entrer du stock depuis la fiche article est réservé'),
      );
      expect(await db.select(db.mouvementsStockLocal).get(), hasLength(1));
    });

    testWidgets('un article JOURNALIER : pas de bloc d’entrée, même pour '
        'l’administrateur', (tester) async {
      await semerPoint('Magasin');
      await semerArticle(
        'tomate',
        'Tomates',
        suivi: SuiviArticle.journalier,
        unite: 'kg',
      );
      await monter(tester, role: 'administrateur');

      await toucher(tester, const Key('stocks-modifier-tomate'));
      expect(find.byKey(const Key('article-bloc-entree')), findsNothing);
    });
  });

  group('La pagination de la vue : « Précédent », « Suivant »', () {
    Future<void> semer(int n) async {
      final magasin = await semerPoint('Magasin');
      for (var i = 0; i < n; i++) {
        final id = 'a${i.toString().padLeft(2, '0')}';
        await semerArticle(id, 'Article $id', pointId: magasin);
      }
    }

    testWidgets('25 articles par page, un pied « 1 – 25 / 30 », et les deux '
        'boutons aux mots de la vue', (tester) async {
      await semer(30);
      await monter(tester, taille: const Size(1600, 4000));

      expect(find.byKey(const Key('stocks-ligne-a00')), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-a24')), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-a25')), findsNothing);
      // Le décompte de l'en-tête est le TOTAL filtré, pas la page.
      expect(find.text('30 article(s)'), findsOneWidget);
      expect(
        texteDe(tester, const Key('stocks-pagination-decompte')),
        '1 – 25 / 30',
      );
      expect(find.text('« Précédent'), findsOneWidget);
      expect(find.text('Suivant »'), findsOneWidget);
      // « Précédent » est grisé en page 1.
      expect(
        tester
            .widget<BoutonStandard>(
              find.byKey(const Key('stocks-pagination-precedent')),
            )
            .onPressed,
        isNull,
      );

      await toucher(tester, const Key('stocks-pagination-suivant'));

      expect(find.byKey(const Key('stocks-ligne-a24')), findsNothing);
      expect(find.byKey(const Key('stocks-ligne-a25')), findsOneWidget);
      expect(find.byKey(const Key('stocks-ligne-a29')), findsOneWidget);
      expect(
        texteDe(tester, const Key('stocks-pagination-decompte')),
        '26 – 30 / 30',
      );
      expect(
        tester
            .widget<BoutonStandard>(
              find.byKey(const Key('stocks-pagination-suivant')),
            )
            .onPressed,
        isNull,
        reason: '« Suivant » est grisé sur la dernière page',
      );

      await toucher(tester, const Key('stocks-pagination-precedent'));
      expect(find.byKey(const Key('stocks-ligne-a00')), findsOneWidget);
    });

    testWidgets('un filtre ramène à la page 1 ; une seule page : aucun pied '
        '(`hasPages()`)', (tester) async {
      await semer(30);
      await monter(tester, taille: const Size(1600, 4000));

      await toucher(tester, const Key('stocks-pagination-suivant'));
      expect(find.byKey(const Key('stocks-ligne-a25')), findsOneWidget);

      await saisir(tester, const Key('stocks-recherche'), 'Article a2');
      // « Article a2… » : a20 à a29, dix articles, une page.
      expect(find.text('10 article(s)'), findsOneWidget);
      expect(find.byKey(const Key('stocks-pagination')), findsNothing);
      expect(find.byKey(const Key('stocks-ligne-a20')), findsOneWidget);
    });
  });

  group(
    'Ce que la vue offre pour ARCHIVER, et que ce poste dit ne pas tenir',
    () {
      testWidgets('aucune case, aucun « Supprimer » : la note NOMME les gestes '
          'avec les mots de la vue', (tester) async {
        final magasin = await semerPoint('Magasin');
        await semerArticle('riz', 'Riz local', pointId: magasin);
        await monter(tester, role: 'administrateur');

        // Rien n'est offert qui n'écrirait rien.
        expect(find.byType(Checkbox), findsNothing);
        expect(find.text('Supprimer'), findsNothing);

        final note = texteDe(tester, const Key('stocks-limite-archivage'));
        for (final mot in const [
          'Supprimer',
          'Tout sélectionner',
          'Sélectionner cette ligne',
          'sélectionné(s)',
        ]) {
          expect(note, contains(mot));
        }
        // Et elle dit POURQUOI : aucune colonne « actif » locale.
        expect(note, contains('colonne « actif »'));
      });

      testWidgets('le schéma local n’a toujours aucune colonne `actif` sur les '
          'articles : le jour où elle naît, ce test rougit et l’archivage se '
          'porte', (tester) async {
        final colonnes =
            (await db.customSelect('PRAGMA table_info(articles_local)').get())
                .map((r) => r.read<String>('name'))
                .toSet();
        expect(colonnes, isNot(contains('actif')));
      });
    },
  );

  group('Les infobulles de « — » : la phrase de la vue ne ment pas ici', () {
    const phraseDeLaVue =
        "Jamais réceptionné : ni point de rattachement, ni prix d'achat. Les deux se posent à la première entrée de stock.";

    testWidgets('l’article sans point ni prix dit ce qui manque, et jamais '
        '« les deux se posent à la première entrée »', (tester) async {
      await semerPoint('Magasin');
      await semerArticle('riz', 'Riz local');
      await monter(tester);

      final messages = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      expect(messages, contains(raisonSansPoint));
      expect(messages, contains(raisonSansPrixAchat));
      for (final m in messages) {
        expect(m, isNot(contains('Les deux se posent')));
      }
      expect(find.text(phraseDeLaVue), findsNothing);
    });

    test(
      'la vue DIT encore la phrase, et le serveur ne pose toujours pas le '
      'point à la première entrée : le jour où l’un change, ce test rougit',
      () {
        final lang = VueBlade.fichier(
          'lang/fr/stocks_pwa.php',
          role: 'les libellés de l’écran Stocks',
        );
        expect(
          lang
              .replaceAll("\\'", "'")
              .replaceAll(RegExp(r"'\s*\n\s*\.\s*'"), ''),
          contains(phraseDeLaVue),
        );

        final moteur = VueBlade.fichier(
          'app/Domain/Stocks/Services/MouvementStockService.php',
          role: 'le moteur des mouvements de stock',
        );
        // La phrase promet que la première entrée pose LE POINT : le moteur du
        // serveur n'écrit jamais `point_stockage_id`.
        expect(moteur, isNot(contains('point_stockage_id')));
        expect(moteur, contains('function entree'));
      },
    );
  });

  group('Inventaires : « Tous les articles », la fiche consolidée de la vue', () {
    Future<void> semerDeuxArticles() async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1000',
      );
      await semerArticle(
        'biere',
        'Bière',
        pointId: magasin,
        ouverture: '5',
        cout: '500',
        unite: 'casier',
      );
      final r = await api().enregistrerMouvement(
        SaisieMouvement(
          articleId: 'riz',
          pointId: magasin,
          type: TypeMouvement.sortie,
          quantite: '4',
          motif: 'Banquet',
        ),
      );
      expect(r, isA<MouvementEnregistre>(), reason: '$r');
    }

    testWidgets('la vue OUVRE sur « Tous les articles », période de trente '
        'jours : comptes, valeur et détail réels', (tester) async {
      await semerDeuxArticles();
      await monter(tester, ecran: const EcranInventaires());

      // Aucun article choisi : la valeur vide du filtre est un CHOIX.
      expect(
        find.byKey(const Key('fiche-consolidee-articles')),
        findsOneWidget,
      );
      expect(texteDe(tester, const Key('fiche-consolidee-articles')), '2');
      expect(texteDe(tester, const Key('fiche-consolidee-mouvementes')), '2');
      // Trois mouvements : deux ouvertures et une sortie.
      expect(texteDe(tester, const Key('fiche-consolidee-mouvements')), '3');
      expect(
        texteDe(tester, const Key('fiche-consolidee-nombre')),
        '3 mouvement(s)',
      );
      // Riz : 6 × 1 000 F ; bière : 5 × 500 F ; seule la VALEUR se totalise.
      expect(
        texteDe(tester, const Key('fiche-consolidee-valeur')),
        '8 500 FCFA',
      );

      // La phrase d'aide et les huit colonnes de la vue.
      expect(
        find.text(
          "Chaque ligne garde l'unite et le solde de son propre article : les quantites d'articles differents ne s'additionnent pas.",
        ),
        findsOneWidget,
      );
      for (final c in const [
        'DATE',
        'ARTICLE',
        'TYPE',
        'MOTIF',
        'ENTRÉE',
        'SORTIE',
        'SOLDE',
        'UTILISATEUR',
      ]) {
        expect(find.text(c), findsOneWidget, reason: c);
      }

      // Une ligne : l'entrée en « + », la sortie avec le signe MOINS du maître
      // (U+2212), le solde de SON article avec SON unité.
      expect(find.text('+10.00 sac'), findsOneWidget);
      expect(find.text('+5.00 casier'), findsOneWidget);
      expect(find.text('\u{2212}4.00 sac'), findsOneWidget);
      expect(find.text('6.00 sac'), findsOneWidget);
      expect(find.text('5.00 casier'), findsOneWidget);
      // Le « qui » est CONNU ici (la vue rend un tiret).
      expect(find.text('Aïcha'), findsNWidgets(3));
      // La date de la vue : `d/m/Y H:i`.
      final aujourdhui = DateTime.now();
      final jour =
          '${aujourdhui.day.toString().padLeft(2, '0')}/'
          '${aujourdhui.month.toString().padLeft(2, '0')}/${aujourdhui.year}';
      expect(find.textContaining(jour), findsNWidgets(3));
      expect(
        find.byKey(const Key('fiche-consolidee-incoherente')),
        findsNothing,
      );
    });

    testWidgets('« Exporter » sous « Tous les articles » : le refus de la vue '
        '(un document de fiche est établi pour UN article)', (tester) async {
      await semerDeuxArticles();
      await monter(tester, ecran: const EcranInventaires());

      await toucher(tester, const Key('fiche-exporter'));

      expect(
        texteDe(tester, const Key('fiche-export-absente')),
        startsWith('Choisissez un article : le document de fiche de stock'),
      );
      // Aucune modale de format ne s'est ouverte.
      expect(find.text('Exporter — Fiche de stock'), findsNothing);
    });

    testWidgets('choisir un article ouvre SA fiche, et « Tous les articles » '
        'revient au consolidé', (tester) async {
      await semerDeuxArticles();
      await monter(tester, ecran: const EcranInventaires());

      await choisir(tester, const Key('fiche-article'), 'Riz local');
      expect(find.byKey(const Key('fiche-consolidee-valeur')), findsNothing);
      expect(texteDe(tester, const Key('fiche-theorique')), '6.00 sac');
      // Le libellé de la vue pour la valeur de la fiche d'un article.
      expect(find.text('VALEUR DU STOCK THÉORIQUE'), findsOneWidget);

      await choisir(tester, const Key('fiche-article'), 'Tous les articles');
      expect(find.byKey(const Key('fiche-theorique')), findsNothing);
      expect(texteDe(tester, const Key('fiche-consolidee-articles')), '2');
    });

    testWidgets('sans article : le consolidé à zéro, la phrase de la vue, et '
        'le sélecteur dit où créer le premier', (tester) async {
      await monter(tester, ecran: const EcranInventaires());

      expect(texteDe(tester, const Key('fiche-consolidee-articles')), '0');
      expect(texteDe(tester, const Key('fiche-consolidee-valeur')), '0 FCFA');
      expect(find.text('Aucun mouvement sur cette période.'), findsOneWidget);
      expect(
        find.text("Créez d'abord un article dans l'écran Stocks."),
        findsOneWidget,
      );
    });

    testWidgets('un article qui n’est plus au référentiel : « Aucun article » '
        'et son détail, pas une phrase d’erreur', (tester) async {
      await semerDeuxArticles();
      await monter(tester, ecran: const EcranInventaires());

      final conteneur = ProviderScope.containerOf(
        tester.element(find.byType(EcranInventaires)),
      );
      conteneur.read(demandeFicheProvider.notifier).article('fantome');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fiche-aucun-article')), findsOneWidget);
      expect(find.text('Aucun article'), findsOneWidget);
      expect(
        find.text("Créez d'abord un article dans l'écran Stocks."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('fiche-refus')), findsNothing);
    });

    testWidgets('une fiche INCOHÉRENTE est NOMMÉE dans le bandeau, avant les '
        'chiffres', (tester) async {
      await monter(
        tester,
        ecran: const EcranInventaires(),
        surcharges: [
          ficheConsolideeProvider.overrideWith(
            (ref) async => const FicheConsolideeRecue(
              FicheConsolidee(
                debut: '2026-10-01',
                fin: '2026-10-30',
                pointId: null,
                articles: 2,
                articlesAvecMouvement: 0,
                valeurStockTheorique: '0',
                incoherents: ['Riz local', 'Bière'],
                lignes: [],
              ),
            ),
          ),
        ],
      );

      final bandeau = find.byKey(const Key('fiche-consolidee-incoherente'));
      expect(bandeau, findsOneWidget);
      final texte = tester
          .widget<Text>(
            find.descendant(of: bandeau, matching: find.byType(Text)),
          )
          .textSpan!
          .toPlainText();
      expect(
        texte,
        'Incohérence détectée. Articles concernes : Riz local, Bière.',
      );
    });

    testWidgets('la fiche d’UN article incohérente dit les mots de la vue', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 1600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.clair,
            home: Scaffold(
              body: SingleChildScrollView(
                child: VueFicheStock(
                  pointLibelle: null,
                  fiche: FicheStock(
                    article: const ArticleFiche(
                      id: 'riz',
                      libelle: 'Riz local',
                      unite: 'sac',
                      cmp: '1000.0000',
                    ),
                    debut: '2026-10-01',
                    fin: '2026-10-30',
                    stockInitial: '0.00',
                    entrees: '10.00',
                    sorties: '0.00',
                    pertes: '0.00',
                    regularisations: '0.00',
                    stockTheorique: '9.00',
                    valeurStockTheorique: '9000',
                    coherent: false,
                    pointId: null,
                    lignes: const [],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final texte = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const Key('fiche-incoherente')),
              matching: find.byType(Text),
            ),
          )
          .textSpan!
          .toPlainText();
      expect(
        texte,
        'Incohérence détectée. Le solde progressif ne retombe pas sur le stock '
        'théorique. Un mouvement a été écrit hors du moteur de stock — ce '
        'document ne doit pas servir de justificatif.',
      );
      expect(
        find.textContaining('Aucun mouvement sur cette période.'),
        findsOneWidget,
      );
    });
  });

  group('Inventaires : l’inventaire physique est REFUSÉ, et l’écran le dit', () {
    testWidgets('le cycle liste les points, « Lancer l’inventaire » est GRISÉ '
        'à sa place, la note nomme les gestes de la vue', (tester) async {
      await semerPoint('Bar');
      await semerPoint('Magasin');
      await monter(tester, ecran: const EcranInventaires());
      await toucher(tester, const Key('inventaires-onglet-inventaire'));

      // Une ligne par point, avec « non définie » (aucune périodicité n'est
      // enregistrée nulle part) deux fois : périodicité et état.
      expect(find.text('Bar'), findsOneWidget);
      expect(find.text('Magasin'), findsOneWidget);
      expect(find.text('non définie'), findsNWidgets(4));

      // Le bouton existe, au libellé de la vue, et n'a AUCUN geste.
      final boutons = tester
          .widgetList<BoutonStandard>(find.byType(BoutonStandard))
          .where((b) => b.libelle == "Lancer l'inventaire")
          .toList();
      expect(boutons, hasLength(2));
      expect(boutons.every((b) => b.onPressed == null), isTrue);

      final note = texteDe(tester, const Key('inventaire-non-porte'));
      for (final mot in const [
        'Lancer l’inventaire',
        'Inventaire du',
        'article(s) comptés',
        'écart(s)',
        'impact valorisé',
        'à compter',
        'Écart valorisé',
        'Enregistrer le comptage',
        'Exporter — Articles en stock',
        'Clôturer et régulariser',
        'Les inventaires clôturés et leurs régularisations apparaîtront ici.',
      ]) {
        expect(note, contains(mot), reason: mot);
      }
      // Et la RAISON : ni table d'inventaire ni lignes de comptage.
      expect(note, contains('ni table d’inventaire'));
    });

    testWidgets('sans point : la phrase de la vue, et aucun bouton', (
      tester,
    ) async {
      await monter(tester, ecran: const EcranInventaires());
      await toucher(tester, const Key('inventaires-onglet-inventaire'));

      expect(
        find.text(
          "Aucun point de stockage n'est défini : un inventaire porte sur un point, il ne peut pas être ouvert sans lui.",
        ),
        findsOneWidget,
      );
      expect(find.text("Lancer l'inventaire"), findsNothing);
    });

    testWidgets('l’historique ne dit NI « aucun » NI « apparaîtront ici » '
        'comme une promesse : il dit que ce poste n’en tient pas', (
      tester,
    ) async {
      await monter(tester, ecran: const EcranInventaires());
      await toucher(tester, const Key('inventaires-onglet-historique'));

      final note = texteDe(tester, const Key('historique-non-porte'));
      expect(note, contains('ne peut pas se tenir ici'));
      // Aucune ligne n'est inventée, aucun « 0 » non plus.
      expect(find.text('0'), findsNothing);
    });

    test('le schéma local n’a toujours ni table d’inventaire ni lignes de '
        'comptage : le jour où elles naissent, ce test rougit et l’inventaire '
        'se porte', () async {
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table'",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(
        tables.where((t) => t.contains('inventaire')),
        isEmpty,
        reason: 'une table d’inventaire est née : portez l’inventaire physique',
      );
    });
  });
}
