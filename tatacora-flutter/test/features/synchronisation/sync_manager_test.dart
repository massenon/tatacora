import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import 'support/faux_transport.dart';

/// Le MOTEUR D'ENVOI (lot F2a) contre un faux transport : chaque ligne de la
/// politique d'erreur convenue au plan du lot a son cas.
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  FauxTransport toutAccepter() => FauxTransport(reponseLot);

  group(
    'les préalables : rien ne part sans appairage, ni en démonstration',
    () {
      test('poste NON appairé : aucune requête, la file intacte', () async {
        final nu = await BancSync.creer(appaire: false);
        addTearDown(nu.fermer);
        await nu.enfilerClients(3);
        final t = toutAccepter();
        final bilan = await nu.manager(t).synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.nonAppaire);
        expect(t.requetes, isEmpty);
        expect((await nu.comptes())[StatutOperationSync.enAttente], 3);
      });

      test('démonstration : JAMAIS de synchronisation, même appairé avec une '
          'file pleine', () async {
        await b.enfilerClients(3);
        final t = toutAccepter();
        final bilan = await b
            .manager(t, demonstration: true)
            .synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.demonstration);
        // Le flavor `demo` n'a pas d'adresse : même refus.
        final sansUrl = await b.manager(t, url: null).synchroniserMaintenant();
        expect(sansUrl.etat, EtatSynchronisation.demonstration);
        expect(t.requetes, isEmpty);
        expect((await b.comptes())[StatutOperationSync.enAttente], 3);
      });

      test(
        'appairé à un AUTRE serveur que celui du build : rien ne part',
        () async {
          await b.appairer(serveur: 'https://ailleurs.essai/api/v1');
          await b.enfilerClients(1);
          final t = toutAccepter();
          expect(
            (await b.manager(t).synchroniserMaintenant()).etat,
            EtatSynchronisation.autreServeur,
          );
          expect(t.requetes, isEmpty);
        },
      );

      test('file vide : aucune requête (zéro réseau au repos)', () async {
        final t = toutAccepter();
        final bilan = await b.manager(t).synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.termine);
        expect(t.requetes, isEmpty);
      });
    },
  );

  group('200 : les résultats sont consignés', () {
    test('le lot part au protocole (poste, jeton, ordre de seq) et chaque '
        'résultat est consigné tel quel, fusion comprise', () async {
      final ids = await b.enfilerClients(3);
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => o['entite_id'] == ids[1]
              ? {
                  'uuid_operation': o['uuid_operation'],
                  'statut': 'synchronise',
                  'entite_id': 'serveur-1',
                  'fusionne_avec': 'serveur-1',
                }
              : null,
        ),
      );
      final bilan = await b.manager(t).synchroniserMaintenant();

      expect(bilan.etat, EtatSynchronisation.termine);
      expect((bilan.lots, bilan.envoyees, bilan.synchronisees), (1, 3, 3));
      final lot = t.lots.single;
      expect(lot.url.toString(), '${BancSync.urlServeur}/sync');
      expect(lot.jeton, BancSync.jeton);
      expect(lot.corps!['poste_id'], BancSync.poste);
      expect([for (final o in lot.operations) o['entite_id']], ids);
      final premiere = lot.operations.first;
      expect(premiere.keys.toSet(), {
        'uuid_operation',
        'table',
        'type',
        'entite_id',
        'payload',
        'horodatage_client',
      });
      expect(premiere['table'], 'clients');
      expect((premiere['payload']! as Map)['nom'], 'C0');

      final fusionnee = await b.operationDe(ids[1]);
      expect(fusionnee.statut, StatutOperationSync.synchronise);
      expect(fusionnee.idServeur, 'serveur-1');
      expect(
        (jsonDecode(fusionnee.resultatJson!) as Map)['fusionne_avec'],
        'serveur-1',
      );
      expect(fusionnee.codeHttp, 200);
      expect((await b.operationDe(ids[0])).synchroniseLe, b.maintenant);
    });

    test('document déjà enregistré, rejeu idempotent, clôture sans session '
        'serveur : des SUCCÈS', () async {
      final ids = await b.enfilerClients(3);
      final drapeaux = [
        {'statut': 'synchronise', 'document_deja_enregistre': true},
        {'statut': 'synchronise', 'rejeu_idempotent': true},
        {'statut': 'cloture_sans_session_serveur'},
      ];
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => {
            'uuid_operation': o['uuid_operation'],
            'entite_id': o['entite_id'],
            ...drapeaux[ids.indexOf(o['entite_id']! as String)],
          },
        ),
      );
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect(bilan.synchronisees, 3);
      expect((await b.comptes())[StatutOperationSync.synchronise], 3);
    });

    test('rejet et conflit par opération : consignés, et l’opération '
        'suivante du même élément BLOQUÉE (règle de F1)', () async {
      final ids = await b.enfilerClients(2);
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => switch (ids.indexOf(o['entite_id']! as String)) {
            0 => {
              'uuid_operation': o['uuid_operation'],
              'statut': 'rejete',
              'entite_id': o['entite_id'],
              'motif': 'Téléphone déjà utilisé.',
            },
            _ => {
              'uuid_operation': o['uuid_operation'],
              'statut': 'conflit',
              'entite_id': o['entite_id'],
            },
          },
        ),
      );
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect((bilan.rejetees, bilan.conflits), (1, 1));
      final rejetee = await b.operationDe(ids[0]);
      expect(rejetee.statut, StatutOperationSync.rejete);
      expect(rejetee.derniereErreur, 'Téléphone déjà utilisé.');

      // Une modification ultérieure du client refusé ne part jamais.
      await b.modifierClient(ids[0], 'Nouveau nom');
      await b.manager(t).synchroniserMaintenant();
      expect(t.lots, hasLength(1), reason: 'rien n’est échu');
      final ops = await b.dao.operations(entiteId: ids[0]);
      expect(ops.last.statut, StatutOperationSync.enAttente);
    });

    test('plus de 50 opérations : des lots de 50, dans l’ordre, jusqu’à '
        'épuisement', () async {
      final ids = await b.enfilerClients(120);
      final t = toutAccepter();
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect([for (final l in t.lots) l.operations.length], [50, 50, 20]);
      expect([
        for (final l in t.lots)
          for (final o in l.operations) o['entite_id'],
      ], ids);
      expect(bilan.synchronisees, 120);
      expect(await b.total(), 120, reason: 'rien n’est supprimé');
    });

    test('200 sans résultat lisible pour une opération : alerte, elle est '
        'rendue à la file avec repli — jamais marquée réussie', () async {
      final ids = await b.enfilerClients(3);
      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) => o['entite_id'] == ids[2]
              ? {'uuid_operation': o['uuid_operation'], 'statut': '???'}
              : null,
        ),
      );
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.alerte);
      expect(bilan.synchronisees, 2);
      final orpheline = await b.operationDe(ids[2]);
      expect(orpheline.statut, StatutOperationSync.enAttente);
      expect(
        orpheline.prochaineTentative,
        b.maintenant.add(const Duration(seconds: 30)),
      );
    });

    test(
      '200 au corps illisible : alerte, tout le lot attend son repli',
      () async {
        await b.enfilerClients(2);
        final t = FauxTransport(
          (_) => const ReponseHttp(statut: 200, corps: null),
        );
        final bilan = await b.manager(t).synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.alerte);
        expect((await b.comptes())[StatutOperationSync.enAttente], 2);
        expect((await b.comptes())[StatutOperationSync.synchronise], 0);
      },
    );
  });

  group('échec transitoire : repli, rien de perdu', () {
    test('serveur injoignable : le lot redevient en_attente avec 30 s de '
        'repli, la synchronisation s’arrête', () async {
      await b.enfilerClients(60);
      final t = FauxTransport((_) => const ServeurInjoignable('délai'));
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect(bilan.etat, EtatSynchronisation.serveurIndisponible);
      expect(t.lots, hasLength(1), reason: 'arrêt au premier échec');
      expect((await b.comptes())[StatutOperationSync.enAttente], 60);
      final premiere = (await b.dao.operations()).first;
      expect(
        premiere.prochaineTentative,
        b.maintenant.add(const Duration(seconds: 30)),
      );
      expect(premiere.derniereErreur, contains('injoignable'));
      expect(bilan.prochaineTentative, premiere.prochaineTentative);
    });

    test('le repli progresse : 30 s → 2 min → 5 min → 15 min → 1 h, puis '
        'reste à 1 h ; avant l’échéance, AUCUNE requête', () async {
      await b.enfilerClients(1);
      final t = FauxTransport((_) => const ServeurInjoignable('coupé'));
      final m = b.manager(t);
      final attendus = [
        const Duration(seconds: 30),
        const Duration(minutes: 2),
        const Duration(minutes: 5),
        const Duration(minutes: 15),
        const Duration(hours: 1),
        const Duration(hours: 1),
      ];
      for (final (rang, delai) in attendus.indexed) {
        await m.synchroniserMaintenant();
        expect(t.lots, hasLength(rang + 1));
        final op = (await b.dao.operations()).single;
        expect(op.prochaineTentative, b.maintenant.add(delai), reason: '$rang');
        // Juste avant l'échéance : rien ne part.
        b.maintenant = b.maintenant.add(delai - const Duration(seconds: 1));
        await m.synchroniserMaintenant();
        expect(t.lots, hasLength(rang + 1), reason: 'repli non échu ($rang)');
        b.maintenant = b.maintenant.add(const Duration(seconds: 1));
      }
      // Le serveur revient : l'opération part et réussit.
      t.repondre = reponseLot;
      await m.synchroniserMaintenant();
      expect(
        (await b.dao.operations()).single.statut,
        StatutOperationSync.synchronise,
      );
    });

    for (final (code, nom) in [
      (500, '500'),
      (502, '502'),
      (503, '503'),
      (429, '429'),
      (408, '408'),
    ]) {
      test('HTTP $nom : transitoire, comme une absence de réponse', () async {
        await b.enfilerClients(2);
        final t = FauxTransport(
          (_) => ReponseHttp(statut: code, corps: const {'message': 'x'}),
        );
        final bilan = await b.manager(t).synchroniserMaintenant();
        expect(bilan.etat, EtatSynchronisation.serveurIndisponible);
        expect(bilan.codeHttp, code);
        expect((await b.comptes())[StatutOperationSync.enAttente], 2);
        expect((await b.comptes())[StatutOperationSync.rejete], 0);
        expect((await b.dao.operations()).first.codeHttp, code);
      });
    }

    test('Retry-After (secondes) est HONORÉ à la place du repli', () async {
      await b.enfilerClients(1);
      final t = FauxTransport(
        (_) => const ReponseHttp(
          statut: 503,
          corps: null,
          entetes: {'retry-after': '600'},
        ),
      );
      await b.manager(t).synchroniserMaintenant();
      expect(
        (await b.dao.operations()).single.prochaineTentative,
        b.maintenant.add(const Duration(minutes: 10)),
      );
    });

    test('Retry-After (date HTTP) est honoré, sur un 429', () async {
      await b.enfilerClients(1);
      // L'horloge du banc à 10:00 locale ; l'en-tête dit « +7 min » en GMT.
      final cible = b.maintenant.toUtc().add(const Duration(minutes: 7));
      const jours = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      String d2(int n) => n.toString().padLeft(2, '0');
      final entete =
          '${jours[cible.weekday - 1]}, ${d2(cible.day)} Oct ${cible.year} '
          '${d2(cible.hour)}:${d2(cible.minute)}:00 GMT';
      final t = FauxTransport(
        (_) => ReponseHttp(
          statut: 429,
          corps: null,
          entetes: {'retry-after': entete},
        ),
      );
      await b.manager(t).synchroniserMaintenant();
      expect(
        (await b.dao.operations()).single.prochaineTentative,
        b.maintenant.add(const Duration(minutes: 7)),
      );
    });
  });

  group(
    '401 / 403 : arrêt total, file intacte, plus rien avant réappairage',
    () {
      for (final (code, etat) in [
        (401, EtatSynchronisation.jetonRefuse),
        (403, EtatSynchronisation.posteNonReconnu),
      ]) {
        test('HTTP $code : ${etat.name}, opérations rendues INTACTES, refus '
            'consigné ; aucune requête avant un nouvel appairage', () async {
          await b.enfilerClients(60);
          final t = FauxTransport(
            (_) => ReponseHttp(statut: code, corps: const {'message': 'non'}),
          );
          final m = b.manager(t);
          final bilan = await m.synchroniserMaintenant();
          expect(bilan.etat, etat);
          expect(t.lots, hasLength(1));
          for (final o in await b.dao.operations()) {
            expect(o.statut, StatutOperationSync.enAttente);
            expect(o.tentatives, 0, reason: 'la tentative ne compte pas');
            expect(o.prochaineTentative, isNull, reason: 'aucun repli');
            expect(o.derniereErreur, isNull);
            expect(o.lotId, isNull);
          }
          expect(
            (await b.fichier())[ClesAppairage.refus],
            containsPair('code', code),
          );

          // Le lendemain : toujours rien.
          b.maintenant = b.maintenant.add(const Duration(days: 1));
          expect((await m.synchroniserMaintenant()).etat, etat);
          expect(t.lots, hasLength(1), reason: 'pas de nouvel essai');

          // Réappairé : tout part.
          await b.appairer();
          t.repondre = reponseLot;
          final apres = await m.synchroniserMaintenant();
          expect(apres.etat, EtatSynchronisation.termine);
          expect(apres.synchronisees, 60);
        });
      }
    },
  );

  group('422 sur le lot entier : bissection', () {
    test('UNE opération fautive parmi 50 : elle seule est rejetée (422, '
        'phrase du serveur), les 49 autres partent', () async {
      final ids = await b.enfilerClients(50);
      final fautive = ids[37];
      final t = FauxTransport((r) {
        final rang = r.operations.indexWhere((o) => o['entite_id'] == fautive);
        if (rang >= 0) {
          return ReponseHttp(
            statut: 422,
            corps: {
              'message': 'Le champ entite_id doit être un UUID valide.',
              'errors': {
                'operations.$rang.entite_id': [
                  'Le champ entite_id doit être un UUID valide.',
                ],
              },
            },
          );
        }
        return reponseLot(r);
      });
      final bilan = await b.manager(t).synchroniserMaintenant();

      expect(bilan.etat, EtatSynchronisation.termine);
      expect((bilan.synchronisees, bilan.rejetees), (49, 1));
      final rejetee = await b.operationDe(fautive);
      expect(rejetee.statut, StatutOperationSync.rejete);
      expect(rejetee.codeHttp, 422);
      expect(
        rejetee.derniereErreur,
        'Refusée par le serveur (422) : Le champ entite_id doit être un UUID '
        'valide.',
      );
      // Chaque opération saine est partie, UNE fois acceptée.
      final acceptees = <String>{
        for (final l in t.lots)
          if (!l.operations.any((o) => o['entite_id'] == fautive))
            ...l.operations.map((o) => o['entite_id']! as String),
      };
      expect(acceptees, ids.toSet()..remove(fautive));
      // Une bissection, pas cinquante envois : ~2 log2(50).
      expect(t.lots.length, lessThanOrEqualTo(13));
      expect(await b.total(), 50);
    });

    test('la bissection ne fait pas partir, après le rejet, une opération '
        'SUIVANTE du même élément : elle est bloquée', () async {
      final ids = await b.enfilerClients(4);
      await b.modifierClient(ids[1], 'Après refus');
      final fautive = (await b.operationDe(ids[1])).uuidOperation;
      final t = FauxTransport(
        (r) => r.uuids.contains(fautive)
            ? const ReponseHttp(statut: 422, corps: {'message': 'Invalide.'})
            : reponseLot(r),
      );
      await b.manager(t).synchroniserMaintenant();
      final ops = await b.dao.operations(entiteId: ids[1]);
      expect(ops[0].statut, StatutOperationSync.rejete);
      expect(ops[1].statut, StatutOperationSync.bloque);
      // Elle n'a figuré que dans le PREMIER lot, refusé en entier (422) ;
      // aucun lot ACCEPTÉ ne l'a portée.
      expect(t.lots.first.uuids, contains(ops[1].uuidOperation));
      expect(
        t.lots.where((l) => !l.uuids.contains(fautive)).expand((l) => l.uuids),
        isNot(contains(ops[1].uuidOperation)),
      );
    });
  });

  group('413 : la taille du lot est divisée par deux', () {
    test('un serveur qui refuse plus de 20 opérations : tout part, en lots '
        'de plus en plus petits — et les lots RÉCLAMÉS ensuite le sont à la '
        'nouvelle taille', () async {
      await b.enfilerClients(100);
      var refus = 0;
      final t = FauxTransport((r) {
        if (r.operations.length > 20) {
          refus++;
          return const ReponseHttp(statut: 413, corps: null);
        }
        return reponseLot(r);
      });
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect(bilan.synchronisees, 100);
      expect([for (final l in t.lots) l.operations.length].take(7), [
        50,
        25,
        13,
        12,
        25,
        13,
        12,
      ]);
      // Après le premier lot, plus aucun lot de 50 : 3 refus en tout (50,
      // puis ses deux moitiés de 25), jamais un de plus.
      expect(refus, 3);
      expect(t.lots.skip(7).map((l) => l.operations.length), [13, 13, 13, 11]);
    });

    test('une opération seule trop volumineuse : rejetée (413), pas de '
        'boucle', () async {
      await b.enfilerClients(1);
      final t = FauxTransport(
        (_) => const ReponseHttp(statut: 413, corps: null),
      );
      final bilan = await b.manager(t).synchroniserMaintenant();
      expect(bilan.rejetees, 1);
      expect(t.lots, hasLength(1));
      expect((await b.dao.operations()).single.codeHttp, 413);
    });
  });

  test('autre 4xx (404) : les opérations du lot sont rejetées avec le code, '
      'alerte, arrêt — les suivantes attendent', () async {
    await b.enfilerClients(60);
    final t = FauxTransport((_) => const ReponseHttp(statut: 404, corps: null));
    final bilan = await b.manager(t).synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.alerte);
    expect(bilan.codeHttp, 404);
    expect(t.lots, hasLength(1));
    final comptes = await b.comptes();
    expect(comptes[StatutOperationSync.rejete], 50);
    expect(comptes[StatutOperationSync.enAttente], 10);
    expect((await b.dao.operations()).first.codeHttp, 404);
  });

  group('un seul envoi à la fois', () {
    test('deux déclencheurs simultanés : UN envoi, le même bilan', () async {
      await b.enfilerClients(3);
      final porte = Completer<void>();
      final t = FauxTransport((r) async {
        await porte.future;
        return reponseLot(r);
      });
      final m = b.manager(t);
      final a = m.synchroniserMaintenant();
      final c = m.synchroniserMaintenant();
      expect(identical(a, c), isTrue);
      await pumpEventQueue();
      porte.complete();
      final (ba, bc) = (await a, await c);
      expect(identical(ba, bc), isTrue);
      expect(t.lots, hasLength(1));
      // Une fois fini, un nouvel appel repart.
      await b.enfilerClients(1);
      await m.synchroniserMaintenant();
      expect(t.lots, hasLength(2));
    });

    test('un SECOND moteur (autre processus, même base) pendant un envoi : '
        'le bail le tient à l’écart', () async {
      await b.enfilerClients(3);
      final porte = Completer<void>();
      final t1 = FauxTransport((r) async {
        await porte.future;
        return reponseLot(r);
      });
      final t2 = toutAccepter();
      final premier = b.manager(t1).synchroniserMaintenant();
      await pumpEventQueue();
      expect(t1.lots, hasLength(1));
      final second = await b.manager(t2).synchroniserMaintenant();
      expect(second.etat, EtatSynchronisation.termine);
      expect(t2.lots, isEmpty, reason: 'tout est sous bail');
      porte.complete();
      expect((await premier).synchronisees, 3);
    });
  });

  test('reprise après un ARRÊT BRUTAL en plein lot : rien ne part sous le '
      'bail, tout part à son échéance', () async {
    await b.enfilerClients(5);
    // Le processus tué : un lot réclamé, jamais conclu.
    final orphelin = await b.dao.reclamerLot(bail: const Duration(minutes: 5));
    expect(orphelin, hasLength(5));
    final t = toutAccepter();
    final m = b.manager(t);
    await m.synchroniserMaintenant();
    expect(t.lots, isEmpty, reason: 'bail en cours');

    b.maintenant = b.maintenant.add(const Duration(minutes: 6));
    final bilan = await m.synchroniserMaintenant();
    expect(bilan.synchronisees, 5);
    expect((await b.comptes())[StatutOperationSync.synchronise], 5);
  });

  test('une erreur interne ne remonte jamais : bilan d’alerte', () async {
    await b.enfilerClients(1);
    final t = FauxTransport((_) => throw StateError('panne'));
    final bilan = await b.manager(t).synchroniserMaintenant();
    expect(bilan.etat, EtatSynchronisation.alerte);
  });

  group('Retry-After et repli (unités)', () {
    test('lireRetryAfter', () {
      final t0 = DateTime.utc(2026, 10, 15, 10);
      expect(lireRetryAfter('120', t0), const Duration(minutes: 2));
      expect(lireRetryAfter(null, t0), isNull);
      expect(lireRetryAfter('demain', t0), isNull);
      expect(
        lireRetryAfter('Thu, 15 Oct 2026 10:00:30 GMT', t0),
        const Duration(seconds: 30),
      );
      expect(lireRetryAfter('999999', t0), plafondRetryAfter);
    });

    test('delaiDeRepli', () {
      expect(
        [for (var i = 1; i <= 7; i++) delaiDeRepli(i)],
        const [
          Duration(seconds: 30),
          Duration(minutes: 2),
          Duration(minutes: 5),
          Duration(minutes: 15),
          Duration(hours: 1),
          Duration(hours: 1),
          Duration(hours: 1),
        ],
      );
    });
  });
}
