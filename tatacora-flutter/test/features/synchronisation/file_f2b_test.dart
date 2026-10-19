import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// La file au lot F2b : le bail RENOUVELÉ avant chaque requête, et les deux
/// gestes de l'écran — « Renvoyer » (nouvel uuid, l'ancien reste en
/// historique) et « Débloquer » (seulement quand le blocage est levé).
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  Future<void> statut(String entiteId, String s, {int rang = 0}) async {
    final o = await b.operationDe(entiteId, rang: rang);
    await b.db.customStatement(
      'UPDATE operations_sync_local SET statut = ? WHERE seq = ?',
      [s, o.seq],
    );
  }

  group('le bail se RENOUVELLE avant chaque requête', () {
    test('une bissection plus longue que le bail : un autre processus ne '
        'reprend RIEN, chaque opération part une seule fois', () async {
      final ids = await b.enfilerClients(4);
      final autre = OperationsSyncDao(b.db, maintenant: () => b.maintenant);
      final voles = <String>[];
      final t = FauxTransport((r) async {
        // Chaque requête dure 4 minutes ; le bail en vaut 5.
        b.maintenant = b.maintenant.add(const Duration(minutes: 4));
        await autre.libererBauxExpires();
        voles.addAll([
          for (final o in await autre.reclamerLot(lotId: 'autre-processus'))
            o.uuidOperation,
        ]);
        return r.operations.length > 1
            ? const ReponseHttp(statut: 422, corps: {'message': 'Lot'})
            : reponseLot(r);
      });
      final bilan = await b.manager(t).synchroniserMaintenant();

      expect(voles, isEmpty, reason: 'le lot en cours a été repris');
      expect(bilan.etat, EtatSynchronisation.termine);
      expect(bilan.synchronisees, 4);
      final envoyees = [for (final l in t.lots) ...l.uuids];
      final uniques = {
        for (final l in t.lots.where((l) => l.uuids.length == 1)) ...l.uuids,
      };
      expect(uniques, hasLength(4));
      expect(t.lots.length, greaterThan(4), reason: 'bissection');
      for (final id in ids) {
        expect(
          (await b.operationDe(id)).statut,
          StatutOperationSync.synchronise,
        );
      }
      expect(envoyees, isNotEmpty);
    });

    test(
      'prolongerBail ne touche que les opérations EN COURS du lot',
      () async {
        await b.enfilerClients(2);
        final lot = await b.dao.reclamerLot(taille: 1, lotId: 'L1');
        b.maintenant = b.maintenant.add(const Duration(minutes: 1));
        expect(await b.dao.prolongerBail('L1', const Duration(minutes: 5)), 1);
        final o = (await b.dao.operations(lotId: 'L1')).single;
        expect(o.uuidOperation, lot.single.uuidOperation);
        expect(o.verrouJusqua, b.maintenant.add(const Duration(minutes: 5)));
        expect(
          await b.dao.prolongerBail('inconnu', const Duration(minutes: 5)),
          0,
        );
      },
    );
  });

  group('« Renvoyer » une opération rejetée', () {
    test('le MÊME document sous un NOUVEL uuid ; l’ancienne reste rejetée, '
        'marquée remplacée, hors de « À traiter »', () async {
      final id = (await b.enfilerClients(1)).single;
      await statut(id, 'rejete');
      final ancienne = await b.operationDe(id);

      final nouvel = await b.dao.renvoyer(ancienne.uuidOperation);
      expect(nouvel, isNot(ancienne.uuidOperation));
      final ops = await b.dao.operations(entiteId: id);
      expect(ops, hasLength(2));
      final (vieille, neuve) = (ops[0], ops[1]);
      expect(vieille.statut, StatutOperationSync.rejete, reason: 'historique');
      expect(neuve.uuidOperation, nouvel);
      expect(neuve.statut, StatutOperationSync.enAttente);
      expect(
        (neuve.payload, neuve.horodatageClient, neuve.type, neuve.table),
        (
          vieille.payload,
          vieille.horodatageClient,
          vieille.type,
          vieille.table,
        ),
      );
      expect(await b.dao.remplacees(), {ancienne.uuidOperation: nouvel});
      expect(await b.dao.aTraiter(), isEmpty);

      await expectLater(
        b.dao.renvoyer(ancienne.uuidOperation),
        throwsA(isA<StateError>()),
        reason: 'déjà renvoyée',
      );
      await expectLater(b.dao.renvoyer(nouvel), throwsA(isA<StateError>()));
    });

    test('la remplaçante PART, devant les opérations bloquées derrière le '
        'rejet ; celles-ci restent bloquées', () async {
      final id = (await b.enfilerClients(1)).single;
      await b.modifierClient(id, 'Nouveau nom');
      await statut(id, 'rejete');
      await statut(id, 'bloque', rang: 1);
      final rejetee = await b.operationDe(id);
      final nouvel = await b.dao.renvoyer(rejetee.uuidOperation);

      final lot = await b.dao.reclamerLot();
      expect([for (final o in lot) o.uuidOperation], [nouvel]);
      expect(
        (await b.operationDe(id, rang: 1)).statut,
        StatutOperationSync.bloque,
      );
    });
  });

  group('« Débloquer » une opération bloquée', () {
    test('refusé tant que le blocage tient ; permis quand la remplaçante est '
        'synchronisée — elle repart alors', () async {
      final id = (await b.enfilerClients(1)).single;
      await b.modifierClient(id, 'Nouveau nom');
      await statut(id, 'rejete');
      await statut(id, 'bloque', rang: 1);
      final bloquee = await b.operationDe(id, rang: 1);

      expect(await b.dao.debloquable(bloquee.uuidOperation), isFalse);
      expect(
        (await b.dao.aTraiter())
            .firstWhere((l) => l.operation.seq == bloquee.seq)
            .debloquable,
        isFalse,
      );
      await expectLater(
        b.dao.debloquer(bloquee.uuidOperation),
        throwsA(isA<StateError>()),
      );

      final nouvel = await b.dao.renvoyer(
        (await b.operationDe(id)).uuidOperation,
      );
      expect(
        await b.dao.debloquable(bloquee.uuidOperation),
        isFalse,
        reason: 'la remplaçante n’est pas encore synchronisée',
      );
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise' "
        'WHERE uuid_operation = ?',
        [nouvel],
      );
      expect(await b.dao.debloquable(bloquee.uuidOperation), isTrue);
      expect((await b.dao.aTraiter()).single.debloquable, isTrue);

      await b.dao.debloquer(bloquee.uuidOperation);
      final apres = await b.operationDe(id, rang: 1);
      expect(apres.statut, StatutOperationSync.enAttente);
      expect(apres.derniereErreur, isNull);
      expect(
        [for (final o in await b.dao.reclamerLot()) o.uuidOperation],
        [bloquee.uuidOperation],
      );
    });

    test('une opération non bloquée ne se débloque pas', () async {
      final id = (await b.enfilerClients(1)).single;
      await expectLater(
        b.dao.debloquer((await b.operationDe(id)).uuidOperation),
        throwsA(isA<StateError>()),
      );
    });
  });
}
