import 'dart:convert';

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
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_restauration.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// La modale « Nouveau plat » / « Modifier » et son champ « Catégorie » (v41,
/// 27/10/2026), montée pour de vrai sur l'écran Restauration : les dix catégories
/// de la carte (`CarteRestaurant::CATEGORIES`) aux mots de la vue, la clé écrite
/// en base et dans la file d'envoi, l'ouverture de l'édition sur la catégorie
/// ENREGISTRÉE, et un plat d'avant la v41 qui s'ouvre sans catégorie inventée.
/// Les dix clés sont confrontées au serveur par `import_categorie_plat_test.dart`
/// et `champs_location_contre_serveur_test.dart`.
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
  });

  tearDown(() => db.close());

  /// Les dix libellés de la vue, dans l'ordre de `CarteRestaurant::CATEGORIES`.
  const libelles = [
    'Entrées',
    'Plats complets',
    'Nos sauces',
    'Garnitures',
    'Accompagnements',
    'Sandwicherie',
    'Pizzas',
    'Nos desserts',
    'Jus maison & cafés',
    'Formules & brochettes',
  ];
  const cles = [
    'entrees',
    'plats',
    'sauces',
    'garnitures',
    'accompagnements',
    'sandwicherie',
    'pizzas',
    'desserts',
    'boissons_maison',
    'formules',
  ];

  List<Override> surcharges() {
    final droits = GardeAcces({'M4': 'C', 'M6': 'C'});
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

  /// Un menu, une fiche (0,3 kg de poulet) — le plat se crée ensuite par l'écran.
  Future<({String menu, String fiche})> poste() async {
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
    await stocks.ajouterMouvement(
      articleId: 'a-poulet',
      pointId: 'p-cui',
      type: TypeMouvement.entree,
      centiemes: 1000,
      motif: 'Réception',
      auteurId: 'u-essai',
      coutDixMilliemes: 25000000,
    );
    final conteneur = ProviderContainer(overrides: surcharges());
    addTearDown(conteneur.dispose);
    final api = conteneur.read(restaurantApiProvider);
    final menu =
        (await api.enregistrerMenu(
                  const SaisieMenu(libelle: 'Carte du jour', type: 'local'),
                )
                as RestaurantRecu<MenuRestaurant>)
            .donnees;
    final fiche =
        (await api.enregistrerRecette(
                  const SaisieFiche(
                    libelle: 'Recette Poulet DG',
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
    return (menu: menu.id, fiche: fiche.id);
  }

  /// Un plat posé par l'API, sous la catégorie [categorie] (`null` : celle d'un
  /// plat d'avant la v41).
  Future<String> plat(
    ({String menu, String fiche}) p,
    String libelle, {
    String? categorie,
  }) async {
    final conteneur = ProviderContainer(overrides: surcharges());
    addTearDown(conteneur.dispose);
    final r =
        await conteneur
                .read(restaurantApiProvider)
                .enregistrerPlat(
                  SaisiePlat(
                    libelle: libelle,
                    menuId: p.menu,
                    recetteId: p.fiche,
                    prixVente: '4500',
                    categorie: categorie,
                  ),
                  modification: false,
                )
            as RestaurantRecu<Plat>;
    return r.donnees.id;
  }

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges(),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranRestauration()),
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

  Future<void> choisirCategorie(WidgetTester tester, String libelle) async {
    await toucher(tester, const Key('modale-plat-categorie'));
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  /// La catégorie affichée dans le sélecteur de la modale.
  String categorieAffichee(WidgetTester tester) => tester
      .widget<DropdownButtonFormField<CategorieCarte>>(
        find.byKey(const Key('modale-plat-categorie')),
      )
      .initialValue!
      .libelle;

  /// La liste déroulante DANS un sélecteur de référentiel (le sélecteur porte aussi
  /// son bouton « créer » et son aide : son centre n'est pas la liste).
  Future<void> choisirDans(
    WidgetTester tester,
    Key selecteur,
    String texte,
  ) async {
    final liste = find.descendant(
      of: find.byKey(selecteur),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.ensureVisible(liste);
    await tester.pumpAndSettle();
    await tester.tap(liste);
    await tester.pumpAndSettle();
    await tester.tap(find.text(texte).last);
    await tester.pumpAndSettle();
  }

  Future<void> choisirMenuEtFiche(WidgetTester tester) async {
    await choisirDans(
      tester,
      const Key('modale-plat-menu'),
      'Carte du jour — Local',
    );
    await choisirDans(
      tester,
      const Key('modale-plat-recette'),
      'Recette Poulet DG',
    );
  }

  Future<void> enregistrer(WidgetTester tester) async {
    await toucher(tester, const Key('modale-plat-enregistrer'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Future<List<Map<String, Object?>>> plats() async => [
    for (final l
        in await db
            .customSelect('SELECT libelle, categorie FROM plats_local')
            .get())
      l.data,
  ];

  Future<List<OperationSync>> file() =>
      OperationsSyncDao(db).operations(table: TableSynchronisee.plats);

  testWidgets('« Catégorie *» offre les DIX catégories de la carte, aux mots de '
      'la vue et dans son ordre ; la première est proposée', (tester) async {
    await poste();
    await monter(tester);
    await toucher(tester, const Key('restauration-ajouter'));

    expect(find.text('Catégorie *', findRichText: true), findsOneWidget);
    expect(categorieAffichee(tester), 'Entrées');

    await toucher(tester, const Key('modale-plat-categorie'));
    final items = tester
        .widgetList<DropdownMenuItem<CategorieCarte>>(
          find.byType(DropdownMenuItem<CategorieCarte>),
        )
        .map((i) => i.value!.libelle)
        .toList();
    // Le menu déroulant porte aussi l'élément affiché : les dix, dans l'ordre.
    expect(items.skip(items.length - 10), libelles);
    expect(
      [for (final c in CategorieCarte.values) c.code],
      cles,
      reason: 'les clés stockées',
    );
  });

  testWidgets('chaque catégorie choisie s’écrit sous SA clé, en base et dans '
      'la création enfilée', (tester) async {
    await poste();

    for (final (i, libelle) in libelles.indexed) {
      // Un écran NEUF par plat : la modale précédente ne laisse rien derrière elle.
      await monter(tester);
      await toucher(tester, const Key('restauration-ajouter'));
      await saisir(tester, const Key('modale-plat-libelle'), 'Plat $i');
      await saisir(tester, const Key('modale-plat-prix'), '4500');
      await choisirMenuEtFiche(tester);
      await choisirCategorie(tester, libelle);
      await enregistrer(tester);
      expect(find.byKey(const Key('modale-plat')), findsNothing, reason: '$i');
    }

    final enBase = {
      for (final p in await plats()) p['libelle']: p['categorie'],
    };
    expect(enBase, {for (final (i, c) in cles.indexed) 'Plat $i': c});

    final creations = await file();
    expect(creations, hasLength(10));
    for (final (i, o) in creations.indexed) {
      expect(o.type, TypeOperationSync.creation);
      expect(
        (jsonDecode(o.payload) as Map<String, dynamic>)['categorie'],
        cles[i],
        reason: 'Plat $i',
      );
    }
  });

  testWidgets('la liste affiche la catégorie du plat, au mot de la vue', (
    tester,
  ) async {
    final p = await poste();
    await plat(p, 'Margherita', categorie: 'pizzas');
    await monter(tester);
    final id = (await db.select(db.platsLocal).getSingle()).id;
    expect(
      tester.widget<Text>(find.byKey(Key('restauration-categorie-$id'))).data,
      'Pizzas',
    );
  });

  testWidgets('« Modifier » s’ouvre sur la catégorie ENREGISTRÉE ; la changer '
      'n’envoie que la catégorie', (tester) async {
    final p = await poste();
    final id = await plat(p, 'Glace', categorie: 'desserts');
    await db.customStatement('DELETE FROM operations_sync_local');
    await monter(tester);

    await toucher(tester, Key('restauration-modifier-$id'));
    expect(categorieAffichee(tester), 'Nos desserts');

    await choisirCategorie(tester, 'Formules & brochettes');
    await enregistrer(tester);

    expect((await plats()).single['categorie'], 'formules');
    final modification = (await file()).single;
    expect(modification.type, TypeOperationSync.modification);
    expect(jsonDecode(modification.payload), {'categorie': 'formules'});
  });

  testWidgets('un plat d’AVANT la v41 s’ouvre sur la première catégorie, comme '
      'la vue — et ne la réécrit pas s’il n’y touche pas', (tester) async {
    final p = await poste();
    final id = await plat(p, 'Ancien plat');
    await db.customStatement(
      "UPDATE plats_local SET categorie = NULL WHERE id = '$id'",
    );
    await db.customStatement('DELETE FROM operations_sync_local');
    await monter(tester);

    await toucher(tester, Key('restauration-modifier-$id'));
    expect(categorieAffichee(tester), 'Entrées');
    await saisir(tester, const Key('modale-plat-prix'), '5000');
    await enregistrer(tester);

    final modification = (await file()).single;
    expect(
      (jsonDecode(modification.payload) as Map<String, dynamic>)['prix_vente'],
      5000,
    );
  });
}
