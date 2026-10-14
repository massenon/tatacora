// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/modules_pilotage.dart';

/// Le graphique « Créances par ancienneté » de la vue d'accueil
/// (`graphe-creances`, script de la vue l.1975-1996) : quatre barres, une par
/// tranche, dans l'ordre du serveur (`Accueil::creancesParAnciennete`).
///
/// Les couleurs sont celles de la vue, et elles disent quelque chose : la
/// teinte s'assombrit avec l'âge (doré, orange, rouge, bordeaux) — la tranche
/// « plus de 90 jours » est celle qu'on doit voir en premier. L'axe des
/// montants se lit en milliers (« 150k »), comme la vue.
class GraphiqueCreancesAnciennete extends StatelessWidget {
  const GraphiqueCreancesAnciennete({required this.tranches, super.key});

  final List<TrancheCreance> tranches;

  /// `backgroundColor` de la vue, tranche par tranche.
  static const List<Color> couleurs = [
    AppColors.gold, // #B8891E
    AppColors.alerte, // #ED6C02
    PaletteMaitre.rouge600, // #DC2626
    PaletteMaitre.rouge900, // #7F1D1D
  ];

  @override
  Widget build(BuildContext context) {
    final valeurs = [for (final t in tranches) t.montantCentimes / 100];
    final maximum = valeurs.isEmpty
        ? 0.0
        : valeurs.reduce((a, b) => a > b ? a : b);

    return SizedBox(
      // `height:260px` de la vue.
      height: AppSpacing.hauteurGraphePilotage,
      child: BarChart(
        BarChartData(
          minY: 0,
          // Une balance à zéro garde un axe lisible plutôt qu'un cadre plat.
          maxY: maximum <= 0 ? 1000 : maximum * 1.15,
          barGroups: [
            for (final (i, t) in tranches.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: t.montantCentimes / 100,
                    color: couleurs[i % couleurs.length],
                    width: 18,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ],
              ),
          ],
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                // `ticks.callback: (v) => (v / 1000) + 'k'`.
                getTitlesWidget: (valeur, meta) => Text(
                  '${_milliers(valeur)}k',
                  style: TextStyle(
                    fontSize: TaillesContenu.t11,
                    color: Ardoise.c500,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (valeur, meta) {
                  final i = valeur.toInt();
                  if (i < 0 || i >= tranches.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.unit),
                    child: Text(
                      libellesTranchesCreances[tranches[i].cle] ??
                          tranches[i].cle,
                      key: Key('pilotage-creances-tranche-$i'),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TaillesContenu.t11,
                        color: Ardoise.c500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `v / 1000` de JavaScript : un entier s'écrit sans décimale.
  static String _milliers(double v) {
    final k = v / 1000;
    return k == k.roundToDouble() ? '${k.round()}' : '$k';
  }
}
