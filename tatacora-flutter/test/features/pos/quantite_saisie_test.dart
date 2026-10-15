import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/usecases/quantite_saisie.dart';

/// Le piège déjà rencontré : « absente » n'est pas « zéro ».
///
/// `Number(quantite) || 1` transformait une quantité **saisie à zéro** en
/// **une unité facturée** (PA-78). Dart ne résout pas le problème tout seul :
/// `int.tryParse(texte) ?? 1` le reproduirait à l'identique dans une autre
/// syntaxe.
///
/// Ce fichier existe pour que la distinction reste éprouvée, et pas seulement
/// écrite dans un commentaire.
void main() {
  group('Champ vide — quantité NON précisée', () {
    test('null vaut 1', () {
      final lue = QuantiteSaisie.depuisTexte(null);
      expect(lue, isA<QuantiteAbsente>());
      expect((lue as QuantiteAbsente).valeur, 1);
    });

    test('chaîne vide vaut 1', () {
      expect(QuantiteSaisie.depuisTexte(''), isA<QuantiteAbsente>());
    });

    test('espaces seuls valent 1', () {
      // Un champ « effacé » laisse souvent un espace derrière lui.
      expect(QuantiteSaisie.depuisTexte('   '), isA<QuantiteAbsente>());
    });
  });

  group('Zéro — quantité PRÉCISÉE, et invalide', () {
    test('« 0 » est refusé, pas ramené à 1', () {
      final lue = QuantiteSaisie.depuisTexte('0');
      expect(
        lue,
        isA<QuantiteRefusee>(),
        reason: 'c’est exactement le défaut que `|| 1` produisait',
      );
    });

    test('le motif nomme la valeur lue, pas une généralité', () {
      final lue = QuantiteSaisie.depuisTexte('0') as QuantiteRefusee;
      // « la quantité doit être positive » laisserait croire à un champ vide
      // alors qu'un zéro a bien été frappé.
      expect(lue.motif, contains('0'));
      expect(lue.saisie, '0');
    });

    test('une quantité négative est refusée', () {
      expect(QuantiteSaisie.depuisTexte('-3'), isA<QuantiteRefusee>());
    });
  });

  group('Saisie illisible', () {
    test('du texte est refusé, jamais interprété', () {
      final lue = QuantiteSaisie.depuisTexte('deux');
      expect(lue, isA<QuantiteRefusee>());
      expect((lue as QuantiteRefusee).motif, contains('deux'));
    });

    test('un décimal est refusé : la quantité est un entier ici', () {
      // Divergence assumée avec le `DECIMAL(10,2)` du document proposé — une
      // consommation de bar ou de restaurant se compte, elle ne se pèse pas.
      // À rouvrir si un catalogue au poids entre au panier.
      expect(QuantiteSaisie.depuisTexte('1.5'), isA<QuantiteRefusee>());
    });
  });

  group('Saisie valide', () {
    test('« 3 » vaut 3', () {
      final lue = QuantiteSaisie.depuisTexte('3');
      expect(lue, isA<QuantiteValide>());
      expect((lue as QuantiteValide).valeur, 3);
    });

    test('les espaces de bordure sont tolérés', () {
      expect((QuantiteSaisie.depuisTexte(' 12 ') as QuantiteValide).valeur, 12);
    });
  });
}
