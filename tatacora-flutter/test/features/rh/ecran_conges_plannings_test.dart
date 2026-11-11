import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/rh/data/conges_plannings_dao.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/conge_planning.dart';
import 'package:tatacora_flutter/features/rh/presentation/ecran_conges_plannings.dart';

/// L'écran « Congés & Plannings » monté pour de vrai, contre une vraie base
/// Drift en mémoire (21/10/2026). Chaque cas éprouve un geste de la vue avec
/// ses libellés et ses phrases EXACTS.
void main() {
  late AppDatabase db;
  late String restauration;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await EmployeDao(db).installerServices();
    restauration = (await db.select(db.servicesRhLocal).get())
        .firstWhere((s) => s.libelle == 'Restauration')
        .id;
  });
  tearDown(() => db.close());

  Future<String> embaucher(String nom) async => (await EmployeDao(db).creer(
    nom: nom,
    prenom: 'Test',
    poste: 'Serveur',
    serviceId: restauration,
    dateEmbauche: DateTime(2023, 2, 1),
    salaireBase: 100000,
  )).id;

  Future<void> monter(WidgetTester tester, {String niveau = 'C'}) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson({'M13': niveau}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranCongesPlannings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choisirEmploye(
    WidgetTester tester,
    String cle,
    String nom,
  ) async {
    await tester.tap(find.byKey(Key(cle)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nom).last);
    await tester.pumpAndSettle();
  }

  /// La police de test (Ahem) élargit les tableaux : le bouton peut tomber hors
  /// de la fenêtre. On le ramène avant de cliquer.
  Future<void> toucher(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  testWidgets('à vide : titre, onglets, trois indicateurs et l’état vide de la '
      'vue', (tester) async {
    await monter(tester);

    expect(find.text('Congés & Plannings'), findsOneWidget);
    expect(
      find.text(
        "Plannings d'équipe par jour et demandes de congé avec leur "
        'validation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Plannings'), findsOneWidget);
    expect(find.text('Congés'), findsOneWidget);
    expect(find.text('CRÉNEAUX DU JOUR'), findsOneWidget);
    expect(find.text('DEMANDES EN ATTENTE'), findsOneWidget);
    expect(find.text("EN CONGÉ AUJOURD'HUI"), findsOneWidget);
    expect(find.text('Aucun créneau planifié ce jour.'), findsOneWidget);
    expect(find.text('Planifier un créneau'), findsOneWidget);

    await tester.tap(find.byKey(const Key('conges-plannings-onglet-conges')));
    await tester.pumpAndSettle();
    expect(find.text('Aucune demande de congé.'), findsOneWidget);
    expect(find.text('Demander un congé'), findsOneWidget);
    expect(find.text('Planifier un créneau'), findsNothing);
  });

  testWidgets('un compte en lecture seule ne voit AUCUN bouton d’écriture', (
    tester,
  ) async {
    await monter(tester, niveau: 'L');
    expect(find.byKey(const Key('conges-plannings-planifier')), findsNothing);

    await tester.tap(find.byKey(const Key('conges-plannings-onglet-conges')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('conges-plannings-demander')), findsNothing);
  });

  testWidgets('planifier : le créneau apparaît, le chevauchement est refusé '
      'DANS la modale, saisie conservée', (tester) async {
    await embaucher('ADJIBI');
    await monter(tester);

    await tester.tap(find.byKey(const Key('conges-plannings-planifier')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modale-planning')), findsOneWidget);
    await choisirEmploye(tester, 'modale-planning-employe', 'ADJIBI Test');
    await tester.tap(find.byKey(const Key('modale-planning-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restauration').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modale-planning-valider')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('modale-planning')), findsNothing);
    expect(find.text('Créneau planifié.'), findsOneWidget);
    expect(find.text('ADJIBI Test'), findsOneWidget);
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('16:00'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('conges-plannings-kpi-plannings')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(find.text('Aucun créneau planifié ce jour.'), findsNothing);

    // Le même employé, le même jour, les mêmes heures : RG-13.
    await tester.tap(find.byKey(const Key('conges-plannings-planifier')));
    await tester.pumpAndSettle();
    await choisirEmploye(tester, 'modale-planning-employe', 'ADJIBI Test');
    await tester.tap(find.byKey(const Key('modale-planning-service')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restauration').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('modale-planning-valider')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('modale-planning-refus')),
        matching: find.text(MessagesCongesPlannings.chevauchement),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('modale-planning')), findsOneWidget);
  });

  testWidgets('demander puis valider : sans paramètre la phrase du serveur '
      'est dite sous la ligne ; paramétré, la pastille passe à Validé', (
    tester,
  ) async {
    await embaucher('ADJIBI');
    await monter(tester);
    await tester.tap(find.byKey(const Key('conges-plannings-onglet-conges')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('conges-plannings-demander')));
    await tester.pumpAndSettle();
    await choisirEmploye(tester, 'modale-conge-employe', 'ADJIBI Test');
    await tester.tap(find.byKey(const Key('modale-conge-valider')));
    await tester.pumpAndSettle();

    expect(
      find.text('Demande de congé enregistrée : elle attend sa validation.'),
      findsOneWidget,
    );
    expect(find.text('Congé annuel'), findsOneWidget);
    expect(find.text('En attente'), findsWidgets);
    expect(find.text('Valider'), findsOneWidget);
    expect(find.text('Refuser'), findsOneWidget);

    // Aucun paramètre : RG-14 REFUSE, la demande reste en attente.
    await toucher(tester, find.text('Valider'));
    expect(
      find.text(
        MessagesCongesPlannings.parametreAbsent(
          CongesPlanningsDao.cleDelaiPreavis,
        ),
      ),
      findsOneWidget,
    );
    expect(
      (await CongesPlanningsDao(db).conges()).single.statut,
      StatutConge.enAttente,
    );

    for (final (cle, valeur) in const [
      (CongesPlanningsDao.cleDelaiPreavis, '10'),
      (CongesPlanningsDao.cleCouverture, '0'),
    ]) {
      await db
          .into(db.parametresSystemeLocal)
          .insert(
            ParametresSystemeLocalCompanion.insert(
              cle: cle,
              valeur: valeur,
              modifieLe: DateTime(2026, 10, 21),
            ),
          );
    }
    // Le congé est dans 7 jours pour un préavis de 10.
    await toucher(tester, find.text('Valider'));
    expect(
      find.text(
        MessagesCongesPlannings.preavisInsuffisant(reel: 7, exige: '10'),
      ),
      findsOneWidget,
    );

    await (db.update(db.parametresSystemeLocal)
          ..where((p) => p.cle.equals(CongesPlanningsDao.cleDelaiPreavis)))
        .write(const ParametresSystemeLocalCompanion(valeur: Value('3')));
    await toucher(tester, find.text('Valider'));
    expect(find.text('Congé validé.'), findsOneWidget);
    expect(find.text('Validé'), findsWidgets);
    expect(
      find.text('Valider'),
      findsNothing,
      reason: 'décidée : plus de gestes',
    );
    expect(
      (await CongesPlanningsDao(db).conges()).single.statut,
      StatutConge.valide,
    );
  });

  testWidgets('refuser garde la demande avec sa trace', (tester) async {
    await embaucher('ADJIBI');
    await monter(tester);
    await tester.tap(find.byKey(const Key('conges-plannings-onglet-conges')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('conges-plannings-demander')));
    await tester.pumpAndSettle();
    await choisirEmploye(tester, 'modale-conge-employe', 'ADJIBI Test');
    await tester.tap(find.byKey(const Key('modale-conge-valider')));
    await tester.pumpAndSettle();

    await toucher(tester, find.text('Refuser'));

    expect(
      find.text('Congé refusé : la demande est conservée.'),
      findsOneWidget,
    );
    expect(find.text('Refusé'), findsWidgets);
    expect(await CongesPlanningsDao(db).conges(), hasLength(1));
  });
}
