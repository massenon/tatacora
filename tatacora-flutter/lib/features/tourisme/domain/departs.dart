/// M9 — les règles de départ, **hors de tout widget et de toute base**.
///
/// Elles vivent ici pour une raison précise : un départ n'existe pas. Il n'y a
/// aucune table `departs`, ni au serveur ni sur ce poste — un départ est le
/// couple (circuit, date) porté par les lignes de `reservations_tour`, plus le
/// guide que ces lignes désignent. Tout ce qui le concerne est donc une
/// DÉRIVATION, et une dérivation se teste sans écran.
///
/// ## Une seule dérivation, jamais deux
///
/// Le serveur a extrait la sienne de l'écran vers son service le 02/09/2026,
/// précisément pour que la carte d'accueil et l'écran ne dérivent pas deux
/// fois la même chose (PA-121). La même discipline s'applique ici : la grille,
/// les indicateurs et les exports lisent tous ces fonctions.
///
/// @see EF-M9-03 Réservation avec affectation de guide
/// @see EF-M9-04 Capacité maximale par circuit
/// @see RG-13 Capacité contrôlée **cumulée sur le départ**
/// @see UC-39 Réaffecter un guide
library;

import 'entities/reservation_tour.dart';

/// Les refus du domaine, **au mot du serveur** (`lang/fr/tourisme.php`).
///
/// Un seul auteur pour ces phrases : le DAO les lève, les tests les attendent,
/// l'écran les affiche. Trois copies finiraient par diverger, et c'est la
/// copie affichée qui tromperait l'opérateur.
abstract final class MessagesTourisme {
  /// `tourisme.participants_minimum`.
  static const String participantsMinimum =
      'Une réservation doit compter au moins un participant.';

  /// `tourisme.capacite_depassee` — le refus de RG-13.
  ///
  /// Il nomme les trois nombres : ce qui est demandé, ce qui reste, et la
  /// capacité du circuit. Un « Départ complet » sec laisserait croire à une
  /// erreur de saisie alors que c'est le CUMUL qui bloque.
  static String capaciteDepassee({
    required int demandes,
    required int restantes,
    required int capacite,
  }) =>
      'Départ complet : $demandes participants demandés pour '
      '$restantes place(s) encore disponible(s) '
      '(capacité du circuit : $capacite).';

  /// `tourisme.guide_deja_affecte`.
  static String guideDejaAffecte(String date) =>
      'Ce guide assure déjà un autre circuit le $date.';

  /// `tourisme.guide_du_depart_impose`.
  static const String guideDuDepartImpose =
      'Ce départ est déjà conduit par un autre guide. Reprenez le guide en '
      'place, ou réaffectez le départ entier.';

  /// `tourisme.affectation_impossible`.
  static const String affectationImpossible =
      'Une prestation annulée ou clôturée ne peut plus changer de guide.';

  /// `tourisme.annulation_apres_cloture`.
  static const String annulationApresCloture =
      'Une prestation clôturée ne peut plus être annulée. Corrigez-la par un '
      'avoir si elle a été facturée.';

  /// `tourisme.pwa.depart_sans_reservation`.
  static const String departSansReservation =
      'Ce départ n\'a aucune réservation active : il n\'existe que par elles, '
      'il n\'y a donc rien à annuler ni à réaffecter.';

  /// `tourisme.validation.circuit_inexistant`.
  static const String circuitInexistant =
      'Ce circuit n\'existe pas au catalogue.';

  /// `tourisme.validation.guide_inexistant`.
  static const String guideInexistant =
      'Ce guide n\'existe pas dans le référentiel.';

  /// `tourisme.validation.client_inexistant`.
  static const String clientInexistant =
      'Ce client n\'existe pas dans le référentiel.';
}

/// Un refus MÉTIER — pas une panne.
///
/// `only_throw_errors` impose une `Exception` ; le type distinct permet à
/// l'écran d'afficher le message tel quel dans la modale, là où une erreur
/// technique n'aurait rien à y faire.
final class RefusTourisme implements Exception {
  const RefusTourisme(this.message);

  final String message;

  @override
  String toString() => message;
}

/// L'état d'un départ — **registre fermé**, l'ordre du maître (colonne
/// « État », `pwa/tourisme/departs.blade.php` l.317-323).
///
/// Il se DÉDUIT, il n'est stocké nulle part : seule l'annulation est une
/// donnée (toutes les lignes du départ annulées). Le stocker exigerait de le
/// faire vieillir, et un poste éteint une semaine afficherait « des places »
/// sur un départ complet (même raisonnement qu'en PA-111).
enum EtatDepart {
  /// Toutes les lignes du départ sont annulées — le départ n'existe plus.
  annule,

  /// Plus une seule place : `places_restantes == 0`.
  complet,

  /// Il reste des places — le maître écrit « N place(s) ».
  placesDisponibles,
}

/// Un départ dérivé : le couple (circuit, date) et ce que ses lignes disent.
final class Depart {
  const Depart({
    required this.circuitId,
    required this.circuitNom,
    required this.date,
    required this.capacite,
    required this.placesVendues,
    required this.prixUnitaire,
    required this.chiffreAffaires,
    required this.annule,
    this.guideId,
    this.guideNom,
    this.duree,
  });

