import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import 'retour_arriere_schema.dart';

/// Migration v26 -> v27 : DEUX tables neuves (`etat_synchronisation_local`,
/// `correspondances_sync_local` — la descente du catalogue, lot F2b du
/// 15/10/2026), éprouvée sur un FICHIER RÉEL portant des données (piège 2),
/// y compris par un poste qui a sauté des livraisons (depuis la v25, la v21
/// et la v10).
///
/// Additive : aucune table existante n'est touchée — la FILE d'envoi d'un
/// poste v26 (la seule copie de ce qui n'est pas parti) traverse intacte —
/// et AUCUNE ligne n'est semée.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v27_');
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
  /// client ; et, quand la version a la file (v26), une opération en attente
  /// — la donnée qui n'est pas encore partie.
  Future<void> semer(AppDatabase db, int v) async {
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
    if (v >= 26) {
      await db.customStatement(
        'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
        'entite_id, type, payload, horodatage_client, cree_le) VALUES '
        "('op-1', 'clients', 'cli-1', 'creation', '{\"nom\":\"KORA\"}', "
        "'2026-10-15T08:00:00.000Z', 0)",
      );
    }
  }

  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    for (final t in tablesAjouteesEnV27) {
      expect(
        tablesAvant,
        isNot(contains(t)),
        reason: 'la fixture doit imiter une v$cible, qui n’a pas $t',
      );
    }
    expect(await version(avant), cible);
    await semer(avant, cible);
    await avant.close();
    return tablesAvant;
  }

  Future<void> exigerDonneesIntactes(AppDatabase db, int depart) async {
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
    if (depart >= 26) {
      final o = await db
          .customSelect(
            'SELECT statut, payload FROM operations_sync_local '
            "WHERE uuid_operation = 'op-1'",
          )
          .getSingle();
      expect(
        (o.data['statut'], o.data['payload']),
        ('en_attente', '{"nom":"KORA"}'),
        reason: 'la file d’un poste v26 traverse la migration INTACTE',
      );
    }
  }

  test('v26 -> v27 : les deux tables APPARAISSENT vides, la file et les '
      'données d’avant sont INTACTES, user_version = courante', () async {
    final tablesAvant = await preparer(26);

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(apres.schemaVersion, greaterThanOrEqualTo(27));
    expect(await tables(apres), {
      ...tablesAvant,
      ...tablesAjouteesEnV27,
      ...tablesAjouteesEnV28,
    });
    for (final t in tablesAjouteesEnV27) {
      expect(await compte(apres, t), 0, reason: '$t : rien n’est semé');
    }
    await exigerDonneesIntactes(apres, 26);
    await apres.close();
  });

  test('colonnes EXACTEMENT celles de la définition, clés primaires, '
      'contrainte d’origine', () async {
    await preparer(26);

    final apres = AppDatabase.surFichier(fichier);
    Future<Map<String, ({int notnull, int pk})>> colonnes(String t) async => {
      for (final l in await apres.customSelect('PRAGMA table_info($t)').get())
        l.data['name'] as String: (
          notnull: l.data['notnull'] as int,
          pk: l.data['pk'] as int,
        ),
    };
    final etat = await colonnes('etat_synchronisation_local');
    expect(etat.keys.toList(), ['cle', 'valeur', 'modifie_le']);
    expect(etat['cle']!.pk, 1);
    expect(etat['valeur']!.notnull, 1);

    final corr = await colonnes('correspondances_sync_local');
    expect(corr.keys.toList(), [
      'table_serveur',
      'id_serveur',
      'id_local',
      'origine',
      'cree_le',
    ]);
    expect((corr['table_serveur']!.pk, corr['id_serveur']!.pk), (1, 2));
    for (final c in corr.values) {
      expect(c.notnull, 1);
    }

    Future<void> inserer(String origine) => apres.customStatement(
      'INSERT INTO correspondances_sync_local (table_serveur, id_serveur, '
      "id_local, origine, cree_le) VALUES ('articles', 's-1', 'l-1', "
      "'$origine', 0)",
    );
    await expectLater(inserer('devine'), throwsA(anything));
    await inserer('flux');
    await expectLater(inserer('file'), throwsA(anything), reason: 'clé');
    expect(await compte(apres, 'correspondances_sync_local'), 1);
    await apres.close();
  });

  test('les tables migrées SERVENT : curseur, correspondance et renvoi '
      'écrits, relus après fermeture', () async {
    await preparer(26);

    final ouverte = AppDatabase.surFichier(fichier);
    final dao = DescenteCatalogueDao(ouverte);
    await ouverte.transaction(() async {
      await dao.poserCurseur('curseur-1');
      await dao.retenirCorrespondance(
        table: 'articles',
        idServeur: 's-1',
        idLocal: 'l-1',
        origine: 'flux',
      );
    });
    await ouverte.customStatement(
      "UPDATE operations_sync_local SET statut = 'rejete' "
      "WHERE uuid_operation = 'op-1'",
    );
    final nouvelle = await OperationsSyncDao(ouverte).renvoyer('op-1');
    await ouverte.close();

    final relue = AppDatabase.surFichier(fichier);
    final d = DescenteCatalogueDao(relue);
    expect(await d.curseur(), 'curseur-1');
    expect(await d.idLocal('articles', 's-1'), 'l-1');
    expect(await OperationsSyncDao(relue).remplacees(), {'op-1': nouvelle});
    await relue.close();
  });

  group('versions SAUTÉES : le poste qui a raté des livraisons', () {
    for (final depart in const [25, 21, 10]) {
      test('v$depart -> courante : les tables apparaissent vides, rien n’est '
          'perdu, et elles servent', () async {
        final tablesAvant = await preparer(depart);

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);
        final tablesApres = await tables(apres);
        expect(tablesApres, containsAll(tablesAvant));
        expect(tablesApres, containsAll(tablesAjouteesEnV26));
        expect(tablesApres, containsAll(tablesAjouteesEnV27));
        for (final t in tablesAjouteesEnV27) {
          expect(await compte(apres, t), 0);
        }
        await exigerDonneesIntactes(apres, depart);

        await ClientDao(apres).creer(
          nom: 'HOUNSOU',
          telephone: '97000003',
          type: TypeClientReferentiel.groupe,
        );
        expect(await OperationsSyncDao(apres).operations(), hasLength(1));
        final dao = DescenteCatalogueDao(apres);
        await dao.poserCurseur('c');
        expect(await dao.curseur(), 'c');
        await apres.close();
      });
    }
  });
}
