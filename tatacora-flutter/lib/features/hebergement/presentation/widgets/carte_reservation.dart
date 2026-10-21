// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/entities/carte_reservation.dart';
import '../../domain/entities/reservation.dart';
import '../../domain/entities/service_reservation.dart';
import '../fiche_reservation.dart';
import 'badge_synchronisation.dart';
import 'dialogue_detail_reservation.dart';
import 'vue_services.dart';

/// Une carte de la grille — la carte de `pwa/hebergement/reservations.blade.php`
/// (l.170-260).
///
/// ## Ce que la carte dit, dans l'ordre de la vue
///
///  1. le client, en gras, et ses actions ;
///  2. sous lui, la ligne d'identité : type de client, canal, dates, nuits ;
///  3. les **pastilles de service** — l'hébergement toujours en tête (la vue
///     l'ajoute d'office : `unite_id` est NOT NULL), puis les services que
///     portent les lignes ;
///  4. l'**unité** : « Unité : BNG-01 — Bungalow » ;
///  5. les montants : Séjour, Consommations, Acompte versé, Reste à payer.
///
/// ## Ce qui a été RETIRÉ le 11/09/2026 (PA-185), parce que la vue ne l'a pas
///
///  - le détail des lignes — quatre au plus, puis « + N autre(s) ligne(s) » :
///    la vue montre les services en pastilles et l'unité, jamais les lignes ;
///  - la mention « panier ouvert » et la ligne « Total ». Deux lignes de
///    montants, jamais un total unique (PA-112) : la règle tient toujours,
///    c'est la vue qui la porte désormais.
///
/// ## L'action « Supprimer » n'est PAS rendue, et c'est délibéré
///
/// Une réservation s'annule, elle ne s'efface pas : RG-02, et la convention
/// `Policy::delete() === false` sur ce dépôt — sans quoi on perdrait la trace
/// de ce qui a été promis à un client. **Voir le détail**, **Modifier** et
/// **Annuler** sont offertes, comme dans la vue.
///
/// ## Deux éléments AJOUTÉS à la vue, et ils doivent le rester
///
/// Le badge de synchronisation et le motif de refus du serveur ne figurent pas
/// dans la vue — qui ne connaît pas le hors-ligne. Ils sont ici parce qu'ils
/// répondent à la question que ce client pose et que la PWA ne pose pas : *ma
/// saisie est-elle partie ?* Sans le badge, un réceptionniste ressaisit une
/// réservation déjà en base et le doublon apparaît ailleurs (PA-63). Sans le
/// motif, il voit « refusée » sans jamais savoir pourquoi. Les retirer par
/// fidélité serait une régression fonctionnelle.
class VueCarteReservation extends ConsumerWidget {
  const VueCarteReservation({
    required this.carte,
    required this.peutAnnuler,
    required this.onAnnuler,
    this.onFacture,
    super.key,
  });

  final CarteReservation carte;
  final bool peutAnnuler;
  final VoidCallback onAnnuler;

  /// Ouvre la facture du séjour. `null` quand aucune facture n'existe.
  final VoidCallback? onFacture;

  Reservation get _r => carte.reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textes = Theme.of(context).textTheme;
    final annulee = _r.statut == StatutReservation.annulee;

    return Card(
      key: Key('carte-${_r.id}'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _entete(context, textes, annulee),
            const SizedBox(height: AppSpacing.xs),
            _pastilles(textes),
            const SizedBox(height: AppSpacing.xs),
            _unite(textes),
            _montants(textes),
            // Le motif de refus est le seul texte que le serveur écrit à
            // l'écran. Il est affiché tel quel, jamais résumé : c'est lui qui
            // dit quoi faire.
            if (_r.motifRejet != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Container(
                key: Key('motif-rejet-${_r.id}'),
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppColors.erreurFondLeger,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.erreurBordure),
                ),
                child: Text(
                  _r.motifRejet!,
                  style: textes.bodySmall?.copyWith(color: AppColors.erreur),
                ),
              ),
            ],

