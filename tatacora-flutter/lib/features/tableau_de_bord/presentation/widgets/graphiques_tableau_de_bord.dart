// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/tableau_de_bord.dart';
import 'panneau_exploitation.dart'
    show carteAccueil, lectureImpossible, styleExploitation;

/// La couleur d'une part d'activité, CELLE QUE LA VUE PEINT RÉELLEMENT — pas
/// celle que sa table voudrait (D329 réécrite le 13/10/2026, décision du lead :
/// le serveur fait foi, ses incohérences se notent et ne se corrigent jamais
/// côté poste seul ; une couleur n'est ni un montant ni un état).
///
/// ⚠ DÉFAUT DE LA VUE, répliqué tel quel. Le script des graphiques de la vue
/// d'accueil (l.1923) remplace d'abord chaque code par son NOM d'activité
/// (`NOMS_ACTIVITES[l.module] || l.module`, table `noms-activites` l.686-692 :
/// M1, M4, M5, M8, M9), puis appelle `couleurs(modules)` (l.1929 et l.1943)
/// avec ces NOMS, alors que `COULEURS_MODULE` (l.1816-1819) est indexé par
/// CODE. Résultat exécuté : les cinq activités nommées tombent toutes sur
/// `COULEUR_PAR_DEFAUT` (`#64748B`, l.1820) — un anneau et des barres d'un
/// seul gris, une légende qui ne distingue plus rien. Seul un code que la
/// table des noms ignore garde son code, donc sa couleur de table : `M2`
/// (`#6B7280`) et `M10` (`#C62828`). À remonter à l'Architecte : corriger la
/// vue ; le poste suivra (il suffira alors de rendre [_couleursModuleDeLaVue]
/// par code).
///
/// [module] est le code de la ventilation ([PartActivite.module], registre
/// réel de `lignes_facture.source_module`, PA-170).
Color couleurActivite(String module) {
  // `NOMS_ACTIVITES[l.module] || l.module` : un code nommé par la vue devient
  // un nom, et un nom n'est jamais une clé de `COULEURS_MODULE`.
  if (_codesNommesParLaVue.contains(module)) return _couleurParDefautDeLaVue;
  return _couleursModuleDeLaVue[module] ?? _couleurParDefautDeLaVue;
}

/// Les clés de la table `noms-activites` de la vue (l.686-692).
const Set<String> _codesNommesParLaVue = {'M1', 'M4', 'M5', 'M8', 'M9'};

/// `COULEURS_MODULE` de la vue (l.1816-1819), indexé par CODE.
const Map<String, Color> _couleursModuleDeLaVue = {
  'M1': AppColors.serviceHebergement,
  'M4': AppColors.serviceRestauration,
  'M5': AppColors.serviceBar,
  'M9': AppColors.serviceTourisme,
  'M8': AppColors.serviceVehicule,
  'M2': AppColors.gris,
  'M10': AppColors.erreur,
};

/// `COULEUR_PAR_DEFAUT` de la vue (`#64748B`, l.1820) — l'ardoise 500.
const Color _couleurParDefautDeLaVue = AppColors.neutre500;

/// Le `<h2 class="text-sm font-bold text-slate-700">` des cartes de la ligne.
TextStyle _styleTitre() => styleExploitation(
  TaillesContenu.sm,
  poids: FontWeight.w700,
  interligne: TaillesContenu.interligneSm,
  couleur: AppColors.neutre700,
);

/// `text-[13px] text-slate-400` — le sous-titre d'une carte.
TextStyle _styleSousTitre() =>
    styleExploitation(TaillesContenu.t13, couleur: AppColors.neutre400);

/// `text-[12px] text-slate-400` — la ligne qui nomme la mesure réelle.
TextStyle _styleMesure() =>
    styleExploitation(TaillesContenu.t12, couleur: AppColors.neutre400);

/// `text-[13px] text-slate-500` — l'état vide (ou la raison d'une absence).
TextStyle _styleEtat() =>
    styleExploitation(TaillesContenu.t13, couleur: AppColors.neutre500);

