import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/archivage_clients.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/domain/messages_archivage_client.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../facturation/support/outils_encaissement.dart';

/// L'archivage d'un client (EF-M3-01) : les QUATRE verrous du serveur rejoués
/// sur les données de ce poste, le lot de la modale (bloqué / partiel /
/// nominal), l'exécution (verrou recontrôlé, écriture + file dans UNE
/// transaction) et la restauration. Les phrases sont confrontées au serveur par
/// `messages_relance_test.dart`.
void main() {
  late AppDatabase db;

  setUp(() async => db = await baseEncaissement());
  tearDown(() => db.close());

  ArchivageClients archivage() => ArchivageClients(
    db,
    maintenant: () => jourEncaissement, // 12/10/2026
    creances: () async => composerCreances(
      pieces: await FactureDao(db).pieces(),
      paiements: const [],
      acomptesParReservation: const {},
    ),
  );

  Future<List<OperationSync>> file() =>
      OperationsSyncDao(db).operations(table: TableSynchronisee.clients);

  Future<bool?> actif(String id) async => (await (db.select(
    db.clientsLocal,
  )..where((c) => c.id.equals(id))).getSingle()).actif;

  /// Une location qui finit à [fin] (clé étrangère du véhicule écartée : ce
  /// n'est pas ce qu'on éprouve).
  Future<void> semerLocation(String clientId, DateTime fin) async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db
        .into(db.contratsLocationLocal)
        .insert(
          ContratsLocationLocalCompanion.insert(
            id: 'loc-$clientId-${fin.day}',
            vehiculeId: 'veh-1',
            clientId: clientId,
            dateDebut: DateTime(2026, 10, 1),
            dateFin: fin,
          ),
        );
  }

  Future<void> semerCircuit(
    String clientId,
    DateTime jour, {
    String statut = 'reservee',
  }) async {
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db
        .into(db.reservationsTourLocal)
        .insert(
          ReservationsTourLocalCompanion.insert(
            id: 'tour-$clientId-${jour.day}-$statut',
            circuitId: 'c-1',
            clientId: clientId,
            guideId: 'g-1',
            dateCircuit: jour,
            nbParticipants: 2,
            statut: statut,
          ),
        );
  }

  group('Les quatre verrous (ReferentielClientService::verrous)', () {
    test('un client libre n’a aucun verrou', () async {
      final c = await creerClient(db);
      expect(await archivage().verrous(c.id), isEmpty);
    });

    test(
      '1. un séjour non annulé dont le départ est aujourd’hui ou plus tard',
      () async {
        final c = await creerClient(db);
        await semerReservation(db, id: 'r1', clientId: c.id); // 20 → 22/10
        expect(await archivage().verrous(c.id), [
          MessagesArchivageClient.verrouSejour(1),
        ]);
      },
    );

    test('1bis. la borne : un séjour qui part AUJOURD’HUI verrouille, hier '
        'non, et un séjour annulé jamais', () async {
      final c = await creerClient(db);
      await semerReservation(db, id: 'r1', clientId: c.id);
      for (final (depart, statut, attendu) in [
        (DateTime(2026, 10, 12), 'confirmee', 1),
        (DateTime(2026, 10, 11), 'confirmee', 0),
        (DateTime(2026, 11, 1), 'annulee', 0),
      ]) {
        await (db.update(
          db.reservationsLocal,
        )..where((r) => r.id.equals('r1'))).write(
          ReservationsLocalCompanion(
            dateDepart: Value(depart),
            statut: Value(statut),
          ),
        );
        expect(
          (await archivage().verrous(c.id)).length,
          attendu,
          reason: '$depart $statut',
        );
      }
    });

    test('2. une location dont la fin est aujourd’hui ou plus tard', () async {
      final c = await creerClient(db);
      await semerLocation(c.id, DateTime(2026, 10, 11)); // finie
      expect(await archivage().verrous(c.id), isEmpty);
      await semerLocation(c.id, DateTime(2026, 10, 12)); // finit aujourd'hui
      await semerLocation(c.id, DateTime(2026, 10, 30));
      expect(await archivage().verrous(c.id), [
        MessagesArchivageClient.verrouLocation(2),
      ]);
    });

    test('3. une réservation de circuit non annulée, à venir', () async {
      final c = await creerClient(db);
      await semerCircuit(c.id, DateTime(2026, 11, 1), statut: 'annulee');
      await semerCircuit(c.id, DateTime(2026, 10, 1)); // passée
      expect(await archivage().verrous(c.id), isEmpty);
      await semerCircuit(c.id, DateTime(2026, 11, 2));
      expect(await archivage().verrous(c.id), [
        MessagesArchivageClient.verrouCircuit(1),
      ]);
    });

    test(
      '4. une facture non soldée — par le prédicat UNIQUE des créances',
      () async {
        final c = await creerClient(db);
        await emettreFacture(db, montant: 5000, clientId: c.id);
        expect(await archivage().verrous(c.id), [
          MessagesArchivageClient.verrouCreance(1),
        ]);
      },
    );

    test('les motifs sortent dans l’ordre du serveur, et ne concernent que CE '
        'client', () async {
      final c = await creerClient(db);
      final autre = await creerClient(db, nom: 'AUTRE', telephone: '2');
      await emettreFacture(db, montant: 5000, clientId: c.id);
      await semerCircuit(c.id, DateTime(2026, 11, 2));
      await semerLocation(c.id, DateTime(2026, 10, 30));
      await semerReservation(db, id: 'r1', clientId: c.id);

      expect(await archivage().verrous(c.id), [
        MessagesArchivageClient.verrouSejour(1),
        MessagesArchivageClient.verrouLocation(1),
        MessagesArchivageClient.verrouCircuit(1),
        MessagesArchivageClient.verrouCreance(1),
      ]);
      expect(await archivage().verrous(autre.id), isEmpty);
    });
  });

  group('Le lot de la modale (confirmerArchivageClient)', () {
    test('NOMINAL : un client libre, nommé', () async {
      final c = await creerClient(db, nom: 'KORA');
      final lot = await archivage().composerLot([c.id]);
      expect(lot.ids, [c.id]);
      expect(lot.bloque, isFalse);
      expect(lot.conserves, 0);
      expect(lot.element, 'KORA');
      expect(lot.nombre, isNull);
    });

    test(
      'BLOQUÉ : le seul client visé est engagé, son motif porte son nom',
      () async {
        final c = await creerClient(db, nom: 'KORA');
        await emettreFacture(db, montant: 5000, clientId: c.id);
        final lot = await archivage().composerLot([c.id]);
        expect(lot.bloque, isTrue);
        expect(lot.ids, isEmpty);
        expect(lot.conserves, 1);
        expect(lot.motifs, [
          'KORA — ${MessagesArchivageClient.verrouCreance(1)}',
        ]);
      },
    );

    test('PARTIEL : une partie part, l’autre est conservée ; le NOMBRE qui '
        'part est annoncé', () async {
      final libre = await creerClient(db, nom: 'ALPHA');
      final libre2 = await creerClient(db, nom: 'BETA', telephone: '2');
      final engage = await creerClient(db, nom: 'GAMMA', telephone: '3');
      await emettreFacture(db, montant: 5000, clientId: engage.id);
      final lot = await archivage().composerLot([
        engage.id,
        libre2.id,
        libre.id,
      ]);
      // Trié par nom, comme `orderBy('nom')`.
      expect(lot.ids, [libre.id, libre2.id]);
      expect(lot.conserves, 1);
      expect(lot.bloque, isFalse);
      expect(lot.element, isNull);
      expect(lot.nombre, 2);
    });

    test('un client DÉJÀ archivé n’entre pas dans le lot ; une sélection '
        'd’archivés est bloquée sans motif', () async {
      final c = await creerClient(db);
      await archivage().archiverUn(c.id);
      final lot = await archivage().composerLot([c.id]);
      expect(lot.bloque, isTrue);
      expect(lot.motifs, isEmpty);
    });
  });

  group('Archiver / restaurer', () {
    test(
      'archive : actif=false ET {actif:false} enfilé, dans le même geste',
      () async {
        final c = await creerClient(db);
        await archivage().archiverUn(c.id);

        expect(await actif(c.id), isFalse);
        final ops = await file();
        expect(ops, hasLength(2)); // création du client, puis son archivage
        expect(ops.last.type, TypeOperationSync.modification);
        expect(jsonDecode(ops.last.payload), {'actif': false});
        // La fiche n'est PAS effacée.
        expect(await db.select(db.clientsLocal).get(), hasLength(1));
      },
    );

    test('le verrou est RECONTRÔLÉ au moment d’agir : rien n’est écrit, rien '
        'n’est enfilé', () async {
      final c = await creerClient(db);
      // La modale s'est ouverte sur un client libre ; une facture est née.
      await emettreFacture(db, montant: 5000, clientId: c.id);
      final avant = (await file()).length;

      await expectLater(
        archivage().archiverUn(c.id),
        throwsA(
          isA<RefusArchivageClient>().having(
            (e) => e.message,
            'message',
            MessagesArchivageClient.verrouCreance(1),
          ),
        ),
      );
      expect(await actif(c.id), isNot(false));
      expect((await file()).length, avant);
    });

    test('un lot : les libres partent, l’engagé reste, le DERNIER refus est '
        'rendu', () async {
      final libre = await creerClient(db, nom: 'ALPHA');
      final engage = await creerClient(db, nom: 'GAMMA', telephone: '3');
      await emettreFacture(db, montant: 5000, clientId: engage.id);

      final r = await archivage().archiverLot([libre.id, engage.id]);
      expect(r.archives, 1);
      expect(r.refus, MessagesArchivageClient.verrouCreance(1));
      expect(await actif(libre.id), isFalse);
      expect(await actif(engage.id), isNot(false));
    });

    test('restaurer : actif=true ET {actif:true} enfilé ; déjà actif = rien '
        'ne bouge', () async {
      final c = await creerClient(db, nom: 'KORA');
      await archivage().archiverUn(c.id);
      final nom = await archivage().restaurer(c.id);

      expect(nom, 'KORA');
      expect(await actif(c.id), isTrue);
      expect(jsonDecode((await file()).last.payload), {'actif': true});

      final avant = (await file()).length;
      await archivage().restaurer(c.id);
      expect((await file()).length, avant, reason: 'déjà actif : rien ne part');
    });

    test('un client d’AVANT la synchronisation part (création, puis archivage) '
        'AVANT d’être archivé', () async {
      await db
          .into(db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: 'ancien',
              nom: 'ANCIEN',
              telephone: '96',
              typeClient: 'particulier',
              statutSync: const Value('local'),
            ),
          );
      await archivage().archiverUn('ancien');
      expect(
        (await file()).map((o) => '${o.type.code} ${jsonDecode(o.payload)}'),
        [startsWith('creation {nom: ANCIEN'), 'modification {actif: false}'],
      );
    });

    test('un client inconnu est refusé', () async {
      await expectLater(
        archivage().archiverUn('fantome'),
        throwsA(isA<RefusArchivageClient>()),
      );
      await expectLater(
        archivage().restaurer('fantome'),
        throwsA(isA<RefusArchivageClient>()),
      );
    });

    test(
      'l’entité lit actif null comme actif (lignes d’avant la v35)',
      () async {
        await db
            .into(db.clientsLocal)
            .insert(
              ClientsLocalCompanion.insert(
                id: 'v34',
                nom: 'V34',
                telephone: '1',
                typeClient: 'particulier',
                actif: const Value(null),
              ),
            );
        final lot = await archivage().composerLot(['v34']);
        expect(lot.ids, ['v34'], reason: 'null = actif');
        expect(
          const Client(
            id: 'x',
            nom: 'n',
            telephone: 't',
            type: TypeClientReferentiel.groupe,
          ).actif,
          isTrue,
        );
      },
    );
  });
}