            if (_r.motifAnnulation != null) ...[
              const SizedBox(height: AppSpacing.unit),
              Text(
                'Annulée : ${_r.motifAnnulation}',
                style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
              ),
            ],
            if (peutAnnuler && !annulee)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: Key('annuler-${_r.id}'),
                  onPressed: onAnnuler,
                  icon: const Icon(Icons.cancel_outlined, size: 16),
                  label: const Text('Annuler'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _entete(BuildContext context, TextTheme textes, bool annulee) {
    // La ligne d'identité de la vue (l.182-185) : type de client, canal,
    // dates, puis « (:nombre nuit(s)) ». Le canal manquant s'écrit « — »,
    // jamais rien : une place vide se lit comme un oubli d'affichage, un
    // tiret comme une donnée absente.
    //
    // Le squelette de cette ligne, une fois ses valeurs retirées, est celui que
    // la vue pose entre ses accolades : « • • → ( ) » — deux puces, une flèche
    // entre les deux dates, la durée entre parenthèses. Il est dit ici, et
    // non rendu à part : la ligne ci-dessous le compose avec ses valeurs.
    final identite = [
      _r.typeClient?.libelle ?? '—',
      _r.canal?.libelle ?? '—',
      '${formaterDate(_r.periode.arrivee)} → ${formaterDate(_r.periode.depart)} '
          '(${_r.nuits} nuit(s))',
    ].join(' • ');

    // Modifier et annuler exigent le droit d'écriture sur M1, et jamais sur
    // une réservation annulée : elle a libéré son unité, et la réengager
    // passerait par-dessus une chambre peut-être revendue depuis.
    final modifiable = peutAnnuler && !annulee;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _r.clientNom,
                style: textes.titleMedium?.copyWith(
                  decoration: annulee ? TextDecoration.lineThrough : null,
                  color: annulee ? AppColors.neutre500 : null,
                ),
              ),
            ),
            // L'œil de la vue : il ouvre le détail, dont le pied reprend
            // « Annuler la réservation » et « Modifier » quand ils sont
            // permis.
            IconButton(
              key: Key('voir-${_r.id}'),
              tooltip: 'Voir le détail',
              visualDensity: VisualDensity.compact,
              onPressed: () => ouvrirDetailReservation(
                context,
                _r,
                uniteNumero: carte.unite?.numero,
                onModifier: modifiable
                    ? () =>
                          ouvrirFicheReservation(context, reservationId: _r.id)
                    : null,
                onAnnuler: modifiable ? onAnnuler : null,
              ),
              icon: const Icon(Icons.visibility_outlined, size: 16),
            ),
            if (modifiable)
              IconButton(
                key: Key('modifier-${_r.id}'),
                tooltip: 'Modifier',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    ouvrirFicheReservation(context, reservationId: _r.id),
                icon: const Icon(Icons.edit_outlined, size: 16),
              ),
            // Puis l'état vis-à-vis du serveur : l'information de premier plan
            // sur ce poste, que la vue ne connaît pas.
            BadgeSynchronisation(statut: _r.statutSynchronisation),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          identite,
          key: Key('identite-${_r.id}'),
          style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
        ),
      ],
    );
  }

  Widget _pastilles(TextTheme textes) {
    // L'hébergement d'abord, toujours — la vue fusionne `['hebergement']` et
    // les services des lignes (l.223). Un ensemble ORDONNÉ : un service porté
    // par plusieurs lignes n'a qu'une pastille.
    final services = <ServiceReservation>{
      ServiceReservation.hebergement,
      for (final l in _r.lignes) l.service,
    };

    return Wrap(
      spacing: AppSpacing.unit,
      runSpacing: AppSpacing.unit,
      children: [
        for (final s in services)
          Container(
            key: Key('pastille-${_r.id}-${s.cle}'),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.demi,
            ),
            decoration: BoxDecoration(
              // La vue pose le fond du service et le texte à sa couleur pleine.
              color: couleurService(s).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              s.nom,
              style: textes.labelSmall?.copyWith(color: couleurService(s)),
            ),
          ),
      ],
    );
  }

  /// « Unité : BNG-01 — Bungalow » — la vue, l.229-230.
  Widget _unite(TextTheme textes) {
    final unite = carte.unite;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre200)),
      ),
      child: Text(
        'Unité : ${unite?.numero ?? '—'} — ${unite?.categorieLibelle ?? '—'}',
        key: Key('unite-${_r.id}'),
        style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
      ),
    );
  }

  /// Les quatre lignes de montants de la vue (l.242-259).
  Widget _montants(TextTheme textes) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.neutre200)),
      ),
      child: Column(
        children: [
          _LigneMontant(
            cle: Key('sejour-${_r.id}'),
            libelle: 'Séjour',
            valeur: formaterFcfa(carte.sejour),
          ),
          // La vue écrit « — » : le serveur ne tient aucun panier. Ce poste,
          // lui, lit le panier OUVERT du séjour — un montant quand il existe,
          // le tiret sinon, jamais « 0 », qui se lirait comme un panier ouvert
          // et vide.
          _LigneMontant(
            cle: Key('consommations-${_r.id}'),
            libelle: 'Consommations',
            valeur: carte.aDesConsommations
                ? formaterFcfa(carte.consommations)
                : '—',
          ),
          _LigneMontant(
            cle: Key('acompte-${_r.id}'),
            libelle: 'Acompte versé',
            valeur: formaterFcfa(_r.acompte),
            couleurValeur: AppColors.succes,
          ),
          _LigneMontant(
            cle: Key('reste-${_r.id}'),
            libelle: 'Reste à payer',
            valeur: formaterFcfa(carte.reste),
            couleurValeur: AppColors.gold,
          ),

          // Le bouton n'existe QUE si la facture existe. Un téléchargement
          // qui ne pointe vers rien est pire qu'un bouton absent.
          if (carte.estFacturee)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                key: Key('facture-${_r.id}'),
                onPressed: onFacture,
                child: Text('Facture ${carte.factureNumero}'),
              ),
            ),
        ],
      ),
    );
  }
}

class _LigneMontant extends StatelessWidget {
  const _LigneMontant({
    required Key cle,
    required this.libelle,
    required this.valeur,
    this.couleurValeur,
  }) : super(key: cle);

  final String libelle;
  final String valeur;
  final Color? couleurValeur;

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.demi),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              libelle,
              style: textes.labelSmall?.copyWith(color: AppColors.neutre500),
            ),
          ),
          Text(
            valeur,
            style: AppTextStyles.montant.copyWith(color: couleurValeur),
          ),
        ],
      ),
    );
  }
}
