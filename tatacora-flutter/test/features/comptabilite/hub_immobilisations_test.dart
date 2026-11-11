import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/immobilisations_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/modales_immobilisations.dart'
    show montantFcfa;
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/outils_comptabilite.dart';

/// L'onglet « Immobilisations » du hub (21/10/2026) : le tableau de
/// l'exercice, la recherche, « + Immobilisation », la modale de création et la
/// modale « Plan » — sur une VRAIE base en mémoire. Chaque cas qui écrit RELIT
/// la base et la file d'envoi (piège 5).
void main() {
  late AppDatabase db;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
  });
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {String droit = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': droit});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
          droitsProvider.overrideWithValue(garde),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'compta-$auteurEssai',
              nom: 'Comptable',
              role: 'comptable',
              droits: garde,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranComptabilite(ongletInitial: 'immo')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> semer(String libelle, int valeur, int duree, String date) =>
      ImmobilisationsDao(db).creer(
        libelle: libelle,
        valeurOrigineCentimes: valeur,
        dureeAnnees: duree,
        dateMiseService: date,
      );

  Future<int> envois() async => (await OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.immobilisations)).length;

  testWidgets('sans immobilisation : la phrase de la vue, pas un tableau '
      'blanc', (tester) async {
    await monter(tester);
    expect(find.byKey(const Key('compta-non-calcule-immo')), findsNothing);
    expect(find.text('Aucune immobilisation enregistrée.'), findsOneWidget);
    expect(find.byKey(const Key('compta-immo-tableau')), findsNothing);
    expect(
      find.textContaining('Durée d’utilité : une estimation de l’entité'),
      findsOneWidget,
    );
  });

  testWidgets('le tableau de l’exercice : brut, dotation, cumul, VNC et pied '
      'TOTAL', (tester) async {
    await semer('Toyota Land Cruiser Prado', 120000000, 4, '$annee-03-15');
    await semer('Groupe électrogène', 50000000, 5, '${annee - 1}-12-01');
    await monter(tester);

    expect(
      find.text('Tableau des immobilisations — exercice $annee'),
      findsOneWidget,
    );
    expect(find.text('Toyota Land Cruiser Prado'), findsOneWidget);
    expect(find.text('IMMO-$annee-00001'), findsOneWidget);
    expect(find.textContaining('mise en service 15/03/$annee'), findsOneWidget);
    expect(find.text('4 ans'), findsOneWidget);
    // Prado : 1 200 000 / 4 = 300 000 ; 10 mois sur 12 = 250 000 la première
    // année. Groupe : 500 000 / 5 = 100 000, un mois sur 12 la première année
    // (8 333,33), puis 100 000 l'année suivante.
    // Prado : dotation de l'exercice 250 000, VNC 950 000 ; Groupe : cumul
    // 8 333,33 + 100 000, VNC 391 666,67 ; pied : brut 1 700 000.
    expect(
      find.text(montantFcfa(25000000)),
      findsNWidgets(2),
    ); // dotation = cumul
    expect(find.text(montantFcfa(95000000)), findsNWidgets(1));
    expect(find.text(montantFcfa(10833333)), findsNWidgets(1));
    expect(find.text(montantFcfa(39166667)), findsNWidgets(1));
    expect(find.text(montantFcfa(170000000)), findsNWidgets(1));
    expect(find.text('TOTAL'), findsOneWidget);
  });

  testWidgets('la recherche filtre sur le libellé ; aucune correspondance : '
      'la phrase du filtre', (tester) async {
    await semer('Toyota Land Cruiser Prado', 120000000, 4, '$annee-03-15');
    await semer('Groupe électrogène', 50000000, 5, '$annee-01-10');
    await monter(tester);

    await tester.enterText(
      find.byKey(const Key('compta-immo-recherche')),
      'groupe',
    );
    await tester.pumpAndSettle();
    expect(find.text('Groupe électrogène'), findsOneWidget);
    expect(find.text('Toyota Land Cruiser Prado'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('compta-immo-recherche')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Aucune immobilisation ne correspond à cette recherche.'),
      findsOneWidget,
    );
  });

  testWidgets('« Plan » ouvre le plan calculé, prorata et total compris, et '
      'n’écrit rien', (tester) async {
    await semer('Toyota Land Cruiser Prado', 120000000, 4, '$annee-03-15');
    await monter(tester);
    final avant = await envois();

    final id = (await db.select(db.immobilisationsLocal).getSingle()).id;
    final plan = find.byKey(Key('compta-immo-plan-$id'));
    await tester.ensureVisible(plan);
    await tester.tap(plan);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-plan-amortissement')), findsOneWidget);
    final resume = tester.widget<Text>(
      find.byKey(const Key('modale-plan-resume')),
    );
    expect(
      resume.data,
      endsWith('· 4 ans · linéaire · mise en service 15/03/$annee'),
    );
    expect(
      find.textContaining('prorata 10/12', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('${annee + 4}', findRichText: true),
      findsWidgets,
    );
    expect(find.text('TOTAL'), findsWidgets);
    expect(
      find.textContaining('La dernière annuité absorbe l’arrondi'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('modale-plan-fermer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modale-plan-amortissement')), findsNothing);
    expect(await envois(), avant);
  });

  testWidgets('la modale crée l’immobilisation : ligne, file, tableau et '
      'phrase de succès', (tester) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('compta-immo-ajouter')));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle immobilisation'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('modale-immobilisation-libelle')),
      'Camionnette',
    );
    await tester.enterText(
      find.byKey(const Key('modale-immobilisation-valeur')),
      '3500000',
    );
    await tester.enterText(
      find.byKey(const Key('modale-immobilisation-date')),
      '01/02/$annee',
    );
    await tester.enterText(
      find.byKey(const Key('modale-immobilisation-duree')),
      '7',
    );
    await tester.tap(
      find.byKey(const Key('modale-immobilisation-enregistrer')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-immobilisation')), findsNothing);
    expect(
      find.text('Immobilisation IMMO-$annee-00001 enregistrée.'),
      findsOneWidget,
    );
    final lignes = await db.select(db.immobilisationsLocal).get();
    expect(lignes, hasLength(1));
    expect(
      [lignes.single.libelle, lignes.single.valeurOrigineCentimes],
      ['Camionnette', 350000000],
    );
    expect(lignes.single.dateMiseService, '$annee-02-01');
    expect(await envois(), 1);
    expect(find.text('Camionnette'), findsOneWidget);
  });

  testWidgets('un refus du service est DIT dans la modale, rien n’est écrit', (
    tester,
  ) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('compta-immo-ajouter')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('modale-immobilisation-enregistrer')),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('modale-immobilisation-refus')),
        matching: find.text("Le libellé de l'immobilisation est obligatoire."),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('modale-immobilisation')), findsOneWidget);
    expect(await db.select(db.immobilisationsLocal).get(), isEmpty);
    expect(await envois(), 0);

    await tester.enterText(
      find.byKey(const Key('modale-immobilisation-libelle')),
      'Camionnette',
    );
    await tester.tap(
      find.byKey(const Key('modale-immobilisation-enregistrer')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text("La valeur d'origine doit être strictement positive."),
      findsOneWidget,
    );
  });

  testWidgets('sans le droit d’écrire sur M10, « + Immobilisation » le dit', (
    tester,
  ) async {
    await monter(tester, droit: 'L');
    await tester.tap(find.byKey(const Key('compta-immo-ajouter')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('compta-immo-sans-droit')), findsOneWidget);
    expect(find.byKey(const Key('modale-immobilisation')), findsNothing);
  });
}
