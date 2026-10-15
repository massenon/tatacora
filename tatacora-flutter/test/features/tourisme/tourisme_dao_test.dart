// `show Value` : sans restriction, `isNull` de Drift entre en collision avec
// le `isNull` de `matcher`, et l'ambiguïté casse la compilation du test.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/tourisme/domain/departs.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/reservation_tour.dart';

/// Le DAO de M9 contre une **vraie base Drift**.
///
/// Les refus se prouvent ici et pas seulement dans le domaine : c'est le DAO
/// qui lit le cumul déjà vendu, dans la transaction qui insère. Un contrôle
/// juste posé au-dessus d'une lecture fausse ne protège rien.
void main() {
  late AppDatabase db;
  late TourismeDao dao;

  final jour = DateTime(2026, 10, 12);

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = TourismeDao(db);

    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
          ),
        );
    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-2',
            nom: 'Chutes de Kota',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 3000,
            capaciteMax: 10,
          ),
        );
    await db
        .into(db.guidesLocal)
        .insert(GuidesLocalCompanion.insert(id: 'gui-1', nom: 'ADJOVI Paul'));
    await db
        .into(db.guidesLocal)
        .insert(GuidesLocalCompanion.insert(id: 'gui-2', nom: 'SOSSOU Amélie'));
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> reserver({
    int participants = 5,
    String circuitId = 'cir-1',
    String guideId = 'gui-1',
    DateTime? date,
  }) => dao.reserver(
    circuitId: circuitId,
    clientId: 'cli-1',
    guideId: guideId,
    dateCircuit: date ?? jour,
    nbParticipants: participants,
  );

  /* ================================================================== */
  group('RG-13 — le cumul est lu DANS la transaction qui insère', () {
    test(
      'trois groupes de 5 sur 12 places : le troisième est refusé',
      () async {
        await reserver();
        await reserver();

        await expectLater(
          reserver(),
          throwsA(
            isA<RefusTourisme>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('5 participants demandés'),
                contains('2 place(s) encore disponible(s)'),
              ),
            ),
          ),
        );

        // Et rien n'a été écrit : le refus n'insère pas « à moitié ».
        final lignes = await db.select(db.reservationsTourLocal).get();
        expect(lignes, hasLength(2));
      },
    );

    test('l\'annulation libère la place, et un nouveau groupe passe', () async {
      await reserver();
      await reserver();
      final lignes = await db.select(db.reservationsTourLocal).get();

      await dao.annulerReservation(lignes.first.id);

      // 12 - 5 = 7 places rendues disponibles : un groupe de 5 repasse.
      await reserver();

      final restantes = await dao.placesRestantes('cir-1', jour);
      expect(restantes, 2);
    });

    test('le cumul est propre à CHAQUE couple (circuit, date)', () async {
      await reserver(participants: 12);

      // Même circuit, autre jour : rien n'est consommé.
      await reserver(participants: 12, date: DateTime(2026, 10, 13));
      // Autre circuit, même jour : le guide change, sinon il serait déjà pris.
      await reserver(circuitId: 'cir-2', participants: 10, guideId: 'gui-2');

      expect(await dao.placesRestantes('cir-1', jour), 0);
      expect(await dao.placesRestantes('cir-1', DateTime(2026, 10, 13)), 0);
      expect(await dao.placesRestantes('cir-2', jour), 0);
    });

    test('zéro participant est refusé', () async {
      await expectLater(
        reserver(participants: 0),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            MessagesTourisme.participantsMinimum,
          ),
        ),
      );
    });
  });

  /* ================================================================== */
  group('Le guide — `guide_id` est NOT NULL (PA-51)', () {
    test('un départ a UN guide : le second groupe reprend le sien', () async {
      await reserver(guideId: 'gui-1');

      await expectLater(
        reserver(guideId: 'gui-2'),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            MessagesTourisme.guideDuDepartImpose,
          ),
        ),
      );

      // Avec le guide en place, le même groupe passe.
      await reserver(guideId: 'gui-1');
      expect(await dao.placesRestantes('cir-1', jour), 2);
    });

    test('un guide ne conduit pas deux circuits le même jour', () async {
      await reserver(circuitId: 'cir-1', guideId: 'gui-1');

      await expectLater(
        reserver(circuitId: 'cir-2', guideId: 'gui-1'),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            contains('12/10/2026'),
          ),
        ),
      );
    });

    test('le même guide peut conduire le même circuit un AUTRE jour', () async {
      // La portée du contrôle est la JOURNÉE : `duree` étant un libellé libre,
      // un circuit de plusieurs jours ne bloque que son jour de départ.
      await reserver(guideId: 'gui-1');
      await reserver(guideId: 'gui-1', date: DateTime(2026, 10, 13));

      final lignes = await db.select(db.reservationsTourLocal).get();
      expect(lignes, hasLength(2));
    });

    test('un guide inconnu est refusé', () async {
      await expectLater(
        reserver(guideId: 'gui-fantome'),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            MessagesTourisme.guideInexistant,
          ),
        ),
      );
    });

    test(
      'UC-39 — la réaffectation porte sur TOUTES les lignes actives du départ',
      () async {
        await reserver(participants: 4);
        await reserver(participants: 4);
        final lignes = await db.select(db.reservationsTourLocal).get();
        await dao.annulerReservation(lignes.first.id);

        final nombre = await dao.reaffecterGuide(
          circuitId: 'cir-1',
          date: jour,
          nouveauGuideId: 'gui-2',
        );

        // Une seule ligne active restait : l'annulée n'est pas réaffectée.
        expect(nombre, 1);

        final apres = await db.select(db.reservationsTourLocal).get();
        final annulee = apres.firstWhere((l) => l.id == lignes.first.id);
        final active = apres.firstWhere((l) => l.id != lignes.first.id);

        expect(active.guideId, 'gui-2');
        expect(annulee.guideId, 'gui-1');
      },
    );

    test('réaffecter un départ SANS réservation active est refusé', () async {
      await expectLater(
        dao.reaffecterGuide(
          circuitId: 'cir-1',
          date: jour,
          nouveauGuideId: 'gui-2',
        ),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            MessagesTourisme.departSansReservation,
          ),
        ),
      );
    });

    test('le guide du départ se LIT avant la saisie', () async {
      expect(await dao.guideDuDepart('cir-1', jour), isNull);

      await reserver(guideId: 'gui-2', circuitId: 'cir-2');
      final guide = await dao.guideDuDepart('cir-2', jour);

      expect(guide?.nom, 'SOSSOU Amélie');
    });
  });

  /* ================================================================== */
  group('Annuler — jamais supprimer (RG-02)', () {
    test('la ligne reste, son statut change', () async {
      await reserver();
      final avant = await db.select(db.reservationsTourLocal).get();

      await dao.annulerReservation(avant.single.id);

      final apres = await db.select(db.reservationsTourLocal).get();
      expect(apres, hasLength(1));
      expect(apres.single.statut, StatutReservationTour.annulee.cle);
    });

    test('annuler un DÉPART annule toutes ses lignes actives', () async {
      await reserver(participants: 4);
      await reserver(participants: 4);

      final nombre = await dao.annulerDepart(circuitId: 'cir-1', date: jour);

      expect(nombre, 2);
      final lignes = await db.select(db.reservationsTourLocal).get();
      expect(
        lignes.every((l) => l.statut == StatutReservationTour.annulee.cle),
        isTrue,
      );
    });

    test('une prestation CLÔTURÉE ne s\'annule plus', () async {
      await reserver();
      final ligne = (await db.select(db.reservationsTourLocal).get()).single;

      await (db.update(
        db.reservationsTourLocal,
      )..where((r) => r.id.equals(ligne.id))).write(
        ReservationsTourLocalCompanion(
          statut: Value(StatutReservationTour.terminee.cle),
        ),
      );

      await expectLater(
        dao.annulerReservation(ligne.id),
        throwsA(
          isA<RefusTourisme>().having(
            (e) => e.message,
            'message',
            MessagesTourisme.annulationApresCloture,
          ),
        ),
      );
    });
  });

  /* ================================================================== */
  group('Ce qui est écrit en base, et ce qui ne doit PAS l\'être', () {
    test(
      'statutSync vaut « local », jamais « en_attente_synchronisation »',
      () async {
        // ⚠ Le DÉFAUT du schéma est `en_attente_synchronisation` — le piège de
        // `MouvementsStockLocal` (PA-134). Aucune table de M9 ne part par une
        // file : laisser ce défaut décrirait une attente sans fin, et le
        // premier écran qui lirait la colonne annoncerait une synchronisation
        // qui n'aura jamais lieu.
        await reserver();
        final ligne = (await db.select(db.reservationsTourLocal).get()).single;

        expect(ligne.statutSync, TourismeDao.statutSyncLocal);
        expect(ligne.statutSync, isNot('en_attente_synchronisation'));
      },
    );

    test('la date est normalisée au JOUR', () async {
      await reserver(date: DateTime(2026, 10, 12, 16, 45));
      final ligne = (await db.select(db.reservationsTourLocal).get()).single;

      expect(ligne.dateCircuit, DateTime(2026, 10, 12));
    });

    test('chaque réservation reçoit un identifiant propre', () async {
      await reserver(participants: 3);
      await reserver(participants: 3);
      final lignes = await db.select(db.reservationsTourLocal).get();

      expect(lignes.map((l) => l.id).toSet(), hasLength(2));
    });
  });

  /* ================================================================== */
  group('La lecture de la fenêtre', () {
    test('la borne HAUTE est inclusive', () async {
      // Sans cela, un départ programmé le dernier jour de la fenêtre
      // disparaîtrait de la grille — et on le croirait annulé.
      await reserver(date: DateTime(2026, 10, 20));

      final lu = await dao.reservationsSurFenetre(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 20),
      );

      expect(lu.reservations, hasLength(1));
    });

    test('une ligne au statut INCONNU est écartée ET comptée', () async {
      await reserver();
      await db
          .into(db.reservationsTourLocal)
          .insert(
            ReservationsTourLocalCompanion.insert(
              id: 'r-cassee',
              circuitId: 'cir-1',
              clientId: 'cli-1',
              guideId: 'gui-1',
              dateCircuit: jour,
              nbParticipants: 3,
              statut: 'brouillon',
            ),
          );

      final lu = await dao.reservationsSurFenetre(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
      );

      // Écartée du calcul — lui prêter « réservée » fausserait la capacité.
      expect(lu.reservations, hasLength(1));
      // …mais comptée : la jeter en silence ferait disparaître une
      // réservation peut-être payée.
      expect(lu.illisibles, 1);
    });

    test('les libellés sont résolus — jamais un UUID à l\'écran', () async {
      await reserver();
      final lu = await dao.reservationsSurFenetre(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 31),
      );

      final r = lu.reservations.single;
      expect(r.circuitNom, 'Cascades de Tanougou');
      expect(r.guideNom, 'ADJOVI Paul');
      expect(r.clientNom, 'KORA');
      expect(r.prixUnitaire, 4500);
      expect(r.montant, 5 * 4500);
    });
  });

  /* ================================================================== */
  group('Le catalogue et le référentiel des guides', () {
    test(
      'une prestation est créée puis rééditée sur le même identifiant',
      () async {
        final cree = await dao.enregistrerCircuit(
          nom: 'Parc de la Pendjari',
          theme: 'Faune',
          zone: 'Pendjari',
          prix: 25000,
          capaciteMax: 7,
        );

        final modifie = await dao.enregistrerCircuit(
          id: cree.id,
          nom: 'Parc national de la Pendjari',
          theme: 'Faune',
          zone: 'Pendjari',
          prix: 27000,
          capaciteMax: 8,
        );

        expect(modifie.id, cree.id);
        final catalogue = await dao.circuits();
        expect(catalogue.where((c) => c.id == cree.id).single.prix, 27000);
        // Rééditer ne duplique pas : 2 circuits semés + 1 créé.
        expect(catalogue, hasLength(3));
      },
    );

    test('une capacité nulle est refusée', () async {
      // C'est la capacité qui sera opposée aux réservations : à zéro, aucune
      // réservation ne serait jamais possible, sans que rien ne le dise.
      await expectLater(
        dao.enregistrerCircuit(
          nom: 'Sans capacité',
          theme: 'Nature',
          zone: 'Atacora',
          prix: 1000,
          capaciteMax: 0,
        ),
        throwsA(isA<RefusTourisme>()),
      );
    });

    test('un guide peut être enregistré sur ce poste', () async {
      // Aucune route n'a jamais exposé le référentiel des guides : sans ce
      // chemin, `guides_local` resterait vide et AUCUNE réservation ne
      // pourrait être prise (`guide_id` est NOT NULL).
      await dao.enregistrerGuide(nom: 'TOKO Marcel', zoneCompetence: 'Atacora');

      final guides = await dao.guides();
      expect(guides.map((g) => g.nom), contains('TOKO Marcel'));
    });

    test('le prix est rendu en francs ENTIERS', () async {
      // La colonne locale est un `REAL` ; le domaine ne manipule que des
      // entiers — le XOF n'a pas de sous-unité en circulation.
      final circuits = await dao.circuits();
      expect(circuits.first.prix, isA<int>());
    });

    test('la durée est LUE, et jamais inventée', () async {
      // ⚠ Ce cas exigeait « elle reste nulle » et gelait la v9, où la colonne
      // n'existait pas. Depuis la v10 (14/09/2026) elle existe : le DAO doit
      // la RENDRE telle quelle — et continuer à rendre `null` quand rien n'est
      // enregistré. Inventer « 1 jour » ferait mesurer l'invention par
      // l'indicateur « Durée indéterminée ».
      final avant = await dao.circuits();
      expect(avant.every((c) => c.duree == null), isTrue);

      final c = avant.first;
      await dao.enregistrerCircuit(
        id: c.id,
        nom: c.nom,
        theme: c.theme,
        zone: c.zone,
        prix: c.prix,
        capaciteMax: c.capaciteMax,
        duree: 'Plusieurs jours',
      );

      final apres = await dao.circuits();
      expect(apres.firstWhere((x) => x.id == c.id).duree, 'Plusieurs jours');
    });
  });
}
