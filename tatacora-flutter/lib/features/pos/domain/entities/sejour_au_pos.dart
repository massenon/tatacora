import '../../../hebergement/domain/entities/reservation.dart';

/// Un séjour est-il offert au POS clients hébergés ?
///
/// Règle du PO du 10/11/2026, IDENTIQUE à `PosHeberges::sejoursEnCours()` du web : AUCUNE règle de
/// période. Toute réservation ni annulée ni terminée (en attente, confirmée, en cours) est offerte,
/// quel que soit le rapport entre ses dates et aujourd'hui — un séjour peut être rallongé,
/// raccourci ou décalé. Seules `annulee` et `terminee` en sont exclues.
bool estSejourAuPos(Reservation r) =>
    r.statut != StatutReservation.annulee &&
    r.statut != StatutReservation.terminee;
