import '../domain/entities/disponibilite.dart';
import '../domain/entities/periode_sejour.dart';
import '../domain/entities/reservation.dart';
import '../domain/entities/unite_hebergement.dart';
import '../domain/repositories/reservation_repository.dart';
import 'reservation_dao.dart';

/// Implémentation **locale** du dépôt — Drift seul, aucun réseau.
///
/// C'est le dépôt du jour 2-3 du sprint : tout fonctionne hors connexion, et
/// rien ne dépend d'un serveur joignable. Le dépôt composite du jour 4 viendra
/// l'envelopper, sans changer une ligne des cas d'usage ni des écrans — c'est
/// tout l'intérêt d'avoir figé le contrat avant l'implémentation.
///
/// ## La disponibilité est calculée, jamais lue dans un champ
///
/// Le `statut` d'une unité est un état **opérationnel** — ce que le personnel
/// constate. La disponibilité, elle, dépend de la période demandée et se
/// déduit des réservations (RG-02). Une unité « réservée » pour le 20 août
/// reste réservable pour le 5 septembre ; s'appuyer sur le statut interdirait
/// toute réservation à l'avance.
///
/// Seul `hors_service` immobilise l'unité quelle que soit la date : c'est
/// précisément parce qu'elle est immobilisée que son calendrier est vide.
final class ReservationRepositoryLocal implements ReservationRepository {
  const ReservationRepositoryLocal(this._dao);

  final ReservationDao _dao;

  @override
  Future<List<UniteHebergement>> unites() => _dao.unites();

  @override
  Future<List<Reservation>> reservations({bool seulementEnSuspens = false}) =>
      _dao.reservations(seulementEnSuspens: seulementEnSuspens);

  @override
  Future<Reservation?> parId(String id) => _dao.parId(id);

  @override
  Future<List<Disponibilite>> consulterDisponibilites(
    PeriodeSejour periode, {
    String? exclureReservationId,
  }) async {
    // Une seule requête pour tous les conflits de la période, puis un
    // regroupement en mémoire. L'alternative — une requête par unité —
    // multiplierait les allers-retours SQLite par la taille du parc, sur un
    // écran que le réceptionniste rafraîchit à chaque changement de date.
    final unites = await _dao.unites();
    final conflits = await _dao.chevauchant(
      periode,
      exclureReservationId: exclureReservationId,
    );

    final parUnite = <String, Reservation>{};
    for (final r in conflits) {
      // On garde le conflit le plus ancien : c'est celui qui a la priorité, et
      // c'est le nom que le réceptionniste doit citer au client.
      final existant = parUnite[r.uniteId];
      if (existant == null ||
          r.periode.arrivee.isBefore(existant.periode.arrivee)) {
        parUnite[r.uniteId] = r;
      }
    }

    return unites.map((unite) {
      if (!unite.statut.estLouable) {
        return Disponibilite.horsService(unite, periode);
      }
      final conflit = parUnite[unite.id];
      if (conflit == null) return Disponibilite.libre(unite, periode);

      return Disponibilite.occupee(
        unite,
        periode,
        reservationId: conflit.id,
        periodeOccupee: conflit.periode,
        clientNom: conflit.clientNom,
      );
    }).toList();
  }

  @override
  Future<Reservation> enregistrer(Reservation reservation) async {
    await _dao.enregistrer(reservation);
    // On relit depuis la base plutôt que de renvoyer l'objet reçu : c'est le
    // seul moyen d'affirmer que ce qui est affiché est bien ce qui est
    // persisté. Renvoyer l'entrée masquerait une écriture partielle.
    final relue = await _dao.parId(reservation.id);
    if (relue == null) {
      throw StateError(
        'La réservation ${reservation.id} n’a pas été retrouvée après écriture.',
      );
    }
    return relue;
  }

  @override
  Future<Reservation> modifier(Reservation reservation) async {
    await _dao.enregistrer(reservation);

    // Relue, jamais rendue telle qu'écrite : c'est la base qui fait foi, et
    // c'est ainsi qu'on constate ce qui a réellement été persisté.
    final relue = await _dao.parId(reservation.id);
    if (relue == null) {
      throw StateError(
        'La réservation ${reservation.id} n’a pas été retrouvée après '
        'modification.',
      );
    }
    return relue;
  }

  @override
  Future<Reservation> creer(
    Reservation reservation, {
    required String auteurId,
  }) async {
    await _dao.creer(reservation, auteurId: auteurId);
    final relue = await _dao.parId(reservation.id);
    if (relue == null) {
      throw StateError(
        'La réservation ${reservation.id} n’a pas été retrouvée après création.',
      );
    }
    return relue;
  }

  @override
  Future<Reservation> annuler(
    String id, {
    required String tauxSaisi,
    required String modeRemboursement,
    required String valeurRemboursement,
    required String auteurId,
  }) => _dao.annulerAvecConditions(
    id,
    tauxSaisi: tauxSaisi,
    modeRemboursement: modeRemboursement,
    valeurRemboursement: valeurRemboursement,
    auteurId: auteurId,
  );
}
