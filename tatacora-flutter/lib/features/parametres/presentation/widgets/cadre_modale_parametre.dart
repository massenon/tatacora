import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';

/// Le CADRE de la fenêtre « Modifier » de Paramètres : titre, champ, actions.
///
/// Fenêtre COMPACTE (PO, 14/10/2026) : l'`AlertDialog` d'avant sortait trop
/// haute (« Raison sociale ») ; un `Dialog` borné, à la hauteur de son
/// contenu, la remplace.
///
/// Fichier à part (15/10/2026) : c'est une MODALE, hors du contenu de page,
/// donc sur l'échelle typographique DÉCLARÉE (`Tailles`) ; l'écran, lui, est
/// dans le contenu de page (`TaillesContenu`). La frontière de la vue reste
/// une frontière de fichiers (`echelle_contenu_test.dart`).
class CadreModaleParametre extends StatelessWidget {
  const CadreModaleParametre({
    super.key,
    required this.titre,
    required this.champ,
    required this.actions,
  });

  final String titre;

  /// Le champ de la clé modifiée, défilant si la fenêtre est trop basse.
  final Widget champ;

  /// Les boutons, alignés à droite.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: AppColors.neutre0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.roundedXl),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: AppLayout.modaleParametre,
        maxHeight: AppLayout.hauteurMaxModaleParametre,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titre,
              style: const TextStyle(
                fontFamily: AppTextStyles.police,
                fontSize: Tailles.t16,
                fontWeight: FontWeight.bold,
                color: Ardoise.c800,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(child: SingleChildScrollView(child: champ)),
            const SizedBox(height: AppSpacing.mdPlus),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: actions,
            ),
          ],
        ),
      ),
    ),
  );
}
