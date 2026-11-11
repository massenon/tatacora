import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/fiche_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// La fiche CONSOLIDÉE (« Tous les articles ») — des fonctions pures, éprouvées
/// sur des valeurs calculées À LA MAIN (chaque cas dit son calcul).
///
/// La règle que ces cas tiennent est celle de `FicheStockService::
/// pourTousLesArticles` : chaque article garde SA fiche ; seule la VALEUR se
/// totalise ; les quantités d'unités différentes ne s'additionnent JAMAIS.
void main() {
  ArticleFiche article(String libelle, String unite) =>
      ArticleFiche(id: libelle, libelle: libelle, unite: unite, cmp: '');

  MouvementCalcul mouvement(
    String articleId,
    TypeMouvement type,
    int centiemes,
    int ordre,
    DateTime date, {
    int? cout,
    String auteur = 'Aïcha',
  }) => MouvementCalcul(
    id: 'm$ordre',
    articleId: articleId,
    pointId: 'p',
    type: type,
    centiemes: centiemes,
    ordre: ordre,
    date: date,
    motif: 'essai',
    auteur: auteur,
    coutDixMilliemes: cout,
  );

  final debut = DateTime(2026, 10, 1);
  final fin = DateTime(2026, 10, 31);

  FicheStock fiche(ArticleFiche a, List<MouvementCalcul> mouvements, int cmp) =>
      calculerFiche(
        article: a,
        cmp: cmp,
        mouvements: mouvements,
        debut: debut,
        fin: fin,
      );

  group('consoliderFiches', () {
    // Riz : +10 sacs à 1 000 F (ordre 1), −4 sacs (ordre 3) -> 6 sacs, 6 000 F.
    // Bière : +5 casiers à 500 F (ordre 2) -> 5 casiers, 2 500 F.
    // Sel : jamais mouvementé -> 0 F, mais compté au catalogue.
    final riz = article('Riz', 'sac');
    final biere = article('Bière', 'casier');
    final sel = article('Sel', 'kg');
    final instant = DateTime(2026, 10, 5, 8);

    final fiches = [
      fiche(biere, [
        mouvement(
          'Bière',
          TypeMouvement.entree,
          500,
          2,
          instant,
          cout: 5000000,
        ),
      ], 5000000),
      fiche(riz, [
        mouvement(
          'Riz',
          TypeMouvement.entree,
          1000,
          1,
          instant,
          cout: 10000000,
        ),
        mouvement(
          'Riz',
          TypeMouvement.sortie,
          400,
          3,
          DateTime(2026, 10, 7, 9),
        ),
      ], 10000000),
      fiche(sel, const [], 0),
    ];

    test('les comptes : articles du catalogue, articles mouvementés, '
        'mouvements', () {
      final c = consoliderFiches(fiches, debut: debut, fin: fin);

      expect(c.articles, 3, reason: 'Bière, Riz, Sel');
      expect(c.articlesAvecMouvement, 2, reason: 'Sel n’a pas bougé');
      expect(c.mouvements, 3, reason: '1 + 2 + 0');
    });

    test('seule la VALEUR se totalise : 6 000 + 2 500 + 0 = 8 500 F', () {
      final c = consoliderFiches(fiches, debut: debut, fin: fin);

      expect(c.valeurStockTheorique, '8500');
    });

    test('un article dormant a une valeur en magasin : il est compté dans le '
        'total sans figurer au détail', () {
      final dormant = fiche(article('Farine', 'sac'), [
        mouvement(
          'Farine',
          TypeMouvement.entree,
          200,
          1,
          DateTime(2026, 9, 1),
          cout: 20000000,
        ),
      ], 20000000);
      // 2 sacs à 2 000 F = 4 000 F, entrés AVANT la période.
      final c = consoliderFiches([dormant], debut: debut, fin: fin);

      expect(c.valeurStockTheorique, '4000');
      expect(c.mouvements, 0);
      expect(c.articlesAvecMouvement, 0);
      expect(c.articles, 1);
    });

    test(
      'chronologique tous articles confondus ; à date égale, par article',
      () {
        // Fiches données dans le DÉSORDRE (Riz avant Bière) : le tri, pas
        // l'ordre d'arrivée, décide.
        final c = consoliderFiches(
          [fiches[1], fiches[0], fiches[2]],
          debut: debut,
          fin: fin,
        );

        expect(
          [for (final l in c.lignes) '${l.article} ${l.ligne.type}'],
          [
            // 05/10 08:00:00 : même instant, « Bière » < « Riz ».
            'Bière Entrée',
            'Riz Entrée',
            // 07/10 09:00:00.
            'Riz Sortie',
          ],
        );
      },
    );

    test('chaque ligne garde son unité ET le solde de SON article', () {
      final c = consoliderFiches(fiches, debut: debut, fin: fin);

      final biereEntree = c.lignes[0];
      expect(biereEntree.unite, 'casier');
      expect(biereEntree.ligne.solde, '5.00');

      final rizSortie = c.lignes[2];
      expect(rizSortie.unite, 'sac');
      // 10 − 4 : le solde de la fiche du riz, pas 5 + 10 − 4.
      expect(rizSortie.ligne.solde, '6.00');
    });

    test('l’auteur du mouvement est CONNU ici : la ligne le porte', () {
      final c = consoliderFiches(fiches, debut: debut, fin: fin);

      expect(c.lignes.every((l) => l.ligne.par == 'Aïcha'), isTrue);
    });

    test('une fiche INCOHÉRENTE est NOMMÉE, jamais noyée dans un compteur', () {
      final incoherente = FicheStock(
        article: riz,
        debut: '2026-10-01',
        fin: '2026-10-31',
        stockInitial: '0.00',
        entrees: '0.00',
        sorties: '0.00',
        pertes: '0.00',
        regularisations: '0.00',
        stockTheorique: '0.00',
        valeurStockTheorique: '0',
        coherent: false,
        pointId: null,
        lignes: const [],
      );

      final c = consoliderFiches(
        [fiches[0], incoherente],
        debut: debut,
        fin: fin,
      );

      expect(c.incoherents, ['Riz']);
      expect(
        consoliderFiches(fiches, debut: debut, fin: fin).incoherents,
        isEmpty,
      );
    });

    test('une valeur négative (sortie forcée) se totalise avec son signe', () {
      // −4 sacs à 1 000 F = −4 000 F ; +5 casiers à 500 F = +2 500 F.
      final negative = fiche(riz, [
        mouvement(
          'Riz',
          TypeMouvement.entree,
          1000,
          1,
          instant,
          cout: 10000000,
        ),
        mouvement('Riz', TypeMouvement.sortie, 1400, 3, instant),
      ], 10000000);

      final c = consoliderFiches([fiches[0], negative], debut: debut, fin: fin);

      expect(c.valeurStockTheorique, '-1500');
    });
  });

  group('dateHeureDeLaVue', () {
    test('« 2026-10-09 14:03:22 » -> « 09/10/2026 14:03 »', () {
      expect(dateHeureDeLaVue('2026-10-09 14:03:22'), '09/10/2026 14:03');
    });

    test('une chaîne inattendue est rendue telle quelle, jamais inventée', () {
      expect(dateHeureDeLaVue('hier'), 'hier');
      expect(dateHeureDeLaVue(''), '');
    });
  });
}
