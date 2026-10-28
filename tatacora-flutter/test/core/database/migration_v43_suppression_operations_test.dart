import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v42 -> v43 (A5 « Purger », 28/10/2026) : AUCUNE colonne ni table, le
/// `CHECK` du type de la file d'envoi (`operations_sync_local`) accepte
/// `suppression`. SQLite ne modifie pas une contrainte : la table est RECRÉE
/// (`elargirTypesOperationsSync`) — le geste le plus risqué du dépôt, éprouvé sur
/// un FICHIER RÉEL qui porte des opérations non synchronisées (piège 2) : aucune
/// ne se perd, aucune colonne ne bouge, les index reviennent, et le compteur `seq`
/// n'est jamais réutilisé.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v43_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<String> ddl(AppDatabase db) async =>
      (await db
                  .customSelect(
                    "SELECT sql FROM sqlite_master WHERE type = 'table' "
                    "AND name = 'operations_sync_local'",
                  )
                  .getSingle())
              .data['sql']
          as String;

  Future<Set<String>> index(AppDatabase db) async => {
    for (final l
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' "
              "AND tbl_name = 'operations_sync_local' AND sql IS NOT NULL",
            )
            .get())
      l.data['name'] as String,
  };

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  Future<List<Map<String, Object?>>> lignes(AppDatabase db) async => [
    for (final l
        in await db
            .customSelect('SELECT * FROM operations_sync_local ORDER BY seq')
            .get())
      l.data,
  ];

  Future<void> inserer(
    AppDatabase db,
    int seq,
    String type,
    String statut,
  ) => db.customStatement(
    'INSERT INTO operations_sync_local (seq, uuid_operation, table_serveur, '
    'entite_id, type, payload, horodatage_client, statut, cree_le, tentatives, '
    "derniere_erreur) VALUES ($seq, 'u-$seq', 'unites_hebergement', 'e-$seq', "
    "'$type', '{\"statut\":\"hors_service\"}', '2026-10-28T08:00:00Z', "
    "'$statut', 1788000000, 3, 'repli')",
  );

  /// Un fichier ramené à [cible] : CHECK étroit, trois opérations dont une
  /// rejetée, et un `seq` 40 donné puis retiré (le compteur est à 40).
  Future<List<Map<String, Object?>>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    expect(await ddl(avant), isNot(contains("'suppression'")));
    expect(await version(avant), cible);
    await inserer(avant, 1, 'creation', 'synchronise');
    await inserer(avant, 2, 'modification', 'en_attente');
    await inserer(avant, 3, 'modification', 'rejete');
    await inserer(avant, 40, 'creation', 'en_attente');
    await avant.customStatement(
      'DELETE FROM operations_sync_local WHERE seq = 40',
    );
    final ecrit = await lignes(avant);
    await avant.close();
    return ecrit;
  }

  for (final depart in const [42, 38, 30, 26]) {
    test('v$depart -> courante : le CHECK accepte « suppression », aucune '
        'opération ne se perd, les index reviennent, seq n’est pas '
        'réutilisé', () async {
      final ecrit = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await ddl(apres), contains("'suppression'"));
      expect(
        await index(apres),
        containsAll(<String>{
          'idx_operations_sync_statut_seq',
          'idx_operations_sync_entite',
        }),
      );
      expect(
        (await apres
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE name LIKE '%_v42'",
                )
                .get())
            .isEmpty,
        isTrue,
        reason: 'la table de transit est abandonnée',
      );

      // Rien ne bouge : mêmes lignes, mêmes colonnes, mêmes valeurs.
      // (une fixture plus ancienne gagne les colonnes des migrations suivantes,
      // v38 : on compare celles que le fichier portait.)
      expect([
        for (final l in await lignes(apres))
          {for (final c in ecrit.first.keys) c: l[c]},
      ], ecrit);

      // Le type nouveau s'écrit ; un type inconnu reste REFUSÉ.
      await expectLater(
        inserer(apres, 50, 'effacement', 'en_attente'),
        throwsA(anything),
      );
      // Le compteur AUTOINCREMENT n'a pas reculé : le `seq` 40 retiré n'est pas rendu.
      await apres.customStatement(
        'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
        'entite_id, type, payload, horodatage_client, cree_le) VALUES '
        "('u-auto', 'vehicules', 'e-auto', 'suppression', '{\"libelle\":\"X\"}', "
        "'2026-10-28T08:00:00Z', 1788000000)",
      );
      final auto = await apres
          .customSelect(
            "SELECT seq FROM operations_sync_local WHERE uuid_operation = 'u-auto'",
          )
          .getSingle();
      expect(auto.data['seq'], 41);
      await apres.close();

      // Survit à la réouverture (rien à refaire).
      final relue = AppDatabase.surFichier(fichier);
      expect(await ddl(relue), contains("'suppression'"));
      expect((await lignes(relue)).length, ecrit.length + 1);
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà large mais marqué '
      'v42 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await inserer(base, 1, 'suppression', 'en_attente');
    await base.customStatement('PRAGMA user_version = 42');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect((await lignes(apres)).single['type'], 'suppression');
    await apres.close();
  });
}
