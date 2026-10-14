import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;
import '../../domain/entities/occupation_mensuelle.dart';
import '../providers_hebergement.dart';

/// L'onglet **« Calendrier d'Occupation »** — `hebergement.blade.php`
/// l.430-476.
///
/// Le calcul vit dans le domaine (`OccupationMensuelle`) et se teste aux
/// bornes : ce fichier ne fait que peindre. Sa structure est celle de la vue —
/// un cadre `p-5`, un en-tête (mois et légende), sept initiales, une grille de
/// sept colonnes en `gap-1.5` de cases carrées, puis la mention « estimé ».
class VueCalendrierOccupation extends ConsumerWidget {
  const VueCalendrierOccupation({super.key});

  /// Les initiales de la vue (l.443), lundi en tête.
  static const joursSemaine = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

  static const mois = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(reservationsProvider);
    final unites = ref.watch(unitesProvider);

    if (reservations.isLoading || unites.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (reservations.hasError) {
      return Center(child: Text('${reservations.error}'));
    }
    if (unites.hasError) return Center(child: Text('${unites.error}'));

    final maintenant = ref.watch(horlogeHebergementProvider)();
    final occupation = OccupationMensuelle.calculer(
      reference: maintenant,
      reservations: reservations.requireValue,
      totalUnites: unites.requireValue.length,
    );

    return Container(
      // `bg-white rounded-xl border border-slate-200 p-5` (l.432).
      padding: const EdgeInsets.all(AppSpacing.mdPlus),
      decoration: BoxDecoration(
        color: AppColors.neutre0,
        border: Border.all(color: Ardoise.c200),
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _enTete(occupation),
          // `mb-4` (l.433).
          const SizedBox(height: AppSpacing.md),
          _grille(occupation, maintenant),
          // `mt-3` (l.474).
          const SizedBox(height: AppSpacing.sm),
          Text(
            // La mention de la vue, portée telle quelle : « estimé ». Un taux
            // présenté comme exact serait lu comme un relevé de présence, et
            // servirait à décider d'une sur-réservation.
            "Taux d'occupation estimé par jour, calculé à partir des réservations "
            "d'hébergement enregistrées (${occupation.totalUnites} unités au total).",
            key: const Key('calendrier-mention'),
            style: styleContenuCarte(TaillesContenu.t13, couleur: Ardoise.c400),
          ),
        ],
      ),
    );
  }

  /// `flex items-center justify-between mb-4` (l.433-440) : le mois en
  /// `text-sm font-bold text-slate-700`, la légende en `text-[12px]
  /// text-slate-400 gap-3`.
  Widget _enTete(OccupationMensuelle occupation) {
    final legende = styleContenuCarte(
      TaillesContenu.t12,
      couleur: Ardoise.c400,
    );

    // `flex items-center justify-between` : sur une ligne, `Wrap` en
    // `spaceBetween` se comporte comme la vue ; trop étroit, la légende passe
    // dessous au lieu de déborder (INSTRUCTION2.txt du PO, 13/10/2026).
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          '${mois[occupation.mois.month - 1]} ${occupation.mois.year}',
          key: const Key('calendrier-mois'),
          style: styleContenuCarte(
            TaillesContenu.sm,
            poids: FontWeight.bold,
            couleur: Ardoise.c700,
          ),
        ),
        // La légende des trois paliers. Sans elle, la couleur d'une case ne
        // veut rien dire — et une couleur qu'on ne sait pas lire se devine,
        // souvent à l'envers.
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (palier, libelle)) in const [
              (PalierOccupation.faible, 'Faible'),
              (PalierOccupation.moyen, 'Moyen'),
              (PalierOccupation.fort, 'Fort'),
            ].indexed) ...[
              // `gap-3` — 12 px.
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // `w-2.5 h-2.5 rounded` — 10 px.
                  Container(
                    width: AppLayout.pastilleLegendeCalendrier,
                    height: AppLayout.pastilleLegendeCalendrier,
                    decoration: BoxDecoration(
                      color: _fond(palier),
                      borderRadius: BorderRadius.circular(AppRadius.rounded),
                    ),
                  ),
                  // `gap-1` — 4 px.
                  const SizedBox(width: AppSpacing.unit),
                  Text(libelle, style: legende),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// `grid grid-cols-7 gap-1.5` (l.442 et l.448) — `gap-1.5` : 6 px.
  Widget _grille(OccupationMensuelle occupation, DateTime maintenant) {
    return LayoutBuilder(
      builder: (context, contraintes) {
        const ecart = AppSpacing.xxs;
        // Sept colonnes, des cases carrées (`aspect-square`).
        final cote = (contraintes.maxWidth - ecart * 6) / 7;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                for (final (i, jour) in joursSemaine.indexed) ...[
                  if (i > 0) const SizedBox(width: ecart),
                  SizedBox(
                    width: cote,
                    child: Text(
                      jour,
                      textAlign: TextAlign.center,
                      style: styleContenuCarte(
                        TaillesContenu.t12,
                        poids: FontWeight.bold,
                        couleur: Ardoise.c400,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            // `mb-1.5`.
            const SizedBox(height: ecart),
            Wrap(
              spacing: ecart,
              runSpacing: ecart,
              children: [
                // Les cases vides du début : sans elles, le 1er du mois se
                // retrouve sous « Lun » quel que soit le jour réel, et la
                // grille entière ment d'un à six jours (l.449-455).
                for (var i = 0; i < occupation.decalagePremierJour; i++)
                  SizedBox(width: cote, height: cote),
                for (final jour in occupation.jours)
                  _Case(
                    jour: jour,
                    cote: cote,
                    aujourdHui:
                        jour.jour.year == maintenant.year &&
                        jour.jour.month == maintenant.month &&
                        jour.jour.day == maintenant.day,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Les fonds de la vue (l.461) : `#F9FAFB` pour un jour sans séjour, puis les
  /// trois teintes des badges.
  static Color _fond(PalierOccupation palier) => switch (palier) {
    PalierOccupation.vide => JetonsCssMaitre.neutre50,
    PalierOccupation.faible => AppColors.badgeVertFond,
    PalierOccupation.moyen => AppColors.reserveGoldFond,
    PalierOccupation.fort => AppColors.badgeRougeFond,
  };
}

/// Une case : `aspect-square rounded-lg border p-1.5 flex flex-col
/// justify-between` (l.463-468).
class _Case extends StatelessWidget {
  const _Case({
    required this.jour,
    required this.cote,
    required this.aujourdHui,
  });

  final JourOccupation jour;
  final double cote;
  final bool aujourdHui;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('jour-${jour.jour.day}'),
      width: cote,
      height: cote,
      // `p-1.5` — 6 px.
      padding: const EdgeInsets.all(AppSpacing.xxs),
      decoration: BoxDecoration(
        color: VueCalendrierOccupation._fond(jour.palier),
        border: Border.all(
          // Le jour courant porte une bordure épaisse à la couleur navy : sur
          // une grille de trente cases colorées, c'est le seul repère qui
          // permette de se situer sans compter (`border-2`).
          color: aujourdHui ? AppColors.navy : Ardoise.c100,
          width: aujourdHui ? AppSpacing.demi : AppLayout.bordureControle,
        ),
        borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${jour.jour.day}',
            style: styleContenuCarte(
              TaillesContenu.t13,
              poids: FontWeight.w600,
              couleur: aujourdHui ? AppColors.navy : Ardoise.c500,
            ),
          ),
          // Le compte ne s'affiche QUE s'il y a quelque chose à compter : un
          // « 0/6 » sur chaque case libre noierait les jours qui comptent.
          if (jour.estOccupe)
            Text(
              '${jour.unitesOccupees}/${jour.totalUnites}',
              key: Key('occupation-${jour.jour.day}'),
              style: styleContenuCarte(
                TaillesContenu.t9,
                couleur: Ardoise.c500,
              ).copyWith(fontFamily: AppTextStyles.policeMonospace),
            ),
        ],
      ),
    );
  }
}
