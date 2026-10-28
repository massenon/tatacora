import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

import 'retour_arriere_schema.dart';

/// Migration v23 -> v24 : UNE table neuve (`roles_local`, D438, 14/10/2026),
/// éprouvée sur un FICHIER RÉEL portant un compte (piège 2).
///
/// Additive : aucune table existante n'est touchée, et AUCUNE ligne n'est
/// semée par la migration — le socle est posé par `RolesDao.installerSocle`
/// à la première lecture de l'écran, et les droits du compte d'avant restent
/// les siens.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v24_');
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

  const droitsAvant = '{"M5":"C","M6":"L"}';

  test('v23 -> v24 : la table APPARAÎT vide, le compte d’avant est INTACT ; '
      'le socle se pose ensuite au geste, sans toucher le compte', () async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, 23);
    final tablesAvant = await tables(avant);
    expect(tablesAvant.intersection(tablesAjouteesEnV24), isEmpty);
    await avant.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, sel, '
      'empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'barman1', 'Barman', 'barman', '$droitsAvant', 's', "
      "'e', 1, 1, 0, 0)",
    );
    await avant.close();

    final apres = AppDatabase.surFichier(fichier);
    final version = await apres.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, apres.schemaVersion);
    expect(apres.schemaVersion, greaterThanOrEqualTo(24));
    expect(await tables(apres), {
      ...tablesAvant,
      ...tablesAjouteesEnV24,
      ...tablesAjouteesEnV25,
      ...tablesAjouteesEnV26,
      ...tablesAjouteesEnV27,
      ...tablesAjouteesEnV28,
      ...tablesAjouteesEnV29,
      ...tablesAjouteesEnV31,
      ...tablesAjouteesEnV32,
      ...tablesAjouteesEnV33,
      ...tablesAjouteesEnV34,
      ...tablesAjouteesEnV35,
      ...tablesAjouteesEnV37,
      ...tablesAjouteesEnV38,
      ...tablesAjouteesEnV39,
      ...tablesAjouteesEnV40,
      ...tablesAjouteesEnV44,
    });

    final roles = await apres
        .customSelect('SELECT COUNT(*) AS n FROM roles_local')
        .getSingle();
    expect(roles.data['n'], 0, reason: 'la migration ne sème rien');
    final u = await apres
        .customSelect('SELECT role, droits_json FROM utilisateurs_local')
        .getSingle();
    expect((u.data['role'], u.data['droits_json']), ('barman', droitsAvant));

    // Le poste migré est utilisable : le socle se pose, le compte compte, et
    // ses droits ne sont réécrits que par un geste de l'écran.
    final dao = RolesDao(apres);
    expect(await dao.installerSocle(), socleRbacCdcf.length);
    final barman = (await dao.roles()).singleWhere(
      (r) => r.libelle == 'barman',
    );
    expect(barman.comptes, 1);
    final relu = await apres
        .customSelect('SELECT droits_json FROM utilisateurs_local')
        .getSingle();
    expect(relu.data['droits_json'], droitsAvant);
    await apres.close();
  });
}
