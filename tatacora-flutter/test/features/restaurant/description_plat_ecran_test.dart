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

/// La modale « Nouveau plat » / « Modifier » et son champ « Description » (v47,
/// 30/10/2026, décision du PO), montée pour de vrai sur l'écran Restauration :
/// champ FACULTATIF (aucun astérisque), multiligne, 500 caractères au plus ; écrite
/// en base et dans la file d'envoi ; relue à l'ouverture de l'édition ; effacée par
/// un champ vidé ; affichée en ligne secondaire sous le nom dans la liste des plats
/// quand elle existe. La règle (trim, 500) est confrontée au serveur par
/// `description_plat_test.dart`.
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
            .customSelect('SELECT id, libelle, description FROM plats_local')
            .get())
      l.data,
  ];

  Future<List<OperationSync>> file() =>
      OperationsSyncDao(db).operations(table: TableSynchronisee.plats);

  testWidgets(
    '« Description » est un champ FACULTATIF : libellé sans astérisque, '
    'un plat se crée sans la remplir',
    (tester) async {
      await poste();
      await monter(tester);
      await toucher(tester, const Key('restauration-ajouter'));

      expect(find.text('Description'), findsOneWidget);
      expect(find.text('Description *', findRichText: true), findsNothing);
      final champ = tester.widget<TextField>(
        find.byKey(const Key('modale-plat-description')),
      );
      expect((champ.minLines, champ.maxLines), (3, 3), reason: 'multiligne');

      await saisir(
        tester,
        const Key('modale-plat-libelle'),
        'Sans description',
      );
      await saisir(tester, const Key('modale-plat-prix'), '4500');
      await choisirMenuEtFiche(tester);
      await enregistrer(tester);

      expect(find.byKey(const Key('modale-plat')), findsNothing);
      expect((await plats()).single['description'], isNull);
      final charge =
          jsonDecode((await file()).single.payload) as Map<String, dynamic>;
      expect(charge.containsKey('description'), isFalse);
    },
  );

  testWidgets('saisie : écrite ROGNÉE en base et dans la création enfilée ; '
      'l’édition la relit, un champ vidé l’efface', (tester) async {
    await poste();
    await monter(tester);
    await toucher(tester, const Key('restauration-ajouter'));
    await saisir(tester, const Key('modale-plat-libelle'), 'Pizza royale');
    await saisir(
      tester,
      const Key('modale-plat-description'),
      '  Jambon, mozza  ',
    );
    await saisir(tester, const Key('modale-plat-prix'), '6000');
    await choisirMenuEtFiche(tester);
    await enregistrer(tester);

    final cree = (await plats()).single;
    expect(cree['description'], 'Jambon, mozza');
    final creation =
        jsonDecode((await file()).single.payload) as Map<String, dynamic>;
    expect(creation['description'], 'Jambon, mozza');

    // La liste la montre sous le nom.
    expect(
      find.byKey(Key('restauration-description-${cree['id']}')),
      findsOneWidget,
    );
    expect(find.text('Jambon, mozza'), findsOneWidget);

    // L'édition relit la description enregistrée, puis l'efface.
    await toucher(tester, Key('restauration-modifier-${cree['id']}'));
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('modale-plat-description')))
          .controller!
          .text,
      'Jambon, mozza',
    );
    await saisir(tester, const Key('modale-plat-description'), '');
    await db.customStatement('DELETE FROM operations_sync_local');
    await enregistrer(tester);

    expect((await plats()).single['description'], isNull);
    final modif =
        jsonDecode((await file()).single.payload) as Map<String, dynamic>;
    expect(modif.containsKey('description'), isTrue);
    expect(modif['description'], isNull);
    expect(
      find.byKey(Key('restauration-description-${cree['id']}')),
      findsNothing,
      reason: 'plus de description : plus de ligne secondaire',
    );
  });

  testWidgets('501 caractères : la phrase du serveur sous le champ, rien n’est '
      'écrit', (tester) async {
    await poste();
    await monter(tester);
    await toucher(tester, const Key('restauration-ajouter'));
    await saisir(tester, const Key('modale-plat-libelle'), 'Trop long');
    await saisir(tester, const Key('modale-plat-description'), 'x' * 501);
    await saisir(tester, const Key('modale-plat-prix'), '4500');
    await choisirMenuEtFiche(tester);
    await enregistrer(tester);

    expect(find.byKey(const Key('modale-plat')), findsOneWidget);
    expect(
      find.text('La description ne peut pas dépasser 500 caractères.'),
      findsOneWidget,
    );
    expect(await plats(), isEmpty);
    expect(await file(), isEmpty);
  });
}
