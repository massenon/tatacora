import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart'
    show horlogeTableauDeBordProvider;
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/reservations_du_jour.dart';

import '../comptabilite/support/outils_comptabilite.dart' show exerciceClos;
import '../facturation/support/outils_encaissement.dart';

/// « Payer » du tableau « Réservations du jour » de l'accueil (lot C du
/// 14/10/2026). Le geste passe par `PaiementsFactureDao` : le paiement ET sa
/// pièce (Dr trésorerie / Cr 4111) dans la MÊME transaction ; une pièce
/// refusée n'écrit RIEN, et la modale reste ouverte avec le motif.
void main() {
  late AppDatabase db;
  final jour = DateTime(2026, 10, 21, 9);

  tearDown(() => db.close());

  /// Un client, sa réservation du 20 au 22/10 (en cours le 21), une facture
  /// d'hébergement LIÉE de 50 000 F, et la caisse ouverte.
  Future<void> semer() async {
    final c = await creerClient(db);
    await semerReservation(db, id: 'r1', clientId: c.id);
    await emettreFacture(
      db,
      montant: 50000,
      clientId: c.id,
      reservationId: 'r1',
      module: ModuleFacturable.m1Hebergement,
    );
    await ouvrirCaissePour(db);
  }

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...surchargesEncaissement(
            db,
            droits: const {'M1': 'C', 'M2': 'C', 'M11': 'C'},
          ),
          horlogeTableauDeBordProvider.overrideWithValue(() => jour),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(
            body: SingleChildScrollView(child: TableReservationsDuJour()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> payer(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('tdb-payer-r1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tdb-modale-payer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('tdb-payer-confirmer')));
    await tester.pumpAndSettle();
  }

  testWidgets('le paiement ET sa pièce (Dr 5711 / Cr 4111) sont écrits '
      'ensemble ; « Payer » disparaît une fois la facture soldée', (
    tester,
  ) async {
    db = await baseEncaissement();
    await tester.runAsync(semer);
    await monter(tester);

    await payer(tester);

    expect(find.byKey(const Key('tdb-modale-payer')), findsNothing);
    expect(find.byKey(const Key('tdb-payer-succes')), findsOneWidget);
    final (paiements, comptes) = (await tester.runAsync(() async {
      final cdao = ComptabiliteDao(db);
      return (
        await compterLignes(db, 'paiements_facture_local'),
        [
          for (final e in await cdao.toutesLesEcritures())
            ((await cdao.compteParId(e.compteId))!.numero, e.debitCentimes),
        ],
      );
    }))!;
    expect(paiements, 1);
    expect(comptes, [('5711', 5000000), ('4111', 0)]);
    expect(find.byKey(const Key('tdb-payer-r1')), findsNothing);
  });

  testWidgets('une pièce REFUSÉE (aucun exercice ouvert) n’écrit RIEN : ni '
      'paiement, ni écriture ; la modale reste ouverte avec le motif', (
    tester,
  ) async {
    // Référentiel installé en 2025, et l'exercice du jour CLÔTURÉ (manquant,
    // il s'ouvrirait de lui-même depuis le 20/10/2026).
    db = await baseEncaissement(maintenant: DateTime(2025, 6, 1));
    await tester.runAsync(() => exerciceClos(db, jourEncaissement.year));
    await tester.runAsync(semer);
    await monter(tester);

    await payer(tester);

    expect(find.byKey(const Key('tdb-modale-payer')), findsOneWidget);
    expect(find.byKey(const Key('tdb-payer-succes')), findsNothing);
    final compte = (await tester.runAsync(
      () async => (
        await compterLignes(db, 'paiements_facture_local'),
        await compterLignes(db, 'ecritures_local'),
      ),
    ))!;
    expect(compte, (0, 0));
  });
}
