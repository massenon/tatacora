import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';

import 'support/outils_comptabilite.dart';

/// Lot 3 (20/10/2026) — la navigation N-1 / N+1 du hub comptable du poste et
/// le statut de l'exercice consulté, aux mots de la vue du hub. Sur une VRAIE
/// base en mémoire : les exercices sont ceux que la descente aligne
/// (`alignerExerciceDescendu`), avec le statut du serveur.
void main() {
  late AppDatabase db;
  late ComptabiliteDao dao;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dao = ComptabiliteDao(db);
  });
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1800, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(const {'M10': 'C'});
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
          home: const Scaffold(body: EcranComptabilite()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final precedent = find.byKey(const Key('compta-exercice-precedent'));
  final suivant = find.byKey(const Key('compta-exercice-suivant'));
  final bandeau = find.byKey(const Key('compta-bandeau-statut'));

  testWidgets('un exercice seul, ouvert : ni navigation ni bandeau', (
    tester,
  ) async {
    await monter(tester);
    expect(precedent, findsNothing);
    expect(suivant, findsNothing);
    expect(bandeau, findsNothing);
  });

  testWidgets(
    'N-1 clôturé au serveur : on y va en un clic, il se dit en lecture seule, '
    'et la saisie y est fermée ; N+1 ramène à l’année',
    (tester) async {
      await dao.alignerExerciceDescendu(
        annee: annee - 1,
        dateDebut: '${annee - 1}-01-01',
        dateFin: '${annee - 1}-12-31',
        statut: StatutExercice.cloture,
        dateCloture: DateTime(annee, 1, 20),
      );
      await monter(tester);

      expect(bandeau, findsNothing);
      expect(
        find.text('← ${TextesComptabilite.exerciceVoisin(annee - 1)}'),
        findsOneWidget,
      );

      await tester.tap(precedent);
      await tester.pumpAndSettle();
      expect(
        find.text(TextesComptabilite.bandeauCloture(annee - 1)),
        findsOneWidget,
      );
      expect(suivant, findsOneWidget);

      // La saisie de N-1 est fermée : aucun « + Nouvelle écriture ».
      await tester.tap(find.byKey(const Key('compta-onglet-saisie')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compta-nouvelle-ecriture')), findsNothing);

      await tester.tap(suivant);
      await tester.pumpAndSettle();
      expect(bandeau, findsNothing);
      expect(find.byKey(const Key('compta-nouvelle-ecriture')), findsOneWidget);
    },
  );

  testWidgets('l’exercice en clôture au serveur le dit, avec les mots de la '
      'vue', (tester) async {
    await dao.alignerExerciceDescendu(
      annee: annee,
      dateDebut: '$annee-01-01',
      dateFin: '$annee-12-31',
      statut: StatutExercice.enCloture,
    );
    await monter(tester);

    // Plus d'exercice ouvert : on choisit celui de l'année.
    final exercices = await dao.exercices();
    expect(exercices.single.statut, StatutExercice.enCloture);
    await tester.tap(find.byType(DropdownButton<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('${TextesComptabilite.exercice} $annee').last);
    await tester.pumpAndSettle();

    expect(
      find.text(TextesComptabilite.bandeauEnCloture(annee)),
      findsOneWidget,
    );
  });
}
