import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_restauration.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import '../../support/selecteur_essai.dart';

/// M4 par la CHAÎNE RÉELLE : l'écran, les providers, `RestaurantApi`,
/// `RestaurantDao`, `StocksDao` et la base — **aucune liste surchargée**.
///
/// `ecran_carte_restaurant_test.dart` surcharge `carteRestaurantProvider` et
/// éprouve les comportements de l'écran ; il ne dit rien de ce que la base
/// reçoit. Ces cas partent d'un poste réel (base en mémoire, session ouverte)
/// et vont jusqu'à la ligne écrite : une fonction pure testée sans test de
/// l'appelant est une assertion vide.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksDao stocks;
  // La fenêtre « Enregistrer sous » remplacée (14/10/2026) : le VRAI
  // export (`exporterCarteRestaurantProvider` → `enregistrementExportProvider`)
  // est emprunté jusqu'à elle.
  late SelecteurEssai selecteur;

  setUp(() async {
    db = AppDatabase.enMemoire();
    stocks = StocksDao(db);
    selecteur = SelecteurEssai();
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

  tearDown(() async {
    await db.close();
  });

  List<Override> surcharges({
    String m4 = 'C',
    String m6 = 'C',
    List<Override> plus = const [],
  }) {
    final droits = GardeAcces({'M4': m4, 'M6': m6});
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
      ...selecteur.surcharges,
      ...plus,
    ];
  }

  Future<void> monter(
    WidgetTester tester,
    Widget ecran, {
    List<Override>? avec,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: avec ?? surcharges(),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: ecran),
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

  Future<void> choisir(WidgetTester tester, Key liste, String libelle) async {
    await toucher(tester, liste);
    await tester.tap(find.text(libelle).last);
    await tester.pumpAndSettle();
  }

  /// Les textes rendus SOUS une clé.
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

  /// Le fichier que l'export RÉEL vient de remettre à « Enregistrer sous » :
  /// un seul, du [type] attendu, sous le nom suggéré `carte_restaurant_<date>`,
  /// et le toast commun le dit.
  List<int> octetsExportes(
    WidgetTester tester, {
    TypeFichierEnregistre type = TypeFichierEnregistre.csv,
  }) {
    expect(selecteur.ecrits, hasLength(1), reason: 'un seul fichier écrit');
    final ecrit = selecteur.ecrits.single;
    expect(ecrit.type, type);
    expect(
      ecrit.nom,
      matches(
        RegExp(
          '^carte_restaurant_[0-9]{4}-[0-9]{2}-[0-9]{2}[.]${type.extension}'
          r'$',
        ),
      ),
    );
    expect(find.text('Export enregistré : ${ecrit.nom}'), findsOneWidget);
    return ecrit.octets;
  }

  /// Le poste du restaurant : un point cuisine, un article (10 kg de poulet à
  /// 2 500 F le kilo, reçus en cuisine) et un article de plus pour les listes.
  Future<void> poste() async {
    // Idempotent : `garni()` l'appelle aussi.
    if ((await stocks.points()).isNotEmpty) return;
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
  }

  /// Un menu, une fiche (0,3 kg de poulet) et un plat posés par l'API de
  /// l'écran — pour les cas qui n'éprouvent pas la saisie.
  Future<({String menu, String fiche, String plat})> garni({
    String libelle = 'Poulet DG',
    bool provisoire = false,
  }) async {
    await poste();
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
    final plat =
        (await api.enregistrerPlat(
                  SaisiePlat(
                    libelle: libelle,
                    menuId: menu.id,
                    recetteId: fiche.id,
                    prixVente: '4500',
                    prixProvisoire: provisoire,
                  ),
                  modification: false,
                )
                as RestaurantRecu<Plat>)
            .donnees;
    return (menu: menu.id, fiche: fiche.id, plat: plat.id);
  }

  /* ==================================================================== */
  /* Le catalogue                                                          */
  /* ==================================================================== */

  group('Le catalogue d’un poste NEUF', () {
    testWidgets('dit la vérité : des zéros mesurés, « Aucun résultat », et '
        'jamais « donnée non disponible »', (tester) async {
      await monter(tester, const EcranRestauration());

      expect(
        textesSous(tester, const Key('restauration-kpi-0')),
        contains('0'),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-1')),
        contains('0 / 0'),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-2')),
        contains('0'),
      );
      // « Retirés de la carte » est COMPTÉ (retraits de la carte, v31) : un
      // poste neuf en a zéro, mesuré, jamais « — ».
      expect(
        textesSous(tester, const Key('restauration-kpi-3')),
        containsAll(['RETIRÉS DE LA CARTE', '0']),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-3')),
        isNot(contains('—')),
      );

      expect(find.text('Aucun résultat'), findsOneWidget);
      expect(find.textContaining('ne figurent pas sur ce poste'), findsNothing);
    });

    testWidgets('les deux autres onglets sont VIDES et le disent avec les mots '
        'de la vue', (tester) async {
      await monter(tester, const EcranRestauration());

      await toucher(tester, const Key('restauration-onglet-fiches'));
      expect(find.byKey(const Key('restauration-fiches-vide')), findsOneWidget);
      expect(
        find.text('Aucune fiche technique ne correspond à ces critères.'),
        findsOneWidget,
      );
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-0')),
        contains('0'),
      );
      // « Compositions provisoires » : COMPTÉES (v35) — un poste neuf en a
      // zéro, mesuré, jamais « — ».
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-2')),
        containsAll(['COMPOSITIONS PROVISOIRES', '0']),
      );
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-2')),
        isNot(contains('—')),
      );
      // La phrase de la vue promet un refus que ce poste ne fait pas : elle est
      // suivie de l'honnêteté.
      expect(
        find.text(MessagesRestaurant.venteSansSortieDeStock),
        findsOneWidget,
      );

      await toucher(tester, const Key('restauration-onglet-menus'));
      expect(find.byKey(const Key('restauration-menus-vide')), findsOneWidget);
      expect(
        find.textContaining('Le bouton « Nouveau menu » en crée un'),
        findsOneWidget,
      );
    });
  });

  group('Du poste neuf au plat — par les gestes de l’écran', () {
    testWidgets('menu, fiche et plat se créent depuis le formulaire de plat, '
        'qui garde sa saisie', (tester) async {
      await poste();
      await monter(tester, const EcranRestauration());

      // 1. « Nouveau plat » sur un poste vide : le manque est NOMMÉ.
      await toucher(tester, const Key('restauration-ajouter'));
      expect(find.byKey(const Key('modale-plat')), findsOneWidget);
      expect(find.text(MessagesRestaurant.aucunMenu), findsOneWidget);
      expect(find.text(MessagesRestaurant.aucuneFiche), findsOneWidget);

      // Une saisie en cours, que la création du menu ne doit pas perdre.
      await saisir(tester, const Key('modale-plat-libelle'), 'Poulet DG');
      await saisir(tester, const Key('modale-plat-prix'), '4 500');

      // 2. Le menu, créé SUR PLACE.
      await toucher(tester, const Key('modale-plat-creer-menu'));
      expect(find.byKey(const Key('modale-menu')), findsOneWidget);
      await saisir(tester, const Key('modale-menu-libelle'), 'Carte du jour');
      await toucher(tester, const Key('modale-menu-enregistrer'));

      expect(find.byKey(const Key('modale-menu')), findsNothing);
      expect(find.byKey(const Key('toast-menu-enregistre')), findsOneWidget);
      expect(find.text('Le menu « Carte du jour » est créé.'), findsOneWidget);
      // La saisie du plat est INTACTE, le menu présélectionné.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('modale-plat-libelle')))
            .controller!
            .text,
        'Poulet DG',
      );
      expect(find.text('Carte du jour — Local'), findsOneWidget);

      // 3. La fiche, créée SUR PLACE, avec une vraie composition.
      await toucher(tester, const Key('modale-plat-creer-fiche'));
      expect(find.byKey(const Key('modale-fiche')), findsOneWidget);
      await saisir(
        tester,
        const Key('modale-fiche-libelle'),
        'Recette Poulet DG',
      );
      await choisir(tester, const Key('modale-fiche-article-0'), 'Poulet — kg');
      await saisir(tester, const Key('modale-fiche-quantite-0'), '0,3');
      await toucher(tester, const Key('modale-fiche-enregistrer'));

      expect(find.byKey(const Key('modale-fiche')), findsNothing);
      // Le coût est DIT dans ses trois états ; ici connu : 0,3 kg × 2 500 F.
      expect(
        find.text(
          'La fiche « Recette Poulet DG » est créée. Coût matière calculé : '
          '${formaterMontantDecimal('750.00', suffixe: 'FCFA')}.',
        ),
        findsOneWidget,
      );
      expect(find.text('Recette Poulet DG'), findsOneWidget);

      // 4. Le plat : prix provisoire coché, puis enregistré.
      await toucher(tester, const Key('modale-plat-provisoire'));
      await toucher(tester, const Key('modale-plat-enregistrer'));

      expect(find.byKey(const Key('modale-plat')), findsNothing);
      expect(
        find.text('Le plat « Poulet DG » est au catalogue.'),
        findsOneWidget,
      );

      // ---- Ce que la base a reçu, ligne par ligne ----
      final menu = await db.select(db.menusLocal).getSingle();
      expect(
        (menu.libelle, menu.type, menu.dateDebut, menu.dateFin),
        ('Carte du jour', 'local', null, null),
      );
      final fiche = await db.select(db.recettesLocal).getSingle();
      expect(fiche.libelle, 'Recette Poulet DG');
      final ligne = await db.select(db.ingredientsRecetteLocal).getSingle();
      expect(
        (ligne.recetteId, ligne.articleId, ligne.quantiteMilliemes),
        (fiche.id, 'a-poulet', 300),
      );
      final plat = await db.select(db.platsLocal).getSingle();
      expect(plat.libelle, 'Poulet DG');
      expect(plat.prixVente, 4500);
      expect(plat.prixProvisoire, isTrue);
      expect(plat.prixCorrigeMain, isFalse);
      expect(plat.menuId, menu.id);
      expect(plat.recetteId, fiche.id);
      expect(plat.creePar, 'u-essai');

      // ---- Ce que l'écran en montre ----
      expect(find.byKey(Key('restauration-ligne-${plat.id}')), findsOneWidget);
      expect(
        textesSous(tester, const Key('restauration-kpi-0')),
        contains('1'),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-1')),
        contains('1 / 1'),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-2')),
        contains('0'),
      );
      expect(find.text('Aucun résultat'), findsNothing);
      expect(
        find.text(formaterMontantDecimal('4500.00', suffixe: 'FCFA')!),
        findsOneWidget,
      );

      // L'onglet des fiches : le plat servi, le coût, l'état.
      await toucher(tester, const Key('restauration-onglet-fiches'));
      expect(textesSous(tester, Key('restauration-fiche-plats-${fiche.id}')), [
        'Poulet DG',
      ]);
      expect(
        textesSous(tester, Key('restauration-fiche-ingredients-${fiche.id}')),
        ['1'],
      );
      expect(textesSous(tester, Key('restauration-fiche-cout-${fiche.id}')), [
        formaterMontantDecimal('750.00', suffixe: 'FCFA'),
      ]);
      expect(textesSous(tester, Key('restauration-fiche-etat-${fiche.id}')), [
        'Composée',
      ]);
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-0')),
        contains('1'),
      );
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-1')),
        contains('0'),
      );

      // L'onglet des menus : type, saison, plats rattachés (COMPTÉS).
      await toucher(tester, const Key('restauration-onglet-menus'));
      expect(textesSous(tester, Key('restauration-menu-saison-${menu.id}')), [
        'Permanent',
      ]);
      expect(textesSous(tester, Key('restauration-menu-plats-${menu.id}')), [
        '1',
      ]);
      expect(find.text('Local'), findsWidgets);
    });

    testWidgets('les cartes distinguent un plat à fiche COMPOSÉE d’un plat à '
        'fiche vide : « 1 / 2 », jamais « 2 / 2 »', (tester) async {
      final ids = await garni();
      // Un second plat, rattaché à une fiche VIDE.
      final container = ProviderContainer(overrides: surcharges());
      addTearDown(container.dispose);
      final api = container.read(restaurantApiProvider);
      final vide =
          (await api.enregistrerRecette(
                    const SaisieFiche(libelle: 'Fiche à écrire', lignes: []),
                  )
                  as RestaurantRecu<Recette>)
              .donnees;
      await api.enregistrerPlat(
        SaisiePlat(
          libelle: 'Salade nue',
          menuId: ids.menu,
          recetteId: vide.id,
          prixVente: '1500',
        ),
        modification: false,
      );

      await monter(tester, const EcranRestauration());

      expect(
        textesSous(tester, const Key('restauration-kpi-0')),
        contains('2'),
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-1')),
        contains('1 / 2'),
      );
      // Une fiche vide est une dette : la carte n’est plus verte.
      expect(
        textesSous(tester, const Key('restauration-kpi-2')),
        contains('1'),
      );
    });

    testWidgets('« Enregistrer » n’est jamais grisé faute de menu : le refus '
        'nomme le champ et RIEN n’est écrit', (tester) async {
      await monter(tester, const EcranRestauration());
      await toucher(tester, const Key('restauration-ajouter'));
      await toucher(tester, const Key('modale-plat-enregistrer'));

      expect(find.byKey(const Key('modale-plat')), findsOneWidget);
      expect(find.text(MessagesRestaurant.libelleObligatoire), findsOneWidget);
      expect(find.text(MessagesRestaurant.prixObligatoire), findsOneWidget);
      expect(find.text(MessagesRestaurant.menuObligatoire), findsOneWidget);
      expect(find.text(MessagesRestaurant.recetteObligatoire), findsOneWidget);
      expect(await db.select(db.platsLocal).get(), isEmpty);
    });

    testWidgets('un prix à fraction de franc est refusé sous son champ', (
      tester,
    ) async {
      final ids = await garni();
      await monter(tester, const EcranRestauration());

      await toucher(tester, Key('restauration-modifier-${ids.plat}'));
      await saisir(tester, const Key('modale-plat-prix'), '4500,50');
      await toucher(tester, const Key('modale-plat-enregistrer'));

      expect(find.text(MessagesRestaurant.prixFractionDeFranc), findsOneWidget);
      expect((await db.select(db.platsLocal).getSingle()).prixVente, 4500);
    });

    testWidgets('modifier le prix d’un plat PROVISOIRE pose « corrigé à la '
        'main », et la modale le dit ensuite en lecture seule', (tester) async {
      final ids = await garni(provisoire: true);
      await monter(tester, const EcranRestauration());

      await toucher(tester, Key('restauration-modifier-${ids.plat}'));
      expect(find.byKey(const Key('modale-plat-corrige-main')), findsNothing);
      await saisir(tester, const Key('modale-plat-prix'), '5000');
      await toucher(tester, const Key('modale-plat-enregistrer'));

      final plat = await db.select(db.platsLocal).getSingle();
      expect(plat.prixVente, 5000);
      expect(plat.prixCorrigeMain, isTrue);

      await toucher(tester, Key('restauration-modifier-${ids.plat}'));
      expect(find.byKey(const Key('modale-plat-corrige-main')), findsOneWidget);
    });
  });

  group('Les fiches et les menus — modification', () {
    testWidgets('composer une fiche existante : la composition est relue à '
        'trois décimales, remplacée, jamais fusionnée', (tester) async {
      await poste();
      await stocks.creerArticle(
        id: 'a-riz',
        libelle: 'Riz',
        categorie: null,
        uniteMesure: 'kg',
        seuilCentiemes: 0,
        suivi: SuiviArticle.permanent,
        pointStockageId: null,
      );
      final ids = await garni();
      await monter(tester, const EcranRestauration());
      await toucher(tester, const Key('restauration-onglet-fiches'));

      await toucher(tester, Key('restauration-fiche-modifier-${ids.fiche}'));
      expect(find.byKey(const Key('modale-fiche')), findsOneWidget);
      // La quantité affichée est celle de la base, à trois décimales.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('modale-fiche-quantite-0')))
            .controller!
            .text,
        '0.300',
      );
      // Le coût matière enregistré, en lecture seule.
      expect(textesSous(tester, const Key('modale-fiche-cout-valeur')), [
        formaterMontantDecimal('750.00', suffixe: 'FCFA'),
      ]);

      // On corrige le poulet et on ajoute du riz.
      await saisir(tester, const Key('modale-fiche-quantite-0'), '0,4');
      await toucher(tester, const Key('modale-fiche-ajouter'));
      await choisir(tester, const Key('modale-fiche-article-1'), 'Riz — kg');
      await saisir(tester, const Key('modale-fiche-quantite-1'), '0,15');
      await toucher(tester, const Key('modale-fiche-enregistrer'));

      var lignes = await (db.select(
        db.ingredientsRecetteLocal,
      )..orderBy([(l) => OrderingTerm.asc(l.articleId)])).get();
      expect(
        [for (final l in lignes) (l.articleId, l.quantiteMilliemes)],
        [('a-poulet', 400), ('a-riz', 150)],
      );
      // Le riz n'a jamais été réceptionné : le coût devient INCOMPLET (nommé),
      // il ne devient pas 0.
      expect(textesSous(tester, Key('restauration-fiche-cout-${ids.fiche}')), [
        'Incomplet',
      ]);
      expect(
        find.textContaining('Son coût matière reste INCONNU : Riz'),
        findsOneWidget,
      );

      // Retirer la ligne du riz le retire RÉELLEMENT de la fiche.
      await toucher(tester, Key('restauration-fiche-modifier-${ids.fiche}'));
      await toucher(tester, const Key('modale-fiche-retirer-1'));
      await toucher(tester, const Key('modale-fiche-enregistrer'));

      lignes = await db.select(db.ingredientsRecetteLocal).get();
      expect([for (final l in lignes) l.articleId], ['a-poulet']);
    });

    testWidgets('un article jamais choisi est refusé SOUS sa ligne, avec la '
        'phrase du serveur', (tester) async {
      await poste();
      await monter(tester, const EcranRestauration());
      await toucher(tester, const Key('restauration-nouvelle-fiche'));

      await saisir(tester, const Key('modale-fiche-libelle'), 'Fiche');
      await saisir(tester, const Key('modale-fiche-quantite-0'), '2');
      await toucher(tester, const Key('modale-fiche-enregistrer'));

      expect(find.text(MessagesRestaurant.articleObligatoire), findsOneWidget);
      expect(await db.select(db.recettesLocal).get(), isEmpty);
    });

    testWidgets('« Fiches vides seulement » isole celles qui ne décrémentent '
        'rien', (tester) async {
      await poste();
      final ids = await garni();
      // Une seconde fiche, VIDE, posée par le DAO de l'écran.
      final container = ProviderContainer(overrides: surcharges());
      addTearDown(container.dispose);
      await container
          .read(restaurantApiProvider)
          .enregistrerRecette(
            const SaisieFiche(libelle: 'Fiche à écrire', lignes: []),
          );

      await monter(tester, const EcranRestauration());
      await toucher(tester, const Key('restauration-onglet-fiches'));
      expect(find.text('Poulet DG'), findsWidgets);
      expect(find.text('Fiche à écrire'), findsOneWidget);
      expect(
        textesSous(tester, const Key('restauration-fiches-kpi-1')),
        contains('1'),
      );

      await toucher(tester, const Key('restauration-fiches-vides'));
      expect(find.text('Fiche à écrire'), findsOneWidget);
      expect(find.byKey(Key('restauration-fiche-${ids.fiche}')), findsNothing);
      // Une fiche vide : « Vide — ne décrémente rien », coût « Non
      // calculable » — pas « 0 F ».
      expect(find.text('Vide — ne décrémente rien'), findsOneWidget);
      expect(find.text('Non calculable'), findsOneWidget);
    });

    testWidgets('modifier un menu : la saison s’affiche, une fin antérieure au '
        'début est refusée', (tester) async {
      final ids = await garni();
      await monter(tester, const EcranRestauration());
      await toucher(tester, const Key('restauration-onglet-menus'));

      await toucher(tester, Key('restauration-menu-modifier-${ids.menu}'));
      await saisir(tester, const Key('modale-menu-debut'), '2026-09-30');
      await saisir(tester, const Key('modale-menu-fin'), '2026-06-01');
      await toucher(tester, const Key('modale-menu-enregistrer'));
      expect(find.text(MessagesRestaurant.saisonInversee), findsOneWidget);
      expect((await db.select(db.menusLocal).getSingle()).dateDebut, isNull);

      await saisir(tester, const Key('modale-menu-debut'), '2026-06-01');
      await saisir(tester, const Key('modale-menu-fin'), '2026-09-30');
      await toucher(tester, const Key('modale-menu-enregistrer'));

      final menu = await db.select(db.menusLocal).getSingle();
      expect((menu.dateDebut, menu.dateFin), ('2026-06-01', '2026-09-30'));
      expect(textesSous(tester, Key('restauration-menu-saison-${ids.menu}')), [
        '01/06/2026 → 30/09/2026',
      ]);
    });
  });

  group('Sans droit', () {
    testWidgets('sans droit de lecture, l’écran refuse et n’affiche AUCUN '
        'chiffre', (tester) async {
      await garni();
      await monter(
        tester,
        const EcranRestauration(),
        avec: surcharges(m4: '-'),
      );

      expect(find.byKey(const Key('restauration-refus')), findsOneWidget);
      expect(find.text(MessagesRestaurant.droitLectureRefuse), findsWidgets);
      // Les cartes ne disent pas « 0 plat » : elles ne savent pas.
      expect(
        textesSous(tester, const Key('restauration-kpi-0')),
        isNot(contains('0')),
      );
    });

    testWidgets('en lecture seule, « Nouveau menu » dit que rien n’est '
        'enregistré', (tester) async {
      await monter(
        tester,
        const EcranRestauration(),
        avec: surcharges(m4: 'L'),
      );
      await toucher(tester, const Key('restauration-nouveau-menu'));
      await saisir(tester, const Key('modale-menu-libelle'), 'Carte');
      await toucher(tester, const Key('modale-menu-enregistrer'));

      expect(find.byKey(const Key('modale-menu-refus')), findsOneWidget);
      expect(find.text(MessagesRestaurant.droitEcritureRefuse), findsOneWidget);
      expect(await db.select(db.menusLocal).get(), isEmpty);
    });
  });

  /* ==================================================================== */
  /* La carte                                                              */
  /* ==================================================================== */

  group('La carte d’un poste NEUF', () {
    testWidgets('est atteignable en production : vide, avec ses raisons, sans '
        'un seul chiffre inventé', (tester) async {
      await monter(tester, const EcranCarteRestaurant());

      expect(find.byKey(const Key('carte-restaurant-vide')), findsOneWidget);
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-articles')),
        contains('0'),
      );
      // Sur une carte vide : pas de taux (« — % de couverture »), pas « 0 % ».
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-lies')),
        contains('0 / 0'),
      );
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-lies')),
        contains('— % de couverture'),
      );
      // Aucun point cuisine : dit.
      expect(
        find.byKey(const Key('carte-restaurant-sans-point-cuisine')),
        findsOneWidget,
      );
      // « Prix provisoires » est COMPTÉ : zéro est une mesure.
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-provisoires')),
        contains('0'),
      );
      // « Retirés du jour » est COMPTÉ depuis la v31 : zéro est une mesure.
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-retires')),
        contains('0'),
      );
      expect(find.textContaining('ne figurent pas sur ce poste'), findsNothing);
    });
  });

  group('La carte lit ce que le poste a écrit', () {
    testWidgets('portions, marque provisoire, fiche et avertissement sur les '
        'ventes', (tester) async {
      await poste();
      final ids = await garni(provisoire: true);
      await monter(tester, const EcranCarteRestaurant());

      // 10 kg / 0,3 kg = 33 portions.
      expect(textesSous(tester, Key('carte-restaurant-portions-${ids.plat}')), [
        '33',
      ]);
      expect(
        find.byKey(Key('carte-restaurant-marque-provisoire-${ids.plat}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('carte-restaurant-marque-corrige-${ids.plat}')),
        findsNothing,
      );
      // La fiche nommée en vert, comme la vue, et son nombre d'ingrédients.
      expect(textesSous(tester, Key('carte-restaurant-fiche-${ids.plat}')), [
        'Recette Poulet DG',
      ]);
      expect(find.text('Fiche technique (1 ingrédient(s))'), findsOneWidget);
      // Le chiffre ne tient pas compte des ventes de ce poste : DIT.
      expect(find.text(MessagesRestaurant.stockSansLesVentes), findsOneWidget);
      // Les compteurs.
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-lies')),
        contains('1 / 1'),
      );
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-provisoires')),
        contains('1'),
      );
      expect(
        find.byKey(const Key('carte-restaurant-sans-point-cuisine')),
        findsNothing,
      );
    });

    testWidgets('une sortie de stock relue : 25 portions, plus 33', (
      tester,
    ) async {
      await poste();
      final ids = await garni();
      await stocks.ajouterMouvement(
        articleId: 'a-poulet',
        pointId: 'p-cui',
        type: TypeMouvement.sortie,
        centiemes: 250,
        motif: 'Vente',
        auteurId: 'u-essai',
      );
      await monter(tester, const EcranCarteRestaurant());

      expect(textesSous(tester, Key('carte-restaurant-portions-${ids.plat}')), [
        '25',
      ]);
    });

    testWidgets('« Rendre indispo. » écrit le retrait d’un plat : « non », '
        'motif sous le nom, KPI, file d’envoi ; « Remettre » le rend', (
      tester,
    ) async {
      await poste();
      final ids = await garni();
      await monter(tester, const EcranCarteRestaurant());
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-retires')),
        contains('0'),
      );

      await toucher(tester, Key('carte-restaurant-rendre-indispo-${ids.plat}'));
      expect(find.byKey(const Key('modale-retrait-carte')), findsOneWidget);
      await saisir(
        tester,
        const Key('retrait-carte-commentaire'),
        'Plus de poulet',
      );
      await toucher(tester, const Key('retrait-carte-confirmer'));

      expect(find.byKey(const Key('modale-retrait-carte')), findsNothing);
      expect(textesSous(tester, Key('carte-restaurant-retrait-${ids.plat}')), [
        'Rupture du jour — Plus de poulet',
      ]);
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-retires')),
        contains('1'),
      );
      expect(
        textesSous(tester, Key('carte-restaurant-disponible-${ids.plat}')),
        ['non'],
      );
      // Un retrait de plat est une `creation` de `indisponibilites_carte`.
      final ops = [
        for (final o in await OperationsSyncDao(
          db,
        ).operations(table: TableSynchronisee.indisponibilitesCarte))
          o.payload,
      ];
      expect(ops, hasLength(1));
      expect(ops.single, contains('"plat_id":"${ids.plat}"'));

      await toucher(tester, Key('carte-restaurant-remettre-${ids.plat}'));
      expect(
        textesSous(tester, Key('carte-restaurant-disponible-${ids.plat}')),
        ['oui'],
      );
      expect(
        find.byKey(Key('carte-restaurant-rendre-indispo-${ids.plat}')),
        findsOneWidget,
      );
    });

    testWidgets('un plat sans fiche composée : « non suivi », sa raison, et '
        'aucune rupture inventée', (tester) async {
      await poste();
      final container = ProviderContainer(overrides: surcharges());
      addTearDown(container.dispose);
      final api = container.read(restaurantApiProvider);
      final menu =
          (await api.enregistrerMenu(
                    const SaisieMenu(libelle: 'Carte', type: 'local'),
                  )
                  as RestaurantRecu<MenuRestaurant>)
              .donnees;
      final fiche =
          (await api.enregistrerRecette(
                    const SaisieFiche(libelle: 'Fiche à écrire', lignes: []),
                  )
                  as RestaurantRecu<Recette>)
              .donnees;
      final plat =
          (await api.enregistrerPlat(
                    SaisiePlat(
                      libelle: 'Salade nue',
                      menuId: menu.id,
                      recetteId: fiche.id,
                      prixVente: '1500',
                    ),
                    modification: false,
                  )
                  as RestaurantRecu<Plat>)
              .donnees;

      await monter(tester, const EcranCarteRestaurant());
      expect(
        find.byKey(Key('carte-restaurant-non-suivi-${plat.id}')),
        findsOneWidget,
      );
      expect(
        find.byKey(Key('carte-restaurant-rupture-${plat.id}')),
        findsNothing,
      );
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-rupture')),
        contains('0'),
      );
      expect(
        textesSous(tester, const Key('carte-restaurant-kpi-sans-lien')),
        contains('1'),
      );
    });
  });

  group('L’export de bout en bout', () {
    testWidgets('le tableur écrit un VRAI fichier : BOM, UTF-8, point-virgule, '
        'nombres bruts, filtre dit', (tester) async {
      await poste();
      await garni(libelle: 'Poulet DG');
      await monter(tester, const EcranCarteRestaurant());

      await toucher(tester, const Key('carte-restaurant-exporter'));
      await toucher(tester, const Key('export-format-excel'));
      await toucher(tester, const Key('export-generer'));

      final octets = octetsExportes(tester);

      // EF BB BF : le BOM qu'attend un Excel en configuration française.
      expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
      final texte = utf8.decode(octets.sublist(3));
      final lignes = const LineSplitter().convert(texte);

      expect(lignes[0], 'Carte du restaurant;Carte complète, aucun filtre');
      expect(
        lignes[2],
        'Article;Categorie;Prix;Ingredients;Portions vendables;Cout matiere;'
        'Marque de prix',
      );
      // Le plat : nombre brut, catégorie du menu, portions et coût calculés.
      // La dernière case (marque de prix) est VIDE : le tarif est ferme.
      expect(lignes[3], 'Poulet DG;Local;4500.00;1;33;750.00;');
      expect(lignes, hasLength(4));
    });

    testWidgets('l’export porte sur les lignes AFFICHÉES, et DIT son filtre', (
      tester,
    ) async {
      await poste();
      await garni(libelle: 'Poulet DG');
      final container = ProviderContainer(overrides: surcharges());
      addTearDown(container.dispose);
      final api = container.read(restaurantApiProvider);
      final menu =
          (await api.menus() as RestaurantRecu<PageRestaurant<MenuRestaurant>>)
              .donnees
              .elements
              .single;
      final fiche =
          (await api.recettes() as RestaurantRecu<PageRestaurant<Recette>>)
              .donnees
              .elements
              .single;
      await api.enregistrerPlat(
        SaisiePlat(
          libelle: 'Riz sauce',
          menuId: menu.id,
          recetteId: fiche.id,
          prixVente: '1500',
        ),
        modification: false,
      );

      await monter(tester, const EcranCarteRestaurant());
      await saisir(tester, const Key('carte-restaurant-recherche'), 'riz');

      await toucher(tester, const Key('carte-restaurant-exporter'));
      await toucher(tester, const Key('export-format-excel'));
      await toucher(tester, const Key('export-generer'));

      final octets = octetsExportes(tester);
      final lignes = const LineSplitter().convert(
        utf8.decode(octets.sublist(3)),
      );

      expect(lignes[0], 'Carte du restaurant;recherche : riz');
      expect(lignes.where((l) => l.startsWith('Riz sauce;')), hasLength(1));
      expect(lignes.where((l) => l.startsWith('Poulet DG;')), isEmpty);
    });

    testWidgets('le PDF (présélectionné) est PRODUIT et enregistré en .pdf', (
      tester,
    ) async {
      await poste();
      await garni(libelle: 'Poulet DG');
      await monter(tester, const EcranCarteRestaurant());

      await toucher(tester, const Key('carte-restaurant-exporter'));
      await toucher(tester, const Key('export-generer'));

      final octets = octetsExportes(tester, type: TypeFichierEnregistre.pdf);
      expect(ascii.decode(octets.sublist(0, 4)), '%PDF');
    });
  });

  /* ==================================================================== */
  /* Les gestes du catalogue : sélection, retrait de la carte              */
  /* ==================================================================== */

  group('Le catalogue des plats : sélection et retrait de la carte', () {
    testWidgets('cocher une ligne compte « 1 sélectionné(s) », « Tout '
        'sélectionner » les prend toutes', (tester) async {
      final ids = await garni();
      await monter(tester, const EcranRestauration());

      expect(find.textContaining('sélectionné(s)'), findsNothing);
      await toucher(tester, Key('restauration-case-${ids.plat}'));
      expect(find.textContaining('1 sélectionné(s)'), findsOneWidget);

      await toucher(tester, Key('restauration-case-${ids.plat}'));
      expect(find.textContaining('sélectionné(s)'), findsNothing);

      await toucher(tester, const Key('restauration-tout'));
      expect(find.textContaining('1 sélectionné(s)'), findsOneWidget);
    });

    testWidgets('« Retirer de la carte » DEMANDE confirmation, écrit le '
        'retrait, l’enfile, et le compteur le suit', (tester) async {
      final ids = await garni(libelle: 'Poulet DG');
      await monter(tester, const EcranRestauration());

      await toucher(tester, Key('restauration-retirer-${ids.plat}'));
      expect(find.text('Retirer « Poulet DG » de la carte ?'), findsOneWidget);

      // Annuler n'écrit rien.
      await toucher(tester, const Key('achats-archivage-annuler'));
      expect(await db.select(db.indisponibilitesCarteLocal).get(), isEmpty);

      await toucher(tester, Key('restauration-retirer-${ids.plat}'));
      await toucher(tester, const Key('achats-archivage-confirmer'));

      final lignes = await db.select(db.indisponibilitesCarteLocal).get();
      expect(lignes, hasLength(1));
      expect(
        find.text('Le plat « Poulet DG » est retiré de la carte.'),
        findsOneWidget,
      );
      expect(
        textesSous(tester, const Key('restauration-kpi-3')),
        containsAll(['RETIRÉS DE LA CARTE', '1']),
      );
      final file = await OperationsSyncDao(db).operations();
      expect(file, isNotEmpty, reason: 'le retrait part au serveur');
    });

    testWidgets('un plat DÉJÀ retiré ne se retire pas deux fois : le verrou '
        'est dit', (tester) async {
      final ids = await garni(libelle: 'Poulet DG');
      await monter(tester, const EcranRestauration());

      await toucher(tester, Key('restauration-retirer-${ids.plat}'));
      await toucher(tester, const Key('achats-archivage-confirmer'));
      await toucher(tester, Key('restauration-retirer-${ids.plat}'));

      expect(
        find.byKey(const Key('achats-archivage-impossible')),
        findsOneWidget,
      );
      expect(
        await db.select(db.indisponibilitesCarteLocal).get(),
        hasLength(1),
      );
    });

    testWidgets('sans droit d’écriture sur M4, le bouton n’est pas offert', (
      tester,
    ) async {
      final ids = await garni();
      await monter(
        tester,
        const EcranRestauration(),
        avec: surcharges(m4: 'L'),
      );
      expect(find.byKey(Key('restauration-retirer-${ids.plat}')), findsNothing);
    });
  });
}
