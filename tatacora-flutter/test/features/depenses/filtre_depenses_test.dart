import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/filtre_depenses.dart';

/// Les cinq filtres de la barre, et la **portée** qui part avec l'export.
///
/// C'est la même liste que l'écran affiche, que les six indicateurs somment et
/// que le fichier emporte (PA-119, PA-121) : une seule fonction, donc un seul
/// endroit où cette règle peut changer.
void main() {
  LigneDepense ligne(
    int montant,
    NatureDepense nature, {
    String compte = '601100',
    String libelle = 'Achat',
  }) => LigneDepense(
    id: 'l-$montant-${nature.name}',
    libelle: libelle,
    compteCharge: compte,
    nature: nature.libelle,
    famille: nature.famille.libelle,
    montant: montant,
  );

  Depense depense({
    required String id,
    required DateTime date,
    required List<LigneDepense> lignes,
    TresorerieDepense? tresorerie = TresorerieDepense.caisse,
    String libelle = 'Marché du matin',
  }) => Depense(
    id: id,
    dateTransaction: date,
    tresorerie: tresorerie,
    libelle: libelle,
    lignes: lignes,
    saisieLe: date,
  );

  final marche = depense(
    id: 'marche',
    date: DateTime(2026, 9, 10),
    libelle: 'Marché du matin — Légumes & condiments',
    lignes: [
      ligne(15000, NatureDepense.oignon, libelle: 'Achat d\'oignons (2 sacs)'),
      ligne(8500, NatureDepense.tomate, libelle: 'Tomates fraîches'),
    ],
  );

  final electricite = depense(
    id: 'sbee',
    date: DateTime(2026, 9, 1),
    libelle: 'Facture d\'électricité SBEE & Eau SONEB',
    tresorerie: TresorerieDepense.banque,
    lignes: [
      ligne(
        45000,
        NatureDepense.electriciteEau,
        compte: '604000',
        libelle: 'Recharge compteur Électricité',
      ),
    ],
  );

  /// Une pièce MÊLÉE : des denrées et un transport sur la même dépense.
  final melangee = depense(
    id: 'melangee',
    date: DateTime(2026, 9, 14),
    libelle: 'Approvisionnement Poissonnerie',
    tresorerie: TresorerieDepense.momo,
    lignes: [
      ligne(32000, NatureDepense.poisson, libelle: 'Poissons Capitaine frais'),
      ligne(
        5000,
        NatureDepense.transport,
        compte: '622100',
        libelle: 'Taxi retour marché',
      ),
    ],
  );

  final registre = [melangee, marche, electricite];

  test('sans filtre, la liste entière est rendue', () {
    expect(filtrerDepenses(registre, const FiltreDepenses()), hasLength(3));
    expect(const FiltreDepenses().applique, isFalse);
  });

  group('Le filtre de catégorie porte sur la FAMILLE des lignes', () {
    test('« Marché » retient aussi la pièce mêlée', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecFamille(FamilleDepense.marche),
      );

      // La pièce mêlée a une ligne de denrées : la masquer ferait disparaître
      // 32 000 F du rayon « Marché » sans que rien ne le signale.
      expect(retenues.map((d) => d.id), containsAll(['marche', 'melangee']));
      expect(retenues.map((d) => d.id), isNot(contains('sbee')));
    });

    test('« Services » retient la même pièce mêlée, et l’électricité', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecFamille(FamilleDepense.services),
      );

      expect(retenues.map((d) => d.id), containsAll(['melangee', 'sbee']));
      expect(retenues.map((d) => d.id), isNot(contains('marche')));
    });
  });

  test('Le filtre de trésorerie ne retient que son compte', () {
    final retenues = filtrerDepenses(
      registre,
      const FiltreDepenses().avecTresorerie(TresorerieDepense.banque),
    );

    expect(retenues, hasLength(1));
    expect(retenues.single.id, 'sbee');
  });

  group('Les bornes de date sont INCLUSES', () {
    test('« à partir du » garde la dépense du jour même', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecDu(DateTime(2026, 9, 10)),
      );

      expect(retenues.map((d) => d.id), containsAll(['marche', 'melangee']));
      expect(retenues.map((d) => d.id), isNot(contains('sbee')));
    });

    test('« jusqu’au » garde la dépense du jour même', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecAu(DateTime(2026, 9, 10)),
      );

      expect(retenues.map((d) => d.id), containsAll(['marche', 'sbee']));
      expect(retenues.map((d) => d.id), isNot(contains('melangee')));
    });

    test('une heure dans la borne ne fait pas sortir la dépense du jour', () {
      // La borne vient d'un sélecteur de date, qui peut porter une heure. Une
      // comparaison sur l'instant, et non sur le jour, exclurait la dépense
      // saisie le matin même.
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecAu(DateTime(2026, 9, 10, 23, 59)),
      );

      expect(retenues.map((d) => d.id), contains('marche'));
    });
  });

  group('La recherche porte sur le libellé, la nature et le compte', () {
    test('le libellé d’une LIGNE est retrouvé', () {
      // « Tomates fraîches » n'apparaît nulle part dans le libellé de la
      // pièce : chercher un achat sans le trouver ferait conclure qu'il n'a
      // jamais été saisi.
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecTerme('tomates'),
      );

      expect(retenues, hasLength(1));
      expect(retenues.single.id, 'marche');
    });

    test('une nature est retrouvée', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecTerme('Transport'),
      );

      expect(retenues.single.id, 'melangee');
    });

    test('un numéro de compte est retrouvé', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecTerme('604000'),
      );

      expect(retenues.single.id, 'sbee');
    });

    test('le LIBELLÉ du compte est retrouvé, pas seulement son numéro', () {
      final retenues = filtrerDepenses(
        registre,
        const FiltreDepenses().avecTerme('Locations diverses'),
      );

      expect(retenues.single.id, 'melangee');
    });
  });

  test('Les filtres se COMBINENT', () {
    final retenues = filtrerDepenses(
      registre,
      const FiltreDepenses()
          .avecFamille(FamilleDepense.marche)
          .avecTresorerie(TresorerieDepense.caisse),
    );

    expect(retenues, hasLength(1));
    expect(retenues.single.id, 'marche');
  });

  group('Un filtre peut être remis à VIDE', () {
    test('« Réinitialiser » rend la liste entière', () {
      // Sans cette propriété, le bouton « Réinitialiser » de la vue ne pourrait
      // pas faire son travail : passer `null` doit EFFACER la borne, pas
      // vouloir dire « ne change pas ».
      final pose = const FiltreDepenses()
          .avecDu(DateTime(2026, 9, 14))
          .avecTresorerie(TresorerieDepense.momo);
      expect(pose.applique, isTrue);

      final vide = pose.avecDu(null).avecTresorerie(null);
      expect(vide.applique, isFalse);
      expect(filtrerDepenses(registre, vide), hasLength(3));
    });
  });

  group('La portée PART avec le document (PA-119)', () {
    test('sans filtre, elle le dit', () {
      expect(
        const FiltreDepenses().description,
        'Registre entier, aucun filtre appliqué',
      );
    });

    test('chaque filtre posé est nommé', () {
      final portee = const FiltreDepenses()
          .avecTerme('tomates')
          .avecDu(DateTime(2026, 9, 1))
          .avecTresorerie(TresorerieDepense.caisse)
          .avecFamille(FamilleDepense.marche)
          .description;

      expect(portee, contains('recherche « tomates »'));
      expect(portee, contains('à partir du 01/09/2026'));
      expect(portee, contains('trésorerie « Caisse »'));
      expect(portee, contains('catégorie « Marché »'));
    });
  });
}
