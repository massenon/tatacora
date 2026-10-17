import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart'
    show StatutUniteLocal;
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_sejour.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import '../facturation/support/outils_encaissement.dart'
    show creerClient, semerReservation;

/// `SejourDao` — check-in / check-out, réplique de `SejourService` (lot C du
/// 14/10/2026, D408). Ce que ces cas tiennent : les refus tombent dans
/// l'ORDRE du serveur, et le refus « unité hors service », qui arrive APRÈS
/// les premières écritures, EMPORTE la transaction entière (rien n'est écrit).
void main() {
  late AppDatabase db;
  late SejourDao dao;
  final heure = DateTime(2026, 10, 20, 14);

  setUp(() async {
    db = AppDatabase.enMemoire();
    final c = await creerClient(db);
    await semerReservation(db, id: 'r1', clientId: c.id);
    dao = SejourDao(db, maintenant: () => heure);
  });

  tearDown(() => db.close());

  Future<void> poserUnite(String statut) =>
      (db.update(db.unitesHebergementLocal)..where((u) => u.id.equals('u-1')))
          .write(UnitesHebergementLocalCompanion(statut: Value(statut)));

  Future<void> poserReservation(String statut) =>
      (db.update(db.reservationsLocal)..where((r) => r.id.equals('r1'))).write(
        ReservationsLocalCompanion(statut: Value(statut)),
      );

  Future<String> statutUnite() async =>
      (await db.select(db.unitesHebergementLocal).getSingle()).statut;

  Future<String> statutReservation() async => (await (db.select(
    db.reservationsLocal,
  )..where((r) => r.id.equals('r1'))).getSingle()).statut;

  Future<int> sejours() async =>
      (await db.select(db.sejoursLocal).get()).length;

  Future<void> refus(Future<void> Function() geste, String message) =>
      expectLater(
        geste(),
        throwsA(
          isA<RefusSejour>().having((e) => e.message, 'message', message),
        ),
      );

  group('Check-in', () {
    test(
      'écrit le séjour, la réservation EN COURS et l’unité OCCUPÉE',
      () async {
        await dao.checkin('r1');
        final s = await db.select(db.sejoursLocal).getSingle();
        expect(s.reservationId, 'r1');
        expect(s.dateCheckinReel, heure);
        expect(s.dateCheckoutReel, isNull);
        expect(await statutReservation(), 'en_cours');
        expect(await statutUnite(), StatutUniteLocal.occupee);
      },
    );

    test('ORDRE du serveur : annulée AVANT unité hors service', () async {
      await poserReservation('annulee');
      await poserUnite(StatutUniteLocal.horsService);
      await refus(() => dao.checkin('r1'), MessagesSejour.reservationAnnulee);
      expect(await sejours(), 0);
    });

    test(
      'ORDRE du serveur : séjour déjà commencé AVANT unité hors service',
      () async {
        await dao.checkin('r1');
        await poserUnite(StatutUniteLocal.horsService);
        await refus(
          () => dao.checkin('r1'),
          MessagesSejour.dejaArrive(dateHeureCommeServeur(heure)),
        );
        expect(await sejours(), 1);
      },
    );

    test('réservation inconnue : refusée', () async {
      await refus(
        () => dao.checkin('fantome'),
        MessagesSejour.reservationIntrouvable,
      );
    });

    test('unité HORS SERVICE : le refus tombe après les écritures et EMPORTE '
        'la transaction — ni séjour, ni statut changé', () async {
      await poserUnite(StatutUniteLocal.horsService);
      await refus(
        () => dao.checkin('r1'),
        MessagesSejour.uniteHorsService('BNG-01'),
      );
      expect(await sejours(), 0);
      expect(await statutReservation(), 'confirmee');
      expect(await statutUnite(), StatutUniteLocal.horsService);
    });
  });

  group('Check-out', () {
    test('ferme le séjour, réservation TERMINÉE, unité en NETTOYAGE (jamais '
        '« libre »)', () async {
      await dao.checkin('r1');
      await dao.checkout('r1');
      final s = await db.select(db.sejoursLocal).getSingle();
      expect(s.dateCheckoutReel, heure);
      expect(await statutReservation(), 'terminee');
      expect(await statutUnite(), StatutUniteLocal.nettoyage);
    });

    test('sans séjour ouvert : la phrase du composant, date VIDE', () async {
      await refus(() => dao.checkout('r1'), MessagesSejour.dejaParti(''));
      await dao.checkin('r1');
      await dao.checkout('r1');
      await refus(() => dao.checkout('r1'), MessagesSejour.dejaParti(''));
    });

    test('unité HORS SERVICE : le départ n’est PAS enregistré (transaction '
        'annulée)', () async {
      await dao.checkin('r1');
      await poserUnite(StatutUniteLocal.horsService);
      await refus(
        () => dao.checkout('r1'),
        MessagesSejour.uniteHorsService('BNG-01'),
      );
      final s = await db.select(db.sejoursLocal).getSingle();
      expect(s.dateCheckoutReel, isNull);
      expect(await statutReservation(), 'en_cours');
    });
  });

  group(
    'synchronisation (lot F5) : l’arrivée et le départ partent au serveur',
    () {
      test('le check-in enfile l’ARRIVÉE à l’heure du poste ; le check-out le '
          'DÉPART du même séjour', () async {
        await dao.checkin('r1');
        final sejour = await db.select(db.sejoursLocal).getSingle();
        await dao.checkout('r1');

        final ops = [
          for (final o in await OperationsSyncDao(db).operations())
            if (o.table.nomServeur == 'sejours') o,
        ];
        expect(ops.map((o) => '${o.type.code} ${o.table.nomServeur}'), [
          'creation sejours',
          'modification sejours',
        ]);
        expect(ops.every((o) => o.entiteId == sejour.id), isTrue);
        expect(ops.first.payload, contains('"reservation_id":"r1"'));
        expect(
          ops.first.payload,
          contains('"date_checkin_reel":"2026-10-20 14:00:00"'),
        );
        expect(
          ops.last.payload,
          contains('"date_checkout_reel":"2026-10-20 14:00:00"'),
        );
      });

      test('un check-in REFUSÉ n’enfile rien', () async {
        await poserReservation('annulee');
        await expectLater(dao.checkin('r1'), throwsA(isA<RefusSejour>()));
        expect(
          (await OperationsSyncDao(
            db,
          ).operations()).where((o) => o.table.nomServeur == 'sejours'),
          isEmpty,
        );
      });
    },
  );
}
