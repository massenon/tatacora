import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';
import '../../features/facturation/support/outils_encaissement.dart';
import 'retour_arriere_schema.dart';

/// Migration v17 -> v18 : UNE table neuve (`paiements_facture_local`) et UNE
/// colonne ajoutée (`paniers_local.session_encaissement_id`), éprouvées sur un
/// FICHIER RÉEL portant des données (piège 2), y compris en sautant des versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des données AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Rien n'est recréé : une facture émise, un panier clôturé et une session
/// ouverte avant la mise à jour sont la seule copie qui existe. Et la migration
/// NE FABRIQUE RIEN : ni paiement (elle ne sait pas quelle facture a été réglée
/// hier), ni rattachement d'un panier à une session (elle ne sait pas où l'argent
/// est entré) — deviner ferait lire un fait que personne n'a constaté.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v18_');
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

  /// Ce que le poste portait AVANT : un auteur, une session ouverte, un panier
  /// au comptant clôturé en espèces, et une facture émise — au format v17.
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    await db.customStatement(
      'INSERT INTO sessions_caisse_local (id, point_vente, '
      'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
      "VALUES ('sess-v17', 'bar', ?, 1787000000, 1000000)",
      [auteurEssai],
    );
    await db.customStatement(
      'INSERT INTO paniers_local (id, type_vente, point_vente, statut, '
      "mode_paiement, montant_cloture, cloture_le) VALUES ('p-v17', "
      "'comptant', 'Réception', 'cloture', 'especes', 4000, 1787000100)",
    );
    await db.customStatement(
      'INSERT INTO pieces_facturation_local (id, numero, origine, '
      'date_emission, client_nom, statut) VALUES '
      "('f-v17', 'F-2026-00001', 'facture_directe', 1787000200, 'KORA', "
      "'emise')",
    );
    await db.customStatement(
      'INSERT INTO lignes_piece_facturation_local (id, piece_id, '
      'module_source, libelle, prix_unitaire, quantite, ordre) VALUES '
      "('l-v17', 'f-v17', 'M5', 'Prestation', 50000, 1, 0)",
    );
  }

  group('v17 -> v18 — la mise à jour d’un poste qui avait des ventes', () {
    test('la fixture ramène bien le fichier à la forme v17 : UNE table et UNE '
        'colonne en moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 17);

      expect(await version(db), 17);
      for (final t in tablesAjouteesEnV18) {
        expect(await tableExiste(db, t), isFalse, reason: '$t devrait manquer');
      }
      expect(
        await colonnes(db, 'paniers_local'),
        isNot(contains('session_encaissement_id')),
      );
      // Les tables de la v17, elles, sont intactes.
      expect(await tableExiste(db, 'sessions_caisse_local'), isTrue);
      await db.close();
    });

    test('à la réouverture : la table naît VIDE, la colonne est AJOUTÉE, les '
        'données antérieures sont INTACTES, rien n’est fabriqué', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 17);
      await semerAvant(avant);
      final tablesAvant = await tables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(18));

      final tablesApres = await tables(apres);
      // La v20 (règlement fournisseur) s'ajoute à la réouverture, après la v18.
      expect(tablesApres.difference(tablesAvant), {
        ...tablesAjouteesEnV18,
        ...tablesAjouteesEnV20,
        ...tablesAjouteesEnV22,
        ...tablesAjouteesEnV23,
        ...tablesAjouteesEnV24,
        ...tablesAjouteesEnV25,
        ...tablesAjouteesEnV26,
        ...tablesAjouteesEnV27,
        ...tablesAjouteesEnV28,
      });
      expect(tablesAvant.difference(tablesApres), isEmpty);

      expect(await colonnes(apres, 'paiements_facture_local'), [
        'id',
        'piece_id',
        'session_id',
        'mode_paiement',
        'montant_centimes',
        'date_paiement',
        'statut',
        'motif_annulation',
        'annule_par_id',
        'date_annulation',
        'utilisateur_creation_id',
      ]);
      expect(await compterLignes(apres, 'paiements_facture_local'), 0);
      expect(
        await colonnes(apres, 'paniers_local'),
        contains('session_encaissement_id'),
      );

      // Le panier d'avant est LÀ, et n'est rattaché à AUCUNE session.
      final panier = await apres
          .customSelect(
            'SELECT montant_cloture, session_encaissement_id FROM paniers_local '
            "WHERE id = 'p-v17'",
          )
          .getSingle();
      expect(panier.data['montant_cloture'], 4000);
      expect(panier.data['session_encaissement_id'], isNull);

      // Les autres données d'avant : intactes.
      expect(await compterLignes(apres, 'sessions_caisse_local'), 1);
      expect(await compterLignes(apres, 'pieces_facturation_local'), 1);
      expect(await compterLignes(apres, 'lignes_piece_facturation_local'), 1);
      expect(await compterLignes(apres, 'utilisateurs_local'), 1);
      await apres.close();
    });

    test('le poste migré est UTILISABLE : la facture émise AVANT s’encaisse, '
        'et un panier clôturé après porte sa session', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 17);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      await baseInstalleeSur(db, jourEncaissement);

      // 1. La facture d'avant s'encaisse, pièce comptable comprise.
      final dao = paiementsDaoSur(db);
      final p = await dao.encaisser(
        pieceId: 'f-v17',
        montant: '20000',
        mode: 'especes',
        auteurId: auteurEssai,
      );
      expect(p.sessionId, 'sess-v17');
      expect(
        (await dao.creanceDe(
          (await factureDaoSur(db).parId('f-v17'))!,
        )).resteDuCentimes,
        3000000,
      );
      expect(await compterLignes(db, 'ecritures_local'), 2);

      // 2. Un panier clôturé APRÈS la mise à jour porte la session ouverte.
      final paniers = PanierDao(db);
      await semerBoisson(db);
      final cloture = await vendreAuComptant(db);
      expect(cloture.sessionEncaissementId, 'sess-v17');

      // 3. Celui d'AVANT n'a pas bougé.
      expect((await paniers.parId('p-v17'))!.sessionEncaissementId, isNull);
      await db.close();
    });

    test('un fichier déjà à la forme v18 mais marqué v17 ne plante pas et ne '
        'perd rien (l’ajout de colonne est conditionnel)', () async {
      // L'état d'un poste qui a reçu un fichier de test, ou qui a sauté une
      // livraison puis restauré une sauvegarde : la table et la colonne existent
      // déjà (piège 3 : « duplicate column name »).
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await db.customStatement(
        'INSERT INTO sessions_caisse_local (id, point_vente, '
        'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
        "VALUES ('s', 'bar', ?, 1787000000, 100)",
        [auteurEssai],
      );
      await db.customStatement(
        'INSERT INTO paniers_local (id, type_vente, statut, '
        "session_encaissement_id) VALUES ('p', 'comptant', 'cloture', 's')",
      );
      await db.customStatement('PRAGMA user_version = 17');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      final r = await rouvert
          .customSelect(
            "SELECT session_encaissement_id FROM paniers_local WHERE id = 'p'",
          )
          .getSingle();
      expect(r.data['session_encaissement_id'], 's');
      await rouvert.close();
    });

    test(
      'les contraintes de la table neuve tiennent sur le fichier migré',
      () async {
        final avant = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(avant, 17);
        await semerAvant(avant);
        await avant.close();

        final db = AppDatabase.surFichier(fichier);
        Future<void> inserer(
          String mode,
          String statut,
          int montant,
        ) => db.customStatement(
          'INSERT INTO paiements_facture_local (id, piece_id, session_id, '
          'mode_paiement, montant_centimes, date_paiement, statut, '
          'utilisateur_creation_id) VALUES (?, ?, ?, ?, ?, 1787000300, ?, ?)',
          [
            'x$mode$statut$montant',
            'f-v17',
            'sess-v17',
            mode,
            montant,
            statut,
            auteurEssai,
          ],
        );

        await inserer('especes', 'actif', 100); // la ligne valide passe
        await expectLater(
          inserer('cheque', 'actif', 100),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer('especes', 'actif', 0),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer('especes', 'annule', 100),
          throwsA(isA<SqliteException>()),
        );
        // Une clé étrangère de la colonne ajoutée : une session inconnue est refusée.
        await expectLater(
          db.customStatement(
            "UPDATE paniers_local SET session_encaissement_id = 'fantome' "
            "WHERE id = 'p-v17'",
          ),
          throwsA(isA<SqliteException>()),
        );
        await db.close();
      },
    );
  });

  group('v10 -> v18 — le poste qui a sauté huit livraisons', () {
    test('la chaîne s’exécute sur un fichier v10 portant des dépenses, et '
        'l’encaissement est possible après', () async {
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
      expect(await compterLignes(apres, 'depenses_local'), 1);
      expect(await tableExiste(apres, 'paiements_facture_local'), isTrue);
      expect(await compterLignes(apres, 'paiements_facture_local'), 0);
      expect(
        await colonnes(apres, 'paniers_local'),
        contains('session_encaissement_id'),
      );

      // Le poste sert : référentiel, caisse, facture, encaissement.
      await baseInstalleeSur(apres, jourEncaissement);
      await ouvrirCaissePour(apres);
      final f = await emettreFacture(apres);
      final p = await paiementsDaoSur(apres).encaisser(
        pieceId: f.id,
        montant: '1000',
        mode: 'carte',
        auteurId: caissierEssai,
      );
      expect(p.montantCentimes, 100000);
      await apres.close();
    });
  });

  group('v2 -> v18 — la chaîne ENTIÈRE', () {
    test('un fichier v2 (la première livraison du poste) arrive à la v18 avec '
        'la colonne ET la table, une seule fois chacune', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 2);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(18));
      expect(await tableExiste(apres, 'paiements_facture_local'), isTrue);
      // `paniers_local` est créée par `createTable` à sa définition COURANTE à la
      // v3 : la colonne y est DÉJÀ, et la v18 ne doit pas la rajouter.
      final noms = await colonnes(apres, 'paniers_local');
      expect(noms.where((n) => n == 'session_encaissement_id'), hasLength(1));

      await semerAuteur(apres);
      await baseInstalleeSur(apres, jourEncaissement);
      await ouvrirCaissePour(apres);
      final f = await emettreFacture(apres);
      await paiementsDaoSur(apres).encaisser(
        pieceId: f.id,
        montant: '500',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      expect(await compterLignes(apres, 'paiements_facture_local'), 1);
      await apres.close();
    });
  });
}
