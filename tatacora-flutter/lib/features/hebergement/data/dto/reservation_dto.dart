import '../../domain/entities/periode_sejour.dart';
import '../../domain/entities/reservation.dart';

/// Traduction du JSON de `ReservationResource` (Laravel) vers le domaine.
///
/// ## Le contrat serveur, relevé le 18/08/2026
///
/// ```json
/// { "id", "client_id", "unite_id", "date_arrivee", "date_depart",
///   "nb_nuitees", "statut", "acompte",
///   "client": { "id", "nom_complet", "telephone" } }
/// ```
///
/// ## Cinq écarts avec le domaine, constatés et NON contournés
///
/// Le serveur ne connaît ni `reference`, ni `tarif_nuit`, ni
/// `motif_annulation` : ces colonnes n'existent pas dans sa table
/// `reservations`. Le DTO ne les invente donc pas — il les laisse à `null`, et
/// c'est la valeur **locale** qui est conservée à la fusion.
///
/// Inventer une référence ou recalculer un tarif à partir du parc courant
/// serait pire que l'absence : la donnée aurait l'air complète et serait
/// fausse. Le détail des cinq écarts est consigné en PA-57.
final class ReservationDto {
  const ReservationDto({
    required this.id,
    required this.clientId,
    required this.uniteId,
    required this.dateArrivee,
    required this.dateDepart,
    required this.nbNuitees,
    required this.statut,
    required this.acompte,
    this.clientNom,
  });

  factory ReservationDto.depuisJson(Map<String, dynamic> json) {
    return ReservationDto(
      id: json['id'] as String,
      clientId: json['client_id'] as String,
      uniteId: json['unite_id'] as String,
      dateArrivee: _date(json['date_arrivee']),
      dateDepart: _date(json['date_depart']),
      nbNuitees: _entier(json['nb_nuitees']),
      statut: json['statut'] as String? ?? '',
      // `acompte` est un DECIMAL(15,2) côté serveur : il arrive en chaîne
      // (« 20000.00 ») ou en nombre selon le pilote. Les deux sont acceptés,
      // et arrondis — le XOF n'a pas de sous-unité en circulation.
      acompte: _entier(json['acompte']),
      clientNom:
          (json['client'] as Map<String, dynamic>?)?['nom_complet'] as String?,
    );
  }

  final String id;
  final String clientId;
  final String uniteId;
  final DateTime dateArrivee;
  final DateTime dateDepart;
  final int nbNuitees;
  final String statut;
  final int acompte;
  final String? clientNom;

  /// Dates renvoyées en `YYYY-MM-DD` par `toDateString()`. On les ramène à
  /// minuit **UTC** : construire un `DateTime` local décalerait le séjour d'un
  /// jour dans un fuseau négatif.
  static DateTime _date(Object? valeur) {
    final brut = valeur as String;
    final p = brut.split('T').first.split('-');
    return DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static int _entier(Object? valeur) {
    if (valeur is int) return valeur;
    if (valeur is double) return valeur.round();
    if (valeur is String) return (double.tryParse(valeur) ?? 0).round();
    return 0;
  }

  /// Fusionne la version serveur avec la version locale.
  ///
  /// Le serveur fait autorité sur ce qu'il connaît — statut, dates, acompte.
  /// La version locale conserve ce que le serveur **ignore** : la référence,
  /// le tarif figé et le motif d'annulation. C'est une fusion, pas un
  /// écrasement : remplacer purement l'objet local perdrait ces trois champs à
  /// la première synchronisation, et le montant de la réservation deviendrait
  /// irrécupérable.
  Reservation fusionner(Reservation locale) {
    return Reservation(
      id: id,
      reference: locale.reference,
      clientId: clientId,
      clientNom: clientNom ?? locale.clientNom,
      uniteId: uniteId,
      periode: PeriodeSejour(arrivee: dateArrivee, depart: dateDepart),
      tarifNuit: locale.tarifNuit,
      statut: StatutReservation.depuisCode(statut),
      statutSynchronisation: StatutSynchronisation.synchronise,
      creeeLe: locale.creeeLe,
      acompte: acompte,
      motifRejet: null,
      motifAnnulation: locale.motifAnnulation,
    );
  }

  /// Entité construite **sans** contrepartie locale — cas d'une réservation
  /// créée sur un autre poste et découverte à la synchronisation.
  ///
  /// `tarifNuit` vaut alors 0 et `reference` porte l'identifiant : ni l'un ni
  /// l'autre n'existe côté serveur. Un montant à 0 est visiblement faux, donc
  /// visible ; un montant recalculé au tarif du jour serait plausible et faux,
  /// donc invisible. On préfère le premier.
  Reservation versEntiteSansLocal({required DateTime creeeLe}) {
    return Reservation(
      id: id,
      reference: 'SRV-${id.substring(0, 8).toUpperCase()}',
      clientId: clientId,
      clientNom: clientNom ?? '',
      uniteId: uniteId,
      periode: PeriodeSejour(arrivee: dateArrivee, depart: dateDepart),
      tarifNuit: 0,
      statut: StatutReservation.depuisCode(statut),
      statutSynchronisation: StatutSynchronisation.synchronise,
      creeeLe: creeeLe,
      acompte: acompte,
    );
  }

  /// Charge utile de création.
  ///
  /// **Six clés exactement** : c'est tout ce que `CreerReservationRequest`
  /// accepte. Envoyer davantage n'échoue pas — Laravel écarte silencieusement
  /// ce qui n'est pas dans `rules()` — mais laisserait croire, à la lecture du
  /// code client, que le serveur reçoit un tarif ou une référence.
  ///
  /// `statut` n'y figure pas : le serveur applique son défaut `en_attente`.
  static Map<String, Object?> chargeCreation(Reservation r) => {
    // L'UUID est fourni par le client : le serveur ne le réattribue jamais et
    // s'en sert comme clé de déduplication.
    'id': r.id,
    'client_id': r.clientId,
    'unite_id': r.uniteId,
    'date_arrivee': jour(r.periode.arrivee),
    'date_depart': jour(r.periode.depart),
    'acompte': r.acompte,
  };

  /// Date seule `YYYY-MM-DD` — la forme attendue par l'API.
  static String jour(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Unité renvoyée par `GET /hebergement/disponibilites`.
///
/// Le serveur ne renvoie **que les unités libres**, et seulement
/// `{id, numero, categorie_id}` — ni tarif, ni capacité, ni motif pour les
/// autres. C'est pourquoi la disponibilité affichée est calculée **en local**,
/// où le parc complet et les motifs sont connus : voir
/// `ReservationRepositoryComposite`.
final class UniteDisponibleDto {
  const UniteDisponibleDto({
    required this.id,
    required this.numero,
    required this.categorieId,
  });

  factory UniteDisponibleDto.depuisJson(Map<String, dynamic> json) =>
      UniteDisponibleDto(
        id: json['id'] as String,
        numero: json['numero'] as String,
        categorieId: json['categorie_id'] as String,
      );

  final String id;
  final String numero;
  final String categorieId;
}
