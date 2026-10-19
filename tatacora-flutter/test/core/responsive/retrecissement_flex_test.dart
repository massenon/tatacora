import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/responsive/mesure_texte.dart';
import 'package:tatacora_flutter/core/responsive/retrecissement_flex.dart';

/// Le partage de largeur d'une rangée `display: flex` qui ne tient pas.
///
/// Les cas sont des CALCULS À LA MAIN, pas des constats : chacun dit la valeur
/// que le navigateur donne (CSS Flexbox §9.7). Les valeurs d'En-tête
/// d'Hébergement (`hebergement.blade.php` l.77-95) en sont le cas réel.
void main() {
  group('partagerRetrecissement', () {
    test('tout tient : chaque élément garde sa base, rien ne s’étire', () {
      final tailles = partagerRetrecissement(
        elements: const [
          ElementFlex(base: 100, minimum: 40),
          ElementFlex(base: 200, minimum: 60),
        ],
        disponible: 1000,
      );
      expect(tailles, [100, 200]);
    });

    test('l’excédent est retranché AU PRORATA des bases', () {
      // 300 + 100 = 400 pour 200 disponibles : 200 d'excédent. 3/4 pour le
      // premier (150), 1/4 pour le second (50).
      final tailles = partagerRetrecissement(
        elements: const [
          ElementFlex(base: 300, minimum: 0),
          ElementFlex(base: 100, minimum: 0),
        ],
        disponible: 200,
      );
      expect(tailles[0], closeTo(150, 0.001));
      expect(tailles[1], closeTo(50, 0.001));
    });

    test(
      'un élément qui toucherait son plancher y est FIGÉ, le reste absorbe',
      () {
        // Sans plancher : 150 et 50. Le second ne descend pas sous 90 : il est
        // figé à 90 et le premier prend le reste (200 - 90 = 110).
        final tailles = partagerRetrecissement(
          elements: const [
            ElementFlex(base: 300, minimum: 0),
            ElementFlex(base: 100, minimum: 90),
          ],
          disponible: 200,
        );
        expect(tailles[0], closeTo(110, 0.001));
        expect(tailles[1], 90);
      },
    );

    test('les écarts (gap) sont retranchés de l’espace disponible', () {
      // 1000 - 100 d'écarts = 900 pour 1000 de bases : facteur 0,9.
      final tailles = partagerRetrecissement(
        elements: const [
          ElementFlex(base: 600, minimum: 0),
          ElementFlex(base: 400, minimum: 0),
        ],
        disponible: 1000,
        ecarts: 100,
      );
      expect(tailles[0], closeTo(540, 0.001));
      expect(tailles[1], closeTo(360, 0.001));
    });

    test('quand les planchers dépassent l’espace, ils l’emportent', () {
      // Le navigateur déborde plutôt que de passer sous min-content.
      final tailles = partagerRetrecissement(
        elements: const [
          ElementFlex(base: 300, minimum: 200),
          ElementFlex(base: 300, minimum: 200),
        ],
        disponible: 100,
      );
      expect(tailles, [200, 200]);
    });

    test(
      'le cas d’Hébergement à 1 383 px : les onglets descendent à leur plancher',
      () {
        // Mesuré dans le navigateur : bloc titre/sous-titre (base ≈ 800), rangée
        // d'onglets (base ≈ 640, plancher 479) ; 1 055 px, un `gap-4`. Les
        // onglets sont figés à leur plancher, le bloc titre prend le reste.
        final tailles = partagerRetrecissement(
          elements: const [
            ElementFlex(base: 800, minimum: 200),
            ElementFlex(base: 640, minimum: 479),
          ],
          disponible: 1055,
          ecarts: 16,
        );
        expect(tailles[1], 479);
        expect(tailles[0], closeTo(1055 - 16 - 479, 0.001));
      },
    );
  });

  group('mesure du texte', () {
    const style = TextStyle(fontSize: 14);

    test('« min-content » est le plus long MOT, « max-content » la phrase', () {
      final mot = largeurMaxContent('Hébergement', style);
      final phrase = largeurMaxContent('Plan d\'Hébergement', style);
      expect(
        largeurMinContent('Plan d\'Hébergement', style),
        largeurMaxContent('d\'Hébergement', style),
      );
      expect(largeurMinContent('Plan d\'Hébergement', style), lessThan(phrase));
      expect(mot, greaterThan(0));
    });

    test('un texte sans espace a le même min et max', () {
      expect(
        largeurMinContent('Disponibilités', style),
        largeurMaxContent('Disponibilités', style),
      );
    });

    test('un texte vide mesure zéro', () {
      expect(largeurMinContent('', style), 0);
    });
  });
}
