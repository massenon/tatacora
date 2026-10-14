// Vue Blade maîtresse (PA-183) : pwa/tourisme/departs.blade.php
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/formats.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../restaurant/presentation/widgets/coquille_restaurant.dart';
import '../../../restaurant/presentation/widgets/tableau_restaurant.dart';
import '../../domain/entities/reservation_tour.dart';
import '../providers_tourisme.dart';
import 'coquille_tourisme.dart';
import 'modale_annulation.dart';

/// L'onglet **« Réservations »** — vue l.408-529.
///
/// ## Le montant est CALCULÉ, il n'est ni stocké ni saisi
///
/// `ReservationTour::montant()` multiplie le prix du circuit par le nombre de
/// participants. Règle du dépôt : toute valeur calculable s'affiche en lecture
/// seule, jamais dans un champ.
///
/// ## « Acompte » et « Reste dû » n'ont aucune source, et c'est structurant
///
/// `reservations_tour` ne porte aucune colonne d'acompte, ni ici ni au
/// serveur. Les deux colonnes gardent leur place et portent « — ». C'est aussi
/// la raison pour laquelle l'indicateur « Reste à encaisser » de la bande du
/// haut n'affiche aucun chiffre : afficher le montant entier le présenterait
/// comme impayé.
class VueReservations extends ConsumerWidget {
  const VueReservations({super.key});

  /// Les colonnes de la vue (l.419-428), dans son ordre.
  ///
  /// ⚠ « Pers. » est ABRÉGÉ à l'écran, et écrit « Personnes » en toutes
  /// lettres dans le document d'export de la vue. Les deux libellés coexistent
  /// chez le maître : les aligner serait harmoniser une distinction voulue.
  static const colonnes = [
    ColonneRestaurant('N°'),
    ColonneRestaurant('Client'),
    ColonneRestaurant('Circuit'),
    ColonneRestaurant('Départ', aDroite: true),
    ColonneRestaurant('Pers.', aDroite: true),
    ColonneRestaurant('Prix / pers.', aDroite: true),
    ColonneRestaurant('Montant', aDroite: true),
    ColonneRestaurant('Acompte', aDroite: true),
    ColonneRestaurant('Reste dû', aDroite: true),
    ColonneRestaurant('', aDroite: true),
  ];

  static const String _raisonAcompte =
      'Aucun acompte n\'est enregistré sur une réservation de circuit. '
      '« 0 FCFA » se lirait « rien versé », et le montant entier '
      'se lirait « tout est dû » : les deux affirmeraient un encaissement que '
      'personne n\'a vérifié.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reservations = ref.watch(reservationsAfficheesProvider);

    return reservations.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => NoteRestaurant(
        cle: const Key('tourisme-reservations-erreur'),
        texte: '$e',
        icone: Icons.error_outline,
      ),
      data: (liste) => liste.isEmpty
          ? const EtatVideTourisme(
              cle: Key('tourisme-reservations-vide'),
              // Le message de la vue (l.409), au mot.
              message: 'Aucune réservation ne correspond.',
            )
          : _Corps(reservations: liste),
    );
  }
}

class _Corps extends StatelessWidget {
  const _Corps({required this.reservations});

  final List<ReservationTour> reservations;

  @override
  Widget build(BuildContext context) {
    // Les totaux de la vue EXCLUENT les lignes annulées (l.436-439) : une
    // réservation annulée ne compte ni en personnes, ni en argent.
    final actives = reservations.where((r) => !r.estAnnulee);
    final personnes = actives.fold<int>(0, (s, r) => s + r.nbParticipants);
    final montant = actives.fold<int>(0, (s, r) => s + r.montant);

    return CadreTableauRestaurant(
      // Le titre du cadre à la vue (l.413).
      titre: 'Réservations',
      corps: TableauRestaurant(
        gabarit: gabaritTourisme,
        colonnes: VueReservations.colonnes,
        clesLignes: [
          for (final r in reservations) Key('tourisme-resa-${r.id}'),
        ],
        lignes: [for (final r in reservations) _ligne(context, r)],
        ligneTotal: _ligneTotal(personnes, montant),
        decorationTotal: decorationTotalTourisme,
      ),
    );
  }

