@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/espace_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/cause_envoi.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/scenario_file.dart' show fileAuProtocole;
import 'support/outils_ventes.dart';

/// LES TABLES DE SALLE, CONTRE LE VRAI MOTEUR (09/11/2026, bogue du PO : le barman
/// du poste A, trois « Tables de salle — Droit manquant »).
///
/// Le poste prend une table HORS LIGNE, avant d'avoir reçu la salle du serveur :
/// il enfile la `creation` de la table (`assurerConnueDuServeur`), puis
/// l'ouverture du panier, puis, à la libération, sa fermeture. Cette file —
/// écrite par les VRAIS écrivains du poste (`PanierDao`, `TablesPosDao`) — est
/// poussée TELLE QUELLE à `SynchronisationService::traiterLot`
/// (`tool/pos/rejouer_tables_salle.php`, salle semée par le vrai seeder), sous le
/// compte du JETON d'appairage d'un rôle de la matrice.
///
/// DÉCISION DU PO (09/11/2026) : « Le jeton du poste porte un seul compte. Tout ce
/// qui sort d'un poste appairé par le barman est jugé sur les droits du barman. NON,
/// ÇA NE DOIT PAS JUGER. » Le serveur ne juge donc plus AUCUN module du compte du
/// jeton : la prise, la libération ET la configuration (créer une table, renuméroter)
/// passent pour TOUS les rôles — c'est le RBAC LOCAL du poste qui décide. Le compte
/// DÉSACTIVÉ reste refusé, et un lot rejeté « Droit manquant » avant la décision se
/// relance (« Renvoyer ») et passe.
///
/// La base d'essai privée se donne par `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TablesPosDao tables;
  late PanierDao paniers;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db);
    tables = TablesPosDao(db);
    paniers = panierDaoSur(db);
  });

  tearDown(() => db.close());

  Future<Map<String, dynamic>> pousser(
    List<({String role, List<Map<String, Object?>> operations})> etapes,
  ) => executerPhp(
    'rejouer_tables_salle.php',
    dossier: 'pos',
    nomVerrou: 'tatacora_tables_test_php',
    entree: {
      'poste_id': 'poste-a',
      'etapes': [
        for (final e in etapes) {'role': e.role, 'operations': e.operations},
      ],
    },
  );

  /// Ce que le barman fait au comptoir bar : prendre R1, puis la libérer.
  Future<String> prendreEtLibererR1() async {
    final r1 = (await tables.toutes()).firstWhere((t) => t.libelle == 'R1');
    expect(r1.espace, EspacePos.restaurant);
    final panier = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar',
      tableId: r1.id,
      espace: 'restaurant',
    );
    await paniers.abandonner(panier.id);
    return r1.id;
  }

  List<Map<String, Object?>> gestes(List<Map<String, Object?>> file) => [
    for (final o in file) o,
  ];

  test('la file de la prise de table est celle du bogue : la table, '
      'l’ouverture, la fermeture', () async {
    await prendreEtLibererR1();
    final file = await fileAuProtocole(db);
    expect(file.map((o) => '${o['type']} ${o['table']}').toList(), [
      'creation tables_salle',
      'creation paniers',
      'modification paniers',
    ]);
  });

  // Tous les rôles de la matrice : aucun n'est présumé, aucun n'est jugé.
  for (final role in [
    'barman',
    'gerant',
    'administrateur',
    'super_admin',
    'receptionniste',
    'cuisine',
    'comptable',
    'magasinier',
    'achats',
    'rh',
  ]) {
    test('$role (compte du jeton) : la prise ET la libération d’une table sont '
        'acceptées, la table se FUSIONNE avec celle du serveur', () async {
      final tableId = await prendreEtLibererR1();
      final file = await fileAuProtocole(db);

      final r = await pousser([(role: role, operations: gestes(file))]);
      final etape = (r['etapes'] as List).single as Map<String, dynamic>;
      final resultats = [
        for (final x in etape['resultats'] as List) x as Map<String, dynamic>,
      ];

      expect(resultats.map((x) => x['statut']).toList(), [
        'synchronise',
        'synchronise',
        'synchronise',
      ], reason: resultats.map((x) => x['motif']).join(' | '));
      expect(
        resultats.first['fusionne_avec'],
        isNotNull,
        reason: 'une table du jeu initial existe déjà au serveur',
      );
      expect(resultats.first['fusionne_avec'], isNot(tableId));
      expect(etape['paniers_ouverts'], 0, reason: 'la table est libérée');
    });
  }

  test('la CONFIGURATION (créer une table, renuméroter) n’est plus jugée sur '
      'PARAM : barman et gérant acceptés comme l’administrateur — le RBAC '
      'local du poste décide', () async {
    final r1 = (await tables.toutes()).firstWhere((t) => t.libelle == 'R1');
    await tables.renumeroter(r1.id, 9);
    await tables.creer(espace: EspacePos.restaurant, numero: 7);
    final file = await fileAuProtocole(db);

    for (final role in ['barman', 'gerant', 'administrateur']) {
      final r = await pousser([(role: role, operations: gestes(file))]);
      final etape = (r['etapes'] as List).single as Map<String, dynamic>;
      final resultats = [
        for (final x in etape['resultats'] as List) x as Map<String, dynamic>,
      ];
      expect(
        resultats.map((x) => x['statut']).toList(),
        everyElement('synchronise'),
        reason: '$role : ${resultats.map((x) => x['motif']).join(' | ')}',
      );
    }
  });

  test('un compte DÉSACTIVÉ reste refusé, pour l’usage comme pour le reste, '
      'et ne bloque rien d’autre : le compte suivant passe', () async {
    await prendreEtLibererR1();
    final file = await fileAuProtocole(db);

    final r = await executerPhp(
      'rejouer_tables_salle.php',
      dossier: 'pos',
      nomVerrou: 'tatacora_tables_test_php',
      entree: {
        'poste_id': 'poste-a',
        'etapes': [
          {'role': 'barman', 'compte_statut': 'desactive', 'operations': file},
          // Le refus d'un compte désactivé est MÉMORISÉ sous l'uuid de chaque opération
          // (idempotence) : le compte actif envoie la même saisie sous de NOUVEAUX uuid, comme
          // « Renvoyer » le fait au poste.
          {
            'role': 'barman',
            'operations': [
              for (final o in file) {...o, 'uuid_operation': const Uuid().v4()},
            ],
          },
        ],
      },
    );
    final etapes = [
      for (final e in r['etapes'] as List) e as Map<String, dynamic>,
    ];
    final refus = [
      for (final x in etapes.first['resultats'] as List)
        (x as Map<String, dynamic>)['code_motif'],
    ];
    expect(refus, ['compte_inactif', 'compte_inactif', 'compte_inactif']);
    expect(etapes.first['paniers_ouverts'], 0);
    expect([
      for (final x in etapes.last['resultats'] as List)
        (x as Map<String, dynamic>)['statut'],
    ], everyElement('synchronise'));
  });

  test('un lot déjà rejeté « Droit manquant » (« À traiter » d’avant la '
      'décision du PO) : « Renvoyer » — ouvert à tous — remet les trois '
      'lignes en file, elles PASSENT, et les opérations bloquées derrière se '
      'débloquent d’elles-mêmes', () async {
    final tableId = await prendreEtLibererR1();
    final dao = OperationsSyncDao(db);
    final file = await fileAuProtocole(db);

    // 1. Ce que l'ancien serveur avait rendu au barman : trois rejets « droit manquant »,
    //    consignés tels quels dans la file du poste (resultat_json).
    final faux = [
      for (final o in file)
        <String, Object?>{
          'uuid_operation': o['uuid_operation'],
          'statut': 'rejete',
          'entite_id': o['entite_id'],
          'motif': 'Vous n’avez pas accès à ce module.',
          'code_motif': 'droit_manquant',
        },
    ];
    await dao.marquerResultat(
      faux.first['uuid_operation']! as String,
      resultat: faux.first,
      codeHttp: 200,
    );
    // La suite de la même table est BLOQUÉE derrière son rejet (règle de F1) ; les deux
    // autres lignes sont des rejets à part (leur élément n'est pas le même).
    for (final x in faux.skip(1)) {
      await dao.marquerResultat(
        x['uuid_operation']! as String,
        resultat: x,
        codeHttp: 200,
      );
    }
    final rejetees = await dao.operations(statut: StatutOperationSync.rejete);
    expect(rejetees.length, 3, reason: 'les trois lignes du PO');
    expect(rejetees.every(renvoiOuvertATous), isTrue);

    // 2. « Renvoyer » (ouvert à tous pour ce code) : même élément, même charge, nouvel uuid.
    final anciennes = {for (final o in rejetees) o.uuidOperation: o};
    for (final o in rejetees) {
      await dao.renvoyer(o.uuidOperation);
    }
    final remplacees = await dao.remplacees();
    expect(remplacees.keys.toSet(), anciennes.keys.toSet());

    Future<List<Map<String, Object?>>> enFile(Set<String> uuids) async => [
      for (final o in await fileAuProtocole(db))
        if (uuids.contains(o['uuid_operation'])) o,
    ];

    // 3. Le serveur actuel (compte du jeton = barman, comme avant) ACCEPTE les renvois.
    final r = await pousser([
      (role: 'barman', operations: await enFile(remplacees.values.toSet())),
    ]);
    final renvoyees = [
      for (final x
          in ((r['etapes'] as List).single as Map)['resultats'] as List)
        x as Map<String, dynamic>,
    ];
    expect(
      renvoyees.map((x) => x['statut']).toList(),
      everyElement('synchronise'),
      reason: renvoyees.map((x) => x['motif']).join(' | '),
    );
    expect(renvoyees.first['fusionne_avec'], isNot(tableId));
    expect(
      renvoyees.map((x) => x['entite_id']).toSet(),
      anciennes.values.map((o) => o.entiteId).toSet(),
      reason: 'même élément : l’idempotence par élément est conservée',
    );
  });
}
