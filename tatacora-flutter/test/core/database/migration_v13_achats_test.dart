import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import 'retour_arriere_schema.dart';

/// Migration v12 -> v13 : CINQ tables d'achats, la source locale de M7 —
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2).
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des lignes AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la
/// réouverture qui emprunte `onUpgrade`.
///
/// Les cinq tables sont NEUVES : la migration ne doit rien toucher d'existant
/// (la donnée de stock, le client, l'utilisateur, le paramètre de tolérance
/// saisis avant la mise à jour sont la seule copie qui existe) ni rien semer.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const tablesAchats = [
    'fournisseurs_local',
    'commandes_achat_local',
    'lignes_commande_achat_local',
    'bons_reception_local',
    'lignes_bon_reception_local',
  ];

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v13_');
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

  Future<bool> tableExiste(AppDatabase db, String table) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(table)],
        )
        .get();
    return r.isNotEmpty;
  }

  /// Ce que le poste portait AVANT : un utilisateur, un client, un point, un
  /// article, une entrée de stock VALORISÉE (12,50 sacs à 1 000 F), et la
  /// tolérance de réception saisie en Paramètres.
  Future<void> semerAvant(AppDatabase db) async {
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
        .into(db.parametresSystemeLocal)
        .insert(
          ParametresSystemeLocalCompanion.insert(
            cle: 'tolerance_reception_pct',
            valeur: '5',
            modifieLe: DateTime(2026, 10, 2),
          ),
        );

    final stocks = StocksDao(db);
    await stocks.creerPoint(libelle: 'Magasin', id: 'p-mag');
    await stocks.creerArticle(
      id: 'a-riz',
      libelle: 'Riz local',
      categorie: 'Denrées',
      uniteMesure: 'sac',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-mag',
      auteurId: 'u-1',
    );
    await stocks.ajouterMouvement(
      articleId: 'a-riz',
      pointId: 'p-mag',
      type: TypeMouvement.entree,
      centiemes: 1250,
      motif: 'Reprise',
      auteurId: 'u-1',
      coutDixMilliemes: 10000000,
    );
  }

  group('v12 -> v13 — la mise à jour d’un poste qui travaillait déjà', () {
    test('la fixture ramène bien le fichier à la forme v12 : CINQ tables en '
        'moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 12);

      expect(await version(db), 12);
      for (final t in tablesAchats) {
        expect(await tableExiste(db, t), isFalse, reason: '$t devrait manquer');
      }
      // Les tables de stock, elles, sont intactes (leur forme v12).
      expect(await tableExiste(db, 'articles_local'), isTrue);
      await db.close();
    });

    test('à la réouverture : cinq tables créées, VIDES, données antérieures '
        'intactes, version 13', () async {
      // Semée par les DAO d'aujourd'hui sur une forme ANCIENNE, qui n'a pas
      // la file d'envoi (v26) : les écrivains n'y enfilent donc rien.
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 12);
      await semerAvant(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      // La version COURANTE : la v14 s'applique à la suite de la v13 (c'est le
      // cas du poste qui rouvre un fichier v12), et ce cas ne porte que sur
      // les cinq tables de la v13.
      expect(await version(apres), apres.schemaVersion);

      for (final t in tablesAchats) {
        expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
        // Rien n'est semé ni déduit : un fournisseur « d'usine » serait
        // plausible, donc invisible.
        expect(await compte(apres, t), 0, reason: '$t devrait être vide');
      }

      // La donnée antérieure est la seule copie qui existe : elle survit.
      expect(await compte(apres, 'utilisateurs_local'), 1);
      expect(await compte(apres, 'clients_local'), 1);
      expect(await compte(apres, 'parametres_systeme_local'), 1);
      expect(await compte(apres, 'articles_local'), 1);
      expect(await compte(apres, 'mouvements_stock_local'), 1);

      final stocks = StocksDao(apres);
      final riz = (await stocks.etat()).lignes.single;
      expect(riz.stock, '12.50');
      // Le coût de l'entrée héritée est celui qui a été posé : 1 000 F.
      expect(riz.coutMoyenPondere, '1000.0000');
      await apres.close();
    });

    test('les colonnes des cinq tables sont figées, table par table', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 12);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await colonnes(apres, 'fournisseurs_local'), [
        'id',
        'raison_sociale',
        'contact',
        'categorie',
        'conditions_paiement',
        'evaluation',
        'cree_le',
        'cree_par',
        'modifie_le',
        'modifie_par',
        // Ajoutée par la v21 (archivage d'un fournisseur) : le fichier est rouvert
        // au schéma COURANT, et une colonne ajoutée se range en dernier.
        'actif',
      ]);
      expect(await colonnes(apres, 'commandes_achat_local'), [
        'id',
        'fournisseur_id',
        'date_commande',
        'statut',
        'cree_le',
        'utilisateur_id',
      ]);
      expect(await colonnes(apres, 'lignes_commande_achat_local'), [
        'id',
        'commande_id',
        'article_id',
        'article_libelle',
        'unite_mesure',
        'quantite_centiemes',
        'prix_unitaire_centimes',
        'rang',
      ]);
      expect(await colonnes(apres, 'bons_reception_local'), [
        'id',
        'commande_id',
        'date_reception',
        'conformite',
        'point_stockage_id',
        'cree_le',
        'utilisateur_id',
      ]);
      expect(await colonnes(apres, 'lignes_bon_reception_local'), [
        'id',
        'bon_id',
        'article_id',
        'quantite_centiemes',
      ]);

      // Ni le montant d'une commande, ni la quantité déjà reçue n'est une colonne
      // (piège 9 : ils divergeraient de leurs lignes). `actif` n'en est une QUE
      // sur `fournisseurs_local` depuis la v21 (archivage, D63) — où quelqu'un
      // l'écrit enfin : `AchatsDao.archiverFournisseur`.
      for (final t in tablesAchats) {
        final cols = await colonnes(apres, t);
        expect(cols, isNot(contains('montant')));
        expect(cols, isNot(contains('montant_total')));
        expect(cols, isNot(contains('quantite_recue')));
        if (t != 'fournisseurs_local') expect(cols, isNot(contains('actif')));
        // Aucun `statut_sync` : annoncer une attente sans fin serait mentir.
        expect(cols, isNot(contains('statut_sync')));
      }
      await apres.close();
    });

    test('le poste migré est UTILISABLE : un fournisseur, une commande, une '
        'réception — et le stock hérité s’en trouve augmenté', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 12);
      await semerAvant(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      final dao = AchatsDao(apres, stocks: StocksDao(apres));

      final f = await dao.creerFournisseur(
        const SaisieFournisseur(
          id: 'f-1',
          raisonSociale: 'SODIS SARL',
          contact: null,
          categorie: null,
          conditionsPaiement: null,
          evaluationCode: null,
        ),
        auteurId: 'u-1',
      );
      final commande = await dao.creerCommande(
        SaisieCommande(
          fournisseurId: f.id,
          dateCommande: '2026-10-09',
          statut: StatutCommande.envoyee,
          lignes: const [
            LigneSaisieCommande(
              articleId: 'a-riz',
              libelle: 'sans importance',
              uniteMesure: 'sans importance',
              quantite: '10',
              prixUnitaire: '1200',
            ),
          ],
        ),
        auteurId: 'u-1',
      );
      expect(commande.commande.montantTotal, '12000.00');

      // La réception écrit, dans la même opération, l'entrée de stock — NON
      // valorisée, comme au serveur (D132) : 12,50 sacs hérités à 1 000 F + 10
      // sacs reçus -> 22,50 sacs, et le coût moyen reste celui d'avant (il aurait
      // valu (12 500 + 12 000) / 22,5 = 1 088,8888 si la réception valorisait).
      final bon = await dao.enregistrerReception(
        SaisieReception(
          commandeId: commande.commande.id,
          pointStockageId: 'p-mag',
          dateReception: null,
          lignes: const [
            LigneSaisieReception(
              articleId: 'a-riz',
              libelle: 'Riz local',
              uniteMesure: 'sac',
              quantiteCommandee: '10.00',
              quantiteDejaRecue: '0.00',
              quantiteRecue: '10',
            ),
          ],
        ),
        auteurId: 'u-1',
      );
      expect(bon.conformiteCode, 'totale');

      final riz = (await StocksDao(apres).etat()).lignes.single;
      expect(riz.stock, '22.50');
      expect(riz.coutMoyenPondere, '1000.0000');
      await apres.close();
    });
  });

  group('v9 -> v13 — le poste qui a sauté quatre livraisons', () {
    test('la chaîne v10, v11, v12 puis v13 s’exécute sur un fichier v9 portant '
        'des données', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 9);
      expect(await version(avant), 9);
      // Un utilisateur et un client au format v9 (inchangés depuis).
      await avant
          .into(avant.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: 'cli-9',
              nom: 'MAMA',
              telephone: '+229 01 00 00 00 09',
              typeClient: 'particulier',
            ),
          );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      for (final t in tablesAchats) {
        expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
      }
      // Les versions intermédiaires ont eu lieu aussi.
      expect(await tableExiste(apres, 'parametres_systeme_local'), isTrue);
      expect(await colonnes(apres, 'articles_local'), contains('suivi'));
      expect(await compte(apres, 'clients_local'), 1);
      await apres.close();
    });
  });

  group('Une migration doit pouvoir se REJOUER (piège 3)', () {
    test('un fichier déjà à la forme v13 mais marqué v12 ne plante pas, et '
        'ne perd rien', () async {
      // `createAll` à la définition COURANTE, une ligne semée, puis
      // `user_version` ramené à 12 sans retirer aucune table : c'est l'état où
      // un `CREATE TABLE` inconditionnel échouerait sur « already exists ».
      final neuf = AppDatabase.surFichier(fichier);
      await neuf.customStatement('SELECT 1');
      await neuf
          .into(neuf.fournisseursLocal)
          .insert(
            FournisseursLocalCompanion.insert(
              id: 'f-garde',
              raisonSociale: 'Ets Kora',
              creeLe: DateTime(2026, 10, 3),
              creePar: (await _utilisateur(neuf)),
            ),
          );
      await neuf.customStatement('PRAGMA user_version = 12');
      await neuf.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      // La ligne existante n'a pas été recréée : `createTable` ne recrée pas.
      expect(await compte(rouvert, 'fournisseurs_local'), 1);
      await rouvert.close();
    });
  });

  group('Le retour arrière est SYMÉTRIQUE (tables neuves)', () {
    test('ramener à la v12 retire les cinq tables de la v13 et les quatre de '
        'la v14, pas une de plus', () async {
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      final avant = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' "
                  "AND name NOT LIKE 'sqlite_%'",
                )
                .get())
          r.data['name'] as String,
      };
      await ramenerSchemaA(db, 12);
      final apres = {
        for (final r
            in await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'table' "
                  "AND name NOT LIKE 'sqlite_%'",
                )
                .get())
          r.data['name'] as String,
      };

      // La fixture ramène depuis la version COURANTE : la v15 (six tables de la
      // comptabilité) puis la v14 (quatre tables du restaurant) sont défaites
      // avant la v13, et ne font pas partie de ce que la v13 ajoute.
      expect(avant.difference(apres), {
        ...tablesAchats,
        ...tablesAjouteesEnV15,
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
        'menus_local',
        'recettes_local',
        'ingredients_recette_local',
        'plats_local',
      });
      expect(apres.difference(avant), isEmpty);
      await db.close();
    });
  });
}

Future<String> _utilisateur(AppDatabase db) async {
  await db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: 'u-rejeu',
          login: 'rejeu',
          nom: 'Rejeu',
          role: 'magasinier',
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );
  return 'u-rejeu';
}
