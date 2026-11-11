import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/fiche_reservation.dart';
import '../domain/messages_canaux.dart';

/// Les CANAUX de réservation du poste (Paramètres › « Canaux de réservation ») —
/// le **seul écrivain** de `canaux_reservation_local` (avec son alignement
/// descendant, [inscrireDescendu], qui n'enfile jamais).
///
/// Vue Blade maîtresse (PA-183) : pwa/transverse/parametres.blade.php
///
/// Réplique de `CanalReservationService` : trois gestes fermés — [ajouter],
/// [renommer], [basculer] — et AUCUNE suppression (« un canal utilisé ne se
/// supprime pas, il se désactive »). Le nom est unique sans tenir compte de la
/// casse. Chaque geste s'écrit ET s'enfile dans UNE transaction
/// (`OperationsSyncDao`) : le serveur reçoit le nom, l'ancien nom d'un
/// renommage, et l'état.
///
/// ## Le jeu initial
///
/// Un poste vierge n'a aucune ligne : [tous] pose alors le jeu initial du maître
/// (`CanalReservation.jeuInitial`) sous des identifiants DÉTERMINISTES (UUID v5
/// du code) — le serveur exige un UUID pour pousser, et deux postes qui posent
/// le jeu aboutissent au même identifiant. Rien n'est enfilé : le serveur sème
/// les mêmes noms, et ce qui descend s'aligne par le NOM.
///
/// ## Les réservations d'avant la v35
///
/// Leur colonne `canal` porte les codes `can-…` du jeu initial. [tous] les
/// remplace par l'identifiant du canal de même NOM, quand la table le détient —
/// sans rien envoyer : le nom d'une réservation ne change pas. Tant que la
/// migration n'a pas eu lieu, le code se lit encore (`CanalReservation.memeQue`).
class CanauxReservationDao {
  CanauxReservationDao(this._db, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final AppDatabase _db;
  final Uuid _uuid;

  OperationsSyncDao get _file => OperationsSyncDao(_db);

  $CanauxReservationLocalTable get _table => _db.canauxReservationLocal;

  /// L'identifiant d'un canal du jeu initial : stable d'un poste à l'autre.
  static String idInitial(CanalReservation canal) => const Uuid().v5(
    Namespace.url.value,
    'tatacora/canal-reservation/${canal.code}',
  );

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// Tous les canaux, désactivés compris, dans leur ordre — et le jeu initial
  /// posé s'il manque (voir l'en-tête).
  Future<List<CanalReservation>> tous() async {
    await assurerJeuInitial();
    return [for (final c in await _lignes()) _versCanal(c)];
  }

  /// Les canaux tels que la table les tient, SANS rien écrire : la lecture des
  /// réservations (liste, fiche, contrôle de chevauchement) ne pose pas le jeu
  /// initial. Vide sur un poste vierge — l'appelant retombe alors sur le code.
  Future<List<CanalReservation>> lus() async => [
    for (final c in await _lignes()) _versCanal(c),
  ];

  /// Le canal qu'une colonne `reservations_local.canal` désigne : par
  /// identifiant, sinon — réservation d'avant la v35 — par le code `can-…` du
  /// jeu initial. `null` quand la valeur est vide ou inconnue : une valeur
  /// absente reste absente, jamais un repli sur « Physique » (l'analyse par
  /// canal deviendrait fausse).
  static CanalReservation? designe(
    String? valeur,
    List<CanalReservation> canaux,
  ) {
    if (valeur == null) return null;
    for (final c in canaux) {
      if (c.code == valeur) return c;
    }
    for (final c in CanalReservation.jeuInitial) {
      if (c.code == valeur) return c;
    }
    return null;
  }

  /// Les canaux PROPOSABLES à la saisie : les actifs, PLUS celui déjà retenu par
  /// la fiche rouverte (un canal désactivé après coup ne disparaît pas d'une
  /// réservation qui le porte — `CanalReservation::proposables`).
  Future<List<CanalReservation>> proposables({CanalReservation? retenu}) async {
    final tous = await this.tous();
    return [
      for (final c in tous)
        if (c.actif || c.memeQue(retenu)) c,
    ];
  }

  /// Le nombre de réservations de chaque canal (identifiant → nombre), codes
  /// d'avant la v35 compris. Un canal sans réservation est absent.
  Future<Map<String, int>> reservationsParCanal() async {
    final lignes = await _db
        .customSelect(
          'SELECT canal, COUNT(*) AS n FROM reservations_local '
          'WHERE canal IS NOT NULL GROUP BY canal',
          readsFrom: {_db.reservationsLocal},
        )
        .get();
    final parValeur = {
      for (final l in lignes) l.data['canal'] as String: l.data['n'] as int,
    };
    final comptes = <String, int>{};
    for (final c in await _lignes()) {
      final ancien = CanalReservation.jeuInitial
          .where((j) => j.libelle.toLowerCase() == c.nom.trim().toLowerCase())
          .map((j) => j.code);
      final n =
          (parValeur[c.id] ?? 0) +
          ancien.fold<int>(0, (t, code) => t + (parValeur[code] ?? 0));
      if (n > 0) comptes[c.id] = n;
    }
    return comptes;
  }

  Future<List<CanalReservationLigne>> _lignes() =>
      (_db.select(_table)..orderBy([
            (c) => OrderingTerm.asc(c.ordre),
            (c) => OrderingTerm.asc(c.nom),
          ]))
          .get();

  CanalReservation _versCanal(CanalReservationLigne c) =>
      CanalReservation(c.id, c.nom, actif: c.actif);

  /* ================================================================== */
  /* Le jeu initial                                                      */
  /* ================================================================== */

  /// Pose le jeu initial sur une table VIDE, puis remplace les codes `can-…`
  /// des réservations d'avant la v35 par l'identifiant du canal de même nom.
  /// Idempotent ; n'enfile rien.
  Future<void> assurerJeuInitial() => _db.transaction(() async {
    final existantes = await _lignes();
    if (existantes.isEmpty) {
      var rang = 0;
      for (final c in CanalReservation.jeuInitial) {
        await _db
            .into(_table)
            .insert(
              CanauxReservationLocalCompanion.insert(
                id: idInitial(c),
                nom: c.libelle,
                ordre: Value(rang++),
              ),
            );
      }
    }
    // Rien à migrer : la requête ci-dessous ne tourne que s'il reste un code.
    final restants = await _db
        .customSelect(
          "SELECT COUNT(*) AS n FROM reservations_local WHERE canal LIKE 'can-%'",
          readsFrom: {_db.reservationsLocal},
        )
        .getSingle();
    if ((restants.data['n'] as int) == 0) return;
    final lignes = existantes.isEmpty ? await _lignes() : existantes;
    for (final ancien in CanalReservation.jeuInitial) {
      final cible = lignes
          .where(
            (c) => c.nom.trim().toLowerCase() == ancien.libelle.toLowerCase(),
          )
          .firstOrNull;
      if (cible == null) continue;
      await _db.customUpdate(
        'UPDATE reservations_local SET canal = ? WHERE canal = ?',
        variables: [
          Variable.withString(cible.id),
          Variable.withString(ancien.code),
        ],
        updates: {_db.reservationsLocal},
      );
    }
  });

  /* ================================================================== */
  /* Les trois gestes                                                    */
  /* ================================================================== */

  String _normaliser(String nom) {
    final net = nom.trim();
    if (net.isEmpty) throw const RefusCanal(MessagesCanaux.nomRequis);
    if (net.length > MessagesCanaux.longueurMax) {
      throw const RefusCanal(MessagesCanaux.nomTropLong);
    }
    return net;
  }

  Future<void> _refuserSiDoublon(String nom, {String? sauf}) async {
    final cle = nom.toLowerCase();
    for (final c in await _lignes()) {
      if (c.id != sauf && c.nom.trim().toLowerCase() == cle) {
        throw RefusCanal(MessagesCanaux.nomDejaUtilise(nom));
      }
    }
  }

  /// « Ajouter un canal » : actif d'emblée, en fin de liste.
  Future<CanalReservation> ajouter(String nom) => _db.transaction(() async {
    await assurerJeuInitial();
    final net = _normaliser(nom);
    await _refuserSiDoublon(net);
    final id = _uuid.v4();
    final rang = (await _lignes()).fold<int>(
      -1,
      (m, c) => c.ordre > m ? c.ordre : m,
    );
    await _db
        .into(_table)
        .insert(
          CanauxReservationLocalCompanion.insert(
            id: id,
            nom: net,
            ordre: Value(rang + 1),
          ),
        );
    await _file.enfiler(
      table: TableSynchronisee.canauxReservation,
      entiteId: id,
      type: TypeOperationSync.creation,
      payload: chargeCanalReservation(nom: net, actif: true),
    );
    return CanalReservation(id, net);
  });

  /// « Renommer » : les réservations déjà saisies suivent (elles citent
  /// l'identifiant, le serveur de même) — l'ancien libellé n'est pas conservé
  /// ici, il n'est dénormalisé nulle part.
  Future<CanalReservation> renommer(String id, String nom) =>
      _db.transaction(() async {
        final canal = await _parId(id);
        final net = _normaliser(nom);
        await _refuserSiDoublon(net, sauf: id);
        if (net == canal.nom) return _versCanal(canal);
        await (_db.update(_table)..where((c) => c.id.equals(id))).write(
          CanauxReservationLocalCompanion(nom: Value(net)),
        );
        await _file.enfiler(
          table: TableSynchronisee.canauxReservation,
          entiteId: id,
          type: TypeOperationSync.modification,
          payload: chargeCanalReservationModifie(
            nom: net,
            ancienNom: canal.nom,
            actif: canal.actif,
          ),
        );
        return CanalReservation(id, net, actif: canal.actif);
      });

  /// « Désactiver » / « Réactiver » : un canal ne s'efface jamais.
  Future<CanalReservation> basculer(String id) => _db.transaction(() async {
    final canal = await _parId(id);
    final actif = !canal.actif;
    await (_db.update(_table)..where((c) => c.id.equals(id))).write(
      CanauxReservationLocalCompanion(actif: Value(actif)),
    );
    await _file.enfiler(
      table: TableSynchronisee.canauxReservation,
      entiteId: id,
      type: TypeOperationSync.modification,
      payload: chargeCanalReservationModifie(nom: canal.nom, actif: actif),
    );
    return CanalReservation(id, canal.nom, actif: actif);
  });

  Future<CanalReservationLigne> _parId(String id) async {
    final c = await (_db.select(
      _table,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (c == null) throw const RefusCanal(MessagesCanaux.introuvable);
    return c;
  }

  /* ================================================================== */
  /* La descente                                                         */
  /* ================================================================== */

  /// Un canal DESCENDU du serveur, sous [id] (local), créé s'il manque — sans
  /// rien renvoyer. Seul appelant : l'aligneur du catalogue.
  Future<void> inscrireDescendu({
    required String id,
    required String nom,
    required bool actif,
  }) async {
    final existant = await (_db.select(
      _table,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    if (existant != null) {
      await (_db.update(_table)..where((c) => c.id.equals(id))).write(
        CanauxReservationLocalCompanion(nom: Value(nom), actif: Value(actif)),
      );
      return;
    }
    final rang = (await _lignes()).fold<int>(
      -1,
      (m, c) => c.ordre > m ? c.ordre : m,
    );
    await _db
        .into(_table)
        .insert(
          CanauxReservationLocalCompanion.insert(
            id: id,
            nom: nom,
            actif: Value(actif),
            ordre: Value(rang + 1),
          ),
        );
  }

  /// Le canal de ce nom (insensible à la casse), ou `null`.
  Future<CanalReservationLigne?> parNom(String nom) async {
    final cle = nom.trim().toLowerCase();
    for (final c in await _lignes()) {
      if (c.nom.trim().toLowerCase() == cle) return c;
    }
    return null;
  }
}
