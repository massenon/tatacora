import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/charges_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';

import 'support/faux_transport.dart';

/// La DESCENTE du catalogue (lot F2b) contre un faux serveur : pagination
/// par curseur, application par page, correspondances, protection des
/// modifications locales non poussées, conversions d'unités, dépendances,
/// archives, centres de coût — et la file qui n'en reçoit rien.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  DescenteCatalogueDao etat() => DescenteCatalogueDao(b.db);

  Future<int> compte(String table) async =>
      (await b.db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Future<Map<String, Object?>?> ligne(String table, String id) async =>
      (await b.db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  FauxTransport transportDe(FauxCatalogue cat) => FauxTransport(
    (r) => r.methode == 'GET' ? cat.repondre(r) : reponseLot(r),
  );

  /// Les cinq éléments d'un petit catalogue, dans l'ordre du serveur.
  List<Map<String, Object?>> petitCatalogue() => [
    element('points_stockage', 'ps-1', {
      'libelle': 'Magasin',
      'type': 'magasin',
    }),
    element('articles', 'art-1', {
      'libelle': 'Riz',
      'categorie': 'Céréales',
      'unite_mesure': 'kg',
      'point_stockage_id': 'ps-1',
      'suivi': 'permanent',
      'seuil_alerte': '12.50',
      'seuil_reappro': null,
    }),
    element('articles', 'art-2', {
      'libelle': 'Huile',
      'categorie': 'Épicerie',
      'unite_mesure': 'l',
      'point_stockage_id': null,
      'suivi': 'permanent',
      'seuil_alerte': '0.00',
    }),
    element('categories_hebergement', 'cat-1', {
      'libelle': 'Chambre double',
      'capacite_max': 2,
      'tarif_base': '25000.00',
    }),
    element('unites_hebergement', 'u-1', {
      'categorie_id': 'cat-1',
      'numero': '101',
      'statut': 'libre',
    }),
  ];

  group('pagination par curseur', () {
    test(
      'trois pages de deux : le curseur rendu est renvoyé, tout est '
      'appliqué, le curseur final est conservé pour la fois suivante',
      () async {
        final cat = FauxCatalogue(petitCatalogue());
        final t = transportDe(cat);
        final bilan = await b
            .descente(t, limite: 2)
            .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});

        expect(bilan.etat, EtatDescente.aJour, reason: '$bilan');
        expect(cat.curseursDemandes, [null, 'c2', 'c4']);
        expect((bilan.pages, bilan.recus, bilan.appliques), (3, 5, 5));
        expect(await etat().curseur(), 'c5');
        final requete = t.descentes.first;
        expect(requete.jeton, BancSync.jeton);
        expect(requete.url.queryParameters['poste_id'], BancSync.poste);
        expect(requete.url.path, '/api/v1/referentiels');

        // La fois suivante repart du curseur conservé.
        await b
            .descente(t, limite: 2)
            .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
        expect(cat.curseursDemandes.last, 'c5');
      },
    );

    test('le curseur n’est écrit qu’APRÈS la page appliquée : un arrêt au '
        'milieu de la deuxième page la REJOUE entière, sans doublon', () async {
      final cat = FauxCatalogue(petitCatalogue());
      var pages = 0;
      final appairage = (await b.lecteur.appairage())!;
      final crash = await b
          .descente(
            transportDe(cat),
            limite: 2,
            avantCurseur: () {
              if (++pages == 2) throw const FileSystemException('coupure');
            },
          )
          .descendre(appairage, surRefus: (_) async {});

      expect(crash.etat, EtatDescente.alerte);
      expect(await etat().curseur(), 'c2', reason: 'page 1 seule acquise');
      expect(
        await ligne('articles_local', 'art-2'),
        isNull,
        reason: 'la page 2 est défaite avec son curseur',
      );
      expect(await compte('categories_hebergement_local'), 0);

      final reprise = await b
          .descente(transportDe(cat), limite: 2)
          .descendre(appairage, surRefus: (_) async {});
      expect(reprise.etat, EtatDescente.aJour);
      expect(cat.curseursDemandes.skip(2), ['c2', 'c4']);
      expect(await compte('articles_local'), 2);
      expect(await compte('points_stockage_local'), 1);
      expect(await compte('unites_hebergement_local'), 1);
      expect(await etat().curseur(), 'c5');
    });

    test('422 (curseur illisible au serveur) : le curseur est oublié et la '
        'descente repart du début', () async {
      await b.db.transaction(() => etat().poserCurseur('perime'));
      final cat = FauxCatalogue(petitCatalogue());
      final t = FauxTransport(
        (r) => r.url.queryParameters['depuis'] == 'perime'
            ? const ReponseHttp(statut: 422, corps: {'message': 'Curseur'})
            : cat.repondre(r),
      );
      final bilan = await b
          .descente(t)
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(bilan.etat, EtatDescente.aJour);
      expect(bilan.appliques, 5);
      expect(await etat().curseur(), 'c5');
    });
  });

  group('écrire sans jamais rien renvoyer', () {
    test('une descente complète n’enfile RIEN dans la file d’envoi', () async {
      await b
          .descente(transportDe(FauxCatalogue(petitCatalogue())))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(await compte('articles_local'), 2);
      expect(await b.total(), 0);
    });

    test('l’écrivain « aligner » n’appelle jamais enfiler (balayage du '
        'source)', () {
      for (final f in [
        'lib/features/synchronisation/data/aligneur_catalogue.dart',
        'lib/features/synchronisation/data/descente_catalogue.dart',
        'lib/features/synchronisation/data/descente_catalogue_dao.dart',
      ]) {
        final source = File(f).readAsStringSync();
        expect(source, isNot(contains('.enfiler(')), reason: f);
      }
    });
  });

  group('conversions d’unités : l’inverse exact du lot F1', () {
    test('décimaux du serveur → entiers du poste, sans flottant', () {
      expect(entierDepuisDecimal('12.50', 2), 1250);
      expect(entierDepuisDecimal('0.250', 3), 250);
      expect(entierDepuisDecimal('1500.00', 0), 1500);
      expect(entierDepuisDecimal('1500', 0), 1500);
      expect(entierDepuisDecimal('-0.005', 3), -5);
      expect(entierDepuisDecimal('1500.50', 0), isNull, reason: 'fraction');
      expect(entierDepuisDecimal('0.2505', 3), isNull);
      expect(entierDepuisDecimal('0.2500', 3), 250);
      expect(entierDepuisDecimal('abc', 2), isNull);
      expect(entierDepuisDecimal(null, 2), isNull);
    });

    test('ALLER-RETOUR : la charge F1 d’un élément, descendue, redonne la '
        'même ligne et la même charge', () async {
      for (final (valeur, decimales) in [(1250, 2), (5, 2), (250, 3), (1, 3)]) {
        expect(
          entierDepuisDecimal(decimalExact(valeur, decimales), decimales),
          valeur,
        );
      }

      // Un article créé sur un poste A (vrai DAO), poussé : son document
      // descend sur un poste B tel que le serveur le rend.
      await StocksDao(
        b.db,
      ).creerPoint(libelle: 'Bar', type: TypePoint.bar, id: 'ps-a');
      await StocksDao(b.db).creerArticle(
        id: 'art-a',
        libelle: 'Bière',
        categorie: 'Boissons',
        uniteMesure: 'casier',
        seuilCentiemes: 1250,
        suivi: SuiviArticle.permanent,
        pointStockageId: 'ps-a',
      );
      final pousse =
          jsonDecode(
                (await b.dao.operations(
                  table: TableSynchronisee.articles,
                )).single.payload,
              )
              as Map<String, Object?>;
      expect(pousse['seuil_alerte'], '12.50');

      final poste2 = await BancSync.creer();
      addTearDown(poste2.fermer);
      await poste2.semerAuteur();
      final recette = chargeRecette(
        libelle: 'Riz sauté',
        lignes: [(articleId: 'art-a', milliemes: 250)],
      );
      final boisson = chargeBoisson(
        libelle: 'Bière 65cl',
        articleId: 'art-a',
        categorie: 'locale',
        prixVenteFrancs: 1000,
      );
      final menu = chargeMenu(
        libelle: 'Carte du midi',
        type: 'local',
        dateDebut: null,
        dateFin: null,
      );
      final plat = chargePlat(
        libelle: 'Riz sauté poulet',
        menuId: 'menu-a',
        recetteId: 'rec-a',
        prixVenteFrancs: 3500,
        prixProvisoire: true,
        prixCorrigeMain: false,
      );
      final categorie = chargeCategorieHebergement(
        libelle: 'Suite',
        tarifBaseFrancs: 45000,
        capaciteMax: 3,
      );
      // Le serveur rend ses montants en `decimal(15,2)` : « 1000.00 ».
      String deuxDecimales(Object? v) => '$v.00';
      final cat = FauxCatalogue([
        element(
          'points_stockage',
          'ps-a',
          chargePointStockage(libelle: 'Bar', type: 'bar'),
        ),
        element('articles', 'art-a', {...pousse, 'seuil_reappro': null}),
        element('cartes_boisson', 'b-a', {
          ...boisson,
          'prix_vente': deuxDecimales(boisson['prix_vente']),
        }),
        element('menus', 'menu-a', menu),
        element('recettes', 'rec-a', {
          ...recette,
          'composition_provisoire': false,
        }),
        element('plats', 'plat-a', {
          ...plat,
          'prix_vente': deuxDecimales(plat['prix_vente']),
          'article_id': null,
        }),
        element('categories_hebergement', 'cat-a', {
          ...categorie,
          'tarif_base': deuxDecimales(categorie['tarif_base']),
        }),
      ]);
      final bilan = await poste2
          .descente(transportDe(cat))
          .descendre(
            (await poste2.lecteur.appairage())!,
            surRefus: (_) async {},
          );
      expect((bilan.appliques, bilan.refuses), (7, 0), reason: '$bilan');

      final a = await poste2.db
          .customSelect("SELECT * FROM articles_local WHERE id = 'art-a'")
          .getSingle();
      expect(a.data['seuil_alerte'], 12.5);
      // La charge F1 relue de la ligne descendue est celle d'origine.
      expect(
        chargeArticle(
          libelle: a.data['libelle'] as String,
          categorie: a.data['categorie'] as String,
          uniteMesure: a.data['unite_mesure'] as String,
          seuilCentiemes: ((a.data['seuil_alerte'] as double) * 100).round(),
          suivi: a.data['suivi'] as String,
          pointStockageId: a.data['point_stockage_id'] as String?,
        ),
        pousse,
      );
      final ing = await poste2.db
          .customSelect('SELECT * FROM ingredients_recette_local')
          .getSingle();
      expect(ing.data['quantite_milliemes'], 250);
      expect(
        (await poste2.db
                .customSelect('SELECT prix_vente FROM cartes_boisson_local')
                .getSingle())
            .data['prix_vente'],
        1000.0,
      );
      final p = await poste2.db
          .customSelect('SELECT * FROM plats_local')
          .getSingle();
      expect((p.data['prix_vente'], p.data['prix_provisoire']), (3500, 1));
      expect(
        (await poste2.db
                .customSelect(
                  'SELECT tarif_base FROM categories_hebergement_local',
                )
                .getSingle())
            .data['tarif_base'],
        45000.0,
      );
      expect(await poste2.total(), 0, reason: 'rien ne remonte');
    });

    test('un prix à fraction de franc est REFUSÉ (compté, motif), jamais '
        'arrondi ; les autres éléments de la page passent', () async {
      final bilan = await b
          .descente(
            transportDe(
              FauxCatalogue([
                element('cartes_boisson', 'b-1', {
                  'libelle': 'Sodabi',
                  'article_id': null,
                  'categorie': 'locale',
                  'prix_vente': '1500.50',
                }),
                element('cartes_boisson', 'b-2', {
                  'libelle': 'Eau',
                  'article_id': null,
                  'categorie': 'locale',
                  'prix_vente': '500.00',
                }),
              ]),
            ),
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect((bilan.recus, bilan.appliques, bilan.refuses), (2, 1, 1));
      expect(bilan.motifsRefus.single, contains('fraction de franc'));
      expect(await ligne('cartes_boisson_local', 'b-1'), isNull);
      expect((await ligne('cartes_boisson_local', 'b-2'))!['article_id'], '');
    });
  });

  group('l’ordre des clés étrangères et les dépendances différées', () {
    test('un plat reçu AVANT son menu et sa fiche attend, puis passe à la '
        'reprise de fin de descente — aucune contrainte violée', () async {
      final cat = FauxCatalogue([
        element('plats', 'plat-1', {
          'libelle': 'Igname pilée',
          'menu_id': 'm-1',
          'recette_id': 'r-1',
          'prix_vente': '2500.00',
          'prix_provisoire': false,
          'prix_corrige_main': false,
        }),
        element('menus', 'm-1', {'libelle': 'Midi', 'type': 'local'}),
        element('recettes', 'r-1', {'libelle': 'Igname', 'lignes': <Object>[]}),
      ]);
      final bilan = await b
          .descente(transportDe(cat))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect((bilan.appliques, bilan.enAttenteDeDependance), (3, 0));
      expect((await ligne('plats_local', 'plat-1'))!['menu_id'], 'm-1');
      expect(await etat().elementsGardes(), isEmpty);
    });

    test('un plat dont le menu n’arrive pas reste GARDÉ (compté), et passe '
        'à la descente suivante quand le menu descend', () async {
      final plat = element('plats', 'plat-1', {
        'libelle': 'Igname pilée',
        'menu_id': 'm-1',
        'recette_id': 'r-1',
        'prix_vente': '2500.00',
      });
      final cat = FauxCatalogue([
        element('recettes', 'r-1', {'libelle': 'Igname', 'lignes': <Object>[]}),
        plat,
      ]);
      final appairage = (await b.lecteur.appairage())!;
      final premier = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect((premier.appliques, premier.enAttenteDeDependance), (1, 1));
      expect(await ligne('plats_local', 'plat-1'), isNull);
      expect((await etat().elementsGardes()).single.element.id, 'plat-1');

      // Le menu descend à la fois suivante (le plat, lui, ne repasse pas).
      cat.elements.add(
        element('menus', 'm-1', {'libelle': 'Midi', 'type': 'local'}),
      );
      final second = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect((second.recus, second.appliques), (1, 2), reason: '$second');
      expect(second.enAttenteDeDependance, 0);
      expect(await ligne('plats_local', 'plat-1'), isNotNull);
    });

    test('UNE ligne qui lève (contrainte imprévue) n’emporte pas la page : '
        'isolée, comptée refusée', () async {
      await b.db.customStatement(
        'CREATE TRIGGER essai_refus BEFORE INSERT ON points_stockage_local '
        "WHEN NEW.id = 'ps-x' BEGIN SELECT RAISE(ABORT, 'refus'); END",
      );
      final bilan = await b
          .descente(
            transportDe(
              FauxCatalogue([
                element('points_stockage', 'ps-x', {'libelle': 'X'}),
                element('points_stockage', 'ps-y', {'libelle': 'Y'}),
              ]),
            ),
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect((bilan.appliques, bilan.refuses), (1, 1));
      expect(bilan.motifsRefus.single, contains('écriture impossible'));
      expect(await ligne('points_stockage_local', 'ps-y'), isNotNull);
      expect(await etat().curseur(), 'c2');
    });
  });

  group('correspondances : jamais de doublon, jamais de clé réécrite', () {
    test('la correspondance du flux traduit l’élément ET les clés qui le '
        'citent ; la ligne locale garde son identifiant', () async {
      await StocksDao(b.db).creerPoint(libelle: 'Réserve', id: 'ps-poste');
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );
      final cat = FauxCatalogue(
        [
          element('points_stockage', 'ps-serveur', {
            'libelle': 'Réserve centrale',
          }),
          element('articles', 'art-1', {
            'libelle': 'Riz',
            'unite_mesure': 'kg',
            'point_stockage_id': 'ps-serveur',
            'suivi': 'permanent',
            'seuil_alerte': '1.00',
          }),
        ],
        correspondances: [
          {
            'table': 'points_stockage',
            'id_poste': 'ps-poste',
            'id_serveur': 'ps-serveur',
          },
        ],
      );
      // Une seule page : la correspondance (rendue en fin de catalogue)
      // arrive avec les éléments et passe AVANT eux.
      final bilan = await b
          .descente(transportDe(cat))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(bilan.appliques, 2);
      expect(
        await compte('points_stockage_local'),
        1,
        reason: 'pas de doublon',
      );
      expect(
        (await ligne('points_stockage_local', 'ps-poste'))!['libelle'],
        'Réserve centrale',
      );
      expect(
        (await ligne('articles_local', 'art-1'))!['point_stockage_id'],
        'ps-poste',
      );
    });

    test('le `fusionne_avec` de la FILE suffit, même avant que le flux des '
        'correspondances arrive', () async {
      await StocksDao(b.db).creerPoint(libelle: 'Réserve', id: 'ps-poste');
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise', "
        "id_serveur = 'ps-serveur'",
      );
      await b
          .descente(
            transportDe(
              FauxCatalogue([
                element('points_stockage', 'ps-serveur', {
                  'libelle': 'Réserve B',
                }),
              ]),
            ),
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(await compte('points_stockage_local'), 1);
      expect(
        (await ligne('points_stockage_local', 'ps-poste'))!['libelle'],
        'Réserve B',
      );
      final c = (await etat().correspondances()).single;
      expect(
        (c.idServeur, c.idLocal, c.origine),
        ('ps-serveur', 'ps-poste', 'file'),
      );
    });
  });

  group('une modification locale NON POUSSÉE n’est jamais écrasée', () {
    Future<void> articleLocalModifie() async {
      final stocks = StocksDao(b.db);
      await stocks.creerArticle(
        id: 'art-1',
        libelle: 'Riz',
        categorie: '',
        uniteMesure: 'kg',
        seuilCentiemes: 100,
        suivi: SuiviArticle.permanent,
        pointStockageId: null,
      );
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );
      await stocks.modifierArticle(
        id: 'art-1',
        libelle: 'Riz parfumé',
        categorie: '',
        uniteMesure: 'kg',
        seuilCentiemes: 100,
        suivi: SuiviArticle.permanent,
        pointStockageId: null,
      );
    }

    final renomme = element('articles', 'art-1', {
      'libelle': 'Riz long (serveur)',
      'unite_mesure': 'kg',
      'suivi': 'permanent',
      'seuil_alerte': '1.00',
    });

    test('opération en attente : la ligne locale est CONSERVÉE, comptée, et '
        'la version serveur gardée pour la reprise', () async {
      await articleLocalModifie();
      final bilan = await b
          .descente(transportDe(FauxCatalogue([renomme])))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect((bilan.appliques, bilan.conservesLocalement), (0, 1));
      expect(
        (await ligne('articles_local', 'art-1'))!['libelle'],
        'Riz parfumé',
      );
      expect((await etat().elementsGardes()).single.nature, 'conserve');
    });

    test('poussée puis PERDUE au serveur (version_serveur_conservee) : la '
        'version serveur s’applique à la descente suivante', () async {
      await articleLocalModifie();
      final cat = FauxCatalogue([renomme]);
      final appairage = (await b.lecteur.appairage())!;
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise', "
        "resultat_json = '{\"statut\":\"synchronise\","
        "\"resolution\":\"version_serveur_conservee\"}'",
      );
      final bilan = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(
        (bilan.recus, bilan.appliques, bilan.conservesLocalement),
        (0, 1, 0),
      );
      expect(
        (await ligne('articles_local', 'art-1'))!['libelle'],
        'Riz long (serveur)',
      );
    });

    test('poussée et GAGNANTE au serveur : la version gardée, périmée, est '
        'oubliée — la ligne locale reste celle du poste', () async {
      await articleLocalModifie();
      final cat = FauxCatalogue([renomme]);
      final appairage = (await b.lecteur.appairage())!;
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise', "
        "resultat_json = '{\"statut\":\"synchronise\"}'",
      );
      final bilan = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect((bilan.appliques, bilan.conservesLocalement), (0, 0));
      expect(
        (await ligne('articles_local', 'art-1'))!['libelle'],
        'Riz parfumé',
      );
      expect(await etat().elementsGardes(), isEmpty);
    });

    test('un HOMONYME créé ici et pas encore parti : pas de doublon ; une '
        'fois fusionné au serveur, la version serveur s’applique à la ligne '
        'du poste', () async {
      await StocksDao(
        b.db,
      ).creerPoint(libelle: 'Magasin central', id: 'ps-poste');
      final cat = FauxCatalogue([
        element('points_stockage', 'ps-serveur', {
          'libelle': 'MAGASIN  Central ',
        }),
      ]);
      final appairage = (await b.lecteur.appairage())!;
      final premier = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(premier.conservesLocalement, 1);
      expect(await compte('points_stockage_local'), 1);

      // L'envoi fusionne la création du poste sur l'élément serveur.
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise', "
        "id_serveur = 'ps-serveur'",
      );
      final second = await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(second.appliques, 1, reason: '$second');
      expect(await compte('points_stockage_local'), 1);
      expect(
        (await ligne('points_stockage_local', 'ps-poste'))!['libelle'],
        'MAGASIN  Central',
      );
    });
  });

  group('archives et centres de coût', () {
    test(
      'fournisseur archivé → `actif` faux ; unité hors service → '
      '`hors_service` ; article archivé → `actif` faux (21/10/2026 : appliqué, '
      'plus « il reste »)',
      () async {
        final bilan = await b
            .descente(
              transportDe(
                FauxCatalogue([
                  element('articles', 'art-1', {
                    'libelle': 'Vieux',
                    'unite_mesure': 'kg',
                    'seuil_alerte': '0.00',
                  }, actif: false),
                  element('categories_hebergement', 'cat-1', {
                    'libelle': 'Simple',
                    'capacite_max': 1,
                    'tarif_base': '15000.00',
                  }),
                  element('unites_hebergement', 'u-1', {
                    'categorie_id': 'cat-1',
                    'numero': '7',
                    'statut': 'hors_service',
                  }, actif: false),
                  element('fournisseurs', 'f-1', {
                    'raison_sociale': 'SOBEBRA',
                    'evaluation': 'bon',
                  }, actif: false),
                ]),
              ),
            )
            .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
        // Plus aucune archive n'est « non portée » : l'article l'est aussi.
        expect((bilan.appliques, bilan.archivesNonPortees), (4, 0));
        expect(await ligne('articles_local', 'art-1'), isNotNull);
        expect((await ligne('articles_local', 'art-1'))!['actif'], 0);
        expect(
          (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
          'hors_service',
        );
        expect((await ligne('fournisseurs_local', 'f-1'))!['actif'], 0);
        expect(
          (await ligne('fournisseurs_local', 'f-1'))!['cree_par'],
          'u-admin',
        );
      },
    );

    test('une unité EXISTANTE garde le statut de son cycle ; réintégrée au '
        'serveur, elle redevient libre', () async {
      final appairage = (await b.lecteur.appairage())!;
      final cat = FauxCatalogue([
        element('categories_hebergement', 'cat-1', {
          'libelle': 'Simple',
          'capacite_max': 1,
          'tarif_base': '15000.00',
        }),
        element('unites_hebergement', 'u-1', {
          'categorie_id': 'cat-1',
          'numero': '7',
          'statut': 'libre',
        }),
      ]);
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      await b.db.customStatement(
        "UPDATE unites_hebergement_local SET statut = 'occupee'",
      );
      await b.db.customStatement('DELETE FROM etat_synchronisation_local');
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'occupee',
      );
      await b.db.customStatement(
        "UPDATE unites_hebergement_local SET statut = 'hors_service'",
      );
      await b.db.customStatement('DELETE FROM etat_synchronisation_local');
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'libre',
      );

      // Archivée au serveur : l'unité EXISTANTE passe hors service.
      cat.elements[1] = element('unites_hebergement', 'u-1', {
        'categorie_id': 'cat-1',
        'numero': '7',
        'statut': 'hors_service',
      }, actif: false);
      await b.db.customStatement('DELETE FROM etat_synchronisation_local');
      await b
          .descente(transportDe(cat))
          .descendre(appairage, surRefus: (_) async {});
      expect(
        (await ligne('unites_hebergement_local', 'u-1'))!['statut'],
        'hors_service',
      );
    });

    test('centres de coût : reconnus par identifiant puis par libellé '
        'normalisé (correspondance retenue, jamais renommés) ; créés sous '
        'l’identifiant serveur seulement s’ils manquent', () async {
      await b.db.customStatement(
        'INSERT INTO centres_cout_local (id, libelle, type) '
        "VALUES ('cc-local', 'Hébergement', 'principal')",
      );
      final bilan = await b
          .descente(
            transportDe(
              FauxCatalogue([
                element('centres_cout', 'cc-serveur', {
                  'libelle': ' HEBERGEMENT',
                  'type': 'principal',
                }),
                element('centres_cout', 'cc-neuf', {
                  'libelle': 'Tourisme',
                  'type': 'principal',
                }),
              ]),
            ),
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(bilan.appliques, 2);
      expect(await compte('centres_cout_local'), 2);
      expect(
        (await ligne('centres_cout_local', 'cc-local'))!['libelle'],
        'Hébergement',
      );
      expect(await ligne('centres_cout_local', 'cc-serveur'), isNull);
      expect(
        (await ligne('centres_cout_local', 'cc-neuf'))!['libelle'],
        'Tourisme',
      );
      final c = (await etat().correspondances()).single;
      expect(
        (c.tableServeur, c.idServeur, c.idLocal, c.origine),
        ('centres_cout', 'cc-serveur', 'cc-local', 'libelle'),
      );
    });

    test('sans aucun compte local, un menu attend (jamais un auteur '
        'inventé)', () async {
      final bilan = await b
          .descente(
            transportDe(
              FauxCatalogue([
                element('menus', 'm-1', {'libelle': 'Midi', 'type': 'local'}),
              ]),
            ),
            auteur: null,
          )
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
      expect(bilan.enAttenteDeDependance, 1);
      expect(await ligne('menus_local', 'm-1'), isNull);
    });
  });

  group('dans le moteur : après l’envoi, sur son PROPRE repli', () {
    test('un échec de la descente ne bloque pas l’envoi suivant ; la '
        'descente attend son repli', () async {
      final ids = await b.enfilerClients(1);
      final t = FauxTransport(
        (r) => r.methode == 'GET'
            ? const ReponseHttp(statut: 503, corps: null)
            : reponseLot(r),
      );
      final manager = b.manager(t, descente: b.descente(t));
      final premier = await manager.synchroniserMaintenant();
      expect(premier.etat, EtatSynchronisation.termine);
      expect(premier.synchronisees, 1);
      expect(premier.descente!.etat, EtatDescente.serveurIndisponible);
      expect(premier.descente!.prochaineTentative, isNotNull);
      expect(
        (await b.operationDe(ids.single)).statut,
        StatutOperationSync.synchronise,
      );

      await b.enfilerClients(1, prefixe: 'D');
      final second = await manager.synchroniserMaintenant();
      expect(t.lots, hasLength(2), reason: 'l’envoi n’attend pas la descente');
      expect(t.descentes, hasLength(1), reason: 'la descente attend son repli');
      expect(second.descente!.etat, EtatDescente.enRepli);

      b.maintenant = b.maintenant.add(const Duration(minutes: 1));
      await manager.synchroniserMaintenant();
      expect(t.descentes, hasLength(2), reason: 'repli échu');
    });

    test('serveur indisponible à l’ENVOI : la descente est tentée quand '
        'même, sur son repli à elle', () async {
      await b.enfilerClients(1);
      final cat = FauxCatalogue(petitCatalogue());
      final t = FauxTransport(
        (r) => r.methode == 'GET'
            ? cat.repondre(r)
            : const ReponseHttp(statut: 503, corps: null),
      );
      final bilan = await b
          .manager(t, descente: b.descente(t))
          .synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.serveurIndisponible);
      expect(bilan.descente!.etat, EtatDescente.aJour);
      expect(await compte('articles_local'), 2);
    });

    test('401 à la descente : refus consigné, tout s’arrête (l’envoi '
        'suivant compris) jusqu’au réappairage', () async {
      final t = FauxTransport(
        (r) => r.methode == 'GET'
            ? const ReponseHttp(statut: 401, corps: null)
            : reponseLot(r),
      );
      final manager = b.manager(t, descente: b.descente(t));
      final bilan = await manager.synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.jetonRefuse);
      expect(bilan.descente!.etat, EtatDescente.refusee);
      expect((await b.lecteur.appairage())!.refus?.codeHttp, 401);

      await b.enfilerClients(1);
      expect(
        (await manager.synchroniserMaintenant()).etat,
        EtatSynchronisation.jetonRefuse,
      );
      expect(t.requetes, hasLength(1));
    });

    test('démonstration et poste non appairé : aucune descente', () async {
      final t = FauxTransport(
        (r) => FauxCatalogue(petitCatalogue()).repondre(r),
      );
      await b
          .manager(t, descente: b.descente(t), demonstration: true)
          .synchroniserMaintenant();
      final nu = await BancSync.creer(appaire: false);
      addTearDown(nu.fermer);
      await nu.manager(t, descente: nu.descente(t)).synchroniserMaintenant();
      expect(t.requetes, isEmpty);
    });

    test('le bilan de la dernière descente est CONSIGNÉ (l’écran le relit '
        'après un redémarrage)', () async {
      final t = transportDe(FauxCatalogue(petitCatalogue()));
      await b.manager(t, descente: b.descente(t)).synchroniserMaintenant();
      final relu = await etat().derniereDescente();
      expect(relu!.etat, EtatDescente.aJour);
      expect((relu.recus, relu.appliques), (5, 5));
      expect(relu.termineeLe, isNotNull);
    });
  });

  group('ancrages extérieurs (piège 12)', () {
    test('l’ordre des tables descendues est celui du SERVEUR '
        '(CatalogueDescendantService::COLONNES)', () {
      final source = File(
        '../tatacora-api/app/Shared/Sync/Services/CatalogueDescendantService.php',
      ).readAsStringSync();
      final bloc = RegExp(
        r'public const COLONNES = \[(.*?)\n    \];',
        dotAll: true,
      ).firstMatch(source)!.group(1)!;
      final tables = [
        for (final m in RegExp(
          r"^\s*'(\w+)' => \[",
          multiLine: true,
        ).allMatches(bloc))
          m.group(1),
      ];
      expect(tables, hasLength(greaterThanOrEqualTo(10)), reason: 'plancher');
      expect(tables, [for (final t in TableDescendue.values) t.nomServeur]);
    });
  });
}
