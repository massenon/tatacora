import '../entities/disponibilite.dart';
import '../entities/periode_sejour.dart';
import '../entities/reservation.dart';
import '../entities/unite_hebergement.dart';

/// Contrat du dépôt de réservations — **le seul type que la présentation
/// connaisse**.
///
/// ## Ce que ce contrat ne dit volontairement pas
///
/// Il ne dit pas si la donnée vient de la base locale ou du réseau. C'est
/// exactement ce qui rend la bascule hors ligne / en ligne invisible à
/// l'interface : aucun écran n'a de branche « si connecté ». L'implémentation
/// composite lit le local d'abord et pousse au réseau ensuite.
///
/// Aucune méthode ne renvoie de DTO ni de modèle Drift. Toujours l'entité de
/// domaine — sans quoi la forme de la base remonterait jusqu'aux widgets, et
/// changer une colonne casserait un écran.
abstract interface class ReservationRepository {
  /// Disponibilité de **toutes** les unités sur la période.
  ///
  /// Renvoie aussi les indisponibles, avec leur motif : une liste tronquée aux
  /// seules unités libres empêche de répondre à « et la Pendjari, elle est
  /// prise ? » sans changer d'écran.
  ///
  /// [exclureReservationId] écarte une réservation du calcul de conflit.
  ///
  /// **C'est indispensable à la MODIFICATION**, et le manque serait invisible
  /// à la relecture : rouvrir une réservation pour changer son acompte ferait
  /// apparaître sa propre chambre comme « occupée par le client lui-même », et
  /// l'enregistrement se refuserait au motif d'un chevauchement avec elle-même.
  Future<List<Disponibilite>> consulterDisponibilites(
    PeriodeSejour periode, {
    String? exclureReservationId,
  });

  /// Le parc, indépendamment de toute période.
  Future<List<UniteHebergement>> unites();

  /// Les réservations, de la plus récente à la plus ancienne.
  ///
  /// [seulementEnSuspens] ne retient que ce qui n'a pas encore été tranché par
  /// le serveur — c'est ce que montre l'écran « Opérations en attente ».
  Future<List<Reservation>> reservations({bool seulementEnSuspens = false});

  Future<Reservation?> parId(String id);

  /// Enregistre une réservation **localement**, SANS passer de pièce comptable.
  ///
  /// ⚠ Ce n'est PAS le chemin de la création : un acompte encaissé doit produire
  /// sa pièce dans la même transaction (règle du PO du 31/08/2026), et c'est
  /// [creer] qui le fait. `enregistrer` écrit la ligne et rien d'autre — l'écriture
  /// brute des données de démonstration et des essais. Aucun écran ne l'appelle ;
  /// un test relit le code pour que cela reste vrai.
  Future<Reservation> enregistrer(Reservation reservation);

  /// Crée une réservation ET la pièce comptable de son acompte, dans la MÊME
  /// transaction (`ReservationService::creer`). Une pièce refusée refuse la
  /// réservation entière : rien n'est écrit.
  ///
  /// [auteurId] nomme celui qui encaisse l'acompte (RG-15) : il n'est exigé que
  /// quand une pièce doit être passée, mais l'écran le fournit toujours.
  Future<Reservation> creer(
    Reservation reservation, {
    required String auteurId,
  });

  /// Met à jour une réservation **existante**, et la remet en file.
  ///
  /// Distincte d'`enregistrer` par le **type d'opération** poussé au serveur :
  /// `modification`, jamais `creation`. Réutiliser `enregistrer` marcherait
  /// localement et serait faux au serveur — il traiterait la mise à jour comme
  /// une création, et c'est la déduplication par UUID qui rattraperait
  /// l'erreur, silencieusement, jusqu'au jour où elle ne la rattraperait pas.
  Future<Reservation> modifier(Reservation reservation);

  /// Annule une réservation AVEC commission et remboursement
  /// (`AnnulationReservationService`) : la commission porte sur le montant global,
  /// le remboursement est borné par l'acompte et produit sa pièce comptable dans
  /// la même transaction.
  ///
  /// Les trois saisies sont BRUTES (celles du formulaire) ; [auteurId] nomme
  /// celui qui annule (RG-15). Lève `RefusAnnulation` — avec la phrase du serveur
  /// et le champ du formulaire — ou `RefusComptable` quand la pièce est refusée ;
  /// rien n'est alors écrit.
  Future<Reservation> annuler(
    String id, {
    required String tauxSaisi,
    required String modeRemboursement,
    required String valeurRemboursement,
    required String auteurId,
  });
}

/// La période demandée est déjà prise sur cette unité.
///
/// Levée par le contrôle **local**, qui ne voit que les réservations de ce
/// poste. Le serveur reste seul juge : lui seul voit les autres postes et pose
/// un verrou pessimiste. Un refus local est donc certain ; une acceptation
/// locale ne l'est pas.
final class ChevauchementDetecte implements Exception {
  const ChevauchementDetecte({
    required this.uniteId,
    required this.reservationEnConflit,
  });

  final String uniteId;
  final ReservationEnConflit reservationEnConflit;

  @override
  String toString() =>
      'Unité $uniteId déjà réservée par ${reservationEnConflit.clientNom} '
      'du ${reservationEnConflit.periode.arrivee} au ${reservationEnConflit.periode.depart}';
}

/// L'unité visée n'existe pas, ou n'est pas vendable.
final class UniteIndisponible implements Exception {
  const UniteIndisponible(this.message);
  final String message;
  @override
  String toString() => message;
}

/// La réservation visée est introuvable localement.
final class ReservationIntrouvable implements Exception {
  const ReservationIntrouvable(this.id);
  final String id;
  @override
  String toString() => 'Réservation $id introuvable';
}
