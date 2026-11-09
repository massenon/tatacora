import '../../../hebergement/domain/entities/reservation.dart';

/// Un séjour est-il offert au POS clients hébergés ?
///
/// LA règle de la vue (`heberges.blade.php`, colonne « Séjours en cours » :
/// `PosHeberges::sejoursEnCours()`, `STATUTS_EN_SEJOUR = ['confirmee', 'en_cours']`) :
/// c'est le STATUT enregistré de la réservation, jamais les dates du jour.
bool estSejourAuPos(Reservation r) =>
    r.statut == StatutReservation.enCours ||
    r.statut == StatutReservation.confirmee;
