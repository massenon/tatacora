import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// « Lier au stock » du restaurant, par la CHAÎNE RÉELLE (écran, providers,
/// `RestaurantApi`, `RestaurantDao`, base) — le geste que le Product Owner ne
/// pouvait pas faire sur le poste (21/10/2026) : menu -> plat -> fiche
/// technique d'articles de stock -> LIEN du plat à un article de stock.
///
/// Le cas écrit d'abord ÉCHOUAIT : le bouton « Lier au stock » de la carte ne
/// faisait qu'afficher « n'est pas disponible », aucune colonne ne portait
/// l'article du plat (piège 5 : un test qui n'emprunte pas le chemin ne
/// protège pas le chemin).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksDao stocks;

  setUp(() async {
    db = AppDatabase.enMemoire();
    stocks = StocksDao(db);
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-essai',
            login: 'chef',
            nom: 'Aïcha',
            role: 'cuisinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    await stocks.creerPoint(
      libelle: 'Cuisine',
      type: TypePoint.cuisine,
      id: 'p-cui',
    );
    await stocks.creerArticle(
      id: 'a-poulet',
      libelle: 'Poulet',
      categorie: null,
      uniteMesure: 'kg',
      seuilCentiemes: 0,
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-cui',
    );
    await stocks.creerArticle(
      id: 'a-eau',
      libelle: 'Eau minérale',
      categorie: null,
      uniteMesure: 'casier',
      seuilCentiemes: 0,
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-cui',
    );
    await stocks.creerArticle(
      id: 'a-oignon',
      libelle: 'Oignon',
      categorie: null,
      uniteMesure: 'kg',
      seuilCentiemes: 0,
      suivi: SuiviArticle.journalier,
      pointStockageId: 'p-cui',
    );
    await stocks.ajouterMouvement(
      articleId: 'a-poulet',
      pointId: 'p-cui',
      type: TypeMouvement.entree,
      centiemes: 1000,
      motif: 'Réception',
      auteurId: 'u-essai',
      coutDixMilliemes: 25000000,
    );
    // 5 casiers d'eau en cuisine.
    await stocks.ajouterMouvement(
      articleId: 'a-eau',
      pointId: 'p-cui',
      type: TypeMouvement.entree,
      centiemes: 500,
      motif: 'Réception',
      auteurId: 'u-essai',
      coutDixMilliemes: 30000000,
    );
  });

  tearDown(() async {
    await db.close();
  });

  List<Override> surcharges({String m4 = 'C'}) {
    final droits = GardeAcces({'M4': m4, 'M6': 'C'});
    return [
      baseLocaleProvider.overrideWithValue(db),
      droitsProvider.overrideWithValue(droits),
      sessionProvider.overrideWithBuild(
        (ref, notifier) => Session(
          utilisateurId: 'u-essai',
          login: 'chef',
          nom: 'Aïcha',
          role: 'cuisinier',
          droits: droits,
        ),
      ),
    ];
  }

  Future<void> monter(WidgetTester tester, {String m4 = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1600, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges(m4: m4),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranCarteRestaurant()),
        ),
      ),
    );
    await tester.pumpAndSettle();
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

  List<String> textesSous(WidgetTester tester, Key cle) => [
    for (final t in tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(cle),
        matching: find.byType(Text),
        matchRoot: true,
      ),
    ))
      t.data ?? t.textSpan!.toPlainText(),
  ];

  /// Le parcours du PO, par l'API de l'écran : un menu, une fiche technique
  /// composée d'un article de stock, un plat dans ce menu.
  Future<String> platDuMenu() async {
    final container = ProviderContainer(overrides: surcharges());
    addTearDown(container.dispose);
    final api = container.read(restaurantApiProvider);
    final menu =
        (await api.enregistrerMenu(
                  const SaisieMenu(libelle: 'Carte du jour', type: 'local'),
                )
                as RestaurantRecu<MenuRestaurant>)
            .donnees;
    final fiche =
        (await api.enregistrerRecette(
                  const SaisieFiche(
                    libelle: 'Recette Eau 50 cl',
                    lignes: [
                      LigneSaisieComposition(
                        articleId: 'a-poulet',
                        quantite: '0,3',
                      ),
                    ],
                  ),
                )
                as RestaurantRecu<Recette>)
            .donnees;
    return (await api.enregistrerPlat(
              SaisiePlat(
                libelle: 'Eau 50 cl',
                menuId: menu.id,
                recetteId: fiche.id,
                prixVente: '500',
                prixProvisoire: false,
              ),
              modification: false,
            )
            as RestaurantRecu<Plat>)
        .donnees
        .id;
  }

  testWidgets('« Lier au stock » ouvre le formulaire, l’enregistrement écrit '
      'l’article ET le conditionnement, les met en file, et la carte les '
      'montre', (tester) async {
    final plat = await platDuMenu();
    await monter(tester);

    // Avant : 10 kg / 0,3 kg = 33 portions, par la fiche technique.
    expect(textesSous(tester, Key('carte-restaurant-portions-$plat')), ['33']);
    expect(find.byKey(Key('carte-restaurant-delier-$plat')), findsNothing);

    await toucher(tester, Key('carte-restaurant-lier-$plat'));
    expect(find.byKey(const Key('modale-lien-plat')), findsOneWidget);
    expect(find.text('Lier au stock'), findsWidgets);

    // Sans article ni conditionnement : refus SOUS les champs, la modale reste.
    await saisir(tester, const Key('lien-plat-conversion'), '');
    await toucher(tester, const Key('lien-plat-enregistrer'));
    expect(find.byKey(const Key('modale-lien-plat')), findsOneWidget);
    expect(
      find.text(MessagesRestaurant.articleLienObligatoire),
      findsOneWidget,
    );
    expect(
      find.text(MessagesRestaurant.conversionRequise('Eau 50 cl')),
      findsOneWidget,
    );
    expect(
      await db.select(db.platsLocal).getSingle().then((p) => p.articleId),
      isNull,
    );

    // Seuls les articles en suivi PERMANENT sont offerts (la phrase de la vue).
    await toucher(tester, const Key('lien-plat-article'));
    expect(find.text('Eau minérale — casier'), findsWidgets);
    expect(find.text('Oignon — kg'), findsNothing);
    await tester.tap(find.text('Eau minérale — casier').last);
    await tester.pumpAndSettle();

    await saisir(tester, const Key('lien-plat-conversion'), '24');
    // L'aperçu : 5 casiers -> 120 unités vendables ; 1/24 par vente.
    expect(find.byKey(const Key('lien-plat-apercu')), findsOneWidget);
    await toucher(tester, const Key('lien-plat-enregistrer'));

    expect(find.byKey(const Key('modale-lien-plat')), findsNothing);
    expect(find.text('« Eau 50 cl » est rattaché au stock.'), findsOneWidget);

    // ---- Ce que la base a reçu ----
    final ligne = await db.select(db.platsLocal).getSingle();
    expect(ligne.articleId, 'a-eau');
    expect(ligne.unitesVendables, '24.0000');

    // ---- Ce que la file d'envoi a reçu : une MODIFICATION du plat ----
    final ops = [
      for (final o in await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.plats))
        o,
    ];
    final modif = ops.where((o) => o.type == TypeOperationSync.modification);
    expect(modif, hasLength(1));
    expect(modif.single.payload, contains('"article_id":"a-eau"'));
    expect(
      modif.single.payload,
      contains('"unites_vendables_par_unite_stock":"24.0000"'),
    );

    // ---- Ce que la carte en montre : le lien direct l'emporte sur la fiche ----
    expect(textesSous(tester, Key('carte-restaurant-fiche-$plat')), [
      'Eau minérale',
    ]);
    expect(find.text('24 par casier'), findsOneWidget);
    // 5 casiers x 24 = 120 portions.
    expect(textesSous(tester, Key('carte-restaurant-portions-$plat')), ['120']);
    expect(find.byKey(Key('carte-restaurant-delier-$plat')), findsOneWidget);
    expect(find.text('Modifier le lien'), findsOneWidget);

    // ---- « Délier » : confirmation, puis les DEUX colonnes repartent ----
    await toucher(tester, Key('carte-restaurant-delier-$plat'));
    expect(find.text('Retirer le lien au stock ?'), findsOneWidget);
    await toucher(tester, const Key('delier-plat-confirmer'));
    final delie = await db.select(db.platsLocal).getSingle();
    expect((delie.articleId, delie.unitesVendables), (null, null));
    final apres = [
      for (final o in await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.plats))
        o,
    ].where((o) => o.type == TypeOperationSync.modification).toList();
    expect(apres, hasLength(2));
    expect(apres.last.payload, contains('"article_id":null'));
    expect(
      apres.last.payload,
      contains('"unites_vendables_par_unite_stock":null'),
    );
    expect(textesSous(tester, Key('carte-restaurant-portions-$plat')), ['33']);
  });

  testWidgets('en lecture seule, « Lier au stock » n’est pas offert', (
    tester,
  ) async {
    final plat = await platDuMenu();
    await monter(tester, m4: 'L');
    expect(find.byKey(Key('carte-restaurant-lier-$plat')), findsNothing);
  });

  test('un article LIÉ à un plat ne s’archive plus : le verrou « vendu à la '
      'carte » du serveur est rejoué (écart v35 levé)', () async {
    final plat = await platDuMenu();
    // Le solde (5 casiers) est un AUTRE verrou : seul « vendu à la carte » nous
    // concerne.
    Future<List<String>> carte() async => [
      for (final v in await stocks.verrousArticle('a-eau'))
        if (v.contains('vendu à la carte')) v,
    ];
    expect(await carte(), isEmpty);

    final container = ProviderContainer(overrides: surcharges());
    addTearDown(container.dispose);
    final r = await container
        .read(restaurantApiProvider)
        .lierAuStock(platId: plat, articleId: 'a-eau', conditionnement: '24');
    expect(r, isA<RestaurantRecu<Plat>>());

    final verrous = await carte();
    expect(verrous, hasLength(1));
    expect(verrous.single, contains('Il est vendu à la carte (1 entrée(s))'));

    // Délié : l'article redevient archivable.
    await container.read(restaurantApiProvider).delierDuStock(plat);
    expect(await carte(), isEmpty);
  });
}
