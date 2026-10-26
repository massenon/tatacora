// Vue Blade maîtresse (PA-183) : pwa/crm/clients-creances.blade.php
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart';
import '../../facturation/domain/creances.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/messages_archivage_client.dart';
import 'client_dao.dart';

/// L'ARCHIVAGE et la restauration d'un client (M3, EF-M3-01) — « supprimer =
/// archiver » : `clients.actif = false`, jamais un effacement. Le **seul
/// écrivain** de `clients_local.actif`.
///
/// Réplique de `ReferentielClientService` : [verrous] en rejoue les QUATRE
/// verrous sur les données de CE poste, aux phrases du serveur :
///
///  1. un séjour non annulé dont le départ est aujourd'hui ou plus tard ;
///  2. une location de véhicule dont la fin est aujourd'hui ou plus tard
///     (ÉCART nommé : `contrats_location_local` n'a aucune colonne de statut,
///     donc un contrat annulé au serveur compte encore ici — le poste est plus
///     strict, jamais plus permissif) ;
///  3. une réservation de circuit non annulée, aujourd'hui ou plus tard ;
///  4. une facture non soldée — par le prédicat UNIQUE de `creances.dart`
///     (`CreanceFacture.estImpayee`), jamais une seconde formule de créance.
///
/// Le verrou est RECONTRÔLÉ au moment d'agir ([archiverUn]), dans la
/// transaction qui écrit : entre l'ouverture de la modale et le clic, une
/// réservation ou une facture a pu naître.
///
/// L'archivage et la restauration s'enfilent (`modification`, `actif`) : le
/// serveur les rejoue sous SA règle (`DroitArchivageService`, quatre verrous).
/// Le droit d'archiver (`regle_archivage.dart`) est tenu par l'appelant, à
/// l'ouverture ET à l'exécution ; restaurer ne l'exige pas.
///
/// @see EF-M3-01 Référentiel clients
/// @see RG-15 Journalisation — un archivage ne détruit rien
class ArchivageClients {
  ArchivageClients(
    this._db, {
    required this._creances,
    DateTime Function()? maintenant,
  }) : _maintenant = maintenant ?? DateTime.now;

  final AppDatabase _db;
  final Future<List<CreanceFacture>> Function() _creances;
  final DateTime Function() _maintenant;

  /// `ReferentielClientService::verrous` — les motifs, dans l'ordre du serveur ;
  /// vide : archivable.
  Future<List<String>> verrous(String clientId) async {
    final t = _maintenant();
    final aujourdhui = DateTime(t.year, t.month, t.day);
    bool aVenir(DateTime d) =>
        !DateTime(d.year, d.month, d.day).isBefore(aujourdhui);
    final motifs = <String>[];

    final sejours =
        (await (_db.select(_db.reservationsLocal)..where(
                  (r) =>
                      r.clientId.equals(clientId) &
                      r.statut.isNotValue('annulee'),
                ))
                .get())
            .where((r) => aVenir(r.dateDepart))
            .length;
    if (sejours > 0) {
      motifs.add(MessagesArchivageClient.verrouSejour(sejours));
    }

    final locations =
        (await (_db.select(
              _db.contratsLocationLocal,
            )..where((c) => c.clientId.equals(clientId))).get())
            .where((c) => aVenir(c.dateFin))
            .length;
    if (locations > 0) {
      motifs.add(MessagesArchivageClient.verrouLocation(locations));
    }

    final circuits =
        (await (_db.select(_db.reservationsTourLocal)..where(
                  (r) =>
                      r.clientId.equals(clientId) &
                      r.statut.isNotValue('annulee'),
                ))
                .get())
            .where((r) => aVenir(r.dateCircuit))
            .length;
    if (circuits > 0) {
      motifs.add(MessagesArchivageClient.verrouCircuit(circuits));
    }

    final impayees = (await _creances())
        .where((c) => c.piece.clientId == clientId && c.estImpayee)
        .length;
    if (impayees > 0) {
      motifs.add(MessagesArchivageClient.verrouCreance(impayees));
    }

    return motifs;
  }

