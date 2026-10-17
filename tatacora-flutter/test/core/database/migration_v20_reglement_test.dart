import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/common.dart' show SqliteException;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_reglement.dart';

import '../../features/achats/support/outils_reglement.dart';
import '../../features/comptabilite/support/outils_comptabilite.dart';
import 'retour_arriere_schema.dart';

/// Migration v19 -> v20 : UNE table neuve (`reglements_fournisseur_local`),
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2), y compris en
/// sautant des versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des données AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Rien n'est recréé : une commande passée, ses lignes et un fournisseur d'avant
/// la mise à jour sont la seule copie qui existe. Et la migration NE FABRIQUE
/// RIEN : ni règlement (elle ne sait pas quelle commande a été payée hier), ni
/// pièce comptable — deviner ferait lire un décaissement que personne n'a
/// constaté.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v20_');
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

  Future<int> compter(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  /// Ce que le poste portait AVANT : un auteur, un fournisseur, une commande de
  /// 4 000 F (un article, 4 × 1 000) — au format v19.
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    await db.customStatement(
      'INSERT INTO fournisseurs_local (id, raison_sociale, cree_le, cree_par) '
      "VALUES ('f-v19', 'Grand Marche SARL', 1787000000, ?)",
      [auteurEssai],
    );
    await db.customStatement(
      'INSERT INTO articles_local (id, libelle, categorie, unite_mesure, '
      "seuil_alerte) VALUES ('a-v19', 'Sucre', 'Denrées', 'kg', 4)",
    );
    await db.customStatement(
      'INSERT INTO commandes_achat_local (id, fournisseur_id, date_commande, '
      "statut, cree_le, utilisateur_id) VALUES ('c-v19', 'f-v19', '2026-10-01', "
      "'envoyee', 1787000100, ?)",
      [auteurEssai],
    );
    await db.customStatement(
      'INSERT INTO lignes_commande_achat_local (id, commande_id, article_id, '
      'article_libelle, unite_mesure, quantite_centiemes, '
      "prix_unitaire_centimes, rang) VALUES ('l-v19', 'c-v19', 'a-v19', "
      "'Sucre', 'kg', 400, 100000, 0)",
    );
  }

  group('v19 -> v20 — la mise à jour d’un poste qui avait des commandes', () {
    test('la fixture ramène bien le fichier à la forme v19 : UNE table en '
        'moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 19);

      expect(await version(db), 19);
      for (final t in tablesAjouteesEnV20) {
        expect(await tableExiste(db, t), isFalse, reason: '$t devrait manquer');
      }
      // Les tables d'achats, elles, sont intactes.
      expect(await tableExiste(db, 'commandes_achat_local'), isTrue);
      await db.close();
    });

    test('à la réouverture : la table naît VIDE avec ses colonnes exactes, les '
        'données antérieures sont INTACTES, rien n’est fabriqué', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 19);
      await semerAvant(avant);
      final tablesAvant = await tables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(20));

      final tablesApres = await tables(apres);
      expect(tablesApres.difference(tablesAvant), {
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

      expect(await colonnes(apres, 'reglements_fournisseur_local'), [
        'id',
        'commande_id',
        'montant_centimes',
        'tresorerie',
        'date_reglement',
        'statut',
        'motif_annulation',
        'annule_par_id',
        'date_annulation',
        'utilisateur_creation_id',
      ]);
      expect(await compter(apres, 'reglements_fournisseur_local'), 0);
      // Aucune pièce comptable fabriquée non plus.
      expect(await compter(apres, 'ecritures_local'), 0);

      // Les données d'avant : intactes.
      expect(await compter(apres, 'fournisseurs_local'), 1);
      expect(await compter(apres, 'commandes_achat_local'), 1);
      expect(await compter(apres, 'lignes_commande_achat_local'), 1);
      expect(await compter(apres, 'utilisateurs_local'), 1);
      await apres.close();
    });

    test('le poste migré est UTILISABLE : la commande d’AVANT affiche son '
        'montant en reste dû, se règle, et sa pièce est passée', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 19);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      await baseInstalleeSur(db, jourReglement);

      // Aucun règlement n'est connu : le reste dû est le montant entier. C'est
      // VRAI du poste (rien n'y a été enregistré), pas de la réalité.
      final api = apiAchatsSur(db);
      final avantReglement = recu(await api.commande('c-v19')).commande;
      expect(avantReglement.montantTotal, '4000.00');
      expect(avantReglement.montantRegle, '0.00');
      expect(avantReglement.resteDu, '4000.00');

      final reglement = recu(
        await api.reglerCommande(
          commandeId: 'c-v19',
          montant: '1500',
          tresorerie: 'caisse',
        ),
      );
      expect(reglement.montantCentimes, 150000);
      expect(await compter(db, 'reglements_fournisseur_local'), 1);
      // Dr 4011 / Cr 5711 : deux lignes, dans la même transaction.
      expect(await compter(db, 'ecritures_local'), 2);

      final apresReglement = recu(await api.commande('c-v19')).commande;
      expect(apresReglement.montantRegle, '1500.00');
      expect(apresReglement.resteDu, '2500.00');
      await db.close();
    });

    test('un fichier déjà à la forme v20 mais marqué v19 ne plante pas et ne '
        'perd rien (createTable ne recrée pas)', () async {
      // L'état d'un poste qui a reçu un fichier de test, ou qui a sauté une
      // livraison puis restauré une sauvegarde : la table existe déjà (piège 3).
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await semerAvant2(db);
      await db.customStatement(
        'INSERT INTO reglements_fournisseur_local (id, commande_id, '
        'montant_centimes, tresorerie, date_reglement, utilisateur_creation_id) '
        "VALUES ('r-existant', 'c-x', 50000, 'caisse', '2026-10-02', ?)",
        [auteurEssai],
      );
      await db.customStatement('PRAGMA user_version = 19');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      final r = await rouvert
          .customSelect(
            'SELECT montant_centimes FROM reglements_fournisseur_local '
            "WHERE id = 'r-existant'",
          )
          .getSingle();
      expect(r.data['montant_centimes'], 50000);
      await rouvert.close();
    });

    test(
      'les contraintes de la table neuve tiennent sur le fichier migré',
      () async {
        final avant = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(avant, 19);
        await semerAvant(avant);
        await avant.close();

        final db = AppDatabase.surFichier(fichier);
        Future<void> inserer({
          String id = 'r',
          String commande = 'c-v19',
          int montant = 100,
          String tresorerie = 'caisse',
          String statut = 'actif',
          String? motif,
          int? dateAnnulation,
          String auteur = auteurEssai,
        }) => db.customStatement(
          'INSERT INTO reglements_fournisseur_local (id, commande_id, '
          'montant_centimes, tresorerie, date_reglement, statut, '
          'motif_annulation, date_annulation, utilisateur_creation_id) '
          "VALUES (?, ?, ?, ?, '2026-10-13', ?, ?, ?, ?)",
          [
            id,
            commande,
            montant,
            tresorerie,
            statut,
            motif,
            dateAnnulation,
            auteur,
          ],
        );

        await inserer(id: 'r-valide'); // la ligne valide passe
        await expectLater(
          inserer(id: 'r1', tresorerie: 'cheque'),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer(id: 'r2', montant: 0),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer(id: 'r3', statut: 'remboursé'),
          throwsA(isA<SqliteException>()),
        );
        // « annulé » sans motif ni date, et le contraire : refusés tous deux.
        await expectLater(
          inserer(id: 'r4', statut: 'annule'),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer(id: 'r5', motif: 'Doublon', dateAnnulation: 1787000500),
          throwsA(isA<SqliteException>()),
        );
        // « annulé » avec son motif ET sa date : accepté.
        await inserer(
          id: 'r6',
          statut: 'annule',
          motif: 'Doublon',
          dateAnnulation: 1787000500,
        );
        // Les deux clés étrangères : une commande ou un auteur inconnus.
        await expectLater(
          inserer(id: 'r7', commande: 'fantome'),
          throwsA(isA<SqliteException>()),
        );
        await expectLater(
          inserer(id: 'r8', auteur: 'fantome'),
          throwsA(isA<SqliteException>()),
        );
        await db.close();
      },
    );
  });

  group('v10 -> v20 — le poste qui a sauté dix livraisons', () {
    test('la chaîne s’exécute sur un fichier v10 portant des dépenses, et le '
        'règlement est possible après', () async {
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
      expect(await compter(apres, 'depenses_local'), 1);
      expect(await tableExiste(apres, 'reglements_fournisseur_local'), isTrue);
      expect(await compter(apres, 'reglements_fournisseur_local'), 0);

      // Le poste sert : référentiel, fournisseur, commande, règlement.
      await baseInstalleeSur(apres, jourReglement);
      final commande = await semerCommande(apres);
      final r = await reglementsDaoSur(apres).regler(
        commandeId: commande,
        montantSaisi: '4000',
        tresorerieSaisie: 'banque',
        auteurId: auteurEssai,
      );
      expect(r.montantCentimes, 400000);
      await apres.close();
    });
  });

  group('v2 -> v20 — la chaîne ENTIÈRE', () {
    test('un fichier v2 (la première livraison du poste) arrive à la v20 avec '
        'la table, une seule fois, et un règlement s’y écrit', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 2);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(20));
      expect(await tableExiste(apres, 'reglements_fournisseur_local'), isTrue);

      await semerAuteur(apres);
      await baseInstalleeSur(apres, jourReglement);
      final commande = await semerCommande(apres);
      await reglementsDaoSur(apres).regler(
        commandeId: commande,
        montantSaisi: '500',
        tresorerieSaisie: 'momo',
        auteurId: auteurEssai,
      );
      expect(await compter(apres, 'reglements_fournisseur_local'), 1);

      // Le refus du sur-règlement tient aussi sur la chaîne entière.
      await expectLater(
        reglementsDaoSur(apres).regler(
          commandeId: commande,
          montantSaisi: '9999',
          tresorerieSaisie: 'momo',
          auteurId: auteurEssai,
        ),
        throwsA(
          predicate(
            (e) =>
                e.toString() == MessagesReglement.superieurAuReste('3500.00'),
          ),
        ),
      );
      expect(await compter(apres, 'reglements_fournisseur_local'), 1);
      await apres.close();
    });
  });
}

/// Une commande minimale pour le test du fichier « déjà v20 » : l'identifiant
/// `c-x` que la ligne de règlement référence.
Future<void> semerAvant2(AppDatabase db) async {
  await db.customStatement(
    'INSERT INTO fournisseurs_local (id, raison_sociale, cree_le, cree_par) '
    "VALUES ('f-x', 'X', 1787000000, ?)",
    [auteurEssai],
  );
  await db.customStatement(
    'INSERT INTO commandes_achat_local (id, fournisseur_id, date_commande, '
    "statut, cree_le, utilisateur_id) VALUES ('c-x', 'f-x', '2026-10-01', "
    "'envoyee', 1787000100, ?)",
    [auteurEssai],
  );
}
