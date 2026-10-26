import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';

import '../../features/caisse/support/outils_caisse.dart';
import '../../features/comptabilite/support/outils_comptabilite.dart';
import '../../features/depenses/support/outils_depenses.dart';
import 'retour_arriere_schema.dart';

/// Migration v16 -> v17 : UNE table neuve (`sessions_caisse_local`), éprouvée sur
/// un FICHIER RÉEL portant des données (piège 2), y compris en sautant des
/// versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des données AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// La table est AJOUTÉE, rien n'est recréé : les dépenses et leurs pièces
/// saisies avant la mise à jour sont la seule copie qui existe. Et la migration
/// NE FABRIQUE AUCUNE SESSION : une migration ne sait pas quelle caisse était
/// ouverte hier, et un fond de caisse inventé serait lu comme un fait.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v17_');
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

  Future<bool> tableExiste(AppDatabase db, String nom) async {
    final r = await db
        .customSelect(
          "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
          'AND name = ?',
          variables: [Variable<String>(nom)],
        )
        .getSingle();
    return (r.data['n'] as int) == 1;
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

  /// Ce que le poste portait AVANT : un auteur et deux dépenses au format v16.
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    const jour = 1787000000;
    for (final (id, tresorerie, libelle, montant) in [
      ('dep-1', 'caisse', 'Marché du matin', 15000),
      ('dep-2', 'banque', 'Électricité', 45000),
    ]) {
      await db.customStatement(
        'INSERT INTO depenses_local (id, date_transaction, tresorerie, '
        'libelle, saisie_le) VALUES (?, ?, ?, ?, ?)',
        [id, jour, tresorerie, libelle, jour],
      );
      await db.customStatement(
        'INSERT INTO lignes_depense_local (id, depense_id, libelle, '
        'compte_charge, nature, famille, montant, ajoutee_le) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        ['l-$id', id, 'Achat', '6011', 'Tomate', 'Marché', montant, jour],
      );
    }
  }

  group('v16 -> v17 — la mise à jour d’un poste qui avait des dépenses', () {
    test('la fixture ramène bien le fichier à la forme v16 : UNE table en '
        'moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 16);

      expect(await version(db), 16);
      for (final t in tablesAjouteesEnV17) {
        expect(await tableExiste(db, t), isFalse, reason: '$t devrait manquer');
      }
      // Les tables de la v15 et v16, elles, sont intactes.
      expect(await tableExiste(db, 'ecritures_local'), isTrue);
      expect(
        await colonnes(db, 'depenses_local'),
        containsAll(['ecriture_id', 'ecriture_refus']),
      );
      await db.close();
    });

    test('à la réouverture : la table est créée VIDE, les données antérieures '
        'sont INTACTES, aucune session fabriquée', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 16);
      await semerAvant(avant);
      final tablesAvant = await tables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(17));

      final tablesApres = await tables(apres);
      // La v18 (encaissement de facture) s'ajoute à la réouverture, après la v17 :
      // sa table neuve est comptée avec celle de la caisse.
      expect(tablesApres.difference(tablesAvant), {
        ...tablesAjouteesEnV17,
        ...tablesAjouteesEnV18,
        ...tablesAjouteesEnV20,
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
        ...tablesAjouteesEnV34,
        ...tablesAjouteesEnV35,
        ...tablesAjouteesEnV37,
      });
      expect(tablesAvant.difference(tablesApres), isEmpty);

      expect(await colonnes(apres, 'sessions_caisse_local'), [
        'id',
        'point_vente',
        'utilisateur_ouverture_id',
        'date_ouverture',
        'montant_fond_centimes',
        'date_cloture',
        'montant_theorique_centimes',
        'montant_constate_centimes',
      ]);
      expect(await compterLignes(apres, 'sessions_caisse_local'), 0);

      // La donnée antérieure est la seule copie qui existe : elle survit.
      expect(await compterLignes(apres, 'depenses_local'), 2);
      expect(await compterLignes(apres, 'lignes_depense_local'), 2);
      expect(await compterLignes(apres, 'utilisateurs_local'), 1);
      await apres.close();
    });

    test('le poste migré est UTILISABLE : on ouvre, on clôture, on rouvre — '
        'et la dépense saisie avant reste lisible', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 16);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      final dao = daoCaisseSur(db);
      final s = await dao.ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '25000',
        auteurId: auteurEssai,
        peutEcrire: true,
      );
      expect(s.fondCentimes, 2500000);
      await expectLater(
        dao.ouvrir(
          point: PointDeVenteCaisse.bar,
          fondSaisi: '1',
          auteurId: auteurEssai,
          peutEcrire: true,
        ),
        throwsA(anything),
      );
      await dao.cloturer(
        point: PointDeVenteCaisse.bar,
        constateSaisi: '25000',
        peutEcrire: true,
        especesEncaisseesCentimes: 0,
      );
      expect((await dao.sessions()).single.estOuverte, isFalse);

      // Les contraintes de la table neuve tiennent sur le fichier migré.
      await expectLater(
        db.customStatement(
          'INSERT INTO sessions_caisse_local (id, point_vente, '
          'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
          "VALUES ('x', 'plage', ?, 1787000000, 0)",
          [auteurEssai],
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db.customStatement(
          'INSERT INTO sessions_caisse_local (id, point_vente, '
          'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
          "VALUES ('y', 'bar', 'fantome', 1787000000, 0)",
          [],
        ),
        throwsA(isA<SqliteException>()),
      );

      // Et la dépense d'avant se lit toujours.
      final depenses = await depenseDaoSur(db).depenses();
      expect(depenses.map((d) => d.montantTotal).toList()..sort(), [
        15000,
        45000,
      ]);
      await db.close();
    });

    test('une dépense peut encore passer sa pièce sur le fichier migré '
        '(la caisse ne casse pas le moteur comptable)', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 16);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      await baseInstalleeSur(db, jourDeReference);
      final neuve = await depenseDaoSur(db).enregistrer(
        dateTransaction: DateTime(2026, 10, 1),
        tresorerie: TresorerieDepense.caisse,
        libelle: 'Gaz',
        lignes: const [
          SaisieLigneDepense(
            libelle: 'Bouteille',
            compteCharge: '6052',
            nature: NatureDepense.electriciteEau,
            montant: 7000,
          ),
        ],
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Structure'),
      );
      expect(neuve.numeroPiece, 'CAI-2026-00001');
      await db.close();
    });

    test('un fichier déjà à la forme v17 mais marqué v16 ne plante pas et ne '
        'perd rien', () async {
      // L'état d'un poste qui a reçu un fichier de test, ou qui a sauté une
      // livraison puis restauré une sauvegarde : la table existe déjà.
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await db.customStatement(
        'INSERT INTO sessions_caisse_local (id, point_vente, '
        'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
        "VALUES ('deja', 'bar', ?, 1787000000, 500000)",
        [auteurEssai],
      );
      await db.customStatement('PRAGMA user_version = 16');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      expect(await compterLignes(rouvert, 'sessions_caisse_local'), 1);
      await rouvert.close();
    });
  });

  group('v10 -> v17 — le poste qui a sauté sept livraisons', () {
    test('la chaîne s’exécute sur un fichier v10 portant des dépenses, et la '
        'caisse s’ouvre', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 10);
      await semerAvant(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await compterLignes(apres, 'depenses_local'), 2);
      expect(await compterLignes(apres, 'lignes_depense_local'), 2);
      expect(await tableExiste(apres, 'sessions_caisse_local'), isTrue);
      expect(await compterLignes(apres, 'sessions_caisse_local'), 0);
      // Le moteur de la v15 est là aussi, VIDE.
      expect(await compterLignes(apres, 'ecritures_local'), 0);

      final s = await daoCaisseSur(apres).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '10000',
        auteurId: auteurEssai,
        peutEcrire: true,
      );
      expect(s.estOuverte, isTrue);
      await apres.close();
    });
  });

  group('v2 -> v17 — la chaîne ENTIÈRE', () {
    test('un fichier v2 (la première livraison du poste) arrive à la v17 avec '
        'une table de caisse utilisable', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 2);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      // Le fichier arrive à la version COURANTE (18 depuis le lot 5), qui contient
      // la v17 : la table de caisse y est, utilisable.
      expect(apres.schemaVersion, greaterThanOrEqualTo(17));
      expect(await tableExiste(apres, 'sessions_caisse_local'), isTrue);
      // `utilisateurs_local` n'existe qu'à partir de la v5 : l'auteur se sème
      // APRÈS la chaîne, sur le fichier arrivé à la v17.
      await semerAuteur(apres);
      final s = await daoCaisseSur(apres).ouvrir(
        point: PointDeVenteCaisse.bar,
        fondSaisi: '1000',
        auteurId: auteurEssai,
        peutEcrire: true,
      );
      expect(s.estOuverte, isTrue);
      await apres.close();
    });
  });
}
