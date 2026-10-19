import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/domain/apercu_lien.dart';

/// L'aperçu de « Lier au stock » — `EcranDeCarte::apercuDuLien()` et
/// `unitesVendables()`, qui calculent en `bcmath`.
///
/// Les cas qui comptent sont ceux où un `double` se tromperait : 0,29 × 100
/// vaut 28,999… en flottant, et la troncature le rend 28.
void main() {
  group('lireDecimal / ecrireDecimal', () {
    test('lit « 24.0000 » et le rend « 24 »', () {
      expect(ecrireDecimal(lireDecimal('24.0000')!), '24');
    });

    test('accepte la virgule tapée au clavier', () {
      expect(ecrireDecimal(lireDecimal('1,5')!), '1.5');
    });

    test('tronque au-delà du dix-millième, comme bcmath en échelle 4', () {
      expect(ecrireDecimal(lireDecimal('0.123456')!), '0.1234');
    });

    test('refuse ce qui n’est pas un nombre', () {
      for (final brut in ['', ' ', 'douze', '1.2.3', '.', '-']) {
        expect(lireDecimal(brut), isNull, reason: '« $brut »');
      }
    });
  });

  group('decrementParVente — bcdiv(1, conversion, 4)', () {
    test('un casier de 24 : chaque vente retire 0.0416 casier', () {
      // 1 / 24 = 0,041666… — TRONQUÉ, pas arrondi, comme `bcdiv`.
      expect(ecrireDecimal(decrementParVente('24')!), '0.0416');
    });

    test('une bouteille à l’unité : 1', () {
      expect(ecrireDecimal(decrementParVente('1')!), '1');
    });

    test('vide, nul ou négatif : AUCUN aperçu, jamais « une pour une »', () {
      for (final brut in ['', '0', '0.0000', '-3', 'abc']) {
        expect(decrementParVente(brut), isNull, reason: '« $brut »');
      }
    });
  });

  group('unitesVendables — bcmul(solde, conversion, 0)', () {
    test('1,96 casier de 24 : 47 bouteilles, pas 47,04', () {
      expect(
        unitesVendables(solde: '1.96', conditionnement: '24'),
        BigInt.from(47),
      );
    });

    test('0,29 × 100 vaut 29 — là où un double donnerait 28', () {
      // Le piège qui justifie de ne pas calculer en flottant.
      expect((0.29 * 100).floor(), 28, reason: 'le piège existe bien');
      expect(
        unitesVendables(solde: '0.29', conditionnement: '100'),
        BigInt.from(29),
      );
    });

    test('un solde négatif tronque VERS ZÉRO, comme bcmath', () {
      expect(
        unitesVendables(solde: '-1.5', conditionnement: '3'),
        BigInt.from(-4),
      );
      expect(
        unitesVendables(solde: '-0.5', conditionnement: '3'),
        BigInt.from(-1),
      );
    });

    test('sans conditionnement exploitable : rien', () {
      expect(unitesVendables(solde: '10', conditionnement: '0'), isNull);
      expect(unitesVendables(solde: '10', conditionnement: ''), isNull);
      expect(unitesVendables(solde: 'x', conditionnement: '24'), isNull);
    });
  });
}
