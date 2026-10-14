// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers_achats.dart';

/// Les deux bandeaux que la vue pose entre son en-tête et ses cartes
/// (`approvisionnement.blade.php` l.88-97) : le message de succès
/// (`session('pwa-succes')`, vert) et l'erreur `selection` (rouge) — celle que
/// l'ouverture de la modale « Régler » lève quand la commande n'existe pas ou
/// est déjà soldée.
///
/// Ils vivent dans la PAGE et non dans la modale : la vue les rend après la
/// fermeture de celle-ci, au-dessus des indicateurs. Le bandeau de la vue
/// disparaît à la requête suivante ; ici il disparaît au prochain geste (le
/// notifier est vidé à l'ouverture d'un règlement) et au changement d'onglet.
class BandeauxAppro extends ConsumerWidget {
  const BandeauxAppro({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bandeau = ref.watch(bandeauApproProvider);
    if (bandeau.succes == null && bandeau.erreurSelection == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bandeau.succes != null)
          _Bandeau(
            cle: const Key('appro-succes'),
            texte: bandeau.succes!,
            fond: AppColors.badgeVertFond,
            bordure: AppColors.succes,
            couleur: AppColors.succes,
            gras: true,
          ),
        if (bandeau.erreurSelection != null)
          _Bandeau(
            cle: const Key('appro-erreur-selection'),
            texte: bandeau.erreurSelection!,
            fond: AppColors.badgeRougeFond,
            bordure: AppColors.bordureRefusRouge,
            couleur: AppColors.erreur,
            gras: false,
          ),
      ],
    );
  }
}

/// `mb-4 rounded-xl px-4 py-3 text-[13px]` (l.89 et l.95).
class _Bandeau extends StatelessWidget {
  const _Bandeau({
    required this.cle,
    required this.texte,
    required this.fond,
    required this.bordure,
    required this.couleur,
    required this.gras,
  }) : super(key: cle);

  final Key cle;
  final String texte;
  final Color fond;
  final Color bordure;
  final Color couleur;
  final bool gras;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md), // mb-4
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md, // px-4
        vertical: AppSpacing.sm, // py-3
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.roundedXl),
        border: Border.all(color: bordure),
      ),
      child: Text(
        texte,
        style: TextStyle(
          fontFamily: AppTextStyles.police,
          fontSize: TaillesContenu.t13,
          fontWeight: gras ? FontWeight.w600 : null,
          height: AppLayout.interligneContenu,
          color: couleur,
        ),
      ),
    );
  }
}
