import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/dto/catalogue_dto.dart';
import 'package:tatacora_flutter/features/pos/data/historique_prix_carte_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/changement_prix_carte.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// L'historique des prix de la carte, côté poste — 26/10/2026 (« le poste fait ce
/// que le web fait »). Le poste TRACE ce qu'il change, REÇOIT les traces des
/// autres postes et de la PWA, ne POUSSE jamais la trace (le serveur en est
/// l'unique auteur), et ne l'affiche qu'une fois quand les deux se rejoignent.
void main() {
  late BancSync b;
  late HistoriquePrixCarteDao dao;
  var tic = 0;
  DateTime horloge() => DateTime(2026, 10, 26, 9, 0, tic++);

  setUp(() async {
    tic = 0;
    b = await BancSync.creer();
    await b.semerAuteur();
    dao = HistoriquePrixCarteDao(b.db, horloge: horloge);
  });
  tearDown(() => b.fermer());

  Future<void> tracerDansTransaction(
    String id,
    int avant,
    int apres, {
    SourceCarte source = SourceCarte.boisson,
  }) => b.db.transaction(
    () => dao.tracer(
      source: source,
      sourceId: id,
      changements: changementsDePrix(prixAvant: avant, prixApres: apres),
    ),
  );

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  Map<String, Object?> trace(
    String id, {
    String source = 'carte_boisson',
    String sourceId = 'b-1',
    String champ = 'prix_vente',
    String? ancien = '1000.00',
    String? nouveau = '1200.00',
    String? par = 'gerant',
    String date = '2026-10-26 10:15:00',
  }) => element('historique_prix_carte', id, {
    'source': source,
    'source_id': sourceId,
    'champ': champ,
    'ancien_prix': ancien,
    'nouveau_prix': nouveau,
    'par': par,
    'created_at': date,
  });

  Future<List<TracePrixLigne>> lignes() async => (b.db.select(
    b.db.historiquePrixCarteLocal,
  )..orderBy([(t) => OrderingTerm.asc(t.creeLe)])).get();

  group('Écrire — la trace du poste', () {
    test('elle DOIT être écrite dans la transaction du changement de prix', () {
      expect(
        () => dao.tracer(
          source: SourceCarte.plat,
          sourceId: 'p-1',
          changements: changementsDePrix(prixAvant: 1, prixApres: 2),
        ),
        throwsStateError,
        reason: 'hors transaction : un prix sans trace, ou une trace sans prix',
      );
    });

    test('rien à tracer : aucune ligne', () async {
      await b.db.transaction(
        () => dao.tracer(
          source: SourceCarte.plat,
          sourceId: 'p-1',
          changements: changementsDePrix(prixAvant: 500, prixApres: 500),
        ),
      );
      expect(await lignes(), isEmpty);
    });

    test('une transaction annulée n’en laisse aucune', () async {
      await expectLater(
        b.db.transaction(() async {
          await dao.tracer(
            source: SourceCarte.plat,
            sourceId: 'p-1',
            changements: changementsDePrix(prixAvant: 500, prixApres: 600),
          );
          throw StateError('échec après la trace');
        }),
        throwsStateError,
      );
      expect(await lignes(), isEmpty);
    });

    test('l’auteur est le compte connecté à l’instant de l’écriture', () async {
      b.db.auteurEcriture = () => (login: 'awa', poste: 'CAISSE-2');
      await tracerDansTransaction('b-1', 1000, 1200);
      b.db.auteurEcriture = () => (login: null, poste: null);
      await tracerDansTransaction('b-1', 1200, 1300);

      expect((await lignes()).map((l) => l.par), ['awa', null]);
    });

    test('la trace du poste n’est JAMAIS enfilée : le serveur en est le seul '
        'auteur', () async {
      await tracerDansTransaction('b-1', 1000, 1200);
      expect(await b.total(), 0);
    });

    test('lecture : du plus récent au plus ancien, propre à l’article et à '
        'son rayon', () async {
      await tracerDansTransaction('b-1', 1000, 1200);
      await tracerDansTransaction('b-1', 1200, 1500);
      await tracerDansTransaction('b-2', 300, 400);
      await tracerDansTransaction('b-1', 900, 950, source: SourceCarte.plat);

      final traces = await dao.deLArticle(SourceCarte.boisson, 'b-1');
      expect(traces.map((t) => t.nouveau), ['1500.00', '1200.00']);
      expect(traces.map((t) => t.champ), ['prix_vente', 'prix_vente']);
      expect(await dao.deLArticle(SourceCarte.plat, 'b-1'), hasLength(1));
      expect(await dao.deLArticle(SourceCarte.boisson, 'inconnu'), isEmpty);
    });
  });

  group('Recevoir — la descente', () {
    test('la trace d’un autre poste descend avec son auteur et sa date, sans '
        'rien renvoyer', () async {
      final bilan = await descendre([trace('srv-1')]);

      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
      final l = (await lignes()).single;
      expect(l.id, 'srv-1');
      expect(
        (l.source, l.sourceId, l.champ),
        ('carte_boisson', 'b-1', 'prix_vente'),
      );
      expect((l.ancienPrix, l.nouveauPrix), ('1000.00', '1200.00'));
      expect(l.par, 'gerant');
      expect(l.creeLe, DateTime(2026, 10, 26, 10, 15));
      expect(l.recuDuServeur, isTrue);
      expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
    });

    test('sans clé étrangère : la trace descend AVANT l’article, et sans '
        'auteur elle garde « — »', () async {
      final bilan = await descendre([
        trace('srv-1', sourceId: 'article-pas-encore-recu', par: null),
      ]);

      expect(bilan.refuses, 0);
      expect(bilan.enAttenteDeDependance, 0);
      expect((await lignes()).single.par, isNull);
    });

    test('la trace du marqueur « corrigé à la main » descend aussi', () async {
      await descendre([
        trace(
          'srv-1',
          source: 'plat',
          sourceId: 'p-1',
          champ: 'prix_corrige_main',
          ancien: '0.00',
          nouveau: '1.00',
        ),
      ]);

      final t = (await dao.deLArticle(SourceCarte.plat, 'p-1')).single;
      expect(
        (t.champ, t.ancien, t.nouveau),
        ('prix_corrige_main', '0.00', '1.00'),
      );
    });

    test('rejouer la même descente ne double rien', () async {
      await descendre([trace('srv-1')]);
      await descendre([trace('srv-1')]);
      expect(await lignes(), hasLength(1));
    });

    test('un élément illisible est REFUSÉ et compté, jamais avalé', () async {
      for (final mauvais in [
        trace('x1', source: 'menu'),
        trace('x2', champ: 'prix_achat'),
        trace('x3', nouveau: 'mille deux cents'),
        trace('x4', date: 'hier'),
      ]) {
        final bilan = await descendre([mauvais]);
        expect(bilan.refuses, 1, reason: '${mauvais['id']}');
      }
      expect(await lignes(), isEmpty);
    });
  });

  group('Une seule ligne quand le poste et le serveur se rejoignent', () {
    test('la trace du poste est ADOPTÉE à celle du serveur : date et auteur '
        'du serveur, une ligne, correspondance retenue', () async {
      b.db.auteurEcriture = () => (login: 'caissier', poste: 'CAISSE-1');
      await tracerDansTransaction('b-1', 1000, 1200);
      final locale = (await lignes()).single;
      expect(locale.recuDuServeur, isFalse);

      await descendre([
        trace('srv-9', par: 'caissier', date: '2026-10-26 11:00:00'),
      ]);

      final apres = await lignes();
      expect(
        apres,
        hasLength(1),
        reason: 'jamais deux fois le même changement',
      );
      expect(apres.single.id, locale.id, reason: 'la ligne locale est gardée');
      expect(apres.single.recuDuServeur, isTrue);
      expect(apres.single.creeLe, DateTime(2026, 10, 26, 11));
      expect(
        await DescenteCatalogueDao(
          b.db,
        ).idLocal('historique_prix_carte', 'srv-9'),
        locale.id,
      );

      // Le rejeu retombe sur la même ligne.
      await descendre([trace('srv-9', par: 'caissier')]);
      expect(await lignes(), hasLength(1));
    });

    test(
      'deux changements IDENTIQUES successifs s’adoptent dans l’ordre où ils '
      'ont été faits',
      () async {
        await tracerDansTransaction('b-1', 1000, 1200);
        await tracerDansTransaction('b-1', 1000, 1200);
        final locales = await lignes();

        await descendre([
          trace('srv-1', date: '2026-10-26 11:00:00'),
          trace('srv-2', date: '2026-10-26 11:05:00'),
        ]);

        final apres = await lignes();
        expect(apres, hasLength(2));
        expect(apres.map((l) => l.id), locales.map((l) => l.id));
        expect(apres.map((l) => l.creeLe), [
          DateTime(2026, 10, 26, 11),
          DateTime(2026, 10, 26, 11, 5),
        ]);
      },
    );

    test(
      'une trace du serveur qui ne correspond à rien du poste s’AJOUTE',
      () async {
        await tracerDansTransaction('b-1', 1000, 1200);

        await descendre([
          trace('srv-1', ancien: '1200.00', nouveau: '1500.00'),
        ]);

        expect(await lignes(), hasLength(2));
      },
    );

    test(
      'une trace déjà confirmée n’est pas adoptée une seconde fois',
      () async {
        await tracerDansTransaction('b-1', 1000, 1200);
        // La date du serveur est ANTÉRIEURE à celle du second changement : sans
        // le filtre « pas encore confirmée », c'est la ligne déjà confirmée (la
        // plus ancienne) que la seconde trace du serveur adopterait à tort.
        await descendre([trace('srv-1', date: '2026-10-26 08:00:00')]);
        // Un second changement identique, fait ensuite sur le poste.
        await tracerDansTransaction('b-1', 1000, 1200);

        await descendre([
          trace('srv-1', date: '2026-10-26 08:00:00'),
          trace('srv-2'),
        ]);

        expect(await lignes(), hasLength(2));
        expect((await lignes()).every((l) => l.recuDuServeur), isTrue);
      },
    );
  });

  group('La chaîne : le prix change sur le poste, le serveur le rapporte', () {
    test('modifier le prix d’une boisson trace, ENFILE la boisson (et elle '
        'seule), puis la descente adopte', () async {
      final catalogue = CatalogueDao(b.db);
      await catalogue.enregistrerBoisson(
        const BoissonDistante(
          id: 'b-1',
          articleId: null,
          libelle: 'Béninoise',
          categorie: 'locale',
          prixVente: 500,
          stockDisponible: null,
        ),
      );
      await catalogue.enregistrerBoisson(
        const BoissonDistante(
          id: 'b-1',
          articleId: null,
          libelle: 'Béninoise',
          categorie: 'locale',
          prixVente: 650,
          stockDisponible: null,
        ),
      );

      final operations = await b.dao.operations();
      expect(operations.map((o) => (o.table.nomServeur, o.type)), [
        ('cartes_boisson', TypeOperationSync.creation),
        ('cartes_boisson', TypeOperationSync.modification),
      ], reason: 'aucune opération pour la trace elle-même');

      await descendre([trace('srv-1', ancien: '500.00', nouveau: '650.00')]);
      final l = (await lignes()).single;
      expect(
        (l.ancienPrix, l.nouveauPrix, l.recuDuServeur),
        ('500.00', '650.00', true),
      );
    });
  });
}
