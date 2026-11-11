import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/sejour_au_pos.dart';

/// PO 10/11/2026 : AUCUNE règle de période au POS hébergés (même règle que le web).
void main() {
  Reservation r(DateTime arrivee, DateTime depart, StatutReservation statut) =>
      Reservation(
        id: 'r',
        reference: 'RES-r',
        clientId: 'c',
        clientNom: 'Jean KORA',
        uniteId: 'u',
        periode: PeriodeSejour(arrivee: arrivee, depart: depart),
        tarifNuit: 10000,
        statut: statut,
        statutSynchronisation: StatutSynchronisation.synchronise,
        creeeLe: DateTime(2026, 11, 1),
      );

  test(
    'en attente, confirmée, en cours : offertes, quelles que soient les dates',
    () {
      for (final s in [
        StatutReservation.enAttente,
        StatutReservation.confirmee,
        StatutReservation.enCours,
      ]) {
        for (final dates in [
          [
            DateTime(2099, 1, 1),
            DateTime(2099, 1, 3),
          ], // dans le futur (décalée)
          [
            DateTime(2020, 1, 1),
            DateTime(2020, 1, 3),
          ], // dans le passé (rallongée)
        ]) {
          expect(
            estSejourAuPos(r(dates[0], dates[1], s)),
            isTrue,
            reason: '$s',
          );
        }
      }
    },
  );

  test('annulée et terminée : jamais', () {
    for (final s in [StatutReservation.annulee, StatutReservation.terminee]) {
      expect(
        estSejourAuPos(r(DateTime(2026, 11, 9), DateTime(2026, 11, 12), s)),
        isFalse,
      );
    }
  });
}
