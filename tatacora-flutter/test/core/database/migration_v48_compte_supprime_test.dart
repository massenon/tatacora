import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v48 (03/11/2026 : SUPPRIMER UN COMPTE UTILISATEUR) : UNE colonne
/// NULLABLE (`utilisateurs_local.supprime_le`), aucune table, éprouvée sur un
/// FICHIER RÉEL portant des données (piège 2).
///
/// Additive, et rien n'est déduit : aucun compte d'avant n'est supprimé (`NULL`),
/// ni désactivé, ni touché. Le curseur de descente est oublié : les comptes déjà
/// supprimés au serveur redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v48_');
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
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
      'sel, empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      'VALUES ';

  /// Une base de la forme v47 : la courante, moins ce que la v48 ajoute (le
  /// retour arrière de `_ajoutsParVersion[48]`), avec des données d'avant.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement(
      'ALTER TABLE utilisateurs_local DROP COLUMN supprime_le',
    );
    await avant.customStatement(
      "$insertion('u-1', 'n.kora', 'KORA Noël', 'administrateur', '{}', 's', "
      "'e', 1, 1, 0, 0), ('u-2', 'a.barman', 'Barman', 'barman', '{}', 's', "
      "'e', 1, 0, 0, 0)",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    expect(
      (await colonnes(avant, 'utilisateurs_local')).keys,
      isNot(contains('supprime_le')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [47, 46, 44, 40]) {
    test('v$depart -> v48 : une colonne NULLABLE, aucun compte supprimé ni '
        'désactivé en route, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(48));

      final cols = await colonnes(apres, 'utilisateurs_local');
      expect(cols.keys, contains('supprime_le'));
      expect(cols['supprime_le'], isFalse, reason: 'NULLABLE');

      final lignes = await apres
          .customSelect(
            'SELECT login, actif, supprime_le FROM utilisateurs_local '
            'ORDER BY login',
          )
          .get();
      expect(lignes.map((l) => l.data['login']), ['a.barman', 'n.kora']);
      // L'état d'AVANT est intact : le désactivé reste désactivé, l'actif actif.
      expect(lignes.map((l) => l.data['actif']), [0, 1]);
      expect(
        lignes.map((l) => l.data['supprime_le']),
        everyElement(isNull),
        reason: 'rien n’est déduit',
      );

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

      // La colonne SERT, et survit à la réouverture.
      await apres.customStatement(
        'UPDATE utilisateurs_local SET supprime_le = 1000, actif = 0 '
        "WHERE login = 'a.barman'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      expect(await version(relue), relue.schemaVersion);
      final lu = await relue
          .customSelect(
            "SELECT supprime_le FROM utilisateurs_local WHERE login = 'a.barman'",
          )
          .getSingle();
      expect(lu.data['supprime_le'], 1000);
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v48 '
      'mais marqué v47 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      "$insertion('u-2', 'a.barman', 'Barman', 'barman', '{}', 's', 'e', 1, "
      '0, 0, 0)',
    );
    await base.customStatement(
      "UPDATE utilisateurs_local SET supprime_le = 1000 WHERE id = 'u-2'",
    );
    await base.customStatement('PRAGMA user_version = 47');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    final u = await apres
        .customSelect('SELECT supprime_le FROM utilisateurs_local')
        .getSingle();
    expect(u.data['supprime_le'], 1000, reason: 'rien n’est écrasé');
    await apres.close();
  });
}
