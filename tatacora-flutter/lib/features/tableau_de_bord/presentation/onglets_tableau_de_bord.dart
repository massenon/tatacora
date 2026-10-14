// Vue Blade maîtresse (PA-183) : pwa/livewire/accueil.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';

/// Les trois profondeurs de lecture du module M11 — `tableau-de-bord.html`
/// l.36-38.
///
/// Le maître les explique lui-même (l.32-34) : « Fusion des deux anciens
/// écrans M11. Deux entrées de menu pointant sur le même module laissaient
/// croire à deux lectures différentes de la même exploitation ; ce sont deux
/// profondeurs de la même. » Le deuxième onglet est l'ancien
/// `m11-pilotage.html`, que le maître a retiré du menu (« Page conservée pour
/// compatibilité »).
enum OngletTableauDeBord {
  exploitation("Vue d'exploitation"),
  pilotage('Pilotage consolidé'),
  croise('Tableau croisé dynamique');

  const OngletTableauDeBord(this.libelle);

  final String libelle;

  /// L'onglet a-t-il un contenu livré ? Les TROIS, depuis le 13/10/2026.
  ///
  /// « Tableau croisé dynamique » était inerte : son motif (« aucune route
  /// serveur n'expose d'axes ni de mesures », « sa source Dépenses n'a aucune
  /// table ») était PÉRIMÉ — le serveur croise ses trois registres dans le
  /// composant de la vue (`Accueil::croiser`), et le poste détient ventes,
  /// dépenses et réservations. Il est porté (`ecran_tableau_croise.dart`,
  /// INSTRUCTION1.txt du PO). Le getter reste : un onglet ajouté demain devra
  /// dire s'il est livré, jamais l'être par omission.
  bool get estLivre => switch (this) {
    OngletTableauDeBord.exploitation ||
    OngletTableauDeBord.pilotage ||
    OngletTableauDeBord.croise => true,
  };
}

/// L'onglet affiché. L'actif par défaut est celui du maître : « Vue
/// d'exploitation » (l.36, seul bouton peint en navy au chargement).
final ongletTableauDeBordProvider =
    NotifierProvider<_OngletNotifier, OngletTableauDeBord>(_OngletNotifier.new);

final class _OngletNotifier extends Notifier<OngletTableauDeBord> {
  @override
  OngletTableauDeBord build() => OngletTableauDeBord.exploitation;

  void choisir(OngletTableauDeBord onglet) {
    if (onglet.estLivre) state = onglet;
  }
}

/// La barre d'onglets du maître — trois pilules, l'active en navy.
class BarreOngletsTableauDeBord extends ConsumerWidget {
  const BarreOngletsTableauDeBord({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actif = ref.watch(ongletTableauDeBordProvider);

    return Wrap(
      spacing: AppSpacing.xs, // gap-2
      children: [
        for (final onglet in OngletTableauDeBord.values)
          _Pilule(
            cle: Key('tdb-onglet-${onglet.name}'),
            onglet: onglet,
            actif: onglet == actif,
            onChoix: onglet.estLivre
                ? () => ref
                      .read(ongletTableauDeBordProvider.notifier)
                      .choisir(onglet)
                : null,
          ),
      ],
    );
  }
}

class _Pilule extends StatelessWidget {
  const _Pilule({
    required Key cle,
    required this.onglet,
    required this.actif,
    required this.onChoix,
  }) : super(key: cle);

  final OngletTableauDeBord onglet;
  final bool actif;
  final VoidCallback? onChoix;

  @override
  Widget build(BuildContext context) {
    final inerte = onChoix == null;

    // `rounded-lg` = 8 px ([AppRadius.roundedLg]). ⚠ Jusqu'au 12/10/2026 la
    // pilule portait `AppRadius.lg`, qui vaut 12 (`rounded-xl`) malgré son nom
    // (alias historique, `app_radius.dart`).
    final pilule = InkWell(
      onTap: onChoix,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Opacity(
        // L'entrée inerte se VOIT inerte — l'Article 3.3 la garde visible et
        // au backlog, pas déguisée en bouton qui marche.
        opacity: inerte ? AppColors.opaciteDesactive : 1,
        child: Container(
          // px-3.5 py-2 du maître.
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.smPlus, // px-3.5 = 14
            vertical: AppSpacing.xs, // py-2 = 8
          ),
          decoration: BoxDecoration(
            color: actif ? AppColors.navy : AppColors.neutre0,
            border: actif ? null : Border.all(color: AppColors.neutre200),
            borderRadius: BorderRadius.circular(AppRadius.roundedLg),
            // `shadow-sm` de l'onglet actif (`Onglets::ACTIF`).
            boxShadow: actif ? AppShadows.tailwindSm : null,
          ),
          child: Text(
            onglet.libelle,
            style: TextStyle(
              fontFamily: AppTextStyles.police,
              fontSize: TaillesContenu.t13, // text-[13px]
              fontWeight: FontWeight.w600, // font-semibold
              height: AppLayout.interligneContenu,
              letterSpacing: 0,
              color: actif ? AppColors.neutre0 : AppColors.neutre500,
            ),
          ),
        ),
      ),
    );

    if (!inerte) return pilule;
    return Tooltip(
      // Aucun onglet n'est inerte depuis le 13/10/2026 ; la branche reste pour
      // un onglet ajouté demain, et ne nomme aucune raison qui vieillirait.
      message: 'Pas encore livré sur ce poste.',
      child: pilule,
    );
  }
}
