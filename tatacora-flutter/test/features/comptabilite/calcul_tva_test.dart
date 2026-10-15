import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/calcul_tva.dart';

/// La TVA du poste, en FONCTIONS PURES (réplique de `CalculTvaService`).
///
/// La confrontation à `bcmath` (177 montants x 26 couples taux/convention) vit
/// dans `ventes_contre_serveur_test.dart` : elle exige MySQL. Ces cas-ci portent
/// des valeurs CALCULÉES À LA MAIN, pour qu'un lecteur voie ce que « arrondi
/// demi vers le haut, une seule fois, en fin de calcul » veut dire.
void main() {
  ParametresTva ttc(String taux) =>
      ParametresTva(active: 'true', taux: taux, convention: 'ttc');
  ParametresTva ht(String taux) =>
      ParametresTva(active: 'true', taux: taux, convention: 'ht');

  group('La ventilation', () {
    test('TTC : la TVA est EXTRAITE — 3 000 F à 18 % = 457,63 F', () {
      final v = ttc('18').ventiler(300000);
      // 3000 x 18 / 118 = 457,627... -> 457,63.
      expect(v.tvaCentimes, 45763);
      expect(v.htCentimes, 254237);
      expect(v.ttcCentimes, 300000);
      expect(v.htCentimes + v.tvaCentimes, v.ttcCentimes);
    });

    test('HT : la TVA est AJOUTÉE — 1 000 F à 18 % = 180 F', () {
      final v = ht('18').ventiler(100000);
      expect(v.tvaCentimes, 18000);
      expect(v.htCentimes, 100000);
      expect(v.ttcCentimes, 118000);
    });

    test('inactive : le montant est ce qu’il est, sans taxe', () {
      final v = const ParametresTva().ventiler(123456);
      expect((v.htCentimes, v.tvaCentimes, v.ttcCentimes), (123456, 0, 123456));
    });

    test('l’arrondi est « demi vers le haut », UNE fois, en fin de calcul', () {
      // 25 F TTC à 18 % : 25 x 18 / 118 = 3,8135... -> 3,81 (et non 3,82 si l’on
      // arrondissait le quotient avant d’ajouter le demi-centime).
      expect(ttc('18').ventiler(2500).tvaCentimes, 381);
      // 0,50 F TTC à 20 % : 0,5 x 20 / 120 = 0,08333 -> 0,08.
      expect(ttc('20').ventiler(50).tvaCentimes, 8);
      // 1,65 F TTC à 10 % : 1,65 x 10 / 110 = 0,15 EXACT -> 0,15.
      expect(ttc('10').ventiler(165).tvaCentimes, 15);
      // Un demi-centime exact monte : 0,05 F HT à 10 % = 0,005 F -> 0,01 F.
      expect(ht('10').ventiler(5).tvaCentimes, 1);
    });

    test(
      'un taux nul ne taxe rien, un taux de 100 % prend la moitié du TTC',
      () {
        expect(ttc('0').ventiler(100000).tvaCentimes, 0);
        expect(ttc('100').ventiler(100000).tvaCentimes, 50000);
      },
    );

    test('un taux à décimales est lu sans flottant', () {
      // 18,5 % : 1000 x 18,5 / 118,5 = 156,12 F.
      expect(ttc('18.5').ventiler(100000).tvaCentimes, 15612);
      expect(ttc('18.50').ventiler(100000).tvaCentimes, 15612);
    });
  });

  group('Les deux commutateurs, jugés comme le serveur (PA-62)', () {
    test('`tva_active` se lit comme FILTER_VALIDATE_BOOLEAN', () {
      for (final vrai in ['1', 'true', 'TRUE', ' on ', 'Yes']) {
        expect(lireBooleenPhp(vrai), isTrue, reason: vrai);
      }
      for (final faux in ['0', 'false', 'off', 'no', '', 'oui', 'vrai', '2']) {
        expect(lireBooleenPhp(faux), isFalse, reason: faux);
      }
    });

    test('absent, `tva_active` vaut faux : jamais une TVA appliquée par '
        'défaut', () {
      expect(const ParametresTva().estActive, isFalse);
      expect(ParametresTva.depuis(const {}).estActive, isFalse);
    });

    test('active SANS taux, ou à taux blanc : refus aux mots du serveur', () {
      for (final taux in [null, '', '   ']) {
        expect(
          () => ParametresTva(active: 'true', taux: taux).ventiler(1000),
          throwsA(
            isA<RefusTva>().having(
              (e) => e.message,
              'message',
              PhrasesTva.tauxAbsent('taux_tva'),
            ),
          ),
          reason: 'taux « $taux »',
        );
      }
    });

    test('un taux illisible est refusé avec une phrase du poste (le serveur '
        'plante en HTTP 500)', () {
      expect(
        () => ParametresTva(
          active: 'true',
          taux: '1e2',
          convention: 'ttc',
        ).ventiler(1000),
        throwsA(
          isA<RefusTva>().having(
            (e) => e.message,
            'message',
            PhrasesTva.tauxIllisible('1e2'),
          ),
        ),
      );
    });

    test(
      'la convention : « ht » à défaut, normalisée, refusée si inconnue',
      () {
        expect(const ParametresTva().conventionOuRefus(), 'ht');
        expect(
          const ParametresTva(convention: '  TTC ').conventionOuRefus(),
          'ttc',
        );
        expect(
          () => const ParametresTva(convention: 'xyz').conventionOuRefus(),
          throwsA(
            isA<RefusTva>().having(
              (e) => e.message,
              'message',
              PhrasesTva.conventionInconnue('xyz', 'convention_prix'),
            ),
          ),
        );
      },
    );

    test('`depuis` lit les TROIS clés, et seulement elles', () {
      final p = ParametresTva.depuis(const {
        'tva_active': 'true',
        'taux_tva': '18',
        'convention_prix': 'ttc',
        'autre': 'x',
      });
      expect((p.active, p.taux, p.convention), ('true', '18', 'ttc'));
    });
  });
}
