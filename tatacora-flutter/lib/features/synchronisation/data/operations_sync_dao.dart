import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../domain/operation_sync.dart';

/// Le SEUL auteur de `operations_sync_local` (schéma v26, lot F1 du
/// 15/10/2026).
///
/// ## `enfiler` : dans la transaction de l'écriture métier, ou pas du tout
///
/// Une donnée non synchronisée est la seule copie qui existe. Si l'écriture
/// métier et son entrée de file étaient deux transactions, un poste coupé
/// entre les deux garderait une vente que rien ne pousse — ou, dans l'autre
/// ordre, pousserait une vente que le poste n'a pas. [enfiler] LÈVE donc
/// lorsqu'il n'est pas appelé à l'intérieur d'une transaction Drift : chaque
/// écrivain l'appelle depuis son propre `transaction(() async { … })`, et un
/// refus de l'un défait l'autre.
///
/// ## Ce que le DAO garantit sur le contenu
///
///  * le payload est sérialisé ICI, au moment de l'écriture : c'est un
///    instantané figé, jamais relu de la base au moment de l'envoi ;
///  * une `modification` n'est enfilée que sur une table dont le gestionnaire
///    serveur l'accepte ([TableSynchronisee.accepteModification]) ;
///  * une `modification` sans aucun champ changé n'est pas enfilée (rien à
///    dire au serveur) ;
///  * le mode démonstration n'enfile rien
///    ([AppDatabase.fileSynchronisationActive]).
///
/// ## L'ordre d'envoi
///
/// `seq` est global, croissant, jamais réutilisé : un référentiel écrit avant
/// le document qui le cite part avant lui. [reclamerLot] le respecte
/// strictement — il s'arrête à la première opération dont le repli n'est pas
/// échu, pour qu'un document ne double jamais l'élément qu'il cite.
class OperationsSyncDao extends DatabaseAccessor<AppDatabase> {
  OperationsSyncDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _maintenant;

  $OperationsSyncLocalTable get _operations =>
      attachedDatabase.operationsSyncLocal;

  /// Sommes-nous DANS une transaction Drift de cette base ?
  ///
  /// Drift remplace, dans la zone d'un `transaction()`, le moteur de la base
  /// par celui de la transaction ; hors transaction, il rend la base même.
  /// C'est la seule façon de le savoir sans exiger de chaque écrivain qu'il
  /// transmette un jeton — et un test l'éprouve dans les deux sens.
  bool get _dansUneTransaction =>
      // ignore: invalid_use_of_internal_member
      !identical(attachedDatabase.resolvedEngine, attachedDatabase);

  /* ================================================================== */
  /* Écriture — l'enfilement, appelé par les écrivains métier            */
  /* ================================================================== */

  /// Dépose UNE opération dans la file et rend son `uuid_operation` — ou
  /// `null` quand rien n'est enfilé (mode démonstration, ou modification sans
  /// champ changé).
  ///
  /// [horodatage] est l'instant de la SAISIE (il arbitre le dernier écrit
  /// gagnant au serveur) ; [dateMetier] la date du document (`AAAA-MM-JJ`).
  ///
  /// @throws StateError appelé hors d'une transaction Drift
  /// @throws ArgumentError opération que le serveur refuserait par principe
  Future<String?> enfiler({
    required TableSynchronisee table,
    required String entiteId,
    required TypeOperationSync type,
    required Map<String, Object?> payload,
    DateTime? horodatage,
    String? dateMetier,
  }) async {
    if (!_dansUneTransaction) {
      throw StateError(
        'OperationsSyncDao.enfiler doit être appelé DANS la transaction de '
        'l’écriture métier : hors d’elle, une coupure entre les deux laisserait '
        'une donnée que rien ne pousse.',
      );
    }
    if (entiteId.isEmpty) {
      throw ArgumentError.value(entiteId, 'entiteId', 'identifiant vide');
    }
    if (type == TypeOperationSync.modification && !table.accepteModification) {
      throw ArgumentError.value(
        table.nomServeur,
        'table',
        'le serveur refuse toute modification de cette table',
      );
    }
    if (type == TypeOperationSync.creation && payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'création sans document');
    }
    if (!attachedDatabase.fileSynchronisationActive) return null;
    if (type == TypeOperationSync.modification && payload.isEmpty) return null;

