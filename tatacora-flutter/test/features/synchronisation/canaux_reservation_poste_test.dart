import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/canaux_reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_canaux.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../facturation/support/outils_encaissement.dart'
    show semerReservation, creerClient;

/// Les CANAUX de réservation sur le poste (21/10/2026, « tout au complet ») :
/// la table `canaux_reservation_local`, son écrivain unique, le jeu initial,
/// les trois gestes qui s'enfilent, la descente qui s'aligne par le NOM, et la
/// lecture des réservations (d'avant la v35 comprises).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late CanauxReservationDao dao;

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = CanauxReservationDao(db);
  });
  tearDown(() => db.close());

  Future<List<OperationSync>> file() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.canauxReservation);

  Future<IssueAlignement> descendre(
    String id,
    Map<String, Object?> donnees, {
    bool actif = true,
  }) => db.transaction(
    () =>
        AligneurCatalogue(
          db,
          DescenteCatalogueDao(db),
          auteur: () async => null,
        ).aligner(
          ElementCatalogue(
            table: TableDescendue.canauxReservation,
            id: id,
            actif: actif,
            modifieLe: '2026-10-21 10:00:00',
            donnees: donnees,
          ),
        ),
  );

  group('le jeu initial', () {
    test('un poste vierge reçoit les sept canaux du maître, dans l’ordre, '
        'sous des UUID stables — et rien n’est enfilé', () async {
      final tous = await dao.tous();
      expect([for (final c in tous) c.libelle], [
        'Physique',
        'Téléphone',
        'WhatsApp',
        'Booking.com',
        'Site web',
        'Facebook',
        'Agence partenaire',
      ]);
      expect(tous.every((c) => c.actif), isTrue);
      // Le serveur exige un UUID pour pousser : jamais les codes `can-…`.
      for (final c in tous) {
        expect(
          c.code,
          matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-')),
        );
      }
      // Stables : un second poste aboutit au même identifiant.
      expect(
        CanauxReservationDao.idInitial(CanalReservation.booking),
        tous[3].code,
      );
      expect(await file(), isEmpty);
      // Idempotent : lire deux fois ne duplique rien.
      expect(await dao.tous(), hasLength(7));
    });

    test('une réservation d’AVANT la v35 (code can-booking) se lit, puis '
        'reçoit l’identifiant du canal de même nom — sans rien envoyer', () async {
      final client = await creerClient(db);
      await semerReservation(db, id: 'res-1', clientId: client.id);
      await db.customStatement(
        "UPDATE reservations_local SET canal = 'can-booking' WHERE id = 'res-1'",
      );
      // Avant toute lecture des canaux : le code se lit encore.
      var r = (await ReservationDao(db).parId('res-1'))!;
      expect(r.canal, CanalReservation.booking);
      expect(r.canal!.libelle, 'Booking.com');

      final avantFile = (await OperationsSyncDao(db).operations()).length;
      final tous = await dao.tous();
      final booking = tous.firstWhere((c) => c.libelle == 'Booking.com');
      final colonne = await db
          .customSelect("SELECT canal FROM reservations_local WHERE id='res-1'")
          .getSingle();
      expect(colonne.data['canal'], booking.code);
      r = (await ReservationDao(db).parId('res-1'))!;
      expect(r.canal, booking);
      expect(
        (await OperationsSyncDao(db).operations()).length,
        avantFile,
        reason: 'le nom ne change pas : rien à pousser',
      );
    });
  });

  group('les trois gestes', () {
    test('ajouter : actif d’emblée, en fin de liste, créé au serveur par son '
        'NOM', () async {
      final c = await dao.ajouter('  Agence Sahel ');
      expect((c.libelle, c.actif), ('Agence Sahel', true));
      final tous = await dao.tous();
      expect(tous.last, c);
      final ops = await file();
      expect(ops, hasLength(1));
      expect(ops.single.type, TypeOperationSync.creation);
      expect(ops.single.entiteId, c.code);
      expect(jsonDecode(ops.single.payload), {
        'nom': 'Agence Sahel',
        'actif': true,
      });
    });

    test('renommer : l’ANCIEN nom part avec l’état, un nom inchangé non', () async {
      final tous = await dao.tous();
      final physique = tous.first;
      await dao.renommer(physique.code, 'Comptoir');
      final ops = await file();
      expect(ops, hasLength(1));
      expect(ops.single.type, TypeOperationSync.modification);
      expect(ops.single.entiteId, physique.code);
      expect(jsonDecode(ops.single.payload), {
        'nom': 'Comptoir',
        'ancien_nom': 'Physique',
        'actif': true,
      });
      expect((await dao.tous()).first.libelle, 'Comptoir');

      await dao.renommer(physique.code, 'Comptoir');
      expect(await file(), hasLength(1));
    });

    test('désactiver puis réactiver : l’état entier, sans ancien nom', () async {
      final c = await dao.ajouter('Salon');
      await dao.basculer(c.code);
      await dao.basculer(c.code);
      final ops = await file();
      expect(ops.map((o) => jsonDecode(o.payload)), [
        {'nom': 'Salon', 'actif': true},
        {'nom': 'Salon', 'actif': false},
        {'nom': 'Salon', 'actif': true},
      ]);
    });

    test('les refus portent les phrases du serveur et n’écrivent rien', () async {
      await dao.tous();
      await expectLater(
        dao.ajouter('   '),
        throwsA(
          isA<RefusCanal>().having(
            (e) => e.message,
            'message',
            MessagesCanaux.nomRequis,
          ),
        ),
      );
      await expectLater(
        dao.ajouter('physique'),
        throwsA(
          isA<RefusCanal>().having(
            (e) => e.message,
            'message',
            MessagesCanaux.nomDejaUtilise('physique'),
          ),
        ),
      );
      final tous = await dao.tous();
      await expectLater(
        dao.renommer(tous[1].code, 'WHATSAPP'),
        throwsA(isA<RefusCanal>()),
      );
      await expectLater(
        dao.basculer('inconnu'),
        throwsA(
          isA<RefusCanal>().having(
            (e) => e.message,
            'message',
            MessagesCanaux.introuvable,
          ),
        ),
      );
      await expectLater(dao.ajouter('x' * 101), throwsA(isA<RefusCanal>()));
      expect(await file(), isEmpty);
      expect(await dao.tous(), hasLength(7));
    });

    test('proposables : les actifs, plus le canal déjà retenu même désactivé ; '
        'le décompte des réservations suit le canal', () async {
      final tous = await dao.tous();
      final whatsapp = tous[2];
      await dao.basculer(whatsapp.code);
      final sans = await dao.proposables();
      expect(sans.map((c) => c.libelle), isNot(contains('WhatsApp')));
      final avec = await dao.proposables(retenu: whatsapp);
      expect(avec.map((c) => c.libelle), contains('WhatsApp'));

      final client = await creerClient(db);
      await semerReservation(db, id: 'res-1', clientId: client.id);
      await db.customStatement(
        "UPDATE reservations_local SET canal = '${tous[0].code}'",
      );
      expect(await dao.reservationsParCanal(), {tous[0].code: 1});
    });

    test('une réservation relit le libellé D’AUJOURD’HUI de son canal renommé', () async {
      final tous = await dao.tous();
      final client = await creerClient(db);
      await semerReservation(db, id: 'res-1', clientId: client.id);
      await db.customStatement(
        "UPDATE reservations_local SET canal = '${tous[3].code}'",
      );
      await dao.renommer(tous[3].code, 'Booking');
      final r = (await ReservationDao(db).parId('res-1'))!;
      expect(r.canal!.libelle, 'Booking');
      // Une valeur inconnue reste ABSENTE, jamais un repli sur « Physique ».
      await db.customStatement(
        "UPDATE reservations_local SET canal = 'n-importe-quoi'",
      );
      expect((await ReservationDao(db).parId('res-1'))!.canal, isNull);
    });
  });

  group('la descente', () {
    test('un canal du serveur s’apparie par son NOM au canal du poste : '
        'l’identifiant local reste, la correspondance est retenue, rien ne '
        'repart', () async {
      final tous = await dao.tous();
      final physique = tous.first;
      final r = await descendre('srv-physique', {'nom': 'physique'});
      expect(r, isA<Aligne>());
      expect(
        await DescenteCatalogueDao(
          db,
        ).idLocal('canaux_reservation', 'srv-physique'),
        physique.code,
      );
      expect(await dao.tous(), hasLength(7), reason: 'aucun doublon');
      expect(await file(), isEmpty);
    });

    test('un canal neuf du serveur est créé, désactivé s’il l’est là-bas, en '
        'fin de liste', () async {
      await dao.tous();
      await descendre('srv-1', {'nom': 'Agence du Sahel'});
      await descendre('srv-2', {'nom': 'Ancien canal'}, actif: false);
      final tous = await dao.tous();
      expect(tous.map((c) => c.libelle).skip(7), [
        'Agence du Sahel',
        'Ancien canal',
      ]);
      expect(tous.last.actif, isFalse);
      expect(await file(), isEmpty);
    });

    test('l’état du serveur s’applique à un canal connu (désactivation, '
        'réactivation)', () async {
      await dao.tous();
      await descendre('srv-1', {'nom': 'Salon'});
      await descendre('srv-1', {'nom': 'Salon'}, actif: false);
      expect((await dao.tous()).last.actif, isFalse);
      await descendre('srv-1', {'nom': 'Salon'});
      expect((await dao.tous()).last.actif, isTrue);
    });

    test('un renommage local qui attend de partir est CONSERVÉ', () async {
      final tous = await dao.tous();
      await dao.renommer(tous[1].code, 'Appel');
      await DescenteCatalogueDao(db).retenirCorrespondance(
        table: 'canaux_reservation',
        idServeur: 'srv-tel',
        idLocal: tous[1].code,
        origine: 'libelle',
      );
      final r = await descendre('srv-tel', {'nom': 'Téléphone'});
      expect(r, isA<ConserveLocalement>());
      expect((await dao.tous())[1].libelle, 'Appel');
    });

    test('le nom du serveur retrouve le canal local, insensible à la casse', () async {
      final tous = await dao.tous();
      final canal = await dao.parNom('booking.COM');
      expect(canal!.id, tous[3].code);
    });

    test('le libellé français de la table est dit, et les canaux descendent '
        'AVANT les réservations', () {
      expect(
        libelleTableServeur('canaux_reservation'),
        'Canaux de réservation',
      );
      final noms = [for (final t in TableDescendue.values) t.nomServeur];
      expect(
        noms.indexOf('canaux_reservation'),
        lessThan(noms.indexOf('reservations')),
      );
    });
  });
}
