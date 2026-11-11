// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/relance.dart';
import 'client_dao.dart';
import '../domain/messages_relance.dart';

/// Les RELANCES des clients débiteurs (M3, EF-M3-03) — le **seul écrivain de
/// saisie** de `relances_clients_local` (la descente passe par
/// `AligneurDocuments`, qui n'enfile rien).
///
/// Réplique de `RelanceClientService::enregistrer`, refus dans son ordre et aux
/// mots du serveur : canal hors registre, client inconnu, montant négatif.
/// Une relance n'est PAS un mouvement d'argent : aucune pièce comptable
/// (`MoteurComptable` n'est pas appelé), seulement un fait daté — que le
/// serveur rejouera avec les mêmes règles (`GestionnaireRelancesClients`).
///
/// Le montant réclamé est FIGÉ en centimes au jour de l'appel : le solde vivant
/// se recalcule, la parole donnée non. La relance s'écrit et s'enfile dans UNE
/// transaction (`OperationsSyncDao.enfiler` lève hors transaction) ; elle ne se
/// modifie ni ne s'efface jamais.
///
/// @see EF-M3-03 Relances clients
class RelancesClientsDao {
  RelancesClientsDao(this._db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _maintenant;

  /// `ClientsCreances::PLAFOND` : le journal des relances est borné.
  static const int plafond = 200;

  /// `ClientsCreances::enregistrerRelance` -> `RelanceClientService::enregistrer`.
  ///
  /// [auteurLogin] est le login du compte connecté (colonne « Par »).
  Future<Relance> enregistrer({
    required String clientId,
    required String canal,
    required int montantReclameCentimes,
    DateTime? promesse,
    String? commentaire,
    String? auteurLogin,
  }) async {
    if (CanalRelance.depuisCode(canal) == null) {
      throw RefusRelance(MessagesRelance.canalInconnu(canal));
    }
    final client = await (_db.select(
      _db.clientsLocal,
    )..where((c) => c.id.equals(clientId))).getSingleOrNull();
    if (client == null) throw const RefusRelance(MessagesRelance.clientInconnu);
    if (montantReclameCentimes < 0) {
      throw const RefusRelance(MessagesRelance.montantInvalide);
    }

    final maintenant = _maintenant();
    final jour = DateTime(maintenant.year, maintenant.month, maintenant.day);
    final jourPromesse = promesse == null
        ? null
        : DateTime(promesse.year, promesse.month, promesse.day);
    final note = commentaire?.trim();
    final texte = note == null || note.isEmpty ? null : note;
    final id = _uuid.v4();

    await _db.transaction(() async {
      // Le client part avant la relance qui le cite (un client d'avant la
      // synchronisation n'a jamais été envoyé).
      await ClientDao(_db).assurerConnuDuServeur(clientId);
      await _db
          .into(_db.relancesClientsLocal)
          .insert(
            RelancesClientsLocalCompanion.insert(
              id: id,
              clientId: clientId,
              dateRelance: _iso(jour),
              canal: canal,
              montantReclameCentimes: montantReclameCentimes,
              promesse: Value(jourPromesse == null ? null : _iso(jourPromesse)),
              commentaire: Value(texte),
              creePar: Value(auteurLogin),
            ),
          );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.relancesClients,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeRelanceClient(
          clientId: clientId,
          dateRelance: jour,
          canal: canal,
          montantReclameCentimes: montantReclameCentimes,
          promesse: jourPromesse,
          commentaire: texte,
        ),
      );
    });

    return Relance(
      id: id,
      clientId: clientId,
      clientNom: _nom(client.nom, client.prenom),
      dateRelance: jour,
      canal: canal,
      montantReclameCentimes: montantReclameCentimes,
      promesse: jourPromesse,
      commentaire: texte,
      creePar: auteurLogin,
    );
  }

  /// `historiqueRelances()` : les plus récentes d'abord, [plafond] au plus.
  /// À jour égale, la dernière écrite en premier n'est pas garantie par le
  /// serveur ; le poste départage par identifiant pour un ordre stable.
  Future<List<Relance>> historique() async {
    final lignes =
        await (_db.select(_db.relancesClientsLocal)
              ..orderBy([
                (r) => OrderingTerm.desc(r.dateRelance),
                (r) => OrderingTerm.asc(r.id),
              ])
              ..limit(plafond))
            .get();
    return _versEntites(lignes);
  }

  /// Toutes les relances d'UN client (`historiqueClient()['relances']`), les
  /// plus récentes d'abord, sans plafond.
  Future<List<Relance>> deClient(String clientId) async {
    final lignes =
        await (_db.select(_db.relancesClientsLocal)
              ..where((r) => r.clientId.equals(clientId))
              ..orderBy([
                (r) => OrderingTerm.desc(r.dateRelance),
                (r) => OrderingTerm.asc(r.id),
              ]))
            .get();
    return _versEntites(lignes);
  }

  /// Toutes les relances, SANS plafond : ce que « Clients à relancer » lit pour
  /// la dernière relance de chaque client (`MAX(date_relance)` du serveur ne
  /// connaît pas le plafond du journal).
  Future<List<Relance>> toutes() async {
    final lignes = await _db.select(_db.relancesClientsLocal).get();
    return _versEntites(lignes);
  }

  Future<List<Relance>> _versEntites(List<RelanceClientLigne> lignes) async {
    final clients = {
      for (final c in await _db.select(_db.clientsLocal).get())
        c.id: _nom(c.nom, c.prenom),
    };
    return [
      for (final r in lignes)
        Relance(
          id: r.id,
          clientId: r.clientId,
          clientNom: clients[r.clientId],
          dateRelance: _jour(r.dateRelance),
          canal: r.canal,
          montantReclameCentimes: r.montantReclameCentimes,
          promesse: r.promesse == null ? null : _jour(r.promesse!),
          commentaire: r.commentaire,
          creePar: r.creePar,
        ),
    ];
  }

  static String _nom(String nom, String? prenom) =>
      [nom, prenom].whereType<String>().join(' ').trim();

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime _jour(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }
}
