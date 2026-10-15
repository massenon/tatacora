import 'dart:convert';
import 'dart:io';

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
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/import_articles.dart';
import 'package:tatacora_flutter/features/stocks/impression/etat_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_inventaires.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/stocks/presentation/providers_stocks.dart';

/// L'écran Gestion des Stocks, monté sur une **vraie base locale** — le chemin
/// que l'exploitant emprunte : clic, modale, `StocksApi`, `StocksDao`, base,
/// relecture. Aucun faux au milieu (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dossier;
  late List<String> fichiersEcrits;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dossier = await Directory.systemTemp.createTemp('tatacora_stocks_');
    fichiersEcrits = [];

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
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<void> monter(
    WidgetTester tester, {
    String niveau = 'C',
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
      role: 'magasinier',
      droits: droits,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild((ref, notifier) => session),
          // Un test de widget n'a pas de greffon natif : le fichier est écrit
          // dans un dossier temporaire, au même format que l'action réelle.
          exporterStocksProvider.overrideWithValue((etat) async {
            final f = File(
              '${dossier.path}/export-${fichiersEcrits.length}.csv',
            );
            // SYNCHRONE : l'E/S asynchrone ne s'achève pas sous le temps
            // simulé d'un test de widget, et le test attendrait un fichier
            // qui n'arrive jamais.
            f.writeAsBytesSync(etat.csvOctets());
            fichiersEcrits.add(f.path);
            return f.path;
          }),
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
      final selecteur = _SelecteurEssai(
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
      await monter(
        tester,
        surcharges: [selecteurFichiersProvider.overrideWithValue(selecteur)],
      );

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
      expect(selecteur.nomEcrit, TextesImportArticles.nomModele);
      // `utf8.decode` retire le BOM : on compare les OCTETS.
      expect(selecteur.octetsEcrits, modeleImportArticlesOctets());
      expect(selecteur.octetsEcrits!.take(3), [0xEF, 0xBB, 0xBF]);
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

      expect(fichiersEcrits, hasLength(1));
      final octets = File(fichiersEcrits.single).readAsBytesSync();
      expect(octets.take(3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8');
      final csv = File(fichiersEcrits.single).readAsStringSync();

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

    testWidgets('le PDF est offert comme dans la vue, et REFUSE avec son '
        'message', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester);

      await toucher(tester, const Key('stocks-exporter'));
      await tester.tap(find.text('PDF Officiel A4 Imprimable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(find.text(TextesStocks.pdfNonProduit), findsOneWidget);
      expect(fichiersEcrits, isEmpty);
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
      expect(fichiersEcrits, isEmpty);
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
}

/// Le sélecteur natif remplacé : un fichier « ouvert » fourni, et ce qui
/// aurait été écrit par « Enregistrer sous » retenu pour l'assertion.
final class _SelecteurEssai implements SelecteurFichiers {
  _SelecteurEssai({this.lu});

  final FichierLu? lu;
  String? nomEcrit;
  List<int>? octetsEcrits;

  @override
  Future<FichierLu?> ouvrirCsv() async => lu;

  @override
  Future<String?> enregistrerSous({
    required String nomSuggere,
    required List<int> octets,
  }) async {
    nomEcrit = nomSuggere;
    octetsEcrits = octets;
    return 'C:/essai/$nomSuggere';
  }
}
