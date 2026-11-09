@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
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

/// LES DROITS DES TABLES DE SALLE, CONTRE LE VRAI MOTEUR (09/11/2026, bogue du
/// PO : le barman du poste A, trois « Tables de salle — Droit manquant »).
///
/// Le poste prend une table HORS LIGNE, avant d'avoir reçu la salle du serveur :
/// il enfile la `creation` de la table (`assurerConnueDuServeur`), puis
/// l'ouverture du panier, puis, à la libération, sa fermeture. Cette file —
/// écrite par les VRAIS écrivains du poste (`PanierDao`, `TablesPosDao`) — est
/// poussée TELLE QUELLE à `SynchronisationService::traiterLot`
/// (`tool/pos/rejouer_tables_salle.php`, salle semée par le vrai seeder), sous le
/// compte du JETON d'appairage d'un rôle de la matrice. Le serveur juge ce
/// compte, pas l'utilisateur connecté au poste.
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

  for (final role in ['barman', 'gerant', 'administrateur', 'super_admin']) {
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

  for (final role in ['receptionniste', 'cuisine', 'comptable', 'magasinier']) {
    test('$role (ne vend pas au POS) : droit_manquant sur la table ET sur le '
        'panier, rien n’est écrit', () async {
      await prendreEtLibererR1();
      final file = await fileAuProtocole(db);

      final r = await pousser([(role: role, operations: gestes(file))]);
      final etape = (r['etapes'] as List).single as Map<String, dynamic>;
      final codes = [
        for (final x in etape['resultats'] as List)
          (x as Map<String, dynamic>)['code_motif'],
      ];

      expect(codes, ['droit_manquant', 'droit_manquant', 'droit_manquant']);
      expect(etape['paniers_ouverts'], 0);
    });
  }

  test('la CONFIGURATION (créer une table, renuméroter, changer les places) '
      'reste réservée à PARAM : barman et gérant refusés, administrateur '
      'accepté', () async {
    // Un geste de configuration du poste : renuméroter R1 → R9 et créer R7.
    final r1 = (await tables.toutes()).firstWhere((t) => t.libelle == 'R1');
    await tables.renumeroter(r1.id, 9);
    await tables.creer(espace: EspacePos.restaurant, numero: 7);
    final file = await fileAuProtocole(db);

    // Le poste cite R1 (création, renumérotation) et la R7 nouvelle.
    for (final role in ['barman', 'gerant']) {
      final r = await pousser([(role: role, operations: gestes(file))]);
      final etape = (r['etapes'] as List).single as Map<String, dynamic>;
      final resultats = [
        for (final x in etape['resultats'] as List) x as Map<String, dynamic>,
      ];
      // 1. La création de R1 (celle du serveur existe : simple FUSION, usage)
      // passe ; 2. la renumérotation et 3. la création de R7 (nouvelle) sont de
      // la configuration : refusées.
      expect(resultats.map((x) => x['statut']).toList(), [
        'synchronise',
        'rejete',
        'rejete',
      ], reason: '$role ne configure pas la salle');
      expect(resultats[1]['code_motif'], 'droit_manquant');
      expect(resultats[2]['code_motif'], 'droit_manquant');
      expect(etape['tables'], 13, reason: 'aucune table créée');
    }

    final admin = await pousser([
      (role: 'administrateur', operations: gestes(file)),
    ]);
    final resultats = [
      for (final x
          in ((admin['etapes'] as List).single as Map)['resultats'] as List)
        x as Map<String, dynamic>,
    ];
    expect(
      resultats.map((x) => x['statut']).toList(),
      everyElement('synchronise'),
      reason: resultats.map((x) => x['motif']).join(' | '),
    );
  });

  test('« Renvoyer » après un droit manquant : la même opération, un NOUVEL '
      'uuid, acceptée dès que le compte du jeton a le droit — les trois lignes '
      'du PO', () async {
    final tableId = await prendreEtLibererR1();
    final dao = OperationsSyncDao(db);
    final file = await fileAuProtocole(db);

    // 1. Le compte du jeton n'avait pas le droit : tout est rejeté, définitivement.
    final premier = await pousser([
      (role: 'receptionniste', operations: gestes(file)),
    ]);
    final resultats = [
      for (final x
          in ((premier['etapes'] as List).single as Map)['resultats'] as List)
        x as Map<String, dynamic>,
    ];
    for (final x in resultats) {
      await dao.marquerResultat(
        x['uuid_operation'] as String,
        resultat: x,
        codeHttp: 200,
      );
    }
    final rejetees = await dao.operations(statut: StatutOperationSync.rejete);
    expect(rejetees.length, 3, reason: 'les trois lignes du PO');
    expect(rejetees.every(renvoiOuvertATous), isTrue);

    // 2. « Renvoyer » (ouvert à tous pour ce code) : même élément, même charge,
    //    nouvel uuid ; l'ancienne reste rejetée, remplacée.
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

    // 3. Le serveur, mis à jour (compte du jeton = barman), accepte les renvois.
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
