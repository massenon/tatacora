import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/fiche_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// Les règles de gestion de M6 — des fonctions pures, éprouvées sur des
/// valeurs calculées À LA MAIN (chaque cas dit son calcul), jamais sur la
/// sortie de la fonction elle-même.
void main() {
  group('Conversions : des entiers, jamais un arrondi silencieux', () {
    test('une quantité saisie devient des centièmes exacts', () {
      expect(lireCentiemes('12'), 1200);
      expect(lireCentiemes('12,5'), 1250);
      expect(lireCentiemes('12.50'), 1250);
      expect(lireCentiemes('0,05'), 5);
      expect(lireCentiemes(' 7 '), 700);
    });

    test('une troisième décimale est REFUSÉE, pas tronquée', () {
      expect(lireCentiemes('12.505'), isNull);
      expect(lireCentiemes('0,001'), isNull);
    });

    test('les formes qui ne sont pas un nombre positif sont refusées', () {
      for (final mauvais in ['', 'abc', '-1', '1 2', '12,', ',5', '1e3']) {
        expect(lireCentiemes(mauvais), isNull, reason: '« $mauvais »');
      }
    });

    test('un coût porte jusqu’à quatre décimales, pas cinq', () {
      expect(lireCout('1250'), 12500000);
      expect(lireCout('833,3333'), 8333333);
      expect(lireCout('0.0001'), 1);
      expect(lireCout('0.00001'), isNull);
    });

    test('l’écriture rend toujours deux (ou quatre) décimales', () {
      expect(ecrireCentiemes(1250), '12.50');
      expect(ecrireCentiemes(5), '0.05');
      expect(ecrireCentiemes(0), '0.00');
      expect(ecrireCentiemes(-50), '-0.50');
      expect(ecrireCentiemes(-1250), '-12.50');
      expect(ecrireCout(8333333), '833.3333');
      expect(ecrireCout(0), '0.0000');
      expect(ecrireCout(1), '0.0001');
    });

    test('lire puis écrire ne change aucun chiffre', () {
      for (final texte in ['12.50', '0.05', '1000.00', '99999.99']) {
        expect(ecrireCentiemes(lireCentiemes(texte)!), texte);
      }
      for (final texte in ['833.3333', '0.0001', '25000.0000']) {
        expect(ecrireCout(lireCout(texte)!), texte);
      }
    });
  });

  group('La valeur d’un stock : quantité × coût, au franc entier', () {
    test('12,50 × 833,3333 = 10 416,66625 -> 10 417 F', () {
      // 1250 × 8 333 333 = 10 416 666 250 millionièmes de franc.
      expect(valeurEnFrancs(1250, 8333333), 10417);
    });

    test('la moitié s’arrondit en s’éloignant de zéro', () {
      // 1,00 × 0,5000 F = 0,5 F exactement -> 1 F ; et -1 F pour -0,5 F.
      expect(valeurEnFrancs(100, 5000), 1);
      expect(valeurEnFrancs(-100, 5000), -1);
      // Juste en dessous de la moitié : 0,4999 F -> 0.
      expect(valeurEnFrancs(100, 4999), 0);
    });

    test('un stock à zéro ou un coût nul valent zéro franc', () {
      expect(valeurEnFrancs(0, 8333333), 0);
      expect(valeurEnFrancs(1250, 0), 0);
    });

    test('un stock négatif (rupture forcée) a une valeur négative', () {
      // -2,00 × 1 250,0000 = -2 500 F.
      expect(valeurEnFrancs(-200, 12500000), -2500);
    });
  });

  group('Le coût moyen pondéré — la formule du serveur, en entiers', () {
    test('10,00 à 1 000 + 5,00 à 1 250,50 -> 1 083,50', () {
      // (1000 × 10 000 000 + 500 × 12 505 000) / 1500 = 10 835 000.
      expect(
        moyennePonderee(
          quantiteAvant: 1000,
          cmpAvant: 10000000,
          quantiteEntree: 500,
          coutEntree: 12505000,
        ),
        10835000,
      );
    });

    test('la division TRONQUE, comme bcdiv — elle n’arrondit pas', () {
      // (100 × 10 000 + 200 × 10 001) / 300 = 3 000 200 / 300 = 10 000,666…
      // Arrondi, on aurait 10 001 ; tronqué, 10 000.
      expect(
        moyennePonderee(
          quantiteAvant: 100,
          cmpAvant: 10000,
          quantiteEntree: 200,
          coutEntree: 10001,
        ),
        10000,
      );
    });

    test('un stock de départ nul ou négatif retombe sur le coût d’entrée', () {
      for (final avant in [0, -200]) {
        expect(
          moyennePonderee(
            quantiteAvant: avant,
            cmpAvant: 5000,
            quantiteEntree: 100,
            coutEntree: 7000,
          ),
          7000,
          reason: 'stock avant $avant',
        );
      }
    });

    test('une entrée au même coût ne change pas le CMP', () {
      expect(
        moyennePonderee(
          quantiteAvant: 300,
          cmpAvant: 25000000,
          quantiteEntree: 700,
          coutEntree: 25000000,
        ),
        25000000,
      );
    });
  });

  group('Le CMP est REJOUÉ des mouvements, dans l’ordre d’écriture', () {
    MouvementCalcul m(
      int ordre,
      TypeMouvement type,
      int quantite, {
      int? cout,
      String point = 'magasin',
    }) => MouvementCalcul(
      id: 'm$ordre',
      articleId: 'riz',
      pointId: point,
      type: type,
      centiemes: quantite,
      ordre: ordre,
      date: DateTime(2026, 10, 1, 8, ordre),
      coutDixMilliemes: cout,
    );

    final histoire = [
      m(1, TypeMouvement.entree, 1000, cout: 10000000), // 10,00 à 1 000
      m(2, TypeMouvement.entree, 500, cout: 12505000), // 5,00 à 1 250,50
      m(3, TypeMouvement.sortie, 300), // sortie : ne change pas le CMP
      m(4, TypeMouvement.entree, 200, point: 'bar'), // transfert sans coût
      m(5, TypeMouvement.perte, 100), // perte : ne change pas le CMP
    ];

    test('seules les entrées valorisées le modifient', () {
      expect(coutMoyenPondereDe(histoire), 10835000);
      expect(coutMoyenPondereDe(histoire.sublist(0, 1)), 10000000);
      expect(coutMoyenPondereDe(const []), 0);
    });

    test('l’ORDRE d’écriture commande, pas l’ordre de la liste ni la date', () {
      expect(coutMoyenPondereDe(histoire.reversed.toList()), 10835000);

      // Une horloge qui a reculé : la date du 2e est AVANT celle du 1er. Le
      // rejeu suit le rang, sinon l'histoire serait réordonnée.
      final recule = [
        MouvementCalcul(
          id: 'a',
          articleId: 'riz',
          pointId: 'magasin',
          type: TypeMouvement.entree,
          centiemes: 1000,
          ordre: 1,
          date: DateTime(2026, 10, 9),
          coutDixMilliemes: 10000000,
        ),
        MouvementCalcul(
          id: 'b',
          articleId: 'riz',
          pointId: 'magasin',
          type: TypeMouvement.entree,
          centiemes: 500,
          ordre: 2,
          date: DateTime(2026, 10, 1),
          coutDixMilliemes: 12505000,
        ),
      ];
      expect(coutMoyenPondereDe(recule), 10835000);
    });

    test('le rang commande MÊME avec une sortie intercalée et des dates '
        'inversées : trier par date donnerait un autre CMP', () {
      MouvementCalcul mv(
        int ordre,
        TypeMouvement type,
        int quantite,
        DateTime date, {
        int? cout,
      }) => MouvementCalcul(
        id: 'r$ordre',
        articleId: 'riz',
        pointId: 'magasin',
        type: type,
        centiemes: quantite,
        ordre: ordre,
        date: date,
        coutDixMilliemes: cout,
      );

      // Écrits dans cet ordre (rang 1, 2, 3), mais datés à rebours :
      //  1. entrée 10,00 à 1 000      (date : le 9)
      //  2. sortie  8,00              (date : le 1)
      //  3. entrée  8,00 à 2 000      (date : le 5)
      // Par RANG : stock 10 -> 2, puis (2 × 1 000 + 8 × 2 000) / 10 = 1 800.
      // Par DATE : la sortie (le 1) passe en premier sur un stock vide (-8),
      // l'entrée du 5 repart de son coût (2 000, stock avant négatif), puis
      // celle du 9 voit un stock nul et repart de 1 000 : CMP 1 000.
      final h = [
        mv(
          1,
          TypeMouvement.entree,
          1000,
          DateTime(2026, 10, 9),
          cout: 10000000,
        ),
        mv(2, TypeMouvement.sortie, 800, DateTime(2026, 10, 1)),
        mv(3, TypeMouvement.entree, 800, DateTime(2026, 10, 5), cout: 20000000),
      ];
      expect(coutMoyenPondereDe(h), 18000000);
      expect(coutMoyenPondereDe(h.reversed.toList()), 18000000);
      expect(
        dernierPrixAchatDe(h),
        20000000,
        reason: 'dernier ÉCRIT, pas daté',
      );
    });

    test('une sortie AVANT la 2e entrée pèse dans la pondération', () {
      // 10,00 à 1 000, sortie de 8,00 -> reste 2,00 ; puis 8,00 à 2 000 :
      // (200 × 10 000 000 + 800 × 20 000 000) / 1000 = 18 000 000.
      final h = [
        m(1, TypeMouvement.entree, 1000, cout: 10000000),
        m(2, TypeMouvement.sortie, 800),
        m(3, TypeMouvement.entree, 800, cout: 20000000),
      ];
      expect(coutMoyenPondereDe(h), 18000000);
    });

    test(
      'après une rupture forcée, la prochaine entrée repart de son coût',
      () {
        // 5,00 à 1 000, sortie forcée de 8,00 -> stock -3,00 ; entrée de 10,00
        // à 1 400 : le stock avant est négatif, le CMP devient 1 400.
        final h = [
          m(1, TypeMouvement.entree, 500, cout: 10000000),
          m(2, TypeMouvement.sortie, 800),
          m(3, TypeMouvement.entree, 1000, cout: 14000000),
        ];
        expect(stockDe(h.sublist(0, 2)), -300);
        expect(coutMoyenPondereDe(h), 14000000);
      },
    );

    test('le dernier prix d’achat est celui de la dernière entrée valorisée, '
        'jamais le CMP', () {
      expect(dernierPrixAchatDe(histoire), 12505000);
      expect(dernierPrixAchatDe(histoire), isNot(coutMoyenPondereDe(histoire)));
      // Un transfert (entrée sans coût) ne remplace pas le prix.
      expect(dernierPrixAchatDe(histoire.sublist(0, 4)), 12505000);
      // Jamais réceptionné : null, pas zéro.
      expect(dernierPrixAchatDe([m(1, TypeMouvement.entree, 100)]), isNull);
      expect(dernierPrixAchatDe(const []), isNull);
    });

    test('la dérive du CMP contre le dernier prix, en pourcentage entier', () {
      // CMP 1 106,25 contre 1 000 : +10,625 % -> 11 (le serveur rend 11).
      expect(deriveCoutMoyenPondere(cmp: 11062500, prixAchat: 10000000), 11);
      // CMP 900 contre 1 000 : -10 %.
      expect(deriveCoutMoyenPondere(cmp: 9000000, prixAchat: 10000000), -10);
      // Identique : 0 (mesurable, et nul).
      expect(deriveCoutMoyenPondere(cmp: 10000000, prixAchat: 10000000), 0);
      // Jamais réceptionné, ou prix nul : pas de dérive du tout.
      expect(deriveCoutMoyenPondere(cmp: 10000000, prixAchat: null), isNull);
      expect(deriveCoutMoyenPondere(cmp: 10000000, prixAchat: 0), isNull);
    });
  });

  group('Le stock : la somme signée, par point', () {
    MouvementCalcul m(TypeMouvement t, int q, String point) => MouvementCalcul(
      id: '$t$q$point',
      articleId: 'a',
      pointId: point,
      type: t,
      centiemes: q,
      ordre: 1,
      date: DateTime(2026, 10, 1),
    );

    test('entrée et régularisation ajoutent, sortie et perte retranchent', () {
      final ms = [
        m(TypeMouvement.entree, 1000, 'bar'),
        m(TypeMouvement.sortie, 250, 'bar'),
        m(TypeMouvement.perte, 50, 'bar'),
        m(TypeMouvement.inventaire, 300, 'bar'),
        // Une régularisation NÉGATIVE : l'écart constaté est signé.
        m(TypeMouvement.inventaire, -100, 'bar'),
      ];
      expect(stockDe(ms), 1000 - 250 - 50 + 300 - 100);
      expect(stockDe(ms), 900);
    });

    test('un point n’est pas l’autre : 10 au bar et 0 au magasin', () {
      final ms = [
        m(TypeMouvement.entree, 1000, 'bar'),
        m(TypeMouvement.entree, 400, 'magasin'),
        m(TypeMouvement.sortie, 150, 'magasin'),
      ];
      expect(stockDe(ms, pointId: 'bar'), 1000);
      expect(stockDe(ms, pointId: 'magasin'), 250);
      expect(stockDe(ms, pointId: 'garage'), 0);
      expect(stockDe(ms), 1250);
    });

    test('la convention de signe est portée par le type, une seule fois', () {
      expect(TypeMouvement.entree.ajouteAuStock, isTrue);
      expect(TypeMouvement.inventaire.ajouteAuStock, isTrue);
      expect(TypeMouvement.sortie.ajouteAuStock, isFalse);
      expect(TypeMouvement.perte.ajouteAuStock, isFalse);
    });
  });

  group('RG-06 — le contrôle de disponibilité', () {
    test('un disponible qui couvre la demande passe', () {
      expect(
        controlerSortie(disponible: 500, demande: 500, forcage: false),
        IssueSortie.couverte,
        reason: 'égal : la sortie du dernier article est permise',
      );
      expect(
        controlerSortie(disponible: 501, demande: 500, forcage: false),
        IssueSortie.couverte,
      );
    });

    test('un disponible insuffisant demande CONFIRMATION, sans écrire', () {
      expect(
        controlerSortie(disponible: 499, demande: 500, forcage: false),
        IssueSortie.ruptureAConfirmer,
      );
    });

    test('le forçage assume la rupture', () {
      expect(
        controlerSortie(disponible: 499, demande: 500, forcage: true),
        IssueSortie.ruptureForcee,
      );
      // Forcer quand ce n'est pas nécessaire n'est pas une rupture.
      expect(
        controlerSortie(disponible: 500, demande: 500, forcage: true),
        IssueSortie.couverte,
      );
    });

    test('un disponible négatif est insuffisant', () {
      expect(
        controlerSortie(disponible: -100, demande: 1, forcage: false),
        IssueSortie.ruptureAConfirmer,
      );
    });

    test('la phrase chiffre les deux nombres comparés', () {
      expect(
        messageRupture(disponible: '3.00', demande: '4.50'),
        'Stock insuffisant : 3.00 disponible, 4.50 demandé. '
        'Une validation explicite est requise pour forcer la sortie.',
      );
    });
  });

  group('L’état consolidé', () {
    final maintenant = DateTime(2026, 10, 9, 14, 3);

    ArticleCalcul article(
      String id,
      String libelle, {
      int seuil = 500,
      SuiviArticle suivi = SuiviArticle.permanent,
      String? categorie,
      String? point,
    }) => ArticleCalcul(
      id: id,
      libelle: libelle,
      categorie: categorie,
      uniteMesure: 'sac',
      seuilCentiemes: seuil,
      suivi: suivi,
      pointStockageId: point,
    );

    var rang = 0;
    MouvementCalcul mv(
      String articleId,
      TypeMouvement type,
      int quantite, {
      String point = 'magasin',
      int? cout,
      DateTime? date,
    }) {
      rang++;
      return MouvementCalcul(
        id: 'mv$rang',
        articleId: articleId,
        pointId: point,
        type: type,
        centiemes: quantite,
        ordre: rang,
        date: date ?? DateTime(2026, 10, 8),
        coutDixMilliemes: cout,
      );
    }

    // Quatre articles, volontairement dans le désordre.
    late List<ArticleCalcul> articles;
    late List<MouvementCalcul> mouvements;

    setUp(() {
      rang = 0;
      articles = [
        article('sel', 'Sel', seuil: 200),
        article('tom', 'Tomates', suivi: SuiviArticle.journalier, seuil: 0),
        article(
          'riz',
          'Riz local (sac 50 kg)',
          seuil: 500,
          categorie: 'Denrées',
          point: 'magasin',
        ),
        article('hui', 'huile de palme', seuil: 500),
      ];
      mouvements = [
        // Riz : 10,00 à 25 000 F au magasin, sortie de 4,00 -> 6,00.
        mv('riz', TypeMouvement.entree, 1000, cout: 250000000),
        mv('riz', TypeMouvement.sortie, 400),
        // Huile : 5,00 à 1 250,50 -> pile sur son seuil (5,00).
        mv('hui', TypeMouvement.entree, 500, cout: 12505000),
        // Un mouvement vieux de 31 jours : hors de la fenêtre de 30 jours.
        mv(
          'sel',
          TypeMouvement.entree,
          300,
          date: DateTime(2026, 10, 9, 14, 3).subtract(const Duration(days: 31)),
        ),
        mv('sel', TypeMouvement.sortie, 300),
        // Un transfert vers le bar, sans coût.
        mv('riz', TypeMouvement.entree, 200, point: 'bar'),
      ];
    });

    EtatStock etat({
      String? pointId,
      EtatStockFiltre filtre = EtatStockFiltre.tous,
    }) => calculerEtat(
      articles: articles,
      mouvements: mouvements,
      maintenant: maintenant,
      libellesPoints: const {'magasin': 'Magasin général', 'bar': 'Bar'},
      pointId: pointId,
      filtre: filtre,
    );

    test(
      'les lignes sont triées par libellé, sans tenir compte de la casse',
      () {
        expect(etat().lignes.map((l) => l.libelle).toList(), [
          'huile de palme',
          'Riz local (sac 50 kg)',
          'Sel',
          'Tomates',
        ]);
      },
    );

    test('le stock, le CMP et la valeur de chaque ligne', () {
      final riz = etat().lignes.firstWhere((l) => l.id == 'riz');
      // 10,00 + 2,00 (bar) - 4,00 = 8,00, tous points confondus.
      expect(riz.stock, '8.00');
      // Le transfert sans coût ne revalorise rien : CMP = 25 000.
      expect(riz.coutMoyenPondere, '25000.0000');
      // 8,00 × 25 000 = 200 000 F.
      expect(riz.valeurStock, '200000');
      expect(riz.prixAchat, '25000.0000');
      expect(riz.deriveCmp, 0);
      expect(riz.categorie, 'Denrées');
      expect(riz.pointLibelle, 'Magasin général');
      expect(riz.portee, 'tous points');
      expect(riz.seuilAlerte, '5.00');

      final huile = etat().lignes.firstWhere((l) => l.id == 'hui');
      expect(huile.stock, '5.00');
      expect(huile.coutMoyenPondere, '1250.5000');
      // 5,00 × 1 250,50 = 6 252,50 -> 6 253 F.
      expect(huile.valeurStock, '6253');
      expect(huile.pointLibelle, isNull, reason: 'jamais rattaché : null');
    });

    test('les compteurs : égalité au seuil comprise, journalier exclu', () {
      final k = etat().kpis;
      // Huile : 5,00 <= 5,00 (sous seuil, pas en rupture). Sel : 0 <= 2,00 et
      // 0 <= 0 (sous seuil ET en rupture). Riz : 8,00 > 5,00. Tomates :
      // journalier -> aucune alarme, bien que son solde soit zéro.
      expect(k.sousSeuil, 2);
      expect(k.rupture, 1);
      expect(k.references, 4);
      expect(k.permanents, 3);
      expect(k.journaliers, 1);
    });

    test('la valeur du stock est la somme des valeurs AFFICHÉES', () {
      // 200 000 (riz) + 6 253 (huile) + 0 (sel) + 0 (tomates).
      expect(etat().kpis.valeurStock, '206253');
      final somme = etat().lignes
          .map((l) => int.parse(l.valeurStock))
          .reduce((a, b) => a + b);
      expect(somme, 206253);
    });

    test(
      'un article journalier n’a pas de stock : ni rupture ni sous seuil',
      () {
        final t = etat().lignes.firstWhere((l) => l.id == 'tom');
        expect(t.estJournalier, isTrue);
        expect(t.enRupture, isFalse);
        expect(t.sousSeuil, isFalse);
        expect(t.valeurStock, '0');
      },
    );

    test('le filtre « sous seuil » masque les sains mais ne change pas '
        'les compteurs d’alarme', () {
      final e = etat(filtre: EtatStockFiltre.sousSeuil);
      expect(e.lignes.map((l) => l.id).toSet(), {'hui', 'sel'});
      // Les compteurs portent sur TOUT le référentiel de la portée.
      expect(e.kpis.sousSeuil, 2);
      expect(e.kpis.rupture, 1);
      expect(e.kpis.permanents, 3);
      expect(e.kpis.journaliers, 1);
      // `references` et la valeur suivent les lignes affichées.
      expect(e.kpis.references, 2);
      expect(e.kpis.valeurStock, '6253');
    });

    test(
      'la portée d’un point recalcule le stock, pas un filtre d’affichage',
      () {
        final bar = etat(pointId: 'bar');
        final riz = bar.lignes.firstWhere((l) => l.id == 'riz');
        expect(riz.stock, '2.00');
        expect(riz.portee, 'Bar');
        // Le CMP est celui de l'ARTICLE : un point n'a pas de coût propre.
        expect(riz.coutMoyenPondere, '25000.0000');
        expect(riz.valeurStock, '50000');
        // Au magasin : 10,00 - 4,00 = 6,00.
        expect(
          etat(
            pointId: 'magasin',
          ).lignes.firstWhere((l) => l.id == 'riz').stock,
          '6.00',
        );
      },
    );

    test('mouvements des 30 jours : la fenêtre est semi-ouverte à gauche', () {
      // Six mouvements, dont un de 31 jours.
      expect(etat().kpis.mouvements30Jours, 5);
      // Au bar : un seul mouvement (le transfert).
      expect(etat(pointId: 'bar').kpis.mouvements30Jours, 1);

      // Pile à 30 jours : encore compté.
      mouvements = [
        mv(
          'riz',
          TypeMouvement.entree,
          100,
          date: maintenant.subtract(const Duration(days: 30)),
        ),
      ];
      expect(etat().kpis.mouvements30Jours, 1);
    });

    test('du stock sans aucun coût connu est COMPTÉ, pas valorisé à zéro', () {
      articles = [
        article('riz', 'Riz', seuil: 100),
        article('poivre', 'Poivre', seuil: 100),
        article('sucre', 'Sucre', seuil: 100),
        article('vide', 'Vide', seuil: 100),
      ];
      mouvements = [
        mv('riz', TypeMouvement.entree, 500, cout: 10000), // valorisé
        mv('poivre', TypeMouvement.entree, 300), // transfert : aucun coût
        // Un stock NÉGATIF sans coût est aussi inconnu : il n'est pas nul.
        mv('sucre', TypeMouvement.sortie, 100),
        // `vide` : aucun mouvement, stock 0 -> rien à valoriser, rien à dire.
      ];
      final k = etat().kpis;
      expect(k.sansValorisation, 2);
      // Leur valeur n'est PAS dans le total (0 F), et l'écran le dit.
      expect(k.valeurStock, '5');
      final poivre = etat().lignes.firstWhere((l) => l.id == 'poivre');
      expect(poivre.prixAchat, isNull, reason: 'jamais réceptionné');
      expect(poivre.valeurStock, '0');
    });

    test('un poste neuf : aucun article, des compteurs à zéro mais VRAIS', () {
      final e = calculerEtat(
        articles: const [],
        mouvements: const [],
        maintenant: maintenant,
        libellesPoints: const {},
      );
      expect(e.lignes, isEmpty);
      expect(e.kpis.references, 0);
      expect(e.kpis.valeurStock, '0');
      expect(e.kpis.permanents, 0);
      expect(e.kpis.journaliers, 0);
      expect(e.kpis.sansValorisation, 0);
      expect(e.arreteAu, '09/10/2026 14:03');
    });
  });

  group('La fiche de stock', () {
    // Riz : une entrée AVANT la période, trois mouvements DANS la période.
    MouvementCalcul mv(
      int ordre,
      TypeMouvement type,
      int quantite,
      DateTime date, {
      String point = 'magasin',
      int? cout,
      bool forcee = false,
    }) => MouvementCalcul(
      id: 'm$ordre',
      articleId: 'riz',
      pointId: point,
      type: type,
      centiemes: quantite,
      ordre: ordre,
      date: date,
      motif: 'motif $ordre',
      auteur: 'Aïcha',
      coutDixMilliemes: cout,
      ruptureForcee: forcee,
    );

    final histoire = [
      mv(
        1,
        TypeMouvement.entree,
        1000,
        DateTime(2026, 9, 30, 9),
        cout: 1000000,
      ),
      mv(2, TypeMouvement.sortie, 300, DateTime(2026, 10, 2, 8, 30)),
      mv(3, TypeMouvement.perte, 50, DateTime(2026, 10, 5, 23, 59)),
      mv(4, TypeMouvement.sortie, 900, DateTime(2026, 10, 7, 12), forcee: true),
      mv(
        5,
        TypeMouvement.entree,
        4000,
        DateTime(2026, 10, 8, 10),
        cout: 1200000,
      ),
    ];

    FicheStock fiche({String? point, DateTime? debut, DateTime? fin}) =>
        calculerFiche(
          article: const ArticleFiche(
            id: 'riz',
            libelle: 'Riz local',
            unite: 'sac',
            cmp: '',
          ),
          cmp: coutMoyenPondereDe(histoire),
          mouvements: histoire,
          debut: debut ?? DateTime(2026, 10, 1),
          fin: fin ?? DateTime(2026, 10, 7),
          pointId: point,
        );

    test('stock initial = solde à la veille ; l’égalité de la fiche tient', () {
      final f = fiche();
      // Avant le 1er octobre : 10,00.
      expect(f.stockInitial, '10.00');
      expect(f.entrees, '0.00');
      expect(f.sorties, '12.00', reason: '3,00 + 9,00');
      expect(f.pertes, '0.50');
      expect(f.regularisations, '0.00');
      // 10,00 - 3,00 - 0,50 - 9,00 = -2,50 : la sortie forcée du 7 octobre.
      expect(f.stockTheorique, '-2.50');
      expect(f.coherent, isTrue);
    });

    test('le solde progressif se lit ligne à ligne, comme un relevé', () {
      final f = fiche();
      expect(f.lignes.map((l) => l.solde).toList(), ['7.00', '6.50', '-2.50']);
      expect(f.lignes.map((l) => l.type).toList(), [
        'Sortie',
        'Perte',
        'Sortie',
      ]);
      // Une ligne est une entrée OU une sortie, jamais les deux.
      expect(f.lignes.first.entree, '0.00');
      expect(f.lignes.first.sortie, '3.00');
    });

    test('la rupture forcée et l’auteur figurent sur la fiche', () {
      final f = fiche();
      expect(f.lignes.map((l) => l.ruptureForcee).toList(), [
        false,
        false,
        true,
      ]);
      expect(f.lignes.every((l) => l.par == 'Aïcha'), isTrue);
      expect(f.lignes.map((l) => l.motif).toList(), [
        'motif 2',
        'motif 3',
        'motif 4',
      ]);
    });

    test('les bornes de la période sont INCLUSES, jusqu’à 23 h 59', () {
      // Le mouvement n° 3 est daté du 5 octobre à 23 h 59 : il est dans une
      // période qui se termine le 5.
      final f = fiche(fin: DateTime(2026, 10, 5));
      expect(f.lignes.map((l) => l.motif).toList(), ['motif 2', 'motif 3']);
      expect(f.stockTheorique, '6.50');
      // Et il n'est pas dans une période qui se termine la veille.
      final avant = fiche(fin: DateTime(2026, 10, 4));
      expect(avant.lignes.map((l) => l.motif).toList(), ['motif 2']);
    });

    test(
      'une période sans mouvement : le stock théorique est celui du début',
      () {
        final f = fiche(
          debut: DateTime(2026, 10, 3),
          fin: DateTime(2026, 10, 4),
        );
        expect(f.lignes, isEmpty);
        expect(f.estVide, isTrue);
        expect(f.stockInitial, '7.00');
        expect(f.stockTheorique, '7.00');
        expect(f.coherent, isTrue);
      },
    );

    test('la valeur est le stock théorique au CMP courant', () {
      // CMP rejoué : 10,00 à 100 puis (stock -2,50 avant) 40,00 à 120 -> le
      // stock avant l'entrée est négatif, le CMP devient 120,0000.
      final f = calculerFiche(
        article: const ArticleFiche(
          id: 'riz',
          libelle: 'Riz local',
          unite: 'sac',
          cmp: '',
        ),
        cmp: coutMoyenPondereDe(histoire),
        mouvements: histoire,
        debut: DateTime(2026, 10, 1),
        fin: DateTime(2026, 10, 31),
      );
      expect(f.article.cmp, '120.0000');
      // Stock théorique : 10 - 3 - 0,5 - 9 + 40 = 37,50 ; × 120 = 4 500 F.
      expect(f.stockTheorique, '37.50');
      expect(f.valeurStockTheorique, '4500');
    });

    test('un point restreint la fiche ET le dit', () {
      final f = fiche(point: 'bar');
      expect(f.pointId, 'bar');
      expect(f.stockInitial, '0.00');
      expect(f.lignes, isEmpty);
      // Le stock du point est donné ; tous points confondus, il ne l'est pas.
      expect(f.article.stock, '0.00');
      expect(fiche().article.stock, isNull);
    });

    test(
      'une fiche dont les deux calculs divergent est déclarée INCOHÉRENTE',
      () {
        // Période inversée (début le 7, fin le 2), appelée directement : le
        // cumul des lignes part du solde à la veille du 7 (6,50, aucune ligne), le
        // stock théorique est relu à la veille du 3 (7,00). Les deux chemins ne
        // peuvent pas s'accorder — et la fiche le DIT au lieu de présenter un
        // total plausible. Sans ce cas, `coherent: true` écrit en dur ne ferait
        // rougir aucun test.
        final f = calculerFiche(
          article: const ArticleFiche(
            id: 'riz',
            libelle: 'Riz local',
            unite: 'sac',
            cmp: '',
          ),
          cmp: coutMoyenPondereDe(histoire),
          mouvements: histoire,
          debut: DateTime(2026, 10, 7),
          fin: DateTime(2026, 10, 2),
        );
        expect(f.coherent, isFalse);
      },
    );

    test('les dates de la fiche sont au format AAAA-MM-JJ', () {
      final f = fiche();
      expect(f.debut, '2026-10-01');
      expect(f.fin, '2026-10-07');
      expect(f.lignes.first.date, '2026-10-02 08:30:00');
    });
  });
}
