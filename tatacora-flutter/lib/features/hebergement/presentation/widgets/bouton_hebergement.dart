import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../restaurant/presentation/widgets/corps_carte_commun.dart'
    show styleContenuCarte;

/// Un bouton de la vue : `btn flex items-center justify-center gap-2 px-4
/// py-2.5 rounded-lg text-[15px] font-semibold` — plein navy SANS bordure
/// (l.100, l.192), ou blanc à bordure navy d'un pixel (l.110). La bordure
/// s'ajoute à la boîte : le bouton à contour fait donc 2 px de plus que le
/// plein, et la vue les centre sur la même ligne (`sm:items-center`).
class BoutonHebergement extends StatelessWidget {
  const BoutonHebergement({
    super.key,
    required this.cle,
    required this.libelle,
    required this.icone,
    required this.plein,
    required this.onPressed,
  });

  final Key cle;
  final String libelle;
  final IconData icone;
  final bool plein;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final texte = plein ? AppColors.neutre0 : AppColors.navy;

    return InkWell(
      key: cle,
      onTap: onPressed,
      borderRadius: BorderRadius.circular(AppRadius.roundedLg),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xsPlus,
        ),
        decoration: BoxDecoration(
          color: plein ? AppColors.navy : AppColors.neutre0,
          border: plein ? null : Border.all(color: AppColors.navy),
          borderRadius: BorderRadius.circular(AppRadius.roundedLg),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: AppLayout.iconeBoutonHebergement, color: texte),
            // `gap-2` — 8 px.
            const SizedBox(width: AppSpacing.xs),
            Text(
              libelle,
              style: styleContenuCarte(
                TaillesContenu.t15,
                poids: FontWeight.w600,
                couleur: texte,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
