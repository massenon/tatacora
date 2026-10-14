import 'package:flutter/material.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/historique_reservations.dart';
import '../../domain/entities/reservation.dart';

/// Ouvre la modale **Détail d'une réservation** —
/// `pwa/hebergement/reservations.blade.php` l.903-944.
///
/// ## Sept champs, ceux de la vue (PA-185, 11/09/2026)
///
/// Unité d'hébergement, Date d'arrivée, Date de départ, Nuits, Acompte versé
/// (FCFA), Statut enregistré, État du jour (dérivé des dates). Jusqu'au
/// 11/09/2026, cette modale portait ceux de l'ancien prototype — Client,
/// Période, Canal, Lignes réservées et un récapitulatif à quatre lignes — que
/// la vue n'a pas. Ils sont retirés : la carte porte déjà le client, le canal,
/// les services et les montants.
///
/// ## Les DEUX états, côte à côte
///
/// Le statut STOCKÉ ne vieillit pas ; l'état du jour se DÉDUIT des dates
/// (PA-111), par la même dérivation que l'historique
/// ([LigneHistorique.deriver]) — jamais une seconde. Les confondre ferait lire
/// « à venir » sur un séjour fini. Le statut s'affiche par son CODE, comme la
/// vue le fait (`{{ $detail->statut }}`).
///
/// ## Le pied : Annuler la réservation, Fermer, Modifier
///
/// Comme la vue. [onAnnuler] et [onModifier] ne sont passés qu'avec les droits
/// et jamais pour une réservation annulée : sans eux, leurs boutons
/// n'existent pas — un bouton qui n'ouvre rien empêche de savoir si la
/// fonction manque ou si l'écran est cassé.
Future<void> ouvrirDetailReservation(
  BuildContext context,
  Reservation reservation, {
  String? uniteNumero,
  VoidCallback? onModifier,
  VoidCallback? onAnnuler,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogueDetailReservation(
      reservation: reservation,
      uniteNumero: uniteNumero,
      onModifier: onModifier,
      onAnnuler: onAnnuler,
    ),
  );
}

class _DialogueDetailReservation extends StatelessWidget {
  const _DialogueDetailReservation({
    required this.reservation,
    this.uniteNumero,
    this.onModifier,
    this.onAnnuler,
  });

  final Reservation reservation;
  final String? uniteNumero;
  final VoidCallback? onModifier;
  final VoidCallback? onAnnuler;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;
    final r = reservation;
    final etat = LigneHistorique.deriver(r, maintenant: DateTime.now()).etat;
    final annuler = onAnnuler;
    final modifier = onModifier;

    return AlertDialog(
      key: const Key('modale-detail-reservation'),
      // La vue écrit « Détail — {client} » : le nom est dans le titre, pour
      // qu'on sache de qui on parle sans lire.
      title: Text(
        'Détail — ${r.clientNom}',
        key: const Key('titre-detail-reservation'),
        style: textes.titleMedium?.copyWith(color: AppColors.navy),
      ),
      content: SizedBox(
        // `largeur="480px"` de la vue.
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Champ(
                cle: 'unite',
                etiquette: 'Unité d\'hébergement',
                // Un numéro inconnu s'écrit « — » : le parc n'a pas descendu,
                // et un identifiant technique ne dirait rien au comptoir.
                valeur: uniteNumero ?? '—',
              ),
              _Champ(
                cle: 'arrivee',
                etiquette: 'Date d\'arrivée',
                valeur: formaterDate(r.periode.arrivee),
              ),
              _Champ(
                cle: 'depart',
                etiquette: 'Date de départ',
                valeur: formaterDate(r.periode.depart),
              ),
              _Champ(cle: 'nuits', etiquette: 'Nuits', valeur: '${r.nuits}'),
              _Champ(
                cle: 'acompte',
                etiquette: 'Acompte versé (FCFA)',
                valeur: formaterFcfa(r.acompte),
                montant: true,
              ),
              _Champ(
                cle: 'statut',
                etiquette: 'Statut enregistré',
                valeur: r.statut.code,
              ),
              _Champ(
                cle: 'etat',
                etiquette: 'État du jour (dérivé des dates)',
                valeur: etat.libelle,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (annuler != null)
          TextButton(
            key: const Key('annuler-detail-reservation'),
            style: TextButton.styleFrom(foregroundColor: AppColors.erreur),
            onPressed: () {
              Navigator.of(context).pop();
              annuler();
            },
            child: const Text('Annuler la réservation'),
          ),
        TextButton(
          key: const Key('fermer-detail-reservation'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
        if (modifier != null)
          FilledButton(
            key: const Key('modifier-detail-reservation'),
            onPressed: () {
              Navigator.of(context).pop();
              modifier();
            },
            child: const Text('Modifier'),
          ),
      ],
    );
  }
}

/// Une ligne `<dt>`/`<dd>` de la vue : l'étiquette à gauche, la valeur à
/// droite (`flex justify-between`).
class _Champ extends StatelessWidget {
  const _Champ({
    required this.cle,
    required this.etiquette,
    required this.valeur,
    this.montant = false,
  });

  final String cle;
  final String etiquette;
  final String valeur;
  final bool montant;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.demi),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              etiquette,
              style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            valeur,
            key: Key('detail-$cle'),
            style: montant
                ? AppTextStyles.montant.copyWith(color: AppColors.neutre700)
                : textes.labelMedium?.copyWith(color: AppColors.neutre700),
          ),
        ],
      ),
    );
  }
}
