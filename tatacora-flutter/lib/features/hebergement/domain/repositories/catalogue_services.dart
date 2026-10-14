// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
import '../entities/service_reservation.dart';

/// Ce que le formulaire de réservation peut proposer, service par service.
///
/// ## Une seule source, pour la raison que le maître écrit lui-même
///
/// `prototype_v2/pages/reservations.html` l.131 justifie le référentiel
/// administrable des canaux ainsi : *« deux listes écrites à la main auraient
/// fini par diverger, et l'analyse par canal serait devenue fausse sans que
/// rien ne le signale »*. La règle vaut pour les catalogues : le point de
/// vente et la réservation vendent les mêmes boissons, les mêmes circuits et
/// les mêmes véhicules. Ils lisent donc les mêmes tables, par la même
/// implémentation.
abstract interface class CatalogueServices {
  /// Les cinq rayons, **dans l'ordre du maître**, y compris ceux qui sont
  /// vides — avec leur raison.
  ///
  /// [periode] sert aux services dont la disponibilité dépend des dates :
  /// l'hébergement d'abord. `null` quand les dates ne sont pas encore
  /// saisies — le maître propose alors tout le parc plutôt que de masquer
  /// arbitrairement, le contrôle définitif ayant lieu à l'enregistrement.
  /// [exclureReservationId] écarte une réservation du calcul d'occupation :
  /// en MODIFICATION, la chambre déjà retenue par cette réservation-là ne doit
  /// pas se présenter comme prise — elle est prise par elle-même.
  Future<List<RayonService>> rayons({
    DateTime? arrivee,
    DateTime? depart,
    String? exclureReservationId,
  });
}
