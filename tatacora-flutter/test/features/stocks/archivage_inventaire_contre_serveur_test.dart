@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';
import 'package:tatacora_flutter/features/stocks/presentation/widgets/modales_inventaire.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// L'ARCHIVAGE d'un article et l'INVENTAIRE physique, CONFRONTÉS au serveur en
/// l'exécutant — jamais à une phrase ou à une règle recopiée (piège 12).
///
///  * les phrases : `lang/fr/stocks.php` et `stocks_pwa.php` lus par
///    `tool/stocks/exporter_calculs.php` ;
///  * les VERROUS : `tool/stocks/rejouer_archivage.php` fait tourner
///    `ReferentielArticleService::verrous` sur six scénarios (en transaction
///    annulée, base d'essai), et le poste monte les mêmes sur sa base locale.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('Les phrases sont celles du serveur, mot pour mot', () {
    late Map<String, dynamic> langue;

    setUpAll(() async {
      final php = await Process.start('php', [
        'tool/stocks/exporter_calculs.php',
      ]);
      php.stdin.write('{}');
      await php.stdin.close();
      final sortie = utf8.decodeStream(php.stdout);
      final erreur = utf8.decodeStream(php.stderr);
      final code = await php.exitCode;
      if (code != 0) fail('exporter_calculs.php : code $code, ${await erreur}');
      langue = jsonDecode(await sortie) as Map<String, dynamic>;
    });

    Map<String, dynamic> archivage() =>
        langue['archivage'] as Map<String, dynamic>;
    Map<String, dynamic> inventaires() =>
        langue['inventaires'] as Map<String, dynamic>;

    test('l’extraction n’est pas vide', () {
      expect(archivage().length, greaterThan(8));
      expect(inventaires().length, greaterThan(40));
    });

    test('les quatre verrous d’archivage', () {
      expect(
        MessagesStock.verrouStock('12.50'),
        (archivage()['verrou_stock'] as String).replaceAll(
          ':quantite',
          '12.50',
        ),
      );
      expect(
        MessagesStock.verrouCommande(3),
        (archivage()['verrou_commande'] as String).replaceAll(':nombre', '3'),
      );
      expect(
        MessagesStock.verrouCarte(2),
        (archivage()['verrou_carte'] as String).replaceAll(':nombre', '2'),
      );
      expect(
        MessagesStock.verrouRecette(4),
        (archivage()['verrou_recette'] as String).replaceAll(':nombre', '4'),
      );
    });

    test('le succès (singulier / pluriel) et la restauration', () {
      // `trans_choice('{1} … |[2,*] …')` : le premier membre pour 1, le second
      // pour deux et plus.
      final membres = (archivage()['succes'] as String).split('|');
      expect(membres, hasLength(2));
      final singulier = membres[0].replaceFirst('{1} ', '');
      final pluriel = membres[1]
          .replaceFirst('[2,*] ', '')
          .replaceAll(':nombre', '5');
      expect(MessagesStock.archivesSucces(1), singulier);
      expect(MessagesStock.archivesSucces(5), pluriel);
      expect(
        MessagesStock.restaure('Riz'),
        (archivage()['restaure'] as String).replaceAll(':libelle', 'Riz'),
      );
    });

    test('les boutons et la pastille de la vue sont ceux du serveur', () {
      expect(archivage()['badge'], 'Archivé');
      expect(archivage()['bouton_ligne'], 'Supprimer');
      expect(archivage()['bouton_lot'], 'Supprimer');
      expect(archivage()['bouton_restaurer'], 'Restaurer');
      expect(archivage()['selection_tout'], 'Tout sélectionner');
      expect(archivage()['selection_ligne'], 'Sélectionner cette ligne');
      expect(archivage()['selectionnes'], ':nombre sélectionné(s)');
    });

    test('l’inventaire : refus du serveur, motif de régularisation, messages '
        'de la vue', () {
      expect(MessagesStock.quantiteNegative, langue['quantite_negative']);
      final incomplet = (langue['inventaire_incomplet'] as String).replaceAll(
        ':nombre',
        '3',
      );
      expect(MessagesStock.inventaireIncomplet(3), incomplet);
      // La modale écrit la même phrase ELLE-MÊME (la mesure de conformité ne
      // suit pas les imports) : les deux copies sont confrontées ici.
      expect(phraseInventaireIncomplet(3), incomplet);

      expect(
        MessagesStock.motifRegularisation(inventaire: 'abc', ecart: '-1.00'),
        (langue['motif_regularisation'] as String)
            .replaceAll(':inventaire', 'abc')
            .replaceAll(':ecart', '-1.00'),
      );
      expect(
        MessagesStock.inventaireOuvert(7),
        (inventaires()['lance'] as String).replaceAll(':nombre', '7'),
      );
      expect(
        MessagesStock.comptageEnregistre('Riz'),
        (inventaires()['comptage_enregistre'] as String).replaceAll(
          ':article',
          'Riz',
        ),
      );
      expect(
        MessagesStock.inventaireCloture(nombre: 2, impact: '2 500 FCFA'),
        (inventaires()['cloture'] as String)
            .replaceAll(':nombre', '2')
            .replaceAll(':impact', '2 500 FCFA'),
      );
      expect(
        MessagesStock.aucunPointDefini,
        inventaires()['aucun_point_defini'],
      );
      expect(inventaires()['incomplet_titre'], 'Inventaire incomplet');
      expect(inventaires()['incomplet_confirmer'], 'Clôturer partiellement');
      expect(inventaires()['cloturer'], 'Clôturer et régulariser');
      expect(inventaires()['lancer'], "Lancer l'inventaire");
      expect(inventaires()['a_compter'], 'à compter');
      expect(inventaires()['enregistrer_comptage'], 'Enregistrer le comptage');
    });
  });

  group('Les verrous rejoués sur le poste sont ceux que le serveur rend', () {
    late AppDatabase db;
    late StocksDao dao;
    late StocksApi api;
    late Map<String, dynamic> serveur;

    setUpAll(() async {
      serveur = await executerPhp(
        'rejouer_archivage.php',
        dossier: 'stocks',
        // Une base d'essai privée (TATACORA_BASE_ESSAI) a son propre verrou :
        // la file de `tatacora_test` ne concerne pas celui qui ne la touche pas.
        nomVerrou:
            Platform.environment['TATACORA_BASE_ESSAI'] ?? 'tatacora_test_php',
      );
    });

    setUp(() async {
      db = AppDatabase.enMemoire();
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-1',
              login: 'magasinier',
              nom: 'Aïcha',
              role: 'administrateur',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
      dao = StocksDao(db);
      api = StocksApi(
        dao: dao,
        peutLire: () => true,
        peutEcrire: () => true,
        auteurId: () => 'u-1',
      );
    });

    tearDown(() => db.close());

    Future<void> article(String id) async {
      final r = await api.enregistrerArticle(
        SaisieArticle(
          id: id,
          libelle: id,
          categorie: 'Denrées',
          uniteMesure: 'sac',
          seuilAlerte: '5',
          suivi: SuiviArticle.permanent,
        ),
      );
      expect(r, isA<ArticleEnregistre>(), reason: '$r');
    }

    Future<void> mouvement(
      String id,
      String point,
      TypeMouvement type,
      String q,
    ) async {
      final r = await api.enregistrerMouvement(
        SaisieMouvement(
          articleId: id,
          pointId: point,
          type: type,
          quantite: q,
          motif: 'Essai',
        ),
      );
      expect(r, isA<MouvementEnregistre>(), reason: '$r');
    }

    var rang = 0;
    Future<void> commande(String article, String statut) async {
      rang++;
      await db
          .into(db.fournisseursLocal)
          .insert(
            FournisseursLocalCompanion.insert(
              id: 'f$rang',
              raisonSociale: 'Grossiste $rang',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-1',
            ),
          );
      await db
          .into(db.commandesAchatLocal)
          .insert(
            CommandesAchatLocalCompanion.insert(
              id: 'c$rang',
              fournisseurId: 'f$rang',
              dateCommande: '2026-10-20',
              statut: statut,
              creeLe: DateTime(2026, 10, 20),
              utilisateurId: 'u-1',
            ),
          );
      await db
          .into(db.lignesCommandeAchatLocal)
          .insert(
            LignesCommandeAchatLocalCompanion.insert(
              id: 'l$rang',
              commandeId: 'c$rang',
              articleId: article,
              articleLibelle: article,
              uniteMesure: 'sac',
              quantiteCentiemes: 500,
              prixUnitaireCentimes: 100000,
              rang: 1,
            ),
          );
    }

    Future<void> boisson(String article, String id) => db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: id,
            articleId: article,
            libelle: id,
            categorie: 'locale',
            prixVente: 1000,
          ),
        );

    Future<void> recette(String article, String id) async {
      await db
          .into(db.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: id,
              libelle: id,
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-1',
            ),
          );
      await db
          .into(db.ingredientsRecetteLocal)
          .insert(
            IngredientsRecetteLocalCompanion.insert(
              recetteId: id,
              articleId: article,
              quantiteMilliemes: 250,
            ),
          );
    }

    List<String> attendu(String scenario) =>
        (serveur[scenario] as List).cast<String>();

    test('l’extraction du serveur n’est pas vide', () {
      expect(serveur.keys, {
        'libre',
        'stock',
        'commandes',
        'carte',
        'recettes',
        'tout',
      });
      expect(attendu('tout'), hasLength(4));
    });

    test('libre : aucun verrou', () async {
      await article('libre');
      expect(await dao.verrousArticle('libre'), attendu('libre'));
    });

    test('stock : le solde restant (entrée de 10, sortie de 3)', () async {
      final p = ((await api.creerPoint(libelle: 'Magasin')) as PointEnregistre)
          .point
          .id;
      await article('stock');
      await mouvement('stock', p, TypeMouvement.entree, '10');
      await mouvement('stock', p, TypeMouvement.sortie, '3');
      expect(await dao.verrousArticle('stock'), attendu('stock'));
    });

    test('commandes : seules celles EN COURS comptent — brouillon et envoyée, '
        'pas réceptionnée ni clôturée', () async {
      await article('commandes');
      await commande('commandes', 'envoyee');
      await commande('commandes', 'brouillon');
      await commande('commandes', 'receptionnee');
      await commande('commandes', 'cloturee');
      expect(await dao.verrousArticle('commandes'), attendu('commandes'));
    });

    test('carte : la boisson vendue', () async {
      await article('carte');
      await boisson('carte', 'b-a');
      expect(await dao.verrousArticle('carte'), attendu('carte'));
    });

    test('recettes : deux compositions', () async {
      await article('recettes');
      await recette('recettes', 'r-1');
      await recette('recettes', 'r-2');
      expect(await dao.verrousArticle('recettes'), attendu('recettes'));
    });

    test('tout : les quatre motifs, dans l’ordre du serveur', () async {
      final p = ((await api.creerPoint(libelle: 'Magasin')) as PointEnregistre)
          .point
          .id;
      await article('tout');
      await mouvement('tout', p, TypeMouvement.entree, '2');
      await commande('tout', 'envoyee');
      await boisson('tout', 'b-b');
      await recette('tout', 'r-3');
      expect(await dao.verrousArticle('tout'), attendu('tout'));
    });
  });
}
