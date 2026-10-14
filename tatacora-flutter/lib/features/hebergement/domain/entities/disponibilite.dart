import 'periode_sejour.dart';
import 'unite_hebergement.dart';

/// Résultat du calcul de disponibilité d'une unité sur une période.
///
/// ## Pourquoi le motif accompagne toujours le refus
///
/// Afficher « indisponible » sans dire pourquoi oblige le réceptionniste à
/// aller chercher ailleurs, devant le client. Le motif est donc porté par
/// l'entité, au même titre que le booléen.
///
/// Il reste **factuel** : « réservée du 12 au 15 », pas un libellé mis en
/// forme. La couche présentation décide de la formulation et de la langue.
final class Disponibilite {
  const Disponibilite({
    required this.unite,
    required this.periode,
    required this.disponible,
    this.motif,
    this.reservationEnConflit,
  });

  /// Unité libre sur toute la période.
  factory Disponibilite.libre(UniteHebergement unite, PeriodeSejour periode) =>
      Disponibilite(unite: unite, periode: periode, disponible: true);

  /// Unité immobilisée par son état opérationnel — hors service.
  factory Disponibilite.horsService(
    UniteHebergement unite,
    PeriodeSejour periode,
  ) => Disponibilite(
    unite: unite,
    periode: periode,
    disponible: false,
    motif: MotifIndisponibilite.horsService,
  );

  /// Unité déjà prise sur tout ou partie de la période.
  factory Disponibilite.occupee(
    UniteHebergement unite,
    PeriodeSejour periode, {
    required String reservationId,
    required PeriodeSejour periodeOccupee,
    required String clientNom,
  }) => Disponibilite(
    unite: unite,
    periode: periode,
    disponible: false,
    motif: MotifIndisponibilite.dejaReservee,
    reservationEnConflit: ReservationEnConflit(
      id: reservationId,
      periode: periodeOccupee,
      clientNom: clientNom,
    ),
  );

  final UniteHebergement unite;
  final PeriodeSejour periode;
  final bool disponible;
  final MotifIndisponibilite? motif;

  /// Renseigné uniquement quand le motif est `dejaReservee`.
  final ReservationEnConflit? reservationEnConflit;

  /// Montant du séjour si l'unité était retenue — utile pour comparer deux
  /// unités libres sans repasser par un calcul dans l'écran.
  int get montantSejour => unite.tarifBase * periode.nuits;

  @override
  String toString() =>
      'Disponibilite(${unite.numero}, ${disponible ? 'libre' : motif?.name})';
}

/// Cause d'indisponibilité — une énumération, pas une chaîne libre.
///
/// Un motif en texte libre finirait traduit à trois endroits différents et
/// impossible à filtrer.
enum MotifIndisponibilite {
  /// L'unité porte un état opérationnel qui l'exclut de la vente.
  horsService,

  /// Une autre réservation couvre tout ou partie de la période.
  dejaReservee,
}

/// La réservation qui bloque, décrite juste assez pour être nommée à l'écran.
final class ReservationEnConflit {
  const ReservationEnConflit({
    required this.id,
    required this.periode,
    required this.clientNom,
  });

  final String id;
  final PeriodeSejour periode;
  final String clientNom;
}
