import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/regles_ecriture.dart';

/// Les règles de gestion en FONCTIONS PURES : sans base, sans horloge. La
/// confrontation au serveur est dans `moteur_contre_serveur_test.dart`.
void main() {
  ExerciceComptable exercice(int annee, StatutExercice statut) =>
      ExerciceComptable(
        id: 'e$annee',
        annee: annee,
        dateDebut: '$annee-01-01',
        dateFin: '$annee-12-31',
        statut: statut,
      );

  MotifRefus? motifDe(void Function() action) {
    try {
      action();
    } on RefusComptable catch (e) {
      return e.motif;
    }
    return null;
  }

  group('verifierEquilibre — en entiers', () {
    test('équilibrée : aucun refus', () {
      verifierEquilibre([
        (debitCentimes: 1000, creditCentimes: 0),
        (debitCentimes: 0, creditCentimes: 600),
        (debitCentimes: 0, creditCentimes: 400),
      ]);
    });

    test('un centime d’écart dans chaque sens', () {
      for (final lignes in [
        [
          (debitCentimes: 1001, creditCentimes: 0),
          (debitCentimes: 0, creditCentimes: 1000),
        ],
        [
          (debitCentimes: 1000, creditCentimes: 0),
          (debitCentimes: 0, creditCentimes: 1001),
        ],
      ]) {
        expect(
          motifDe(() => verifierEquilibre(lignes)),
          MotifRefus.pieceDesequilibree,
        );
      }
    });

    test('la phrase porte débit, crédit et écart signé', () {
      try {
        verifierEquilibre([
          (debitCentimes: 750, creditCentimes: 0),
          (debitCentimes: 0, creditCentimes: 1000),
        ]);
        fail('refus attendu');
      } on RefusComptable catch (e) {
        expect(e.message, contains('7.50 au débit contre 10.00 au crédit'));
        expect(e.message, contains('écart de -2.50'));
      }
    });

    test('zéro = zéro : équilibrée mais sans montant', () {
      expect(
        motifDe(
          () => verifierEquilibre([(debitCentimes: 0, creditCentimes: 0)]),
        ),
        MotifRefus.pieceSansMontant,
      );
    });

    test('le déséquilibre prime sur la pièce à zéro', () {
      expect(
        motifDe(
          () => verifierEquilibre([
            (debitCentimes: 5, creditCentimes: 0),
            (debitCentimes: 0, creditCentimes: 0),
          ]),
        ),
        MotifRefus.pieceDesequilibree,
      );
    });

    test('pièce vide', () {
      expect(motifDe(() => verifierPieceNonVide(0)), MotifRefus.pieceVide);
      expect(motifDe(() => verifierPieceNonVide(1)), isNull);
    });
  });

  group('verifierContraintesDeLigne', () {
    test(
      'négatif, ou débit ET crédit : refusé ; débit seul, crédit seul, zéro : admis',
      () {
        expect(
          motifDe(
            () => verifierContraintesDeLigne((
              debitCentimes: -1,
              creditCentimes: 0,
            )),
          ),
          MotifRefus.contrainteBase,
        );
        expect(
          motifDe(
            () => verifierContraintesDeLigne((
              debitCentimes: 0,
              creditCentimes: -1,
            )),
          ),
          MotifRefus.contrainteBase,
        );
        expect(
          motifDe(
            () => verifierContraintesDeLigne((
              debitCentimes: 1,
              creditCentimes: 1,
            )),
          ),
          MotifRefus.contrainteBase,
        );
        for (final ok in [
          (debitCentimes: 5, creditCentimes: 0),
          (debitCentimes: 0, creditCentimes: 5),
          (debitCentimes: 0, creditCentimes: 0),
        ]) {
          expect(motifDe(() => verifierContraintesDeLigne(ok)), isNull);
        }
      },
    );
  });

  group('Exercice', () {
    test('estDateIso : le calendrier réel', () {
      for (final ok in ['2031-01-01', '2032-02-29', '2031-12-31']) {
        expect(estDateIso(ok), isTrue, reason: ok);
      }
      for (final ko in [
        '2031-02-30',
        '2031-02-29',
        '2031-13-01',
        'hier',
        '',
        '2031-1-1',
        '2031-01-01 ',
      ]) {
        expect(estDateIso(ko), isFalse, reason: ko);
      }
    });

    test('exerciceCouvrant : bornes comprises, date invalide = aucun', () {
      final exs = [
        exercice(2030, StatutExercice.cloture),
        exercice(2031, StatutExercice.ouvert),
      ];
      expect(exerciceCouvrant(exs, '2031-01-01')?.annee, 2031);
      expect(exerciceCouvrant(exs, '2031-12-31')?.annee, 2031);
      expect(exerciceCouvrant(exs, '2030-12-31')?.annee, 2030);
      expect(exerciceCouvrant(exs, '2032-01-01'), isNull);
      expect(exerciceCouvrant(exs, '2031-02-30'), isNull);
      expect(exerciceCouvrant(exs, 'n’importe quoi'), isNull);
    });

    test('exerciceOuvertPour : absent, en clôture, clôturé, ouvert', () {
      final exs = [
        exercice(2029, StatutExercice.enCloture),
        exercice(2030, StatutExercice.cloture),
        exercice(2031, StatutExercice.ouvert),
      ];
      expect(exerciceOuvertPour(exs, '2031-06-01').annee, 2031);
      expect(
        motifDe(() => exerciceOuvertPour(exs, '2032-06-01')),
        MotifRefus.exerciceAbsent,
      );
      expect(
        motifDe(() => exerciceOuvertPour(exs, '2029-06-01')),
        MotifRefus.exerciceNonOuvert,
      );
      expect(
        motifDe(() => exerciceOuvertPour(exs, '2030-06-01')),
        MotifRefus.exerciceNonOuvert,
      );
      try {
        exerciceOuvertPour(exs, '2029-06-01');
      } on RefusComptable catch (e) {
        expect(e.message, contains('L\'exercice 2029 est en_cloture'));
      }
    });
  });

  group('Imputabilité et centre', () {
    const plan = ['6', '60', '601', '6011', '6012', '131', '139', '552', '55'];

    test('une division (sous-comptes au plan) n’est pas imputable', () {
      expect(estDivision('6', plan), isTrue);
      expect(estDivision('60', plan), isTrue);
      expect(estDivision('601', plan), isTrue);
      expect(
        estDivision('55', plan),
        isTrue,
        reason: '552 est son sous-compte',
      );
    });

    test('une feuille à moins de 4 chiffres l’est : 552, 131, 139', () {
      for (final f in ['552', '131', '139']) {
        expect(estDivision(f, plan), isFalse, reason: f);
      }
    });

    test('4 chiffres ou plus : toujours imputable', () {
      expect(estDivision('6011', [...plan, '60111']), isFalse);
    });

    CompteDuPlan compte({String? centre}) => CompteDuPlan(
      id: 'c',
      numero: '6011',
      libelle: 'Achats',
      classe: '6',
      nature: 'charge',
      centreCoutDefautId: centre,
    );

    test('centre : explicite, sinon défaut du compte, sinon refus RG-12', () {
      expect(
        centrePour(
          centreExplicite: 'X',
          compte: compte(centre: 'D'),
        ),
        'X',
      );
      expect(
        centrePour(centreExplicite: null, compte: compte(centre: 'D')),
        'D',
      );
      expect(
        motifDe(() => centrePour(centreExplicite: null, compte: compte())),
        MotifRefus.centreAbsent,
      );
      expect(
        motifDe(() => centrePour(centreExplicite: '', compte: compte())),
        MotifRefus.centreAbsent,
      );
    });
  });

  test('numéro de pièce : CODE-AAAA-NNNNN, sur cinq chiffres au moins', () {
    expect(formaterNumeroPiece('VTE', 2031, 1), 'VTE-2031-00001');
    expect(formaterNumeroPiece('ACH', 2026, 42), 'ACH-2026-00042');
    expect(formaterNumeroPiece('OD', 2031, 100000), 'OD-2031-100000');
  });

  test('libellé de contre-passation : celui du serveur', () {
    expect(libelleContrepassation('Vente'), 'Contre-passation — Vente');
  });
}
