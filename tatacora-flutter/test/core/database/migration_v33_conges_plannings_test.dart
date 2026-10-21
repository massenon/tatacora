import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v32 -> v33 : DEUX tables neuves (`plannings_local` et
/// `conges_local`, 21/10/2026), éprouvées sur un FICHIER RÉEL portant des
/// données (piège 2), y compris par un poste qui a sauté des livraisons.
///
/// Additive : la file d'envoi et le parc traversent intacts, AUCUNE ligne n'est
/// semée, et le curseur de descente est oublié (les créneaux et les demandes
/// déjà au serveur doivent redescendre).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v33_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

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
    for (final t in tablesAjouteesEnV33) {
      expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$cible');
    }
    expect(await version(avant), cible);
    await avant.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
    );
    if (cible >= 27) {
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'abc', 0)",
      );
    }
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [32, 26, 10]) {
    test('v$depart -> courante : les tables apparaissent vides, le parc est '
        'INTACT, et elles servent', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(33));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV33]),
      );
      expect(await compte(apres, 'plannings_local'), 0);
      expect(await compte(apres, 'conges_local'), 0);
      expect(await compte(apres, 'vehicules_local'), 1);
      if (depart >= 27) {
        expect(
          await apres
              .customSelect(
                'SELECT COUNT(*) AS n FROM etat_synchronisation_local '
                "WHERE cle = 'descente.curseur'",
              )
              .getSingle()
              .then((l) => l.data['n']),
          0,
          reason: 'le catalogue redescend une fois',
        );
      }

      await apres.customStatement(
        'INSERT INTO plannings_local (id, employe_id, service_id, date, '
        "heure_debut, heure_fin) VALUES ('p-1', 'e-1', 's-1', 0, '08:00', '12:00')",
      );
      await apres.customStatement(
        'INSERT INTO conges_local (id, employe_id, type, date_debut, date_fin) '
        "VALUES ('c-1', 'e-1', 'annuel', 0, 86400)",
      );
      await expectLater(
        apres.customStatement(
          'INSERT INTO conges_local (id, employe_id, type, date_debut, '
          "date_fin) VALUES ('c-1', 'e-2', 'maladie', 0, 0)",
        ),
        throwsA(anything),
        reason: 'clé : l’identifiant',
      );
      await apres.close();

      final relue = AppDatabase.surFichier(fichier);
      final c = await relue
          .customSelect('SELECT statut_validation FROM conges_local')
          .getSingle();
      expect(
        c.data['statut_validation'],
        'en_attente',
        reason: 'une demande attend sa décision par défaut',
      );
      await relue.close();
    });
  }
}