    final maintenant = _maintenant();
    final uuidOperation = _uuid.v4();
    await into(_operations).insert(
      OperationsSyncLocalCompanion.insert(
        uuidOperation: uuidOperation,
        tableServeur: table.nomServeur,
        entiteId: entiteId,
        type: type.code,
        payload: jsonEncode(payload),
        horodatageClient: (horodatage ?? maintenant).toUtc().toIso8601String(),
        dateMetier: Value(dateMetier),
        creeLe: maintenant,
      ),
    );
    return uuidOperation;
  }

  /* ================================================================== */
  /* Le moteur d'envoi (F2) — réclamer, libérer, marquer                 */
  /* ================================================================== */

  /// Réclame un lot : les plus anciennes opérations `en_attente` échues, dans
  /// l'ordre de `seq`, passées `en_cours` sous le lot [lotId] (généré si
  /// absent) et un bail de [bail].
  ///
  /// Deux règles d'ordre :
  ///  * la réclamation s'ARRÊTE à la première opération en attente dont le
  ///    repli n'est pas échu — un document ne double jamais ce qu'il cite ;
  ///  * une opération dont l'élément a une opération ANTÉRIEURE non aboutie
  ///    (en cours, rejetée, en conflit, bloquée) est laissée de côté.
  ///    Plusieurs opérations du même élément peuvent partir dans un même lot
  ///    (ouverture puis clôture d'une caisse : le serveur l'admet).
  Future<List<OperationSync>> reclamerLot({
    int taille = 50,
    Duration bail = const Duration(minutes: 2),
    String? lotId,
  }) {
    return transaction(() async {
      final maintenant = _maintenant();
      final lot = lotId ?? _uuid.v4();
      final nonAbouties =
          await (select(_operations)
                ..where(
                  (o) =>
                      o.statut.isNotValue(StatutOperationSync.synchronise.code),
                )
                ..orderBy([(o) => OrderingTerm.asc(o.seq)]))
              .get();

      final retenus = <String>{};
      final reclames = <int>[];
      for (final o in nonAbouties) {
        if (reclames.length >= taille) break;
        final cle = '${o.tableServeur}|${o.entiteId}';
        if (o.statut != StatutOperationSync.enAttente.code) {
          retenus.add(cle);
          continue;
        }
        if (retenus.contains(cle)) continue;
        final prochaine = o.prochaineTentative;
        if (prochaine != null && prochaine.isAfter(maintenant)) break;
        reclames.add(o.seq);
      }
      if (reclames.isEmpty) return const <OperationSync>[];

      await (update(_operations)..where((o) => o.seq.isIn(reclames))).write(
        OperationsSyncLocalCompanion(
          statut: Value(StatutOperationSync.enCours.code),
          lotId: Value(lot),
          verrouJusqua: Value(maintenant.add(bail)),
        ),
      );
      await customUpdate(
        'UPDATE operations_sync_local SET tentatives = tentatives + 1 '
        'WHERE seq IN (${List.filled(reclames.length, '?').join(', ')})',
        variables: [for (final s in reclames) Variable.withInt(s)],
        updates: {_operations},
      );
      return operations(lotId: lot);
    });
  }

  /// Rend `en_attente` les opérations `en_cours` dont le bail est échu — le
  /// lot d'un processus tué. Appelée au démarrage du poste
  /// (`liberationBauxSyncProvider`, lu par `main.dart`). Rend le nombre
  /// d'opérations libérées.
  Future<int> libererBauxExpires() {
    final maintenant = _maintenant();
    return (update(_operations)..where(
          (o) =>
              o.statut.equals(StatutOperationSync.enCours.code) &
              (o.verrouJusqua.isNull() |
                  o.verrouJusqua.isSmallerThanValue(maintenant)),
        ))
        .write(
          OperationsSyncLocalCompanion(
            statut: Value(StatutOperationSync.enAttente.code),
            lotId: const Value(null),
            verrouJusqua: const Value(null),
          ),
        );
  }

  /// Consigne le résultat RENDU par le serveur pour une opération
  /// (`resultats[]` de `/api/v1/sync`), tel quel dans `resultat_json`.
  ///
  /// `synchronise` et `cloture_sans_session_serveur` (une clôture acceptée
  /// pour une caisse que le serveur ne connaît pas — jamais bloquée) sont des
  /// succès ; `rejete` et `conflit` sont définitifs. `fusionne_avec` devient
  /// [OperationSync.idServeur]. Un rejet BLOQUE les opérations suivantes
  /// encore en attente sur le même élément.
  Future<void> marquerResultat(
    String uuidOperation, {
    required Map<String, Object?> resultat,
    int? codeHttp,
  }) {
    return transaction(() async {
      final operation = await _parUuid(uuidOperation);
      final statutServeur = resultat['statut'];
      final statut = switch (statutServeur) {
        'synchronise' ||
        'cloture_sans_session_serveur' => StatutOperationSync.synchronise,
        'rejete' => StatutOperationSync.rejete,
        'conflit' => StatutOperationSync.conflit,
        _ => throw ArgumentError.value(
          statutServeur,
          'resultat.statut',
          'statut de résultat inconnu',
        ),
      };
      final maintenant = _maintenant();
      final fusion = resultat['fusionne_avec'];
      final motif = resultat['motif'];
      await (update(
        _operations,
      )..where((o) => o.seq.equals(operation.seq))).write(
        OperationsSyncLocalCompanion(
          statut: Value(statut.code),
          resultatJson: Value(jsonEncode(resultat)),
          codeHttp: Value(codeHttp),
          idServeur: Value(fusion is String ? fusion : null),
          derniereErreur: Value(motif is String ? motif : null),
          verrouJusqua: const Value(null),
          synchroniseLe: Value(
            statut == StatutOperationSync.synchronise ? maintenant : null,
          ),
        ),
      );

      if (statut == StatutOperationSync.rejete) {
        await (update(_operations)..where(
              (o) =>
                  o.tableServeur.equals(operation.tableServeur) &
                  o.entiteId.equals(operation.entiteId) &
                  o.seq.isBiggerThanValue(operation.seq) &
                  o.statut.equals(StatutOperationSync.enAttente.code),
            ))
            .write(
              OperationsSyncLocalCompanion(
                statut: Value(StatutOperationSync.bloque.code),
                derniereErreur: Value(
                  'Bloquée : l’opération ${operation.uuidOperation} sur le '
                  'même élément a été refusée par le serveur.',
                ),
              ),
            );
      }
    });
  }

  /// Un échec TRANSITOIRE (réseau, 5xx, lot entier refusé) : l'opération
  /// redevient `en_attente`, à retenter après [delai]. Rien n'est perdu.
  Future<void> marquerEchecTransitoire(
    String uuidOperation, {
    required String erreur,
    int? codeHttp,
    required Duration delai,
  }) async {
    final maintenant = _maintenant();
    await (update(
      _operations,
    )..where((o) => o.uuidOperation.equals(uuidOperation))).write(
      OperationsSyncLocalCompanion(
        statut: Value(StatutOperationSync.enAttente.code),
        lotId: const Value(null),
        verrouJusqua: const Value(null),
        derniereErreur: Value(erreur),
        codeHttp: Value(codeHttp),
        prochaineTentative: Value(maintenant.add(delai)),
      ),
    );
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  /// Les opérations dans l'ordre de `seq`, filtrées au besoin.
  Future<List<OperationSync>> operations({
    StatutOperationSync? statut,
    TableSynchronisee? table,
    String? entiteId,
    String? lotId,
  }) async {
    final q = select(_operations)..orderBy([(o) => OrderingTerm.asc(o.seq)]);
    if (statut != null) q.where((o) => o.statut.equals(statut.code));
    if (table != null) q.where((o) => o.tableServeur.equals(table.nomServeur));
    if (entiteId != null) q.where((o) => o.entiteId.equals(entiteId));
    if (lotId != null) q.where((o) => o.lotId.equals(lotId));
    return [for (final l in await q.get()) _vers(l)];
  }

  /// Le nombre d'opérations par statut (zéro compris).
  Future<Map<StatutOperationSync, int>> compteParStatut() async {
    final lignes = await customSelect(
      'SELECT statut, COUNT(*) AS n FROM operations_sync_local GROUP BY statut',
      readsFrom: {_operations},
    ).get();
    final comptes = {for (final s in StatutOperationSync.values) s: 0};
    for (final l in lignes) {
      comptes[StatutOperationSync.depuisCode(l.data['statut'] as String)] =
          l.data['n'] as int;
    }
    return comptes;
  }

  Future<OperationSyncLocale> _parUuid(String uuidOperation) async {
    final ligne = await (select(
      _operations,
    )..where((o) => o.uuidOperation.equals(uuidOperation))).getSingleOrNull();
    if (ligne == null) {
      throw StateError('Opération inconnue de la file : $uuidOperation.');
    }
    return ligne;
  }

  OperationSync _vers(OperationSyncLocale l) => OperationSync(
    seq: l.seq,
    uuidOperation: l.uuidOperation,
    table:
        TableSynchronisee.depuisNom(l.tableServeur) ??
        (throw StateError('Table hors registre : « ${l.tableServeur} ».')),
    entiteId: l.entiteId,
    type: TypeOperationSync.depuisCode(l.type),
    payload: l.payload,
    horodatageClient: l.horodatageClient,
    dateMetier: l.dateMetier,
    statut: StatutOperationSync.depuisCode(l.statut),
    lotId: l.lotId,
    verrouJusqua: l.verrouJusqua,
    tentatives: l.tentatives,
    prochaineTentative: l.prochaineTentative,
    derniereErreur: l.derniereErreur,
    codeHttp: l.codeHttp,
    resultatJson: l.resultatJson,
    idServeur: l.idServeur,
    creeLe: l.creeLe,
    synchroniseLe: l.synchroniseLe,
  );
}
