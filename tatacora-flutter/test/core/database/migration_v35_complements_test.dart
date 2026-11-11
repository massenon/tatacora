import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v34 -> v35 : QUATRE tables neuves (immobilisations, relances,
/// inventaires et leurs lignes) et CINQ colonnes (`actif` des articles et des
/// clients, composition provisoire, remise du panier), éprouvées sur un FICHIER
/// RÉEL portant des données (piège 2), y compris par un poste qui a sauté des
/// livraisons. Additive : les saisies d'avant traversent intactes, les défauts
/// sont des faits (tout est actif, rien n'est provisoire ni remisé), et le
/// curseur de descente est oublié.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v35_');
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

  Future<Set<String>> colonnes(AppDatabase db, String t) async => {
    for (final c in await db.customSelect('PRAGMA table_info($t)').get())
      c.data['name'] as String,
  };

  Future<int> compte(AppDatabase db, String t) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $t').getSingle())
              .data['n']
          as int;

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  for (final depart in const [34, 33, 26, 10]) {
    test('v$depart -> courante : tables vides, colonnes aux défauts, données '
        'd’avant INTACTES, et le tout sert', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      final tablesAvant = await tables(avant);
      for (final t in tablesAjouteesEnV35) {
        expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$depart');
      }
      expect(await colonnes(avant, 'articles_local'), isNot(contains('actif')));
      await avant.customStatement(
        'INSERT INTO vehicules_local (id, categorie, immatriculation, '
        "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
      );
      if (depart >= 27) {
        await avant.customStatement(
          'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
          "VALUES ('descente.curseur', 'abc', 0)",
        );
      }
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(35));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV35]),
      );
      for (final t in tablesAjouteesEnV35) {
        expect(await compte(apres, t), 0, reason: t);
      }
      expect(await colonnes(apres, 'articles_local'), contains('actif'));
      expect(await colonnes(apres, 'clients_local'), contains('actif'));
      expect(
        await colonnes(apres, 'recettes_local'),
        contains('composition_provisoire'),
      );
      expect(
        await colonnes(apres, 'paniers_local'),
        containsAll(['remise_type', 'remise_valeur_centiemes']),
      );
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
        'INSERT INTO immobilisations_local (id, code, libelle, '
        'valeur_origine_centimes, date_mise_service) '
        "VALUES ('i-1', 'IMMO-1', 'Camion', 1000000, '2026-01-01')",
      );
      await expectLater(
        apres.customStatement(
          'INSERT INTO immobilisations_local (id, code, libelle, '
          'valeur_origine_centimes, date_mise_service) '
          "VALUES ('i-1', 'IMMO-2', 'Autre', 1, '2026-01-01')",
        ),
        throwsA(anything),
        reason: 'clé : l’identifiant',
      );
      await apres.close();
    });
  }
}
