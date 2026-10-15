@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// La conversion chaîne décimale <-> centimes, CONFRONTÉE à `bcadd($v, '0', 2)`
/// (PHP exécuté) : troncature, signe, refus.
void main() {
  const cas = <String>[
    '0',
    '0.00',
    '12500',
    '12500.00',
    '12500.5',
    '12500.50',
    '10.999',
    '10.991',
    '0.001',
    '-0.001',
    '-3.5',
    '-3.55',
    '-0.5',
    '.5',
    '5.',
    '+7.25',
    '1',
    '99999999999999.99',
    '0.1',
    '0.2',
    '0.30',
    '  12.5  ',
    'abc',
    '',
    '1,5',
    '1e3',
    '--1',
    '12.5.3',
    '0x10',
  ];

  test(
    'chaque chaîne donne la sortie de bcadd, ou un refus comme lui',
    () async {
      final r = await executerPhp(
        'exporter_montants.php',
        entree: {'montants': cas},
      );
      final attendus = (r['montants'] as List<dynamic>).cast<String?>();
      expect(attendus, hasLength(cas.length));

      var lisibles = 0;
      var refuses = 0;
      for (var i = 0; i < cas.length; i++) {
        final attendu = attendus[i];
        if (attendu == null) {
          refuses++;
          expect(
            () => centimesDepuisChaine(cas[i]),
            throwsFormatException,
            reason: 'bcadd refuse « ${cas[i]} »',
          );
        } else {
          lisibles++;
          expect(
            chaineDepuisCentimes(centimesDepuisChaine(cas[i])),
            attendu,
            reason: 'bcadd(« ${cas[i]} ») = $attendu',
          );
        }
      }
      // Non vide : les deux branches ont réellement été éprouvées.
      expect(lisibles, greaterThan(15));
      expect(refuses, greaterThan(4));
    },
  );

  test('la troncature ne ARRONDIT jamais : 10.999 donne 1099 centimes', () {
    expect(centimesDepuisChaine('10.999'), 1099);
    expect(centimesDepuisChaine('-10.999'), -1099);
  });

  test('l’unité de calcul est l’entier : 0,10 + 0,20 = 0,30 exactement', () {
    expect(
      centimesDepuisChaine('0.1') + centimesDepuisChaine('0.2'),
      centimesDepuisChaine('0.3'),
    );
  });

  test('aller-retour sans perte sur des centimes entiers', () {
    for (final c in [
      0,
      1,
      99,
      100,
      101,
      -1,
      -99,
      -100,
      123456789,
      -987654321,
    ]) {
      expect(centimesDepuisChaine(chaineDepuisCentimes(c)), c);
    }
  });

  test('LigneDemandee.depuisMontants convertit, ou refuse avec un motif', () {
    final l = LigneDemandee.depuisMontants(
      compte: '5711',
      debit: '12500.5',
      credit: null,
    );
    expect(l.debitCentimes, 1250050);
    expect(l.creditCentimes, 0);

    try {
      LigneDemandee.depuisMontants(compte: '5711', debit: 'douze');
      fail('Un montant illisible devait être refusé.');
    } on RefusComptable catch (e) {
      expect(e.motif, MotifRefus.montantIllisible);
      expect(e.message, contains('douze'));
    }
  });
}
