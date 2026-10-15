import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/graphiques_tableau_de_bord.dart';

import '../../support/vue_blade.dart';

/// D329 (réécrite le 13/10/2026, décision du lead) : les parts d'activité ont
/// la couleur que la vue d'accueil PEINT RÉELLEMENT — le gris de
/// `COULEUR_PAR_DEFAUT` pour toute activité nommée —, pas celle que sa table
/// `COULEURS_MODULE` voudrait. Le défaut est celui de la vue, il est à
/// remonter à l'Architecte ; le poste suivra la correction.
///
/// Rien n'est recopié dans ce test : la table des couleurs, la couleur par
/// défaut et la table des noms sont RELUES dans la vue, et la couleur peinte
/// est rejouée comme le script la calcule (piège 12).
void main() {
  late final String vue = VueBlade.fichier(
    'resources/views/pwa/livewire/accueil.blade.php',
    role: 'le script des graphiques de la vue d accueil',
  );

  Color couleurCss(String hex) => Color(int.parse('FF$hex', radix: 16));

  /// `const COULEURS_MODULE = { M1: '#14213D', … }`.
  Map<String, Color> couleursModule() {
    final bloc = RegExp(
      r'const COULEURS_MODULE = \{([^}]*)\}',
    ).firstMatch(vue)!.group(1)!;
    return {
      for (final m in RegExp(r"(M\d+): '#([0-9A-Fa-f]{6})'").allMatches(bloc))
        m.group(1)!: couleurCss(m.group(2)!),
    };
  }

  /// `const COULEUR_PAR_DEFAUT = '#64748B';`.
  Color couleurParDefaut() => couleurCss(
    RegExp(
      r"const COULEUR_PAR_DEFAUT = '#([0-9A-Fa-f]{6})'",
    ).firstMatch(vue)!.group(1)!,
  );

  /// Les clés de `<script … id="noms-activites">{ "M1": …, … }`.
  Set<String> codesNommes() {
    final bloc = RegExp(
      // Jusqu'à `</script>` : les valeurs sont des `{{ __('…') }}`.
      r'id="noms-activites">([\s\S]*?)</script>',
    ).firstMatch(vue)!.group(1)!;
    return {for (final m in RegExp(r'"(M\d+)":').allMatches(bloc)) m.group(1)!};
  }

  /// La couleur que le script de la vue PEINT pour un code de ventilation :
  /// `couleurs(modules)` avec `modules = NOMS_ACTIVITES[l.module] || l.module`.
  /// Un code nommé devient un nom (jamais une clé de `COULEURS_MODULE`).
  Color peinteParLaVue(String code) {
    final cle = codesNommes().contains(code) ? 'nom:$code' : code;
    return couleursModule()[cle] ?? couleurParDefaut();
  }

  test('le défaut de la vue est TOUJOURS là : les noms passent à '
      '`couleurs()`, la table est indexée par code (ce test rougira le jour '
      'où la vue sera corrigée — rouvrir alors `couleurActivite`)', () {
    expect(
      vue,
      contains('ventilation.map((l) => NOMS_ACTIVITES[l.module] || l.module)'),
    );
    expect(
      RegExp(r'backgroundColor: couleurs\(modules\)').allMatches(vue),
      hasLength(2),
      reason: 'l’anneau et les barres horizontales',
    );
    // Balayage non vide : les tables relues portent bien des entrées.
    expect(couleursModule(), hasLength(greaterThanOrEqualTo(7)));
    expect(codesNommes(), {'M1', 'M4', 'M5', 'M8', 'M9'});
    expect(couleurParDefaut(), const Color(0xFF64748B));
  });

  test('couleurActivite rend, code par code, la couleur que la vue PEINT : '
      'le gris pour les cinq activités nommées, la couleur de table pour M2 '
      'et M10 (que la vue ne nomme pas), le gris pour un code inconnu', () {
    final codes = {...couleursModule().keys, ...codesNommes(), 'M99'};
    expect(codes, hasLength(greaterThanOrEqualTo(8)));
    var gris = 0, colores = 0;
    for (final code in codes) {
      expect(couleurActivite(code), peinteParLaVue(code), reason: code);
      if (peinteParLaVue(code) == couleurParDefaut()) {
        gris++;
      } else {
        colores++;
      }
    }
    // Le jeu mord des deux côtés : des parts grises ET des parts colorées.
    expect(gris, greaterThanOrEqualTo(6));
    expect(colores, 2);
  });

  Future<void> monter(WidgetTester tester, Widget enfant) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(width: 600, child: enfant),
          ),
        ),
      ),
    );
  }

  const parts = [
    PartActivite(module: 'M1', montant: '50000.00'),
    PartActivite(module: 'M5', montant: '4500.00'),
    PartActivite(module: 'M2', montant: '1000.00'),
  ];

  testWidgets('RENDU — l’anneau « Réservations par activité » : sections et '
      'légende de la couleur peinte par la vue (M1 et M5 en gris #64748B, '
      'M2 en #6B7280)', (tester) async {
    await monter(tester, const GraphiqueRepartition(parts: parts));

    final sections = tester
        .widget<PieChart>(find.byType(PieChart))
        .data
        .sections;
    expect(
      [for (final s in sections) s.color],
      [AppColors.neutre500, AppColors.neutre500, AppColors.gris],
    );
    expect(AppColors.neutre500, const Color(0xFF64748B));
    for (final p in parts) {
      final pastille = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(Key('tdb-part-${p.module}')),
              matching: find.byType(Container),
            )
            .first,
      );
      expect(pastille.color, peinteParLaVue(p.module), reason: p.module);
    }
  });

  testWidgets('RENDU — les barres « Statistiques de ventes par activité » '
      'ont la même couleur peinte', (tester) async {
    await monter(tester, const GraphiqueActivites(parts: parts));

    final carte = find.byKey(const Key('tdb-carte-ventes-activite'));
    final remplissages = [
      for (final c in tester.widgetList<Container>(
        find.descendant(of: carte, matching: find.byType(Container)),
      ))
        if (c.decoration case BoxDecoration(
          :final color?,
        ) when color != AppColors.neutre100 && color != AppColors.neutre0)
          color,
    ];
    // Une barre colorée par part, dans l'ordre des parts.
    expect(
      remplissages.where(
        (c) => c == AppColors.neutre500 || c == AppColors.gris,
      ),
      [AppColors.neutre500, AppColors.neutre500, AppColors.gris],
    );
    // Aucune couleur « voulue » par la table de la vue n'est rendue.
    for (final voulue in [AppColors.navy, AppColors.serviceBar]) {
      expect(remplissages, isNot(contains(voulue)));
    }
  });
}
