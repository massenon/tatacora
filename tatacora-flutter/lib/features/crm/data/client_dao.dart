import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/tables/clients_table.dart';
import '../../synchronisation/data/documents_autres_postes.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/client.dart';

part 'client_dao.g.dart';

/// Accès Drift au référentiel client (M3).
///
/// ## Le client reste sur ce poste — ZÉRO RÉSEAU (14/09/2026)
///
/// ⚠ Ce fichier a longtemps expliqué l'inverse, et l'explication vaut d'être
/// gardée pour ce qu'elle apprend. `clients` était au registre
/// `TABLES_SYNCHRONISABLES` du serveur : un client créé au comptoir devait
/// partir **avant la réservation qui le référence**, sans quoi le serveur
/// rejetait celle-ci sur une clé étrangère vers un client inconnu (PA-116,
/// PA-127). L'ordre était garanti par l'horodatage de la file.
///
/// Depuis la décision du Product Owner, il n'y a plus de file, plus de serveur,
/// et donc plus d'ordre à garantir : le client est écrit ici, et c'est tout.
/// `statutSync` vaut `local` — surtout pas `en_attente_synchronisation`, qui
/// afficherait une attente que rien ne viendra jamais lever.
///
/// ## Ce que la disparition du serveur EMPORTE avec elle
///
/// Le RBAC par opération (PA-65) s'appliquait au moment de la poussée : un
/// réceptionniste sans droit `C` sur M3 voyait son client refusé par le
/// serveur, et l'écran masquait le bouton en **contrepartie visible** de ce
/// refus. Ce filet-là n'existe plus. Le masquage RBAC de l'écran est désormais
/// le SEUL contrôle : plus rien, en aval, ne rattrapera une écriture indue.
@DriftAccessor(tables: [ClientsLocal])
class ClientDao extends DatabaseAccessor<AppDatabase> with _$ClientDaoMixin {
  ClientDao(super.db);

  static const _uuid = Uuid();

  /// Tous les clients du poste, par ordre alphabétique.
  Future<List<Client>> clients() async {
    final lignes =
        await (select(clientsLocal)..orderBy([
              (c) => OrderingTerm.asc(c.nom),
              (c) => OrderingTerm.asc(c.prenom),
            ]))
            .get();
    return lignes.map(_versEntite).toList(growable: false);
  }

