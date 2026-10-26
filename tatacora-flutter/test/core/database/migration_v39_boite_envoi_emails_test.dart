import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v38 -> v39 : UNE table neuve (`boite_envoi_emails_local`, la boîte
/// d'envoi des e-mails du poste, 26/10/2026), éprouvée sur un FICHIER RÉEL
/// portant des données (piège 2), y compris par un poste qui a sauté des
/// livraisons.
///
/// Additive : la file d'envoi et le parc traversent intacts, la table apparaît
/// VIDE (aucun e-mail n'est fabriqué pour les messages d'avant), la clé
/// d'idempotence est UNIQUE au schéma et les valeurs par défaut tiennent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v39_');
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
    for (final t in tablesAjouteesEnV39) {
      expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$cible');
    }
    expect(await version(avant), cible);
    await avant.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
    );
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [38, 26, 10]) {
    test('v$depart -> courante : la table apparaît vide, le parc est INTACT, '
        'la clé d’idempotence est UNIQUE et les défauts tiennent', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(39));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV39]),
      );
      expect(await compte(apres, 'boite_envoi_emails_local'), 0);
      expect(await compte(apres, 'vehicules_local'), 1);

      const colonnes =
          'INSERT INTO boite_envoi_emails_local (id, cle_idempotence, '
          'source, source_id, adresse, objet, corps, cree_le) VALUES ';
      await apres.customStatement(
        "$colonnes('e-1', 'notification:m-1', 'notification', 'm-1', "
        "'kora@exemple.bj', 'Objet', 'Corps', 0)",
      );
      await expectLater(
        apres.customStatement(
          "$colonnes('e-2', 'notification:m-1', 'notification', 'm-1', "
          "'kora@exemple.bj', 'Objet', 'Corps', 0)",
        ),
        throwsA(anything),
        reason: 'la même clé d’idempotence ne produit JAMAIS un second e-mail',
      );
      await apres.close();

      final relue = AppDatabase.surFichier(fichier);
      final l = await relue
          .customSelect(
            'SELECT statut, tentatives, derniere_erreur, envoye_le '
            "FROM boite_envoi_emails_local WHERE id = 'e-1'",
          )
          .getSingle();
      expect(l.data['statut'], 'en_attente');
      expect(l.data['tentatives'], 0);
      expect(l.data['derniere_erreur'], isNull);
      expect(l.data['envoye_le'], isNull);
      await relue.close();
    });
  }

  test('la migration rejouée sur un fichier déjà v39 mais marqué v38 ne plante '
      'pas, et ne perd rien (piège 3)', () async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement(
      'INSERT INTO boite_envoi_emails_local (id, cle_idempotence, source, '
      'adresse, objet, corps, cree_le) VALUES (\'e-1\', \'notification:m-1\', '
      '\'notification\', \'a@b.bj\', \'O\', \'C\', 0)',
    );
    await avant.customStatement('PRAGMA user_version = 38');
    await avant.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(await compte(apres, 'boite_envoi_emails_local'), 1);
    await apres.close();
  });
}
