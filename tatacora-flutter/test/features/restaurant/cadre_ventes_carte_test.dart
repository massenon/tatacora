import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/bar/presentation/widgets/vue_ventes_bar.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/cadre_ventes_carte.dart';

import '../../support/vue_blade.dart';

/// Le cadre du panneau « Ventes » des deux cartes — Phase 2, 09/10/2026.
///
/// ## Ce que ces cas protègent
///
/// Le cadre est l'UNIQUE auteur des mots du panneau pour le bar et le
/// restaurant (`pwa/carte/corps.blade.php` l.563-711). Deux défauts le
/// guettent : un mot qui diverge de la langue servie par la PWA (les écrans
/// jumeaux finissent par diverger), et un chiffre plausible — « 0 ligne(s) »,
/// « 0 FCFA » — là où le poste ne détient aucune vente.
///
/// Les libellés sont RELUS de `lang/fr/carte_pwa.php` par PHP, jamais
/// recopiés : une liste recopiée ici ne vérifierait qu'elle-même.
void main() {
  String commun(String cle) => VueBlade.libelle('carte_pwa.commun.$cle')!;

  group('les mots du panneau sont ceux de la vue', () {
    test('un mot par clé de langue, au caractère près', () {
      final attendus = <String, String>{
        TextesVentesCarte.recherche: commun('ventes_recherche'),
        TextesVentesCarte.tousStatuts: commun('ventes_tous_statuts'),
        TextesVentesCarte.validee: commun('ventes_statut_validee'),
        TextesVentesCarte.annulee: commun('ventes_statut_annulee'),
        TextesVentesCarte.du: commun('ventes_du'),
        TextesVentesCarte.au: commun('ventes_au'),
        TextesVentesCarte.bornesAide: commun('ventes_bornes_aide'),
        TextesVentesCarte.stockAide: commun('ventes_stock_aide'),
        TextesVentesCarte.totalPage: commun('ventes_total_page'),
        TextesVentesCarte.totalPageAide: commun('ventes_total_page_aide'),
      };
      // Un balayage vide serait vert : dix mots, ni plus ni moins.
      expect(attendus, hasLength(10));
      for (final e in attendus.entries) {
        expect(e.key, e.value);
      }
    });

    test('le compteur absent garde le gabarit de la vue, sans chiffre', () {
      final gabarit = commun('ventes_compteur');
      expect(gabarit, ':nombre ligne(s) · Total validé : :total');
      expect(
        TextesVentesCarte.compteurAbsent,
        gabarit.replaceAll(':nombre', '—').replaceAll(':total', '—'),
      );
      expect(TextesVentesCarte.compteurAbsent, isNot(contains('0')));
    });

    test('les colonnes suivent la vue : trois à gauche, six à droite', () {
      final attendues = [
        for (final cle in const [
          'date',
          'ticket',
          'article',
          'stock',
          'prix',
          'quantite',
          'montant',
          'statut',
          'utilisateur',
        ])
          commun('ventes_col_$cle'),
      ];
      expect(colonnesVentesCarte.map((c) => c.titre).toList(), attendues);
      expect(colonnesVentesCarte.map((c) => c.aDroite).toList(), [
        false,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
      ]);
    });

    test(
      'le bar reprend les mêmes mots que le cadre, il n’en tient pas un second',
      () {
        expect(TextesVentesBar.recherche, TextesVentesCarte.recherche);
        expect(TextesVentesBar.tousStatuts, TextesVentesCarte.tousStatuts);
        expect(TextesVentesBar.bornesAide, TextesVentesCarte.bornesAide);
        expect(TextesVentesBar.stockAide, TextesVentesCarte.stockAide);
        expect(TextesVentesBar.totalPage, TextesVentesCarte.totalPage);
        expect(TextesVentesBar.totalPageAide, TextesVentesCarte.totalPageAide);
        expect(
          TextesVentesBar.colonnes,
          colonnesVentesCarte.map((c) => c.titre).toList(),
        );
      },
    );
  });

  group('le cadre sans donnée', () {
    Future<void> monter(WidgetTester tester, {required String message}) async {
      tester.view
        ..physicalSize = const Size(1383, 1000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: SingleChildScrollView(
              child: CadreVentesSansDonnee(
                cleMessage: const Key('message-ventes'),
                message: message,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('dit le message reçu, tel quel, et n’invente aucun chiffre', (
      tester,
    ) async {
      await monter(tester, message: 'Motif exact du refus.');

      expect(
        tester.widget<Text>(find.byKey(const Key('message-ventes'))).data,
        'Motif exact du refus.',
      );
      // Le total de la page est « — » : une somme de zéro ligne n'a pas été
      // faite, « 0 FCFA » affirmerait le contraire.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      expect(find.textContaining('FCFA'), findsNothing);
    });

    testWidgets('le message occupe la place de la ligne vide, sous l’en-tête', (
      tester,
    ) async {
      await monter(tester, message: 'Motif exact du refus.');

      final entete = tester.getRect(find.text('DATE'));
      final message = tester.getRect(find.byKey(const Key('message-ventes')));
      final total = tester.getRect(find.text(TextesVentesCarte.totalPage));

      expect(message.top, greaterThan(entete.bottom));
      expect(total.top, greaterThan(message.bottom));
    });
  });
}
