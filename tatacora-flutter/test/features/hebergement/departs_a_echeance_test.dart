import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';

import '../facturation/support/outils_encaissement.dart';

/// `SejourDao.departsAEcheance` — la lecture de `AlertesOuverture::
/// departsAEcheance()` : séjour OUVERT (arrivée réelle, pas de départ réel)
/// dont le départ prévu est AUJOURD'HUI ou avant, comparé au JOUR. La
/// réservation d'essai part le 22/10/2026.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await baseEncaissement();
    final c = await creerClient(db, nom: 'KORA');
    await semerReservation(db, id: 'r1', clientId: c.id);
  });

  tearDown(() => db.close());

  Future<List<String>> departs(DateTime maintenant) async => [
    for (final d in await SejourDao(db).departsAEcheance(maintenant))
      '${d.reservationId}|${d.clientNom}|${d.uniteNumero}',
  ];

  test('avant l’arrivée réelle : aucun séjour, donc aucune ligne', () async {
    expect(await departs(DateTime(2026, 10, 25)), isEmpty);
  });

  test('départ prévu DEMAIN : pas encore à échéance', () async {
    await SejourDao(db).checkin('r1');
    expect(await departs(DateTime(2026, 10, 21, 23, 59)), isEmpty);
  });

  test('départ prévu AUJOURD’HUI (à toute heure) ou dépassé : listé', () async {
    await SejourDao(db).checkin('r1');
    expect(await departs(DateTime(2026, 10, 22, 0, 1)), ['r1|KORA|BNG-01']);
    expect(await departs(DateTime(2026, 10, 22, 23, 59)), ['r1|KORA|BNG-01']);
    expect(await departs(DateTime(2026, 10, 27)), ['r1|KORA|BNG-01']);
  });

  test('après le check-out : plus de ligne', () async {
    final dao = SejourDao(db);
    await dao.checkin('r1');
    await dao.checkout('r1');
    expect(await departs(DateTime(2026, 10, 27)), isEmpty);
  });

  test(
    'checkoutDuSejour : introuvable, puis clos (avec sa DATE), puis réussi',
    () async {
      final dao = SejourDao(db);
      await dao.checkin('r1');
      final sejour = (await db.select(db.sejoursLocal).get()).single;

      await expectLater(
        dao.checkoutDuSejour('zzz'),
        throwsA(
          predicate(
            (e) => '$e'.contains(
              'Ce séjour n’existe plus : rien n’a été modifié.',
            ),
          ),
        ),
      );
      await dao.checkoutDuSejour(sejour.id);
      expect(
        (await db.select(db.unitesHebergementLocal).getSingle()).statut,
        'nettoyage',
      );
      await expectLater(
        dao.checkoutDuSejour(sejour.id),
        throwsA(
          predicate(
            (e) => RegExp(
              r'Le départ a déjà été enregistré le \d{2}/\d{2}/\d{4} \d{2}:\d{2}\.',
            ).hasMatch('$e'),
          ),
        ),
      );
    },
  );
}
