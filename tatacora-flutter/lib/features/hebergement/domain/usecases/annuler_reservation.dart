import '../entities/reservation.dart';
import '../repositories/reservation_repository.dart';

/// Annule une réservation, AVEC commission et remboursement (EF-M1-06).
///
/// ## Annuler n'est pas supprimer
///
/// La réservation reste en base, avec son statut `annulee`, son taux, sa
/// commission et ce qu'elle a remboursé. Elle cesse d'engager l'unité, mais elle
/// continue d'exister : c'est ce qui permet d'expliquer, une semaine plus tard,
/// pourquoi une chambre est restée vide un soir de forte demande — et combien le
/// client a perdu. Une suppression effacerait la question avec la réponse.
///
/// ## Ce qui change le 12/10/2026 (lot 6)
///
/// Le geste ne prenait qu'un MOTIF. Le serveur n'en connaît pas : il demande un
/// taux, applique une commission sur le montant GLOBAL, rembourse au plus
/// l'acompte, et passe la pièce du remboursement dans la même transaction
/// (`AnnulationReservationService`). Ce poste fait de même, par le MÊME dépôt —
/// un seul chemin d'annulation : une annulation qui ne passerait pas par la
/// pièce laisserait l'acompte dans les comptes comme s'il était encore dû au
/// client.
///
/// ## Un séjour terminé ne s'annule pas — garde du POSTE
///
/// Le serveur ne la porte pas (il ne regarde que `statut = annulee`). Elle est
/// conservée parce que l'écran n'offre déjà pas le geste sur un séjour terminé
/// (annuler un séjour consommé ne libère rien et fausserait le chiffre d'affaires
/// du mois écoulé), et qu'une correction passe par un avoir côté facturation.
final class AnnulerReservation {
  const AnnulerReservation(this._depot);

  final ReservationRepository _depot;

  Future<Reservation> call(
    String id, {
    required String tauxSaisi,
    required String modeRemboursement,
    required String valeurRemboursement,
    required String auteurId,
  }) async {
    final existante = await _depot.parId(id);
    if (existante == null) throw ReservationIntrouvable(id);

    if (existante.statut == StatutReservation.terminee) {
      throw StateError(
        'Le séjour est terminé : il ne s’annule plus. Une correction passe par '
        'un avoir côté facturation.',
      );
    }

    return _depot.annuler(
      id,
      tauxSaisi: tauxSaisi,
      modeRemboursement: modeRemboursement,
      valeurRemboursement: valeurRemboursement,
      auteurId: auteurId,
    );
  }
}
