import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/responsive/rangee_flex_wrap.dart';

/// La rangée `flex-wrap` AVEC croissance de la barre de filtres des Stocks.
///
/// Les cas de la fonction pure sont calculés à la main (le calcul est dans le
/// nom du cas) ; les cas de widget posent des cases de largeur connue et lisent
/// leurs positions — la mesure ne passe jamais par la fonction qu'elle éprouve.
void main() {
  group(
    'partagerCroissance — l’espace libre, à égalité, plancher respecté',
    () {
      test('assez de place : part égale', () {
        // 600 / 2 = 300 chacun ; le plancher de 220 est respecté.
        expect(partagerCroissance(planchers: [220, 0], libre: 600), [300, 300]);
      });

      test('un plancher qui ne tient pas dans la part est FIGÉ', () {
        // Part 400 / 2 = 200 < 220 : le premier est figé à 220, le reste (180)
        // va au second.
        expect(partagerCroissance(planchers: [220, 0], libre: 400), [220, 180]);
      });

      test(
        'un espace libre insuffisant ne rend jamais une largeur négative',
        () {
          // Part 50 < 220 : figé à 220, reste -120 -> le second reçoit 0.
          expect(partagerCroissance(planchers: [220, 0], libre: 100), [220, 0]);
        },
      );

      test('trois éléments à égalité', () {
        expect(partagerCroissance(planchers: [100, 100, 100], libre: 450), [
          150,
          150,
          150,
        ]);
      });

      test('le figeage se propage : 300 figé, puis 75 et 75', () {
        // Part 450 / 3 = 150 < 300 : figé ; reste 150, deux restants -> 75.
        expect(partagerCroissance(planchers: [300, 0, 0], libre: 450), [
          300,
          75,
          75,
        ]);
      });

      test('aucun élément : rien', () {
        expect(partagerCroissance(planchers: [], libre: 100), isEmpty);
      });
    },
  );

  group('RangeeFlexWrap — le repli et la croissance du navigateur', () {
    Widget boite(String cle, double largeur, {double hauteur = 20}) =>
        SizedBox(key: Key(cle), width: largeur, height: hauteur);

    Future<void> monter(
      WidgetTester tester, {
      required double largeur,
      required List<Widget> enfants,
    }) async {
      // Le banc d'essai fait 800 px : une rangée plus large serait rognée par
      // la FENÊTRE et le calcul porterait sur une largeur qui n'est pas celle
      // qu'on croit éprouver.
      tester.view
        ..physicalSize = const Size(2000, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: largeur,
              child: RangeeFlexWrap(
                key: const Key('rangee'),
                ecart: 10,
                ecartLignes: 8,
                children: enfants,
              ),
            ),
          ),
        ),
      );
    }

    Offset pos(WidgetTester tester, String cle) =>
        tester.getTopLeft(find.byKey(Key(cle))) -
        tester.getTopLeft(find.byKey(const Key('rangee')));

    double largeurDe(WidgetTester tester, String cle) =>
        tester.getSize(find.byKey(Key(cle))).width;

    testWidgets('tout tient : l’élément élastique prend le reste', (
      tester,
    ) async {
      await monter(
        tester,
        largeur: 500,
        enfants: [
          boite('a', 100),
          ElementElastique(largeurMin: 50, child: boite('b', 1)),
          boite('c', 100),
        ],
      );

      // 500 - 200 (rigides) - 20 (deux écarts) = 280.
      expect(largeurDe(tester, 'b'), 280);
      expect(pos(tester, 'a').dx, 0);
      expect(pos(tester, 'b').dx, 110);
      expect(pos(tester, 'c').dx, 400);
      // Le dernier élément touche le bord droit.
      expect(pos(tester, 'c').dx + 100, 500);
    });

    testWidgets('ça ne tient pas : passage à la ligne, écart de lignes', (
      tester,
    ) async {
      await monter(
        tester,
        largeur: 500,
        enfants: [boite('a', 300), boite('b', 300, hauteur: 30)],
      );

      expect(pos(tester, 'a'), const Offset(0, 0));
      // La deuxième ligne commence sous la première (20) + l'écart (8).
      expect(pos(tester, 'b'), const Offset(0, 28));
      expect(tester.getSize(find.byKey(const Key('rangee'))).height, 28 + 30);
    });

    testWidgets('la barre des Stocks à 1 000 px : le deuxième bouton passe à '
        'la ligne, la recherche reste à son plancher', (tester) async {
      // Recherche (plancher 220), quatre listes de 150, un espace élastique,
      // trois boutons de 60 — la composition de la vue.
      await monter(
        tester,
        largeur: 1000,
        enfants: [
          ElementElastique(largeurMin: 220, child: boite('recherche', 1)),
          boite('l1', 150),
          boite('l2', 150),
          boite('l3', 150),
          boite('l4', 150),
          const ElementElastique(child: SizedBox(key: Key('espace'))),
          boite('b1', 60),
          boite('b2', 60),
          boite('b3', 60),
        ],
      );

      // Ligne 1 : 220 + 4 × 150 + 0 + 60 = 880 de contenu, 6 écarts = 60 ->
      // 940 ; avec « b2 » (+10 +60) : 1010 > 1000 -> « b2 » passe à la ligne.
      // Libre = 1000 - 660 - 60 = 280 ; part 140 < 220 : la recherche est
      // figée à son plancher, l'espace reçoit les 60 restants.
      expect(largeurDe(tester, 'recherche'), 220);
      expect(largeurDe(tester, 'espace'), 60);
      // « b1 » finit pile au bord droit : 1000.
      expect(pos(tester, 'b1').dx + 60, 1000);
      expect(pos(tester, 'b1').dy, 0);

      // Ligne 2 : « b2 » puis « b3 », à gauche.
      expect(pos(tester, 'b2'), const Offset(0, 28));
      expect(pos(tester, 'b3'), const Offset(70, 28));
    });

    testWidgets('large : la recherche GRANDIT, les boutons restent à droite', (
      tester,
    ) async {
      await monter(
        tester,
        largeur: 1600,
        enfants: [
          ElementElastique(largeurMin: 220, child: boite('recherche', 1)),
          boite('l1', 150),
          const ElementElastique(child: SizedBox(key: Key('espace'))),
          boite('b1', 60),
          boite('b2', 60),
        ],
      );

      // Libre = 1600 - (150 + 60 + 60) - 4 écarts (40) = 1290 ; part 645.
      expect(largeurDe(tester, 'recherche'), 645);
      expect(largeurDe(tester, 'espace'), 645);
      expect(pos(tester, 'b2').dx + 60, 1600);
    });

    testWidgets('les éléments d’une ligne sont centrés verticalement', (
      tester,
    ) async {
      await monter(
        tester,
        largeur: 400,
        enfants: [
          boite('haut', 50, hauteur: 40),
          boite('bas', 50, hauteur: 20),
        ],
      );

      expect(pos(tester, 'haut').dy, 0);
      // (40 - 20) / 2 = 10.
      expect(pos(tester, 'bas').dy, 10);
    });

    testWidgets('un clic atteint un enfant déplacé', (tester) async {
      tester.view
        ..physicalSize = const Size(2000, 800)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      var touche = false;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 200,
              child: RangeeFlexWrap(
                ecart: 10,
                ecartLignes: 8,
                children: [
                  boite('a', 150),
                  GestureDetector(
                    key: const Key('cible'),
                    // Une boîte vide ne se touche pas sans cela.
                    behavior: HitTestBehavior.opaque,
                    onTap: () => touche = true,
                    child: const SizedBox(width: 150, height: 30),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('cible')));
      expect(touche, isTrue);
    });
  });
}
