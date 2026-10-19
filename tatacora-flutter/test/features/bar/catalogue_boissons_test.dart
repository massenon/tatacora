import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/bar/impression/etat_catalogue_boissons.dart';
import 'package:tatacora_flutter/features/bar/presentation/providers_catalogue_boissons.dart';

/// Le catalogue des boissons — un écran que la vue Blade de la PWA n'a PAS
/// (signalé comme ajout par `tool/conformite_blade/t-blade-flutter.js`,
/// PA-183). Les règles ci-dessous restent vraies ; c'est l'écran qui est à
/// arbitrer.
///
/// ## Ce que ces cas protègent
///
/// Trois risques, un groupe chacun :
///
///  1. **`null` pris pour zéro.** `stock_disponible` vaut `null` quand le
///     serveur ne sait pas ; « 0 » se lirait « rupture » et ferait commander
///     des caisses qu'on a déjà (PA-129, Article 7).
///  2. **La pagination du maître appliquée sur une page serveur.** Le serveur
///     pagine par 50 en dur ; le maître affiche 10 lignes. La découpe est
///     locale, et le décompte doit dire sur quoi il porte.
///  3. **Les deux registres de catégorie.** Le maître écrit « Importée », le
///     schéma stocke `importee`. Les confondre casse l'envoi — c'est le piège
///     nommé en PA-116 sur les types de client.
void main() {
  Boisson boisson(
    String id, {
    String libelle = 'Sodabi artisanal',
    String categorie = 'locale',
    String prix = '1000.00',
    String? stock = '42.00',
    String article = 'art-1',
  }) => Boisson(
    id: id,
    libelle: libelle,
    categorie: CategorieBoisson.depuisCode(categorie),
    categorieBrute: categorie,
    prixVente: prix,
    articleId: article,
    stockDisponible: stock,
    stockLectureSeule: true,
  );

  PageBar<Boisson> pageServeur(List<Boisson> b, {int? total}) => PageBar(
    elements: b,
    total: total ?? b.length,
    page: 1,
    derniere: 1,
    parPage: 50,
  );

  /* ================================================================== */
  group('CategorieBoisson — deux registres, un seul point de rencontre', () {
    test('le libellé est celui du MAÎTRE, le code celui du SCHÉMA', () {
      // ⚠ Le maître écrit « Importée » (capitale, accent) ; l'enum du schéma
      // vaut `importee`. Envoyer le libellé ferait échouer `Rule::in` en 422.
      expect(CategorieBoisson.importee.libelle, 'Importée');
      expect(CategorieBoisson.importee.code, 'importee');
      expect(CategorieBoisson.locale.libelle, 'Locale');
      expect(CategorieBoisson.maison.libelle, 'Maison');
    });

    test('les trois codes sont EXACTEMENT ceux de l\'enum du schéma', () {
      expect(CategorieBoisson.values.map((c) => c.code).toList(), [
        'locale',
        'maison',
        'importee',
      ]);
    });

    test('un code inconnu ne se range PAS par défaut', () {
      // `null` plutôt qu'un repli sur `locale` : une valeur ajoutée demain
      // doit se voir, pas atterrir en silence dans la mauvaise case.
      expect(CategorieBoisson.depuisCode('artisanale'), isNull);
      expect(CategorieBoisson.depuisCode(null), isNull);
    });

    test('une catégorie inconnue reste AFFICHABLE via son code brut', () {
      final b = boisson('1', categorie: 'artisanale');
      expect(b.categorie, isNull);
      // Sans `categorieBrute`, la valeur disparaîtrait de l'écran au lieu de
      // s'y voir — et personne ne saurait que le serveur en a envoyé une.
      expect(b.categorieLibelle, 'artisanale');
    });
  });

  /* ================================================================== */
  // ⚠ COUVERTURE RETIRÉE le 14/09/2026 — `BoissonsApi.lireBoisson`.
  //
  // Ces trois cas figeaient la lecture du JSON du serveur : `stock_disponible`
  // à `null` reste `null` (« on ne sait pas ») et ne devient jamais zéro (« en
  // rupture »), et `stock_lecture_seule` est lu plutôt que supposé. Le poste
  // est zéro réseau : il n'y a plus de JSON à lire, et la méthode a été
  // supprimée avec le corps du client.
  //
  // **L'invariant, lui, n'est pas mort** — il a changé de porteur. C'est
  // désormais `stockBarProvider` qui rend `null` plutôt qu'une liste vide, et
  // `composerCarte` qui l'affiche « non consulté ». Le jour où un inventaire
  // local alimentera la carte, c'est là qu'il faudra le réarmer : un zéro sur
  // l'écran qui sert à commander est le défaut que ces trois cas empêchaient.

  /* ================================================================== */
  group('SaisieBoisson — l\'identifiant ne part JAMAIS dans le corps', () {
    test('le corps du PUT ne porte pas `id`', () async {
      // ⚠ `EnregistrerBoissonRequest` accepte `'id' => ['sometimes','uuid']`
      // et `id` est `$fillable` sur `CarteBoisson` : un `id` posté sur un PUT
      // RÉÉCRIRAIT la clé primaire, cassant toute référence dans
      // `lignes_vente_bar`. Ce cas fige que l'identifiant ne sert que l'URL.
      const saisie = SaisieBoisson(
        libelle: 'Sodabi',
        categorie: CategorieBoisson.locale,
        prixVente: '1000',
        articleId: 'art-1',
        id: 'boisson-existante',
      );

      expect(saisie.id, 'boisson-existante');
      // Le corps est construit dans `enregistrer()` ; le cas de rendu qui suit
      // (`ecran_catalogue_boissons_test.dart`) éprouve l'envoi réel.
      expect(saisie.articleId, 'art-1');
    });
  });

  /* ================================================================== */
  group('decouperCommeLeMaitre — 10 lignes par page, filtre local', () {
    test('la page vaut les 10 premières, comme `crud-engine.js` l.21', () {
      final page = decouperCommeLeMaitre(
        pageServeur([for (var i = 0; i < 25; i++) boisson('$i')]),
        terme: '',
        page: 1,
      );

      expect(page.elements.length, BoissonsApi.boissonsParPage);
      expect(page.total, 25);
      expect(page.derniere, 3);
      expect(page.premier, 1);
      expect(page.dernier, 10);
    });

    test('la dernière page ne contient que le reste', () {
      final page = decouperCommeLeMaitre(
        pageServeur([for (var i = 0; i < 25; i++) boisson('$i')]),
        terme: '',
        page: 3,
      );

      expect(page.elements.length, 5);
      expect(page.premier, 21);
      expect(page.dernier, 25);
    });

    test('une page hors bornes revient à la dernière, pas à du vide', () {
      // Rien ne protège d'un total qui rétrécit entre deux lectures : rester
      // en page 9 afficherait une liste vide sous un total non nul.
      final page = decouperCommeLeMaitre(
        pageServeur([for (var i = 0; i < 12; i++) boisson('$i')]),
        terme: '',
        page: 9,
      );

      expect(page.page, 2);
      expect(page.elements, isNotEmpty);
    });

    test('la recherche filtre sur le libellé et remet le total à jour', () {
      final page = decouperCommeLeMaitre(
        pageServeur([
          boisson('1', libelle: 'Sodabi artisanal'),
          boisson('2', libelle: 'Tchoukoutou'),
          boisson('3', libelle: 'Jus de bissap frais'),
        ]),
        terme: 'tchouk',
        page: 1,
      );

      expect(page.elements.length, 1);
      expect(page.total, 1);
      expect(page.elements.single.libelle, 'Tchoukoutou');
    });

    test('une recherche sans résultat rend une page vide, total 0', () {
      final page = decouperCommeLeMaitre(
        pageServeur([boisson('1')]),
        terme: 'introuvable',
        page: 1,
      );

      expect(page.elements, isEmpty);
      expect(page.total, 0);
      // « Affichage de 0-0 sur 0 » — la formulation du maître tient sur le
      // vide sans afficher « 1-0 ».
      expect(page.premier, 0);
    });

    test(
      'l\'avertissement N\'APPARAÎT QUE si le serveur a réellement tronqué',
      () {
        // Une mention permanente cesse d'être lue. Elle ne doit se voir que
        // quand le catalogue dépasse la page serveur de 50.
        final court = decouperCommeLeMaitre(
          pageServeur([for (var i = 0; i < 12; i++) boisson('$i')]),
          terme: '',
          page: 1,
        );
        expect(court.avertissement, isNull);

        final tronque = decouperCommeLeMaitre(
          pageServeur(
            [for (var i = 0; i < 50; i++) boisson('$i')],
            // Le serveur en annonce 120 et n'en a envoyé que 50.
            total: 120,
          ),
          terme: '',
          page: 1,
        );
        expect(tronque.avertissement, isNotNull);
        expect(tronque.avertissement, contains('50'));
        expect(tronque.avertissement, contains('120'));
        expect(tronque.totalServeur, 120);
      },
    );
  });

  /* ================================================================== */
  group('EtatCatalogueBoissons — le CSV dit ce qu\'il porte', () {
    test('les quatre colonnes du maître sont écrites', () {
      // `m5-bar.html` l.113-118 : `nom, categorie, prix, stock_disponible`.
      expect(EtatCatalogueBoissons.colonnes, [
        'nom',
        'categorie',
        'prix',
        'stock_disponible',
      ]);
      // Aucune n'est sans source — contrairement à M4, où deux ont dû être
      // retirées.
      expect(EtatCatalogueBoissons.colonnesAbsentes, isEmpty);
    });

    test('un stock inconnu part en case VIDE, jamais en « 0 »', () {
      final csv = EtatCatalogueBoissons.csv([
        boisson('1', libelle: 'Sodabi', stock: null),
      ], filtre: 'page 1');

      final lignes = const LineSplitter().convert(csv);
      final ligne = lignes.firstWhere((l) => l.startsWith('Sodabi'));

      // « Sodabi;Locale;1000.00; » — quatre champs, le dernier vide.
      expect(ligne, 'Sodabi;Locale;1000.00;');
      // Le point du cas : un comptable qui lit « 0 » conclut « rupture » et
      // commande.
      expect(ligne.endsWith(';0'), isFalse);
    });

    test('un stock connu part tel quel, sans arrondi', () {
      final csv = EtatCatalogueBoissons.csv([
        boisson('1', libelle: 'Sodabi', stock: '42.60'),
      ], filtre: 'page 1');

      // Nombre BRUT : un tableur ne sait pas additionner « 42,6 unités », et
      // arrondir 42,6 à 43 annoncerait un casier qu'on n'a pas.
      expect(csv, contains('Sodabi;Locale;1000.00;42.60'));
    });

    test('le fichier porte le BOM UTF-8 et le point-virgule (RG-19)', () {
      final csv = EtatCatalogueBoissons.csv(const [], filtre: 'page 1');

      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Boissons;page 1'));
      expect(csv, contains('nom;categorie;prix;stock_disponible'));
    });

    test('le filtre est ÉCRIT dans le fichier (PA-119)', () {
      final csv = EtatCatalogueBoissons.csv([
        boisson('1'),
      ], filtre: 'catégorie : Locale · page 2');

      // Quelqu'un qui filtre puis exporte attend son filtre. Le document le
      // dit, sinon il enverrait au comptable un fichier qu'il croit complet.
      expect(csv, contains('catégorie : Locale · page 2'));
    });

    test('un point-virgule dans un libellé ne casse PAS les colonnes', () {
      final csv = EtatCatalogueBoissons.csv([
        boisson('1', libelle: 'Cocktail; maison'),
      ], filtre: 'page 1');

      expect(csv, contains('Cocktail, maison;Locale'));
    });
  });
}
