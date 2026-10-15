import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/format/decimal_bc.dart';
import 'package:tatacora_flutter/features/hebergement/domain/annulation_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/annulation_enregistree.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';

/// L'annulation avec commission et remboursement, en FONCTIONS PURES (réplique
/// de `AnnulationReservationService` et de la validation du composant).
///
/// La confrontation au vrai serveur (`annulation_contre_serveur_test.dart`)
/// compare ces mêmes calculs sur huit annulations réelles ; ces cas-ci portent
/// des valeurs CALCULÉES À LA MAIN, et les frontières (24 h pile, acompte pile).
void main() {
  group('Le délai — INFORMATIF, jamais un automatisme', () {
    final arrivee = DateTime(2031, 7, 10);

    test('minuit du jour d’arrivée sert de référence', () {
      // 9 juillet 10:00 -> 10 juillet 00:00 : 14 heures.
      expect(delaiHeuresAvantArrivee(arrivee, DateTime(2031, 7, 9, 10)), 14.0);
    });

    test('la frontière de 24 h : 24 h pile n’est PAS sous le seuil, 23 h 59 '
        'l’est', () {
      expect(estSousLeSeuil(arrivee, DateTime(2031, 7, 9)), isFalse);
      expect(estSousLeSeuil(arrivee, DateTime(2031, 7, 9, 0, 1)), isTrue);
    });

    test('une arrivée DÉJÀ PASSÉE est négative — et sous le seuil, comme au '
        'serveur', () {
      final d = delaiHeuresAvantArrivee(arrivee, DateTime(2031, 7, 10, 10));
      expect(d, -10.0);
      expect(estSousLeSeuil(arrivee, DateTime(2031, 7, 10, 10)), isTrue);
    });

    test('l’arrivée est lue par son JOUR, pas par son fuseau', () {
      // Une arrivée stockée en UTC ne doit pas glisser d'un jour.
      final utc = DateTime.utc(2031, 7, 10);
      expect(delaiHeuresAvantArrivee(utc, DateTime(2031, 7, 9, 10)), 14.0);
    });

    test('number_format(.., 1) : une décimale, virgule de milliers', () {
      expect(formaterHeures(14), '14.0');
      expect(formaterHeures(590), '590.0');
      expect(formaterHeures(1862.5), '1,862.5');
      expect(formaterHeures(-10), '-10.0');
      expect(formaterHeures(0), '0.0');
      expect(formaterHeures(1234567.89), '1,234,567.9');
    });
  });

  group('Le taux par défaut', () {
    test('le paramètre, sinon 50.00 — le repli du serveur', () {
      expect(tauxParDefaut(const {}), '50.00');
      expect(
        tauxParDefaut(const {'hebergement_taux_annulation_moins_24h': '30'}),
        '30',
      );
      expect(tauxParDefaut(const {'autre': '9'}), '50.00');
    });
  });

  group('Le montant total inconnu — refusé plutôt qu’inventé', () {
    test('sans tarif figé ET sans ligne, il est inconnu', () {
      expect(
        montantTotalCentimes(
          tarifNuit: 0,
          aDesLignes: false,
          totalDuRecapitulatifFrancs: 0,
        ),
        isNull,
      );
    });

    test('avec des lignes, ou un tarif figé, il est connu', () {
      expect(
        montantTotalCentimes(
          tarifNuit: 0,
          aDesLignes: true,
          totalDuRecapitulatifFrancs: 56000,
        ),
        5600000,
      );
      expect(
        montantTotalCentimes(
          tarifNuit: 28000,
          aDesLignes: false,
          totalDuRecapitulatifFrancs: 56000,
        ),
        5600000,
      );
    });
  });

  group('Le remboursement suggéré', () {
    test('ce qu’il reste de l’acompte après la commission théorique, en %', () {
      // Total 40 000, taux 10 -> commission 4 000 ; acompte 10 000 -> reste
      // 6 000 = 60 % de l'acompte.
      expect(
        pourcentageRembourseSuggere(
          acompteCentimes: 1000000,
          totalCentimes: 4000000,
          taux: '10',
        ),
        '60.00',
      );
    });

    test('jamais négatif : une commission plus grosse que l’acompte suggère '
        '« 0 », littéral', () {
      expect(
        pourcentageRembourseSuggere(
          acompteCentimes: 500000,
          totalCentimes: 4000000,
          taux: '50',
        ),
        '0',
      );
    });

    test('sans acompte, ou sans total connu : « 0 »', () {
      expect(
        pourcentageRembourseSuggere(
          acompteCentimes: 0,
          totalCentimes: 4000000,
          taux: '50',
        ),
        '0',
      );
      expect(
        pourcentageRembourseSuggere(
          acompteCentimes: 500000,
          totalCentimes: null,
          taux: '50',
        ),
        '0',
      );
    });

    test('un acompte égal à la commission suggère « 0.00 » (pas « 0 »)', () {
      // Le reste est nul mais pas NÉGATIF : le serveur rend le quotient, soit
      // « 0.00 », et non le littéral « 0 » du cas négatif.
      expect(
        pourcentageRembourseSuggere(
          acompteCentimes: 2000000,
          totalCentimes: 4000000,
          taux: '50',
        ),
        '0.00',
      );
    });
  });

  group('Le calcul — dans l’ORDRE du serveur', () {
    ResultatAnnulation annuler({
      bool dejaAnnulee = false,
      int? total = 4000000,
      int acompte = 500000,
      String taux = '50',
      String mode = 'pourcentage',
      String valeur = '60',
    }) => calculerAnnulation(
      dejaAnnulee: dejaAnnulee,
      totalCentimes: total,
      acompteCentimes: acompte,
      tauxSaisi: taux,
      modeSaisi: mode,
      valeurSaisie: valeur,
    );

    RefusAnnulation refus(void Function() geste) {
      try {
        geste();
      } on RefusAnnulation catch (e) {
        return e;
      }
      fail('Aucun refus levé.');
    }

    test('la commission porte sur le MONTANT GLOBAL, jamais sur l’acompte', () {
      final r = annuler();
      // 50 % de 40 000 = 20 000, quand l'acompte n'est que de 5 000.
      expect(r.commissionCentimes, 2000000);
      expect(r.totalCentimes, 4000000);
      expect(r.tauxCentiemes, 5000);
    });

    test('un remboursement en POURCENTAGE de l’acompte', () {
      // 60 % de 5 000 = 3 000.
      expect(annuler().rembourseCentimes, 300000);
    });

    test('un remboursement en FCFA direct', () {
      final r = annuler(mode: 'montant', valeur: '1234');
      expect(r.rembourseCentimes, 123400);
      expect(r.modeSaisie, 'montant');
    });

    test('le taux est TRONQUÉ à deux décimales, jamais arrondi', () {
      expect(annuler(taux: '33.339').tauxCentiemes, 3333);
      // Et la commission suit ce taux tronqué : 40 000 x 33,33 % = 13 332.
      expect(annuler(taux: '33.339').commissionCentimes, 1333200);
    });

    test('la commission est TRONQUÉE au centime', () {
      // 333,33 F x 33,33 % = 111,098889 F -> 111,09 F (et non 111,10 F).
      final r = annuler(
        total: 33333,
        taux: '33.33',
        mode: 'montant',
        valeur: '0',
      );
      expect(r.commissionCentimes, 11109);
    });

    test('le pourcentage est lu à QUATRE décimales, le montant à deux', () {
      // 33,3333 % de 5 000 F = 1 666,665 -> tronqué à 1 666,66 F.
      expect(annuler(valeur: '33.3333').rembourseCentimes, 166666);
      // 12,3456 FCFA -> 12,34 F.
      expect(
        annuler(mode: 'montant', valeur: '12.3456').rembourseCentimes,
        1234,
      );
    });

    test('rembourser exactement l’acompte passe, un centime de plus non', () {
      expect(
        annuler(mode: 'montant', valeur: '5000').rembourseCentimes,
        500000,
      );
      final r = refus(() => annuler(mode: 'montant', valeur: '5000.01'));
      expect(r.message, MessagesAnnulation.remboursementSuperieurAcompte);
      expect(r.champ, 'aRembourseValeur');
      // 100,01 % de l'acompte : 5 000,50 F.
      expect(
        refus(() => annuler(valeur: '100.01')).message,
        MessagesAnnulation.remboursementSuperieurAcompte,
      );
      expect(annuler(valeur: '100').rembourseCentimes, 500000);
    });

    test('le taux hors bornes est refusé sous le champ du remboursement', () {
      for (final taux in ['100.01', '-0.01', '101', '-1']) {
        final r = refus(() => annuler(taux: taux));
        expect(r.message, MessagesAnnulation.tauxInvalide, reason: taux);
        expect(r.champ, 'aRembourseValeur', reason: taux);
      }
      // Les bornes elles-mêmes passent.
      expect(annuler(taux: '0').commissionCentimes, 0);
      expect(annuler(taux: '100').commissionCentimes, 4000000);
      // Et un taux de -0.001, tronqué à -0.00, est NUL : il passe (bccomp à 2).
      expect(annuler(taux: '-0.001').tauxCentiemes, 0);
    });

    test('un remboursement négatif, un mode inconnu : refusés', () {
      expect(
        refus(() => annuler(valeur: '-1')).message,
        MessagesAnnulation.remboursementNegatif,
      );
      final m = refus(() => annuler(mode: 'cheque'));
      expect(m.message, MessagesAnnulation.modeInconnu('cheque'));
      expect(m.champ, 'aRembourseValeur');
    });

    test('déjà annulée, puis montant inconnu : la BANNIÈRE, et AVANT tout', () {
      final a = refus(() => annuler(dejaAnnulee: true, taux: '999'));
      expect(a.message, MessagesAnnulation.dejaAnnulee);
      expect(a.champ, 'annulation');

      final b = refus(() => annuler(total: null, taux: '999'));
      expect(b.message, MessagesAnnulation.montantTotalInconnu);
      expect(b.champ, 'annulation');
    });

    test('l’ordre : le taux est jugé AVANT le remboursement', () {
      expect(
        refus(() => annuler(taux: '150', valeur: '-1')).message,
        MessagesAnnulation.tauxInvalide,
      );
    });

    test('une saisie illisible est refusée (le serveur plante en 500)', () {
      expect(
        refus(() => annuler(taux: '1e1')).message,
        MessagesAnnulation.malForme,
      );
      expect(
        refus(() => annuler(valeur: '12,5')).message,
        MessagesAnnulation.malForme,
      );
    });
  });

  group('La validation Livewire — champ par champ, aux mots du serveur', () {
    Map<String, List<String>> valider(String? t, String? m, String? v) =>
        validerSaisieAnnulation(taux: t, mode: m, valeur: v);

    test('une saisie valide ne dit rien', () {
      expect(valider('50', 'pourcentage', '60'), isEmpty);
      expect(valider('0', 'montant', '0'), isEmpty);
      expect(valider('100', 'montant', '8000.5'), isEmpty);
    });

    test('vide : « obligatoire », et rien d’autre sur ce champ', () {
      final e = valider('', null, '   ');
      expect(e['aTaux'], [MessagesAnnulation.obligatoire('a taux')]);
      expect(e['aModeRemboursement'], [
        MessagesAnnulation.obligatoire('a mode remboursement'),
      ]);
      expect(e['aRembourseValeur'], [
        MessagesAnnulation.obligatoire('a rembourse valeur'),
      ]);
    });

    test('non numérique : « doit être un nombre », jamais min/max', () {
      final e = valider('abc', 'xx', 'z');
      expect(e['aTaux'], [MessagesAnnulation.nombre('a taux')]);
      expect(e['aModeRemboursement'], [
        MessagesAnnulation.invalide('a mode remboursement'),
      ]);
      expect(e['aRembourseValeur'], [
        MessagesAnnulation.nombre('a rembourse valeur'),
      ]);
    });

    test('les bornes du taux : 0 et 100 passent, au-delà non', () {
      expect(valider('100', 'montant', '1'), isEmpty);
      expect(valider('0', 'montant', '1'), isEmpty);
      expect(valider('100.01', 'montant', '1')['aTaux'], [
        MessagesAnnulation.maximum('a taux', '100'),
      ]);
      expect(valider('-0.01', 'montant', '1')['aTaux'], [
        MessagesAnnulation.minimum('a taux', '0'),
      ]);
    });

    test('un remboursement négatif : « au minimum de 0 »', () {
      expect(valider('50', 'montant', '-5')['aRembourseValeur'], [
        MessagesAnnulation.minimum('a rembourse valeur', '0'),
      ]);
    });
  });

  group('Ce que l’annulation a fixé', () {
    AnnulationEnregistree avec(int taux) => AnnulationEnregistree(
      tauxCentiemes: taux,
      totalCentimes: 0,
      commissionCentimes: 0,
      rembourseCentimes: 0,
      modeSaisie: 'montant',
      date: DateTime(2031, 6, 15),
    );

    test(
      'le taux est imprimé comme la vue : « 50 % », « 12.5 % », « 33.33 % »',
      () {
        expect(avec(5000).tauxAffiche, '50 %');
        expect(avec(1250).tauxAffiche, '12.5 %');
        expect(avec(3333).tauxAffiche, '33.33 %');
        expect(avec(10000).tauxAffiche, '100 %');
        expect(avec(0).tauxAffiche, '0 %');
        expect(avec(5).tauxAffiche, '0.05 %');
      },
    );

    test('un remboursement nul n’est pas un remboursement', () {
      expect(avec(5000).aRembourse, isFalse);
      final r = AnnulationEnregistree(
        tauxCentiemes: 0,
        totalCentimes: 0,
        commissionCentimes: 0,
        rembourseCentimes: 1,
        modeSaisie: 'montant',
        date: DateTime(2031, 6, 15),
      );
      expect(r.aRembourse, isTrue);
    });
  });

  group('DecimalBc — la troncature de bcmath', () {
    DecimalBc d(String s) => DecimalBc.lire(s)!;

    test('lire refuse tout ce qui n’est pas « [-]chiffres[.chiffres] »', () {
      for (final mauvais in ['', 'abc', '1e3', '1,5', ' 1', '1 ', '.5', '5.']) {
        expect(DecimalBc.lire(mauvais), isNull, reason: '« $mauvais »');
      }
      expect(DecimalBc.lire('-0.5')!.estNegatif, isTrue);
      expect(DecimalBc.lire('0')!.estNegatif, isFalse);
    });

    test('versEchelle TRONQUE vers zéro, ne réarrondit pas', () {
      expect(d('12.999').versEchelle(2).toString(), '12.99');
      expect(d('-12.999').versEchelle(2).toString(), '-12.99');
      expect(d('12.5').versEchelle(4).toString(), '12.5000');
    });

    test('fois : le produit exact, tronqué à l’échelle demandée', () {
      expect(d('3333').fois(d('33.33'), 4).toString(), '111088.8900');
      expect(d('1.5').fois(d('1.5'), 1).toString(), '2.2');
    });

    test('divise : le quotient, tronqué', () {
      expect(d('10').divise(d('3'), 2).toString(), '3.33');
      expect(d('-10').divise(d('3'), 2).toString(), '-3.33');
      expect(d('1').divise(d('100'), 2).toString(), '0.01');
    });

    test('moins et compare : la comparaison tronque AVANT de juger', () {
      expect(d('5').moins(d('7.255'), 2).toString(), '-2.25');
      // bccomp('-0.001', '0', 2) vaut 0.
      expect(d('-0.001').compare(d('0'), 2), 0);
      expect(d('0.01').compare(d('0'), 2), 1);
    });
  });
}