/// La carte **« Chiffre d'affaires vs Dépenses »** (l.625-663) — barres
/// groupées, l'encaissé en navy et les dépenses en rouge (`#14213D`,
/// `#C62828`, script de la vue l.1886-1898), sur `height:280px`.
///
/// Les trois boutons « 3 mois / 6 mois / 1 an » (`px-2.5 py-1 rounded
/// text-[12px] font-semibold`, l'actif en navy) ne s'offrent QUE si la série
/// existe : sans elle, ils ne commanderaient rien (Article 3.3). Aujourd'hui la
/// série n'existe pas sur ce poste — la courbe des dépenses lit la classe 6
/// complète — et la carte dit pourquoi ([SeriesTableauDeBord.raisonMensuelle]),
/// à la place du canevas : jamais une série inventée.
class GraphiqueCaDepenses extends StatelessWidget {
  const GraphiqueCaDepenses({
    required this.series,
    required this.mois,
    required this.onMois,
    super.key,
  });

  /// `null` : la lecture a ÉCHOUÉ — la carte écrit la phrase de la vue
  /// ([lectureImpossible]) et ne pose aucun canevas (l.660-661).
  final SeriesTableauDeBord? series;

  /// L'étendue affichée — 3, 6 ou 12 mois, les trois boutons de la vue.
  final int mois;
  final ValueChanged<int> onMois;

