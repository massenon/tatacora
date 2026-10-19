import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/place_hebergement.dart';

/// ⚠ **Q3 — l'hébergement est-il une ligne de panier ?**
///
/// La question n'est pas tranchée. Ce fichier éprouve les **deux** branches du
/// point nommé qui la porte, pour deux raisons :
///
///  1. la branche retenue doit produire le bon montant ;
///  2. la branche **non** retenue doit refuser **explicitement**, et non
///     produire un chiffre plausible. Un refus jamais éprouvé est un refus
///     dont personne ne sait s'il existe encore — c'est précisément la famille
///     de défauts que la campagne PA-59 → PA-67 a démontée.
void main() {
  group('Position portée : l’hébergement reste sur la réservation', () {
    test('la constante du dépôt est bien celle du document', () {
      // Si quelqu'un bascule la constante sans implémenter l'autre branche,
      // ce test le dit avant que la composition ne lève en production.
      expect(placeHebergementRetenue, PlaceHebergement.horsPanier);
    });

    test('les deux montants restent NOMMÉS, jamais fondus en un total', () {
      final composition = CompositionFactureSejour.composer(
        montantHebergement: 56000,
        totalPanier: 7700,
      );

      // « votre chambre, vos consommations » est une phrase qu'on prononce au
      // comptoir ; « 63 700 F » n'en est pas une.
      expect(composition.hebergement, 56000);
      expect(composition.consommations, 7700);
      expect(composition.total, 63700);
    });

    test('un panier vide n’efface pas la nuitée', () {
      final composition = CompositionFactureSejour.composer(
        montantHebergement: 56000,
        totalPanier: 0,
      );
      expect(composition.total, 56000);
    });
  });

  group('Branche non tranchée : le refus EST le livrable', () {
    test('composer sur l’hypothèse « ligne de panier » lève', () {
      // Écrire `consommations: totalPanier` en supposant que la nuitée s'y
      // trouve déjà donnerait un total juste SI quelqu'un avait pensé à l'y
      // mettre, et un total amputé d'une nuit sinon — sans qu'aucun test ne
      // puisse distinguer les deux cas.
      expect(
        () => CompositionFactureSejour.composer(
          montantHebergement: 56000,
          totalPanier: 7700,
          place: PlaceHebergement.ligneDePanier,
        ),
        throwsA(isA<UnimplementedError>()),
      );
    });

    test('le message nomme Q3 et son document', () {
      try {
        CompositionFactureSejour.composer(
          montantHebergement: 0,
          totalPanier: 0,
          place: PlaceHebergement.ligneDePanier,
        );
        fail('la branche non tranchée aurait dû lever');
      } on UnimplementedError catch (e) {
        expect(e.message, contains('Q3'));
        expect(e.message, contains('PROPOSITION_MODELE_PANIER_POS'));
      }
    });
  });

  group(
    'La position se lit aussi dans la structure, pas seulement en commentaire',
    () {
      test('M1 Hébergement n’est PAS un catalogue vendable', () {
        // Une ligne d'hébergement n'est pas seulement absente : elle est
        // inexprimable. C'est ce qui rend la position portée vérifiable sans
        // relire le code de chaque écran.
        expect(ModuleVendable.values.map((m) => m.code), isNot(contains('M1')));
      });

      test(
        'le registre des catalogues vendables est fermé à quatre modules',
        () {
          // Un registre qui s'élargirait sans arbitrage ferait entrer M1 par la
          // porte de service.
          expect(ModuleVendable.values, hasLength(4));
          expect(
            () => ModuleVendable.depuisCode('M1'),
            throwsA(isA<ArgumentError>()),
          );
        },
      );
    },
  );
}
