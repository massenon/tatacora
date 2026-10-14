/// Le **calendrier d'occupation** — `m1-hebergement.html`,
/// `rendreCalendrierOccupation()`.
///
/// ## Ce que ce calendrier dit, et ce qu'il ne dit pas
///
/// Il montre, jour par jour, **combien d'unités sont engagées sur le parc**.
/// Le maître l'écrit en toutes lettres sous sa grille : *« Taux d'occupation
/// estimé par jour »*. Estimé, parce qu'il compte les unités retenues par des
/// réservations, pas les clients réellement présents — un séjour annulé le
/// matin même y figure encore jusqu'à ce qu'il soit annulé dans le logiciel.
///
/// La mention est portée telle quelle : un taux présenté comme exact serait lu
/// comme un relevé, et servirait à décider d'une sur-réservation.
///
/// ## Bornes SEMI-OUVERTES, comme partout ailleurs
///
/// `arrivée <= jour < départ`. Le jour du départ, la chambre est libre : elle
/// se reloue le soir même. La compter occupée ce jour-là gonflerait le taux
/// d'un jour par séjour — sur un mois plein, d'un tiers.
library;

import 'reservation.dart';
import 'service_reservation.dart';

/// L'occupation d'un jour du mois.
final class JourOccupation {
  const JourOccupation({
    required this.jour,
    required this.unitesOccupees,
    required this.totalUnites,
  });

  final DateTime jour;

  /// Nombre d'unités engagées ce jour-là, **borné au parc** : deux
  /// réservations sur la même chambre — un conflit que RG-01 doit empêcher,
  /// mais qui peut exister le temps d'une synchronisation — ne feraient pas
  /// afficher « 7/6 ».
  final int unitesOccupees;

  final int totalUnites;

  /// Entre 0 et 1. Zéro quand le parc est vide : diviser par zéro donnerait
  /// `NaN`, et un `NaN` peint une case dans la couleur du hasard.
  double get taux => totalUnites == 0 ? 0 : unitesOccupees / totalUnites;

  bool get estOccupe => unitesOccupees > 0;

  /// Les trois paliers du maître — faible, moyen, fort.
  ///
  /// Ce sont **ses seuils** (`taux < 0.5`, `taux < 0.9`), pas des valeurs
  /// choisies ici : ils commandent la couleur des cases, et sa légende les
  /// nomme.
  PalierOccupation get palier {
    if (unitesOccupees == 0) return PalierOccupation.vide;
    if (taux < 0.5) return PalierOccupation.faible;
    if (taux < 0.9) return PalierOccupation.moyen;
    return PalierOccupation.fort;
  }
}

enum PalierOccupation { vide, faible, moyen, fort }

/// Le mois entier, prêt à peindre.
final class OccupationMensuelle {
  const OccupationMensuelle({
    required this.mois,
    required this.jours,
    required this.totalUnites,
    required this.decalagePremierJour,
  });

  /// Calcule l'occupation du mois de [reference].
  ///
  /// [maintenant] et [reference] sont injectés : une grille qui lit l'horloge
  /// dans son calcul devient intestable aux bornes — et ce sont les bornes qui
  /// comptent, le premier et le dernier jour du mois.
  factory OccupationMensuelle.calculer({
    required DateTime reference,
    required List<Reservation> reservations,
    required int totalUnites,
  }) {
    final premier = DateTime(reference.year, reference.month);
    // Le zéro du mois suivant EST le dernier jour de celui-ci — sans avoir à
    // savoir lequel des mois compte 28, 30 ou 31 jours.
    final nbJours = DateTime(reference.year, reference.month + 1, 0).day;

    // Seules les réservations qui portent réellement de l'hébergement pèsent
    // sur l'occupation des chambres : une fiche qui ne contient qu'un circuit
    // n'occupe aucune unité.
    final avecHebergement = reservations
        .where((r) => r.estActive)
        .where(
          (r) =>
              r.lignes.isEmpty ||
              r.lignes.any((l) => l.service == ServiceReservation.hebergement),
        )
        .toList();

    final jours = <JourOccupation>[];
    for (var j = 1; j <= nbJours; j++) {
      final jour = DateTime(reference.year, reference.month, j);
      var occupees = 0;

      for (final r in avecHebergement) {
        final arrivee = _jour(r.periode.arrivee);
        final depart = _jour(r.periode.depart);
        // Bornes semi-ouvertes : le jour du départ ne compte pas.
        if (!jour.isBefore(arrivee) && jour.isBefore(depart)) {
          // Une réservation d'avant le détail par service (schéma < v8) n'a
          // aucune ligne : elle engage tout de même son unité, celle que
          // porte `unite_id`. La compter pour zéro ferait disparaître de la
          // grille tout l'historique du poste.
          final unites = r.lignes
              .where((l) => l.service == ServiceReservation.hebergement)
              .length;
          occupees += unites == 0 ? 1 : unites;
        }
      }

      jours.add(
        JourOccupation(
          jour: jour,
          unitesOccupees: totalUnites == 0
              ? occupees
              : (occupees > totalUnites ? totalUnites : occupees),
          totalUnites: totalUnites,
        ),
      );
    }

    return OccupationMensuelle(
      mois: premier,
      jours: jours,
      totalUnites: totalUnites,
      // Lundi = 0, comme au maître : `(getDay() + 6) % 7`. Dart numérote les
      // jours de 1 (lundi) à 7 (dimanche), d'où le simple `- 1`.
      decalagePremierJour: premier.weekday - 1,
    );
  }

  final DateTime mois;
  final List<JourOccupation> jours;
  final int totalUnites;

  /// Cases vides à poser avant le 1er, pour que la colonne du lundi soit bien
  /// celle du lundi.
  final int decalagePremierJour;
}

DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
