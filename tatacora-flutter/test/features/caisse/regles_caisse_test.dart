import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/montant_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/caisse/presentation/widgets/barre_session_caisse.dart';

/// Les règles PURES de la caisse : lecture d'une saisie, arrondi, troncature,
/// théorique, écart, message. Aucune base, aucun widget — et chaque valeur
/// attendue ici est celle que le VRAI composant PHP a rendue
/// (`caisse_contre_serveur_test.dart` les confronte une à une ; ce fichier
/// donne à chacune sa raison).
void main() {
  group('lire une saisie comme is_numeric de PHP 8', () {
    test('les formes numériques acceptées', () {
      for (final ok in [
        '0',
        '25000',
        '+5',
        '5.',
        '.5',
        '1e3',
        '1E-2',
        '.5e1',
        '00012',
        ' 1000',
        '5 ',
        '\t5\n',
        '-0',
      ]) {
        expect(DecimalSaisi.lire(ok), isNotNull, reason: '« $ok »');
      }
    });

    test(
      'les formes refusées : hexadécimal, milliers, virgule, exposant nu',
      () {
        for (final non in [
          '',
          ' ',
          'abc',
          '0x1A',
          '1 000',
          '1,5',
          '5e',
          '.',
          '--5',
          '1.2.3',
          '+',
        ]) {
          expect(DecimalSaisi.lire(non), isNull, reason: '« $non »');
        }
      },
    );
  });

  group('min:0 se juge sur la valeur EXACTE', () {
    test('-0 passe, -0.001 est refusé alors qu’il s’arrondirait à zéro', () {
      expect(DecimalSaisi.lire('-0')!.respecteMinZero, isTrue);
      expect(DecimalSaisi.lire('-0.0')!.respecteMinZero, isTrue);
      expect(DecimalSaisi.lire('-0.001')!.respecteMinZero, isFalse);
      expect(DecimalSaisi.lire('-.5')!.respecteMinZero, isFalse);
      expect(DecimalSaisi.lire('0.001')!.respecteMinZero, isTrue);
    });
  });

  group('les centimes que DECIMAL(15,2) stockerait', () {
    int? c(String s) => DecimalSaisi.lire(s)!.centimesArrondis;

    test('arrondi à la demi-unité ÉLOIGNÉE de zéro (MySQL)', () {
      expect(c('0.005'), 1);
      expect(c('0.0049'), 0);
      expect(c('1.005'), 101);
      expect(c('1000.555'), 100056);
      expect(c('12345678.995'), 1234567900);
    });

    test('l’exposant déplace la virgule', () {
      expect(c('1e3'), 100000);
      expect(c('.5e1'), 500);
      expect(c('1E-2'), 1);
      expect(c('1.5e3'), 150000);
      expect(c('1e12'), 100000000000000);
    });

    test('la plage de la colonne : 9 999 999 999 999,99, pas un centime de '
        'plus', () {
      expect(c('9999999999999.99'), 999999999999999);
      expect(c('9999999999999.994'), 999999999999999);
      // Arrondi AVANT le contrôle de plage : 9 999 999 999 999,995 sort.
      expect(c('9999999999999.995'), isNull);
      expect(c('1e13'), isNull);
      expect(c('99999999999999999'), isNull);
    });

    test('un exposant démesuré ne fabrique aucun entier géant', () {
      expect(c('1e999999'), isNull);
      expect(c('1e-999999'), 0);
      expect(c('0e999999'), 0);
    });
  });

  group('l’écart annoncé : la différence EXACTE, TRONQUÉE vers zéro', () {
    int e(String constate, int theorique) =>
        DecimalSaisi.lire(constate)!.ecartTronque(theorique);

    test('à deux décimales, c’est la soustraction ordinaire', () {
      expect(e('1000', 100000), 0);
      expect(e('1500.40', 150000), 40);
      expect(e('1499.60', 150000), -40);
    });

    test('à trois décimales, bcsub tronque et ne s’arrondit PAS', () {
      // 0.999 - 1.00 = -0.001 -> -0.00 : « aucun écart », alors que la valeur
      // STOCKÉE (arrondie) est 1.00 et que l'écart de stockage serait de 0.
      expect(e('0.999', 100), 0);
      expect(e('1500.999', 150000), 99);
      expect(e('13345.675', 1334567), 0);
      // Troncature vers ZÉRO, y compris pour un écart négatif.
      expect(e('1.001', 200), -99);
      expect(e('1.5', 200), -50);
    });

    test('ce n’est PAS (constaté arrondi) - théorique', () {
      // La divergence que le serveur porte, répliquée : constaté 1500.999
      // stocké 1501.00 (arrondi), écart annoncé 0.99 (tronqué) et non 1.00.
      final d = DecimalSaisi.lire('1500.999')!;
      expect(d.centimesArrondis, 150100);
      expect(d.ecartTronque(150000), 99);
      expect(d.centimesArrondis! - 150000, isNot(99));
    });
  });

  group('bcsub refuse ce que is_numeric accepte', () {
    test('exposant, espaces et signes doublés ne sont pas « bien formés »', () {
      for (final mal in ['1.5e3', ' 5', '5 ', '5e1', '1e3', '\t5']) {
        final d = DecimalSaisi.lire(mal)!;
        expect(d.estBienFormePourBc, isFalse, reason: '« $mal »');
      }
      for (final bien in ['5.', '+5', '.5', '-0', '0005', '-.5']) {
        final d = DecimalSaisi.lire(bien)!;
        expect(d.estBienFormePourBc, isTrue, reason: '« $bien »');
      }
    });
  });

  group('la validation de forme, dans l’ordre de Laravel', () {
    void refuse(String? brut, ChampCaisse champ, String message) {
      expect(
        () => validerMontantSaisi(brut, champ),
        throwsA(
          isA<RefusCaisse>()
              .having((e) => e.message, 'message', message)
              .having((e) => e.champ, 'champ', champ),
        ),
      );
    }

    test('required : vide, null et espaces seuls', () {
      for (final vide in [null, '', '  ', '\t\n']) {
        refuse(
          vide,
          ChampCaisse.fond,
          'Le champ fond caisse saisi est obligatoire.',
        );
      }
    });

    test('required retire les blancs de PHP, PAS l’espace insécable', () {
      // U+00A0 n'est pas un blanc pour `trim()` de PHP : « required » passe, et
      // c'est « numeric » qui refuse.
      refuse(
        ' ',
        ChampCaisse.fond,
        'Le champ fond caisse saisi doit être un nombre.',
      );
    });

    test('numeric puis min:0, avec le NOM du champ du serveur', () {
      refuse(
        'abc',
        ChampCaisse.fond,
        'Le champ fond caisse saisi doit être un nombre.',
      );
      refuse(
        '-5',
        ChampCaisse.fond,
        'Le champ fond caisse saisi doit etre au minimum de 0.',
      );
      refuse(
        'abc',
        ChampCaisse.constate,
        'Le champ montant constate saisi doit être un nombre.',
      );
      refuse(
        '-1',
        ChampCaisse.constate,
        'Le champ montant constate saisi doit etre au minimum de 0.',
      );
    });

    test('une saisie valide rend la valeur lue', () {
      expect(
        validerMontantSaisi(' 1000', ChampCaisse.fond).centimesArrondis,
        100000,
      );
    });
  });

  group('le théorique', () {
    test('fond + espèces, en entiers', () {
      expect(
        theoriqueCentimes(fondCentimes: 1000000, especesCentimes: 1234567),
        2234567,
      );
      expect(theoriqueCentimes(fondCentimes: 0, especesCentimes: 0), 0);
    });
  });

  group('le montant au format du serveur', () {
    test('MontantFcfa::format : demi-unité éloignée de zéro, -0 devient 0', () {
      expect(formaterCentimesEnFcfa(0), '0 FCFA');
      expect(formaterCentimesEnFcfa(49), '0 FCFA');
      expect(formaterCentimesEnFcfa(50), '1 FCFA');
      expect(formaterCentimesEnFcfa(-49), '0 FCFA');
      expect(formaterCentimesEnFcfa(-50), '-1 FCFA');
      expect(formaterCentimesEnFcfa(150000), '1 500 FCFA');
      expect(formaterCentimesEnFcfa(-50000), '-500 FCFA');
      expect(formaterCentimesEnFcfa(323306789), '3 233 068 FCFA');
      expect(formaterCentimesEnFcfa(100000000000000), '1 000 000 000 000 FCFA');
    });
  });

  group('les messages d’issue', () {
    test('ouverture', () {
      expect(messageOuverture(PointDeVenteCaisse.bar), 'Caisse bar ouverte.');
    });

    test(
      'clôture : « aucun écart » seulement si l’écart est EXACTEMENT nul',
      () {
        expect(
          messageCloture(PointDeVenteCaisse.bar, 0),
          'Caisse bar clôturée — aucun écart.',
        );
        // Un écart de 1 centime n'est pas « aucun écart » : le serveur compare
        // AVANT d'arrondir, puis écrit « écart de 0 FCFA ».
        expect(
          messageCloture(PointDeVenteCaisse.bar, 1),
          'Caisse bar clôturée — écart de 0 FCFA.',
        );
        expect(
          messageCloture(PointDeVenteCaisse.bar, -50000),
          'Caisse bar clôturée — écart de -500 FCFA.',
        );
        expect(
          messageCloture(PointDeVenteCaisse.bar, 323306789),
          'Caisse bar clôturée — écart de 3 233 068 FCFA.',
        );
      },
    );

    test(
      'l’écart est TOUJOURS annoncé : plus de message « écart non calculé »',
      () {
        // Avant le lot 5, le poste n'avait pas la source des espèces et la clôture
        // disait « écart non calculé ». Le serveur ne l'a jamais dit : il calcule
        // toujours le théorique.
        for (final ecart in [-100, 0, 1, 50000]) {
          expect(
            messageCloture(PointDeVenteCaisse.bar, ecart),
            isNot(contains('non calculé')),
          );
        }
      },
    );
  });

  group('la barre de session', () {
    test('la durée écoulée : minutes sous une heure, « 1h05 » au-delà', () {
      expect(dureeEcouleeDeLaBarre(Duration.zero), '0 min');
      expect(dureeEcouleeDeLaBarre(const Duration(minutes: 59)), '59 min');
      expect(dureeEcouleeDeLaBarre(const Duration(minutes: 60)), '1h00');
      expect(dureeEcouleeDeLaBarre(const Duration(minutes: 65)), '1h05');
      expect(
        dureeEcouleeDeLaBarre(const Duration(hours: 25, minutes: 7)),
        '25h07',
      );
      // Une horloge qui recule (changement d'heure, réglage) ne produit jamais
      // une durée négative.
      expect(dureeEcouleeDeLaBarre(const Duration(minutes: -5)), '0 min');
    });
  });

  group('les points de vente', () {
    test('le registre est celui de l’enum du serveur, avec les deux formes du '
        'nom', () {
      expect(PointDeVenteCaisse.values.map((p) => p.code), [
        'reception',
        'restaurant',
        'bar',
      ]);
      // Le POS écrit le code brut (« Caisse bar »), la barre supérieure le
      // libellé (« Bar ») — deux formes pour un point, signalé.
      expect(PointDeVenteCaisse.bar.libelle, 'Bar');
      expect(PointDeVenteCaisse.reception.libelle, 'Réception');
      expect(PointDeVenteCaisse.depuisCode('inconnu'), isNull);
    });
  });
}
