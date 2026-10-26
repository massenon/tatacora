import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import 'retour_arriere_schema.dart';

/// Migration v11 -> v12 : sept colonnes AJOUTÉES aux trois tables de stock, la
/// source locale de M6 — éprouvée sur un FICHIER RÉEL portant des données.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais (piège 2).
/// Ces cas partent d'un fichier ramené à l'ancienne version, y sèment des
/// lignes AU FORMAT DE CETTE VERSION (SQL brut : le schéma courant ne sait plus
/// les écrire), le ferment, puis le rouvrent : c'est la réouverture qui
/// emprunte `onUpgrade`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v12_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  /// Les lignes de stock d'un poste en v11 : un point, un article, un
  /// mouvement — telles que la v1 les écrivait (sans les sept colonnes), avec
  /// le défaut PIÈGE de `statut_sync`.
  Future<void> semerStockV11(AppDatabase db) async {
    await db.customStatement(
      "INSERT INTO points_stockage_local (id, libelle) VALUES ('p-bar', 'Bar')",
    );
    await db.customStatement(
      'INSERT INTO articles_local '
      '(id, libelle, categorie, unite_mesure, seuil_alerte) '
      "VALUES ('a-riz', 'Riz local', 'Denrées', 'sac', 5.0)",
    );
    await db.customStatement(
      'INSERT INTO mouvements_stock_local '
      '(id, article_id, point_id, type_mouvement, quantite, motif, '
      'date_mouvement) '
      "VALUES ('m-1', 'a-riz', 'p-bar', 'entree', 12.5, 'Reprise', 1760000000)",
    );
  }

  /// Ce que la v11 portait AUTOUR : un client, un utilisateur, un taux de paie.
  Future<void> semerAutour(AppDatabase db) async {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'magasinier',
            nom: 'Aïcha',
            role: 'magasinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    await db
        .into(db.tauxPaieLocal)
        .insert(
          TauxPaieLocalCompanion.insert(
            cle: 'taux_cnss_salarie',
            valeur: '3.6',
            description: const Value('posé avant la mise à jour'),
          ),
        );
  }

  Future<int> version(AppDatabase db) async {
    final r = await db.customSelect('PRAGMA user_version').getSingle();
    return r.data.values.first as int;
  }

  Future<int> compte(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<List<String>> colonnes(AppDatabase db, String table) async {
    final r = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final c in r) c.data['name'] as String];
  }

  group('v11 -> v12 — la mise à jour d’un poste qui travaillait déjà', () {
    test('la fixture ramène bien les trois tables à leur forme v11', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 11);

      expect(await version(db), 11);
      expect(await colonnes(db, 'points_stockage_local'), ['id', 'libelle']);
      expect(await colonnes(db, 'articles_local'), [
        'id',
        'libelle',
        'categorie',
        'unite_mesure',
        'seuil_alerte',
      ]);
      expect(await colonnes(db, 'mouvements_stock_local'), [
        'id',
        'article_id',
        'point_id',
        'type_mouvement',
        'quantite',
        'motif',
        'date_mouvement',
        'statut_sync',
      ]);
      await db.close();
    });

    test('à la réouverture : sept colonnes ajoutées, AUCUNE table neuve, '
        'version 12', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 11);
      await semerAutour(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);

      expect(await colonnes(apres, 'points_stockage_local'), [
        'id',
        'libelle',
        'type',
      ]);
      expect(await colonnes(apres, 'articles_local'), [
        'id',
        'libelle',
        'categorie',
        'unite_mesure',
        'seuil_alerte',
        'suivi',
        'point_stockage_id',
        // v35 : l'archivage d'un article (ajoutée en dernier).
        'actif',
      ]);
      expect(await colonnes(apres, 'mouvements_stock_local'), [
        'id',
        'article_id',
        'point_id',
        'type_mouvement',
        'quantite',
        'motif',
        'date_mouvement',
        'statut_sync',
        'cout_unitaire_dix_milliemes',
        'utilisateur_id',
        'rupture_forcee',
        'ordre',
      ]);

      // La migration v12 est ADDITIVE : elle n'ajoute aucune table. Le fichier
      // est rouvert au schéma COURANT, donc la v13 (cinq tables d'achats) puis
      // la v14 (quatre tables du restaurant) et la v15 (six tables de la
      // comptabilité) s'y ajoutent : 35 tables à la v12, 40 à la v13, 44 à la
      // v14, 50 à la v15, 51 à la v17 (sessions de caisse), 52 à la v18
      // (encaissement de facture), 53 à la v20 (règlement fournisseur), 54 à
      // la v22 (alertes vues), 55 à la v23 (séjours), 56 à la v24 (rôles), 57
      // à la v25 (boîte d'envoi de l'éditeur), 58 à la v26 (file d'envoi du
      // poste), 60 à la v27 (descente du catalogue). Les 35 premières sont
      // celles que cette migration a laissées.
      expect(apres.allTables.length, 75);
      await apres.close();
    });

    test(
      'les lignes déjà présentes survivent, avec des valeurs HONNÊTES',
      () async {
        final avant = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(avant, 11);
        await semerAutour(avant);
        await semerStockV11(avant);
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);

        // Rien n'est perdu, ni dans le stock ni autour.
        expect(await compte(apres, 'points_stockage_local'), 1);
        expect(await compte(apres, 'articles_local'), 1);
        expect(await compte(apres, 'mouvements_stock_local'), 1);
        expect(await compte(apres, 'clients_local'), 1);
        expect(await compte(apres, 'utilisateurs_local'), 1);
        final taux = await apres.select(apres.tauxPaieLocal).getSingle();
        expect(taux.valeur, '3.6');

        final point = await apres.select(apres.pointsStockageLocal).getSingle();
        expect(point.libelle, 'Bar');
        expect(point.type, isNull, reason: 'aucun type déduit');

        final article = await apres.select(apres.articlesLocal).getSingle();
        expect(article.libelle, 'Riz local');
        expect(article.seuilAlerte, 5.0);
        // Le défaut décrit le comportement en vigueur : tout article existant
        // était suivi en stock. Le rattachement, lui, n'est PAS inventé.
        expect(article.suivi, 'permanent');
        expect(article.pointStockageId, isNull);

        final m = await apres.select(apres.mouvementsStockLocal).getSingle();
        expect(m.quantite, 12.5);
        expect(m.motif, 'Reprise');
        // Aucun coût, aucun auteur, aucune rupture : rien n'est déduit.
        expect(m.coutUnitaireDixMilliemes, isNull);
        expect(m.utilisateurId, isNull);
        expect(m.ruptureForcee, isFalse);
        expect(m.ordre, 0);
        // La valeur héritée du piège n'est pas « corrigée » en douce : c'est
        // l'écriture qui l'évite (voir plus bas), pas une migration de données.
        expect(m.statutSync, 'en_attente_synchronisation');
        await apres.close();
      },
    );

    test(
      'la ligne héritée est LISIBLE : stock, valeur inconnue, auteur absent',
      () async {
        final avant = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(avant, 11);
        await semerStockV11(avant);
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        final dao = StocksDao(apres, maintenant: () => DateTime(2026, 10, 9));

        final etat = await dao.etat();
        final riz = etat.lignes.single;
        expect(riz.stock, '12.50');
        // Aucune entrée valorisée : le coût est INCONNU, pas nul. Le total ne
        // l'invente pas, et le compteur le dit.
        expect(riz.prixAchat, isNull);
        expect(etat.kpis.sansValorisation, 1);

        final journal = await dao.journal(articleId: 'a-riz');
        expect(journal.total, 1);
        expect(journal.mouvements.single.utilisateur, isNull);
        expect(journal.mouvements.single.quantite, '12.50');
        await apres.close();
      },
    );

    test('la table migrée est UTILISABLE : écriture sous une vraie session, '
        'relecture après fermeture, clés étrangères actives', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 11);
      await semerAutour(avant);
      await semerStockV11(avant);
      await avant.close();

      final ouverte = AppDatabase.surFichier(fichier);
      final dao = StocksDao(
        ouverte,
        maintenant: () => DateTime(2026, 10, 9, 8),
      );

      final issue = await dao.ajouterMouvement(
        articleId: 'a-riz',
        pointId: 'p-bar',
        type: TypeMouvement.entree,
        centiemes: 800,
        motif: 'Réception',
        auteurId: 'u-1',
        coutDixMilliemes: 250000000,
      );
      final pose = issue as MouvementPose;
      expect(pose.mouvement.utilisateur, 'Aïcha');

      // Le rang repart APRÈS le plus grand rang existant (la ligne héritée
      // porte 0), et le statut n'est JAMAIS le défaut du schéma.
      final ecrit = await (ouverte.select(
        ouverte.mouvementsStockLocal,
      )..where((m) => m.id.equals(pose.mouvement.id))).getSingle();
      expect(ecrit.ordre, 1);
      expect(ecrit.statutSync, 'local');

      // Un auteur inexistant est refusé : vraie clé étrangère, sur le fichier
      // réel aussi.
      await expectLater(
        ouverte
            .into(ouverte.mouvementsStockLocal)
            .insert(
              MouvementsStockLocalCompanion.insert(
                id: 'm-x',
                articleId: 'a-riz',
                pointId: 'p-bar',
                typeMouvement: 'entree',
                quantite: 1,
                motif: 'x',
                dateMouvement: DateTime(2026, 10, 9),
                utilisateurId: const Value('fantome'),
              ),
            ),
        throwsA(anything),
      );
      // Un rattachement à un point inexistant l'est aussi.
      await expectLater(
        ouverte.customStatement(
          "UPDATE articles_local SET point_stockage_id = 'fantome'",
        ),
        throwsA(anything),
      );
      await ouverte.close();

      final relue = AppDatabase.surFichier(fichier);
      final etat = await StocksDao(relue).etat();
      // 12,50 hérité + 8,00 reçu = 20,50.
      expect(etat.lignes.single.stock, '20.50');
      // Le stock hérité n'a AUCUN coût connu : il pèse pour zéro dans la
      // pondération, exactement comme au serveur (CMP à 0 par défaut) :
      // (1250 × 0 + 800 × 25 000) / 2050 = 9 756,0975 (tronqué).
      expect(etat.lignes.single.coutMoyenPondere, '9756.0975');
      await relue.close();
    });
  });

  group('v9 -> v12 — le poste qui a sauté deux livraisons', () {
    test('la chaîne v10, v11 puis v12 s’exécute sur un fichier v9 portant des '
        'données', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 9);
      expect(await version(avant), 9);
      await semerStockV11(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      // Les trois versions ont eu lieu : file retirée (v10), paramètres (v11),
      // colonnes de stock (v12).
      expect(await colonnes(apres, 'parametres_systeme_local'), isNotEmpty);
      expect(await colonnes(apres, 'taux_paie_local'), isNotEmpty);
      expect(await colonnes(apres, 'articles_local'), contains('suivi'));
      expect(
        await colonnes(apres, 'mouvements_stock_local'),
        contains('rupture_forcee'),
      );
      expect(await compte(apres, 'mouvements_stock_local'), 1);
      await apres.close();
    });
  });

  group('Une migration doit pouvoir se REJOUER (piège 3)', () {
    test(
      'un fichier déjà à la forme v12 mais marqué v11 ne plante pas',
      () async {
        // `createAll` à la définition COURANTE, puis `user_version` ramené à 11
        // sans retirer aucune colonne : c'est l'état exact où un `addColumn`
        // inconditionnel échoue sur « duplicate column name ».
        final neuf = AppDatabase.surFichier(fichier);
        await neuf.customStatement('SELECT 1');
        await neuf.customStatement('PRAGMA user_version = 11');
        await neuf.close();

        final rouvert = AppDatabase.surFichier(fichier);
        expect(await version(rouvert), rouvert.schemaVersion);
        expect(await colonnes(rouvert, 'articles_local'), contains('suivi'));
        await rouvert.close();
      },
    );
  });
}
