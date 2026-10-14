import 'package:flutter/material.dart';

export '../../../../core/format/formats.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/reservation.dart';

/// État de synchronisation, rendu visible sur chaque ligne.
///
/// ## Pourquoi ce badge n'est pas un détail technique
///
/// Un réceptionniste qui ignore qu'une saisie n'est pas partie la ressaisira,
/// et le doublon apparaîtra ailleurs — souvent au moment de facturer. Le
/// statut de synchronisation est donc une information de **premier plan**, au
/// même titre que le nom du client.
///
/// ## Le vocabulaire est celui de l'utilisateur, pas celui du protocole
///
/// « En attente d'envoi » plutôt que `local`, « Refusée » plutôt que `rejete`.
/// Le code technique reste dans l'entité ; l'écran dit ce que la personne doit
/// comprendre pour agir.
class BadgeSynchronisation extends StatelessWidget {
  const BadgeSynchronisation({required this.statut, super.key});

  final StatutSynchronisation statut;

  @override
  Widget build(BuildContext context) {
    final (libelle, fond, texte, icone) = switch (statut) {
      StatutSynchronisation.local => (
        'En attente d’envoi',
        AppColors.reserveGoldFond,
        AppColors.reserveGoldTexte,
        Icons.schedule,
      ),
      StatutSynchronisation.enAttente => (
        'Envoi en cours',
        AppColors.infoBleuFond,
        AppColors.infoBleuTexte,
        Icons.sync,
      ),
      StatutSynchronisation.synchronise => (
        'Synchronisée',
        AppColors.succesFond,
        AppColors.succes,
        Icons.cloud_done_outlined,
      ),
      // Le rouge est réservé à ce cas : c'est le seul qui demande une action.
      StatutSynchronisation.rejete => (
        'Refusée par le serveur',
        AppColors.erreurFond,
        AppColors.erreur,
        Icons.error_outline,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.unit,
      ),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 13, color: texte),
          const SizedBox(width: AppSpacing.unit),
          Text(
            libelle,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: texte,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
