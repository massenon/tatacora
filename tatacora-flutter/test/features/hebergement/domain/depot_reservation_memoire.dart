import 'package:tatacora_flutter/features/hebergement/domain/annulation_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/annulation_enregistree.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/disponibilite.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/repositories/reservation_repository.dart';

/// Double de test entièrement en mémoire.
///
/// Le jour 1 du sprint impose de tester le domaine **sans aucune source de
/// données**. Ce double n'est pas une commodité : il vérifie que le contrat
/// est satisfaisable sans Drift ni réseau. Un contrat qu'on ne peut honorer
/// qu'avec une base est un contrat qui a laissé fuir la persistance dans le
/// domaine.
///
/// Il implémente la règle de disponibilité **de la même façon que le fera
/// l'implémentation Drift** : c'est aussi une spécification exécutable de ce
/// que le jour 2 devra reproduire.
final class DepotReservationMemoire implements ReservationRepository {
  DepotReservationMemoire({
    List<UniteHebergement> unites = const [],
    List<Reservation> reservations = const [],
    DateTime? maintenant,
  }) : _unites = [...unites],
       _reservations = [...reservations],
       _maintenant = maintenant ?? DateTime(2026, 8, 1);

  final List<UniteHebergement> _unites;
  final List<Reservation> _reservations;
  final DateTime _maintenant;

  /// Compteurs d'appel — permettent d'affirmer qu'un cas d'usage a bien
  /// délégué au dépôt, au lieu de recalculer dans son coin.
  int appelsEnregistrer = 0;
  int appelsCreer = 0;
  int appelsModifier = 0;
  int appelsAnnuler = 0;

  /// Les identifiants réellement exclus du calcul de conflit.
  ///
  /// Comptés plutôt que supposés : sans cette trace, un cas d'usage qui
  /// oublierait de passer `exclureReservationId` resterait vert tant que le
  /// jeu de test ne contient pas la réservation modifiée elle-même — et c'est
  /// exactement le cas qu'on ne pense pas à écrire.
  final List<String?> exclusionsDemandees = [];

  @override
  Future<List<UniteHebergement>> unites() async => List.unmodifiable(_unites);

  @override
  Future<List<Disponibilite>> consulterDisponibilites(
    PeriodeSejour periode, {
    String? exclureReservationId,
  }) async {
    exclusionsDemandees.add(exclureReservationId);

    return _unites.map((unite) {
      if (!unite.statut.estLouable) {
        return Disponibilite.horsService(unite, periode);
      }

      final conflit = _reservations
          .where((r) => r.uniteId == unite.id)
          // Une réservation ne se chevauche jamais elle-même.
          .where((r) => r.id != exclureReservationId)
          .where((r) => r.estActive)
          .where((r) => r.periode.chevauche(periode))
          .firstOrNull;

      if (conflit == null) return Disponibilite.libre(unite, periode);

      return Disponibilite.occupee(
        unite,
        periode,
        reservationId: conflit.id,
        periodeOccupee: conflit.periode,
        clientNom: conflit.clientNom,
      );
    }).toList();
  }

  @override
  Future<List<Reservation>> reservations({
    bool seulementEnSuspens = false,
  }) async {
    final liste = seulementEnSuspens
        ? _reservations
              .where((r) => r.statutSynchronisation.estEnSuspens)
              .toList()
        : [..._reservations];
    liste.sort((a, b) => b.creeeLe.compareTo(a.creeeLe));
    return liste;
  }

  @override
  Future<Reservation?> parId(String id) async =>
      _reservations.where((r) => r.id == id).firstOrNull;

  @override
  Future<Reservation> enregistrer(Reservation reservation) async {
    appelsEnregistrer++;
    // Écrasement par identifiant : c'est l'idempotence de l'UUID client, celle
    // qui protège d'un doublon quand le réseau coupe en pleine requête.
    _reservations.removeWhere((r) => r.id == reservation.id);
    _reservations.add(reservation);
    return reservation;
  }

  @override
  Future<Reservation> modifier(Reservation reservation) async {
    appelsModifier++;
    final index = _reservations.indexWhere((r) => r.id == reservation.id);
    if (index < 0) throw ReservationIntrouvable(reservation.id);
    // Remplacée EN PLACE, jamais ajoutée : une modification qui empilerait une
    // seconde version laisserait deux réservations sur la même chambre, et le
    // contrôle de chevauchement les verrait se contredire.
    _reservations[index] = reservation;
    return reservation;
  }

  @override
  Future<Reservation> creer(
    Reservation reservation, {
    required String auteurId,
  }) async {
    appelsCreer++;
    // Le même écrasement par identifiant que [enregistrer] : l'idempotence de
    // l'UUID client.
    _reservations.removeWhere((r) => r.id == reservation.id);
    _reservations.add(reservation);
    return reservation;
  }

  @override
  Future<Reservation> annuler(
    String id, {
    required String tauxSaisi,
    required String modeRemboursement,
    required String valeurRemboursement,
    required String auteurId,
  }) async {
    final index = _reservations.indexWhere((r) => r.id == id);
    if (index < 0) throw ReservationIntrouvable(id);
    final r = _reservations[index];

    // Les MÊMES règles que le dépôt Drift : c'est la fonction pure du domaine,
    // pas un calcul recopié ici.
    final resultat = calculerAnnulation(
      dejaAnnulee: r.statut == StatutReservation.annulee,
      totalCentimes: montantTotalCentimes(
        tarifNuit: r.tarifNuit,
        aDesLignes: r.lignes.isNotEmpty,
        totalDuRecapitulatifFrancs: r.recapitulatif.total,
      ),
      acompteCentimes: r.acompte * 100,
      tauxSaisi: tauxSaisi,
      modeSaisi: modeRemboursement,
      valeurSaisie: valeurRemboursement,
    );
    appelsAnnuler++;

    final annulee = r.copyWith(
      statut: StatutReservation.annulee,
      statutSynchronisation: StatutSynchronisation.local,
      annulation: AnnulationEnregistree(
        tauxCentiemes: resultat.tauxCentiemes,
        totalCentimes: resultat.totalCentimes,
        commissionCentimes: resultat.commissionCentimes,
        rembourseCentimes: resultat.rembourseCentimes,
        modeSaisie: resultat.modeSaisie,
        date: _maintenant,
        auteurId: auteurId,
      ),
    );
    _reservations[index] = annulee;
    return annulee;
  }

  DateTime get maintenant => _maintenant;
}
