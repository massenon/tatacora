import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/domain/champs_profil.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// Migration -> v49 (03/11/2026 : « MON PROFIL » MODIFIABLE SOUS DROIT) : DEUX
/// colonnes NULLABLES sur `utilisateurs_local` et les trois droits `PROFIL_*` posés
/// dans les matrices déjà stockées — ADDITIVEMENT. Éprouvée sur un FICHIER RÉEL
/// portant des données (piège 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v49_');
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

  const insertionCompte =
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
      'sel, empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      'VALUES ';

  const insertionRole =
      'INSERT INTO roles_local (id, libelle, droits_json, date_creation, '
      'date_modification) VALUES ';

  /// Une base de la forme v48 : la courante, moins ce que la v49 ajoute, avec des
  /// données d'avant — matrices SANS les droits de profil, dont l'une déjà réglée.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement(
      'ALTER TABLE utilisateurs_local DROP COLUMN telephone',
    );
    await avant.customStatement(
      'ALTER TABLE utilisateurs_local DROP COLUMN intitule_de_poste',
    );
    await avant.customStatement('DELETE FROM roles_local');
    await avant.customStatement(
      "$insertionRole('r-adm', 'administrateur', '{\"M1\":\"C\"}', 0, 0), "
      "('r-bar', 'barman', '{\"M5\":\"C\",\"PROFIL_NOM\":\"-\"}', 0, 0), "
      "('r-x', 'role_libre', '{\"M3\":\"L\"}', 0, 0), "
      "('r-casse', 'casse', 'pas du json', 0, 0)",
    );
    await avant.customStatement(
      "$insertionCompte('u-1', 'n.kora', 'KORA Noël', 'administrateur', "
      "'{\"M1\":\"C\"}', 's', 'e', 1, 1, 0, 0), ('u-2', 'a.barman', 'Barman', "
      "'barman', '{\"M5\":\"C\",\"PROFIL_NOM\":\"-\"}', 's', 'e', 1, 1, 0, 0)",
    );
    expect(
      (await colonnes(avant, 'utilisateurs_local')).keys,
      isNot(contains('telephone')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  Future<Map<String, dynamic>> droitsDe(
    AppDatabase db,
    String table,
    String colonne,
    String cle,
  ) async {
    final l = await db
        .customSelect(
          'SELECT droits_json FROM $table WHERE $colonne = ?',
          variables: [Variable.withString(cle)],
        )
        .getSingle();
    return jsonDecode(l.data['droits_json'] as String) as Map<String, dynamic>;
  }

  for (final depart in const [48, 47, 44, 40]) {
    test('v$depart -> v49 : deux colonnes NULLABLES, droits de profil posés '
        'sans réécrire un réglage, rien de déduit', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(49));

      final cols = await colonnes(apres, 'utilisateurs_local');
      expect(cols['telephone'], isFalse, reason: 'NULLABLE');
      expect(cols['intitule_de_poste'], isFalse, reason: 'NULLABLE');
      final lignes = await apres
          .customSelect(
            'SELECT login, nom, telephone, intitule_de_poste '
            'FROM utilisateurs_local ORDER BY login',
          )
          .get();
      expect(lignes.map((l) => l.data['nom']), ['Barman', 'KORA Noël']);
      expect(lignes.map((l) => l.data['telephone']), everyElement(isNull));
      expect(
        lignes.map((l) => l.data['intitule_de_poste']),
        everyElement(isNull),
      );

      // Les matrices : nom et téléphone pour tous, intitulé pour les rôles
      // d'administration ; un réglage DÉJÀ fait (`PROFIL_NOM` = `-`) est intact.
      final adm = await droitsDe(
        apres,
        'roles_local',
        'libelle',
        'administrateur',
      );
      expect(adm['M1'], 'C');
      expect(adm['PROFIL_NOM'], 'C');
      expect(adm['PROFIL_TELEPHONE'], 'C');
      expect(adm['PROFIL_INTITULE'], 'C');
      final bar = await droitsDe(apres, 'roles_local', 'libelle', 'barman');
      expect(bar['PROFIL_NOM'], '-', reason: 'réglage conservé');
      expect(bar['PROFIL_TELEPHONE'], 'C');
      expect(bar['PROFIL_INTITULE'], '-');
      final libre = await droitsDe(
        apres,
        'roles_local',
        'libelle',
        'role_libre',
      );
      expect(libre['PROFIL_NOM'], 'C');
      expect(libre['PROFIL_INTITULE'], '-');
      final casse = await apres
          .customSelect(
            "SELECT droits_json FROM roles_local WHERE libelle = 'casse'",
          )
          .getSingle();
      expect(casse.data['droits_json'], 'pas du json', reason: 'jamais deviné');

      // Les comptes portent la même chose que leur rôle.
      final compteBar = await droitsDe(
        apres,
        'utilisateurs_local',
        'login',
        'a.barman',
      );
      expect(compteBar['PROFIL_NOM'], '-');
      expect(compteBar['PROFIL_TELEPHONE'], 'C');
      final compteAdm = await droitsDe(
        apres,
        'utilisateurs_local',
        'login',
        'n.kora',
      );
      expect(compteAdm['PROFIL_INTITULE'], 'C');

      // Les valeurs par défaut sont celles du domaine (et du serveur).
      for (final role in const ['administrateur', 'super_admin', 'barman']) {
        final socle = socleDuRole(role)!;
        final defauts = droitsProfilParDefaut(role);
        for (final e in defauts.entries) {
          expect(socle[e.key], e.value, reason: '$role ${e.key}');
        }
      }

      // Les colonnes SERVENT et survivent à la réouverture.
      await apres.customStatement(
        "UPDATE utilisateurs_local SET telephone = '+229 97', "
        "intitule_de_poste = 'Chef' WHERE login = 'n.kora'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      final lu = await relue
          .customSelect(
            "SELECT telephone, intitule_de_poste FROM utilisateurs_local WHERE login = 'n.kora'",
          )
          .getSingle();
      expect(lu.data['telephone'], '+229 97');
      expect(lu.data['intitule_de_poste'], 'Chef');
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v49 mais '
      'marqué v48 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      "$insertionCompte('u-2', 'a.barman', 'Barman', 'barman', "
      "'{\"PROFIL_NOM\":\"-\"}', 's', 'e', 1, 1, 0, 0)",
    );
    await base.customStatement(
      "UPDATE utilisateurs_local SET telephone = '97' WHERE id = 'u-2'",
    );
    await base.customStatement('PRAGMA user_version = 48');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    final u = await apres
        .customSelect(
          "SELECT telephone, droits_json FROM utilisateurs_local WHERE id = 'u-2'",
        )
        .getSingle();
    expect(u.data['telephone'], '97');
    expect(
      (jsonDecode(u.data['droits_json'] as String) as Map)['PROFIL_NOM'],
      '-',
    );
    await apres.close();
  });
}
