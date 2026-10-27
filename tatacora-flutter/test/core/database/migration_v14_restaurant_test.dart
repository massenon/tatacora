import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/carte_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import 'retour_arriere_schema.dart';

/// Migration v13 -> v14 : QUATRE tables du restaurant, la source locale de M4 —
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2).
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des lignes AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Les quatre tables sont NEUVES : la migration ne doit rien toucher d'existant
/// (le stock, le client, l'utilisateur, la tolérance saisis avant la mise à
/// jour sont la seule copie qui existe) ni rien semer — un plat « d'usine » se
/// vendrait au comptoir à un prix que personne n'a décidé.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const tablesRestaurant = [
    'menus_local',
    'recettes_local',
    'ingredients_recette_local',
    'plats_local',
  ];

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v14_');
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

  Future<Set<String>> toutesLesTables(AppDatabase db) async => {
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
      r.data['name'] as String,
  };

  /// Ce que le poste portait AVANT : un utilisateur, un client, un point de
  /// cuisine, un article, une entrée de stock VALORISÉE (10 kg de poulet à
  /// 2 500 F), la tolérance saisie en Paramètres.
  Future<void> semerAvant(AppDatabase db) async {
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'chef',
            nom: 'Aïcha',
            role: 'cuisinier',
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
    await stocks.creerPoint(
      libelle: 'Cuisine',
      type: TypePoint.cuisine,
      id: 'p-cui',
    );
    await stocks.creerArticle(
      id: 'a-poulet',
      libelle: 'Poulet',
      categorie: 'Viandes',
      uniteMesure: 'kg',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-cui',
      auteurId: 'u-1',
    );
    await stocks.ajouterMouvement(
      articleId: 'a-poulet',
      pointId: 'p-cui',
      type: TypeMouvement.entree,
      centiemes: 1000,
      motif: 'Reprise',
      auteurId: 'u-1',
      coutDixMilliemes: 25000000,
    );
  }

  group('v13 -> v14 — la mise à jour d’un poste qui travaillait déjà', () {
    test('la fixture ramène bien le fichier à la forme v13 : QUATRE tables en '
        'moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 13);

      expect(await version(db), 13);
      for (final t in tablesRestaurant) {
        expect(await tableExiste(db, t), isFalse, reason: '$t devrait manquer');
      }
      // Les tables d'achats de la v13, elles, sont intactes.
      expect(await tableExiste(db, 'fournisseurs_local'), isTrue);
      await db.close();
    });

    test('à la réouverture : quatre tables créées, VIDES, données antérieures '
        'intactes, version 14', () async {
      // Semée par les DAO d'aujourd'hui sur une forme ANCIENNE, qui n'a pas
      // la file d'envoi (v26) : les écrivains n'y enfilent donc rien.
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 13);
      await semerAvant(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      // Le fichier est rouvert au schéma COURANT : la v15 (comptabilité) suit
      // la v14 (cette migration). La version 14 est un point de la chaîne, pas
      // son terme.
      expect(await version(apres), apres.schemaVersion);
      // Le terme de la chaîne n'est pas figé ici : chaque version suivante
      // (v15 comptabilité, v16 pièce des dépenses) le déplace.
      expect(apres.schemaVersion, greaterThanOrEqualTo(15));

      for (final t in tablesRestaurant) {
        expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
        // Rien n'est semé ni déduit : un plat « d'usine » se vendrait au
        // comptoir à un prix que personne n'a décidé.
        expect(await compte(apres, t), 0, reason: '$t devrait être vide');
      }

      // La donnée antérieure est la seule copie qui existe : elle survit.
      expect(await compte(apres, 'utilisateurs_local'), 1);
      expect(await compte(apres, 'clients_local'), 1);
      expect(await compte(apres, 'parametres_systeme_local'), 1);
      expect(await compte(apres, 'points_stockage_local'), 1);
      expect(await compte(apres, 'articles_local'), 1);
      expect(await compte(apres, 'mouvements_stock_local'), 1);

      final poulet = (await StocksDao(apres).etat()).lignes.single;
      expect(poulet.stock, '10.00');
      expect(poulet.coutMoyenPondere, '2500.0000');
      await apres.close();
    });

    test('les colonnes des quatre tables sont figées, table par table', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 13);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await colonnes(apres, 'menus_local'), [
        'id',
        'libelle',
        'type',
        'date_debut',
        'date_fin',
        'cree_le',
        'cree_par',
        'modifie_le',
        'modifie_par',
      ]);
      expect(await colonnes(apres, 'recettes_local'), [
        'id',
        'libelle',
        'cree_le',
        'cree_par',
        'modifie_le',
        'modifie_par',
        // v35 : la composition provisoire (ajoutée en dernier).
        'composition_provisoire',
      ]);
      expect(await colonnes(apres, 'ingredients_recette_local'), [
        'recette_id',
        'article_id',
        'quantite_milliemes',
      ]);
      expect(await colonnes(apres, 'plats_local'), [
        'id',
        'menu_id',
        'recette_id',
        'libelle',
        'prix_vente',
        'prix_provisoire',
        'prix_corrige_main',
        'cree_le',
        'cree_par',
        'modifie_le',
        'modifie_par',
        // v36 : le lien direct au stock (ajouté en dernier).
        'article_id',
        'unites_vendables',
        // v41 : la catégorie du plat (dix valeurs de la carte).
        'categorie',
      ]);

      // Ni un coût, ni une marge, ni des portions, ni un taux n'est une colonne
      // (piège 9 : personne ne les écrirait, ou ils divergeraient de leurs
      // sources) ; ni une disponibilité du jour (`disponible`, portée par
      // `indisponibilites_carte_local`) ; aucun `statut_sync`.
      for (final t in tablesRestaurant) {
        final cols = await colonnes(apres, t);
        for (final interdit in [
          'cout_matiere',
          'cout_matiere_calcule',
          'marge',
          'portions',
          'portions_vendables',
          'stock',
          'taux',
          'article_id_direct',
          'unites_vendables_par_unite_stock',
          'disponible',
          // `composition_provisoire` n'est plus interdite : la v35 (21/10/2026)
          // l'ajoute à `recettes_local`, la PWA l'écrivant.
          // `categorie` n'est plus interdite sur `plats_local` : la v41 (27/10/2026)
          // l'ajoute (les dix catégories de la carte, saisies comme au web).
          'statut_sync',
        ]) {
          expect(cols, isNot(contains(interdit)), reason: '$t.$interdit');
        }
      }
      await apres.close();
    });

    test('le poste migré est UTILISABLE : un menu, une fiche, un plat — et la '
        'carte lit le stock HÉRITÉ', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 13);
      await semerAvant(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      final stocks = StocksDao(apres);
      final api = RestaurantApi(
        dao: RestaurantDao(apres, stocks: stocks),
        peutLire: () => true,
        peutEcrire: () => true,
        auteurId: () => 'u-1',
      );

      final menu =
          ((await api.enregistrerMenu(
                    const SaisieMenu(libelle: 'Carte', type: 'local'),
                  ))
                  as RestaurantRecu<MenuRestaurant>)
              .donnees;
      final fiche =
          ((await api.enregistrerRecette(
                    const SaisieFiche(
                      libelle: 'Poulet DG',
                      lignes: [
                        LigneSaisieComposition(
                          articleId: 'a-poulet',
                          quantite: '0,3',
                        ),
                      ],
                    ),
                  ))
                  as RestaurantRecu<Recette>)
              .donnees;
      await api.enregistrerPlat(
        SaisiePlat(
          libelle: 'Poulet DG',
          menuId: menu.id,
          recetteId: fiche.id,
          prixVente: '4500',
        ),
        modification: false,
      );

      // 10 kg hérités à 2 500 F / 0,3 kg = 33 portions ; coût 750 F.
      final ligne = ((await api.carte()) as RestaurantRecu<CarteRestaurant>)
          .donnees
          .lignes
          .single;
      expect(ligne.portionsVendables, 33);
      expect(ligne.coutMatiere, '750.00');
      expect(ligne.marge, '3750.00');
      await apres.close();
    });
  });

  group('v9 -> v14 — le poste qui a sauté cinq livraisons', () {
    test('la chaîne v10 à v14 s’exécute sur un fichier v9 portant des '
        'données', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 9);
      expect(await version(avant), 9);
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
      for (final t in tablesRestaurant) {
        expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
        expect(await compte(apres, t), 0, reason: t);
      }
      // Les versions intermédiaires ont eu lieu aussi.
      expect(await tableExiste(apres, 'fournisseurs_local'), isTrue);
      expect(await tableExiste(apres, 'parametres_systeme_local'), isTrue);
      expect(await colonnes(apres, 'articles_local'), contains('suivi'));
      expect(await compte(apres, 'clients_local'), 1);
      await apres.close();
    });
  });

  group('Une migration doit pouvoir se REJOUER (piège 3)', () {
    test('un fichier déjà à la forme v14 mais marqué v13 ne plante pas, et ne '
        'perd rien', () async {
      // `createAll` à la définition COURANTE, une ligne semée, puis
      // `user_version` ramené à 13 sans retirer aucune table : c'est l'état où
      // un `CREATE TABLE` inconditionnel échouerait sur « already exists ».
      final neuf = AppDatabase.surFichier(fichier);
      await neuf.customStatement('SELECT 1');
      await neuf
          .into(neuf.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-rejeu',
              login: 'rejeu',
              nom: 'Rejeu',
              role: 'cuisinier',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
      await neuf
          .into(neuf.menusLocal)
          .insert(
            MenusLocalCompanion.insert(
              id: 'm-garde',
              libelle: 'Carte gardée',
              type: 'local',
              creeLe: DateTime(2026, 10, 3),
              creePar: 'u-rejeu',
            ),
          );
      await neuf.customStatement('PRAGMA user_version = 13');
      await neuf.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      // La ligne existante n'a pas été recréée : `createTable` ne recrée pas.
      expect(await compte(rouvert, 'menus_local'), 1);
      await rouvert.close();
    });
  });

  group('Le retour arrière est SYMÉTRIQUE (tables neuves)', () {
    test('ramener à la v13 retire exactement les quatre tables, pas une de '
        'plus', () async {
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      final avant = await toutesLesTables(db);
      await ramenerSchemaA(db, 13);
      final apres = await toutesLesTables(db);

      // La fixture ramène depuis la version COURANTE : la v15 (six tables de la
      // comptabilité) est défaite avant la v14, et ne fait pas partie de ce
      // que la v14 ajoute.
      expect(avant.difference(apres), {
        ...tablesRestaurant,
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
        ...tablesAjouteesEnV34,
        ...tablesAjouteesEnV35,
        ...tablesAjouteesEnV37,
        ...tablesAjouteesEnV38,
        ...tablesAjouteesEnV39,
        ...tablesAjouteesEnV40,
      });
      expect(apres.difference(avant), isEmpty);
      await db.close();
    });
  });
}
