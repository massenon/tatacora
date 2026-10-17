import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/messages_sejour.dart';
import 'parc_dao.dart' show StatutUniteLocal;

/// Check-in, check-out — RÉPLIQUE LOCALE de `SejourService` du serveur
/// (14/10/2026, lot C du plan du PO, décision du Lead D408).
///
/// **SEUL auteur de `sejours_local`.** Il écrit aussi, comme le service du
/// serveur, `reservations_local.statut` (`en_cours` au check-in, `terminee` au
/// check-out) et `unites_hebergement_local.statut` (`occupee`, `nettoyage`) :
/// ce sont les trois gestes qui font réellement avancer le cycle de l'unité.
///
/// ## Les refus du serveur, dans SON ordre
///
/// Check-in (`SejourService::checkin`) : réservation annulée → séjour déjà
/// commencé → (écriture du séjour et du statut de la réservation) → unité hors
/// service. Le dernier refus tombe APRÈS les premières écritures, dans la même
/// transaction : il les emporte, comme `DB::transaction` au serveur.
///
/// Check-out (`Accueil::confirmerCheckout` puis `SejourService::checkout`) :
/// aucun séjour OUVERT pour la réservation → « départ déjà enregistré le . »
/// (date vide, comme le composant) ; séjour sans arrivée → même phrase ; puis
/// l'unité hors service, qui emporte tout.
///
/// ## Ce qui n'est PAS ici
///
/// « Ménage terminé » (`SejourService::marquerNettoyee`) reste
/// `ParcDao.marquerNettoyee`, déjà appelé par le plan d'hébergement : un second
/// écrivain du même geste serait le défaut « deux auteurs » (PA-161). Écart
/// résiduel nommé : le serveur REFUSE une unité qui n'est pas en nettoyage
/// (`sejour.pas_en_nettoyage`), `ParcDao` la remet à `libre` sans rien dire
/// (le bouton n'est rendu que sur une unité en nettoyage).
///
/// ## Aucun mixin généré
///
/// Même forme que `PaiementsFactureDao` : les tables sont enregistrées par la
/// base, `attachedDatabase` suffit — aucun `part`, donc aucun mixin vide
/// possible.
///
/// @see EF-M1-03 Check-in
/// @see EF-M1-04 Check-out
/// @see RG-02 Disponibilité toujours calculée, jamais stockée
class SejourDao extends DatabaseAccessor<AppDatabase> {
  SejourDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : l'heure d'arrivée et de départ en dépend, et un test qui lit
  /// l'horloge réelle change de résultat chaque minute.
  final DateTime Function() _maintenant;

  $SejoursLocalTable get _sejours => attachedDatabase.sejoursLocal;
  $ReservationsLocalTable get _reservations =>
      attachedDatabase.reservationsLocal;
  $UnitesHebergementLocalTable get _unites =>
      attachedDatabase.unitesHebergementLocal;

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// Les réservations dont le séjour est OUVERT — `Accueil::sejoursEnCours()` :
  /// `whereNull('date_checkout_reel')`, et rien d'autre. C'est ce qui décide,
  /// ligne par ligne, du bouton « Check-out » plutôt que « Check-in ».
  Future<Set<String>> reservationsAuSejourOuvert() async {
    final lignes = await (select(
      _sejours,
    )..where((s) => s.dateCheckoutReel.isNull())).get();
    return {for (final s in lignes) s.reservationId};
  }

