import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/corps_carte_commun.dart';

/// La gouttière de défilement de `PageCarte` (10/10/2026).
///
/// `<main class="flex-1 overflow-y-auto">` de la vue porte une barre de
/// navigateur classique de 8 px (`app.css` l.79) : elle retire 8 px à la zone
/// utile dès que la page déborde, et seulement alors. Mesuré sur `rh/paie` :
/// 1 047 px utiles au navigateur, 1 055 ici avant ce correctif.
void main() {
  const fenetre = Size(1383, 729);
  // `lg:p-8` : la fenêtre dépasse 1 024 px.
  const marge = AppSpacing.xl;
  const cle = Key('contenu');

  Future<double> largeurDuContenu(
    WidgetTester tester, {
    required double hauteur,
    Widget? avant,
  }) async {
    tester.view
      ..physicalSize = fenetre
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageCarte(
            largeurMax: AppLayout.pagePaie,
            enfants: [
              ?avant,
              SizedBox(key: cle, height: hauteur),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byKey(cle)).width;
  }

  testWidgets('une page qui déborde perd 8 px à droite', (tester) async {
    final largeur = await largeurDuContenu(tester, hauteur: 3000);

    expect(largeur, fenetre.width - 2 * marge - AppLayout.gouttiereDefilement);
  });

  testWidgets('une page qui ne déborde pas garde toute sa largeur', (
    tester,
  ) async {
    final largeur = await largeurDuContenu(tester, hauteur: 100);

    expect(largeur, fenetre.width - 2 * marge);
  });

  testWidgets('la marge gauche est inchangée, la droite gagne la gouttière', (
    tester,
  ) async {
    await largeurDuContenu(tester, hauteur: 3000);

    final gauche = tester.getTopLeft(find.byKey(cle)).dx;
    final droite = tester.getTopRight(find.byKey(cle)).dx;

    // Marge gauche inchangée ; à droite, marge + gouttière.
    expect(gauche, marge);
    expect(fenetre.width - droite, marge + AppLayout.gouttiereDefilement);
  });

  testWidgets('un défilement INTERNE ne réserve pas la gouttière de la page', (
    tester,
  ) async {
    // Un tableau qui défile en largeur dans une page courte : sa barre n'est
    // pas celle de la page.
    final largeur = await largeurDuContenu(
      tester,
      hauteur: 100,
      avant: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: const SizedBox(width: 5000, height: 20),
      ),
    );

    expect(largeur, fenetre.width - 2 * marge);
  });

  testWidgets('la gouttière se retire quand la page cesse de déborder', (
    tester,
  ) async {
    await largeurDuContenu(tester, hauteur: 3000);

    // Le même arbre, devenu court : même `State`, même type de widget.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PageCarte(
            largeurMax: AppLayout.pagePaie,
            enfants: [SizedBox(key: cle, height: 100)],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byKey(cle)).width, fenetre.width - 2 * marge);
  });
}
