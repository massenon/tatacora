import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/selecteur_exercice_barre.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/presentation/providers_depenses.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';

/// Le SÉLECTEUR D'EXERCICE global du poste (PO, 20/10/2026,
/// `docs/SPEC_SELECTEUR_EXERCICE.md`) — réplique de `ExerciceConsulte` du
/// serveur : défaut, choix, date de référence, écrans qui le suivent, et la
/// barre aux mots de la vue.
ExerciceComptable _exercice(int annee, StatutExercice statut) =>
    ExerciceComptable(
      id: 'ex-$annee',
      annee: annee,
      dateDebut: '$annee-01-01',
      dateFin: '$annee-12-31',
      statut: statut,
    );

void main() {
  final e2026 = _exercice(2026, StatutExercice.enCloture);
  final e2027 = _exercice(2027, StatutExercice.ouvert);
  final e2025 = _exercice(2025, StatutExercice.cloture);
  final tous = [e2025, e2026, e2027];

  test(
    'le défaut est l’exercice ouvert le plus récent, sinon le plus récent',
    () {
      expect(exerciceParDefaut(tous)?.annee, 2027);
      expect(exerciceParDefaut([e2025, e2026])?.annee, 2026);
      expect(exerciceParDefaut(const []), isNull);
      expect(exerciceConsulteParmi(tous, 'ex-2025')?.annee, 2025);
      expect(exerciceConsulteParmi(tous, 'inconnu')?.annee, 2027);
    },
  );

  test('la date de référence reste dans l’exercice consulté', () {
    final maintenant = DateTime(2027, 2, 10, 9);
    expect(dateDeReference(e2027, maintenant), maintenant);
    expect(dateDeReference(e2026, maintenant), DateTime(2026, 12, 31, 12));
    expect(dateDeReference(null, maintenant), maintenant);
    expect(dansLExercice(e2026, '2026-06-01'), isTrue);
    expect(dansLExercice(e2026, '2027-01-01T08:00:00'), isFalse);
  });

  test('seuls les écrans de la liste suivent le sélecteur', () {
    for (final r in const [
      '/comptabilite',
      '/tableau-de-bord',
      '/etats',
      '/depenses',
      '/facturation',
      '/fournisseurs',
      '/approvisionnement',
      '/paie',
    ]) {
      expect(routeSuitLExercice(r), isTrue, reason: r);
    }
    expect(routeSuitLExercice('/hebergement'), isFalse);
    expect(routeSuitLExercice('/pos'), isFalse);
  });

  test('choisir 2026 : le tableau de bord se cale au 31/12/2026, les dépenses '
      'sont celles de 2026, et revenir rend 2027', () async {
    final depenses = [
      for (final (id, date) in [
        ('d-2025', DateTime(2025, 6, 1)),
        ('d-2027', DateTime(2027, 1, 20)),
      ])
        Depense(
          id: id,
          dateTransaction: date,
          tresorerie: TresorerieDepense.caisse,
          libelle: 'Marché',
          lignes: const [],
          saisieLe: date,
        ),
    ];
    final c = ProviderContainer(
      overrides: [
        exercicesDuPosteProvider.overrideWith(
          (ref) async => tous.reversed.toList(),
        ),
        depensesProvider.overrideWith((ref) async => depenses),
        libellesComptesProvider.overrideWithValue(const LibellesDesComptes()),
      ],
    );
    addTearDown(c.dispose);
    await c.read(exercicesDuPosteProvider.future);
    final abonnement = c.listen(depensesFiltreesProvider, (_, _) {});
    addTearDown(abonnement.close);
    Future<List<String>> ids() async => [
      for (final d in await c.read(depensesFiltreesProvider.future)) d.id,
    ];

    expect(c.read(exerciceConsulteProvider)?.annee, 2027);
    expect(await ids(), ['d-2027']);

    c.read(exerciceChoisiProvider.notifier).choisir('ex-2025');
    expect(c.read(horlogeTableauDeBordProvider)(), DateTime(2025, 12, 31, 12));
    expect(await ids(), ['d-2025']);

    c.read(exerciceChoisiProvider.notifier).revenir();
    expect(c.read(exerciceConsulteProvider)?.annee, 2027);
  });

  Future<void> monter(WidgetTester tester, String route) async {
    tester.view
      ..physicalSize = const Size(1800, 600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          exercicesDuPosteProvider.overrideWith(
            (ref) async => tous.reversed.toList(),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: ColoredBox(
              color: Colors.black,
              child: SelecteurExerciceBarre(routeActive: route),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('la barre : aux mots de la vue, sur les écrans qui le suivent', (
    tester,
  ) async {
    await monter(tester, '/hebergement');
    expect(find.byKey(const Key('choix-exercice')), findsNothing);

    await monter(tester, '/facturation');
    expect(find.text(TextesSelecteurExercice.exercice), findsOneWidget);
    expect(find.text('2027 — ouvert'), findsOneWidget);
    expect(find.byKey(const Key('pastille-exercice')), findsNothing);

    await tester.tap(find.byKey(const Key('choix-exercice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026 — en clôture').last);
    await tester.pumpAndSettle();
    expect(find.text('Vous consultez 2026 (en clôture)'), findsOneWidget);

    await tester.tap(find.text('Revenir à 2027'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pastille-exercice')), findsNothing);
  });
}
