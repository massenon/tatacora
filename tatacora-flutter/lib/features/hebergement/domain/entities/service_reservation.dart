// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
/// Les cinq services combinables d'une réservation, portés du maître.
///
/// ## Ce que le maître dit, et que le client Flutter ignorait
///
/// `prototype_v2/pages/reservations.html` l.30 l'écrit en sous-titre de la
/// page : *« Une réservation peut combiner Hébergement, Restauration, Bar,
/// Tourisme et/ou Location de véhicule sur une même fiche client. »* Ce n'est
/// pas un ornement : le formulaire (l.144) rend la sélection **obligatoire**,
/// et le récapitulatif financier additionne les sous-totaux des cinq services
/// (`reservations-services.js:recalculerTotaux`).
///
/// Le client Flutter ne connaissait qu'une chambre et un tarif de nuit. Le
/// sous-total valait donc `tarif × nuits` — juste pour un séjour sec, faux dès
/// qu'un circuit ou une location entre dans la même fiche.
///
/// ## Registre FERMÉ
///
/// Cinq valeurs, jamais dérivées d'une chaîne libre. C'est ce qui distingue ce
/// modèle d'un identifiant polymorphe, et c'est le même choix que
/// `ModuleVendable` au point de vente.
///
/// @see prototype_v2/pages/reservations-services.js l.40 (`SERVICES`)
library;

/// Un service inclus dans une réservation.
enum ServiceReservation {
  hebergement(
    cle: 'hebergement',
    nom: 'Hébergement',
    labelQuantite: 'Nuits',
    labelLigne: 'une chambre',
  ),
  restauration(
    cle: 'restauration',
    nom: 'Restauration',
    labelQuantite: 'Nb. personnes',
    labelLigne: 'un plat',
  ),
  bar(
    cle: 'bar',
    nom: 'Bar',
    labelQuantite: 'Quantité',
    labelLigne: 'une boisson',
  ),
  tourisme(
    cle: 'tourisme',
    nom: 'Tourisme',
    labelQuantite: 'Nb. participants',
    labelLigne: 'un circuit',
  ),
  vehicule(
    cle: 'vehicule',
    nom: 'Véhicule',
    labelQuantite: 'Nb. jours',
    labelLigne: 'un véhicule',
  );

  const ServiceReservation({
    required this.cle,
    required this.nom,
    required this.labelQuantite,
    required this.labelLigne,
  });

  /// Le code du maître — **c'est lui qui est persisté**, jamais le nom
  /// affiché. Un libellé est du texte d'interface : le renommer orphelinerait
  /// les lignes déjà écrites.
  final String cle;

  final String nom;

  /// L'intitulé de la quantité, propre à chaque service. « Nuits » pour une
  /// chambre, « Nb. participants » pour un circuit : le même champ ne compte
  /// pas la même chose.
  final String labelQuantite;

  /// Complète « Ajouter … » sur le bouton du bloc.
  final String labelLigne;

  /// Vrai quand la quantité **se déduit** et ne se saisit pas.
  ///
  /// Seul l'hébergement : sa quantité EST le nombre de nuits du séjour
  /// (`reservations-services.js:quantiteEstCalculee`). Le maître rend le champ
  /// en lecture seule plutôt que de le masquer — un champ absent ferait
  /// chercher où est passé le nombre de nuits.
  bool get quantiteEstCalculee => this == ServiceReservation.hebergement;

  static ServiceReservation? parCle(String? cle) {
    if (cle == null) return null;
    for (final s in values) {
      if (s.cle == cle) return s;
    }
    return null;
  }
}

/// Une entrée proposable au catalogue d'un service.
///
/// Reprend la forme que `catalogue()` rend au maître : un identifiant, un
/// libellé, un prix, et la disponibilité.
final class OptionService {
  const OptionService({
    required this.id,
    required this.libelle,
    required this.prix,
    this.disponible = true,
  });

  final String id;
  final String libelle;

  /// En francs CFA. Entier : le XOF n'a pas de sous-unité en circulation.
  final int prix;

  final bool disponible;

  @override
  bool operator ==(Object other) =>
      other is OptionService && other.id == id && other.libelle == libelle;

  @override
  int get hashCode => Object.hash(id, libelle);
}

/// Le catalogue d'un service, tel que le formulaire l'affiche.
///
/// Un rayon **vide reste visible avec sa raison** — jamais omis. C'est déjà la
/// règle du point de vente (PA-90), et le maître la tient lui aussi : il rend
/// « Aucun élément disponible actuellement pour … » plutôt que de retirer le
/// bloc (`reservations-services.js`, rendu de la zone des lignes).
final class RayonService {
  const RayonService({
    required this.service,
    required this.options,
    this.motifIndisponibilite,
  });

  final ServiceReservation service;
  final List<OptionService> options;

  /// Renseigné quand le rayon est vide **par construction**, pas par hasard.
  final String? motifIndisponibilite;

  bool get estVide => options.isEmpty;
}

/// Une ligne de service d'une réservation.
///
/// ## Libellé et prix sont FIGÉS à l'ajout
///
/// Exactement le raisonnement du panier (PA-98) et du `tarifNuit` (PA-55) :
/// relire le catalogue à l'affichage ferait varier le montant d'une
/// réservation déjà prise au premier changement de tarif, et le client
/// recevrait une facture différente du devis. Le catalogue dit ce qu'on vend
/// **aujourd'hui** ; la ligne dit ce qui a été vendu.
final class LigneService {
  const LigneService({
    required this.id,
    required this.service,
    required this.itemId,
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
  });

  final String id;
  final ServiceReservation service;

  /// Le code de l'entrée retenue au catalogue. Vide tant que l'utilisateur
  /// n'a pas choisi — le maître ajoute la ligne d'abord (« Choisir... »), et
  /// une ligne sans choix ne compte pour rien au récapitulatif.
  final String itemId;

  final String libelle;
  final int prixUnitaire;
  final int quantite;

  bool get estRenseignee => itemId.isNotEmpty;

  /// Zéro tant que rien n'est choisi : une ligne vide ne doit pas peser sur le
  /// total, et surtout pas y peser d'un montant qu'aucun catalogue ne porte.
  int get sousTotal => estRenseignee ? prixUnitaire * quantite : 0;

  LigneService copyWith({
    String? itemId,
    String? libelle,
    int? prixUnitaire,
    int? quantite,
  }) => LigneService(
    id: id,
    service: service,
    itemId: itemId ?? this.itemId,
    libelle: libelle ?? this.libelle,
    prixUnitaire: prixUnitaire ?? this.prixUnitaire,
    quantite: quantite ?? this.quantite,
  );
}