  final String circuitId;
  final String circuitNom;

  /// Le jour du départ, normalisé à minuit.
  final DateTime date;

  /// `circuits.capacite_max` — **jamais une saisie** (EF-M9-04).
  final int capacite;

  final int placesVendues;

  /// Prix par personne, en francs entiers.
  final int prixUnitaire;

  /// Somme des montants des lignes ACTIVES, en francs entiers.
  final int chiffreAffaires;

  /// Vrai quand aucune ligne active ne subsiste.
  final bool annule;

  /// Le guide du départ — celui de ses lignes actives. `null` seulement quand
  /// le départ est entièrement annulé.
  final String? guideId;
  final String? guideNom;

  /// La durée du circuit — texte LIBRE, lue depuis la v10 (14/09/2026).
  /// `null` = aucune durée renseignée, ce que [dureeIndeterminee] compte.
  final String? duree;

  int get placesRestantes {
    final reste = capacite - placesVendues;
    return reste < 0 ? 0 : reste;
  }

  EtatDepart get etat {
    if (annule) return EtatDepart.annule;
    if (placesRestantes == 0) return EtatDepart.complet;
    return EtatDepart.placesDisponibles;
  }

  /// Le remplissage en pourcentage, **plafonné à 100** — la jauge du maître
  /// (l.292). Une jauge qui dépasserait sa barre dirait une sur-réservation
  /// que le contrôle de capacité interdit.
  int get pourcentageRemplissage {
    if (capacite <= 0) return 0;
    final brut = (placesVendues / capacite) * 100;
    final arrondi = brut.round();
    return arrondi > 100 ? 100 : arrondi;
  }

  /// La clé d'un départ — ce qui l'identifie, faute de table.
  static String cle(String circuitId, DateTime date) =>
      '$circuitId|${cleDeJour(date)}';
}

