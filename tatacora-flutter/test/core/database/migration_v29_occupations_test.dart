import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v28 -> v29 : UNE table neuve (`occupations_tables_local` —
/// l'occupation des tables par les autres postes, lot F6 du 18/10/2026),
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2), y compris par
/// un poste qui a sauté des livraisons (depuis la v26 et la v10).
///
/// Additive : la file d'envoi traverse intacte, AUCUNE ligne n'est semée.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v29_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> tables(AppDatabase db) async => {
    for (final l
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
      l.data['name'] as String,
  };

  Future<int> compte(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    for (final t in tablesAjouteesEnV29) {
      expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$cible');
    }
    expect(await version(avant), cible);
    await avant.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', '01', 'particulier')",
    );
    if (cible >= 26) {
      await avant.customStatement(
        'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
        'entite_id, type, payload, horodatage_client, cree_le) VALUES '
        "('op-1', 'clients', 'cli-1', 'creation', '{}', "
        "'2026-10-15T08:00:00.000Z', 0)",
      );
    }
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [28, 26, 10]) {
    test('v$depart -> courante : la table apparaît vide, la file et les '
        'données d’avant sont INTACTES, et elle sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(29));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV29]),
      );
      expect(await compte(apres, 'occupations_tables_local'), 0);
      expect(await compte(apres, 'clients_local'), 1);
      if (depart >= 26) {
        expect(await compte(apres, 'operations_sync_local'), 1);
      }

      await apres.customStatement(
        'INSERT INTO occupations_tables_local (panier_id, table_id, '
        "point_vente, poste_origine, ouvert, recu_le) VALUES ('p-1', 't-1', "
        "'Restaurant', 'POSTE-A', 1, 0)",
      );
      await expectLater(
        apres.customStatement(
          'INSERT INTO occupations_tables_local (panier_id, table_id, '
          "point_vente, poste_origine, ouvert, recu_le) VALUES ('p-1', 't-2', "
          "'Bar', NULL, 0, 0)",
        ),
        throwsA(anything),
        reason: 'clé : le panier',
      );
      await apres.close();

      final relue = AppDatabase.surFichier(fichier);
      final l = await relue
          .customSelect('SELECT poste_origine FROM occupations_tables_local')
          .getSingle();
      expect(l.data['poste_origine'], 'POSTE-A');
      await relue.close();
    });
  }
}
