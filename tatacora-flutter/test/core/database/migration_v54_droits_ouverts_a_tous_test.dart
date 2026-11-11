import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/domain/champs_profil.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// Migration -> v54 (09/11/2026 : « Synchronisation », « Appairage Postes » et
/// « Import & Export » au menu de TOUS les rôles par défaut) : AUCUNE table ni
/// colonne ; trois droits `SYNCHRO`, `APPAIRAGE`, `IMPORT_EXPORT` posés dans les
/// matrices DÉJÀ stockées — ADDITIVEMENT, sans réécrire un réglage ni retirer un
/// droit. Éprouvée sur un FICHIER RÉEL portant des données (piège 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v54_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

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

  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement('DELETE FROM roles_local');
    await avant.customStatement(
      "$insertionRole('r-adm', 'administrateur', '{\"M1\":\"C\"}', 0, 0), "
      // Un réglage fait à l'écran : IMPORT_EXPORT retiré au barman. Il PRIME.
      "('r-bar', 'barman', '{\"M5\":\"C\",\"IMPORT_EXPORT\":\"-\"}', 0, 0), "
      "('r-x', 'role_libre', '{\"M3\":\"L\"}', 0, 0), "
      "('r-casse', 'casse', 'pas du json', 0, 0)",
    );
    await avant.customStatement(
      "$insertionCompte('u-1', 'n.kora', 'KORA Noël', 'administrateur', "
      "'{\"M1\":\"C\"}', 's', 'e', 1, 1, 0, 0), ('u-2', 'a.barman', 'Barman', "
      "'barman', '{\"M5\":\"C\",\"IMPORT_EXPORT\":\"-\"}', 's', 'e', 1, 1, 0, 0)",
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

  for (final depart in const [53, 52, 49, 44]) {
    test('v$depart -> v54 : trois droits posés (L ; C pour l’administration) '
        'sans réécrire un réglage ni retirer un droit', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(54));

      final adm = await droitsDe(
        apres,
        'roles_local',
        'libelle',
        'administrateur',
      );
      expect(adm['M1'], 'C', reason: 'aucun droit existant retiré');
      for (final code in droitsOuvertsATous) {
        expect(adm[code], 'C', reason: 'administration : $code en C');
      }

      final bar = await droitsDe(apres, 'roles_local', 'libelle', 'barman');
      expect(bar['IMPORT_EXPORT'], '-', reason: 'le réglage d’écran PRIME');
      expect(bar['SYNCHRO'], 'L');
      expect(bar['APPAIRAGE'], 'L');
      expect(bar['M5'], 'C');

      final libre = await droitsDe(
        apres,
        'roles_local',
        'libelle',
        'role_libre',
      );
      for (final code in droitsOuvertsATous) {
        expect(
          libre[code],
          'L',
          reason: 'un rôle hors socle reçoit la lecture',
        );
      }

      // Les comptes suivent leur rôle.
      final compteAdm = await droitsDe(
        apres,
        'utilisateurs_local',
        'login',
        'n.kora',
      );
      expect(compteAdm['SYNCHRO'], 'C');
      final compteBar = await droitsDe(
        apres,
        'utilisateurs_local',
        'login',
        'a.barman',
      );
      expect(compteBar['IMPORT_EXPORT'], '-');
      expect(compteBar['APPAIRAGE'], 'L');

      // Une matrice illisible n'est jamais touchée (aucun droit deviné).
      final casse = await apres
          .customSelect(
            "SELECT droits_json FROM roles_local WHERE libelle = 'casse'",
          )
          .getSingle();
      expect(casse.data['droits_json'], 'pas du json');
      await apres.close();
    });
  }

  test('idempotente : rejouer la migration ne change plus rien', () async {
    await preparer(53);
    final a = AppDatabase.surFichier(fichier);
    final premiere = await droitsDe(a, 'roles_local', 'libelle', 'barman');
    await a.close();
    // Rouvrir à la version courante ne rejoue pas ; forcer 53 la rejoue.
    final b = AppDatabase.surFichier(fichier);
    await b.customStatement('PRAGMA user_version = 53');
    await b.close();
    final c = AppDatabase.surFichier(fichier);
    expect(await droitsDe(c, 'roles_local', 'libelle', 'barman'), premiere);
    await c.close();
  });

  test('le socle du poste et les défauts d’un rôle neuf disent la même chose '
      'que le serveur : L pour tous, C pour l’administration', () {
    for (final e in socleRbacCdcf.entries) {
      for (final code in droitsOuvertsATous) {
        expect(
          e.value[code],
          // IMPORT_EXPORT : `C` aussi pour le gérant et le comptable (PO 11/11/2026).
          rolesAdministrationProfil.contains(e.key) ||
                  (code == 'IMPORT_EXPORT' &&
                      const {'gerant', 'comptable'}.contains(e.key))
              ? 'C'
              : 'L',
          reason: '${e.key} / $code',
        );
      }
    }
    expect(droitsOuvertsATousParDefaut('barman'), {
      'SYNCHRO': 'L',
      'APPAIRAGE': 'L',
      'IMPORT_EXPORT': 'L',
    });
  });
}
