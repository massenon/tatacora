import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'retour_arriere_schema.dart';

/// Migration v25 -> v26 : UNE table neuve (`operations_sync_local`, la file
/// d'envoi du poste, lot F1 du 15/10/2026) et ses deux index, éprouvée sur un
/// FICHIER RÉEL portant des données (piège 2), y compris par un poste qui a
/// sauté des livraisons (depuis la v24, la v21 et la v10).
///
/// Additive : aucune table existante n'est touchée, et AUCUNE ligne n'est
/// semée — la migration ne sait pas ce que le serveur détient déjà.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v26_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> tables(AppDatabase db) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return {for (final l in r) l.data['name'] as String};
  }

  Future<int> compte(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<int> version(AppDatabase db) async {
    final r = await db.customSelect('PRAGMA user_version').getSingle();
    return r.data.values.first as int;
  }

  /// Sème, au format d'une version ancienne (v10 et après), un compte et un
  /// client : la donnée d'avant, seule copie qui existe.
  Future<void> semer(AppDatabase db) async {
    await db.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, sel, '
      'empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'admin', 'Admin', 'administrateur', '{}', "
      "'s', 'e', 1, 1, 0, 0)",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', '+229 01 00 00 00 01', 'particulier')",
    );
  }

  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    expect(
      tablesAvant,
      isNot(contains('operations_sync_local')),
      reason: 'la fixture doit imiter une v$cible, qui n’a pas la file',
    );
    expect(await version(avant), cible);
    await semer(avant);
    await avant.close();
    return tablesAvant;
  }

  Future<void> exigerDonneesIntactes(AppDatabase db) async {
    final c = await db
        .customSelect(
          "SELECT nom, telephone FROM clients_local WHERE id = 'cli-1'",
        )
        .getSingle();
    expect(
      (c.data['nom'], c.data['telephone']),
      ('KORA', '+229 01 00 00 00 01'),
    );
    expect(await compte(db, 'utilisateurs_local'), 1);
  }

  test('v25 -> v26 : la file APPARAÎT vide, les données d’avant sont '
      'INTACTES, user_version = courante', () async {
    final tablesAvant = await preparer(25);

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(apres.schemaVersion, greaterThanOrEqualTo(26));
    expect(await tables(apres), {
      ...tablesAvant,
      ...tablesAjouteesEnV26,
      ...tablesAjouteesEnV27,
      ...tablesAjouteesEnV28,
      ...tablesAjouteesEnV29,
      ...tablesAjouteesEnV31,
      ...tablesAjouteesEnV32,
    });
    expect(
      await compte(apres, 'operations_sync_local'),
      0,
      reason: 'la migration ne fabrique aucune opération',
    );
    await exigerDonneesIntactes(apres);
    await apres.close();
  });

  test('colonnes EXACTEMENT celles de la définition, deux index, '
      'AUTOINCREMENT', () async {
    await preparer(25);

    final apres = AppDatabase.surFichier(fichier);
    final info = await apres
        .customSelect('PRAGMA table_info(operations_sync_local)')
        .get();
    final colonnes = {
      for (final l in info)
        l.data['name'] as String: (
          notnull: l.data['notnull'] as int,
          defaut: l.data['dflt_value'] as String?,
          pk: l.data['pk'] as int,
        ),
    };
    expect(colonnes.keys.toList(), [
      'seq',
      'uuid_operation',
      'table_serveur',
      'entite_id',
      'type',
      'payload',
      'horodatage_client',
      'date_metier',
      'statut',
      'lot_id',
      'verrou_jusqua',
      'tentatives',
      'prochaine_tentative',
      'derniere_erreur',
      'code_http',
      'resultat_json',
      'id_serveur',
      'cree_le',
      'synchronise_le',
    ]);
    expect(colonnes['seq']!.pk, 1);
    for (final obligatoire in [
      'uuid_operation',
      'table_serveur',
      'entite_id',
      'type',
      'payload',
      'horodatage_client',
      'statut',
      'tentatives',
      'cree_le',
    ]) {
      expect(colonnes[obligatoire]!.notnull, 1, reason: obligatoire);
    }
    expect(colonnes['statut']!.defaut, "'en_attente'");
    expect(colonnes['tentatives']!.defaut, '0');

    final sql = await apres
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'operations_sync_local'",
        )
        .getSingle();
    expect(sql.data['sql'] as String, contains('AUTOINCREMENT'));

    final index = await apres
        .customSelect(
          "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'operations_sync_local' AND sql IS NOT NULL "
          'ORDER BY name',
        )
        .get();
    expect(
      {for (final l in index) l.data['name']: l.data['sql']},
      {
        'idx_operations_sync_entite':
            'CREATE INDEX idx_operations_sync_entite ON operations_sync_local '
            '(table_serveur, entite_id)',
        'idx_operations_sync_statut_seq':
            'CREATE INDEX idx_operations_sync_statut_seq ON '
            'operations_sync_local (statut, seq)',
      },
    );
    await apres.close();
  });

  test('contraintes tenues sur le fichier migré : type et statut fermés, '
      'uuid_operation unique', () async {
    await preparer(25);

    final apres = AppDatabase.surFichier(fichier);
    Future<void> inserer(String uuid, String type, [String? statut]) =>
        apres.customStatement(
          'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
          'entite_id, type, payload, horodatage_client, cree_le'
          '${statut == null ? '' : ', statut'}) VALUES '
          "('$uuid', 'clients', 'c', '$type', '{}', 'h', 0"
          "${statut == null ? '' : ", '$statut'"})",
        );
    await expectLater(inserer('u-1', 'suppression'), throwsA(anything));
    await expectLater(inserer('u-1', 'creation', 'perdu'), throwsA(anything));
    await inserer('u-1', 'creation');
    await expectLater(inserer('u-1', 'creation'), throwsA(anything));
    expect(await compte(apres, 'operations_sync_local'), 1);
    await apres.close();
  });

  test('la file migrée SERT : un écrivain y dépose son document, relu après '
      'fermeture', () async {
    await preparer(25);

    final ouverte = AppDatabase.surFichier(fichier);
    final client = await ClientDao(ouverte).creer(
      nom: 'DOSSOU',
      telephone: '97000002',
      type: TypeClientReferentiel.particulier,
    );
    await ouverte.close();

    final relue = AppDatabase.surFichier(fichier);
    final o = (await OperationsSyncDao(relue).operations()).single;
    expect(o.table, TableSynchronisee.clients);
    expect(o.entiteId, client.id);
    expect(o.statut, StatutOperationSync.enAttente);
    await exigerDonneesIntactes(relue);
    await relue.close();
  });

  group('versions SAUTÉES : le poste qui a raté des livraisons', () {
    for (final depart in const [24, 21, 10]) {
      test('v$depart -> courante : la file apparaît vide, rien n’est perdu, '
          'et elle sert', () async {
        final tablesAvant = await preparer(depart);

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);
        final tablesApres = await tables(apres);
        expect(tablesApres, containsAll(tablesAvant));
        expect(tablesApres, containsAll(tablesAjouteesEnV26));
        expect(await compte(apres, 'operations_sync_local'), 0);
        await exigerDonneesIntactes(apres);

        await ClientDao(apres).creer(
          nom: 'HOUNSOU',
          telephone: '97000003',
          type: TypeClientReferentiel.groupe,
        );
        expect(await OperationsSyncDao(apres).operations(), hasLength(1));
        await apres.close();
      });
    }
  });
}
