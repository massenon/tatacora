import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/sync_manager.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';
import 'package:uuid/uuid.dart';

/// Une requête vue par le faux transport.
final class RequeteVue {
  RequeteVue(this.methode, this.url, this.corps, this.jeton);

  final String methode;
  final Uri url;
  final Map<String, Object?>? corps;
  final String? jeton;

  /// Les opérations d'un `POST /sync`.
  List<Map<String, Object?>> get operations => [
    for (final o in (corps?['operations'] as List? ?? const []))
      o as Map<String, Object?>,
  ];

  List<String> get uuids => [
    for (final o in operations) o['uuid_operation']! as String,
  ];
}

/// Un faux [TransportSynchronisation] : chaque requête est consignée, et la
/// réponse vient de [repondre].
final class FauxTransport implements TransportSynchronisation {
  FauxTransport(this.repondre);

  FutureOr<IssueHttp> Function(RequeteVue requete) repondre;
  final List<RequeteVue> requetes = [];

  List<RequeteVue> get lots => [
    for (final r in requetes)
      if (r.url.path.endsWith('/sync')) r,
  ];

  @override
  Future<IssueHttp> post(
    Uri url, {
    Map<String, Object?>? corps,
    String? jeton,
  }) async {
    // Copie PROFONDE : le moteur ne doit pas pouvoir modifier ce qu'on a vu.
    final copie = corps == null
        ? null
        : jsonDecode(jsonEncode(corps)) as Map<String, Object?>;
    final r = RequeteVue('POST', url, copie, jeton);
    requetes.add(r);
    return repondre(r);
  }

  @override
  Future<IssueHttp> get(Uri url, {String? jeton}) async {
    final r = RequeteVue('GET', url, null, jeton);
    requetes.add(r);
    return repondre(r);
  }
}

/// La réponse 200 du serveur : chaque opération [statut] (par défaut
/// `synchronise`), sauf celles que [particulier] décide.
ReponseHttp reponseLot(
  RequeteVue r, {
  Map<String, Object?>? Function(Map<String, Object?> op)? particulier,
}) => ReponseHttp(
  statut: 200,
  corps: {
    'session_id': 'session-essai',
    'resultats': [
      for (final o in r.operations)
        particulier?.call(o) ??
            {
              'uuid_operation': o['uuid_operation'],
              'statut': 'synchronise',
              'entite_id': o['entite_id'],
            },
    ],
  },
);

/// Le banc d'un essai du moteur : une base en mémoire, une horloge, un
/// `poste.json` dans un dossier temporaire.
final class BancSync {
  BancSync._(this.db, this.dossier);

  static Future<BancSync> creer({bool appaire = true}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final b = BancSync._(
      AppDatabase.enMemoire(),
      await Directory.systemTemp.createTemp('tatacora-sync-'),
    );
    if (appaire) await b.appairer();
    return b;
  }

  final AppDatabase db;
  final Directory dossier;

  /// Une heure LOCALE : Drift relit ses dates en heure locale.
  DateTime maintenant = DateTime(2026, 10, 15, 10);

  static const urlServeur = 'https://serveur.essai/api/v1';
  static const jeton = '7|jeton-essai';
  static const poste = 'COMPTOIR-ESSAI';

  String get cheminPoste => '${dossier.path}/poste.json';
  Future<String> chemin() async => cheminPoste;

  late final OperationsSyncDao dao = OperationsSyncDao(
    db,
    maintenant: () => maintenant,
  );

  LecteurConfigurationPoste get lecteur =>
      LecteurConfigurationPoste(chemin: chemin);
  EcrivainConfigurationPoste get ecrivain =>
      EcrivainConfigurationPoste(chemin: chemin);

  Future<void> appairer({String serveur = urlServeur}) =>
      ecrivain.enregistrerAppairage(
        AppairagePoste(
          posteId: poste,
          jetonApi: jeton,
          serveur: serveur,
          appaireLe: maintenant,
          compte: 'gerant',
        ),
      );

  SyncManager manager(
    TransportSynchronisation transport, {
    bool demonstration = false,
    String? url = urlServeur,
    int tailleLot = 50,
  }) => SyncManager(
    dao: dao,
    transport: transport,
    urlServeur: url,
    demonstration: demonstration,
    lecteur: lecteur,
    ecrivain: ecrivain,
    maintenant: () => maintenant,
    tailleLot: tailleLot,
  );

  /// Enfile [n] créations de clients (une par élément), dans l'ordre.
  Future<List<String>> enfilerClients(int n, {String prefixe = 'C'}) async {
    final ids = <String>[];
    for (var i = 0; i < n; i++) {
      final id = const Uuid().v4();
      await db.transaction(
        () => dao.enfiler(
          table: TableSynchronisee.clients,
          entiteId: id,
          type: TypeOperationSync.creation,
          payload: {'nom': '$prefixe$i', 'telephone': '9700${1000 + i}'},
        ),
      );
      ids.add(id);
    }
    return ids;
  }

  /// Enfile une modification du client [id].
  Future<void> modifierClient(String id, String nom) => db.transaction(
    () => dao.enfiler(
      table: TableSynchronisee.clients,
      entiteId: id,
      type: TypeOperationSync.modification,
      payload: {'nom': nom},
    ),
  );

  Future<Map<StatutOperationSync, int>> comptes() => dao.compteParStatut();

  Future<int> total() async =>
      (await comptes()).values.fold<int>(0, (a, b) => a + b);

  Future<OperationSync> operationDe(String entiteId, {int rang = 0}) async =>
      (await dao.operations(entiteId: entiteId))[rang];

  Future<Map<String, Object?>> fichier() async =>
      jsonDecode(await File(cheminPoste).readAsString())
          as Map<String, Object?>;

  Future<void> fermer() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  }
}
