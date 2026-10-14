// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
/// Les deux confirmations d'annulation — vue l.845-860.
///
/// ## « Annuler » n'est PAS « supprimer », et la nuance est le livrable
///
/// Aucune suppression n'existe dans ce module : `annuler()` passe le statut à
/// `annulee`, ce qui libère aussitôt la place au départ puisque la capacité se
/// calcule sur les lignes actives. La ligne reste lisible — une réservation
/// effacée emporterait la trace de ce qui a été encaissé (RG-02, RG-15).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
// `app_spacing.dart` réexporte `app_radius.dart`.
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/textes_modale_restaurant.dart';
import '../../domain/departs.dart';
import '../../domain/entities/reservation_tour.dart';
import '../providers_tourisme.dart';

/// Annule UNE réservation.
Future<bool?> ouvrirModaleAnnulationReservation(
  BuildContext context, {
  required ReservationTour reservation,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleAnnulation(reservation: reservation),
);

/// Annule un DÉPART entier — toutes ses réservations actives.
Future<bool?> ouvrirModaleAnnulationDepart(
  BuildContext context, {
  required Depart depart,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: true,
  barrierColor: AppColors.voileModale,
  builder: (_) => _ModaleAnnulation(depart: depart),
);

class _ModaleAnnulation extends ConsumerStatefulWidget {
  const _ModaleAnnulation({this.reservation, this.depart});

  final ReservationTour? reservation;
  final Depart? depart;

  @override
  ConsumerState<_ModaleAnnulation> createState() => _ModaleAnnulationState();
}

class _ModaleAnnulationState extends ConsumerState<_ModaleAnnulation> {
  bool _envoi = false;
  String? _refus;

  bool get _estReservation => widget.reservation != null;

  /// Le libellé de l'élément — vue `tourisme.pwa.verrou_reservation` pour une
  /// réservation, « nom — date » pour un départ (l.487).
  String get _element {
    final r = widget.reservation;
    if (r != null) {
      return 'Réservation de ${r.clientNom} (${r.nbParticipants} pers.) '
          'le ${formaterDate(r.dateCircuit)}';
    }
    final d = widget.depart!;
    return '${d.circuitNom} — ${formaterDate(d.date)}';
  }

  /// Un départ SANS réservation active n'existe pas : il n'y a rien à annuler.
  ///
  /// C'est le verrou de la vue (l.490-491). Le bouton est alors désactivé
  /// plutôt que laissé actif pour échouer — mais le DAO refuse de toute façon,
  /// et c'est lui qui protège.
  bool get _bloque {
    final d = widget.depart;
    return d != null && (d.annule || d.placesVendues == 0);
  }

  @override
  Widget build(BuildContext context) {
    final places = widget.depart?.placesVendues ?? 0;

    return CoquilleModaleRestaurant(
      cle: const Key('tourisme-modale-annulation'),
      titre: _estReservation ? 'Annuler la réservation' : 'Annuler le départ',
      largeur: AppLayout.modaleReservationTourisme,
      refus: _refus,
      cleRefus: const Key('tourisme-modale-annulation-refus'),
      corps: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // Les deux messages de la vue (l.852-853), au mot.
            _estReservation
                ? 'Voulez-vous annuler la réservation $_element ?'
                : 'Voulez-vous annuler le départ $_element ?',
            key: const Key('tourisme-annulation-message'),
            style: TextesRestaurant.corps,
          ),
          if (_bloque) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xsPlus),
              decoration: BoxDecoration(
                color: PaletteMaitre.ambre50,
                border: Border.all(color: PaletteMaitre.ambre200),
                borderRadius: BorderRadius.circular(AppRadius.roundedLg),
              ),
              child: const Text(
                // Le message de la vue (`tourisme.pwa.depart_sans_reservation`).
                'Ce départ n\'a aucune réservation active : il n\'existe que '
                'par elles, il n\'y a donc rien à annuler ni à réaffecter.',
                key: Key('tourisme-annulation-bloquee'),
                style: TextesRestaurant.mention,
              ),
            ),
          ],
          if (!_estReservation && !_bloque && places > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              // L'avertissement rouge de la vue (l.855-858).
              padding: const EdgeInsets.all(AppSpacing.xsPlus),
              decoration: BoxDecoration(
                color: PaletteMaitre.rouge50,
                border: Border.all(color: PaletteMaitre.rouge200),
                borderRadius: BorderRadius.circular(AppRadius.roundedXl),
              ),
              child: Text(
                // Le message de la vue, au mot.
                '$places place(s) déjà vendue(s) : les réservations seront '
                'annulées. Les clients concernés devront être prévenus et '
                'remboursés.',
                key: const Key('tourisme-annulation-places-vendues'),
                style: TextesRestaurant.secondaire.copyWith(
                  color: PaletteMaitre.rouge700,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton(
          key: const Key('tourisme-annulation-retour'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler', style: TextesModaleRestaurant.bouton),
        ),
        FilledButton(
          key: const Key('tourisme-annulation-valider'),
          onPressed: _envoi || _bloque ? null : _executer,
          child: const Text('Confirmer', style: TextesModaleRestaurant.bouton),
        ),
      ],
    );
  }

  Future<void> _executer() async {
    setState(() {
      _envoi = true;
      _refus = null;
    });

    final dao = ref.read(tourismeDaoProvider);

    try {
      final String message;

      if (_estReservation) {
        await dao.annulerReservation(widget.reservation!.id);
        // Le message de la vue (`tourisme.pwa.reservation_annulee_faite`).
        message = 'Réservation annulée, places libérées.';
      } else {
        final nombre = await dao.annulerDepart(
          circuitId: widget.depart!.circuitId,
          date: widget.depart!.date,
        );
        // Le message de la vue (`tourisme.pwa.depart_annule_faite`).
        message =
            'Départ annulé — $nombre réservation(s) passée(s) en annulation.';
      }

      if (!mounted) return;

      rechargerTourisme(ref);
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('tourisme-annulation-faite'),
          content: Text(message),
        ),
      );
    } on RefusTourisme catch (e) {
      if (!mounted) return;
      setState(() {
        _envoi = false;
        _refus = e.message;
      });
    }
  }
}
