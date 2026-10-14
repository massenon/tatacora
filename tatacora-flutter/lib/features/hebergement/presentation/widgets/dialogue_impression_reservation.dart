import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';

/// Ce que l'utilisateur a répondu à la modale.
enum ChoixImpression {
  /// « Plus tard » — ou la modale fermée d'un clic dehors.
  plusTard,

  /// « Imprimer la facture ».
  imprimer,
}

/// La modale **« Réservation enregistrée »** — `reservations.html` l.192-210.
///
/// ## Les mots sont ceux du maître, y compris « facture »
///
/// Le bouton dit « Imprimer la facture », parce que c'est l'écran que le client
/// a validé des yeux et le mot qu'emploie le comptoir. **Le document imprimé,
/// lui, s'appelle « Confirmation de réservation »** — et l'écart est
/// délibéré : voir l'en-tête de `impression/confirmation_reservation.dart`. Un
/// papier titré « facture », sans numéro ni cachet fiscal, remis à un client,
/// serait un faux document fiscal.
///
/// ## Pourquoi une réponse plutôt qu'un appel direct
///
/// La modale ne sait pas imprimer et n'a aucune raison de le savoir : elle rend
/// [ChoixImpression] à son appelant. C'est ce qui la rend montable dans un test
/// sans greffon natif, et c'est ce qui garde **un seul endroit** où
/// l'impression est déclenchée.
Future<ChoixImpression> demanderImpressionReservation(
  BuildContext context,
) async {
  final choix = await showDialog<ChoixImpression>(
    context: context,
    builder: (context) => const _DialogueImpressionReservation(),
  );
  // Fermée d'un clic dehors : c'est un « plus tard », jamais une impression.
  return choix ?? ChoixImpression.plusTard;
}

class _DialogueImpressionReservation extends StatelessWidget {
  const _DialogueImpressionReservation();

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return AlertDialog(
      key: const Key('modale-impression-facture'),
      // `max-width:420px` du maître.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // La pastille verte du maître : un disque de 56 px et une coche.
            // Elle dit que l'enregistrement a réussi AVANT qu'on lise la
            // question — sans elle, la modale ressemble à une demande de
            // confirmation, et l'utilisateur croit que rien n'est encore fait.
            Container(
              width: 56,
              height: 56,
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: const BoxDecoration(
                color: AppColors.succesFond,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: AppColors.succes, size: 26),
            ),
            Text(
              'Réservation enregistrée',
              style: textes.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Voulez-vous imprimer la facture de cette réservation ?',
              style: textes.bodySmall?.copyWith(color: AppColors.neutre500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(
          key: const Key('bouton-plus-tard'),
          onPressed: () => Navigator.of(context).pop(ChoixImpression.plusTard),
          child: const Text('Plus tard'),
        ),
        FilledButton.icon(
          key: const Key('bouton-imprimer-facture'),
          onPressed: () => Navigator.of(context).pop(ChoixImpression.imprimer),
          icon: const Icon(Icons.print_outlined, size: 15),
          label: const Text('Imprimer la facture'),
        ),
      ],
    );
  }
}
