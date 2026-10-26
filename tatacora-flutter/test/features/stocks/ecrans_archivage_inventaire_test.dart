import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_inventaire.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';
import 'package:tatacora_flutter/features/stocks/impression/etat_inventaire.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_inventaires.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../../support/selecteur_essai.dart';

/// Les deux écrans de M6 qui écrivent désormais ce qu'ils ne savaient pas
/// écrire : l'ARCHIVAGE des articles (Gestion des Stocks) et l'INVENTAIRE
/// physique (Inventaires & Fiches de stock), montés sur une VRAIE base locale —
/// clic, modale, `StocksApi`, `StocksDao`, base, file d'envoi, relecture.
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

  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    String role = 'administrateur',
    String niveau = 'C',
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1400)
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
          ...selecteur.surcharges,
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

  Future<String> semerPoint(String libelle) async =>
      ((await api().creerPoint(libelle: libelle)) as PointEnregistre).point.id;

  Future<void> semerArticle(
    String id,
    String libelle, {
    String? pointId,
    String? ouverture,
    String? cout,
  }) async {
    final r = await api().enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: 'Denrées',
        uniteMesure: 'sac',
        seuilAlerte: '5',
        suivi: SuiviArticle.permanent,
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

  String texteDe(WidgetTester tester, Key cle) =>
      (tester.widget(find.byKey(cle)) as Text).data!;

  String texteRiche(WidgetTester tester, Key cle) =>
      (tester.widget(find.byKey(cle)) as Text).textSpan!.toPlainText();

  Future<bool?> actif(String id) async => (await (db.select(
    db.articlesLocal,
  )..where((a) => a.id.equals(id))).getSingle()).actif;

  Future<List<OperationSync>> operations(TableSynchronisee table) =>
      OperationsSyncDao(db).operations(table: table);

  /* ==================================================================== */
  /* L'archivage — Gestion des Stocks                                       */
  /* ==================================================================== */

  group('Archiver depuis la ligne', () {
    testWidgets('« Supprimer » -> la modale de la vue -> « Supprimer '
        'définitivement » : l’article est ARCHIVÉ, marqué, restaurable, et '
        'l’archivage part dans la file', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester, const EcranStocks());

      await toucher(tester, const Key('stocks-supprimer-riz'));

      // La modale de la vue : titre, question (le nom), rappel, deux boutons.
      expect(find.text('Confirmer la suppression'), findsOneWidget);
      expect(
        texteRiche(tester, const Key('achats-archivage-question')),
        'Voulez-vous archiver Riz local ?',
      );
      expect(
        texteRiche(tester, const Key('achats-archivage-rappel')),
        "L'élément part aux archives et reste restaurable — rien n'est effacé.",
      );
      expect(find.text('Supprimer définitivement'), findsOneWidget);
      expect(
        await actif('riz'),
        isTrue,
        reason: 'rien tant qu’on ne confirme pas',
      );

      await toucher(tester, const Key('achats-archivage-confirmer'));

      expect(await actif('riz'), isFalse);
      // Rien n'est effacé : l'article reste au référentiel, marqué.
      expect(find.byKey(const Key('stocks-ligne-riz')), findsOneWidget);
      expect(find.byKey(const Key('stocks-archive-riz')), findsOneWidget);
      expect(find.text('Archivé'), findsOneWidget);
      expect(
        texteDe(tester, const Key('stocks-archivage-succes')),
        'Article archivé — il reste restaurable.',
      );
      // « Supprimer » cède la place à « Restaurer ».
      expect(find.byKey(const Key('stocks-supprimer-riz')), findsNothing);
      expect(find.byKey(const Key('stocks-restaurer-riz')), findsOneWidget);

      final envoyees = await operations(TableSynchronisee.articles);
      final archivage = envoyees.last;
      expect(archivage.type, TypeOperationSync.modification);
      expect(archivage.entiteId, 'riz');
      expect(jsonDecode(archivage.payload), {'actif': false});
    });

    testWidgets('annuler n’archive RIEN', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester, const EcranStocks());

      await toucher(tester, const Key('stocks-supprimer-riz'));
      await toucher(tester, const Key('achats-archivage-annuler'));

      expect(find.text('Confirmer la suppression'), findsNothing);
      expect(await actif('riz'), isTrue);
    });

    testWidgets('un article qui a du stock : la modale est BLOQUÉE — « '
        'Archivage impossible », la phrase du verrou, AUCUN bouton de '
        'confirmation — et rien n’est écrit', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle(
        'riz',
        'Riz local',
        pointId: magasin,
        ouverture: '10',
        cout: '1250',
      );
      await monter(tester, const EcranStocks());

      await toucher(tester, const Key('stocks-supprimer-riz'));

      expect(find.text('Archivage impossible'), findsOneWidget);
      // Le motif porte le NOM de l'article (« Riz local — … »), comme le serveur.
      expect(
        find.text('Riz local — ${MessagesStock.verrouStock('10.00')}'),
        findsOneWidget,
      );
      // Le bouton DISPARAÎT (il n'est pas grisé) : le laisser visible et inerte
      // laisserait croire à une panne.
      expect(find.byKey(const Key('achats-archivage-confirmer')), findsNothing);
      expect(find.text('Supprimer définitivement'), findsNothing);

      await toucher(tester, const Key('achats-archivage-annuler'));
      expect(await actif('riz'), isTrue);
      expect(await operations(TableSynchronisee.articles), hasLength(1));
    });
  });

  group('Archiver une sélection', () {
    testWidgets('« Tout sélectionner » -> la barre « N sélectionné(s) » -> '
        'lot PARTIEL : la modale annonce combien resteront, seuls les libres '
        'partent', (tester) async {
      final magasin = await semerPoint('Magasin');
      await semerArticle('a', 'Ananas');
      await semerArticle('b', 'Beurre', pointId: magasin, ouverture: '3');
      await semerArticle('c', 'Céleri');
      await monter(tester, const EcranStocks());

      expect(find.byKey(const Key('stocks-selection')), findsNothing);
      await toucher(tester, const Key('stocks-tout'));

      expect(
        texteRiche(tester, const Key('stocks-selection-compte')),
        '3 sélectionné(s)',
      );
      expect(find.text('Supprimer'), findsWidgets);

      await toucher(tester, const Key('stocks-selection-supprimer'));

      // Le lot : 2 partent (le nombre, pas le nom), 1 reste, avec SON motif.
      expect(
        texteRiche(tester, const Key('achats-archivage-question')),
        'Voulez-vous archiver les 2 élément(s) sélectionnés ?',
      );
      expect(
        texteDe(tester, const Key('achats-archivage-conserves')),
        '1 élément(s) seront conservés : ils sont engagés ailleurs.',
      );
      expect(
        find.text('Beurre — ${MessagesStock.verrouStock('3.00')}'),
        findsOneWidget,
      );

      await toucher(tester, const Key('achats-archivage-confirmer'));

      expect(await actif('a'), isFalse);
      expect(await actif('b'), isTrue);
      expect(await actif('c'), isFalse);
      expect(
        texteDe(tester, const Key('stocks-archivage-succes')),
        '2 articles archivés — ils restent restaurables.',
      );
      // La sélection est vidée.
      expect(find.byKey(const Key('stocks-selection')), findsNothing);
    });

    testWidgets('cocher une ligne, puis changer de filtre : la sélection est '
        'REMISE À ZÉRO — « Supprimer » ne porte jamais sur des lignes que '
        'l’écran ne montre plus', (tester) async {
      await semerArticle('a', 'Ananas');
      await semerArticle('b', 'Beurre');
      await monter(tester, const EcranStocks());

      await toucher(tester, const Key('stocks-case-a'));
      expect(find.byKey(const Key('stocks-selection')), findsOneWidget);

      await saisir(tester, const Key('stocks-recherche'), 'Beurre');
      expect(find.byKey(const Key('stocks-selection')), findsNothing);
      expect(find.byKey(const Key('stocks-ligne-a')), findsNothing);
      expect(find.byKey(const Key('stocks-ligne-b')), findsOneWidget);
    });

    testWidgets('la croix de la barre efface la sélection', (tester) async {
      await semerArticle('a', 'Ananas');
      await monter(tester, const EcranStocks());

      await toucher(tester, const Key('stocks-case-a'));
      await toucher(tester, const Key('stocks-selection-effacer'));
      expect(find.byKey(const Key('stocks-selection')), findsNothing);
    });
  });

  group('Restaurer', () {
    testWidgets('« Restaurer » remet l’article actif et le dit — hors de la '
        'règle d’archivage : un magasinier sans la bascule le peut', (
      tester,
    ) async {
      await semerArticle('riz', 'Riz local');
      await StocksDao(db).archiverArticle('riz');
      await monter(tester, const EcranStocks(), role: 'magasinier');

      // Ni case ni « Supprimer » pour lui…
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byKey(const Key('stocks-supprimer-riz')), findsNothing);
      // …mais « Restaurer » est là.
      expect(find.byKey(const Key('stocks-archive-riz')), findsOneWidget);
      await toucher(tester, const Key('stocks-restaurer-riz'));

      expect(await actif('riz'), isTrue);
      expect(
        texteDe(tester, const Key('stocks-restaure')),
        'Article « Riz local » restauré.',
      );
      expect(find.byKey(const Key('stocks-archive-riz')), findsNothing);
      final derniere = (await operations(TableSynchronisee.articles)).last;
      expect(jsonDecode(derniere.payload), {'actif': true});
    });
  });

  group('La règle d’archivage est UNE, reçue par l’écran', () {
    testWidgets('la bascule « Suppression d’un enregistrement » OUVERTE donne '
        'au magasinier les cases et « Supprimer »', (tester) async {
      await semerArticle('riz', 'Riz local');
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: 'activation_suppression',
              valeur: 'true',
              modifieLe: DateTime(2026, 10, 21),
            ),
          );
      await monter(tester, const EcranStocks(), role: 'magasinier');

      expect(find.byKey(const Key('stocks-case-riz')), findsOneWidget);
      expect(find.byKey(const Key('stocks-supprimer-riz')), findsOneWidget);
    });

    testWidgets('en lecture seule, le droit d’écrire manque : ni case, ni '
        '« Supprimer »', (tester) async {
      await semerArticle('riz', 'Riz local');
      await monter(tester, const EcranStocks(), niveau: 'L');

      expect(find.byType(Checkbox), findsNothing);
      expect(find.byKey(const Key('stocks-supprimer-riz')), findsNothing);
    });
  });

  /* ==================================================================== */
  /* L'inventaire physique                                                  */
  /* ==================================================================== */

  Future<String> jeuInventaire() async {
    final magasin = await semerPoint('Magasin');
    await semerArticle(
      'riz',
      'Riz local',
      pointId: magasin,
      ouverture: '10',
      cout: '1250',
    );
    await semerArticle('huile', 'Huile', pointId: magasin, ouverture: '4');
    return magasin;
  }

  Future<void> lancer(WidgetTester tester, String point) async {
    await toucher(tester, const Key('inventaires-onglet-inventaire'));
    await toucher(tester, Key('inventaire-cycle-$point-lancer'));
  }

  Future<void> compter(WidgetTester tester, String article, String q) async {
    await toucher(tester, Key('inventaire-compter-$article'));
    await saisir(tester, const Key('comptage-quantite'), q);
    await toucher(tester, const Key('comptage-enregistrer'));
  }

  group('Ouvrir, compter', () {
    testWidgets('« Lancer l’inventaire » ouvre la feuille : le titre, le '
        'décompte, UN article par ligne « à compter » avec son théorique '
        'du point', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      expect(
        texteDe(tester, const Key('inventaire-ouvert')),
        'Inventaire ouvert — 2 article(s) à compter.',
      );
      expect(
        texteDe(tester, const Key('inventaire-titre')),
        'Inventaire du ${formaterDate(DateTime.now())} — Magasin',
      );
      expect(
        texteRiche(tester, const Key('inventaire-resume')),
        '0 / 2 article(s) comptés · 0 écart(s) · impact valorisé 0 FCFA',
      );
      // Le cycle a disparu : une seule étape à la fois.
      expect(find.byKey(Key('inventaire-cycle-$magasin-lancer')), findsNothing);
      expect(find.text('à compter'), findsNWidgets(2));
      expect(texteDe(tester, const Key('inventaire-theorique-riz')), '10.00');
      expect(texteDe(tester, const Key('inventaire-theorique-huile')), '4.00');
      expect(texteDe(tester, const Key('inventaire-ecart-riz')), '—');
      // Ouvrir n'écrit RIEN : ni inventaire, ni opération.
      expect(await db.select(db.inventairesLocal).get(), isEmpty);
      expect(await operations(TableSynchronisee.inventaires), isEmpty);
      // Et l'écran dit ce que cela coûte.
      expect(
        texteDe(tester, const Key('inventaire-en-memoire')),
        TextesInventaires.comptageEnMemoire,
      );
    });

    testWidgets('compter un article : la modale de la vue, puis le compté, '
        'l’écart et sa valeur au coût moyen, et le résumé', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      await toucher(tester, const Key('inventaire-compter-riz'));
      expect(find.text('Enregistrer le comptage'), findsNWidgets(2));
      expect(find.text('Riz local'), findsWidgets);
      await saisir(tester, const Key('comptage-quantite'), '12');
      await toucher(tester, const Key('comptage-enregistrer'));

      expect(
        texteDe(tester, const Key('inventaire-comptage-fait')),
        'Comptage de « Riz local » enregistré.',
      );
      expect(find.byKey(const Key('modale-comptage')), findsNothing);
      expect(texteDe(tester, const Key('inventaire-ecart-riz')), '+2.00');
      expect(
        texteDe(tester, const Key('inventaire-valorise-riz')),
        '2 500 FCFA',
      );
      expect(
        texteRiche(tester, const Key('inventaire-resume')),
        '1 / 2 article(s) comptés · 1 écart(s) · impact valorisé 2 500 FCFA',
      );
      // Toujours rien d'écrit en base.
      expect(await db.select(db.inventairesLocal).get(), isEmpty);
    });

    testWidgets('un second comptage ÉCRASE le premier (correction de saisie) ; '
        'un manquant est négatif, rouge et valorisé en négatif', (
      tester,
    ) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      await compter(tester, 'riz', '12');
      await compter(tester, 'riz', '8');

      expect(texteDe(tester, const Key('inventaire-ecart-riz')), '-2.00');
      expect(
        texteDe(tester, const Key('inventaire-valorise-riz')),
        '-2 500 FCFA',
      );
      expect(
        texteRiche(tester, const Key('inventaire-resume')),
        '1 / 2 article(s) comptés · 1 écart(s) · impact valorisé -2 500 FCFA',
      );
    });

    testWidgets('un écart sans coût connu n’est pas valorisé : « — », et le '
        'résumé le dit', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      await compter(tester, 'huile', '3'); // 4 attendus, aucun coût

      expect(texteDe(tester, const Key('inventaire-ecart-huile')), '-1.00');
      expect(texteDe(tester, const Key('inventaire-valorise-huile')), '—');
      expect(
        texteDe(tester, const Key('inventaire-sans-cout')),
        TextesInventaires.ecartsSansCout(1),
      );
    });

    testWidgets('une saisie vide ou négative est refusée DANS la modale, avec '
        'les phrases du serveur — la feuille ne bouge pas', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      await toucher(tester, const Key('inventaire-compter-riz'));
      await toucher(tester, const Key('comptage-enregistrer'));
      expect(find.text(MessagesStock.quantitePositive), findsOneWidget);

      await saisir(tester, const Key('comptage-quantite'), '-3');
      await toucher(tester, const Key('comptage-enregistrer'));
      expect(
        find.descendant(
          of: find.byKey(const Key('comptage-refus')),
          matching: find.text(MessagesStock.quantiteNegative),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modale-comptage')), findsOneWidget);

      await toucher(tester, const Key('modale-stock-annuler'));
      expect(texteDe(tester, const Key('inventaire-ecart-riz')), '—');
    });
  });

  group('Clôturer', () {
    testWidgets('PARTIEL : la modale « Inventaire incomplet » annonce combien '
        'ne sont pas comptés (phrase du serveur) ; confirmer écrit '
        'l’inventaire, ses lignes et la régularisation, et le DIT', (
      tester,
    ) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);
      await compter(tester, 'riz', '12');

      await toucher(tester, const Key('inventaire-cloturer'));

      expect(find.text('Inventaire incomplet'), findsOneWidget);
      expect(find.text(MessagesStock.inventaireIncomplet(1)), findsOneWidget);
      expect(
        find.text(
          'Clôturer maintenant ne régularisera QUE les articles comptés ; '
          'les autres resteront à leur stock théorique actuel, sans que rien '
          'ne le signale par la suite.',
        ),
        findsOneWidget,
      );
      expect(find.text('Clôturer partiellement'), findsOneWidget);
      expect(await db.select(db.inventairesLocal).get(), isEmpty);

      await toucher(tester, const Key('cloture-confirmer'));

      // Écrit : l'en-tête, la ligne, le mouvement d'excédent.
      final inventaire = await db.select(db.inventairesLocal).getSingle();
      expect(inventaire.pointId, magasin);
      expect(inventaire.utilisateurId, 'u-essai');
      final ligne = await db.select(db.lignesInventaireLocal).getSingle();
      expect(
        (
          ligne.articleId,
          ligne.quantiteConstateeCentiemes,
          ligne.ecartCentiemes,
        ),
        ('riz', 1200, 200),
      );
      final regularisation = (await StocksDao(db).mouvementsCalcul()).last;
      expect(regularisation.type, TypeMouvement.inventaire);
      expect(regularisation.centiemes, 200);

      expect(
        texteDe(tester, const Key('inventaire-cloture-fait')),
        'Inventaire clôturé — 1 régularisation(s), impact 2 500 FCFA.',
      );
      // Retour à l'étape 1 : le brouillon est clos, et le dernier inventaire
      // du point porte sa date.
      expect(find.byKey(const Key('inventaire-titre')), findsNothing);
      expect(
        texteDe(tester, Key('inventaire-cycle-$magasin-dernier')),
        formaterDate(DateTime.now()),
      );
      // Et la file part dans l'ordre : l'inventaire, puis son mouvement.
      final file = await OperationsSyncDao(db).operations();
      final apres = file.skipWhile(
        (o) => o.table != TableSynchronisee.inventaires,
      );
      expect(apres.map((o) => o.table), [
        TableSynchronisee.inventaires,
        TableSynchronisee.mouvementsStock,
      ]);
    });

    testWidgets('COMPLET : la modale ne dit PAS « incomplet » — l’inventaire '
        'l’est — et le bouton garde le nom du geste', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);
      await compter(tester, 'riz', '10');
      await compter(tester, 'huile', '4');

      await toucher(tester, const Key('inventaire-cloturer'));

      expect(find.text('Inventaire incomplet'), findsNothing);
      expect(find.textContaining('n\'ont pas été comptés'), findsNothing);
      expect(find.text('Clôturer partiellement'), findsNothing);
      expect(find.text('Clôturer et régulariser'), findsNWidgets(3));

      await toucher(tester, const Key('cloture-confirmer'));
      expect(
        texteDe(tester, const Key('inventaire-cloture-fait')),
        'Inventaire clôturé — 0 régularisation(s), impact 0 FCFA.',
      );
      expect(await db.select(db.lignesInventaireLocal).get(), hasLength(2));
    });

    testWidgets('annuler la clôture n’écrit rien et garde le comptage', (
      tester,
    ) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);
      await compter(tester, 'riz', '12');

      await toucher(tester, const Key('inventaire-cloturer'));
      await toucher(tester, const Key('modale-stock-annuler'));

      expect(await db.select(db.inventairesLocal).get(), isEmpty);
      expect(texteDe(tester, const Key('inventaire-ecart-riz')), '+2.00');
    });

    testWidgets('le comptage est EN MÉMOIRE : un écran remonté repart du cycle '
        '(et le dit avant)', (tester) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);
      await compter(tester, 'riz', '12');

      await tester.pumpWidget(const SizedBox());
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await toucher(tester, const Key('inventaires-onglet-inventaire'));

      expect(
        find.byKey(Key('inventaire-cycle-$magasin-lancer')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('inventaire-titre')), findsNothing);
    });
  });

  group('L’historique et l’export', () {
    testWidgets(
      'l’onglet « Inventaires clôturés » liste ce qui est écrit : '
      'date, point, articles, régularisés, « — » aux trois montants, auteur',
      (tester) async {
        final magasin = await jeuInventaire();
        await StocksDao(db).cloturerInventaire(
          pointId: magasin,
          date: DateTime(2026, 10, 19),
          comptages: {
            'riz': const ComptageBrouillon(
              theoriqueCentiemes: 1000,
              constateCentiemes: 1200,
            ),
            'huile': const ComptageBrouillon(
              theoriqueCentiemes: 400,
              constateCentiemes: 400,
            ),
          },
          auteurId: 'u-essai',
        );
        await monter(tester, const EcranInventaires(), role: 'magasinier');
        await toucher(tester, const Key('inventaires-onglet-historique'));

        expect(find.text('Aucun inventaire clôturé'), findsNothing);
        final ligne = find.byWidgetPredicate(
          (w) => w.key.toString().contains('historique-'),
        );
        expect(ligne, findsWidgets);
        expect(find.text('19/10/2026'), findsOneWidget);
        expect(find.text('Magasin'), findsOneWidget);
        expect(find.text('2'), findsOneWidget, reason: 'articles comptés');
        expect(find.text('1'), findsOneWidget, reason: 'régularisés');
        expect(find.text('essai'), findsOneWidget, reason: 'login de l’auteur');
        // Manquants, excédents, impact : « — » comme la vue.
        expect(find.text('—'), findsNWidgets(3));
      },
    );

    testWidgets('« Exporter » sans rien de compté : le refus, aucun fichier', (
      tester,
    ) async {
      final magasin = await jeuInventaire();
      await monter(tester, const EcranInventaires(), role: 'magasinier');
      await lancer(tester, magasin);

      await toucher(tester, const Key('inventaire-exporter'));
      await tester.tap(find.byKey(const Key('export-format-excel')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Générer & Télécharger'));
      await tester.pumpAndSettle();

      expect(
        texteDe(tester, const Key('inventaire-export-vide')),
        EtatInventaire.refusVide,
      );
      expect(selecteur.ecrits, isEmpty);
    });

    testWidgets(
      '« Exporter » le comptage affiché : tableur (BOM, point-virgule, '
      'nombres bruts) ET PDF',
      (tester) async {
        final magasin = await jeuInventaire();
        await monter(tester, const EcranInventaires(), role: 'magasinier');
        await lancer(tester, magasin);
        await compter(tester, 'riz', '12');
        await compter(tester, 'huile', '3');

        await toucher(tester, const Key('inventaire-exporter'));
        await tester.tap(find.byKey(const Key('export-format-excel')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Générer & Télécharger'));
        await tester.pumpAndSettle();

        final csv = selecteur.dernier;
        expect(csv.nom, startsWith('${EtatInventaire.prefixeFichier}_'));
        expect(csv.nom, endsWith('.csv'));
        expect(csv.octets.take(3), [0xEF, 0xBB, 0xBF]);
        expect(csv.texte, contains(EtatInventaire.entetes.join(';')));
        expect(csv.texte, contains('Riz local;10.00;12.00;+2.00;2500'));
        // L'huile n'a pas de coût : « — », jamais zéro.
        expect(csv.texte, contains('Huile;4.00;3.00;-1.00;—'));
        expect(csv.texte, contains('Magasin — inventaire du '));

        await toucher(tester, const Key('inventaire-exporter'));
        await tester.tap(find.text('Générer & Télécharger'));
        await tester.pumpAndSettle();
        expect(selecteur.dernier.estUnPdf, isTrue);
        expect(selecteur.ecrits, hasLength(2));
      },
    );
  });
}
