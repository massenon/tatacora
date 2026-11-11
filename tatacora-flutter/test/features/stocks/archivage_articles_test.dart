import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/archivage_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// L'ARCHIVAGE d'un article (« supprimer = archiver ») par le chemin que
/// l'écran emprunte : `StocksApi` -> `StocksDao` -> la base et la file d'envoi.
/// Les quatre VERROUS du serveur (`ReferentielArticleService::verrous`) sont
/// rejoués sur les données locales ; leurs phrases sont confrontées au fichier
/// de langue PHP dans `messages_stock_contre_serveur_test.dart`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksApi api;
  late StocksDao dao;
  late AchatsDao achats;
  var peutEcrire = true;
  var peutArchiver = true;
  late DateTime horloge;

  setUp(() async {
    db = AppDatabase.enMemoire();
    peutEcrire = true;
    peutArchiver = true;
    horloge = DateTime(2026, 10, 21, 8);

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

    DateTime tic() => horloge = horloge.add(const Duration(minutes: 1));
    dao = StocksDao(db, maintenant: tic);
    achats = AchatsDao(db, stocks: dao, maintenant: tic);
    api = StocksApi(
      dao: dao,
      peutLire: () => true,
      peutEcrire: () => peutEcrire,
      auteurId: () => 'u-1',
      peutArchiver: () async => peutArchiver,
    );
  });

  tearDown(() => db.close());

  Future<String> point() async =>
      ((await api.creerPoint(libelle: 'Magasin')) as PointEnregistre).point.id;

  Future<void> article(String id, String libelle) async {
    final r = await api.enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: 'Denrées',
        uniteMesure: 'sac',
        seuilAlerte: '5',
        suivi: SuiviArticle.permanent,
      ),
    );
    expect(r, isA<ArticleEnregistre>(), reason: '$r');
  }

  Future<void> mouvement(
    String articleId,
    String pointId,
    TypeMouvement type,
    String quantite, {
    bool force = false,
  }) async {
    final r = await api.enregistrerMouvement(
      SaisieMouvement(
        articleId: articleId,
        pointId: pointId,
        type: type,
        quantite: quantite,
        motif: 'Mouvement d’essai',
        validationRupture: force,
      ),
    );
    expect(r, isA<MouvementEnregistre>(), reason: '$r');
  }

  Future<bool?> actif(String id) async => (await (db.select(
    db.articlesLocal,
  )..where((a) => a.id.equals(id))).getSingle()).actif;

  Future<List<OperationSync>> file() =>
      OperationsSyncDao(db).operations(table: TableSynchronisee.articles);

  Future<String> fournisseur() async {
    final f = await achats.creerFournisseur(
      const SaisieFournisseur(
        id: 'four-1',
        raisonSociale: 'Grossiste',
        contact: null,
        categorie: null,
        conditionsPaiement: null,
        evaluationCode: null,
      ),
      auteurId: 'u-1',
    );
    return f.id;
  }

  Future<void> commande(String articleId) async {
    await achats.creerCommande(
      SaisieCommande(
        fournisseurId: await fournisseur(),
        dateCommande: '2026-10-20',
        statut: StatutCommande.envoyee,
        lignes: [
          LigneSaisieCommande(
            articleId: articleId,
            libelle: 'ignoré',
            uniteMesure: 'ignorée',
            quantite: '5',
            prixUnitaire: '1000',
          ),
        ],
      ),
      auteurId: 'u-1',
    );
  }

  group('Les quatre verrous du serveur, rejoués sur les données locales', () {
    test('1. du stock reste : strictement positif, tous points confondus — '
        'zéro ou négatif ne verrouille pas', () async {
      final magasin = await point();
      await article('riz', 'Riz local');
      expect(await dao.verrousArticle('riz'), isEmpty);

      await mouvement('riz', magasin, TypeMouvement.entree, '10');
      expect(await dao.verrousArticle('riz'), [
        MessagesStock.verrouStock('10.00'),
      ]);

      // Sorti en entier : plus rien ne verrouille.
      await mouvement('riz', magasin, TypeMouvement.sortie, '10');
      expect(await dao.verrousArticle('riz'), isEmpty);

      // Un solde NÉGATIF (sortie forcée) ne verrouille pas non plus : le
      // serveur compare `> 0`.
      await mouvement('riz', magasin, TypeMouvement.sortie, '3', force: true);
      expect(await dao.verrousArticle('riz'), isEmpty);
    });

    test('2. une commande d’achat EN COURS le porte (une ligne = une unité du '
        'décompte) ; réceptionnée ou clôturée, elle n’engage plus', () async {
      await article('riz', 'Riz local');
      await commande('riz');
      expect(await dao.verrousArticle('riz'), [
        MessagesStock.verrouCommande(1),
      ]);

      for (final statut in ['receptionnee', 'cloturee']) {
        await db.customStatement(
          "UPDATE commandes_achat_local SET statut = '$statut'",
        );
        expect(await dao.verrousArticle('riz'), isEmpty, reason: statut);
      }

      // Un statut INCONNU engage : on ne devine pas qu'une commande est
      // derrière nous (`whereNotIn` du serveur).
      await db.customStatement(
        "UPDATE commandes_achat_local SET statut = 'inconnu'",
      );
      expect(await dao.verrousArticle('riz'), [
        MessagesStock.verrouCommande(1),
      ]);
    });

    test('3. il est vendu à la carte (boissons du bar)', () async {
      await article('biere', 'Bière');
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: 'b-1',
              articleId: 'biere',
              libelle: 'Bière 65 cl',
              categorie: 'locale',
              prixVente: 1000,
            ),
          );
      expect(await dao.verrousArticle('biere'), [MessagesStock.verrouCarte(1)]);
    });

    test('4. il entre dans une recette', () async {
      await article('tomate', 'Tomates');
      await db
          .into(db.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: 'r-1',
              libelle: 'Sauce',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-1',
            ),
          );
      await db
          .into(db.ingredientsRecetteLocal)
          .insert(
            IngredientsRecetteLocalCompanion.insert(
              recetteId: 'r-1',
              articleId: 'tomate',
              quantiteMilliemes: 250,
            ),
          );
      expect(await dao.verrousArticle('tomate'), [
        MessagesStock.verrouRecette(1),
      ]);
    });

    test('les motifs s’additionnent dans l’ordre du serveur : stock, '
        'commande, carte, recette', () async {
      final magasin = await point();
      await article('riz', 'Riz local');
      await mouvement('riz', magasin, TypeMouvement.entree, '2');
      await commande('riz');
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: 'b-1',
              articleId: 'riz',
              libelle: 'Riz cuit',
              categorie: 'maison',
              prixVente: 500,
            ),
          );
      expect(await dao.verrousArticle('riz'), [
        MessagesStock.verrouStock('2.00'),
        MessagesStock.verrouCommande(1),
        MessagesStock.verrouCarte(1),
      ]);
    });
  });

  group('Le lot que la modale présente', () {
    test('NOMINAL, PARTIEL, BLOQUÉ : le nom, le nombre qui PART, les motifs '
        'avec le nom de l’article', () async {
      final magasin = await point();
      await article('a', 'Ananas');
      await article('b', 'Beurre');
      await mouvement('b', magasin, TypeMouvement.entree, '3');

      final nominal = await dao.composerLotArchivage(['a']);
      expect(nominal.ids, ['a']);
      expect((nominal.bloque, nominal.conserves), (false, 0));
      expect(nominal.element, 'Ananas');
      expect(nominal.nombre, isNull);

      final partiel = await dao.composerLotArchivage(['b', 'a']);
      expect(partiel.ids, ['a']);
      expect(partiel.conserves, 1);
      expect(partiel.bloque, isFalse);
      expect(partiel.motifs, ['Beurre — ${MessagesStock.verrouStock('3.00')}']);
      // Deux visés : on dit le NOMBRE, jamais un nom.
      expect(partiel.element, isNull);
      expect(partiel.nombre, 1);

      final bloque = await dao.composerLotArchivage(['b']);
      expect(bloque.bloque, isTrue);
      expect(bloque.ids, isEmpty);
      expect(bloque.motifs, hasLength(1));
    });

    test('une sélection d’articles DÉJÀ archivés ouvre la modale bloquée, '
        'sans motif', () async {
      await article('a', 'Ananas');
      await dao.archiverArticle('a');

      final lot = await dao.composerLotArchivage(['a']);
      expect(lot.bloque, isTrue);
      expect(lot.ids, isEmpty);
      expect(lot.motifs, isEmpty);
      expect(lot.conserves, 0);
    });
  });

  group('Archiver, restaurer', () {
    test('archiver pose `actif = false`, enfile {"actif": false}, ne supprime '
        'RIEN ; restaurer remet `true` et enfile {"actif": true}', () async {
      await article('riz', 'Riz local');
      final avant = (await file()).length;

      await dao.archiverArticle('riz');
      expect(await actif('riz'), isFalse);
      expect(await db.select(db.articlesLocal).get(), hasLength(1));

      var operations = (await file()).skip(avant).toList();
      expect(operations, hasLength(1));
      expect(operations.single.type, TypeOperationSync.modification);
      expect(operations.single.entiteId, 'riz');
      expect(jsonDecode(operations.single.payload), {'actif': false});

      final libelle = await dao.restaurerArticle('riz');
      expect(libelle, 'Riz local');
      expect(await actif('riz'), isTrue);
      operations = (await file()).skip(avant).toList();
      expect(jsonDecode(operations.last.payload), {'actif': true});
    });

    test('déjà archivé : rien ne change et rien ne part ; déjà actif, '
        'restaurer non plus', () async {
      await article('riz', 'Riz local');
      await dao.archiverArticle('riz');
      final apresArchivage = (await file()).length;

      await dao.archiverArticle('riz');
      expect((await file()).length, apresArchivage);

      await dao.restaurerArticle('riz');
      final apresRestauration = (await file()).length;
      await dao.restaurerArticle('riz');
      expect((await file()).length, apresRestauration);
    });

    test('un article engagé est REFUSÉ au moment d’agir — les verrous sont '
        'recontrôlés, pas ceux de l’ouverture de la modale', () async {
      final magasin = await point();
      await article('riz', 'Riz local');

      // La modale s'ouvre sur un lot NOMINAL…
      final lot = await dao.composerLotArchivage(['riz']);
      expect(lot.ids, ['riz']);
      // …puis une entrée de stock naît avant le clic.
      await mouvement('riz', magasin, TypeMouvement.entree, '4');

      final operations = (await file()).length;
      await expectLater(
        dao.archiverArticle('riz'),
        throwsA(
          isA<RefusStock>().having(
            (e) => e.motif,
            'motif',
            MessagesStock.verrouStock('4.00'),
          ),
        ),
      );
      expect(await actif('riz'), isTrue);
      expect((await file()).length, operations);
    });

    test('les motifs d’un article doublement engagé sont joints par une '
        'espace, comme `implode(" ", motifs)` du serveur', () async {
      final magasin = await point();
      await article('riz', 'Riz local');
      await mouvement('riz', magasin, TypeMouvement.entree, '4');
      await commande('riz');

      await expectLater(
        dao.archiverArticle('riz'),
        throwsA(
          isA<RefusStock>().having(
            (e) => e.motif,
            'motif',
            '${MessagesStock.verrouStock('4.00')} '
                '${MessagesStock.verrouCommande(1)}',
          ),
        ),
      );
    });

    test('un lot : le refus d’un article engagé n’empêche PAS les autres — '
        'succès et dernier refus coexistent', () async {
      final magasin = await point();
      await article('a', 'Ananas');
      await article('b', 'Beurre');
      await article('c', 'Céleri');
      await mouvement('b', magasin, TypeMouvement.entree, '1');

      final r = await dao.archiverLot(['a', 'b', 'c']);
      expect(r.archives, 2);
      expect(r.refus, MessagesStock.verrouStock('1.00'));
      expect(await actif('a'), isFalse);
      expect(await actif('b'), isTrue);
      expect(await actif('c'), isFalse);
    });

    test('un article inconnu : le refus de la vue', () async {
      await expectLater(
        dao.archiverArticle('fantome'),
        throwsA(
          isA<RefusStock>().having(
            (e) => e.motif,
            'motif',
            MessagesStock.articleInexistant,
          ),
        ),
      );
      await expectLater(
        dao.restaurerArticle('fantome'),
        throwsA(isA<RefusStock>()),
      );
    });

    test('un article archivé RESTE au référentiel et dans l’état du stock, '
        'marqué `actif = false` : il se retrouve, donc se restaure', () async {
      await article('riz', 'Riz local');
      await dao.archiverArticle('riz');

      final etat = await dao.etat();
      final ligne = etat.lignes.single;
      expect((ligne.id, ligne.actif), ('riz', false));
      expect((await dao.articles()).single.actif, isFalse);

      // Un fichier ramené d'avant la colonne (`actif` NULL) vaut ACTIF : un
      // NULL qui archiverait tout le parc serait le pire des replis.
      await db.customStatement('UPDATE articles_local SET actif = NULL');
      expect((await dao.etat()).lignes.single.actif, isTrue);
    });
  });

  group('Les droits : l’API exige la règle d’archivage, restaurer non', () {
    test('sans le droit d’écrire : 403 partout', () async {
      await article('riz', 'Riz local');
      peutEcrire = false;

      for (final r in [
        await api.preparerArchivage(['riz']),
        await api.archiverArticles(['riz']),
        await api.restaurerArticle('riz'),
      ]) {
        expect((r as StocksRefuse<dynamic>).codeHttp, 403);
      }
      expect(await actif('riz'), isTrue);
    });

    test('l’écriture sans la règle (bascule fermée, hors administrateur) '
        'refuse avec la phrase du serveur, dès l’OUVERTURE de la modale et '
        'de nouveau à l’exécution — mais RESTAURER reste permis', () async {
      await article('riz', 'Riz local');
      await dao.archiverArticle('riz');
      await article('huile', 'Huile');
      peutArchiver = false;

      final ouverture = await api.preparerArchivage(['huile']);
      expect(
        (ouverture as StocksRefuse<LotArchivage>).motif,
        startsWith('Archivage refusé'),
      );
      final execution = await api.archiverArticles(['huile']);
      expect(execution, isA<StocksRefuse<ResultatArchivage>>());
      expect(await actif('huile'), isTrue);

      final restauration = await api.restaurerArticle('riz');
      expect((restauration as StocksOk<String>).valeur, 'Riz local');
      expect(await actif('riz'), isTrue);
    });

    test('avec la règle : le lot est composé puis archivé', () async {
      await article('riz', 'Riz local');

      final lot =
          (await api.preparerArchivage(['riz']) as StocksOk<LotArchivage>)
              .valeur;
      expect(lot.ids, ['riz']);
      final r =
          (await api.archiverArticles(lot.ids) as StocksOk<ResultatArchivage>)
              .valeur;
      expect(r.archives, 1);
      expect(r.refus, isNull);
      expect(await actif('riz'), isFalse);
    });
  });
}
