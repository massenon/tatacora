import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/indicateurs_depenses.dart';

/// Le **montant décaissé** et les six indicateurs de M10.
///
/// Ces cas ne touchent ni la base ni un widget : ce sont les formules, et elles
/// doivent tenir seules. La règle qu'ils protègent est celle que le manuel
/// écrit au chapitre 9.1 et que la vue porte à son pied de tableau — *« Le
/// Montant décaissé (FCFA) ne se saisit pas : c'est le total des lignes »*.
void main() {
  LigneDepense ligne({
    required int montant,
    NatureDepense nature = NatureDepense.tomate,
    String compte = '601100',
    String libelle = 'Tomates fraîches',
  }) => LigneDepense(
    id: 'l-$montant-${nature.name}',
    libelle: libelle,
    compteCharge: compte,
    nature: nature.libelle,
    famille: nature.famille.libelle,
    montant: montant,
  );

  Depense depense({
    required List<LigneDepense> lignes,
    TresorerieDepense? tresorerie = TresorerieDepense.caisse,
    String id = 'dep-1',
  }) => Depense(
    id: id,
    dateTransaction: DateTime(2026, 9, 14),
    tresorerie: tresorerie,
    libelle: 'Marché du matin — Légumes & condiments',
    lignes: lignes,
    saisieLe: DateTime(2026, 9, 14, 8),
  );

  group('Le montant décaissé est la somme des lignes', () {
    test('trois achats font un seul décaissement', () {
      final d = depense(
        lignes: [
          ligne(montant: 15000, nature: NatureDepense.oignon),
          ligne(montant: 8500, nature: NatureDepense.tomate),
          ligne(montant: 3500, nature: NatureDepense.piment),
        ],
      );

      expect(d.montantTotal, 27000);
    });

    test('une dépense à une seule ligne vaut cette ligne', () {
      expect(depense(lignes: [ligne(montant: 25000)]).montantTotal, 25000);
    });

    test('retirer une ligne change le total — il n’est jamais figé', () {
      final trois = depense(
        lignes: [
          ligne(montant: 15000, nature: NatureDepense.oignon),
          ligne(montant: 8500, nature: NatureDepense.tomate),
          ligne(montant: 3500, nature: NatureDepense.piment),
        ],
      );
      final deux = depense(
        lignes: [
          ligne(montant: 15000, nature: NatureDepense.oignon),
          ligne(montant: 8500, nature: NatureDepense.tomate),
        ],
      );

      // Si le total était stocké plutôt que sommé, la seconde vaudrait encore
      // 27 000 — le défaut exact qu'une colonne dénormalisée produirait.
      expect(trois.montantTotal, isNot(deux.montantTotal));
      expect(deux.montantTotal, 23500);
    });
  });

  group('Les indicateurs somment chaque LIGNE dans SA famille', () {
    test('une dépense mêlée compte dans les deux familles', () {
      // Un marché du matin qui mêle des tomates et le transport : la pièce
      // entière ne doit pas tomber dans la famille de sa première ligne.
      final melangee = depense(
        lignes: [
          ligne(montant: 20000, nature: NatureDepense.tomate),
          ligne(
            montant: 5000,
            nature: NatureDepense.transport,
            compte: '622100',
            libelle: 'Taxi retour marché',
          ),
        ],
      );

      final k = IndicateursDepenses.calculer([melangee]);

      expect(k.total, 25000);
      expect(k.marche, 20000);
      expect(k.services, 5000);
      expect(k.marche + k.services, k.total);
    });

    test('« Caisse » ne compte que les espèces', () {
      final k = IndicateursDepenses.calculer([
        depense(id: 'a', lignes: [ligne(montant: 10000)]),
        depense(
          id: 'b',
          tresorerie: TresorerieDepense.banque,
          lignes: [ligne(montant: 45000)],
        ),
        depense(
          id: 'c',
          tresorerie: TresorerieDepense.momo,
          lignes: [ligne(montant: 12000)],
        ),
      ]);

      expect(k.total, 67000);
      expect(k.caisse, 10000, reason: 'la carte annonce « espèces »');
    });

    test('une trésorerie inconnue n’est pas rangée dans la caisse', () {
      final k = IndicateursDepenses.calculer([
        depense(id: 'x', tresorerie: null, lignes: [ligne(montant: 9000)]),
      ]);

      expect(k.total, 9000);
      expect(k.caisse, 0);
    });

    test('la dépense moyenne est ABSENTE quand la liste est vide', () {
      final k = IndicateursDepenses.calculer(const []);

      // `null`, jamais `0` : « aucune dépense saisie » et « zéro franc
      // dépensé » ne disent pas la même chose (Article 7).
      expect(k.moyenne, isNull);
      expect(k.nombre, 0);
      expect(k.total, 0);
    });

    test('la moyenne est le total divisé par le nombre de pièces', () {
      final k = IndicateursDepenses.calculer([
        depense(id: 'a', lignes: [ligne(montant: 10000)]),
        depense(id: 'b', lignes: [ligne(montant: 20000)]),
      ]);

      expect(k.moyenne, 15000);
    });
  });

  group('L’affichage d’une ligne', () {
    test('un compte du PLAN rend son libellé', () {
      const plan = LibellesDesComptes({'6052': 'Fournitures non stockables'});
      expect(
        ligne(montant: 1, compte: '6052').compteAffiche(plan),
        '6052 · Fournitures non stockables',
      );
    });

    test('un compte de l’ANCIEN registre à six chiffres reste nommé', () {
      // Une dépense saisie avant la v16 porte encore « 601100 » : sans l'ancien
      // registre, elle s'afficherait « 601100 · — » alors que la ligne a été
      // enregistrée avec ce libellé.
      expect(
        ligne(
          montant: 1,
          compte: '601100',
        ).compteAffiche(const LibellesDesComptes()),
        '601100 · Achats denrées alimentaires (cuisine)',
      );
    });

    test('le PLAN l’emporte sur l’ancien registre', () {
      const plan = LibellesDesComptes({'601100': 'Libellé du plan'});
      expect(
        ligne(montant: 1, compte: '601100').compteAffiche(plan),
        '601100 · Libellé du plan',
      );
    });

    test('un compte absent des deux rend « — », jamais un voisin', () {
      // Un libellé approché donnerait à un compte erroné l'apparence d'un
      // compte juste.
      expect(
        ligne(
          montant: 1,
          compte: '999999',
        ).compteAffiche(const LibellesDesComptes({'6052': 'x'})),
        '999999 · —',
      );
    });

    test('les natures distinctes sont jointes, aucune n’est tue', () {
      final d = depense(
        lignes: [
          ligne(montant: 1, nature: NatureDepense.tomate),
          ligne(montant: 2, nature: NatureDepense.viande),
          ligne(montant: 3, nature: NatureDepense.tomate),
        ],
      );

      expect(d.naturesAffichees, 'Tomate, Viande');
    });
  });
}
