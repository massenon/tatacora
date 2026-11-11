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
import 'package:tatacora_flutter/features/pos/data/historique_prix_carte_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/changement_prix_carte.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/ecran_carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/providers_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// « Prix » et « Historique des prix » du restaurant, par la CHAÎNE RÉELLE
/// (écran, providers, `RestaurantApi`, `RestaurantDao`, base) — les deux gestes
/// que le poste refusait faute de table de trace (26/10/2026, schéma v38).
///
/// Le cas écrit d'abord ÉCHOUAIT : les deux boutons ne faisaient qu'afficher
/// « n'est pas disponible » (piège 5 : un test qui n'emprunte pas le chemin ne
/// protège pas le chemin).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.enMemoire();
    db.auteurEcriture = () => (login: 'chef', poste: 'CAISSE-1');
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
    final stocks = StocksDao(db);
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

  /// Un menu, une fiche, un plat à [prix] ; [provisoire] pose la marque
  /// « tarif provisoire » du plat.
  Future<String> platDuMenu({
    String prix = '500',
    bool provisoire = false,
  }) async {
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
                    libelle: 'Recette Poulet',
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
                libelle: 'Poulet DG',
                menuId: menu.id,
                recetteId: fiche.id,
                prixVente: prix,
                prixProvisoire: provisoire,
              ),
              modification: false,
            )
            as RestaurantRecu<Plat>)
        .donnees
        .id;
  }

  Future<List<TracePrixLigne>> traces() =>
      db.select(db.historiquePrixCarteLocal).get();

  testWidgets('« Prix » : refus sous le champ (vide, zéro, fraction), puis le '
      'prix change, est TRACÉ, enfilé, et l’historique le montre', (
    tester,
  ) async {
    final plat = await platDuMenu(prix: '500');
    await monter(tester);

    // Aucune trace à la CRÉATION : l'observateur du serveur ne naît qu'à la
    // modification d'un plat existant.
    expect(await traces(), isEmpty);

    await toucher(tester, Key('carte-restaurant-prix-$plat'));
    expect(find.byKey(const Key('modale-prix-plat')), findsOneWidget);
    expect(find.text('Modifier le prix — Poulet DG'), findsOneWidget);
    expect(
      find.text("Le changement est tracé dans l'historique des prix."),
      findsOneWidget,
    );
    // Le champ part du prix actuel, en francs entiers.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('prix-plat-champ')))
          .controller!
          .text,
      '500',
    );

    for (final (saisie, phrase) in [
      ('', MessagesRestaurant.prixObligatoire),
      ('0', MessagesRestaurant.prixNul),
      ('12,5', MessagesRestaurant.prixFractionDeFranc),
      ('abc', MessagesRestaurant.prixIllisible),
    ]) {
      await saisir(tester, const Key('prix-plat-champ'), saisie);
      await toucher(tester, const Key('prix-plat-confirmer'));
      expect(find.byKey(const Key('modale-prix-plat')), findsOneWidget);
      expect(find.text(phrase), findsOneWidget, reason: 'saisie « $saisie »');
    }
    // Rien n'a été écrit par les refus.
    expect((await db.select(db.platsLocal).getSingle()).prixVente, 500);
    expect(await traces(), isEmpty);

    await saisir(tester, const Key('prix-plat-champ'), '650');
    await toucher(tester, const Key('prix-plat-confirmer'));

    expect(find.byKey(const Key('modale-prix-plat')), findsNothing);
    expect(find.text('Prix de « Poulet DG » modifié.'), findsOneWidget);
    expect((await db.select(db.platsLocal).getSingle()).prixVente, 650);

    // La TRACE, écrite dans la même transaction : prix seul (la marque n'a pas
    // bougé), auteur et instant du poste.
    final t = await traces();
    expect(t, hasLength(1));
    expect(
      (t.single.source, t.single.sourceId, t.single.champ),
      ('plat', plat, 'prix_vente'),
    );
    expect((t.single.ancienPrix, t.single.nouveauPrix), ('500.00', '650.00'));
    expect(t.single.par, 'chef');
    expect(t.single.recuDuServeur, isFalse);

    // La FILE : une modification du plat avec le prix — et AUCUNE opération pour
    // la trace (le serveur en est l'unique auteur).
    final ops = await OperationsSyncDao(db).operations();
    expect(
      ops.where((o) => o.table.nomServeur == 'historique_prix_carte'),
      isEmpty,
    );
    final modif = ops.where(
      (o) =>
          o.table == TableSynchronisee.plats &&
          o.type == TypeOperationSync.modification,
    );
    expect(modif, hasLength(1));
    expect(modif.single.payload, contains('"prix_vente":650'));

    // L'historique montre la trace, aux colonnes et aux mots de la vue.
    await toucher(tester, Key('carte-restaurant-historique-prix-$plat'));
    expect(find.byKey(const Key('modale-historique-prix')), findsOneWidget);
    expect(find.text('Historique des prix'), findsWidgets);
    for (final entete in ['Date', 'Champ', 'Ancien', 'Nouveau', 'Par']) {
      expect(find.text(entete), findsOneWidget, reason: entete);
    }
    Finder dansLaModale(String texte) => find.descendant(
      of: find.byKey(const Key('modale-historique-prix')),
      matching: find.text(texte),
    );
    expect(dansLaModale('Prix de vente'), findsOneWidget);
    expect(dansLaModale('500 FCFA'), findsOneWidget);
    expect(dansLaModale('650 FCFA'), findsOneWidget);
    expect(dansLaModale('chef'), findsOneWidget);
    expect(find.byKey(const Key('historique-prix-vide')), findsNothing);
  });

  testWidgets('un plat dont le prix n’a jamais changé : la phrase de la vue, '
      'pas un tableau', (tester) async {
    final plat = await platDuMenu();
    await monter(tester);

    await toucher(tester, Key('carte-restaurant-historique-prix-$plat'));

    expect(find.byKey(const Key('modale-historique-prix')), findsOneWidget);
    expect(
      find.text('Aucun changement de prix enregistré pour cet article.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('historique-prix-tableau')), findsNothing);
  });

  testWidgets('changer le prix d’un plat au tarif PROVISOIRE pose la marque '
      '« corrigé à la main » : DEUX traces, comme le serveur', (tester) async {
    final plat = await platDuMenu(prix: '500', provisoire: true);
    await monter(tester);

    await toucher(tester, Key('carte-restaurant-prix-$plat'));
    await saisir(tester, const Key('prix-plat-champ'), '700');
    await toucher(tester, const Key('prix-plat-confirmer'));

    final t = {
      for (final l in await traces()) l.champ: (l.ancienPrix, l.nouveauPrix),
    };
    expect(t, {
      'prix_vente': ('500.00', '700.00'),
      'prix_corrige_main': ('0.00', '1.00'),
    });

    await toucher(tester, Key('carte-restaurant-historique-prix-$plat'));
    Finder dansLaModale(String texte) => find.descendant(
      of: find.byKey(const Key('modale-historique-prix')),
      matching: find.text(texte),
    );
    expect(dansLaModale('Corrigé à la main'), findsOneWidget);
    expect(dansLaModale('Non'), findsOneWidget);
    expect(dansLaModale('Oui'), findsOneWidget);
  });

  testWidgets('en lecture seule : l’historique se lit, « Prix » n’est pas '
      'offert', (tester) async {
    final plat = await platDuMenu();
    await monter(tester, m4: 'L');

    expect(find.byKey(Key('carte-restaurant-prix-$plat')), findsNothing);
    await toucher(tester, Key('carte-restaurant-historique-prix-$plat'));
    expect(find.byKey(const Key('modale-historique-prix')), findsOneWidget);
  });

  testWidgets('les traces DESCENDUES du serveur (un autre poste) s’affichent '
      'avec leur auteur', (tester) async {
    final plat = await platDuMenu();
    await HistoriquePrixCarteDao(db).inscrireDescendue(
      id: 'srv-1',
      source: SourceCarte.plat,
      sourceId: plat,
      champ: champPrixVente,
      ancien: '500.00',
      nouveau: '550.00',
      par: 'gerant',
      creeLe: DateTime(2026, 10, 25, 9, 30),
    );
    await monter(tester);

    await toucher(tester, Key('carte-restaurant-historique-prix-$plat'));

    Finder dansLaModale(String texte) => find.descendant(
      of: find.byKey(const Key('modale-historique-prix')),
      matching: find.text(texte),
    );
    expect(dansLaModale('gerant'), findsOneWidget);
    expect(dansLaModale('25/10/2026 09:30'), findsOneWidget);
    expect(dansLaModale('550 FCFA'), findsOneWidget);
  });
}