  @override
  Widget build(BuildContext context) {
    final series =
        this.series ??
        const SeriesTableauDeBord(mensuelle: [], ventilation: []);
    final maximum = series.maximumMensuel;
    final raison = this.series == null
        ? lectureImpossible
        : series.raisonMensuelle;
    final etiquette = styleExploitation(
      TaillesContenu.t11,
      couleur: AppColors.gris,
    );

    return Container(
      key: const Key('tdb-carte-ca'),
      padding: const EdgeInsets.all(AppSpacing.mdPlus), // p-5
      decoration: carteAccueil(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // `flex items-center justify-between mb-1 flex-wrap gap-2`.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              Text("Chiffre d'affaires vs Dépenses", style: _styleTitre()),
              if (raison == null)
                Wrap(
                  spacing: AppSpacing.unit, // gap-1
                  children: [
                    for (final (valeur, libelle) in const [
                      (3, '3 mois'),
                      (6, '6 mois'),
                      (12, '1 an'),
                    ])
                      _BoutonEtendue(
                        cle: Key('tdb-mois-$valeur'),
                        libelle: libelle,
                        actif: mois == valeur,
                        onChoix: () => onMois(valeur),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.unit), // mb-1
          Text(
            'Basé sur les encaissements et dépenses enregistrés',
            style: _styleSousTitre(),
          ),
          const SizedBox(height: AppSpacing.md), // mb-4
          if (raison != null)
            // « Non calculable » et « aucun mouvement » ne se disent pas
            // pareil : le second rassure, le premier est vrai.
            Text(
              raison,
              key: const Key('tdb-ca-indisponible'),
              style: _styleEtat(),
            )
          else if (series.mensuelle.isEmpty)
            Text(
              'Aucun mouvement sur les mois demandés.',
              key: const Key('tdb-ca-vide'),
              style: _styleEtat(),
            )
          else ...[
            SizedBox(
              height: MesuresAccueil.hauteurGraphiqueCa,
              child: BarChart(
                BarChartData(
                  // L'axe part de ZÉRO, toujours. Un axe tronqué fait
                  // paraître énorme un écart de quelques pour cent.
                  minY: 0,
                  maxY: maximum == 0
                      ? 1
                      : maximum * MesuresAccueil.margeHautAxeCa,
                  barGroups: [
                    for (final (index, point) in series.mensuelle.indexed)
                      BarChartGroupData(
                        x: index,
                        barRods: [
                          BarChartRodData(
                            toY: double.tryParse(point.chiffreAffaires) ?? 0,
                            color: AppColors.navy,
                            width: AppSpacing.xsPlus,
                            borderRadius: BorderRadius.circular(
                              AppRadius.rounded,
                            ),
                          ),
                          BarChartRodData(
                            toY: double.tryParse(point.depenses) ?? 0,
                            color: AppColors.erreur,
                            width: AppSpacing.xsPlus,
                            borderRadius: BorderRadius.circular(
                              AppRadius.rounded,
                            ),
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
                        reservedSize: AppSpacing.xlPlus,
                        // `(v / 1000) + 'k'` — l'axe de la vue.
                        getTitlesWidget: (valeur, meta) => Text(
                          '${(valeur / 1000).round()}k',
                          style: etiquette,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: AppSpacing.lgPlus,
                        getTitlesWidget: (valeur, meta) {
                          final index = valeur.toInt();
                          if (index < 0 || index >= series.mensuelle.length) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            series.mensuelle[index].libelleCourt,
                            style: etiquette,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            // `legend: { position: 'bottom' }` — les libellés de série de la
            // vue (`serie.col_ca`, `serie.col_depenses`).
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.md,
              children: const [
                _Pastille(
                  couleur: AppColors.navy,
                  libelle: "Chiffre d'affaires encaissé",
                ),
                _Pastille(couleur: AppColors.erreur, libelle: 'Dépenses'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// La carte **« Réservations par activité »** (l.677-701) — l'anneau.
///
/// Le titre et le sous-titre sont ceux de la vue ; la troisième ligne, ajoutée
/// par la vue elle-même, nomme la mesure réelle : des MONTANTS facturés par
/// activité (`lignes_facture.source_module`, RG-04), pas un compte de
/// réservations (PA-49, PA-121). L'ancien titre de cet écran, « Répartition
/// par activité », est retiré : la vue a gardé celui du maître et ajouté la
/// ligne qui dit la vérité.
class GraphiqueRepartition extends StatelessWidget {
  const GraphiqueRepartition({required this.parts, super.key});

  /// `null` : la lecture a ÉCHOUÉ ([lectureImpossible], l.698-699).
  final List<PartActivite>? parts;

  @override
  Widget build(BuildContext context) {
    final lues = this.parts;
    final parts = lues ?? const <PartActivite>[];
    final total = parts.fold<double>(
      0,
      (somme, p) => somme + (double.tryParse(p.montant) ?? 0),
    );

    return Container(
      key: const Key('tdb-carte-repartition'),
      padding: const EdgeInsets.all(AppSpacing.mdPlus), // p-5
      decoration: carteAccueil(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Réservations par activité', style: _styleTitre()),
          Text('Sur la période sélectionnée', style: _styleSousTitre()),
          const SizedBox(height: AppSpacing.xs), // mb-2
          Text(
            'Ventilation des montants facturés par activité.',
            style: _styleMesure(),
          ),
          const SizedBox(height: AppSpacing.xs), // mb-2
          if (lues == null)
            Text(
              lectureImpossible,
              key: const Key('tdb-repartition-illisible'),
              style: _styleEtat(),
            )
          else if (parts.isEmpty)
            Text(
              'Aucune ligne facturée sur la période.',
              key: const Key('tdb-repartition-vide'),
              style: _styleEtat(),
            )
          else ...[
            // Un total nul (une facture et son avoir) ne se dessine pas :
            // `fl_chart` rendrait un disque qu'on prendrait pour une part
            // unique. La légende reste — les activités existent.
            if (total != 0)
              SizedBox(
                height: MesuresAccueil.hauteurGraphiqueActivites,
                child: PieChart(
                  PieChartData(
                    centerSpaceRadius: AppSpacing.xlPlus,
                    sectionsSpace: AppSpacing.demi,
                    sections: [
                      for (final part in parts)
                        PieChartSectionData(
                          value: double.tryParse(part.montant) ?? 0,
                          color: couleurActivite(part.module),
                          radius: AppSpacing.xlPlus,
                          showTitle: false,
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            // `legend: { position: 'bottom' }` : le NOM de chaque activité.
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.unit,
              children: [
                for (final part in parts)
                  _Pastille(
                    cle: Key('tdb-part-${part.module}'),
                    couleur: couleurActivite(part.module),
                    libelle: part.libelle,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// La carte **« 📊 Statistiques de ventes par activité »** (l.708-722) —
/// barres horizontales (`indexAxis: 'y'`), même mesure et même source que
/// l'anneau : deux TRACÉS d'une seule mesure (PA-121).
///
/// ÉCART — le canevas de la vue n'écrit les montants qu'au survol (infobulle
/// Chart.js) ; ce poste n'a pas d'infobulle de graphique et les écrit en bout
/// de barre, pour que le chiffre reste lisible.
class GraphiqueActivites extends StatelessWidget {
  const GraphiqueActivites({required this.parts, super.key});

  /// `null` : la lecture a ÉCHOUÉ ([lectureImpossible], l.719-720).
  final List<PartActivite>? parts;

  @override
  Widget build(BuildContext context) {
    final lues = this.parts;
    final parts = lues ?? const <PartActivite>[];
    final etiquette = styleExploitation(
      TaillesContenu.t12,
      couleur: AppColors.neutre700,
    );
    final maximum = parts.fold<double>(0, (m, p) {
      final v = double.tryParse(p.montant) ?? 0;
      return v > m ? v : m;
    });

    return Container(
      key: const Key('tdb-carte-ventes-activite'),
      padding: const EdgeInsets.all(AppSpacing.mdPlus), // p-5
      decoration: carteAccueil(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('📊 Statistiques de ventes par activité', style: _styleTitre()),
          const SizedBox(height: AppSpacing.unit), // mb-1
          Text(
            'Nombre de réservations incluant chaque service, période '
            'sélectionnée',
            style: _styleSousTitre(),
          ),
          const SizedBox(height: AppSpacing.unit), // mb-1
          Text(
            // Une seule chaîne : le comparateur ne recolle pas deux littéraux
            // de guillemets différents.
            "Montants facturés par activité, même mesure que l'anneau ci-dessus.",
            style: _styleMesure(),
          ),
          const SizedBox(height: AppSpacing.md), // mb-4
          if (lues == null)
            Text(
              lectureImpossible,
              key: const Key('tdb-activites-illisible'),
              style: _styleEtat(),
            )
          else if (parts.isEmpty)
            Text(
              'Aucune ligne facturée sur la période.',
              key: const Key('tdb-activites-vide'),
              style: _styleEtat(),
            )
          else
            for (final part in parts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.unit),
                child: Row(
                  children: [
                    SizedBox(
                      width: MesuresAccueil.colonneLibelleActivite,
                      child: Text(
                        part.libelle,
                        overflow: TextOverflow.ellipsis,
                        style: etiquette,
                      ),
                    ),
                    Expanded(
                      child: _Barre(
                        valeur: double.tryParse(part.montant) ?? 0,
                        maximum: maximum,
                        couleur: couleurActivite(part.module),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    SizedBox(
                      width: MesuresAccueil.colonneMontantActivite,
                      child: Text(
                        formaterFcfa(
                          (double.tryParse(part.montant) ?? 0).round(),
                        ),
                        key: Key('tdb-montant-${part.module}'),
                        textAlign: TextAlign.right,
                        style: etiquette,
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

/// Une barre horizontale proportionnelle (`borderRadius: 6` de la vue).
class _Barre extends StatelessWidget {
  const _Barre({
    required this.valeur,
    required this.maximum,
    required this.couleur,
  });

  final double valeur;
  final double maximum;
  final Color couleur;

  @override
  Widget build(BuildContext context) {
    // Division par zéro impossible : un maximum nul rend une barre vide, pas
    // un `NaN` de largeur.
    final part = maximum <= 0 ? 0.0 : (valeur / maximum).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, contraintes) => Stack(
        children: [
          Container(
            height: AppSpacing.smPlus,
            decoration: BoxDecoration(
              color: AppColors.neutre100,
              borderRadius: BorderRadius.circular(AppRadius.roundedMd),
            ),
          ),
          Container(
            height: AppSpacing.smPlus,
            width: contraintes.maxWidth * part,
            decoration: BoxDecoration(
              color: couleur,
              borderRadius: BorderRadius.circular(AppRadius.roundedMd),
            ),
          ),
        ],
      ),
    );
  }
}

/// `px-2.5 py-1 rounded text-[12px] font-semibold` ; actif `bg-[var(--navy)]
/// text-white`, inactif `border border-slate-200 text-slate-500`.
class _BoutonEtendue extends StatelessWidget {
  const _BoutonEtendue({
    required Key cle,
    required this.libelle,
    required this.actif,
    required this.onChoix,
  }) : super(key: cle);

  final String libelle;
  final bool actif;
  final VoidCallback onChoix;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChoix,
      borderRadius: BorderRadius.circular(AppRadius.rounded),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xsPlus, // px-2.5
          vertical: AppSpacing.unit, // py-1
        ),
        decoration: BoxDecoration(
          color: actif ? AppColors.navy : null,
          border: actif ? null : Border.all(color: AppColors.neutre200),
          borderRadius: BorderRadius.circular(AppRadius.rounded),
        ),
        child: Text(
          libelle,
          style: styleExploitation(
            TaillesContenu.t12,
            poids: FontWeight.w600,
            couleur: actif ? AppColors.neutre0 : AppColors.neutre500,
          ),
        ),
      ),
    );
  }
}

/// Une entrée de légende — `boxWidth: 10` de la vue.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.couleur, required this.libelle, Key? cle})
    : super(key: cle);

  final Color couleur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: AppSpacing.xsPlus,
          height: AppSpacing.xsPlus,
          color: couleur,
        ),
        const SizedBox(width: AppSpacing.unit),
        Text(
          libelle,
          style: styleExploitation(TaillesContenu.t11, couleur: AppColors.gris),
        ),
      ],
    );
  }
}
