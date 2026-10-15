import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/carte_bar.dart';
import 'package:tatacora_flutter/features/bar/impression/etat_carte.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';

/// La carte du bar — composition, filtres et documents.
///
/// ## Ce que ces cas protègent
///
/// **Que « je ne sais pas » ne se dise jamais « zéro ».** Le stock est calculé
/// par le serveur sur des tables M6 que ce poste ne détient pas ; hors
/// connexion il est absent. Un zéro à sa place ferait commander des caisses
/// déjà en réserve, et un « 0 en rupture » se lirait comme une bonne nouvelle.
void main() {
  LigneCarte ligne(
    String id, {
    String libelle = 'Béninoise 33cl',
    String categorie = 'locale',
    int prix = 1000,
    String? articleId,
    double? stock,
  }) => LigneCarte(
    id: id,
    libelle: libelle,
    categorie: categorie,
    prix: prix,
    articleId: articleId,
    stock: stock,
  );

  // ⚠ Le stock de la carte est `stockVendable` (bouteilles) depuis PA-199 ;
  // `stockDisponible` (casiers) reçoit ici une valeur DIFFÉRENTE, pour que le
  // test rougisse si la composition relisait les casiers.
  BoissonDistante distante(String id, {String? articleId, double? stock}) =>
      BoissonDistante(
        id: id,
        articleId: articleId,
        libelle: 'x',
        categorie: 'locale',
        prixVente: 1000,
        stockDisponible: stock == null ? null : stock / 24,
        stockVendable: stock,
      );

  /* ================================================================== */
  group('La composition', () {
    test('sans réponse du serveur, la carte LOCALE suffit', () {
      // C'est le sens de l'écran : la carte s'affiche au comptoir sans réseau.
      final carte = composerCarte(local: [ligne('b1')], distantes: null);

      expect(carte, hasLength(1));
      expect(carte.single.stock, isNull);
      expect(carte.single.prix, 1000);
    });

    test('le stock du serveur enrichit la ligne locale', () {
      final carte = composerCarte(
        local: [ligne('b1')],
        distantes: [distante('b1', articleId: 'art-1', stock: 12)],
      );

      expect(carte.single.stock, 12);
      expect(carte.single.estLieAuStock, isTrue);
    });

    test('l’état de retrait n’est CONNU que pour ce que le serveur a rendu', () {
      // `b1` est dans la réponse, retiré ; `b2` aussi, à la carte ; `b3` n'y
      // est pas — créée ailleurs depuis, ou hors de la page servie. Pour elle,
      // aucune supposition : ni « à la carte », ni « retirée ».
      final retrait = IndisponibiliteDistante(
        motif: 'rupture',
        libelle: 'Rupture du jour',
        temporaire: true,
      );
      final carte = composerCarte(
        local: [ligne('b1'), ligne('b2'), ligne('b3')],
        distantes: [
          BoissonDistante(
            id: 'b1',
            articleId: 'art-1',
            libelle: 'x',
            categorie: 'locale',
            prixVente: 1000,
            stockDisponible: null,
            indisponibilite: retrait,
          ),
          distante('b2'),
        ],
      );

      expect(carte[0].disponibiliteConnue, isTrue);
      expect(carte[0].estRetiree, isTrue);
      expect(carte[1].disponibiliteConnue, isTrue);
      expect(carte[1].estRetiree, isFalse);
      expect(carte[2].disponibiliteConnue, isFalse);
    });

    test('sans réponse du serveur, AUCUN état de retrait n’est connu', () {
      final carte = composerCarte(local: [ligne('b1')], distantes: null);

      expect(carte.single.disponibiliteConnue, isFalse);
    });

    test('« sans lien » et « non consulté » ne se confondent PAS', () {
      // Les deux donnent `stock == null`, et la conséquence n'est pas la même :
      // l'un ne décrémente aucun casier, l'autre attend le réseau.
      final sansLien = composerCarte(
        local: [ligne('b1')],
        distantes: [distante('b1', stock: null)],
      ).single;
      final nonConsulte = composerCarte(
        local: [ligne('b1', articleId: 'art-1')],
        distantes: null,
      ).single;

      expect(sansLien.estLieAuStock, isFalse);
      expect(nonConsulte.estLieAuStock, isTrue);
      expect(sansLien.stock, isNull);
      expect(nonConsulte.stock, isNull);
    });

    test('un stock ABSENT n’est pas une rupture', () {
      expect(ligne('b1', stock: null).enRupture, isFalse);
      expect(ligne('b1', stock: 0).enRupture, isTrue);
    });

    test('le lien de stock du SERVEUR fait foi', () {
      // La copie locale peut dater d'avant un rattachement fait au bureau.
      final carte = composerCarte(
        local: [ligne('b1')],
        distantes: [distante('b1', articleId: 'art-neuf')],
      );

      expect(carte.single.articleId, 'art-neuf');
    });
  });

  /* ================================================================== */
  group('Les filtres', () {
    late List<LigneCarte> carte;

    setUp(() {
      carte = [
        ligne('b1', libelle: 'Béninoise', articleId: 'a1', stock: 12),
        ligne('b2', libelle: 'Sodabi', categorie: 'maison'),
        ligne(
          'b3',
          libelle: 'Heineken',
          categorie: 'importee',
          articleId: 'a3',
          stock: 0,
        ),
      ];
    });

    test('la recherche porte sur le libellé', () {
      expect(filtrerCarte(carte, terme: 'sodabi'), hasLength(1));
    });

    test('« lié » et « sans lien » partagent la carte', () {
      final lies = filtrerCarte(carte, etat: EtatCarte.lie);
      final sans = filtrerCarte(carte, etat: EtatCarte.sansLien);

      expect(lies, hasLength(2));
      expect(sans, hasLength(1));
      expect(lies.length + sans.length, carte.length);
    });

    test('« en rupture » ne retient QUE le stock connu à zéro', () {
      final rupture = filtrerCarte(carte, etat: EtatCarte.ruptureStock);

      expect(rupture, hasLength(1));
      expect(rupture.single.id, 'b3');
    });

    test('les six états de la vue, dans son ordre (PA-200)', () {
      // `pwa/carte/corps.blade.php` l.246-254 — « Retirés du jour » et « Prix
      // provisoire » manquaient faute de donnée ; l'API les rend désormais.
      expect(EtatCarte.values.map((e) => e.code), [
        '',
        'indisponible',
        'lie',
        'sans_lien',
        'rupture_stock',
        'provisoire',
      ]);
    });

    test(
      '« Retirés du jour » et « Prix provisoire » filtrent sur la donnée',
      () {
        final lignes = [
          LigneCarte(
            id: 'r',
            libelle: 'Retirée',
            categorie: 'locale',
            prix: 1000,
            articleId: 'a',
            stock: 1,
            indisponibilite: IndisponibiliteDistante(
              motif: 'rupture',
              libelle: 'Rupture du jour',
              temporaire: true,
            ),
          ),
          const LigneCarte(
            id: 'p',
            libelle: 'Provisoire',
            categorie: 'locale',
            prix: 1000,
            articleId: 'a',
            stock: 1,
            prixProvisoire: true,
          ),
        ];
        expect(
          filtrerCarte(lignes, etat: EtatCarte.indisponible).single.id,
          'r',
        );
        expect(filtrerCarte(lignes, etat: EtatCarte.provisoire).single.id, 'p');
      },
    );

    test(
      'la couverture compte liens, retraits et provisoires par catégorie',
      () {
        final couverture = couvertureParCategorie([
          const LigneCarte(
            id: 'a',
            libelle: 'a',
            categorie: 'locale',
            prix: 1,
            articleId: 'x',
            stock: null,
            prixProvisoire: true,
          ),
          LigneCarte(
            id: 'b',
            libelle: 'b',
            categorie: 'locale',
            prix: 1,
            articleId: null,
            stock: null,
            indisponibilite: IndisponibiliteDistante(
              motif: 'saison',
              libelle: 'Hors saison',
              temporaire: true,
            ),
          ),
          const LigneCarte(
            id: 'c',
            libelle: 'c',
            categorie: 'maison',
            prix: 1,
            articleId: 'y',
            stock: null,
          ),
        ]);

        final locale = couverture.first;
        expect(locale.categorie, 'locale');
        expect(locale.articles, 2);
        expect(locale.lies, 1);
        expect(locale.sansLien, 1);
        expect(locale.tauxLisible, '50');
        expect(locale.indisponibles, 1);
        expect(locale.provisoires, 1);

        final total = CouvertureCategorieBar.total(couverture);
        expect(total.articles, 3);
        expect(total.lies, 2);
        expect(total.tauxLisible, '66.7');
      },
    );
  });

  /* ================================================================== */
  group('Les indicateurs', () {
    test('« en rupture » DIT quand le stock n’a pas été consulté', () {
      // Sans cela, « 0 » se lirait comme une bonne nouvelle.
      final horsLigne = KpisCarte.calculer([ligne('b1', articleId: 'a1')]);
      final enLigne = KpisCarte.calculer([
        ligne('b1', articleId: 'a1', stock: 4),
      ]);

      expect(horsLigne.stockConnu, isFalse);
      expect(horsLigne.enRupture, 0);
      expect(enLigne.stockConnu, isTrue);
    });

    test('les six indicateurs de la vue, comptés comme la PWA', () {
      final kpis = KpisCarte.calculer([
        // Rupture : comptée en rupture, JAMAIS aussi sous le seuil.
        const LigneCarte(
          id: 'b1',
          libelle: 'a',
          categorie: 'locale',
          prix: 1000,
          articleId: 'a1',
          stock: 0,
          rupture: true,
          sousSeuil: true,
        ),
        // Sous le seuil, provisoire.
        const LigneCarte(
          id: 'b2',
          libelle: 'b',
          categorie: 'locale',
          prix: 1000,
          articleId: 'a2',
          stock: 5,
          rupture: false,
          sousSeuil: true,
          prixProvisoire: true,
        ),
        // Retirée du jour, sans lien.
        LigneCarte(
          id: 'b3',
          libelle: 'c',
          categorie: 'locale',
          prix: 1000,
          articleId: null,
          stock: null,
          indisponibilite: IndisponibiliteDistante(
            motif: 'rupture',
            libelle: 'Rupture du jour',
            temporaire: true,
          ),
        ),
      ]);

      expect(kpis.articles, 3);
      expect(kpis.indisponibles, 1);
      expect(kpis.disponibles, 2);
      expect(kpis.lies, 2);
      expect(kpis.sansLien, 1);
      expect(kpis.tauxLisible, '66.7');
      expect(kpis.enRupture, 1);
      expect(kpis.sousSeuil, 1);
      expect(kpis.prixProvisoires, 1);
    });

    test('le taux entier s’imprime sans décimale, comme la PWA', () {
      final kpis = KpisCarte.calculer([ligne('b1', articleId: 'a1')]);
      expect(kpis.tauxLisible, '100');
    });
  });

  /* ================================================================== */
  group('Les documents', () {
    test('le CSV laisse la case de stock VIDE, jamais à zéro', () {
      // Un zéro dirait « rupture » ; la case vide dit « on ne sait pas ».
      final csv = EtatCarteBar.csv([
        ligne('b1', articleId: 'a1'),
      ], filtre: 'Carte complète');

      expect(csv.startsWith('﻿'), isTrue, reason: 'BOM UTF-8 (RG-19)');
      expect(csv, contains('Béninoise 33cl;locale;1000;oui;'));
      expect(csv, isNot(contains('oui;0')));
    });

    test('la fiche des prix ÉCARTE les sans-tarif et les COMPTE', () async {
      // « On ne masque pas : un tarif absent devient négociable au comptoir. »
      final (octets, ecartes) = await EtatCarteBar.ficheDesPrix([
        ligne('b1'),
        ligne('b2', libelle: 'Cocktail maison', prix: 0),
      ]);

      expect(ecartes, 1);
      // Un document réellement composé : c'est la composition qui lève sur un
      // glyphe absent de la police.
      expect(octets.length, greaterThan(1000));
    });

    test('le tableau de gestion se compose, filtre en sous-titre', () async {
      final octets = await EtatCarteBar.pdf([
        ligne('b1'),
      ], filtre: 'locale — recherche « bén »');

      expect(octets.length, greaterThan(1000));
    });
  });
}
