import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/database/reconcilier_schema.dart';

/// R2 (PRD réinstallation) : une base à `user_version = 44` à laquelle on retire
/// une table, une colonne et un déclencheur est rétablie à l'ouverture, et ce
/// qui est posé est écrit au journal ; rien n'est jamais retiré.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('tatacora_reconcilier_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });
  tearDown(() {
    try {
      dossier.deleteSync(recursive: true);
    } on FileSystemException {
      // Verrou Windows : sans conséquence.
    }
  });

  Future<void> creerBaseCourante() async {
    final db = AppDatabase.surFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      'INSERT INTO parametres_systeme_local (cle, valeur, modifie_le) '
      "VALUES ('k', 'garde-moi', 0)",
    );
    await db.close();
  }

  Future<void> abimer(List<String> instructions) async {
    final db = AppDatabase.surFichier(fichier);
    for (final i in instructions) {
      await db.customStatement(i);
    }
    await db.close();
  }

  Future<Set<String>> noms(AppDatabase db, String type) async => {
    for (final l
        in await db
            .customSelect(
              'SELECT name FROM sqlite_master WHERE type = ?',
              variables: [Variable.withString(type)],
            )
            .get())
      l.data['name'] as String,
  };

  test('table, colonne et déclencheur retirés : rétablis à l ouverture, '
      'journalisés, la ligne survit', () async {
    await creerBaseCourante();
    await abimer([
      'DROP TABLE pieces_saisie_local',
      'ALTER TABLE parametres_systeme_local DROP COLUMN valeur',
      'DROP TRIGGER rg11_exercice_clos_ajout',
    ]);

    final lignes = <String>[];
    final db = AppDatabase.surFichier(fichier)..journalDemarrage = lignes.add;
    await db.customSelect('SELECT 1').get();

    expect(await noms(db, 'table'), contains('pieces_saisie_local'));
    expect(await noms(db, 'trigger'), contains('rg11_exercice_clos_ajout'));
    final colonnes = {
      for (final c
          in await db
              .customSelect('PRAGMA table_info(parametres_systeme_local)')
              .get())
        c.data['name'] as String,
    };
    expect(colonnes, contains('valeur'));
    final ligne = await db
        .customSelect('SELECT cle, valeur FROM parametres_systeme_local')
        .getSingle();
    expect(ligne.data['cle'], 'k');
    expect(ligne.data['valeur'], '', reason: 'NOT NULL : DEFAULT explicite');

    final journal = lignes.join('\n');
    expect(journal, contains('Réconciliation du schéma'));
    expect(journal, contains('pieces_saisie_local'));
    expect(journal, contains('parametres_systeme_local.valeur'));
    expect(journal, contains('rg11_exercice_clos_ajout'));
    expect(await ecartRapide(db), isFalse);
    await db.close();
  });

  test(
    'jamais destructive : table et colonne en trop laissées et journalisées',
    () async {
      await creerBaseCourante();
      await abimer([
        'CREATE TABLE table_en_trop (a INTEGER)',
        'ALTER TABLE parametres_systeme_local ADD COLUMN colonne_en_trop TEXT',
        'INSERT INTO table_en_trop VALUES (7)',
      ]);
      final lignes = <String>[];
      final db = AppDatabase.surFichier(fichier)..journalDemarrage = lignes.add;
      final rapport = await reconcilierSchema(db);
      expect(rapport.aPose, isFalse);
      expect(
        (await db.customSelect('SELECT a FROM table_en_trop').getSingle()).data,
        {'a': 7},
      );
      expect(rapport.enTrop, contains('table table_en_trop'));
      expect(
        rapport.enTrop,
        contains('colonne parametres_systeme_local.colonne_en_trop'),
      );
      expect(lignes.join(), contains('LAISSÉS'));
      await db.close();
    },
  );

  test(
    'le contrôle rapide voit un déclencheur, une colonne, une table',
    () async {
      final db = AppDatabase.enMemoire();
      await db.customSelect('SELECT 1').get();
      expect(await ecartRapide(db), isFalse);
      for (final casse in [
        'DROP TRIGGER rg11_ecriture_jamais_supprimee',
        'ALTER TABLE parametres_systeme_local DROP COLUMN modifie_par',
        'DROP TABLE pieces_saisie_local',
      ]) {
        await db.customStatement(casse);
        expect(await ecartRapide(db), isTrue, reason: casse);
        await reconcilierSchema(db);
        expect(await ecartRapide(db), isFalse, reason: casse);
      }
      await db.close();
    },
  );

  test(
    'onUpgrade se termine par la réconciliation (user_version ancienne)',
    () async {
      await creerBaseCourante();
      await abimer([
        'ALTER TABLE parametres_systeme_local DROP COLUMN modifie_par',
        'PRAGMA user_version = 43',
      ]);
      final lignes = <String>[];
      final db = AppDatabase.surFichier(fichier)..journalDemarrage = lignes.add;
      await db.customSelect('SELECT 1').get();
      final colonnes = {
        for (final c
            in await db
                .customSelect('PRAGMA table_info(parametres_systeme_local)')
                .get())
          c.data['name'] as String,
      };
      expect(colonnes, contains('modifie_par'));
      expect(lignes.join(), contains('migrée depuis v43'));
      expect(lignes.join(), contains('parametres_systeme_local.modifie_par'));
      await db.close();
    },
  );

  test('une base saine : aucun écart, rien posé', () async {
    await creerBaseCourante();
    final db = AppDatabase.surFichier(fichier);
    expect(await ecartRapide(db), isFalse);
    expect((await reconcilierSchema(db)).aPose, isFalse);
    await db.close();
  });
}
