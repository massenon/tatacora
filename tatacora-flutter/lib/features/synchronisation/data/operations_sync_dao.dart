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
    // QUI écrit et depuis quel poste (v38) : relu à l'instant de l'écriture,
    // pour le Journal d'Audit. `null` si personne n'est connu (démonstration,
    // banc sans session) : l'écran dit « — », il n'invente aucun compte.
    final auteur = attachedDatabase.auteurEcriture();
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
        auteurLogin: Value(auteur.login),
        posteNom: Value(auteur.poste),
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

      // Lot F2b : une opération REMPLACÉE (« Renvoyer ») n'est plus que de
      // l'historique — elle ne retient plus son élément. Et sa remplaçante
      // passe devant les opérations BLOQUÉES derrière le rejet : elle est,
      // pour le serveur, l'opération antérieure qu'elles attendent.
      final remplacements = await remplacees();
      final remplacantes = remplacements.values.toSet();
      final retenus = <String>{};
      final retenusParBlocage = <String>{};
      final reclames = <int>[];
      for (final o in nonAbouties) {
        if (reclames.length >= taille) break;
        if (remplacements.containsKey(o.uuidOperation)) continue;
        final cle = '${o.tableServeur}|${o.entiteId}';
        if (o.statut == StatutOperationSync.bloque.code) {
          retenusParBlocage.add(cle);
          continue;
        }
        if (o.statut != StatutOperationSync.enAttente.code) {
          retenus.add(cle);
          continue;
        }
        if (retenus.contains(cle)) continue;
        if (retenusParBlocage.contains(cle) &&
            !remplacantes.contains(o.uuidOperation)) {
          continue;
        }
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

  /// Rend `en_attente` des opérations RÉCLAMÉES sans rien consigner contre
  /// elles — ni erreur, ni repli, et la tentative ne compte pas (lot F2a) :
  /// le jeton ou le poste a été refusé (401/403), l'envoi n'a jamais jugé
  /// l'opération. Seules les opérations encore `en_cours` sont touchées.
  Future<void> rendreEnAttente(List<String> uuidsOperation) async {
    if (uuidsOperation.isEmpty) return;
    await customUpdate(
      'UPDATE operations_sync_local SET statut = ?, lot_id = NULL, '
      'verrou_jusqua = NULL, tentatives = MAX(tentatives - 1, 0) '
      'WHERE statut = ? AND uuid_operation IN '
      '(${List.filled(uuidsOperation.length, '?').join(', ')})',
      variables: [
        Variable.withString(StatutOperationSync.enAttente.code),
        Variable.withString(StatutOperationSync.enCours.code),
        for (final u in uuidsOperation) Variable.withString(u),
      ],
      updates: {_operations},
    );
  }

  /// PROLONGE le bail du lot [lotId] : ses opérations encore `en_cours`
  /// sont tenues jusqu'à maintenant + [bail]. Appelée par le moteur avant
  /// CHAQUE requête d'un lot (lot F2b) : une bissection longue sur un réseau
  /// lent ne laisse jamais son bail échoir en route — sans quoi un autre
  /// processus (`libererBauxExpires`, puis `reclamerLot`) reprendrait les
  /// mêmes opérations et les enverrait une seconde fois. Rend le nombre
  /// d'opérations prolongées.
  Future<int> prolongerBail(String lotId, Duration bail) {
    final echeance = _maintenant().add(bail);
    return (update(_operations)..where(
          (o) =>
              o.lotId.equals(lotId) &
              o.statut.equals(StatutOperationSync.enCours.code),
        ))
        .write(OperationsSyncLocalCompanion(verrouJusqua: Value(echeance)));
  }

  /* ================================================================== */
  /* L'écran de synchronisation (lot F2b) — renvoyer, débloquer          */
  /* ================================================================== */

  /// Le préfixe des clés de remplacement dans `etat_synchronisation_local`.
  static const prefixeRemplacement = 'operation_remplacee:';

  /// « Renvoyer » une opération REJETÉE (geste d'Administrateur) : le MÊME
  /// document, le MÊME horodatage de saisie, sous un NOUVEL
  /// `uuid_operation` — le serveur, qui a mémorisé le rejet sous l'ancien,
  /// le rejugerait sinon à l'identique. Utile quand le référentiel qui
  /// manquait est arrivé depuis.
  ///
  /// L'ancienne ligne RESTE dans la file, rejetée, avec son motif : c'est
  /// l'historique. Elle est marquée remplacée (clé
  /// `operation_remplacee:<ancien>` → nouvel uuid), dans la MÊME transaction
  /// que l'enfilement, et ne retient plus son élément. Rend le nouvel uuid.
  ///
  /// [chargeCorrigee] (26/10/2026, « Corriger » de l'écran) : la charge
  /// CORRIGÉE par l'utilisateur remplace celle de l'ancienne opération — elle
  /// doit être un document non vide (une `creation` sans document est refusée,
  /// comme à l'enfilement) ; tout le reste (horodatage de saisie, élément,
  /// type) est inchangé. L'ancienne charge reste, intacte, dans la ligne
  /// rejetée : c'est l'historique de la correction.
  ///
  /// @throws StateError opération inconnue, non rejetée, ou déjà renvoyée
  /// @throws ArgumentError charge corrigée vide
  Future<String> renvoyer(
    String uuidOperation, {
    Map<String, Object?>? chargeCorrigee,
  }) {
    if (chargeCorrigee != null && chargeCorrigee.isEmpty) {
      throw ArgumentError.value(
        chargeCorrigee,
        'chargeCorrigee',
        'charge corrigée vide',
      );
    }
    return transaction(() async {
      final ancienne = await _parUuid(uuidOperation);
      if (ancienne.statut != StatutOperationSync.rejete.code) {
        throw StateError(
          'Seule une opération rejetée par le serveur se renvoie.',
        );
      }
      if ((await remplacees()).containsKey(uuidOperation)) {
        throw StateError('Cette opération a déjà été renvoyée.');
      }
      final maintenant = _maintenant();
      final nouvelle = _uuid.v4();
      await into(_operations).insert(
        OperationsSyncLocalCompanion.insert(
          uuidOperation: nouvelle,
          tableServeur: ancienne.tableServeur,
          entiteId: ancienne.entiteId,
          type: ancienne.type,
          payload: chargeCorrigee == null
              ? ancienne.payload
              : jsonEncode(chargeCorrigee),
          horodatageClient: ancienne.horodatageClient,
          dateMetier: Value(ancienne.dateMetier),
          creeLe: maintenant,
          // La remplaçante est la MÊME écriture, renvoyée : elle garde son
          // auteur et son poste (celui qui « Renvoie » n'a pas saisi le document).
          auteurLogin: Value(ancienne.auteurLogin),
          posteNom: Value(ancienne.posteNom),
        ),
      );
      await into(attachedDatabase.etatSynchronisationLocal).insert(
        EtatSynchronisationLocalCompanion.insert(
          cle: '$prefixeRemplacement$uuidOperation',
          valeur: nouvelle,
          modifieLe: maintenant,
        ),
      );
      return nouvelle;
    });
  }

  /// Les opérations REMPLACÉES : ancien uuid → uuid de la remplaçante.
  Future<Map<String, String>> remplacees() async {
    final t = attachedDatabase.etatSynchronisationLocal;
    final lignes = await (select(
      t,
    )..where((e) => e.cle.like('$prefixeRemplacement%'))).get();
    return {
      for (final l in lignes)
        l.cle.substring(prefixeRemplacement.length): l.valeur,
    };
  }

  /// Une opération BLOQUÉE peut-elle repartir ? Oui quand TOUTES les
  /// opérations antérieures du même élément sont abouties : synchronisées,
  /// ou remplacées par une opération elle-même synchronisée. Sans cela, elle
  /// s'appliquerait au serveur sur un état qu'il n'a pas.
  Future<bool> debloquable(String uuidOperation) async {
    final o = await _parUuid(uuidOperation);
    if (o.statut != StatutOperationSync.bloque.code) return false;
    return _anterieuresAbouties(o, await remplacees());
  }

  Future<bool> _anterieuresAbouties(
    OperationSyncLocale o,
    Map<String, String> remplacements,
  ) async {
    final anterieures =
        await (select(_operations)..where(
              (a) =>
                  a.tableServeur.equals(o.tableServeur) &
                  a.entiteId.equals(o.entiteId) &
                  a.seq.isSmallerThanValue(o.seq),
            ))
            .get();
    final synchronisees = {
      for (final a
          in await (select(_operations)..where(
                (a) =>
                    a.tableServeur.equals(o.tableServeur) &
                    a.entiteId.equals(o.entiteId) &
                    a.statut.equals(StatutOperationSync.synchronise.code),
              ))
              .get())
        a.uuidOperation,
    };
    for (final a in anterieures) {
      if (a.statut == StatutOperationSync.synchronise.code) continue;
      // Une chaîne de renvois : la DERNIÈRE remplaçante fait foi.
      var courant = a.uuidOperation;
      final vus = <String>{};
      while (remplacements.containsKey(courant) && vus.add(courant)) {
        courant = remplacements[courant]!;
      }
      if (courant == a.uuidOperation || !synchronisees.contains(courant)) {
        return false;
      }
    }
    return true;
  }

  /// « Débloquer » une opération bloquée dont le blocage est levé (voir
  /// [debloquable]) : elle redevient `en_attente`, sans repli, et partira à
  /// la prochaine synchronisation.
  ///
  /// @throws StateError opération non bloquée, ou blocage toujours en place
  Future<void> debloquer(String uuidOperation) {
    return transaction(() async {
      final o = await _parUuid(uuidOperation);
      if (o.statut != StatutOperationSync.bloque.code) {
        throw StateError('Cette opération n’est pas bloquée.');
      }
      if (!await _anterieuresAbouties(o, await remplacees())) {
        throw StateError(
          'Le blocage tient toujours : une opération antérieure sur le même '
          'élément n’est pas encore synchronisée.',
        );
      }
      await (update(_operations)..where((a) => a.seq.equals(o.seq))).write(
        OperationsSyncLocalCompanion(
          statut: Value(StatutOperationSync.enAttente.code),
          derniereErreur: const Value(null),
          prochaineTentative: const Value(null),
        ),
      );
    });
  }

  /// La liste « À traiter » de l'écran : les opérations REJETÉES, en
  /// CONFLIT ou BLOQUÉES, les plus récentes d'abord — sans les rejetées déjà
  /// renvoyées (elles sont l'historique de leur remplaçante).
  Future<List<OperationATraiter>> aTraiter() async {
    final remplacements = await remplacees();
    final lignes =
        await (select(_operations)
              ..where(
                (o) => o.statut.isIn([
                  StatutOperationSync.rejete.code,
                  StatutOperationSync.conflit.code,
                  StatutOperationSync.bloque.code,
                ]),
              )
              ..orderBy([(o) => OrderingTerm.desc(o.seq)]))
            .get();
    return [
      for (final l in lignes)
        if (!remplacements.containsKey(l.uuidOperation))
          OperationATraiter(
            operation: _vers(l),
            debloquable:
                l.statut == StatutOperationSync.bloque.code &&
                await _anterieuresAbouties(l, remplacements),
          ),
    ];
  }

  /// Les opérations ACCEPTÉES par le serveur avec un signalement
  /// (`anomalies` du résultat, ou clôture d'une caisse inconnue du
  /// serveur), les plus récentes d'abord — lecture seule pour l'écran.
  Future<List<OperationSync>> avecAnomalies() async {
    final lignes =
        await (select(_operations)
              ..where(
                (o) =>
                    o.statut.equals(StatutOperationSync.synchronise.code) &
                    (o.resultatJson.like('%"anomalies"%') |
                        o.resultatJson.like('%cloture_sans_session_serveur%')),
              )
              ..orderBy([(o) => OrderingTerm.desc(o.seq)]))
            .get();
    return [for (final l in lignes) _vers(l)];
  }

  /// Une modification locale de l'élément attend-elle encore de partir
  /// (opération `en_attente`, `en_cours` ou `bloque`) ? La descente du
  /// catalogue ne l'écrase alors pas (lot F2b).
  Future<bool> enSuspens(String tableServeur, String entiteId) async {
    final ligne =
        await (select(_operations)
              ..where(
                (o) =>
                    o.tableServeur.equals(tableServeur) &
                    o.entiteId.equals(entiteId) &
                    o.statut.isIn([
                      StatutOperationSync.enAttente.code,
                      StatutOperationSync.enCours.code,
                      StatutOperationSync.bloque.code,
                    ]),
              )
              ..limit(1))
            .getSingleOrNull();
    return ligne != null;
  }

  /// La DERNIÈRE opération de l'élément (plus grand `seq`), ou `null`.
  Future<OperationSync?> derniereOperation(
    String tableServeur,
    String entiteId,
  ) async {
    final ligne =
        await (select(_operations)
              ..where(
                (o) =>
                    o.tableServeur.equals(tableServeur) &
                    o.entiteId.equals(entiteId),
              )
              ..orderBy([(o) => OrderingTerm.desc(o.seq)])
              ..limit(1))
            .getSingleOrNull();
    return ligne == null ? null : _vers(ligne);
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
  Future<Map<StatutOperationSync, int>> compteParStatut() async =>
      _comptes(await _requeteComptes().get());

  /// Un signal à CHAQUE écriture de la file (lot F3, voyant de la barre
  /// supérieure) : une vente enfilée fait relire les comptes sans attendre un
  /// passage du moteur. Le signal de tables de Drift, et non une requête
  /// `.watch()` : une requête surveillée laisse, à sa fermeture, un minuteur
  /// que le banc de test refuse (`!timersPending`) — et ce bouton est monté
  /// dans la barre de TOUS les écrans.
  Stream<void> surveillerFile() => attachedDatabase.tableUpdates(
    TableUpdateQuery.onTableName('operations_sync_local'),
  );

  Selectable<QueryRow> _requeteComptes() => customSelect(
    'SELECT statut, COUNT(*) AS n FROM operations_sync_local GROUP BY statut',
    readsFrom: {_operations},
  );

  static Map<StatutOperationSync, int> _comptes(List<QueryRow> lignes) {
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
    auteurLogin: l.auteurLogin,
    posteNom: l.posteNom,
  );
}
