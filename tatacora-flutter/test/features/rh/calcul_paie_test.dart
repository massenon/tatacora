import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/periode_paie.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/taux_paie.dart';
import 'package:tatacora_flutter/features/rh/domain/refus_rh.dart';
import 'package:tatacora_flutter/features/rh/domain/services/calcul_paie_service.dart';

/// Le calcul de paie **et ses deux refus** — M13, PA-53.
///
/// ## Ce qui est éprouvé ici, et pourquoi ce sont les cas qui comptent
///
/// Les deux refus sont le **livrable** du module, pas des lacunes. Un test qui
/// se contenterait de vérifier le net laisserait passer exactement le défaut
/// que ce module existe pour empêcher : quelqu'un qui, pour « faire tourner
/// l'écran », inscrirait 2 % de risques professionnels dans le référentiel, ou
/// prolongerait le barème ITS au-delà de 500 000 F.
///
/// Les cas de refus sont donc écrits **contre le référentiel réellement
/// installé** (`ReferentielPaie.confirmes`), et non contre une carte vide
/// fabriquée pour l'occasion : une carte vide refuserait tout, y compris ce
/// qui doit être calculé, et le test serait vert sans rien distinguer.
///
/// Aucun de ces cas ne touche la base : `CalculPaieService` est pur et
/// synchrone, ce qui permet d'être certain que le refus ne dépend d'aucun état.
void main() {
  /// Le référentiel **tel que le poste l'installe** — quatre taux confirmés.
  final referentielInstalle = {
    for (final taux in ReferentielPaie.confirmes) taux.cle: taux.valeur,
  };

  final moteur = CalculPaieService(referentielInstalle);

  /* ================================================================== */
  group('Le net salarial — cas chiffré sur 150 000 F', () {
    // 150 000 F est le brut par défaut du simulateur du maître.
    //
    //   CNSS 3,6 %          150 000 x 3,6 %          =   5 400
    //   Revenu imposable    150 000 - 5 400          = 144 600
    //   ITS, tranche 10 %   (144 600 - 60 000) x 10 %=   8 460
    //   Net                 150 000 - 5 400 - 8 460  = 136 140
    late final retenues = moteur.retenuesSalariales(150000);

    test('la CNSS salariale vaut 3,6 % du brut', () {
      expect(retenues.cnssSalarie, 5400);
    });

    test("l'ITS porte sur le revenu IMPOSABLE, pas sur le brut", () {
      expect(retenues.revenuImposable, 144600);
      expect(retenues.its, 8460);

      // Le contrôle qui prouve que le cas mord : appliquer le barème au brut
      // donnerait 9 000 F. Sans cette ligne, on ne saurait pas si l'assertion
      // ci-dessus distingue quoi que ce soit — et surtaxer chaque bulletin de
      // 540 F est parfaitement plausible à la lecture.
      expect(retenues.its, isNot(9000));
    });

    test('le net à payer est calculé, et il vaut 136 140 F', () {
      expect(retenues.netAPayer, 136140);

      // Le net n'est jamais le brut moins la seule CNSS : si l'ITS cessait
      // d'être déduit, ce test tomberait.
      expect(retenues.netAPayer, isNot(retenues.brut - retenues.cnssSalarie));
    });

    test(
      'le total des retenues et le net reconstituent exactement le brut',
      () {
        expect(retenues.netAPayer + retenues.totalRetenues, retenues.brut);
      },
    );
  });

  /* ================================================================== */
  group('Le REFUS du coût total employeur est le livrable (PA-53)', () {
    test(
      'le référentiel installé ne porte AUCUN taux de risques professionnels',
      () {
        // C'est la garde de fond : si quelqu'un ajoutait ce taux au
        // référentiel « pour faire tourner l'écran », tous les refus qui
        // suivent deviendraient verts en silence, et le module rendrait un
        // coût employeur supposé.
        expect(
          ReferentielPaie.confirmes.map((t) => t.cle),
          isNot(contains(ClesTaux.cnssRisquesProfessionnels)),
        );
        expect(
          moteur.tauxEstParametre(ClesTaux.cnssRisquesProfessionnels),
          isFalse,
        );
      },
    );

    test('le référentiel est COMPLET par ailleurs : le refus ne vient pas '
        "d'une installation ratée", () {
      final etat = moteur.etatReferentiel();

      expect(etat.complet, isTrue);
      expect(etat.salarial, isTrue);
      expect(etat.patronal, isTrue);
      // …et pourtant le taux de risques professionnels manque. C'est l'état
      // NORMAL du module, pas une anomalie d'installation.
      expect(etat.risquesProfessionnels, isFalse);
    });

    test('demander un total de charge patronale est REFUSÉ', () {
      expect(
        () => moteur.chargesPatronalesAvecRisquesProfessionnels(150000),
        throwsA(isA<TauxNonParametre>()),
      );
    });

    test('le refus NOMME la clé qui manque, il ne dit pas « erreur »', () {
      try {
        moteur.chargesPatronalesAvecRisquesProfessionnels(150000);
        fail('Le total de charge patronale aurait dû être refusé.');
      } on TauxNonParametre catch (refus) {
        expect(refus.cle, ClesTaux.cnssRisquesProfessionnels);
        expect(refus.message, contains('taux_cnss_risques_professionnels'));
        expect(refus.message, contains("n'est pas paramétré"));
      }
    });

    test('la part CONFIRMÉE, elle, se calcule : 19,4 % du brut', () {
      final charges = moteur.chargesPatronalesConfirmees(150000);

      expect(charges.pension, 9600); // 6,4 %
      expect(charges.prestationsFamiliales, 13500); // 9 %
      expect(charges.vps, 6000); // 4 %
      expect(charges.total, 29100); // 19,4 %
    });

    test("l'incertitude est PUBLIÉE en fourchette, jamais moyennée", () {
      final fourchette = CalculPaieService.fourchetteRisquesProfessionnels(
        150000,
      );

      expect(fourchette.minimum, 1500); // 1 %
      expect(fourchette.maximum, 6000); // 4 %
      expect(fourchette.ecart, 4500);
      // Ce que le refus protège, chiffré : sur douze mois et un seul salarié.
      expect(fourchette.ecartAnnuel, 54000);

      // Le milieu de fourchette — 2,5 %, soit 3 750 F — est exactement
      // l'hypothèse refusée. Aucun accesseur ne doit le rendre.
      expect(fourchette.minimum, isNot(3750));
      expect(fourchette.maximum, isNot(3750));
    });
  });

  /* ================================================================== */
  group("Le REFUS de l'ITS au-delà de 500 000 F (PA-53)", () {
    test('le barème confirmé se calcule jusqu\'au plafond inclus', () {
      // 0 + 9 000 (10 %) + 15 000 (15 %) + 47 500 (19 %) = 71 500.
      expect(moteur.impotSurTraitements(500000), 71500);
    });

    test('un franc au-dessus du plafond est REFUSÉ', () {
      expect(
        () => moteur.impotSurTraitements(500001),
        throwsA(isA<BaremeItsNonTranche>()),
      );
    });

    test('le refus dit POURQUOI : deux sources divergent', () {
      try {
        moteur.impotSurTraitements(600000);
        fail('Le calcul au-delà du plafond aurait dû être refusé.');
      } on BaremeItsNonTranche catch (refus) {
        expect(refus.plafond, 500000);
        expect(refus.revenuImposable, 600000);
        expect(refus.message, contains('deux sources divergent'));
        expect(refus.message, contains('refusé'));
        // Le refus renvoie vers la seule issue réelle.
        expect(refus.message, contains('DGI'));
      }
    });

    test('le plafond porte sur le revenu IMPOSABLE, pas sur le brut — '
        'un brut de 518 000 F passe encore', () {
      // 518 000 - 3,6 % = 499 352, sous le plafond : le bulletin s'établit.
      // Si le plafond était comparé au BRUT, ce cas serait refusé à tort, et
      // un salarié parfaitement calculable resterait sans bulletin.
      final retenues = moteur.retenuesSalariales(518000);
      expect(retenues.revenuImposable, 499352);
      expect(retenues.netAPayer, greaterThan(0));
    });

    test('un brut de 520 000 F, lui, franchit le plafond et est refusé', () {
      // 520 000 - 3,6 % = 501 280 > 500 000.
      expect(
        () => moteur.retenuesSalariales(520000),
        throwsA(isA<BaremeItsNonTranche>()),
      );
    });

    test('aucun repli ne calcule à la place du barème non tranché', () {
      // Ni zéro, ni la dernière tranche prolongée : le calcul entier tombe.
      // Un ITS de 0 F sur un cadre serait une retenue à la source absente sur
      // un document conservé sans limitation de durée.
      expect(
        () => moteur.retenuesSalariales(1000000),
        throwsA(isA<BaremeItsNonTranche>()),
      );
    });
  });

  /* ================================================================== */
  group("Le VPS n'est JAMAIS une retenue salariale", () {
    test('il est absent du total des retenues, et donc du net', () {
      final retenues = moteur.retenuesSalariales(150000);
      final charges = moteur.chargesPatronalesConfirmees(150000);

      // Le total des retenues ne contient que CNSS + ITS.
      expect(retenues.totalRetenues, retenues.cnssSalarie + retenues.its);
      expect(retenues.totalRetenues, 13860);

      // S'il y entrait, le net serait minoré de 6 000 F — un bulletin faux,
      // donc une déclaration sociale erronée.
      expect(charges.vps, 6000);
      expect(retenues.netAPayer, isNot(136140 - charges.vps));
    });
  });

  /* ================================================================== */
  group('Le référentiel VIDE refuse tout, et le dit', () {
    const vide = CalculPaieService({});

    test('aucun calcul salarial ne se fait sans taux', () {
      expect(
        () => vide.retenuesSalariales(150000),
        throwsA(isA<TauxNonParametre>()),
      );
    });

    test("l'état nomme les quatre clés absentes", () {
      final etat = vide.etatReferentiel();

      expect(etat.complet, isFalse);
      expect(etat.clesAbsentes, ClesTaux.confirmees);
      expect(etat.refus, isA<ReferentielIncomplet>());
      // Le taux de risques professionnels n'est PAS listé : son absence est
      // voulue, ce n'est pas une installation incomplète.
      expect(
        etat.clesAbsentes,
        isNot(contains(ClesTaux.cnssRisquesProfessionnels)),
      );
    });
  });

  /* ================================================================== */
  group('Les taux sont lus en entiers, jamais en flottant', () {
    test('« 3,6 » s\'applique exactement', () {
      expect(Taux.depuisTexte('3.6')!.pourcentDe(150000), 5400);
      expect(Taux.depuisTexte('3,6')!.pourcentDe(150000), 5400);
      expect(Taux.depuisTexte('3.6')!.libelle, '3,6');
    });

    test('un taux illisible rend null — jamais zéro', () {
      // Zéro calculerait une CNSS de 0 F sans qu'aucun écran ne s'en aperçoive.
      expect(Taux.depuisTexte(null), isNull);
      expect(Taux.depuisTexte(''), isNull);
      expect(Taux.depuisTexte('trois virgule six'), isNull);
    });

    test("l'arrondi est commercial, pas bancaire", () {
      // 156,5 F : l'arrondi commercial donne 157, l'arrondi bancaire 156.
      // Le cas est choisi pour les distinguer — sur une demie « vers le pair »,
      // les deux règles rendraient le même franc et le test serait vide.
      expect(arrondiCommercial(1565, 10), 157);
      expect(arrondiCommercial(1575, 10), 158);
      expect(arrondiCommercial(-1565, 10), -157);
    });
  });

  /* ================================================================== */
  group('Le barème affiché vient du barème qui calcule', () {
    test('quatre tranches, et le cumul atteint 71 500 F au plafond', () {
      final lignes = moteur.baremeAffiche();

      expect(lignes.length, 4);
      expect(lignes.first.tranche.taux, 0);
      expect(lignes.first.maximum, 0);
      expect(lignes.last.tranche.plafond, CalculPaieService.plafondItsConfirme);
      expect(lignes.last.cumul, 71500);
    });

    test("le barème s'arrête à 500 000 F — aucune tranche au-delà", () {
      expect(
        CalculPaieService.baremeIts.map((t) => t.plafond),
        everyElement(lessThanOrEqualTo(500000)),
      );
    });
  });

  /* ================================================================== */
  group("La période et l'échéance du VPS", () {
    test('la période se lit et se nomme en français', () {
      expect(PeriodePaie.depuisTexte('2026-09')!.libelleLong, 'septembre 2026');
      expect(PeriodePaie.depuisTexte('2026-09')!.code, '2026-09');
    });

    test('une période mal formée rend null', () {
      expect(PeriodePaie.depuisTexte('2026-13'), isNull);
      expect(PeriodePaie.depuisTexte('septembre'), isNull);
      expect(PeriodePaie.depuisTexte(null), isNull);
    });

    test("l'échéance du VPS est le 10 du mois SUIVANT", () {
      expect(
        PeriodePaie.depuisTexte('2026-09')!.echeanceVps,
        DateTime(2026, 10, 10),
      );
      // Le passage d'année : une échéance recopiée à la main se tromperait ici.
      expect(
        PeriodePaie.depuisTexte('2026-12')!.echeanceVps,
        DateTime(2027, 1, 10),
      );
    });
  });
}
