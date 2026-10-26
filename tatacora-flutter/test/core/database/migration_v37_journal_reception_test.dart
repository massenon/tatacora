import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v36 -> v37 : UNE table neuve (`journal_reception_local`, le journal
/// de réception du poste, 26/10/2026), éprouvée sur un FICHIER RÉEL portant des
/// données (piège 2), y compris par un poste qui a sauté des livraisons.
///
/// Additive : la file d'envoi et le curseur de descente traversent intacts, la
/// table apparaît VIDE (la descente la remplit), sa clé est (table, élément) et
/// ses contraintes tiennent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v37_');
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
    for (final t in tablesAjouteesEnV37) {
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

  for (final depart in const [36, 26, 10]) {
    test('v$depart -> courante : la table apparaît vide, le parc et le '
        'curseur sont INTACTS, et elle sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(37));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV37]),
      );
      expect(await compte(apres, 'journal_reception_local'), 0);
      expect(await compte(apres, 'vehicules_local'), 1);
      if (depart >= 27) {
        expect(
          await compte(apres, 'etat_synchronisation_local'),
          greaterThanOrEqualTo(1),
        );
      }
      if (depart == 36) {
        // Une migration additive de la v36 ne touche pas au curseur.
        final curseur = await apres
            .customSelect(
              'SELECT valeur FROM etat_synchronisation_local '
              "WHERE cle = 'descente.curseur'",
            )
            .getSingle();
        expect(curseur.data['valeur'], 'abc');
      }

      const colonnes =
          'INSERT INTO journal_reception_local (table_serveur, element_id, '
          'issue, cause, recu_le, derniere_tentative_le) VALUES ';
      await apres.customStatement(
        "$colonnes('clients', 'c-1', 'aligne', 'aucune', 0, 0)",
      );
      await expectLater(
        apres.customStatement(
          "$colonnes('clients', 'c-1', 'refuse', 'donnee_illisible', 0, 0)",
        ),
        throwsA(anything),
        reason: 'clé : la table ET l’élément',
      );
      await apres.customStatement(
        "$colonnes('fournisseurs', 'c-1', 'refuse', 'donnee_illisible', 0, 0)",
      );
      await expectLater(
        apres.customStatement(
          "$colonnes('clients', 'c-2', 'perdu', 'aucune', 0, 0)",
        ),
        throwsA(anything),
        reason: 'issue : registre fermé',
      );
      await apres.close();

      final relue = AppDatabase.surFichier(fichier);
      final l = await relue
          .customSelect(
            'SELECT motif, tentatives, element_json '
            "FROM journal_reception_local WHERE table_serveur = 'clients'",
          )
          .getSingle();
      expect(l.data['motif'], '');
      expect(l.data['tentatives'], 1);
      expect(l.data['element_json'], isNull);
      await relue.close();
    });
  }
}
