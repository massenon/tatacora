import 'reservation.dart';
import 'unite_hebergement.dart';

/// Ce qu'une **carte** de la grille affiche — la réservation, plus ce qui vit
/// ailleurs.
///
/// ## Deux lignes de montants, jamais un total unique
///
/// *« Un montant unique de 62 400 F laisserait croire que la nuitée a changé
/// de prix. "Séjour 50 000 F" puis "Consommations 12 400 F" dit ce qui s'est
/// réellement passé, et permet de discuter l'un sans remettre l'autre en
/// cause »* (PA-112). La vue Blade tient la même règle : Séjour, Consommations,
/// Acompte versé, Reste à payer — aucun total.
///
/// ## Une seule source, pas deux jeux à synchroniser
///
/// Les consommations ne sont **pas** recopiées sur la réservation : le panier
/// porte déjà `reservationId`. Il n'y a rien à tenir à jour, il y a une source
/// à lire. Un total dénormalisé sur la réservation deviendrait faux au premier
/// article ajouté depuis le point de vente, et rien ne le signalerait.
///
/// ## Le bouton de facture n'existe QUE si la facture existe
///
/// *« Un téléchargement qui ne pointe vers rien est pire qu'un bouton absent :
/// l'utilisateur clique, rien ne vient, et il ne sait pas si le document manque
/// ou si l'écran est cassé. »*
final class CarteReservation {
  const CarteReservation({
    required this.reservation,
    this.consommations = 0,
    this.unite,
    this.factureId,
    this.factureNumero,
  });

  final Reservation reservation;

  /// Total du **panier ouvert** rattaché à ce séjour, en francs CFA. Zéro
  /// quand aucun panier n'est ouvert — la carte écrit alors « — », comme la
  /// vue, jamais « 0 », qui se lirait comme un panier ouvert et vide.
  final int consommations;

  /// L'unité réservée, pour la ligne « Unité : BNG-01 — Bungalow » de la vue
  /// (l.229-230). `null` quand le parc n'a pas encore descendu sur ce poste :
  /// la carte écrit alors un tiret, jamais un identifiant technique.
  final UniteHebergement? unite;

  /// La pièce de facturation émise pour ce séjour, s'il y en a une.
  final String? factureId;
  final String? factureNumero;

  bool get aDesConsommations => consommations > 0;

  bool get estFacturee => factureId != null && factureNumero != null;

  /// Le séjour seul, remise comprise — jamais les consommations.
  int get sejour => reservation.recapitulatif.total;

  /// Reste dû **sur le séjour**, acompte déduit.
  ///
  /// Les consommations n'y entrent pas : elles se règlent au point de vente,
  /// à la clôture du panier. Les additionner ici annoncerait une créance que
  /// la caisse va encaisser dans la minute.
  int get reste => reservation.resteAPayer;
}
