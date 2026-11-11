import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v50 (07/11/2026 : FACTURATION NORMALISÉE) : HUIT colonnes
/// NULLABLES sur `pieces_facturation_local`, aucune table, éprouvée sur un
/// FICHIER RÉEL portant des factures (piège 2).
///
/// Additive, et rien n'est déduit : aucune pièce d'avant n'est « normalisée » ni
/// « en attente » (NULL), `numero_mecef` d'une démonstration est conservé tel
/// quel, aucune ligne ne disparaît. Le curseur de descente est oublié : les
/// normalisations déjà faites au serveur redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const colonnesAjoutees = [
    'normalisation_statut',
    'normalisation_motif',
    'normalisation_mode',
    'normalisation_compteur',
    'normalisation_compteur_avant',
    'code_mecef',
    'qr_code_fiscal',
    'normalisee_le',
  ];

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v50_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Map<String, bool>> colonnes(AppDatabase db, String table) async => {
    for (final c in await db.customSelect('PRAGMA table_info($table)').get())
      c.data['name'] as String: c.data['notnull'] == 1,
  };

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  const insertion =
      'INSERT INTO pieces_facturation_local (id, numero, origine, '
      'date_emission, client_nom, statut, numero_mecef, statut_transmission) '
      'VALUES ';

  /// Une base de la forme v49 : la courante, moins ce que la v50 ajoute (le retour
  /// arrière de `_ajoutsParVersion[50]`), avec des factures d'avant.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    for (final nom in colonnesAjoutees.reversed) {
      await avant.customStatement(
        'ALTER TABLE pieces_facturation_local DROP COLUMN $nom',
      );
    }
    await avant.customStatement(
      "$insertion('p-1', 'F-2026-00001', 'pos_comptant', 1000, 'Passage', "
      "'emise', NULL, 'transmise'), ('p-2', 'F-2026-00002', 'pos_sejour', 2000, "
      "'Séjour', 'emise', 'MECEF-DEMO-ABCD1234', 'recue'), "
      "('p-3', 'PROV-2026-00003', 'facture_directe', 3000, 'Direct', 'annulee', "
      "NULL, 'en_attente')",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    final cols = await colonnes(avant, 'pieces_facturation_local');
    for (final nom in colonnesAjoutees) {
      expect(cols.keys, isNot(contains(nom)), reason: 'préparée sans $nom');
    }
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [49, 48, 44, 40]) {
    test('v$depart -> v50 : huit colonnes NULLABLES, aucune pièce déduite, '
        'aucune ligne perdue, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(50));

      final cols = await colonnes(apres, 'pieces_facturation_local');
      for (final nom in colonnesAjoutees) {
        expect(cols.keys, contains(nom));
        expect(cols[nom], isFalse, reason: '$nom est NULLABLE');
      }

      final lignes = await apres
          .customSelect(
            'SELECT id, numero, statut, numero_mecef, normalisation_statut, '
            'normalisation_mode, qr_code_fiscal, code_mecef, normalisee_le '
            'FROM pieces_facturation_local ORDER BY id',
          )
          .get();
      expect(lignes.map((l) => l.data['id']), ['p-1', 'p-2', 'p-3']);
      // L'état d'AVANT est intact, y compris le numéro de démonstration.
      expect(lignes.map((l) => l.data['numero_mecef']), [
        null,
        'MECEF-DEMO-ABCD1234',
        null,
      ]);
      expect(lignes.map((l) => l.data['statut']), [
        'emise',
        'emise',
        'annulee',
      ]);
      for (final colonne in const [
        'normalisation_statut',
        'normalisation_mode',
        'qr_code_fiscal',
        'code_mecef',
        'normalisee_le',
      ]) {
        expect(
          lignes.map((l) => l.data[colonne]),
          everyElement(isNull),
          reason: '$colonne : rien n’est déduit',
        );
      }

      // Le curseur est OUBLIÉ ; le reste de l'état est intact.
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

      // Les colonnes SERVENT, et survivent à la réouverture.
      await apres.customStatement(
        'UPDATE pieces_facturation_local SET normalisation_statut = '
        "'normalisee', normalisation_mode = 'boitier', numero_mecef = "
        "'ED04000623-41', qr_code_fiscal = 'F;ED04000623;ABC;3201910768821;"
        "20261107100000', normalisee_le = 5000 WHERE id = 'p-1'",
      );
      await apres.close();

      final rouvert = AppDatabase.surFichier(fichier);
      final p1 = await rouvert
          .customSelect(
            'SELECT normalisation_statut, numero_mecef FROM '
            "pieces_facturation_local WHERE id = 'p-1'",
          )
          .getSingle();
      expect(p1.data['normalisation_statut'], 'normalisee');
      expect(p1.data['numero_mecef'], 'ED04000623-41');
      expect(await version(rouvert), rouvert.schemaVersion);
      await rouvert.close();
    });
  }

  test('un fichier de la forme v50 marqué v49 se rejoue sans « duplicate '
      'column »', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement('PRAGMA user_version = 49');
    await base.close();

    final rejoue = AppDatabase.surFichier(fichier);
    final cols = await colonnes(rejoue, 'pieces_facturation_local');
    for (final nom in colonnesAjoutees) {
      expect(cols.keys, contains(nom));
    }
    expect(await version(rejoue), rejoue.schemaVersion);
    await rejoue.close();
  });
}
