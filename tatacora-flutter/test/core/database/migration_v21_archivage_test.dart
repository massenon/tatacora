import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart'
    show RefusAchats;
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';

import '../../features/achats/support/outils_reglement.dart';
import '../../features/comptabilite/support/outils_comptabilite.dart';
import 'retour_arriere_schema.dart';

/// Migration v20 -> v21 : UNE colonne AJOUTÉE (`fournisseurs_local.actif`), aucune
/// table, éprouvée sur un FICHIER RÉEL portant des données (piège 2), y compris
/// en sautant des versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des données AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Rien n'est recréé : un fournisseur et ses commandes d'avant la mise à jour
/// sont la seule copie qui existe. Et la migration NE DÉDUIT RIEN : les
/// fournisseurs d'avant naissent actifs parce que c'est un FAIT (le geste
/// d'archivage était refusé, aucun n'a été archivé), pas parce qu'on le suppose.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v21_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<int> version(AppDatabase db) async {
    final r = await db.customSelect('PRAGMA user_version').getSingle();
    return r.data.values.first as int;
  }

  Future<Set<String>> tables(AppDatabase db) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return {for (final l in r) l.data['name'] as String};
  }

  Future<List<String>> colonnes(AppDatabase db, String table) async {
    final r = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final c in r) c.data['name'] as String];
  }

  /// Ce que le poste portait AVANT : un auteur, deux fournisseurs, et une
  /// commande envoyée chez le premier — au format v20.
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    for (final (id, nom) in [('f-v20a', 'Alpha'), ('f-v20b', 'Bravo')]) {
      await db.customStatement(
        'INSERT INTO fournisseurs_local (id, raison_sociale, cree_le, cree_par) '
        'VALUES (?, ?, 1787000000, ?)',
        [id, nom, auteurEssai],
      );
    }
    await db.customStatement(
      'INSERT INTO commandes_achat_local (id, fournisseur_id, date_commande, '
      "statut, cree_le, utilisateur_id) VALUES ('c-v20', 'f-v20a', "
      "'2026-10-01', 'envoyee', 1787000100, ?)",
      [auteurEssai],
    );
  }

  group('v20 -> v21 — la mise à jour d’un poste qui avait des fournisseurs', () {
    test('la fixture ramène bien le fichier à la forme v20 : UNE colonne en '
        'moins, aucune table', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 20);

      expect(await version(db), 20);
      expect(
        await colonnes(db, 'fournisseurs_local'),
        isNot(contains('actif')),
      );
      await db.close();
    });

    test('à la réouverture : la colonne est AJOUTÉE en dernier, aucune table '
        'n’apparaît, les fournisseurs d’avant sont ACTIFS et INTACTS', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 20);
      await semerAvant(avant);
      final tablesAvant = await tables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(21));

      // Aucune table neuve à la v21, aucune table perdue (les v22 et v23
      // ajoutent les leurs, rouvert au schéma courant).
      expect(await tables(apres), {
        ...tablesAvant,
        ...tablesAjouteesEnV22,
        ...tablesAjouteesEnV23,
        ...tablesAjouteesEnV24,
        ...tablesAjouteesEnV25,
        ...tablesAjouteesEnV26,
        ...tablesAjouteesEnV27,
        ...tablesAjouteesEnV28,
        ...tablesAjouteesEnV29,
        ...tablesAjouteesEnV31,
        ...tablesAjouteesEnV32,
        ...tablesAjouteesEnV33,
      });

      // La colonne est en DERNIER, et une base NEUVE a le même ordre.
      final migrees = await colonnes(apres, 'fournisseurs_local');
      expect(migrees.last, 'actif');
      expect(migrees.where((c) => c == 'actif'), hasLength(1));
      final neuve = AppDatabase.enMemoire();
      await neuve.customStatement('SELECT 1');
      expect(migrees, await colonnes(neuve, 'fournisseurs_local'));
      await neuve.close();

      // Les fournisseurs d'avant : intacts et ACTIFS (un fait, pas une déduction).
      final lignes = await apres
          .customSelect(
            'SELECT id, raison_sociale, actif FROM fournisseurs_local ORDER BY id',
          )
          .get();
      expect(
        [
          for (final l in lignes)
            (l.data['id'], l.data['raison_sociale'], l.data['actif']),
        ],
        [('f-v20a', 'Alpha', 1), ('f-v20b', 'Bravo', 1)],
      );
      // La commande d'avant n'a pas bougé.
      final cmd = await apres
          .customSelect('SELECT statut FROM commandes_achat_local')
          .getSingle();
      expect(cmd.data['statut'], 'envoyee');
      await apres.close();
    });

    test('le poste migré est UTILISABLE : le fournisseur engagé d’AVANT '
        'refuse l’archivage, l’autre s’archive et se restaure', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 20);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      await baseInstalleeSur(db, jourReglement);
      final achats = achatsDaoSur(db);

      // Alpha porte une commande envoyée AVANT la mise à jour : le verrou la voit.
      await expectLater(
        achats.archiverFournisseur('f-v20a', auteurId: auteurEssai),
        throwsA(
          isA<RefusAchats>().having(
            (e) => e.motif,
            'motif',
            MessagesAchats.verrouArchivage(1),
          ),
        ),
      );
      // Bravo s'archive, disparaît du sélecteur, et se restaure.
      await achats.archiverFournisseur('f-v20b', auteurId: auteurEssai);
      expect(
        [for (final f in await achats.tousLesFournisseurs()) f.id],
        ['f-v20a'],
      );
      final bravo = await achats.restaurerFournisseur(
        'f-v20b',
        auteurId: auteurEssai,
      );
      expect(bravo.actif, isTrue);
      await db.close();
    });

    test('un fichier déjà à la forme v21 mais marqué v20 ne plante pas et ne '
        'perd rien (l’ajout de colonne est conditionnel)', () async {
      // L'état d'un poste qui a reçu un fichier de test, ou qui a restauré une
      // sauvegarde : la colonne existe déjà (piège 3, « duplicate column name »).
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await db.customStatement(
        'INSERT INTO fournisseurs_local (id, raison_sociale, cree_le, cree_par, '
        "actif) VALUES ('f-x', 'Archivé avant', 1787000000, ?, 0)",
        [auteurEssai],
      );
      await db.customStatement('PRAGMA user_version = 20');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      final r = await rouvert
          .customSelect("SELECT actif FROM fournisseurs_local WHERE id = 'f-x'")
          .getSingle();
      expect(r.data['actif'], 0, reason: 'un archivé le reste');
      await rouvert.close();
    });

    test('la contrainte de la colonne tient sur le fichier migré', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 20);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      Future<void> poser(Object? valeur) => db.customStatement(
        'UPDATE fournisseurs_local SET actif = ? WHERE id = ?',
        [valeur, 'f-v20b'],
      );

      await poser(0); // un booléen
      await poser(1);
      await expectLater(poser(2), throwsA(isA<SqliteException>()));
      await expectLater(poser(null), throwsA(isA<SqliteException>()));
      await db.close();
    });
  });

  group('v10 -> v21 — le poste qui a sauté onze livraisons', () {
    test('la chaîne s’exécute sur un fichier v10 portant des dépenses, et '
        'l’archivage est possible après', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 10);
      await semerAuteur(avant);
      const jour = 1787000000;
      await avant.customStatement(
        'INSERT INTO depenses_local (id, date_transaction, tresorerie, '
        'libelle, saisie_le) VALUES (?, ?, ?, ?, ?)',
        ['dep-1', jour, 'caisse', 'Marché du matin', jour],
      );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await colonnes(apres, 'fournisseurs_local'), contains('actif'));

      final achats = achatsDaoSur(apres);
      await semerCommande(apres, statut: 'cloturee');
      await achats.archiverFournisseur('f-1', auteurId: auteurEssai);
      expect(
        (await apres.select(apres.fournisseursLocal).getSingle()).actif,
        isFalse,
      );
      await apres.close();
    });
  });

  group('v2 -> v21 — la chaîne ENTIÈRE', () {
    test('un fichier v2 (la première livraison du poste) arrive à la v21 avec '
        'la colonne, une seule fois', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 2);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(21));
      // `fournisseurs_local` est créée par `createTable` à la v13, à sa définition
      // COURANTE : la colonne y est DÉJÀ, et la v21 ne doit pas la rajouter.
      final noms = await colonnes(apres, 'fournisseurs_local');
      expect(noms.where((n) => n == 'actif'), hasLength(1));

      await semerAuteur(apres);
      await semerCommande(apres, statut: 'cloturee');
      await achatsDaoSur(
        apres,
      ).archiverFournisseur('f-1', auteurId: auteurEssai);
      expect(
        (await apres.select(apres.fournisseursLocal).getSingle()).actif,
        isFalse,
      );
      await apres.close();
    });
  });
}
