import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';

/// M6 sur sa source LOCALE — par le chemin que l'écran emprunte :
/// `StocksApi` -> `StocksDao` -> la base. Aucun faux : un test qui simulerait le
/// DAO ne dirait rien de ce que la base reçoit réellement (piège 5).
void main() {
  late AppDatabase db;
  late StocksApi api;
  var peutLire = true;
  var peutEcrire = true;
  String? auteur = 'u-1';
  late DateTime horloge;

  setUp(() async {
    db = AppDatabase.enMemoire();
    peutLire = true;
    peutEcrire = true;
    auteur = 'u-1';
    horloge = DateTime(2026, 10, 9, 8);

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

    api = StocksApi(
      dao: StocksDao(
        db,
        // Chaque appel avance d'une minute : deux mouvements n'ont jamais le
        // même instant, et l'ordre d'écriture est observable.
        maintenant: () => horloge = horloge.add(const Duration(minutes: 1)),
      ),
      peutLire: () => peutLire,
      peutEcrire: () => peutEcrire,
      auteurId: () => auteur,
    );
  });

  tearDown(() => db.close());

  Future<String> point(String libelle, {TypePoint? type}) async {
    final r = await api.creerPoint(libelle: libelle, type: type);
    return (r as PointEnregistre).point.id;
  }

  Future<void> article(
    String id, {
    String libelle = 'Riz local (sac 50 kg)',
    String seuil = '5',
    SuiviArticle suivi = SuiviArticle.permanent,
    String? pointId,
    String unite = 'sac',
  }) async {
    final r = await api.enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: 'Denrées',
        uniteMesure: unite,
        seuilAlerte: seuil,
        suivi: suivi,
        pointStockageId: pointId,
      ),
    );
    expect(r, isA<ArticleEnregistre>(), reason: '$r');
  }

  Future<ResultatEcritureMouvement> mouvement(
    String articleId,
    String pointId,
    TypeMouvement type,
    String quantite, {
    String motif = 'Réception',
    String? cout,
    bool force = false,
  }) => api.enregistrerMouvement(
    SaisieMouvement(
      articleId: articleId,
      pointId: pointId,
      type: type,
      quantite: quantite,
      motif: motif,
      coutUnitaire: cout,
      validationRupture: force,
    ),
  );

  Future<int> nombreMouvements() async =>
      (await db.select(db.mouvementsStockLocal).get()).length;

  LigneStock ligne(EtatStock e, String id) =>
      e.lignes.firstWhere((l) => l.id == id);

  Future<EtatStock> etat({String? pointId, EtatStockFiltre? filtre}) async =>
      ((await api.etat(pointId: pointId, etat: filtre)) as StockRecu).etat;

  group('Les points de stockage', () {
    test(
      'un point se crée, avec son type, et se relit trié par libellé',
      () async {
        await point('Magasin général', type: TypePoint.magasin);
        await point('Bar', type: TypePoint.bar);
        await point('Local sans type');

        final points = await api.points();
        expect(points.map((p) => p.libelle).toList(), [
          'Bar',
          'Local sans type',
          'Magasin général',
        ]);
        expect(points.map((p) => p.type).toList(), ['bar', null, 'magasin']);
      },
    );

    test(
      'un libellé vide ou un homonyme est refusé, sans rien écrire',
      () async {
        await point('Bar');

        final vide = await api.creerPoint(libelle: '   ');
        expect((vide as PointRefuse).motif, contains('obligatoire'));

        // Deux points « Bar » se choisiraient au hasard dans un sélecteur.
        final doublon = await api.creerPoint(libelle: 'bar');
        expect((doublon as PointRefuse).motif, contains('existe déjà'));

        expect(await db.select(db.pointsStockageLocal).get(), hasLength(1));
      },
    );
  });

  group('Le référentiel des articles', () {
    test('un article naît SANS stock : zéro mouvement, stock 0.00', () async {
      final bar = await point('Bar');
      await article('riz', pointId: bar);

      expect(await nombreMouvements(), 0);
      final l = ligne(await etat(), 'riz');
      expect(l.stock, '0.00');
      expect(l.valeurStock, '0');
      expect(l.pointLibelle, 'Bar');
      expect(l.categorie, 'Denrées');
      expect(l.seuilAlerte, '5.00');
    });

    test('un libellé, une unité ou un seuil absents sont refusés, champ par '
        'champ, avec les mots du serveur', () async {
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'x',
          libelle: '  ',
          categorie: null,
          uniteMesure: '',
          seuilAlerte: '',
        ),
      );
      final refus = r as ArticleRefuse;
      expect(refus.erreurs['libelle'], MessagesStock.libelleObligatoire);
      expect(refus.erreurs['unite_mesure'], MessagesStock.uniteObligatoire);
      expect(refus.erreurs['seuil_alerte'], MessagesStock.seuilObligatoire);
      expect(await db.select(db.articlesLocal).get(), isEmpty);
    });

    test('un seuil à trois décimales est refusé, pas tronqué', () async {
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'x',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5,555',
        ),
      );
      expect((r as ArticleRefuse).erreurs, contains('seuil_alerte'));
      expect(await db.select(db.articlesLocal).get(), isEmpty);
    });

    test(
      'un second envoi du même identifiant est refusé : pas de doublon',
      () async {
        await article('riz');
        final r = await api.enregistrerArticle(
          const SaisieArticle(
            id: 'riz',
            libelle: 'Autre',
            categorie: null,
            uniteMesure: 'kg',
            seuilAlerte: '1',
          ),
        );
        expect((r as ArticleRefuse).motif, MessagesStock.identifiantDejaPris);
        expect(await db.select(db.articlesLocal).get(), hasLength(1));
      },
    );

    test('un point de rattachement inconnu est refusé', () async {
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'x',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '1',
          pointStockageId: 'fantome',
        ),
      );
      expect(
        (r as ArticleRefuse).erreurs['point_stockage_id'],
        MessagesStock.pointInexistant,
      );
    });

    test(
      'un article journalier : seuil ramené à zéro, aucune alarme',
      () async {
        await article(
          'tom',
          libelle: 'Tomates',
          suivi: SuiviArticle.journalier,
        );
        final e = await etat();
        final t = ligne(e, 'tom');
        expect(t.seuilAlerte, '0.00', reason: 'même si "5" a été saisi');
        expect(t.estJournalier, isTrue);
        expect(t.enRupture, isFalse);
        expect(e.kpis.sousSeuil, 0);
        expect(e.kpis.rupture, 0);
        expect(e.kpis.journaliers, 1);
      },
    );

    test('la modification change le référentiel, jamais le stock', () async {
      final bar = await point('Bar');
      await article('riz', pointId: bar);
      await mouvement('riz', bar, TypeMouvement.entree, '10', cout: '1000');

      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'riz',
          libelle: 'Riz parfumé',
          categorie: 'Épicerie',
          uniteMesure: 'sac',
          seuilAlerte: '8',
        ),
        modification: true,
      );
      expect(r, isA<ArticleEnregistre>());

      final l = ligne(await etat(), 'riz');
      expect(l.libelle, 'Riz parfumé');
      expect(l.categorie, 'Épicerie');
      expect(l.seuilAlerte, '8.00');
      expect(
        l.pointLibelle,
        isNull,
        reason: 'rattachement retiré par la saisie',
      );
      expect(l.stock, '10.00');
      expect(l.coutMoyenPondere, '1000.0000');
    });

    test(
      'l’unité d’un article qui a des mouvements ne se modifie pas',
      () async {
        final bar = await point('Bar');
        await article('riz');
        await mouvement('riz', bar, TypeMouvement.entree, '10');

        final r = await api.enregistrerArticle(
          const SaisieArticle(
            id: 'riz',
            libelle: 'Riz local (sac 50 kg)',
            categorie: 'Denrées',
            uniteMesure: 'kg',
            seuilAlerte: '5',
          ),
          modification: true,
        );
        final refus = r as ArticleRefuse;
        expect(refus.erreurs['unite_mesure'], contains('1 mouvement(s)'));
        expect(ligne(await etat(), 'riz').uniteMesure, 'sac');
      },
    );

    test('sans mouvement, l’unité se corrige', () async {
      await article('riz');
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'kg',
          seuilAlerte: '5',
        ),
        modification: true,
      );
      expect(r, isA<ArticleEnregistre>());
      expect(ligne(await etat(), 'riz').uniteMesure, 'kg');
    });

    test('modifier un article inconnu est refusé', () async {
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'fantome',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5',
        ),
        modification: true,
      );
      expect(r, isA<ArticleRefuse>());
    });
  });

  group('Le stock d’ouverture entre comme un MOUVEMENT, avec l’article', () {
    test(
      'article, entrée datée et motivée, CMP : une seule opération',
      () async {
        final magasin = await point('Magasin');

        final r = await api.enregistrerArticle(
          SaisieArticle(
            id: 'riz',
            libelle: 'Riz local (sac 50 kg)',
            categorie: 'Denrées',
            uniteMesure: 'sac',
            seuilAlerte: '5',
            pointStockageId: magasin,
            stockOuverture: '10',
            valeurAchat: '1250,50',
          ),
        );
        expect(r, isA<ArticleEnregistre>());

        final ecrits = await db.select(db.mouvementsStockLocal).get();
        expect(ecrits, hasLength(1));
        expect(ecrits.single.typeMouvement, 'entree');
        expect(ecrits.single.quantite, 10.0);
        expect(ecrits.single.motif, MessagesStock.motifOuverture);
        expect(ecrits.single.pointId, magasin);
        expect(ecrits.single.coutUnitaireDixMilliemes, 12505000);
        expect(ecrits.single.utilisateurId, 'u-1');

        final l = ligne(await etat(), 'riz');
        expect(l.stock, '10.00');
        expect(l.coutMoyenPondere, '1250.5000');
        // 10 × 1 250,50 = 12 505 F.
        expect(l.valeurStock, '12505');
        expect(l.pointLibelle, 'Magasin');
      },
    );

    test('sans coût, l’entrée ne valorise rien : la valeur est INCONNUE, '
        'pas nulle', () async {
      final magasin = await point('Magasin');
      await api.enregistrerArticle(
        SaisieArticle(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5',
          pointStockageId: magasin,
          stockOuverture: '10',
        ),
      );

      final e = await etat();
      expect(ligne(e, 'riz').stock, '10.00');
      expect(ligne(e, 'riz').valeurInconnue, isTrue);
      expect(e.kpis.sansValorisation, 1);
      expect(
        (await db.select(db.mouvementsStockLocal).get())
            .single
            .coutUnitaireDixMilliemes,
        isNull,
      );
    });

    test('un stock d’ouverture sans point est refusé et n’EXIGE pas de '
        'rattrapage : l’article n’est pas créé', () async {
      final r = await api.enregistrerArticle(
        const SaisieArticle(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5',
          stockOuverture: '10',
        ),
      );
      expect((r as ArticleRefuse).erreurs, contains('point_stockage_id'));
      // Tout ou rien : un article sans le stock que l'exploitant a saisi serait
      // un stock faux que rien ne signale.
      expect(await db.select(db.articlesLocal).get(), isEmpty);
      expect(await nombreMouvements(), 0);
    });

    test(
      'si l’entrée est refusée, l’article n’est pas créé (transaction)',
      () async {
        final magasin = await point('Magasin');
        auteur = null; // l'entrée exige un « qui » (RG-15)

        final r = await api.enregistrerArticle(
          SaisieArticle(
            id: 'riz',
            libelle: 'Riz',
            categorie: null,
            uniteMesure: 'sac',
            seuilAlerte: '5',
            pointStockageId: magasin,
            stockOuverture: '10',
          ),
        );
        expect(r, isA<ArticleRefuse>());
        expect(await db.select(db.articlesLocal).get(), isEmpty);
        expect(await nombreMouvements(), 0);
      },
    );

    test(
      'zéro, ou un article journalier : aucune entrée n’est écrite',
      () async {
        final magasin = await point('Magasin');
        await api.enregistrerArticle(
          SaisieArticle(
            id: 'a',
            libelle: 'A',
            categorie: null,
            uniteMesure: 'sac',
            seuilAlerte: '5',
            pointStockageId: magasin,
            stockOuverture: '0',
          ),
        );
        await api.enregistrerArticle(
          SaisieArticle(
            id: 'b',
            libelle: 'B',
            categorie: null,
            uniteMesure: 'kg',
            seuilAlerte: '5',
            suivi: SuiviArticle.journalier,
            pointStockageId: magasin,
            stockOuverture: '8',
          ),
        );
        expect(await db.select(db.articlesLocal).get(), hasLength(2));
        expect(await nombreMouvements(), 0);
      },
    );

    test('les formes refusées sont nommées champ par champ', () async {
      final magasin = await point('Magasin');
      final r = await api.enregistrerArticle(
        SaisieArticle(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5',
          pointStockageId: magasin,
          stockOuverture: '1,234',
          valeurAchat: 'abc',
        ),
      );
      final refus = r as ArticleRefuse;
      expect(refus.erreurs, contains('stock_ouverture'));
      expect(await db.select(db.articlesLocal).get(), isEmpty);
    });

    test('à la MODIFICATION, aucune entrée n’est écrite : le stock ne se '
        'corrige que par un mouvement', () async {
      final magasin = await point('Magasin');
      await article('riz');

      final r = await api.enregistrerArticle(
        SaisieArticle(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilAlerte: '5',
          pointStockageId: magasin,
          stockOuverture: '99',
          valeurAchat: '1000',
        ),
        modification: true,
      );
      expect(r, isA<ArticleEnregistre>());
      expect(await nombreMouvements(), 0);
    });
  });

  group('Un mouvement : le stock se constitue, il ne se saisit pas', () {
    test(
      'entrée valorisée, deuxième entrée, sortie : valeurs exactes',
      () async {
        final magasin = await point('Magasin général', type: TypePoint.magasin);
        await article('riz', seuil: '4');

        // 10,00 à 1 000 F.
        var r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.entree,
          '10',
          cout: '1000',
        );
        expect(r, isA<MouvementEnregistre>());
        var l = ligne(await etat(), 'riz');
        expect(l.stock, '10.00');
        expect(l.coutMoyenPondere, '1000.0000');
        expect(l.valeurStock, '10000');

        // + 5,00 à 1 250,50 F : (10 × 1000 + 5 × 1250,50) / 15 = 1 083,50.
        r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.entree,
          '5',
          cout: '1250,50',
        );
        expect(r, isA<MouvementEnregistre>());
        l = ligne(await etat(), 'riz');
        expect(l.stock, '15.00');
        expect(l.coutMoyenPondere, '1083.5000');
        // 15 × 1 083,50 = 16 252,50 -> 16 253 F.
        expect(l.valeurStock, '16253');
        expect(l.prixAchat, '1250.5000', reason: 'le dernier prix, pas le CMP');
        expect(
          l.deriveCmp,
          -13,
          reason: '(1083,5 - 1250,5) / 1250,5 = -13,35 %',
        );

        // - 3,00 : une sortie ne change pas le CMP.
        r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.sortie,
          '3',
          motif: 'Cuisine',
        );
        expect(r, isA<MouvementEnregistre>());
        l = ligne(await etat(), 'riz');
        expect(l.stock, '12.00');
        expect(l.coutMoyenPondere, '1083.5000');
        // 12 × 1 083,50 = 13 002 F.
        expect(l.valeurStock, '13002');
      },
    );

    test(
      'le mouvement rendu porte son auteur, son coût figé et son sens',
      () async {
        final magasin = await point('Magasin général');
        await article('riz');

        final r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.entree,
          '12,5',
          motif: '  Réception SODIS  ',
          cout: '833,3333',
        );
        final m = (r as MouvementEnregistre).mouvement;
        expect(m.quantite, '12.50');
        expect(m.motif, 'Réception SODIS', reason: 'le motif est nettoyé');
        expect(m.utilisateur, 'Aïcha');
        expect(m.coutUnitaire, '833.3333');
        expect(m.sens, 'entree');
        expect(m.estEntrante, isTrue);
        expect(m.ruptureForcee, isFalse);
        expect(m.articleLibelle, 'Riz local (sac 50 kg)');
        expect(m.pointLibelle, 'Magasin général');
      },
    );

    test('la ligne écrite : rang croissant, statut « local », auteur, '
        'JAMAIS le défaut du schéma', () async {
      final magasin = await point('Magasin');
      await article('riz');
      for (final q in ['1', '2', '3']) {
        await mouvement('riz', magasin, TypeMouvement.entree, q);
      }

      final lignes = await (db.select(
        db.mouvementsStockLocal,
      )..orderBy([(m) => OrderingTerm.asc(m.ordre)])).get();
      expect(lignes.map((l) => l.ordre).toList(), [1, 2, 3]);
      for (final l in lignes) {
        // Le défaut du schéma, `en_attente_synchronisation`, décrirait une
        // attente sans fin (PA-134).
        expect(l.statutSync, 'local');
        expect(l.utilisateurId, 'u-1');
        expect(l.ruptureForcee, isFalse);
      }
    });

    test('un transfert (entrée sans coût) ne revalorise rien', () async {
      final magasin = await point('Magasin');
      final bar = await point('Bar');
      await article('riz');
      await mouvement('riz', magasin, TypeMouvement.entree, '10', cout: '1000');
      await mouvement(
        'riz',
        magasin,
        TypeMouvement.sortie,
        '4',
        motif: 'Transfert',
      );
      await mouvement(
        'riz',
        bar,
        TypeMouvement.entree,
        '4',
        motif: 'Transfert',
      );

      final l = ligne(await etat(), 'riz');
      expect(l.stock, '10.00');
      expect(l.coutMoyenPondere, '1000.0000');
      // Au bar : 4,00 ; au magasin : 6,00.
      expect(ligne(await etat(pointId: bar), 'riz').stock, '4.00');
      expect(ligne(await etat(pointId: magasin), 'riz').stock, '6.00');
    });

    test('un article journalier ne reçoit aucun mouvement', () async {
      final magasin = await point('Magasin');
      await article('tom', libelle: 'Tomates', suivi: SuiviArticle.journalier);

      final r = await mouvement('tom', magasin, TypeMouvement.entree, '5');
      expect(
        (r as MouvementRefuse).motif,
        MessagesStock.refusJournalier('Tomates'),
      );
      expect(await nombreMouvements(), 0);
    });

    test('les formes refusées : champ par champ, rien d’écrit', () async {
      final magasin = await point('Magasin');
      await article('riz');

      var r = await mouvement('riz', magasin, TypeMouvement.entree, '0');
      expect((r as MouvementRefuse).erreurs, contains('quantite'));
      r = await mouvement('riz', magasin, TypeMouvement.entree, '1,234');
      expect((r as MouvementRefuse).erreurs, contains('quantite'));
      r = await mouvement('riz', magasin, TypeMouvement.entree, '');
      expect((r as MouvementRefuse).erreurs, contains('quantite'));
      r = await mouvement(
        'riz',
        magasin,
        TypeMouvement.entree,
        '1',
        motif: '   ',
      );
      expect(
        (r as MouvementRefuse).erreurs['motif'],
        MessagesStock.motifObligatoire,
      );
      r = await mouvement(
        'riz',
        magasin,
        TypeMouvement.entree,
        '1',
        cout: '1.23456',
      );
      expect((r as MouvementRefuse).erreurs, contains('cout_unitaire'));

      expect(await nombreMouvements(), 0);
    });

    test(
      'un coût sur une sortie, une validation de rupture sur une entrée, '
      'une régularisation saisie : refusés avec les mots du serveur',
      () async {
        final magasin = await point('Magasin');
        await article('riz');
        await mouvement('riz', magasin, TypeMouvement.entree, '10');

        var r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.sortie,
          '1',
          cout: '100',
        );
        expect((r as MouvementRefuse).motif, MessagesStock.coutReserveEntree);

        r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.entree,
          '1',
          force: true,
        );
        expect((r as MouvementRefuse).motif, MessagesStock.ruptureSurSortie);

        // `inventaire` naît d'un comptage clôturé, jamais d'un formulaire.
        r = await api.enregistrerMouvement(
          SaisieMouvement(
            articleId: 'riz',
            pointId: magasin,
            type: TypeMouvement.inventaire,
            quantite: '3',
            motif: 'Je corrige à la main',
          ),
        );
        expect((r as MouvementRefuse).motif, MessagesStock.typeInconnu);

        expect(await nombreMouvements(), 1, reason: "seule l'entrée du départ");
      },
    );

    test('article ou point inconnu : refus, pas de ligne orpheline', () async {
      final magasin = await point('Magasin');
      await article('riz');

      var r = await mouvement('fantome', magasin, TypeMouvement.entree, '1');
      expect((r as MouvementRefuse).motif, MessagesStock.articleInexistant);
      r = await mouvement('riz', 'fantome', TypeMouvement.entree, '1');
      expect((r as MouvementRefuse).motif, MessagesStock.pointInexistant);
      expect(await nombreMouvements(), 0);
    });

    test(
      'sans auteur, aucun mouvement : un « qui » est obligatoire (RG-15)',
      () async {
        final magasin = await point('Magasin');
        await article('riz');
        auteur = null;

        final r = await mouvement('riz', magasin, TypeMouvement.entree, '1');
        expect((r as MouvementRefuse).motif, contains('auteur'));
        expect(await nombreMouvements(), 0);
      },
    );
  });

  group('RG-06 — la rupture est une question, jamais une erreur sèche', () {
    late String magasin;
    late String bar;

    setUp(() async {
      magasin = await point('Magasin');
      bar = await point('Bar');
      await article('riz');
      await mouvement('riz', magasin, TypeMouvement.entree, '12', cout: '1000');
    });

    test('une sortie au-delà du disponible demande CONFIRMATION et n’écrit '
        'rien', () async {
      final avant = await nombreMouvements();

      final r = await mouvement(
        'riz',
        magasin,
        TypeMouvement.sortie,
        '20',
        motif: 'Banquet',
      );
      final rupture = r as RuptureAConfirmer;
      expect(rupture.stockDisponible, '12.00');
      expect(rupture.quantiteDemandee, '20.00');
      expect(
        rupture.message,
        'Stock insuffisant : 12.00 disponible, 20.00 demandé. '
        'Une validation explicite est requise pour forcer la sortie.',
      );
      expect(await nombreMouvements(), avant);
      expect(ligne(await etat(), 'riz').stock, '12.00');
    });

    test('le disponible est celui du POINT, pas celui de l’article', () async {
      // 12 au magasin, 0 au bar : sortir 1 au bar est une rupture.
      final r = await mouvement('riz', bar, TypeMouvement.sortie, '1');
      final rupture = r as RuptureAConfirmer;
      expect(rupture.stockDisponible, '0.00');
    });

    test('sortir exactement le disponible passe', () async {
      final r = await mouvement('riz', magasin, TypeMouvement.sortie, '12');
      expect(r, isA<MouvementEnregistre>());
      expect(ligne(await etat(), 'riz').stock, '0.00');
    });

    test('une perte est soumise au même contrôle', () async {
      final r = await mouvement(
        'riz',
        magasin,
        TypeMouvement.perte,
        '13',
        motif: 'Casse',
      );
      expect(r, isA<RuptureAConfirmer>());
    });

    test(
      'le forçage écrit le stock NÉGATIF et en laisse la trace nominative',
      () async {
        final r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.sortie,
          '20',
          motif: 'Banquet',
          force: true,
        );
        final m = (r as MouvementEnregistre).mouvement;
        expect(m.ruptureForcee, isTrue);
        expect(m.utilisateur, 'Aïcha');
        expect(m.libelleJournal, 'Sortie — rupture forcée');

        final e = await etat();
        expect(ligne(e, 'riz').stock, '-8.00');
        expect(ligne(e, 'riz').enRupture, isTrue);
        // 12 - 20 = -8,00 × 1 000 F = -8 000 F : le stock négatif se valorise.
        expect(ligne(e, 'riz').valeurStock, '-8000');

        // La trace est en base : qui, quand, et le drapeau.
        final ecrit = await (db.select(
          db.mouvementsStockLocal,
        )..where((l) => l.id.equals(m.id))).getSingle();
        expect(ecrit.ruptureForcee, isTrue);
        expect(ecrit.utilisateurId, 'u-1');
      },
    );

    test(
      'un forçage inutile (le disponible suffit) n’est PAS une rupture',
      () async {
        final r = await mouvement(
          'riz',
          magasin,
          TypeMouvement.sortie,
          '5',
          force: true,
        );
        expect((r as MouvementEnregistre).mouvement.ruptureForcee, isFalse);
      },
    );

    test('deux sorties simultanées de 8 sur 12 : une seule passe', () async {
      // Le contrôle et l'écriture sont dans la MÊME transaction : sans cela,
      // les deux liraient 12 et le stock passerait à -4 sans que personne l'ait
      // décidé.
      final resultats = await Future.wait([
        mouvement('riz', magasin, TypeMouvement.sortie, '8', motif: 'A'),
        mouvement('riz', magasin, TypeMouvement.sortie, '8', motif: 'B'),
      ]);

      expect(resultats.whereType<MouvementEnregistre>(), hasLength(1));
      expect(resultats.whereType<RuptureAConfirmer>(), hasLength(1));
      expect(ligne(await etat(), 'riz').stock, '4.00');

      final rangs = (await db.select(db.mouvementsStockLocal).get())
          .map((m) => m.ordre)
          .toList();
      expect(rangs.toSet(), hasLength(rangs.length), reason: 'rangs distincts');
    });
  });

  group('Le journal et la fiche', () {
    late String magasin;

    setUp(() async {
      magasin = await point('Magasin');
      await article('riz');
      await mouvement('riz', magasin, TypeMouvement.entree, '10', cout: '1000');
      await mouvement(
        'riz',
        magasin,
        TypeMouvement.sortie,
        '3',
        motif: 'Cuisine',
      );
      await mouvement('riz', magasin, TypeMouvement.perte, '1', motif: 'Casse');
    });

    test('du plus récent au plus ancien, avec le total du filtre', () async {
      final r = await api.mouvements(articleId: 'riz', parPage: 2);
      final journal = r as JournalRecu;
      expect(journal.mouvements.map((m) => m.motif).toList(), [
        'Casse',
        'Cuisine',
      ]);
      // La page est tronquée, le total ne l'est pas.
      expect(journal.total, 3);
      expect(journal.mouvements.first.libelleType, 'Perte');
      expect(journal.mouvements.first.sens, 'sortie');
      expect(journal.mouvements.every((m) => m.utilisateur == 'Aïcha'), isTrue);
    });

    test('les filtres d’article, de point et de type', () async {
      await article('sel', libelle: 'Sel');
      await mouvement('sel', magasin, TypeMouvement.entree, '2');

      final parArticle = await api.mouvements(articleId: 'sel');
      expect((parArticle as JournalRecu).total, 1);

      final parType = await api.mouvements(type: TypeMouvement.sortie);
      expect((parType as JournalRecu).total, 1);

      final autre = await point('Bar');
      final parPoint = await api.mouvements(pointId: autre);
      expect((parPoint as JournalRecu).total, 0);
      expect(parPoint.mouvements, isEmpty);
    });

    test(
      'la fiche : initial, flux, théorique, valeur — et le « qui »',
      () async {
        final r = await api.fiche(
          articleId: 'riz',
          debut: DateTime(2026, 10, 9),
          fin: DateTime(2026, 10, 9),
        );
        final f = (r as FicheRecue).fiche;
        expect(f.stockInitial, '0.00');
        expect(f.entrees, '10.00');
        expect(f.sorties, '3.00');
        expect(f.pertes, '1.00');
        expect(f.stockTheorique, '6.00');
        expect(f.valeurStockTheorique, '6000');
        expect(f.coherent, isTrue);
        expect(f.lignes.map((l) => l.solde).toList(), [
          '10.00',
          '7.00',
          '6.00',
        ]);
        expect(f.lignes.every((l) => l.par == 'Aïcha'), isTrue);
      },
    );

    test('une fiche sur un article inconnu ou une période inversée est '
        'REFUSÉE', () async {
      final inconnu = await api.fiche(
        articleId: 'fantome',
        debut: DateTime(2026, 10, 1),
        fin: DateTime(2026, 10, 9),
      );
      expect((inconnu as FicheRefusee).motif, MessagesStock.articleInexistant);

      final inversee = await api.fiche(
        articleId: 'riz',
        debut: DateTime(2026, 10, 9),
        fin: DateTime(2026, 10, 1),
      );
      expect((inversee as FicheRefusee).motif, MessagesStock.periodeInversee);
    });

    test(
      'le sélecteur d’articles de la fiche : suivi permanent, avec le CMP',
      () async {
        await article(
          'tom',
          libelle: 'Tomates',
          suivi: SuiviArticle.journalier,
        );

        final tous = await api.articles();
        expect(tous!.map((a) => a.libelle).toSet(), {
          'Riz local (sac 50 kg)',
          'Tomates',
        });

        final permanents = await api.articles(suivi: StocksApi.suiviPermanent);
        expect(permanents!.map((a) => a.id).toList(), ['riz']);
        expect(permanents.single.cmp, '1000.0000');
      },
    );
  });

  group('Les droits : un bouton masqué ne protège rien', () {
    test(
      'sans droit d’écriture, aucune des trois écritures n’aboutit',
      () async {
        final magasin = await point('Magasin');
        await article('riz');
        peutEcrire = false;

        final p = await api.creerPoint(libelle: 'Autre');
        expect((p as PointRefuse).motif, refusEcritureStocks);

        final a = await api.enregistrerArticle(
          const SaisieArticle(
            id: 'y',
            libelle: 'Y',
            categorie: null,
            uniteMesure: 'kg',
            seuilAlerte: '1',
          ),
        );
        expect((a as ArticleRefuse).motif, refusEcritureStocks);

        final m = await mouvement('riz', magasin, TypeMouvement.entree, '1');
        expect((m as MouvementRefuse).motif, refusEcritureStocks);

        expect(await db.select(db.pointsStockageLocal).get(), hasLength(1));
        expect(await db.select(db.articlesLocal).get(), hasLength(1));
        expect(await nombreMouvements(), 0);
      },
    );

    test(
      'sans droit de lecture, rien ne se consulte et rien ne se suppose',
      () async {
        await article('riz');
        peutLire = false;

        final e = await api.etat();
        expect((e as StockRefuse).motif, refusLectureStocks);
        expect(e.codeHttp, 403);
        // `null` : « on ne sait pas », jamais une liste vide (« aucun article »).
        expect(await api.articles(), isNull);
        expect(await api.points(), isEmpty);
        expect(await api.mouvements(), isA<JournalRefuse>());
        expect(
          await api.fiche(
            articleId: 'riz',
            debut: DateTime(2026, 10, 1),
            fin: DateTime(2026, 10, 9),
          ),
          isA<FicheRefusee>(),
        );
      },
    );
  });

  group('L’état par le chemin de l’écran', () {
    test('un poste neuf : un état VIDE et reçu, pas un refus ni un zéro '
        'inventé', () async {
      final e = await etat();
      expect(e.lignes, isEmpty);
      expect(e.kpis.references, 0);
      expect(e.kpis.valeurStock, '0');
      expect(e.kpis.mouvements30Jours, 0);
      expect(await api.points(), isEmpty);
    });

    test(
      'le filtre « sous seuil » et les compteurs du référentiel entier',
      () async {
        final magasin = await point('Magasin');
        await article('riz', seuil: '5');
        await article('sel', libelle: 'Sel', seuil: '2');
        await mouvement(
          'riz',
          magasin,
          TypeMouvement.entree,
          '10',
          cout: '1000',
        );
        await mouvement('sel', magasin, TypeMouvement.entree, '2', cout: '300');

        final e = await etat(filtre: EtatStockFiltre.sousSeuil);
        // Riz : 10 > 5 (sain, masqué). Sel : 2 <= 2 (sous seuil).
        expect(e.lignes.map((l) => l.id).toList(), ['sel']);
        expect(e.kpis.sousSeuil, 1);
        expect(e.kpis.permanents, 2);
        expect(e.kpis.references, 1);
      },
    );

    test('les mouvements des 30 derniers jours sont comptés', () async {
      final magasin = await point('Magasin');
      await article('riz');
      await mouvement('riz', magasin, TypeMouvement.entree, '10');
      await mouvement('riz', magasin, TypeMouvement.sortie, '1');
      expect((await etat()).kpis.mouvements30Jours, 2);
    });
  });

  group('Aucun écran ne lit le piège du schéma', () {
    test(
      '`statutSync` n’apparaît que dans le DAO, et pour y écrire « local »',
      () {
        final fichiers = Directory('lib/features/stocks')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();
        // Le balayage ne doit pas être vide (piège 4).
        expect(fichiers.length, greaterThan(10));

        final occurrences = <String>[];
        for (final f in fichiers) {
          final texte = f.readAsStringSync();
          // Les COMMENTAIRES peuvent nommer le piège ; le CODE, jamais.
          final code = texte
              .split('\n')
              .where((l) => !l.trimLeft().startsWith('//'))
              .join('\n');
          if (code.contains('statutSync') ||
              code.contains('en_attente_synchronisation')) {
            occurrences.add(f.path.replaceAll(r'\', '/'));
          }
        }
        expect(occurrences, ['lib/features/stocks/data/stocks_dao.dart']);

        // Les commentaires du DAO NOMMENT le piège ; son code ne l'écrit pas.
        final dao = File('lib/features/stocks/data/stocks_dao.dart')
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(dao, contains("statutSync: const Value('local')"));
        expect(dao.contains('en_attente_synchronisation'), isFalse);
      },
    );
  });
}