  /// Les arrivées du jour SANS check-in enregistré — `AlertesOuverture::
  /// alertesReservations()` : réservation non annulée, arrivée AUJOURD'HUI,
  /// aucun séjour dont `date_checkin_reel` est renseignée ; la plus
  /// anciennement créée d'abord ; plafonnée à [plafond].
  ///
  /// Le nom rendu est celui du serveur : `trim(prenom . ' ' . nom)` — le
  /// PRÉNOM d'abord (l'inverse de la colonne « Client » de l'accueil).
  Future<List<ArriveeSansCheckIn>> arriveesSansCheckIn(
    DateTime maintenant, {
    required int plafond,
  }) async {
    final pointees = {
      for (final s in await (select(
        _sejours,
      )..where((s) => s.dateCheckinReel.isNotNull())).get())
        s.reservationId,
    };
    final candidates =
        (await (select(_reservations)
                  ..where((r) => r.statut.equals('annulee').not())
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.dateCreationLocale),
                    (r) => OrderingTerm.asc(r.id),
                  ]))
                .get())
            .where(
              (r) =>
                  !pointees.contains(r.id) &&
                  _memeJour(r.dateArrivee, maintenant),
            )
            .take(plafond)
            .toList();
    if (candidates.isEmpty) return const [];

    final clients = attachedDatabase.clientsLocal;
    final fiches = {
      for (final c in await (select(
        clients,
      )..where((c) => c.id.isIn(candidates.map((r) => r.clientId)))).get())
        c.id: c,
    };
    return [
      for (final r in candidates)
        ArriveeSansCheckIn(
          reservationId: r.id,
          client: switch (fiches[r.clientId]) {
            null => null,
            final c => '${c.prenom ?? ''} ${c.nom}'.trim(),
          },
        ),
    ];
  }

  /// La réservation à pointer sur une UNITÉ — `Hebergement::reservationDuJour`
  /// du plan d'hébergement : même unité, non annulée, arrivée au plus
  /// aujourd'hui, départ après aujourd'hui, la plus ancienne arrivée d'abord.
  /// `null` : aucune arrivée attendue (le plan le DIT,
  /// `hebergement.checkin_impossible`). Le nom rendu est `nomComplet()` du
  /// serveur : `trim(prenom . ' ' . nom)` (lot D, 14/10/2026, D416).
  Future<({String reservationId, String? client})?> reservationDuJourDeLUnite(
    String uniteId,
  ) async {
    final aujourdhui = _jour(_maintenant());
    final candidates =
        (await (select(_reservations)
                  ..where(
                    (r) =>
                        r.uniteId.equals(uniteId) &
                        r.statut.equals('annulee').not(),
                  )
                  ..orderBy([
                    (r) => OrderingTerm.asc(r.dateArrivee),
                    (r) => OrderingTerm.asc(r.id),
                  ]))
                .get())
            .where(
              (r) =>
                  !_jour(r.dateArrivee).isAfter(aujourdhui) &&
                  _jour(r.dateDepart).isAfter(aujourdhui),
            );
    if (candidates.isEmpty) return null;
    final r = candidates.first;
    final fiche = await (select(
      attachedDatabase.clientsLocal,
    )..where((c) => c.id.equals(r.clientId))).getSingleOrNull();
    return (
      reservationId: r.id,
      client: fiche == null
          ? null
          : '${fiche.prenom ?? ''} ${fiche.nom}'.trim(),
    );
  }

  /// La réservation du séjour EN COURS sur une unité —
  /// `SejourService::sejourEnCours($unite)` : séjour sans départ réel dont la
  /// réservation porte l'unité. `null` : aucun séjour en cours (le plan le
  /// DIT, `hebergement.checkout_impossible`).
  Future<String?> reservationAuSejourEnCoursDeLUnite(String uniteId) async {
    final ouverts = await (select(
      _sejours,
    )..where((s) => s.dateCheckoutReel.isNull())).get();
    if (ouverts.isEmpty) return null;
    final reservations =
        await (select(_reservations)..where(
              (r) =>
                  r.uniteId.equals(uniteId) &
                  r.id.isIn(ouverts.map((s) => s.reservationId)),
            ))
            .get();
    return reservations.isEmpty ? null : reservations.first.id;
  }

  /// Le jour civil d'une date (les dates de séjour sont stockées à minuit).
  static DateTime _jour(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /* ================================================================== */
  /* Écritures                                                           */
  /* ================================================================== */

  /// Enregistre l'arrivée réelle — `SejourService::checkin`.
  ///
  /// @throws RefusSejour réservation inconnue ou annulée, séjour déjà
  ///   commencé, unité hors service (rien n'est écrit)
  Future<void> checkin(String reservationId) => transaction(() async {
    final reservation = await (select(
      _reservations,
    )..where((r) => r.id.equals(reservationId))).getSingleOrNull();
    if (reservation == null) {
      throw const RefusSejour(MessagesSejour.reservationIntrouvable);
    }

    if (reservation.statut == 'annulee') {
      throw const RefusSejour(MessagesSejour.reservationAnnulee);
    }

    // `Sejour::where('reservation_id', …)->first()` : un séjour, ouvert OU
    // clos — une réservation ne se pointe qu'une fois.
    final existant =
        await (select(_sejours)
              ..where((s) => s.reservationId.equals(reservationId))
              ..limit(1))
            .getSingleOrNull();
    if (existant != null) {
      final date = existant.dateCheckinReel;
      throw RefusSejour(
        MessagesSejour.dejaArrive(
          date == null ? '' : dateHeureCommeServeur(date),
        ),
      );
    }

    final maintenant = _maintenant();
    final id = _uuid.v4();
    await into(_sejours).insert(
      SejoursLocalCompanion.insert(
        id: id,
        reservationId: reservationId,
        dateCheckinReel: Value(maintenant),
        // Tableau vide plutôt que `null` : « aucun occupant relevé » et
        // « champ jamais renseigné » ne doivent pas se ressembler (serveur).
        occupants: const Value('[]'),
        dateCreation: maintenant,
        dateModification: maintenant,
      ),
    );

    await (update(_reservations)..where((r) => r.id.equals(reservationId)))
        .write(const ReservationsLocalCompanion(statut: Value('en_cours')));

    await _changerStatutUnite(reservation.uniteId, StatutUniteLocal.occupee);

    // Lot F5 : l'arrivée part au serveur (`SejourService::checkin`), à
    // l'heure réelle du poste.
    await OperationsSyncDao(attachedDatabase).enfiler(
      table: TableSynchronisee.sejours,
      entiteId: id,
      type: TypeOperationSync.creation,
      payload: chargeArrivee(reservationId: reservationId, arrivee: maintenant),
      horodatage: maintenant,
    );
  });

  /// Enregistre le départ réel — `Accueil::confirmerCheckout` puis
  /// `SejourService::checkout`. L'unité passe en NETTOYAGE, jamais en
  /// « libre » : elle n'est pas prête tant que le ménage n'est pas fait.
  ///
  /// @throws RefusSejour aucun séjour ouvert, séjour sans arrivée, unité hors
  ///   service (rien n'est écrit)
  Future<void> checkout(String reservationId) => transaction(() async {
    final ouvert =
        await (select(_sejours)
              ..where(
                (s) =>
                    s.reservationId.equals(reservationId) &
                    s.dateCheckoutReel.isNull(),
              )
              ..limit(1))
            .getSingleOrNull();
    if (ouvert == null) {
      // `__('sejour.deja_parti', ['date' => ''])` — la phrase du composant,
      // date VIDE comprise.
      throw RefusSejour(MessagesSejour.dejaParti(''));
    }

    // `! $verrouille->estEnCours()` : arrivée renseignée ET départ absent.
    if (ouvert.dateCheckinReel == null) {
      throw RefusSejour(MessagesSejour.dejaParti(''));
    }

    final maintenant = _maintenant();
    await (update(_sejours)..where((s) => s.id.equals(ouvert.id))).write(
      SejoursLocalCompanion(
        dateCheckoutReel: Value(maintenant),
        dateModification: Value(maintenant),
      ),
    );

    final reservation = await (select(
      _reservations,
    )..where((r) => r.id.equals(reservationId))).getSingle();
    await (update(_reservations)..where((r) => r.id.equals(reservationId)))
        .write(const ReservationsLocalCompanion(statut: Value('terminee')));

    await _changerStatutUnite(reservation.uniteId, StatutUniteLocal.nettoyage);

    // Lot F5 : le départ part au serveur (`SejourService::checkout`).
    await OperationsSyncDao(attachedDatabase).enfiler(
      table: TableSynchronisee.sejours,
      entiteId: ouvert.id,
      type: TypeOperationSync.modification,
      payload: chargeDepart(depart: maintenant),
      horodatage: maintenant,
    );
  });

  /// `SejourService::changerStatutUnite` — une unité hors service n'est
  /// JAMAIS touchée : la maintenance prime, et le refus emporte la transaction.
  Future<void> _changerStatutUnite(String uniteId, String statut) async {
    final unite = await (select(
      _unites,
    )..where((u) => u.id.equals(uniteId))).getSingle();
    if (unite.statut == StatutUniteLocal.horsService) {
      throw RefusSejour(MessagesSejour.uniteHorsService(unite.numero));
    }
    await (update(_unites)..where((u) => u.id.equals(uniteId))).write(
      UnitesHebergementLocalCompanion(statut: Value(statut)),
    );
  }

  /// `whereDate(date_arrivee, today)` : la date d'arrivée est stockée à minuit
  /// UTC (`PeriodeSejour`) ; on compare ses composantes au JOUR de [maintenant].
  static bool _memeJour(DateTime stockee, DateTime maintenant) =>
      stockee.year == maintenant.year &&
      stockee.month == maintenant.month &&
      stockee.day == maintenant.day;
}

/// Une arrivée du jour sans check-in : la réservation et le nom du client
/// (`null` : fiche introuvable — « Client inconnu » au serveur).
final class ArriveeSansCheckIn {
  const ArriveeSansCheckIn({required this.reservationId, required this.client});

  final String reservationId;
  final String? client;
}
