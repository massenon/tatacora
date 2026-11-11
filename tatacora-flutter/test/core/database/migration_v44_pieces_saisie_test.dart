import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

/// Migration -> v44 (D246 rouvert, 28/10/2026 : comptes et pièces saisies à la
/// main partagés) : UNE table neuve (`pieces_saisie_local`) et UNE colonne
/// NULLABLE (`ecritures_serveur_local.piece_origine_id`), éprouvées sur un
/// FICHIER RÉEL portant des données (piège 2).
///
/// Additive, et rien n'est déduit : une pièce saisie avant la v44 n'est ni
/// marquée ni envoyée (aucune ligne fabriquée dans `pieces_saisie_local`), une
/// ligne du miroir d'avant n'a pas d'origine. Le curseur de descente est oublié :
/// le plan du serveur et l'origine des pièces redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v44_');
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

  /// Une base de la forme v43 : la courante, moins ce que la v44 ajoute (le
  /// retour arrière de `_ajoutsParVersion[44]`), avec des données d'avant.
  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await avant.customStatement('DROP TABLE pieces_saisie_local');
    await avant.customStatement(
      'ALTER TABLE ecritures_serveur_local DROP COLUMN piece_origine_id',
    );
    await avant.customStatement(
      'INSERT INTO ecritures_serveur_local (id, annee, code_journal, '
      'numero_compte, libelle_compte, classe, date_ecriture, libelle, '
      "debit_centimes, credit_centimes) VALUES ('e-1', 2031, 'OD', '5711', "
      "'Caisse', '5', '2031-06-10', 'Avant la v44', 1500, 0)",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    final tablesAvant = await tables(avant);
    expect(tablesAvant, isNot(contains('pieces_saisie_local')));
    expect(
      (await colonnes(avant, 'ecritures_serveur_local')).keys,
      isNot(contains('piece_origine_id')),
    );
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [43, 42]) {
    test('v$depart -> v44 : table neuve, colonne NULLABLE, l’existant est '
        'INTACT, rien n’est fabriqué, et ça sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(44));
      expect(await tables(apres), containsAll(tablesAvant));
      expect(await tables(apres), contains('pieces_saisie_local'));

      final cols = await colonnes(apres, 'ecritures_serveur_local');
      expect(cols.keys, contains('piece_origine_id'));
      expect(cols['piece_origine_id'], isFalse, reason: 'NULLABLE');

      // Aucune pièce de saisie fabriquée ; la ligne d'avant n'a pas d'origine.
      expect(
        (await apres
                .customSelect('SELECT COUNT(*) AS n FROM pieces_saisie_local')
                .getSingle())
            .data['n'],
        0,
      );
      final e = await apres
          .customSelect(
            'SELECT libelle, debit_centimes, piece_origine_id '
            "FROM ecritures_serveur_local WHERE id = 'e-1'",
          )
          .getSingle();
      expect(e.data['libelle'], 'Avant la v44');
      expect(e.data['debit_centimes'], 1500);
      expect(e.data['piece_origine_id'], isNull);

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

      // La table et la colonne SERVENT, et survivent à la réouverture.
      await apres.customStatement(
        'INSERT INTO pieces_saisie_local (id, numero_piece, code_journal, '
        'date_piece, libelle, statut, cree_le) VALUES '
        "('p-1', 'OD-2031-00001', 'OD', '2031-06-10', 'Régularisation', "
        "'validee', 1788000000)",
      );
      await apres.customStatement(
        "UPDATE ecritures_serveur_local SET piece_origine_id = 'p-1' "
        "WHERE id = 'e-1'",
      );
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      expect(await version(relue), relue.schemaVersion);
      final p = await relue
          .customSelect(
            'SELECT p.numero_piece, e.piece_origine_id FROM pieces_saisie_local p '
            'JOIN ecritures_serveur_local e ON e.piece_origine_id = p.id',
          )
          .getSingle();
      expect(p.data['numero_piece'], 'OD-2031-00001');
      expect(p.data['piece_origine_id'], 'p-1');
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v44 '
      'mais marqué v42 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO pieces_saisie_local (id, numero_piece, code_journal, '
      'date_piece, libelle, statut, cree_le) VALUES '
      "('p-1', 'OD-2031-00001', 'OD', '2031-06-10', 'Garde-moi', 'brouillon', 1)",
    );
    await base.customStatement('PRAGMA user_version = 42');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    final p = await apres
        .customSelect('SELECT libelle FROM pieces_saisie_local')
        .getSingle();
    expect(p.data['libelle'], 'Garde-moi', reason: 'rien n’est écrasé');
    expect(
      (await colonnes(apres, 'ecritures_serveur_local')).keys,
      contains('piece_origine_id'),
    );
    await apres.close();
  });
}