  /// `ClientsCreances::confirmerArchivageClient` : compose le lot que la modale
  /// présente, pour les [ids] visés (une ligne, ou la sélection).
  ///
  /// Seuls les clients ACTIFS entrent dans le lot, triés par nom ; chacun
  /// engagé porte son motif « [nom] — [verrous] » (joints par une espace).
  /// `libelle` est le nom quand le lot n'en compte qu'UN SEUL — conservés
  /// compris —, vide sinon ; un lot sans client archivable est BLOQUÉ.
  Future<LotArchivage> composerLot(List<String> ids) async {
    final actifs =
        await (_db.select(_db.clientsLocal)..where(
                (c) =>
                    c.id.isIn(ids) & (c.actif.isNull() | c.actif.equals(true)),
              ))
              .get()
          ..sort((a, b) {
            final c = a.nom.compareTo(b.nom);
            return c != 0 ? c : a.id.compareTo(b.id);
          });

    final retenus = <String>[];
    final motifs = <String>[];
    final noms = <String>[];
    var conserves = 0;
    for (final c in actifs) {
      final nom = _nom(c.nom, c.prenom);
      noms.add(nom);
      final raisons = await verrous(c.id);
      if (raisons.isEmpty) {
        retenus.add(c.id);
        continue;
      }
      conserves++;
      motifs.add('$nom — ${raisons.join(' ')}');
    }
    return LotArchivage(
      ids: retenus,
      motifs: motifs,
      conserves: conserves,
      bloque: retenus.isEmpty,
      libelle: noms.length == 1 ? noms.first : '',
    );
  }

  /// `ReferentielClientService::archiver` : recontrôle les verrous, puis
  /// `actif = false` — et l'envoie au serveur. Lève [RefusArchivageClient] (les
  /// motifs joints par une espace) si le client est engagé.
  Future<void> archiverUn(String id) async {
    // Les verrous sont relus DANS la transaction qui écrit.
    await _db.transaction(() async {
      final c = await (_db.select(
        _db.clientsLocal,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (c == null) {
        throw const RefusArchivageClient(MessagesArchivageClient.introuvable);
      }
      final raisons = await verrous(id);
      if (raisons.isNotEmpty) {
        throw RefusArchivageClient(raisons.join(' '));
      }
      // Le serveur doit connaître le client avant de l'archiver.
      await ClientDao(_db).assurerConnuDuServeur(id);
      await (_db.update(_db.clientsLocal)..where((x) => x.id.equals(id))).write(
        const ClientsLocalCompanion(actif: Value(false)),
      );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.clients,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeArchivageClient(actif: false),
      );
    });
  }

  /// `ClientsCreances::archiverClients` : archive chaque client du lot par
  /// [archiverUn], et rend le nombre archivé ET le DERNIER refus. Un refus
  /// n'empêche PAS les autres archivages du lot.
  Future<ResultatArchivage> archiverLot(List<String> ids) async {
    final fiches = await (_db.select(
      _db.clientsLocal,
    )..where((c) => c.id.isIn(ids))).get();
    var archives = 0;
    String? refus;
    for (final c in fiches) {
      try {
        await archiverUn(c.id);
        archives++;
      } on RefusArchivageClient catch (e) {
        refus = e.message;
      }
    }
    return ResultatArchivage(archives: archives, refus: refus);
  }

  /// `ReferentielClientService::restaurer` : `actif = true`. Déjà actif : rien
  /// ne change et rien ne part. Rend le NOM du client (le message de succès le
  /// cite). Restaurer n'est PAS derrière la règle d'archivage : fermer la
  /// bascule pendant qu'un client est aux archives ne doit jamais l'y enfermer.
  Future<String> restaurer(String id) => _db.transaction(() async {
    final c = await (_db.select(
      _db.clientsLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (c == null) {
      throw const RefusArchivageClient(MessagesArchivageClient.introuvable);
    }
    if (c.actif == false) {
      await ClientDao(_db).assurerConnuDuServeur(id);
      await (_db.update(_db.clientsLocal)..where((x) => x.id.equals(id))).write(
        const ClientsLocalCompanion(actif: Value(true)),
      );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.clients,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeArchivageClient(actif: true),
      );
    }
    return _nom(c.nom, c.prenom);
  });

  static String _nom(String nom, String? prenom) =>
      [nom, prenom].whereType<String>().join(' ').trim();
}

/// Un archivage (ou une restauration) refusé : rien n'a été écrit.
final class RefusArchivageClient implements Exception {
  const RefusArchivageClient(this.message);

  final String message;

  @override
  String toString() => message;
}
