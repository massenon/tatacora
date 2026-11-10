import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/catalogue_services_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';

import '../facturation/support/outils_encaissement.dart'
    show creerClient, semerReservation;

/// RÉSERVATION MULTI-CHAMBRES (décision du PO du 10/11/2026 : « pour UNE SEULE réservation un
/// client peut réserver UNE ou PLUSIEURS chambres »). La première chambre vit sur `unite_id`,
/// les suivantes sont des lignes d'hébergement : ce que ces cas tiennent, sur une VRAIE base.
void main() {
  late AppDatabase db;
  late String clientId;

  setUp(() async {
    db = AppDatabase.enMemoire();
    clientId = (await creerClient(db)).id;
    await semerReservation(db, id: 'r1', clientId: clientId, total: 56000);
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-2',
            categorieId: 'cat-1',
            numero: 'BNG-02',
            statut: 'libre',
          ),
        );
    // La réservation r1 porte une SECONDE chambre : BNG-02 (tarif de nuit 40 000).
    final r = (await ReservationDao(db).parId('r1'))!;
    await ReservationDao(db).enregistrer(
      Reservation(
        id: r.id,
        reference: r.reference,
        clientId: r.clientId,
        clientNom: r.clientNom,
        uniteId: r.uniteId,
        periode: r.periode,
        tarifNuit: r.tarifNuit,
        statut: r.statut,
        statutSynchronisation: r.statutSynchronisation,
        creeeLe: r.creeeLe,
        acompte: r.acompte,
        typeClient: r.typeClient,
        canal: r.canal,
        lignes: [
          ...r.lignes,
          const LigneService(
            id: 'l-r1-2',
            service: ServiceReservation.hebergement,
            itemId: 'u-2',
            libelle: 'Studio (BNG-02)',
            prixUnitaire: 40000,
            quantite: 2,
          ),
        ],
      ),
    );
  });

  tearDown(() => db.close());

  test('la réservation porte DEUX chambres et son total les somme', () async {
    final r = (await ReservationDao(db).parId('r1'))!;
    expect(r.uniteIds, ['u-1', 'u-2']);
    expect(r.sousTotalServices, 56000 + 80000);
  });

  test('la chambre supplémentaire est OCCUPÉE pour la disponibilité', () async {
    final depot = ReservationRepositoryLocal(ReservationDao(db));
    final dispo = await depot.consulterDisponibilites(
      PeriodeSejour(
        arrivee: DateTime(2026, 10, 20),
        depart: DateTime(2026, 10, 22),
      ),
    );
    final bng2 = dispo.firstWhere((d) => d.unite.id == 'u-2');
    expect(bng2.disponible, isFalse);
    expect(bng2.reservationEnConflit?.id, 'r1');

    // Le jour du départ, elle est libre (bornes semi-ouvertes).
    final apres = await depot.consulterDisponibilites(
      PeriodeSejour(
        arrivee: DateTime(2026, 10, 22),
        depart: DateTime(2026, 10, 24),
      ),
    );
    expect(apres.firstWhere((d) => d.unite.id == 'u-2').disponible, isTrue);
  });

  test(
    'le catalogue ne propose pas la chambre supplémentaire déjà prise',
    () async {
      final rayons = await CatalogueServicesDao(
        db,
      ).rayons(arrivee: DateTime(2026, 10, 20), depart: DateTime(2026, 10, 22));
      final chambres = rayons.firstWhere(
        (r) => r.service == ServiceReservation.hebergement,
      );
      final bng2 = chambres.options.firstWhere((c) => c.id == 'u-2');
      expect(bng2.disponible, isFalse);
    },
  );

  test(
    'l\'arrivée occupe TOUTES les chambres, le départ les passe au ménage',
    () async {
      final sejours = SejourDao(
        db,
        maintenant: () => DateTime(2026, 10, 20, 14),
      );
      await sejours.checkin('r1');
      final unites = {
        for (final u in await db.select(db.unitesHebergementLocal).get())
          u.id: u.statut,
      };
      expect(unites['u-1'], 'occupee');
      expect(unites['u-2'], 'occupee');
      expect(await sejours.reservationAuSejourEnCoursDeLUnite('u-2'), 'r1');

      await sejours.checkout('r1');
      final apres = {
        for (final u in await db.select(db.unitesHebergementLocal).get())
          u.id: u.statut,
      };
      expect(apres['u-1'], 'nettoyage');
      expect(apres['u-2'], 'nettoyage');
    },
  );

  test(
    "l'envoi porte la chambre SUPPLÉMENTAIRE comme ligne hébergement, jamais la principale",
    () async {
      // Une création à deux chambres, par le chemin d'écriture réel (`creer`) : la file reçoit
      // `lignes` = la seule chambre SUPPLÉMENTAIRE (la principale vit sur `unite_id`).
      await ReservationDao(db).creer(
        Reservation(
          id: 'r2',
          reference: 'LOC-r2',
          clientId: clientId,
          clientNom: 'Client',
          uniteId: 'u-1',
          periode: PeriodeSejour(
            arrivee: DateTime(2026, 11, 20),
            depart: DateTime(2026, 11, 22),
          ),
          tarifNuit: 28000,
          statut: StatutReservation.enAttente,
          statutSynchronisation: StatutSynchronisation.local,
          creeeLe: DateTime(2026, 11, 1),
          lignes: const [
            LigneService(
              id: 'l-r2-1',
              service: ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow (BNG-01)',
              prixUnitaire: 28000,
              quantite: 2,
            ),
            LigneService(
              id: 'l-r2-2',
              service: ServiceReservation.hebergement,
              itemId: 'u-2',
              libelle: 'Bungalow (BNG-02)',
              prixUnitaire: 28000,
              quantite: 2,
            ),
          ],
        ),
        auteurId: 'u-essai',
      );

      final operations = await OperationsSyncDao(db).operations(entiteId: 'r2');
      final creation = jsonDecode(operations.first.payload) as Map;
      final lignes = (creation['lignes'] as List).cast<Map>();
      expect(lignes.map((l) => l['source_id']), ['u-2']);
      expect(lignes.single['service'], 'hebergement');
      expect(creation['unite_id'], 'u-1');
    },
  );
}