  Future<Client?> parId(String id) async {
    final ligne = await (select(
      clientsLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return ligne == null ? null : _versEntite(ligne);
  }

  /// Crée un client **et** son entrée de file, dans la même transaction.
  ///
  /// Les séparer ouvrirait une fenêtre — courte, mais réelle — où
  /// l'application peut être tuée entre les deux : le client existerait
  /// localement sans que rien ne le pousse, et la première réservation qui le
  /// référence serait rejetée par le serveur, définitivement.
  Future<Client> creer({
    required String nom,
    required String telephone,
    required TypeClientReferentiel type,
    String? prenom,
    String? email,
  }) async {
    final client = Client(
      id: _uuid.v4(),
      nom: nom.trim(),
      prenom: (prenom?.trim().isEmpty ?? true) ? null : prenom!.trim(),
      telephone: telephone.trim(),
      email: (email?.trim().isEmpty ?? true) ? null : email!.trim(),
      type: type,
    );

    await transaction(() async {
      await into(clientsLocal).insert(
        ClientsLocalCompanion.insert(
          id: client.id,
          nom: client.nom,
          prenom: Value(client.prenom),
          telephone: client.telephone,
          email: Value(client.email),
          typeClient: client.type.code,
          // ZÉRO RÉSEAU depuis le 14/09/2026 : ce client est **enregistré sur
          // ce poste**, et il n'attend rien.
          //
          // La valeur était `en_attente_synchronisation`, et la file qui la
          // suivait vient d'être supprimée (v10). La laisser ferait dire à la
          // fiche « en attente de synchronisation » pour toujours — l'attente
          // sans fin que PA-59/60/61 condamnent, et la raison même pour
          // laquelle la file a été retirée plutôt que laissée à grossir.
          statutSync: const Value('local'),
        ),
      );
      // Lot F1 (15/10/2026) : la file d'envoi revient, en tâche de fond. Le
      // client part au serveur dans CETTE transaction. `statut_sync` reste
      // `local` : aucun écran n'annonce d'attente tant que le moteur d'envoi
      // (F2) n'existe pas.
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.clients,
        entiteId: client.id,
        type: TypeOperationSync.creation,
        payload: chargeClient(
          nom: client.nom,
          prenom: client.prenom,
          telephone: client.telephone,
          email: client.email,
          typeClient: client.type.code,
        ),
      );
    });

    return client;
  }

  /// Écrit des clients **venus du serveur**, sans entrée de file (PA-127).
  ///
  /// Les renvoyer serait une boucle : ils viennent de là. Et leur `statutSync`
  /// vaut `synchronise`, ce qui est vrai — le marquer « en attente » ferait
  /// annoncer par le bandeau un travail qui n'existe pas (PA-59/60/61).
  ///
  /// L'écriture est un **upsert** : une fiche corrigée au serveur doit
  /// remplacer la copie locale, sinon la correction ne redescendrait jamais.
  /// Une saisie locale non encore poussée est **épargnée** — c'est la seule
  /// copie qui existe, et l'écraser la perdrait définitivement.
  Future<int> aligner(List<Client> distants) async {
    if (distants.isEmpty) return 0;

    final enAttente = {
      for (final c in await clients())
        if (c.enAttenteDeSynchronisation) c.id,
    };

    var ecrits = 0;
    await transaction(() async {
      for (final c in distants) {
        if (enAttente.contains(c.id)) continue;

        await into(clientsLocal).insertOnConflictUpdate(
          ClientsLocalCompanion.insert(
            id: c.id,
            nom: c.nom,
            prenom: Value(c.prenom),
            telephone: c.telephone,
            email: Value(c.email),
            typeClient: c.type.code,
            statutSync: const Value('synchronise'),
          ),
        );
        ecrits++;
      }
    });

    return ecrits;
  }

  /// Le serveur doit connaître le client avant tout geste qui le CITE ou le
  /// MODIFIE (une relance, un archivage) : sans cela, le serveur répondrait
  /// « client inconnu » à chaque tentative. Un client d'avant la
  /// synchronisation (v26) n'a jamais été envoyé : sa CRÉATION s'enfile alors,
  /// avec ses valeurs courantes (et son archivage, s'il est archivé), AVANT le
  /// geste — `seq` fait l'ordre. À appeler DANS la transaction du geste
  /// (`enfiler` lève sinon). Inconnu de ce poste : rien.
  Future<void> assurerConnuDuServeur(String id) async {
    final c = await (select(
      clientsLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    if (c == null) return;
    // Connu : descendu (origine retenue), ou créé ici et sa création est dans
    // la file, ou écrit par la descente avant la v35 (`statut_sync` =
    // `synchronise` — les saisies de ce poste, elles, valent `local`).
    if (c.statutSync == 'synchronise' ||
        await DocumentsAutresPostes(
          attachedDatabase,
        ).connuDuServeur(TableSynchronisee.clients, id)) {
      return;
    }
    final file = OperationsSyncDao(attachedDatabase);
    await file.enfiler(
      table: TableSynchronisee.clients,
      entiteId: id,
      type: TypeOperationSync.creation,
      payload: chargeClient(
        nom: c.nom,
        prenom: c.prenom,
        telephone: c.telephone,
        email: c.email,
        typeClient: c.typeClient,
      ),
    );
    if (c.actif == false) {
      await file.enfiler(
        table: TableSynchronisee.clients,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeArchivageClient(actif: false),
      );
    }
  }

  Client _versEntite(ClientsLocalData d) => Client(
    id: d.id,
    nom: d.nom,
    prenom: d.prenom,
    telephone: d.telephone,
    email: d.email,
    type: TypeClientReferentiel.parCode(d.typeClient),
    solde: d.solde,
    statutSync: d.statutSync,
    actif: d.actif != false,
  );
}
