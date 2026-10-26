import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_inventaire.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart'
    show SuiviArticle;
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// L'INVENTAIRE physique (EF-M6-05) par le chemin que l'écran emprunte :
/// `StocksApi` -> `StocksDao` -> la base et la file d'envoi. Aucun faux : un
/// test qui simulerait le DAO ne dirait rien de ce que la base reçoit
/// réellement (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late StocksApi api;
  late StocksDao dao;
  var peutEcrire = true;
  String? auteur = 'u-1';
  late DateTime horloge;

  setUp(() async {
    db = AppDatabase.enMemoire();
    peutEcrire = true;
    auteur = 'u-1';
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

    dao = StocksDao(
      db,
      maintenant: () => horloge = horloge.add(const Duration(minutes: 1)),
    );
    api = StocksApi(
      dao: dao,
      peutLire: () => true,
      peutEcrire: () => peutEcrire,
      auteurId: () => auteur,
    );
  });

  tearDown(() => db.close());

  Future<String> point(String libelle) async =>
      ((await api.creerPoint(libelle: libelle)) as PointEnregistre).point.id;

  Future<void> article(
    String id,
    String libelle, {
    SuiviArticle suivi = SuiviArticle.permanent,
  }) async {
    final r = await api.enregistrerArticle(
      SaisieArticle(
        id: id,
        libelle: libelle,
        categorie: 'Denrées',
        uniteMesure: 'sac',
        seuilAlerte: '5',
        suivi: suivi,
      ),
    );
    expect(r, isA<ArticleEnregistre>(), reason: '$r');
  }

  Future<void> mouvement(
    String articleId,
    String pointId,
    TypeMouvement type,
    String quantite, {
    String? cout,
    bool force = false,
  }) async {
    final r = await api.enregistrerMouvement(
      SaisieMouvement(
        articleId: articleId,
        pointId: pointId,
        type: type,
        quantite: quantite,
        motif: 'Mouvement d’essai',
        coutUnitaire: cout,
        validationRupture: force,
      ),
    );
    expect(r, isA<MouvementEnregistre>(), reason: '$r');
  }

  /// Le jeu de départ de la plupart des cas : un magasin, du riz (10 sacs à
  /// 1 250 FCFA) et de l'huile (4 bidons SANS coût).
  Future<({String magasin})> jeu() async {
    final magasin = await point('Magasin');
    await article('riz', 'Riz local');
    await article('huile', 'Huile 20 L');
    await mouvement('riz', magasin, TypeMouvement.entree, '10', cout: '1250');
    await mouvement('huile', magasin, TypeMouvement.entree, '4');
    return (magasin: magasin);
  }

  ComptageBrouillon compte(int theorique, int constate) => ComptageBrouillon(
    theoriqueCentiemes: theorique,
    constateCentiemes: constate,
  );

  Future<List<OperationSync>> file() => OperationsSyncDao(db).operations();

  Future<int> nb(TableInfo<Table, Object?> t) async =>
      (await db
              .customSelect('SELECT COUNT(*) AS n FROM ${t.actualTableName}')
              .getSingle())
          .read<int>('n');

  group(
    'La clôture écrit l’inventaire, ses lignes et la régularisation ENSEMBLE',
    () {
      test('excédent en `inventaire` non valorisée, manquant en `perte` : '
          'lignes, mouvements, motif, stock, bilan', () async {
        final j = await jeu();
        final avant = (await dao.mouvementsCalcul()).length;

        final bilan = await dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {
            'riz': compte(1000, 1200), // +2 (excédent)
            'huile': compte(400, 300), // -1 (manquant, sans coût)
          },
          auteurId: 'u-1',
        );

        // L'en-tête et ses lignes, en CENTIÈMES.
        final inventaire = await db.select(db.inventairesLocal).getSingle();
        expect(inventaire.id, bilan.inventaireId);
        expect(inventaire.pointId, j.magasin);
        expect(inventaire.dateInventaire, '2026-10-21');
        expect(inventaire.utilisateurId, 'u-1');

        final lignes = {
          for (final l in await db.select(db.lignesInventaireLocal).get())
            l.articleId: l,
        };
        expect(lignes.keys, {'riz', 'huile'});
        expect(
          (
            lignes['riz']!.quantiteTheoriqueCentiemes,
            lignes['riz']!.quantiteConstateeCentiemes,
            lignes['riz']!.ecartCentiemes,
          ),
          (1000, 1200, 200),
        );
        expect(lignes['huile']!.ecartCentiemes, -100);
        expect(
          lignes.values.every((l) => l.inventaireId == inventaire.id),
          isTrue,
        );

        // Les DEUX mouvements de régularisation : le type, la quantité POSITIVE,
        // le motif du serveur (l'écart signé à deux décimales), l'auteur.
        final tous = await dao.mouvementsCalcul();
        final nouveaux = tous.skip(avant).toList();
        expect(nouveaux, hasLength(2));
        final parArticle = {for (final m in nouveaux) m.articleId: m};
        expect(parArticle['riz']!.type, TypeMouvement.inventaire);
        expect(parArticle['riz']!.centiemes, 200);
        expect(parArticle['riz']!.coutDixMilliemes, isNull);
        expect(
          parArticle['riz']!.motif,
          MessagesStock.motifRegularisation(
            inventaire: inventaire.id,
            ecart: '2.00',
          ),
        );
        expect(parArticle['huile']!.type, TypeMouvement.perte);
        expect(parArticle['huile']!.centiemes, 100);
        expect(
          parArticle['huile']!.motif,
          'Régularisation inventaire ${inventaire.id} — écart de -1.00',
        );
        expect(parArticle.values.every((m) => m.auteur == 'Aïcha'), isTrue);

        // Le stock suit le constaté, et le coût moyen n'a pas bougé : un
        // excédent n'achète rien.
        expect(stockDe(tous.where((m) => m.articleId == 'riz')), 1200);
        expect(stockDe(tous.where((m) => m.articleId == 'huile')), 300);
        expect(
          coutMoyenPondereDe(tous.where((m) => m.articleId == 'riz')),
          12500000,
        );

        // Le bilan : 2 régularisations ; l'excédent de riz vaut 2 × 1 250 ; le
        // manquant d'huile n'a AUCUN coût connu — non valorisé, compté à part.
        expect(bilan.regularisations, 2);
        expect(bilan.excedentsFrancs, 2500);
        expect(bilan.manquantsFrancs, 0);
        expect(bilan.ecartsSansCout, 1);
        expect(bilan.ecartValoriseFrancs, 2500);
      });

      test('la file porte l’inventaire d’abord, ses deux mouvements ensuite, '
          'au contrat du serveur (centièmes)', () async {
        final j = await jeu();
        final avant = (await file()).length;

        final bilan = await dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1200), 'huile': compte(400, 300)},
          auteurId: 'u-1',
        );

        final nouvelles = (await file()).skip(avant).toList();
        expect(nouvelles.map((o) => '${o.type.code} ${o.table.nomServeur}'), [
          'creation inventaires',
          'creation mouvements_stock',
          'creation mouvements_stock',
        ]);
        expect(nouvelles.map((o) => o.statut).toSet(), {
          StatutOperationSync.enAttente,
        });

        final charge = jsonDecode(nouvelles[0].payload) as Map<String, dynamic>;
        expect(nouvelles[0].entiteId, bilan.inventaireId);
        expect(charge['point_id'], j.magasin);
        expect(charge['date_inventaire'], '2026-10-21');
        final lignes = (charge['lignes'] as List).cast<Map<String, dynamic>>();
        expect(lignes, hasLength(2));
        final riz = lignes.firstWhere((l) => l['article_id'] == 'riz');
        expect(
          (riz['quantite_theorique'], riz['quantite_constatee'], riz['ecart']),
          (1000, 1200, 200),
        );
        expect(riz['id'], isNotEmpty);

        final types = [
          for (final o in nouvelles.skip(1))
            (jsonDecode(o.payload) as Map<String, dynamic>)['type_mouvement'],
        ];
        expect(types..sort(), ['inventaire', 'perte']);
        final entree = nouvelles
            .skip(1)
            .map((o) => jsonDecode(o.payload) as Map<String, dynamic>)
            .firstWhere((p) => p['type_mouvement'] == 'inventaire');
        expect(entree['quantite'], 200);
        expect(entree['cout_unitaire'], isNull);
        expect(entree['rupture_forcee'], isFalse);
      });

      test('une ligne SANS écart est écrite mais ne régularise rien', () async {
        final j = await jeu();
        final avant = (await dao.mouvementsCalcul()).length;
        final operations = (await file()).length;

        final bilan = await dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1000)},
          auteurId: 'u-1',
          partielAutorise: true,
        );

        expect(bilan.regularisations, 0);
        expect(await nb(db.lignesInventaireLocal), 1);
        expect((await dao.mouvementsCalcul()).length, avant);
        // L'inventaire seul part : aucun mouvement.
        expect((await file()).length, operations + 1);
      });

      test('un manquant plus grand que le disponible d’aujourd’hui est écrit '
          'quand même, et tracé comme forcé', () async {
        final j = await jeu();
        // Le comptage figeait 10 ; depuis, 8 sacs sont partis (disponible = 2).
        await mouvement('riz', j.magasin, TypeMouvement.sortie, '8');

        await dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 500)}, // -5 > 2 disponibles
          auteurId: 'u-1',
          partielAutorise: true,
        );

        final perte = (await dao.mouvementsCalcul()).last;
        expect((perte.type, perte.centiemes), (TypeMouvement.perte, 500));
        expect(perte.ruptureForcee, isTrue);
        // Un inventaire constate le réel : le stock passe à -3.
        expect(
          stockDe(
            (await dao.mouvementsCalcul()).where((m) => m.articleId == 'riz'),
          ),
          -300,
        );
      });
    },
  );

  group('Un refus n’écrit RIEN', () {
    test('un inventaire incomplet est refusé sans clôture partielle '
        'explicite — avec la phrase du serveur', () async {
      final j = await jeu();
      final operations = (await file()).length;

      await expectLater(
        dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1200)},
          auteurId: 'u-1',
        ),
        throwsA(
          isA<RefusStock>().having(
            (e) => e.motif,
            'motif',
            MessagesStock.inventaireIncomplet(1),
          ),
        ),
      );
      expect(await nb(db.inventairesLocal), 0);
      expect(await nb(db.lignesInventaireLocal), 0);
      expect((await file()).length, operations);
    });

    test('un article inconnu emporte TOUT : ni inventaire, ni ligne, ni '
        'mouvement, ni opération', () async {
      final j = await jeu();
      final operations = (await file()).length;
      final mouvements = (await dao.mouvementsCalcul()).length;

      await expectLater(
        dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1200), 'fantome': compte(0, 1)},
          auteurId: 'u-1',
          partielAutorise: true,
        ),
        throwsA(isA<RefusStock>()),
      );
      expect(await nb(db.inventairesLocal), 0);
      expect(await nb(db.lignesInventaireLocal), 0);
      expect((await dao.mouvementsCalcul()).length, mouvements);
      expect((await file()).length, operations);
    });

    test('une panne EN COURS de clôture (le troisième geste échoue) annule les '
        'deux premiers : une seule transaction', () async {
      final j = await jeu();
      final operations = (await file()).length;
      final mouvements = (await dao.mouvementsCalcul()).length;

      // La base refuse l'écriture d'un mouvement `inventaire` : le manquant
      // d'huile (premier par libellé) est déjà écrit quand l'excédent de riz
      // échoue — inventaire, lignes, perte et opérations compris.
      await db.customStatement(
        'CREATE TRIGGER panne BEFORE INSERT ON mouvements_stock_local '
        "WHEN NEW.type_mouvement = 'inventaire' "
        "BEGIN SELECT RAISE(ABORT, 'panne d''essai'); END",
      );

      await expectLater(
        dao.cloturerInventaire(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1200), 'huile': compte(400, 300)},
          auteurId: 'u-1',
        ),
        throwsA(anything),
      );

      expect(await nb(db.inventairesLocal), 0);
      expect(await nb(db.lignesInventaireLocal), 0);
      expect((await dao.mouvementsCalcul()).length, mouvements);
      expect((await file()).length, operations);
    });

    test(
      'un point inconnu, un constaté négatif et l’absence d’auteur',
      () async {
        final j = await jeu();

        await expectLater(
          dao.cloturerInventaire(
            pointId: 'nulle-part',
            date: DateTime(2026, 10, 21),
            comptages: {'riz': compte(1000, 1000)},
            auteurId: 'u-1',
            partielAutorise: true,
          ),
          throwsA(
            isA<RefusStock>().having(
              (e) => e.motif,
              'motif',
              MessagesStock.pointInexistant,
            ),
          ),
        );
        await expectLater(
          dao.cloturerInventaire(
            pointId: j.magasin,
            date: DateTime(2026, 10, 21),
            comptages: {'riz': compte(1000, -100)},
            auteurId: 'u-1',
            partielAutorise: true,
          ),
          throwsA(
            isA<RefusStock>().having(
              (e) => e.motif,
              'motif',
              MessagesStock.quantiteNegative,
            ),
          ),
        );
        await expectLater(
          dao.cloturerInventaire(
            pointId: j.magasin,
            date: DateTime(2026, 10, 21),
            comptages: {'riz': compte(1000, 1000)},
            auteurId: null,
            partielAutorise: true,
          ),
          throwsA(isA<RefusStock>()),
        );
        expect(await nb(db.inventairesLocal), 0);
      },
    );

    test('sans le droit d’écrire sur M6, ni ouverture ni clôture', () async {
      final j = await jeu();
      peutEcrire = false;

      final ouverture = await api.lancerInventaire(j.magasin);
      expect(ouverture, isA<StocksRefuse<dynamic>>());
      final cloture = await api.cloturerInventaire(
        InventaireEnCours(
          pointId: j.magasin,
          date: DateTime(2026, 10, 21),
          comptages: {'riz': compte(1000, 1200)},
        ),
      );
      expect(cloture, isA<StocksRefuse<dynamic>>());
      expect(await nb(db.inventairesLocal), 0);
    });
  });

  group('Ouvrir et compter', () {
    test('ouvrir porte sur un point connu, et dit combien d’articles sont à '
        'compter — tout le référentiel, comme le serveur', () async {
      final j = await jeu();
      await article('pain', 'Pain', suivi: SuiviArticle.journalier);

      final r = await api.lancerInventaire(
        j.magasin,
        aujourdhui: DateTime(2026, 10, 21, 17, 30),
      );
      final ouvert =
          (r as StocksOk<({InventaireEnCours inventaire, int aCompter})>)
              .valeur;
      expect(ouvert.aCompter, 3);
      // Le jour, sans l'heure.
      expect(ouvert.inventaire.date, DateTime(2026, 10, 21));
      expect(ouvert.inventaire.comptages, isEmpty);
      // Ouvrir n'écrit RIEN : le comptage vit en mémoire jusqu'à la clôture.
      expect(await nb(db.inventairesLocal), 0);

      final inconnu = await api.lancerInventaire('nulle-part');
      expect(
        (inconnu as StocksRefuse<dynamic>).motif,
        MessagesStock.aucunPointDefini,
      );
    });

    test('compter FIGE le théorique AU POINT, refuse un négatif et une '
        'saisie illisible, accepte zéro', () async {
      final j = await jeu();
      final autre = await point('Bar');
      await mouvement('riz', autre, TypeMouvement.entree, '3');

      final r = await api.compter(
        pointId: j.magasin,
        articleId: 'riz',
        quantite: '12,5',
      );
      final c = (r as StocksOk<ComptageBrouillon>).valeur;
      // 10 au magasin : les 3 du bar ne sont pas son théorique.
      expect((c.theoriqueCentiemes, c.constateCentiemes), (1000, 1250));
      expect(c.ecartCentiemes, 250);

      final zero = await api.compter(
        pointId: j.magasin,
        articleId: 'riz',
        quantite: '0',
      );
      expect(
        (zero as StocksOk<ComptageBrouillon>).valeur.ecartCentiemes,
        -1000,
      );

      for (final (saisie, attendu) in [
        ('-3', MessagesStock.quantiteNegative),
        ('', MessagesStock.quantitePositive),
        ('1,234', 'Nombre attendu, au plus deux décimales (ex. 12 ou 12,5).'),
      ]) {
        final refus = await api.compter(
          pointId: j.magasin,
          articleId: 'riz',
          quantite: saisie,
        );
        expect((refus as StocksRefuse<dynamic>).motif, attendu, reason: saisie);
      }

      final inconnu = await api.compter(
        pointId: j.magasin,
        articleId: 'fantome',
        quantite: '1',
      );
      expect(
        (inconnu as StocksRefuse<dynamic>).motif,
        MessagesStock.articleInexistant,
      );
    });
  });

  group('La feuille de comptage (fonction pure)', () {
    test('un article non compté a un constaté `null` — jamais zéro — et le '
        'théorique du point ; un compté garde le théorique FIGÉ', () async {
      final j = await jeu();
      final feuille = await dao.feuilleDeComptage(
        pointId: j.magasin,
        comptages: {'riz': compte(900, 1000)},
      );

      final huile = feuille.lignes.firstWhere((l) => l.articleId == 'huile');
      expect(huile.constateCentiemes, isNull);
      expect(huile.ecartCentiemes, isNull);
      expect(huile.valoriseFrancs, isNull);
      expect(huile.compte, isFalse);
      expect(huile.theoriqueCentiemes, 400);

      // Le riz porte le théorique figé AU COMPTAGE (900), pas celui d'aujourd'hui.
      final riz = feuille.lignes.firstWhere((l) => l.articleId == 'riz');
      expect(riz.theoriqueCentiemes, 900);
      expect(riz.ecartCentiemes, 100);
      expect(riz.valoriseFrancs, 1250);

      expect((feuille.total, feuille.comptes, feuille.nonComptes), (2, 1, 1));
      expect((feuille.ecarts, feuille.impactFrancs), (1, 1250));
      // Trié par libellé : « Huile 20 L » avant « Riz local ».
      expect(feuille.lignes.map((l) => l.articleId), ['huile', 'riz']);
    });

    test('un écart sans coût connu n’est PAS valorisé (« — »), un écart nul '
        'vaut zéro', () async {
      final j = await jeu();
      final feuille = await dao.feuilleDeComptage(
        pointId: j.magasin,
        comptages: {'huile': compte(400, 300), 'riz': compte(1000, 1000)},
      );

      final huile = feuille.lignes.firstWhere((l) => l.articleId == 'huile');
      expect(huile.valoriseFrancs, isNull);
      expect(huile.sansCout, isTrue);
      final riz = feuille.lignes.firstWhere((l) => l.articleId == 'riz');
      expect(riz.valoriseFrancs, 0);
      expect(riz.sansCout, isFalse);
      expect(feuille.ecartsSansCout, 1);
      expect(feuille.impactFrancs, 0);
    });

    test(
      'la valeur d’un manquant est NÉGATIVE, au coût moyen pondéré',
      () async {
        final j = await jeu();
        final feuille = await dao.feuilleDeComptage(
          pointId: j.magasin,
          comptages: {'riz': compte(1000, 800)},
        );
        expect(
          feuille.lignes.firstWhere((l) => l.articleId == 'riz').valoriseFrancs,
          -2500,
        );
        expect(feuille.impactFrancs, -2500);
      },
    );
  });

  group('L’historique', () {
    test('liste les inventaires clôturés, du plus récent au plus ancien : '
        'articles, régularisés, auteur ; le dernier de chaque point', () async {
      final j = await jeu();
      final bar = await point('Bar');

      await dao.cloturerInventaire(
        pointId: j.magasin,
        date: DateTime(2026, 10, 19),
        comptages: {'riz': compte(1000, 1000), 'huile': compte(400, 300)},
        auteurId: 'u-1',
      );
      await dao.cloturerInventaire(
        pointId: j.magasin,
        date: DateTime(2026, 10, 21),
        comptages: {'riz': compte(1000, 1200)},
        auteurId: 'u-1',
        partielAutorise: true,
      );

      final liste = await dao.inventairesClos();
      expect(liste.map((i) => i.date), ['2026-10-21', '2026-10-19']);
      expect(
        liste.map((i) => (i.articles, i.regularises, i.par, i.pointLibelle)),
        [(1, 1, 'magasinier', 'Magasin'), (2, 1, 'magasinier', 'Magasin')],
      );

      final derniers = await dao.dernierInventaireParPoint();
      expect(derniers[j.magasin], '2026-10-21');
      // Un point sans inventaire n'a PAS de date.
      expect(derniers.containsKey(bar), isFalse);
    });
  });
}
