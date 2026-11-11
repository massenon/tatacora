import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v47 (30/10/2026 : la DESCRIPTION FACULTATIVE d'un plat) : UNE
/// colonne NULLABLE (`plats_local.description`), aucune table, éprouvée sur un
/// FICHIER RÉEL portant des données (piège 2).
///
/// Additive, et rien n'est déduit : les plats d'avant n'ont pas de description
/// (`NULL`, jamais une chaîne vide ni un texte fabriqué à partir du libellé). Le
/// curseur de descente est oublié : les descriptions des plats déjà au serveur
/// redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v47_');
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

  /// Une base de la forme v46 : la courante, moins ce que la v47 ajoute (le
  /// retour arrière de `_ajoutsParVersion[47]`), avec des données d'avant.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement(
      'ALTER TABLE plats_local DROP COLUMN description',
    );
    await avant.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
      'sel, empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'n.kora', 'KORA Noël', 'administrateur', '{}', 's', "
      "'e', 1, 1, 0, 0)",
    );
    await avant.customStatement(
      'INSERT INTO menus_local (id, libelle, type, cree_le, cree_par) '
      "VALUES ('m-1', 'Carte', 'local', 0, 'u-1')",
    );
    await avant.customStatement(
      'INSERT INTO recettes_local (id, libelle, cree_le, cree_par) '
      "VALUES ('r-1', 'Riz', 0, 'u-1')",
    );
    await avant.customStatement(
      'INSERT INTO plats_local (id, menu_id, recette_id, libelle, '
      'prix_vente, cree_le, cree_par) VALUES '
      "('p-1', 'm-1', 'r-1', 'Riz sauce', 2500, 0, 'u-1')",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    expect(
      (await colonnes(avant, 'plats_local')).keys,
      isNot(contains('description')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [46, 44, 40]) {
    test('v$depart -> v47 : une colonne NULLABLE, l’existant est INTACT, '
        'aucune description fabriquée, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(47));

      final cols = await colonnes(apres, 'plats_local');
      expect(cols.keys, contains('description'));
      expect(cols['description'], isFalse, reason: 'NULLABLE');

      final p = await apres
          .customSelect(
            "SELECT libelle, prix_vente, description FROM plats_local WHERE id = 'p-1'",
          )
          .getSingle();
      expect((p.data['libelle'], p.data['prix_vente']), ('Riz sauce', 2500));
      expect(p.data['description'], isNull, reason: 'rien n’est déduit');

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
        "UPDATE plats_local SET description = 'Riz, sauce arachide' "
        "WHERE id = 'p-1'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      expect(await version(relue), relue.schemaVersion);
      final lu = await relue
          .customSelect('SELECT description FROM plats_local')
          .getSingle();
      expect(lu.data['description'], 'Riz, sauce arachide');
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v47 '
      'mais marqué v46 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
      'sel, empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'n.kora', 'KORA Noël', 'administrateur', '{}', 's', "
      "'e', 1, 1, 0, 0)",
    );
    await base.customStatement(
      'INSERT INTO menus_local (id, libelle, type, cree_le, cree_par) '
      "VALUES ('m-1', 'Carte', 'local', 0, 'u-1')",
    );
    await base.customStatement(
      'INSERT INTO recettes_local (id, libelle, cree_le, cree_par) '
      "VALUES ('r-1', 'Riz', 0, 'u-1')",
    );
    await base.customStatement(
      'INSERT INTO plats_local (id, menu_id, recette_id, libelle, '
      'description, prix_vente, cree_le, cree_par) VALUES '
      "('p-1', 'm-1', 'r-1', 'Riz sauce', 'garde-moi', 2500, 0, 'u-1')",
    );
    await base.customStatement('PRAGMA user_version = 46');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    final p = await apres
        .customSelect('SELECT description FROM plats_local')
        .getSingle();
    expect(p.data['description'], 'garde-moi', reason: 'rien n’est écrasé');
    await apres.close();
  });
}
