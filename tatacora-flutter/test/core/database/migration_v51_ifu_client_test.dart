import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v51 (07/11/2026 : IFU DU CLIENT) : TROIS colonnes NULLABLES —
/// `pieces_facturation_local.acheteur_ifu` et `.acheteur_nom`, `clients_local.ifu` —,
/// aucune table, éprouvée sur un FICHIER RÉEL portant des factures et des clients
/// (piège 2), y compris en sautant des versions.
///
/// Additive, et rien n'est déduit : aucun IFU n'est inventé pour une pièce ou une fiche
/// d'avant (NULL), aucune ligne ne disparaît, le numéro de démonstration d'une pièce
/// d'avant est conservé. Le curseur de descente est oublié : les IFU des fiches déjà au
/// serveur redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const colonnesPieces = ['acheteur_ifu', 'acheteur_nom'];

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v51_');
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

  /// Une base de la forme v50 : la courante, moins ce que la v51 ajoute (le retour
  /// arrière de `_ajoutsParVersion[51]`), avec des factures et des clients d'avant.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement('ALTER TABLE clients_local DROP COLUMN ifu');
    for (final nom in colonnesPieces.reversed) {
      await avant.customStatement(
        'ALTER TABLE pieces_facturation_local DROP COLUMN $nom',
      );
    }
    await avant.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) VALUES '
      "('c-1', 'Sabi', '96000003', 'groupe')",
    );
    await avant.customStatement(
      'INSERT INTO pieces_facturation_local (id, numero, origine, '
      'date_emission, client_nom, statut, numero_mecef, statut_transmission) '
      "VALUES ('p-1', 'F-2026-00001', 'pos_comptant', 1000, 'Passage', 'emise', "
      "NULL, 'transmise'), ('p-2', 'F-2026-00002', 'pos_sejour', 2000, 'Séjour', "
      "'emise', 'ED04000623-41', 'recue')",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    expect(
      (await colonnes(avant, 'pieces_facturation_local')).keys,
      isNot(contains('acheteur_ifu')),
      reason: 'préparée sans les colonnes de la v51',
    );
    expect(
      (await colonnes(avant, 'clients_local')).keys,
      isNot(contains('ifu')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [50, 49, 44, 40]) {
    test('v$depart -> v51 : trois colonnes NULLABLES, aucun IFU déduit, aucune '
        'ligne perdue, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(51));

      final pieces = await colonnes(apres, 'pieces_facturation_local');
      for (final nom in colonnesPieces) {
        expect(pieces.keys, contains(nom));
        expect(pieces[nom], isFalse, reason: '$nom est NULLABLE');
      }
      final clients = await colonnes(apres, 'clients_local');
      expect(clients.keys, contains('ifu'));
      expect(clients['ifu'], isFalse);

      final lignes = await apres
          .customSelect(
            'SELECT id, numero_mecef, acheteur_ifu, acheteur_nom FROM '
            'pieces_facturation_local ORDER BY id',
          )
          .get();
      expect(lignes.map((l) => l.data['id']), ['p-1', 'p-2']);
      expect(lignes.map((l) => l.data['numero_mecef']), [
        null,
        'ED04000623-41',
      ]);
      expect(lignes.map((l) => l.data['acheteur_ifu']), everyElement(isNull));
      expect(lignes.map((l) => l.data['acheteur_nom']), everyElement(isNull));
      final fiche = await apres
          .customSelect("SELECT ifu FROM clients_local WHERE id = 'c-1'")
          .getSingle();
      expect(fiche.data['ifu'], isNull, reason: 'aucun IFU inventé');

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
        "UPDATE pieces_facturation_local SET acheteur_ifu = '3201910768821', "
        "acheteur_nom = 'SARL Atacora' WHERE id = 'p-1'",
      );
      await apres.customStatement(
        "UPDATE clients_local SET ifu = '0202011344660' WHERE id = 'c-1'",
      );
      await apres.close();

      final rouvert = AppDatabase.surFichier(fichier);
      final p1 = await rouvert
          .customSelect(
            'SELECT acheteur_ifu, acheteur_nom FROM '
            "pieces_facturation_local WHERE id = 'p-1'",
          )
          .getSingle();
      expect(p1.data['acheteur_ifu'], '3201910768821');
      expect(p1.data['acheteur_nom'], 'SARL Atacora');
      final c1 = await rouvert
          .customSelect("SELECT ifu FROM clients_local WHERE id = 'c-1'")
          .getSingle();
      expect(c1.data['ifu'], '0202011344660');
      expect(await version(rouvert), rouvert.schemaVersion);
      await rouvert.close();
    });
  }

  test('un fichier de la forme v51 marqué v50 se rejoue sans « duplicate '
      'column »', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement('PRAGMA user_version = 50');
    await base.close();

    final rejoue = AppDatabase.surFichier(fichier);
    final pieces = await colonnes(rejoue, 'pieces_facturation_local');
    for (final nom in colonnesPieces) {
      expect(pieces.keys, contains(nom));
    }
    expect((await colonnes(rejoue, 'clients_local')).keys, contains('ifu'));
    expect(await version(rejoue), rejoue.schemaVersion);
    await rejoue.close();
  });
}