/// `Y-m-d` — la clé de regroupement d'un départ, et rien d'autre.
String cleDeJour(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Le jour nu d'une date : un départ est un JOUR, pas un instant.
DateTime jourDe(DateTime d) => DateTime(d.year, d.month, d.day);

/// Les DÉPARTS dérivés des lignes de réservation.
///
/// Port fidèle de `ReservationTourService::departsDerives()`. Deux points qui
/// comptent, et qui se perdraient à la réécriture :
///
/// 1. un départ naît `annule: true` et repasse à `false` **dès qu'une ligne
///    active est rencontrée** : un départ dont toutes les lignes sont
///    annulées reste donc visible, annulé, plutôt que de disparaître de la
///    grille sans que personne ne sache ce qu'il est devenu ;
/// 2. une ligne annulée ne compte **ni en places, ni en chiffre d'affaires**,
///    et ne donne pas son guide au départ.
List<Depart> departsDerives(List<ReservationTour> reservations) {
  final parCle = <String, _DepartEnCours>{};

  for (final r in reservations) {
    final jour = jourDe(r.dateCircuit);
    final cle = Depart.cle(r.circuitId, jour);

    final depart = parCle.putIfAbsent(
      cle,
      () => _DepartEnCours(
        circuitId: r.circuitId,
        circuitNom: r.circuitNom,
        date: jour,
        capacite: r.capaciteCircuit,
        prixUnitaire: r.prixUnitaire,
        duree: r.dureeCircuit,
      ),
    );

    if (r.estAnnulee) continue;

    depart.annule = false;
    depart.placesVendues += r.nbParticipants;
    depart.chiffreAffaires += r.montant;
    depart.guideId ??= r.guideId;
    depart.guideNom ??= r.guideNom;
  }

  return parCle.values.map((d) => d.fige()).toList(growable: false);
}

final class _DepartEnCours {
  _DepartEnCours({
    required this.circuitId,
    required this.circuitNom,
    required this.date,
    required this.capacite,
    required this.prixUnitaire,
    required this.duree,
  });

  final String circuitId;
  final String circuitNom;
  final DateTime date;
  final int capacite;
  final int prixUnitaire;
  final String? duree;

  bool annule = true;
  int placesVendues = 0;
  int chiffreAffaires = 0;
  String? guideId;
  String? guideNom;

  Depart fige() => Depart(
    circuitId: circuitId,
    circuitNom: circuitNom,
    date: date,
    capacite: capacite,
    placesVendues: placesVendues,
    prixUnitaire: prixUnitaire,
    chiffreAffaires: chiffreAffaires,
    annule: annule,
    guideId: guideId,
    guideNom: guideNom,
    duree: duree,
  );
}

/// Les six agrégats de la bande d'indicateurs — port de
/// `ReservationTourService::agregerDeparts()`.
final class AgregatsDeparts {
  const AgregatsDeparts({
    required this.departs,
    required this.placesVendues,
    required this.capaciteOfferte,
    required this.complets,
    required this.chiffreAffaires,
    required this.tauxRemplissage,
    required this.dureeIndeterminee,
  });

  final int departs;
  final int placesVendues;
  final int capaciteOfferte;
  final int complets;
  final int chiffreAffaires;

  /// `null` quand aucune capacité n'est offerte.
  ///
  /// « 0 % » se lirait comme un départ désert, alors qu'il n'y a **rien à
  /// remplir** (blade l.137-138, Article 7). Les deux situations ne se
  /// corrigent pas de la même façon.
  final double? tauxRemplissage;

  /// Le nombre de départs à durée indéterminée.
  ///
  /// **Vrai compte depuis la v10 (14/09/2026)** : la colonne existe et le DAO
  /// la lit. ⚠ Jusque-là il valait toujours 0, par un garde-fou volontaire —
  /// `null` disait alors « colonne absente », et compter aurait mesuré
  /// l'absence de la colonne (PA-59/60/61). Le garde-fou est RETIRÉ avec la
  /// v10 : le conserver exclurait du compte tous les circuits sans durée,
  /// c'est-à-dire les plus indéterminés de tous.
  final int dureeIndeterminee;
}

AgregatsDeparts agregerDeparts(List<Depart> departs) {
  var placesVendues = 0;
  var capaciteOfferte = 0;
  var chiffreAffaires = 0;
  var complets = 0;
  var indeterminees = 0;

  for (final d in departs) {
    placesVendues += d.placesVendues;
    capaciteOfferte += d.capacite;
    chiffreAffaires += d.chiffreAffaires;
    if (d.placesRestantes == 0) complets++;
    if (dureeIndeterminee(d.duree)) indeterminees++;
  }

  return AgregatsDeparts(
    departs: departs.length,
    placesVendues: placesVendues,
    capaciteOfferte: capaciteOfferte,
    complets: complets,
    chiffreAffaires: chiffreAffaires,
    tauxRemplissage: capaciteOfferte > 0
        ? ((placesVendues / capaciteOfferte) * 1000).round() / 10
        : null,
    dureeIndeterminee: indeterminees,
  );
}

/// `circuits.duree` est un `varchar` **libre** (PA-51) : une durée exploitable
/// contient un chiffre (« 3 jours / 2 nuits »). « Plusieurs jours » n'en est
/// pas une.
///
/// La règle teste la **présence** d'un chiffre, pas sa position — reprise
/// telle quelle du serveur, sans « correction » silencieuse. Conséquence
/// métier, écrite au bandeau du maître : un circuit de plusieurs jours ne
/// bloque que son **jour de départ**.
///
/// ⚠ `null` vaut « indéterminée » — au serveur, et ici DEPUIS LA V10
/// (14/09/2026), la colonne existant désormais et pouvant être vide. Avant la
/// v10, `null` voulait dire « colonne absente » et
/// [AgregatsDeparts.dureeIndeterminee] portait un garde-fou pour n'en rien
/// conclure ; il est retiré en même temps que la colonne est arrivée.
bool dureeIndeterminee(String? duree) {
  if (duree == null) return true;
  return !RegExp(r'[0-9]').hasMatch(duree);
}

/// Les places encore disponibles sur un départ — jamais négatif.
int placesRestantesPour({required int capacite, required int dejaVendues}) {
  final reste = capacite - dejaVendues;
  return reste < 0 ? 0 : reste;
}

/// **RG-13 — le contrôle de capacité, CUMULÉ sur le départ.**
///
/// Rend le message de refus, ou `null` si la réservation passe.
///
/// C'est le cœur de M9, et la lecture littérale « une réservation ne dépasse
/// pas la capacité » ne suffit pas : trois groupes de 5 sur un circuit à 12
/// places tiennent chacun pris isolément, et le troisième doit être refusé.
/// Le contrôle porte donc sur `dejaVendues + demandes`, où `dejaVendues` est
/// la somme des lignes ACTIVES du même couple (circuit, date).
///
/// ⚠ Ce contrôle-ci est celui du POSTE. L'arbitrage entre deux postes hors
/// ligne n'a pas lieu ici et ne peut pas y avoir lieu : il se tranche au
/// serveur, sous verrou pessimiste, comme RG-01. `reservations_tour` n'étant
/// pas au registre des tables synchronisables, il ne se tranche **nulle
/// part** pour l'instant — c'est écrit à l'écran, pas masqué.
String? refusDeCapaciteCumulee({
  required int capacite,
  required int dejaVendues,
  required int demandes,
}) {
  if (demandes < 1) return MessagesTourisme.participantsMinimum;

  final restantes = capacite - dejaVendues;
  if (demandes > restantes) {
    return MessagesTourisme.capaciteDepassee(
      demandes: demandes,
      restantes: restantes < 0 ? 0 : restantes,
      capacite: capacite,
    );
  }

  return null;
}

/// Le taux du maître : « 66.7 % », « 100 % » — une décimale, et pas de
/// décimale inutile (PHP `round(x, 1)` puis concaténation).
String formaterTaux(double taux) {
  final arrondi = (taux * 10).round() / 10;
  return arrondi == arrondi.roundToDouble()
      ? arrondi.toInt().toString()
      : arrondi.toString();
}
