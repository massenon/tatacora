// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/pilotage.dart';

/// Le tracé « Marge sur coûts directs par activité » — `m11-pilotage.js`,
/// `rendreGraphes` (`graphe-centres`).
///
/// ## L'axe INCLUT toujours zéro, et un cas le tient
///
/// Une marge est un écart à zéro : tronquer l'axe ferait paraître énorme un
/// écart de quelques pour cent, et un centre déficitaire perdrait sa ligne de
/// flottaison. La leçon de PA-122 vaut ici mot pour mot — le commentaire qui
/// affirmait cette propriété sur le graphique voisin n'était tenu par aucun
/// test, et une mutation l'a prouvé. **Le cas existe** :
/// `test/features/tableau_de_bord/pilotage_test.dart` relit `minY`/`maxY` sur
/// le graphique réellement instancié, avec et sans centre déficitaire.
class GraphiqueMargeCentres extends StatelessWidget {
  const GraphiqueMargeCentres({required this.centres, super.key});

  final List<CentreAnalytique> centres;

  @override
  Widget build(BuildContext context) {
    if (centres.isEmpty) {
      // Un cadre vide se lit comme un tracé qui n'a pas chargé.
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Text(
          'Aucun centre mouvementé sur cet exercice.',
          key: const Key('pilotage-centres-vide'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: TaillesContenu.t13, color: Ardoise.c500),
        ),
      );
    }

    final valeurs = [for (final c in centres) c.resultatTrace];
    final maximum = valeurs.reduce((a, b) => a > b ? a : b);
    final minimum = valeurs.reduce((a, b) => a < b ? a : b);

    return SizedBox(
      // `height:260px` du maître (`tableau-de-bord.html` l.208).
      height: AppSpacing.hauteurGraphePilotage,
      child: BarChart(
        BarChartData(
          // Zéro est TOUJOURS dans l'axe : `minY` ne monte jamais au-dessus
          // de 0, `maxY` ne descend jamais en dessous. Sans quoi une marge
          // légèrement positive semblerait immense, ou un déficit
          // disparaîtrait du cadre.
          minY: minimum >= 0 ? 0 : minimum * 1.15,
          maxY: maximum <= 0 ? 0 : maximum * 1.15,
          barGroups: [
            for (final (index, centre) in centres.indexed)
              BarChartGroupData(
                x: index,
                barRods: [
                  BarChartRodData(
                    toY: centre.resultatTrace,
                    // « Le rouge n'est pas décoratif : un centre déficitaire
                    // doit se voir sans avoir à lire l'axe » (le maître).
                    // `#C62828` / `#14213D` : les couleurs de la vue (script
                    // `graphe-centres`), relevées le 13/10/2026.
                    color: centre.deficitaire
                        ? AppColors.erreur
                        : AppColors.navy,
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
                getTitlesWidget: (valeur, meta) => Text(
                  // Notation compacte, comme le `notation: 'compact'` du
                  // maître : un axe en francs pleins déborde de la colonne.
                  _compact(valeur),
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
                  final index = valeur.toInt();
                  if (index < 0 || index >= centres.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.unit),
                    child: Text(
                      centres[index].libelle,
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

  /// « 1,2 M » / « 350 k » — l'équivalent du `Intl.NumberFormat('fr-FR',
  /// {notation: 'compact'})` du maître, sans dépendance.
  static String _compact(double v) {
    final absolu = v.abs();
    final signe = v < 0 ? '-' : '';
    if (absolu >= 1000000) {
      final m = absolu / 1000000;
      return '$signe${m == m.roundToDouble() ? m.round() : m.toStringAsFixed(1).replaceAll('.', ',')} M';
    }
    if (absolu >= 1000) return '$signe${(absolu / 1000).round()} k';
    return '$signe${absolu.round()}';
  }
}
