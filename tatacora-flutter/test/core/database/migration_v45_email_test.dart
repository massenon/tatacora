import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v45 (28/10/2026 : l'e-mail FACULTATIF d'un employé et d'un
/// compte) : DEUX colonnes NULLABLES (`employes_local.email`,
/// `utilisateurs_local.email`), aucune table, éprouvées sur un FICHIER RÉEL
/// portant des données (piège 2).
///
/// Additive, et rien n'est déduit : les lignes d'avant n'ont pas d'adresse
/// (`NULL`, jamais une chaîne vide ni une adresse fabriquée à partir du nom ou
/// du login). Le curseur de descente est oublié : les adresses des employés déjà
/// au serveur redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v45_');
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

  /// Une base de la forme v44 : la courante, moins ce que la v45 ajoute (le
  /// retour arrière de `_ajoutsParVersion[45]`), avec des données d'avant.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement('ALTER TABLE employes_local DROP COLUMN email');
    await avant.customStatement(
      'ALTER TABLE utilisateurs_local DROP COLUMN email',
    );
    await avant.customStatement(
      'INSERT INTO services_rh_local (id, libelle) VALUES '
      "('s-1', 'Hébergement')",
    );
    await avant.customStatement(
      'INSERT INTO employes_local (id, matricule, nom, prenom, poste, '
      'service_id, date_embauche, salaire_base, statut) VALUES '
      "('e-1', 'EMP-2026-00001', 'KORA', 'Jean', 'Veilleur', 's-1', 0, "
      "80000, 'actif')",
    );
    await avant.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
      'sel, empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'n.kora', 'KORA Noël', 'administrateur', '{}', 's', "
      "'e', 1, 1, 0, 0)",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    expect(
      (await colonnes(avant, 'employes_local')).keys,
      isNot(contains('email')),
    );
    expect(
      (await colonnes(avant, 'utilisateurs_local')).keys,
      isNot(contains('email')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [44, 40]) {
    test('v$depart -> v45 : deux colonnes NULLABLES, l’existant est INTACT, '
        'aucune adresse fabriquée, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(45));

      for (final table in const ['employes_local', 'utilisateurs_local']) {
        final cols = await colonnes(apres, table);
        expect(cols.keys, contains('email'), reason: table);
        expect(cols['email'], isFalse, reason: '$table : NULLABLE');
      }

      final e = await apres
          .customSelect(
            "SELECT nom, salaire_base, email FROM employes_local WHERE id = 'e-1'",
          )
          .getSingle();
      expect((e.data['nom'], e.data['salaire_base']), ('KORA', 80000));
      expect(e.data['email'], isNull, reason: 'rien n’est déduit');
      final u = await apres
          .customSelect(
            "SELECT login, email FROM utilisateurs_local WHERE id = 'u-1'",
          )
          .getSingle();
      expect(u.data['login'], 'n.kora');
      expect(u.data['email'], isNull, reason: 'rien n’est déduit du login');

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
        "UPDATE employes_local SET email = 'jean.kora@exemple.bj' "
        "WHERE id = 'e-1'",
      );
      await apres.customStatement(
        "UPDATE utilisateurs_local SET email = 'n.kora@exemple.bj' "
        "WHERE id = 'u-1'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      expect(await version(relue), relue.schemaVersion);
      final lus = await relue
          .customSelect(
            'SELECT (SELECT email FROM employes_local) AS e, '
            '(SELECT email FROM utilisateurs_local) AS u',
          )
          .getSingle();
      expect(
        (lus.data['e'], lus.data['u']),
        ('jean.kora@exemple.bj', 'n.kora@exemple.bj'),
      );
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v45 '
      'mais marqué v44 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO services_rh_local (id, libelle) VALUES '
      "('s-1', 'Hébergement')",
    );
    await base.customStatement(
      'INSERT INTO employes_local (id, matricule, nom, prenom, email, poste, '
      'service_id, date_embauche, salaire_base, statut) VALUES '
      "('e-1', 'EMP-2026-00001', 'KORA', 'Jean', 'garde-moi@exemple.bj', "
      "'Veilleur', 's-1', 0, 80000, 'actif')",
    );
    await base.customStatement('PRAGMA user_version = 44');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    final e = await apres
        .customSelect('SELECT email FROM employes_local')
        .getSingle();
    expect(
      e.data['email'],
      'garde-moi@exemple.bj',
      reason: 'rien n’est écrasé',
    );
    await apres.close();
  });
}
