import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v41 -> v42 (le reçu en image d'une dépense, lot L4, 27/10/2026) :
/// AUCUNE table neuve, SIX colonnes nullables sur `depenses_local`
/// (`recu_nom`, `recu_sha256`, `recu_taille`, `recu_type`, `recu_statut`,
/// `recu_cause`), éprouvées sur un FICHIER RÉEL portant des données (piège 2),
/// y compris par un poste qui a sauté des livraisons.
///
/// Additive, et rien n'est déduit : une dépense d'avant n'a pas de reçu
/// (`recu_statut` NULL = « sans reçu »), jamais une valeur plausible fabriquée.
/// Le curseur de descente est oublié, pour que les dépenses déjà au serveur
/// redescendent avec la référence de leur reçu.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v42_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  const colonnesRecu = {
    'recu_nom',
    'recu_sha256',
    'recu_taille',
    'recu_type',
    'recu_statut',
    'recu_cause',
  };

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

  Future<Map<String, bool>> colonnes(AppDatabase db) async => {
    for (final c
        in await db.customSelect('PRAGMA table_info(depenses_local)').get())
      c.data['name'] as String: c.data['notnull'] == 1,
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
    expect(
      (await colonnes(avant)).keys,
      isNot(contains('recu_statut')),
      reason: 'imiter une v$cible',
    );
    expect(await version(avant), cible);
    await avant.customStatement(
      'INSERT INTO depenses_local (id, date_transaction, tresorerie, libelle) '
      "VALUES ('d-1', 1788000000, 'caisse', 'Marché du matin')",
    );
    await avant.customStatement(
      'INSERT INTO lignes_depense_local (id, depense_id, libelle, '
      'compte_charge, nature, famille, montant) VALUES '
      "('l-1', 'd-1', 'Tomates', '6011', 'Tomate', 'Marché', 12500)",
    );
    if (cible >= 27) {
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
      );
    }
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [41, 40, 30, 16, 10]) {
    test('v$depart -> courante : six colonnes NULLABLES, la dépense d’avant est '
        'INTACTE et « sans reçu », rien n’est fabriqué, et ça sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(42));
      expect(await tables(apres), containsAll(tablesAvant));

      final cols = await colonnes(apres);
      expect(cols.keys, containsAll(colonnesRecu));
      for (final c in colonnesRecu) {
        expect(cols[c], isFalse, reason: '$c est NULLABLE');
      }

      expect(await compte(apres, 'depenses_local'), 1);
      expect(await compte(apres, 'lignes_depense_local'), 1);
      final d = await apres
          .customSelect(
            'SELECT libelle, recu_nom, recu_sha256, recu_taille, recu_type, '
            "recu_statut, recu_cause FROM depenses_local WHERE id = 'd-1'",
          )
          .getSingle();
      expect(d.data['libelle'], 'Marché du matin');
      for (final c in colonnesRecu) {
        expect(d.data[c], isNull, reason: '$c : aucun reçu déduit');
      }

      if (depart >= 27) {
        // Le curseur est OUBLIÉ (les références de reçu redescendent) ; le reste
        // de l'état — la génération des données du serveur — est intact.
        final etat = {
          for (final l
              in await apres
                  .customSelect(
                    'SELECT cle, valeur FROM etat_synchronisation_local',
                  )
                  .get())
            l.data['cle'] as String: l.data['valeur'] as String,
        };
        expect(etat.containsKey('descente.curseur'), isFalse);
        expect(etat['serveur.generation'], 'g1');
      }

      // Les colonnes SERVENT : un reçu s'écrit et survit à la réouverture.
      await apres.customStatement(
        "UPDATE depenses_local SET recu_nom = 'd-1.png', recu_sha256 = 'ab', "
        "recu_taille = 68, recu_type = 'image/png', recu_statut = 'en_attente' "
        "WHERE id = 'd-1'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      final r = await relue
          .customSelect(
            'SELECT recu_nom, recu_taille, recu_statut FROM depenses_local',
          )
          .getSingle();
      expect(r.data['recu_nom'], 'd-1.png');
      expect(r.data['recu_taille'], 68);
      expect(r.data['recu_statut'], 'en_attente');
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v42 '
      'mais marqué v41 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO depenses_local (id, date_transaction, tresorerie, libelle, '
      "recu_statut) VALUES ('d-1', 1788000000, 'caisse', 'Marché', 'envoye')",
    );
    await base.customStatement('PRAGMA user_version = 41');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(await compte(apres, 'depenses_local'), 1);
    expect((await colonnes(apres)).keys, containsAll(colonnesRecu));
    final d = await apres
        .customSelect('SELECT recu_statut FROM depenses_local')
        .getSingle();
    expect(d.data['recu_statut'], 'envoye', reason: 'rien n’est écrasé');
    await apres.close();
  });
}