  List<Widget> _ligne(BuildContext context, ReservationTour r) {
    return [
      const CelluleAbsenteTourisme(
        raison: 'Une réservation de circuit n\'a pas de numéro sur ce poste.',
      ),
      _CelluleClient(reservation: r),
      Text(r.circuitNom, style: TextesRestaurant.corps),
      Text(formaterDate(r.dateCircuit), style: TextesRestaurant.corps),
      Text(r.nbParticipants.toString(), style: TextesRestaurant.corpsFort),
      Text(formaterFcfa(r.prixUnitaire), style: TextesRestaurant.corps),
      Text(
        formaterFcfa(r.montant),
        style: TextesRestaurant.corpsFort.copyWith(color: AppColors.navy),
      ),
      const CelluleAbsenteTourisme(raison: VueReservations._raisonAcompte),
      const CelluleAbsenteTourisme(raison: VueReservations._raisonAcompte),
      _ActionAnnuler(reservation: r),
    ];
  }

  /// La ligne TOTAL — vue l.465-473.
  ///
  /// Même écart de rendu qu'à l'onglet Départs : `colspan` n'existe pas dans
  /// une `Table` Flutter, le libellé occupe donc la première cellule. Les deux
  /// colonnes sans montant portent « — », comme à la vue (l.470-471).
  List<Widget> _ligneTotal(int personnes, int montant) {
    Widget vide() => const SizedBox.shrink();
    Widget tiret() =>
        Text(CarteIndicateurRestaurant.absent, style: styleTotalTourisme);

    return [
      Text(
        // La vue écrit « TOTAL » seul sur cet onglet (l.466), sans décompte.
        'TOTAL',
        key: const Key('tourisme-reservations-total'),
        style: styleTotalTourisme,
      ),
      vide(),
      vide(),
      vide(),
      Text(
        personnes.toString(),
        key: const Key('tourisme-reservations-total-personnes'),
        style: styleTotalTourisme,
      ),
      vide(),
      Text(
        formaterFcfa(montant),
        key: const Key('tourisme-reservations-total-montant'),
        style: styleTotalTourisme,
      ),
      tiret(),
      tiret(),
      vide(),
    ];
  }
}

/// La cellule « Client » — nom, téléphone, et la mention d'annulation
/// (vue l.442-448).
class _CelluleClient extends StatelessWidget {
  const _CelluleClient({required this.reservation});

  final ReservationTour reservation;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(reservation.clientNom, style: TextesRestaurant.corpsFort),
        Text(
          reservation.clientTelephone ?? CarteIndicateurRestaurant.absent,
          style: TextesRestaurant.mention,
        ),
        if (reservation.estAnnulee)
          Text(
            // Le libellé de la vue (l.446) — SINGULIER : il qualifie UN objet,
            // là où le filtre « Annulés » désigne un ensemble.
            'Annulée',
            key: Key('tourisme-resa-annulee-${reservation.id}'),
            style: TextesRestaurant.mention.copyWith(
              color: PaletteMaitre.rouge600,
            ),
          ),
      ],
    );
  }
}

/// Le bouton « Annuler » d'une ligne — vue l.458-461.
///
/// Absent sur une réservation déjà annulée, comme à la vue. Aucune suppression
/// n'est offerte : une réservation ne se supprime pas (RG-02), elle s'annule —
/// et c'est l'annulation qui libère la place au départ.
class _ActionAnnuler extends ConsumerWidget {
  const _ActionAnnuler({required this.reservation});

  final ReservationTour reservation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (reservation.estAnnulee) return const SizedBox.shrink();

    // `@if ($peutEcrire && ! $estAnnulee)` de la vue (l.458).
    if (!ref.watch(peutEcrireTourismeProvider)) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerRight,
      child: ActionLigneTourisme(
        cle: Key('tourisme-annuler-resa-${reservation.id}'),
        libelle: 'Annuler',
        onPresse: () => ouvrirModaleAnnulationReservation(
          context,
          reservation: reservation,
        ),
      ),
    );
  }
}
