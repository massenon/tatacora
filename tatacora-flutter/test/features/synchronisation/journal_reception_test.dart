import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/journal_reception_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/journal_reception.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';

import 'support/faux_transport.dart';

/// Le JOURNAL DE RÉCEPTION (schéma v37) : chaque élément descendu y reçoit
/// son issue et sa CAUSE, les relances le mettent à jour, la rétention le
/// borne — et seule la descente l'écrit.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  JournalReceptionDao journal() =>
      JournalReceptionDao(b.db, maintenant: () => b.maintenant);

  FauxTransport transportDe(FauxCatalogue cat) => FauxTransport(
    (r) => r.methode == 'GET' ? cat.repondre(r) : reponseLot(r),
  );

  Future<DescenteCatalogue> descendre(
    FauxCatalogue cat, {
    String? auteur = 'u-admin',
  }) async {
    // Le faux serveur repart de zéro : le curseur d'avant n'a plus de sens.
    await DescenteCatalogueDao(b.db).effacerCurseur();
    final d = b.descente(transportDe(cat), auteur: auteur);
    await d.descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    return d;
  }

  Future<EntreeJournalReception> entree(String table, String id) async {
    final e = await journal().lire(table, id);
    expect(e, isNotNull, reason: 'le journal ne tient pas $table/$id');
    return e!;
  }

  group('chaque issue est consignée avec sa cause', () {
    test('alignée : l’élément, son nom lisible, aucune cause', () async {
      await descendre(
        FauxCatalogue([
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
          }),
        ]),
      );
      final riz = await entree('articles', 'art-1');
      expect(riz.issue, IssueReception.aligne);
      expect(riz.cause, CauseReception.aucune);
      expect(riz.etiquette, 'Riz');
      expect(riz.tentatives, 1);
      expect(riz.motif, '');
      expect(await journal().lire('articles', 'art-1'), isNotNull);
      final c = await journal().compter();
      expect((c.recus, c.aligne, c.aTraiter), (2, 2, 0));
      expect(
        (await b.db.select(b.db.journalReceptionLocal).get()).every(
          (l) => l.elementJson == null,
        ),
        isTrue,
        reason: 'un élément aligné ne garde plus son contenu',
      );
    });

    test('en attente : la dépendance manquante est NOMMÉE, puis levée '
        'quand l’élément lié arrive (deux tentatives)', () async {
      final unite = element('unites_hebergement', 'u-1', {
        'categorie_id': 'cat-1',
        'numero': '101',
        'statut': 'libre',
      });
      await descendre(FauxCatalogue([unite]));
      var e = await entree('unites_hebergement', 'u-1');
      expect(e.issue, IssueReception.enAttente);
      expect(e.cause, CauseReception.dependanceManquante);
      expect(e.dependance, 'categories_hebergement');
      expect(e.explication.phrase, contains('Catégories d\'hébergement'));
      expect(e.elementJson, isNotNull, reason: 'gardé pour la relance');

      await descendre(
        FauxCatalogue([
          element('categories_hebergement', 'cat-1', {
            'libelle': 'Chambre double',
            'capacite_max': 2,
            'tarif_base': '25000.00',
          }),
          unite,
        ]),
      );
      e = await entree('unites_hebergement', 'u-1');
      expect(e.issue, IssueReception.aligne);
      expect(e.elementJson, isNull);
      expect(e.tentatives, greaterThanOrEqualTo(2));
    });

    test(
      'refusée : la valeur inconnue est nommée avec son champ ; une '
      'nouvelle version corrigée au serveur repart à une tentative',
      () async {
        final base = {
          'libelle': 'Huile',
          'categorie': 'Épicerie',
          'unite_mesure': 'l',
          'suivi': 'quotidien-fou',
          'seuil_alerte': '1.00',
        };
        await descendre(FauxCatalogue([element('articles', 'art-9', base)]));
        var e = await entree('articles', 'art-9');
        expect(e.issue, IssueReception.refuse);
        expect(e.cause, CauseReception.valeurInconnue);
        expect(e.champ, 'Suivi');
        expect(e.explication.phrase, contains('quotidien-fou'));
        expect(e.elementJson, isNotNull);

        final corrige = element('articles', 'art-9', {
          ...base,
          'suivi': 'permanent',
        })..['modifie_le'] = '2026-10-16 09:00:00';
        await descendre(FauxCatalogue([corrige]));
        e = await entree('articles', 'art-9');
        expect(e.issue, IssueReception.aligne);
        expect(e.tentatives, 1, reason: 'autre version : on repart');
      },
    );

    test('refusée : une fraction de franc est une précision non tenue, '
        'une donnée absente nomme son champ', () async {
      await descendre(
        FauxCatalogue([
          element('categories_hebergement', 'cat-1', {
            'libelle': 'Chambre',
            'capacite_max': 2,
            'tarif_base': '25000.50',
          }),
          element('categories_hebergement', 'cat-2', {
            'capacite_max': 2,
            'tarif_base': '1000.00',
          }),
        ]),
      );
      final fraction = await entree('categories_hebergement', 'cat-1');
      expect(fraction.cause, CauseReception.precisionNonTenue);
      final sansLibelle = await entree('categories_hebergement', 'cat-2');
      expect(sansLibelle.cause, CauseReception.donneeIllisible);
      expect(sansLibelle.champ, 'Libellé');
    });

    test(
      'un élément illisible est consigné lui aussi, sans table devinée',
      () async {
        await descendre(
          FauxCatalogue([
            {
              'table': 'table_du_futur',
              'id': 'x-1',
              'donnees': <String, Object?>{},
            },
            {'donnees': <String, Object?>{}},
          ]),
        );
        final inconnue = await journal().lister(table: 'table_du_futur');
        expect(inconnue, hasLength(1));
        expect(inconnue.single.issue, IssueReception.refuse);
        expect(inconnue.single.cause, CauseReception.donneeIllisible);
        expect(inconnue.single.elementJson, isNull);
        final sans = await journal().lister(table: 'inconnue');
        expect(sans.single.elementId, 'illisible-1');
        expect((await journal().compter()).refuse, 2);
      },
    );

    test(
      'conservée : une modification locale en attente est la cause',
      () async {
        final ids = await b.enfilerClients(1);
        await descendre(
          FauxCatalogue([
            element('clients', ids.single, {
              'nom': 'Autre nom',
              'telephone': '97001000',
              'type': 'particulier',
            }),
          ]),
        );
        final e = await entree('clients', ids.single);
        expect(e.issue, IssueReception.conserve);
        expect(e.cause, CauseReception.conflitLocal);
        expect(e.explication.action, ActionCorrection.voirFileEnvoi);
      },
    );
  });

  test('les reprises AUTOMATIQUES d’un élément gardé ne gonflent pas ses '
      'tentatives tant que rien ne change', () async {
    final d = await descendre(
      FauxCatalogue([
        element('unites_hebergement', 'u-1', {
          'categorie_id': 'cat-1',
          'numero': '101',
          'statut': 'libre',
        }),
      ]),
    );
    final avant = await entree('unites_hebergement', 'u-1');
    for (var i = 0; i < 3; i++) {
      b.maintenant = b.maintenant.add(const Duration(minutes: 5));
      await d.descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    }
    final apres = await entree('unites_hebergement', 'u-1');
    expect(apres.tentatives, 1);
    expect(apres.derniereTentativeLe, avant.derniereTentativeLe);
    // Une relance MANUELLE, elle, compte.
    await d.relancerElement('unites_hebergement', 'u-1');
    expect((await entree('unites_hebergement', 'u-1')).tentatives, 2);
  });

  group('relancer', () {
    test('« Relancer » un élément sans compte local : la cause est nommée, '
        'le compte créé, la relance aligne CET élément', () async {
      final menu = element('menus', 'm-1', {
        'libelle': 'Midi',
        'type': 'local',
      });
      // Aucun compte pour porter l'écriture.
      await b.db.customStatement('DELETE FROM utilisateurs_local');
      final d = await descendre(FauxCatalogue([menu]), auteur: null);
      var e = await entree('menus', 'm-1');
      expect(e.cause, CauseReception.sansCompteLocal);
      expect(e.explication.route, '/comptes-utilisateurs');

      var r = await d.relancerElement('menus', 'm-1');
      expect(r.issue, IssueReception.enAttente, reason: 'toujours sans compte');
      expect((await entree('menus', 'm-1')).tentatives, 2);

      await b.semerAuteur();
      final d2 = b.descente(transportDe(FauxCatalogue([menu])));
      r = await d2.relancerElement('menus', 'm-1');
      expect(r.reussi, isTrue, reason: r.phrase);
      e = await entree('menus', 'm-1');
      expect(e.issue, IssueReception.aligne);
      expect(e.elementJson, isNull);
      expect(
        await (b.db.select(b.db.menusLocal)).get(),
        hasLength(1),
        reason: 'le menu est écrit sur le poste',
      );
      expect(
        (await b.dao.operations()),
        isEmpty,
        reason: 'une relance n’enfile jamais',
      );
    });

    test('« Relancer » un élément qui n’est plus gardé le dit', () async {
      final d = b.descente(transportDe(FauxCatalogue(const [])));
      final r = await d.relancerElement('menus', 'inconnu');
      expect(r.issue, isNull);
      expect(r.phrase, contains('n’est plus gardé'));
    });

    test(
      '« Relancer tout » rejoue les refusés et reprend les gardés',
      () async {
        await b.db.customStatement('DELETE FROM utilisateurs_local');
        await descendre(
          FauxCatalogue([
            element('menus', 'm-1', {'libelle': 'Midi', 'type': 'local'}),
            element('menus', 'm-2', {'libelle': 'Soir', 'type': 'local'}),
          ]),
          auteur: null,
        );
        expect((await journal().compter()).enAttente, 2);
        await b.semerAuteur();
        final d = b.descente(transportDe(FauxCatalogue(const [])));
        expect(await d.relancerTout(), 0);
        final c = await journal().compter();
        expect((c.aligne, c.aTraiter), (2, 0));
      },
    );
  });

  group('rétention bornée', () {
    Future<void> semer(String id, IssueReception issue, DateTime quand) => b.db
        .into(b.db.journalReceptionLocal)
        .insert(
          JournalReceptionLocalCompanion.insert(
            tableServeur: 'clients',
            elementId: id,
            issue: issue.code,
            cause: 'aucune',
            recuLe: quand,
            derniereTentativeLe: quand,
          ),
        );

    test('les alignés de plus de 30 jours partent, les éléments à traiter '
        'restent même anciens', () async {
      await semer('vieux', IssueReception.aligne, DateTime(2026, 8, 1));
      await semer('recent', IssueReception.aligne, DateTime(2026, 10, 14));
      await semer('vieux-refuse', IssueReception.refuse, DateTime(2026, 8, 1));
      expect(await journal().purger(), 1);
      final ids = {for (final e in await journal().lister()) e.elementId};
      expect(ids, {'recent', 'vieux-refuse'});
    });

    test('au-delà de 5 000 lignes, les alignés les plus anciens partent '
        'd’abord', () async {
      await b.db.batch((lot) {
        for (var i = 0; i < JournalReceptionDao.lignesMax + 10; i++) {
          lot.insert(
            b.db.journalReceptionLocal,
            JournalReceptionLocalCompanion.insert(
              tableServeur: 'clients',
              elementId: 'c-$i',
              issue: i < 5 ? 'refuse' : 'aligne',
              cause: 'aucune',
              recuLe: DateTime(2026, 10, 14, 0, 0, i % 60, 0),
              derniereTentativeLe: DateTime(
                2026,
                10,
                1,
              ).add(Duration(minutes: i)),
            ),
          );
        }
      });
      expect(await journal().purger(), 10);
      final c = await journal().compter();
      expect(c.recus, JournalReceptionDao.lignesMax);
      expect(c.refuse, 5, reason: 'les refusés (anciens) sont gardés');
    });
  });

  group('un SEUL écrivain', () {
    List<File> sources() => [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.endsWith('.g.dart') &&
            !f.path.endsWith('app_database.dart'))
          f,
    ];

    test('la table n’est écrite que par JournalReceptionDao', () {
      final motifs = [
        RegExp(r'\bjournalReceptionLocal\b'),
        RegExp(r'JournalReceptionLocalCompanion\b'),
        RegExp(
          r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+journal_reception_local',
        ),
      ];
      final ecrivains = [
        for (final f in sources())
          if (motifs.any((m) => m.hasMatch(f.readAsStringSync()))) f.path,
      ];
      expect(ecrivains, [
        'lib/features/synchronisation/data/journal_reception_dao.dart',
      ]);
    });

    test('seule DescenteCatalogue appelle ses gestes d’écriture — jamais un '
        'aligneur, jamais la file d’envoi, jamais l’écran', () {
      final appelants = [
        for (final f in sources())
          if (RegExp(r'\.(consigner|consignerIllisible|purger)\(').hasMatch(
            f.readAsStringSync().replaceAll('_dao.consignerBilan', ''),
          ))
            if (f.readAsStringSync().contains('JournalReceptionDao') ||
                f.readAsStringSync().contains('_journal.'))
              f.path,
      ];
      expect(appelants, [
        'lib/features/synchronisation/data/descente_catalogue.dart',
      ]);
    });

    test('le journal n’enfile rien : le DAO ne touche pas la file', () {
      final dao = File(
        'lib/features/synchronisation/data/journal_reception_dao.dart',
      ).readAsStringSync();
      expect(dao, isNot(contains('OperationsSyncDao')));
      expect(dao, isNot(contains('enfiler')));
      expect(dao, isNot(contains('operationsSyncLocal')));
    });
  });

  test('une descente applique la rétention : un vieil élément aligné '
      'part, un refusé ancien reste', () async {
    for (final (id, issue) in [
      ('vieux', IssueReception.aligne),
      ('vieux-refuse', IssueReception.refuse),
    ]) {
      await b.db
          .into(b.db.journalReceptionLocal)
          .insert(
            JournalReceptionLocalCompanion.insert(
              tableServeur: 'clients',
              elementId: id,
              issue: issue.code,
              cause: 'aucune',
              recuLe: DateTime(2026, 8, 1),
              derniereTentativeLe: DateTime(2026, 8, 1),
            ),
          );
    }
    await descendre(FauxCatalogue(const []));
    final ids = {for (final e in await journal().lister()) e.elementId};
    expect(ids, {'vieux-refuse'});
  });

  group('filtres', () {
    test('par table, par issue et par date', () async {
      await descendre(
        FauxCatalogue([
          element('unites_hebergement', 'u-1', {
            'categorie_id': 'cat-1',
            'numero': '101',
            'statut': 'libre',
          }),
          element('points_stockage', 'ps-1', {
            'libelle': 'Magasin',
            'type': 'magasin',
          }),
        ]),
      );
      expect(await journal().lister(), hasLength(2));
      expect(
        (await journal().lister(table: 'points_stockage')).single.elementId,
        'ps-1',
      );
      expect(
        (await journal().lister(
          issue: IssueReception.enAttente,
        )).single.elementId,
        'u-1',
      );
      expect(
        await journal().lister(du: DateTime(2026, 10, 16)),
        isEmpty,
        reason: 'réception du 15/10',
      );
      expect(
        await journal().lister(
          du: DateTime(2026, 10, 15),
          au: DateTime(2026, 10, 15),
        ),
        hasLength(2),
      );
      expect(await journal().tablesPresentes(), [
        'points_stockage',
        'unites_hebergement',
      ]);
    });
  });
}
