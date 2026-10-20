import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/hebergement/data/pieces_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// L'acompte d'une réservation passe sa pièce (Dr trésorerie du mode / Cr 4191)
/// dans la MÊME transaction que la réservation — chemin réel `CreerReservation`
/// -> `ReservationRepositoryLocal.creer` -> `ReservationDao.creer` ->
/// `MoteurComptable` -> `ecritures_local`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final jour = DateTime(2026, 8, 1, 10);
  late AppDatabase db;
  late ComptabiliteDao compta;
  late ReservationRepositoryLocal depot;

  Future<void> semerParc() async {
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT INTO unites_hebergement_local (id, categorie_id, numero, statut) '
      "VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) VALUES '
      "('cli-1', 'KORA', '+229 01', 'particulier')",
    );
  }

  setUp(() async {
    db = await baseInstallee(maintenant: jour);
    compta = ComptabiliteDao(db);
    await semerParc();
    depot = ReservationRepositoryLocal(
      ReservationDao(
        db,
        maintenant: () => jour,
        moteur: () async => moteurSur(db, maintenant: () => jour),
      ),
    );
  });

  tearDown(() => db.close());

  Future<Reservation> reserver({
    int acompte = 20000,
    ModePaiementReservation? mode = ModePaiementReservation.especes,
    String auteur = auteurEssai,
    ReservationRepositoryLocal? via,
  }) async => CreerReservation(via ?? depot, maintenant: () => jour)(
    unite: (await (via ?? depot).unites()).first,
    clientId: 'cli-1',
    clientNom: '',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 8, 10),
      depart: DateTime(2026, 8, 12),
    ),
    acompte: acompte,
    modePaiement: mode,
    auteurId: auteur,
  );

  Future<int> reservations() async =>
      (await db
                  .customSelect('SELECT COUNT(*) AS n FROM reservations_local')
                  .getSingle())
              .data['n']
          as int;

  Future<List<String>> piece(String reservationId) async {
    final lignes = await compta.lignesParLibelle(
      MessagesAnnulation.libelleDeLAcompte(reservationId),
    );
    return [
      for (final l in lignes)
        '${(await compta.compteParId(l.compteId))!.numero} '
            '${l.debitCentimes > 0 ? 'D${l.debitCentimes}' : 'C${l.creditCentimes}'}',
    ];
  }

  group('Avec un acompte reçu, la pièce naît avec la réservation', () {
    test('espèces : Dr 5711 / Cr 4191', () async {
      final r = await reserver();
      expect(await piece(r.id), ['5711 D2000000', '4191 C2000000']);
    });

    test(
      'Mobile Money : 552 (la banque, elle, est épinglée par la fonction pure)',
      () async {
        final a = await reserver(mode: ModePaiementReservation.mobileMoney);
        expect((await piece(a.id)).first, '552 D2000000');
      },
    );

    test('à CRÉDIT, sans mode, ou sans acompte : aucune pièce (un fait, '
        'pas un oubli) et aucun moteur requis', () async {
      final sansMoteur = ReservationRepositoryLocal(ReservationDao(db));
      for (final (acompte, mode) in [
        (20000, ModePaiementReservation.credit),
        (20000, null),
        (0, ModePaiementReservation.especes),
      ]) {
        await db.customStatement('DELETE FROM reservations_local');
        final r = await reserver(acompte: acompte, mode: mode, via: sansMoteur);
        expect(await piece(r.id), isEmpty);
        expect(await reservations(), 1);
      }
      expect((await compta.toutesLesEcritures()), isEmpty);
    });
  });

  group('Une pièce refusée emporte la réservation', () {
    test(
      'sans auteur : refus RG-15, aucune réservation, aucune pièce',
      () async {
        await expectLater(
          reserver(auteur: ''),
          throwsA(
            isA<RefusComptable>().having(
              (e) => e.motif,
              'motif',
              MotifRefus.auteurAbsent,
            ),
          ),
        );
        expect(await reservations(), 0);
        expect(await compta.toutesLesEcritures(), isEmpty);
      },
    );

    test('hors exercice : refus, rien d’écrit', () async {
      // Un exercice 2040 CLÔTURÉ : manquant, il s'ouvrirait de lui-même à sa
      // première pièce depuis le 20/10/2026.
      await exerciceClos(db, 2040);
      final hors = ReservationRepositoryLocal(
        ReservationDao(
          db,
          maintenant: () => DateTime(2040, 1, 2, 10),
          moteur: () async =>
              moteurSur(db, maintenant: () => DateTime(2040, 1, 2, 10)),
        ),
      );
      await expectLater(reserver(via: hors), throwsA(isA<RefusComptable>()));
      expect(await reservations(), 0);
      expect(await compta.toutesLesEcritures(), isEmpty);
    });

    test('un DAO sans moteur LÈVE quand une pièce est due : jamais un acompte '
        'sans sa pièce par omission', () async {
      final sansMoteur = ReservationRepositoryLocal(ReservationDao(db));
      await expectLater(reserver(via: sansMoteur), throwsStateError);
      expect(await reservations(), 0);
    });
  });

  group('La fonction pure', () {
    test('trésorerie par mode : crédit et absent ne bougent aucune '
        'trésorerie', () {
      expect(tresorerieDeLAcompte(ModePaiementReservation.credit), isNull);
      expect(tresorerieDeLAcompte(null), isNull);
      expect(tresorerieDeLAcompte(ModePaiementReservation.cheque), isNotNull);
    });

    test('le remboursement : Dr 4191 (la dette s’éteint) / Cr 5711 (la '
        'caisse sort), journal de caisse, libellé au nom du client', () {
      final d = pieceDuRemboursement(
        client: 'Jean KORA',
        rembourseCentimes: 300000,
        dateIso: '2026-08-01',
      );
      expect(d.journal, 'CAI');
      expect(d.libelle, MessagesAnnulation.libelleDeLaPiece('Jean KORA'));
      expect(
        [
          for (final l in d.lignes)
            (l.compte, l.debitCentimes, l.creditCentimes),
        ],
        [('4191', 300000, 0), ('5711', 0, 300000)],
      );
    });

    test('acompte nul ou négatif : pas de pièce', () {
      for (final c in [0, -100]) {
        expect(
          pieceDeLAcompte(
            reservationId: 'r',
            mode: ModePaiementReservation.especes,
            acompteCentimes: c,
            dateIso: '2026-08-01',
          ),
          isNull,
        );
      }
    });
  });
}
