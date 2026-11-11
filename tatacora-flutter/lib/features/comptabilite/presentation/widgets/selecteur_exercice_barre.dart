import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/mesures_fenetre.dart';
import '../../domain/entities/comptabilite.dart';
import '../exercice_consulte.dart';

/// Les mots du sélecteur — `lang/fr/pwa.php`, `coquille.exercice_*`, au
/// caractère près.
abstract final class TextesSelecteurExercice {
  static const String exercice = 'Exercice';
  static String statut(StatutExercice s) => switch (s) {
    StatutExercice.ouvert => 'ouvert',
    StatutExercice.enCloture => 'en clôture',
    StatutExercice.cloture => 'clôturé',
  };
  static String option(ExerciceComptable e) =>
      '${e.annee} — ${statut(e.statut)}';
  static String pastille(ExerciceComptable e) =>
      'Vous consultez ${e.annee} (${statut(e.statut)})';
  static String revenir(int annee) => 'Revenir à $annee';
}

/// Le SÉLECTEUR D'EXERCICE de la barre supérieure — `#selecteur-exercice` du
/// composant `SelecteurExercice` de la PWA (AJOUT du PO du 20/10/2026, R1/R3
/// de `docs/SPEC_SELECTEUR_EXERCICE.md`). Affiché seulement sur les écrans
/// qui le suivent ([routeSuitLExercice]), pour tout compte qui les ouvre.
class SelecteurExerciceBarre extends ConsumerWidget {
  const SelecteurExerciceBarre({
    required this.routeActive,
    this.reduit = false,
    super.key,
  });

  final String routeActive;

  /// Fenêtre étroite (repli par priorité de la barre, 09/11/2026) : sans
  /// libellé « Exercice » ni lien « Revenir » ; la pastille reste, et choisir
  /// l'exercice par défaut dans la liste revient à l'exercice courant.
  final bool reduit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!routeSuitLExercice(routeActive)) return const SizedBox.shrink();
    final exercices = ref.watch(exercicesDuPosteProvider).value ?? const [];
    if (exercices.isEmpty) return const SizedBox.shrink();
    final consulte = ref.watch(exerciceConsulteProvider);
    final defaut = exerciceParDefaut(exercices);
    final autre =
        consulte != null && defaut != null && consulte.id != defaut.id;
    final blanc = TextStyle(
      color: AppColors.neutre0,
      fontFamily: AppTextStyles.police,
      fontSize: Tailles.t12,
      fontWeight: FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm), // mr-3
      // Borné : la pastille et « Revenir » se coupent par une ellipse au lieu
      // de pousser la barre hors de la fenêtre (09/11/2026).
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(
            MesuresFenetre.largeurMinSelecteurExercice,
            MediaQuery.sizeOf(context).width *
                MesuresFenetre.fractionMaxSelecteurExercice,
          ),
        ),
        child: Row(
          key: const Key('selecteur-exercice'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!reduit) ...[
              Text(
                TextesSelecteurExercice.exercice,
                style: blanc.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.neutre0.withValues(
                    alpha: OpacitesCoquille.libelleExercice,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('choix-exercice'),
                value: consulte?.id,
                dropdownColor: AppColors.navy,
                style: blanc,
                iconEnabledColor: AppColors.neutre0,
                // Ouvert : relu, pour proposer un exercice descendu depuis.
                onTap: () => ref.invalidate(exercicesDuPosteProvider),
                items: [
                  for (final e in exercices)
                    DropdownMenuItem(
                      value: e.id,
                      child: Text(TextesSelecteurExercice.option(e)),
                    ),
                ],
                onChanged: (id) {
                  final choisi = id == defaut?.id ? null : id;
                  ref.read(exerciceChoisiProvider.notifier).choisir(choisi);
                },
              ),
            ),
            if (autre) ...[
              const SizedBox(width: AppSpacing.xs),
              // `Flexible` + ellipse : la barre ne déborde jamais (09/11/2026).
              Flexible(
                child: Container(
                  key: const Key('pastille-exercice'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.demi,
                  ),
                  decoration: BoxDecoration(
                    color: switch (consulte.statut) {
                      StatutExercice.enCloture => PaletteMaitre.ambre200,
                      StatutExercice.cloture => Ardoise.c200,
                      StatutExercice.ouvert => AppColors.neutre0.withValues(
                        alpha: OpacitesCoquille.bordureCaisse,
                      ),
                    },
                    borderRadius: BorderRadius.circular(AppRadius.roundedFull),
                  ),
                  child: Text(
                    TextesSelecteurExercice.pastille(consulte),
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: blanc.copyWith(
                      fontSize: Tailles.t11,
                      color: switch (consulte.statut) {
                        StatutExercice.enCloture => PaletteMaitre.ambre900,
                        StatutExercice.cloture => Ardoise.c700,
                        StatutExercice.ouvert => AppColors.neutre0,
                      },
                    ),
                  ),
                ),
              ),
              if (!reduit) ...[
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: InkWell(
                    key: const Key('revenir-exercice'),
                    onTap: () =>
                        ref.read(exerciceChoisiProvider.notifier).revenir(),
                    child: Text(
                      TextesSelecteurExercice.revenir(defaut.annee),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: blanc.copyWith(
                        fontSize: Tailles.t11,
                        color: AppColors.gold,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
