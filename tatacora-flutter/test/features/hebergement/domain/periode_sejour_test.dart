import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';

/// La convention de bornes est la source d'erreur la plus coûteuse du module.
/// Elle est testée seule, avant tout le reste.
void main() {
  PeriodeSejour periode(int jourArrivee, int jourDepart) => PeriodeSejour(
    arrivee: DateTime(2026, 8, jourArrivee),
    depart: DateTime(2026, 8, jourDepart),
  );

  group('Nombre de nuits', () {
    test('arrivée le 10, départ le 12 = 2 nuits', () {
      expect(periode(10, 12).nuits, 2);
    });

    test('une seule nuit', () {
      expect(periode(10, 11).nuits, 1);
    });

    test('un séjour de zéro nuit est refusé à la construction', () {
      expect(
        () => PeriodeSejour(
          arrivee: DateTime(2026, 8, 10),
          depart: DateTime(2026, 8, 10),
        ),
        throwsArgumentError,
      );
    });

    test('un départ antérieur à l’arrivée est refusé', () {
      expect(
        () => PeriodeSejour(
          arrivee: DateTime(2026, 8, 12),
          depart: DateTime(2026, 8, 10),
        ),
        throwsArgumentError,
      );
    });

    /// `fin.difference(debut).inDays` renvoie 1 au lieu de 2 dès qu'un
    /// changement d'heure traverse le séjour. La normalisation à minuit UTC
    /// neutralise le problème — et ce test le prouve sur une bascule réelle
    /// (Europe, dernier dimanche d'octobre).
    test('l’heure de la journée n’influence pas le compte', () {
      final p = PeriodeSejour(
        arrivee: DateTime(2026, 10, 24, 23, 30),
        depart: DateTime(2026, 10, 26, 6, 15),
      );
      expect(p.nuits, 2);
    });

    test('deux instants du même jour donnent la même borne', () {
      final matin = PeriodeSejour(
        arrivee: DateTime(2026, 8, 10, 6),
        depart: DateTime(2026, 8, 12, 6),
      );
      final soir = PeriodeSejour(
        arrivee: DateTime(2026, 8, 10, 22),
        depart: DateTime(2026, 8, 12, 22),
      );
      expect(matin, soir);
    });
  });

  group('Chevauchement — bornes semi-ouvertes', () {
    test('un départ le 12 et une arrivée le 12 ne se chevauchent PAS', () {
      // Le cas décisif : la chambre est libérée le matin, relouée le soir.
      // L'erreur inverse refuse des réservations parfaitement valides.
      expect(periode(10, 12).chevauche(periode(12, 14)), isFalse);
      expect(periode(12, 14).chevauche(periode(10, 12)), isFalse);
    });

    test('deux séjours qui se recouvrent d’une nuit se chevauchent', () {
      expect(periode(10, 13).chevauche(periode(12, 15)), isTrue);
    });

    test('un séjour entièrement inclus dans un autre se chevauche', () {
      expect(periode(10, 20).chevauche(periode(12, 14)), isTrue);
      expect(periode(12, 14).chevauche(periode(10, 20)), isTrue);
    });

    test('deux séjours identiques se chevauchent', () {
      expect(periode(10, 12).chevauche(periode(10, 12)), isTrue);
    });

    test('deux séjours disjoints ne se chevauchent pas', () {
      expect(periode(10, 12).chevauche(periode(20, 22)), isFalse);
    });
  });

  group('Jour contenu', () {
    final p = periode(10, 12);

    test('le jour d’arrivée est occupé', () {
      expect(p.contient(DateTime(2026, 8, 10)), isTrue);
    });

    test('la nuit intermédiaire est occupée', () {
      expect(p.contient(DateTime(2026, 8, 11)), isTrue);
    });

    test('le jour de départ ne l’est PAS', () {
      expect(p.contient(DateTime(2026, 8, 12)), isFalse);
    });

    test('la veille de l’arrivée non plus', () {
      expect(p.contient(DateTime(2026, 8, 9)), isFalse);
    });
  });
}
