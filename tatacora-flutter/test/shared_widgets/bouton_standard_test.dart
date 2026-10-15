import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

/// Le bouton standard (D432, D442) aux mesures de la VUE : `text-[13px]`
/// (12,5 dans `<main>`), `py-2`, `px-3.5` / `px-4`, bordure sur toutes les
/// variantes — SAUF la hauteur et le rayon : décision du PO du 14/10/2026,
/// 40 px de haut FIXES et rayon 6 px (au lieu des ~37 px et `rounded-lg` = 8
/// de la vue).
void main() {
  Future<void> monter(WidgetTester tester, Widget bouton) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: bouton)),
      ),
    );
  }

  Container cadre(WidgetTester tester) => tester.widget<Container>(
    find.descendant(
      of: find.byType(BoutonStandard),
      matching: find.byType(Container),
    ),
  );

  Text texte(WidgetTester tester) => tester.widget<Text>(find.text('Exporter'));

  /// La hauteur décidée par le PO (14/10/2026), bordure comprise — écrite en
  /// CLAIR, pas relue du jeton : un jeton modifié doit faire rougir ce test.
  const hauteurPo = 40.0;

  /// Le rayon décidé par le PO (14/10/2026).
  const rayonPo = 6.0;

  testWidgets('secondaire : 12,5 px, interligne 1,5, py-2 px-3.5, rayon 6, '
      '40 px (PO), graisse normale', (tester) async {
    var touches = 0;
    await monter(
      tester,
      BoutonStandard(libelle: 'Exporter', onPressed: () => touches++),
    );

    expect(TaillesContenu.t13, 12.5);
    expect(AppLayout.hauteurBoutonStandard, hauteurPo);
    final c = cadre(tester);
    expect(
      c.padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.smPlus,
        vertical: AppSpacing.xs,
      ),
    );
    expect(AppSpacing.smPlus, 14);
    expect(AppSpacing.xs, 8);
    final deco = c.decoration! as BoxDecoration;
    expect(deco.borderRadius, BorderRadius.circular(rayonPo));
    expect((deco.border! as Border).top.color, Ardoise.c300);

    final style = texte(tester).style!;
    expect(style.fontSize, 12.5);
    expect(style.height, 1.5);
    expect(style.letterSpacing, 0);
    expect(style.fontWeight, FontWeight.w400);

    // 40 px FIXES, bordure comprise — plus les ~37 px de la vue.
    final h = tester.getSize(find.byType(BoutonStandard)).height;
    expect(h, hauteurPo);
    // Le libellé est centré verticalement dans ces 40 px.
    final centreTexte = tester.getCenter(find.text('Exporter')).dy;
    final centreBouton = tester.getCenter(find.byType(BoutonStandard)).dy;
    expect(centreTexte, closeTo(centreBouton, 0.5));

    await tester.tap(find.byType(BoutonStandard));
    expect(touches, 1);
  });

  testWidgets('primaire : px-4, semi-gras, MÊME hauteur que le secondaire '
      '(bordure de sa couleur)', (tester) async {
    await monter(
      tester,
      BoutonStandard(
        libelle: 'Exporter',
        variante: VarianteBouton.primaire,
        onPressed: () {},
      ),
    );
    expect(
      cadre(tester).padding,
      const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
    );
    expect(texte(tester).style!.fontWeight, FontWeight.w600);
    expect(tester.getSize(find.byType(BoutonStandard)).height, hauteurPo);
    final deco = cadre(tester).decoration! as BoxDecoration;
    expect(deco.borderRadius, BorderRadius.circular(rayonPo));
  });

  testWidgets('compact : 12 px, px-3 ; désactivé : grisé et sans geste', (
    tester,
  ) async {
    await monter(
      tester,
      const BoutonStandard(libelle: 'Exporter', compact: true, onPressed: null),
    );
    expect(texte(tester).style!.fontSize, TaillesContenu.t12);
    expect((cadre(tester).padding! as EdgeInsets).left, AppSpacing.sm);
    // La hauteur est FIXE : `compact` ne règle que police et remplissage.
    expect(tester.getSize(find.byType(BoutonStandard)).height, hauteurPo);
    expect(
      tester
          .widget<Opacity>(
            find
                .descendant(
                  of: find.byType(BoutonStandard),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      OpacitesBouton.desactive,
    );
  });
}
