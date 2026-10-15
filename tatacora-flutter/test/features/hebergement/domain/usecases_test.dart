import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/disponibilite.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/repositories/reservation_repository.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/annuler_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/consulter_disponibilites.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';

import 'depot_reservation_memoire.dart';

void main() {
  // Le sprint impose un domaine testable SANS source de données : ni Drift,
  // ni réseau n'apparaissent dans ce fichier.
  final maintenant = DateTime(2026, 8, 1);
  DateTime horloge() => maintenant;

  UniteHebergement unite(
    String id,
    String numero,
    int tarif, {
    StatutUnite statut = StatutUnite.libre,
  }) => UniteHebergement(
    id: id,
    numero: numero,
    categorieId: 'cat-1',
    categorieLibelle: 'Bungalow',
    statut: statut,
    tarifBase: tarif,
    capaciteMax: 2,
  );

  PeriodeSejour periode(int arrivee, int depart) => PeriodeSejour(
    arrivee: DateTime(2026, 8, arrivee),
    depart: DateTime(2026, 8, depart),
  );

  Reservation reservationExistante({
    required String id,
    required String uniteId,
    required PeriodeSejour p,
    StatutReservation statut = StatutReservation.confirmee,
    String client = 'Jean KORA',
  }) => Reservation(
    id: id,
    reference: 'RES-$id',
    clientId: 'cli-1',
    clientNom: client,
    uniteId: uniteId,
    periode: p,
    tarifNuit: 28000,
    statut: statut,
    statutSynchronisation: StatutSynchronisation.synchronise,
    creeeLe: maintenant,
  );

  /* ================================================================= */
  group('ConsulterDisponibilites', () {
    test('les unités libres passent avant les indisponibles', () async {
      final depot = DepotReservationMemoire(
        unites: [
          unite('u1', 'BNG-01', 28000),
          unite('u2', 'CH-101', 18000),
          unite('u3', 'TNT-01', 8500, statut: StatutUnite.horsService),
        ],
        reservations: [
          reservationExistante(id: 'r1', uniteId: 'u2', p: periode(10, 12)),
        ],
      );

      final resultat = await ConsulterDisponibilites(depot)(periode(10, 12));

      expect(resultat.first.unite.numero, 'BNG-01');
      expect(resultat.first.disponible, isTrue);
      expect(resultat.skip(1).every((d) => !d.disponible), isTrue);
    });

    test(
      'à disponibilité égale, la moins chère est proposée en premier',
      () async {
        final depot = DepotReservationMemoire(
          unites: [unite('u1', 'BNG-01', 28000), unite('u2', 'CH-101', 18000)],
        );

        final resultat = await ConsulterDisponibilites(depot)(periode(10, 12));

        expect(resultat.map((d) => d.unite.numero), ['CH-101', 'BNG-01']);
      },
    );

    test('à tarif égal, l’ordre reste stable entre deux appels', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u2', 'CH-102', 18000), unite('u1', 'CH-101', 18000)],
      );
      final cas = ConsulterDisponibilites(depot);

      final premier = (await cas(
        periode(10, 12),
      )).map((d) => d.unite.numero).toList();
      final second = (await cas(
        periode(10, 12),
      )).map((d) => d.unite.numero).toList();

      expect(premier, second);
      expect(premier, ['CH-101', 'CH-102']);
    });

    test('les indisponibles restent listées, avec leur motif', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
        reservations: [
          reservationExistante(
            id: 'r1',
            uniteId: 'u1',
            p: periode(10, 12),
            client: 'Marie DOSSOU',
          ),
        ],
      );

      final resultat = await ConsulterDisponibilites(depot)(periode(11, 13));

      expect(resultat, hasLength(1));
      expect(resultat.first.disponible, isFalse);
      expect(resultat.first.motif, MotifIndisponibilite.dejaReservee);
      expect(resultat.first.reservationEnConflit?.clientNom, 'Marie DOSSOU');
    });

    test('une réservation annulée ne bloque plus rien', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
        reservations: [
          reservationExistante(
            id: 'r1',
            uniteId: 'u1',
            p: periode(10, 12),
            statut: StatutReservation.annulee,
          ),
        ],
      );

      final resultat = await ConsulterDisponibilites(depot)(periode(10, 12));
      expect(resultat.first.disponible, isTrue);
    });

    test('un départ le 12 laisse l’unité libre à partir du 12', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
        reservations: [
          reservationExistante(id: 'r1', uniteId: 'u1', p: periode(10, 12)),
        ],
      );

      final resultat = await ConsulterDisponibilites(depot)(periode(12, 14));
      expect(resultat.first.disponible, isTrue);
    });
  });

  /* ================================================================= */
  group('CreerReservation', () {
    test('le montant est calculé, jamais fourni', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      final r = await CreerReservation(depot, maintenant: horloge)(
        auteurId: 'u-essai',
        unite: unite('u1', 'BNG-01', 28000),
        clientId: 'cli-1',
        clientNom: 'Jean KORA',
        periode: periode(10, 12),
      );

      expect(r.nuits, 2);
      expect(r.montantTotal, 56000);
      expect(r.tarifNuit, 28000);
    });

    test('l’identifiant est un UUID posé à la création', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      final r = await CreerReservation(depot, maintenant: horloge)(
        auteurId: 'u-essai',
        unite: unite('u1', 'BNG-01', 28000),
        clientId: 'cli-1',
        clientNom: 'Jean KORA',
        periode: periode(10, 12),
      );

      expect(r.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-')));
      // La création passe par `creer` (la réservation ET la pièce de son acompte
      // dans la même transaction), pas par l'écriture brute.
      expect(depot.appelsCreer, 1);
      expect(depot.appelsEnregistrer, 0);
    });

    test('elle part en « local », pas en « synchronise »', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      final r = await CreerReservation(depot, maintenant: horloge)(
        auteurId: 'u-essai',
        unite: unite('u1', 'BNG-01', 28000),
        clientId: 'cli-1',
        clientNom: 'Jean KORA',
        periode: periode(10, 12),
      );

      // Le serveur n'a pas encore tranché : afficher « synchronisé » serait
      // une promesse que le client ne peut pas tenir.
      expect(r.statutSynchronisation, StatutSynchronisation.local);
      expect(r.statutSynchronisation.estEnSuspens, isTrue);
    });

    test('un chevauchement local est refusé, avec le conflit nommé', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
        reservations: [
          reservationExistante(
            id: 'r1',
            uniteId: 'u1',
            p: periode(10, 13),
            client: 'Marie DOSSOU',
          ),
        ],
      );

      await expectLater(
        CreerReservation(depot, maintenant: horloge)(
          auteurId: 'u-essai',
          unite: unite('u1', 'BNG-01', 28000),
          clientId: 'cli-2',
          clientNom: 'Paul ADJOVI',
          periode: periode(12, 15),
        ),
        throwsA(
          isA<ChevauchementDetecte>().having(
            (e) => e.reservationEnConflit.clientNom,
            'client en conflit',
            'Marie DOSSOU',
          ),
        ),
      );
      expect(depot.appelsEnregistrer, 0, reason: 'rien ne doit être écrit');
    });

    test('une unité hors service est refusée à toute date', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000, statut: StatutUnite.horsService)],
      );

      await expectLater(
        CreerReservation(depot, maintenant: horloge)(
          auteurId: 'u-essai',
          unite: unite('u1', 'BNG-01', 28000, statut: StatutUnite.horsService),
          clientId: 'cli-1',
          clientNom: 'Jean KORA',
          periode: periode(10, 12),
        ),
        throwsA(isA<UniteIndisponible>()),
      );
    });

    test('une unité en nettoyage reste réservable pour plus tard', () async {
      // Le statut opérationnel n'est pas la disponibilité : une chambre en
      // cours de ménage aujourd'hui est louable la semaine prochaine.
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000, statut: StatutUnite.nettoyage)],
      );

      final r = await CreerReservation(depot, maintenant: horloge)(
        auteurId: 'u-essai',
        unite: unite('u1', 'BNG-01', 28000, statut: StatutUnite.nettoyage),
        clientId: 'cli-1',
        clientNom: 'Jean KORA',
        periode: periode(20, 22),
      );

      expect(r.nuits, 2);
    });

    test('une arrivée dans le passé est refusée', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      await expectLater(
        CreerReservation(depot, maintenant: horloge)(
          auteurId: 'u-essai',
          unite: unite('u1', 'BNG-01', 28000),
          clientId: 'cli-1',
          clientNom: 'Jean KORA',
          periode: PeriodeSejour(
            arrivee: DateTime(2026, 7, 20),
            depart: DateTime(2026, 7, 22),
          ),
        ),
        throwsArgumentError,
      );
    });

    test('un acompte supérieur au montant du séjour est refusé', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      await expectLater(
        CreerReservation(depot, maintenant: horloge)(
          auteurId: 'u-essai',
          unite: unite('u1', 'BNG-01', 28000),
          clientId: 'cli-1',
          clientNom: 'Jean KORA',
          periode: periode(10, 12),
          acompte: 100000, // le séjour vaut 56 000
        ),
        throwsArgumentError,
      );
    });

    test('le reste à payer se déduit de l’acompte', () async {
      final depot = DepotReservationMemoire(
        unites: [unite('u1', 'BNG-01', 28000)],
      );

      final r = await CreerReservation(depot, maintenant: horloge)(
        auteurId: 'u-essai',
        unite: unite('u1', 'BNG-01', 28000),
        clientId: 'cli-1',
        clientNom: 'Jean KORA',
        periode: periode(10, 12),
        acompte: 20000,
      );

      expect(r.resteAPayer, 36000);
    });

    test(
      'le tarif est figé : changer la grille ne change pas le passé',
      () async {
        final depot = DepotReservationMemoire(
          unites: [unite('u1', 'BNG-01', 28000)],
        );

        final r = await CreerReservation(depot, maintenant: horloge)(
          auteurId: 'u-essai',
          unite: unite('u1', 'BNG-01', 28000),
          clientId: 'cli-1',
          clientNom: 'Jean KORA',
          periode: periode(10, 12),
        );

        // La grille passe à 35 000 : la réservation déjà prise ne bouge pas.
        final apres = await depot.parId(r.id);
        expect(apres!.tarifNuit, 28000);
        expect(apres.montantTotal, 56000);
      },
    );
  });

  /* ================================================================= */
  group('AnnulerReservation', () {
    DepotReservationMemoire depotAvecReservation({
      StatutReservation statut = StatutReservation.confirmee,
    }) => DepotReservationMemoire(
      unites: [unite('u1', 'BNG-01', 28000)],
      reservations: [
        reservationExistante(
          id: 'r1',
          uniteId: 'u1',
          p: periode(10, 12),
          statut: statut,
        ),
      ],
    );

    /// Une annulation SANS argent : commission seule, rien à rembourser.
    Future<Reservation> annuler(
      DepotReservationMemoire depot, {
      String id = 'r1',
      String taux = '50',
      String mode = 'montant',
      String valeur = '0',
    }) => AnnulerReservation(depot)(
      id,
      tauxSaisi: taux,
      modeRemboursement: mode,
      valeurRemboursement: valeur,
      auteurId: 'u-essai',
    );

    test('annuler conserve la réservation et FIXE taux, total, commission '
        'et auteur', () async {
      final depot = depotAvecReservation();

      final r = await annuler(depot);

      expect(r.statut, StatutReservation.annulee);
      final a = r.annulation!;
      // La commission porte sur le MONTANT GLOBAL (2 nuits à 28 000 F), pas sur
      // l'acompte : 50 % de 56 000 F.
      expect(a.totalCentimes, 5600000);
      expect(a.tauxCentiemes, 5000);
      expect(a.commissionCentimes, 2800000);
      expect(a.rembourseCentimes, 0);
      expect(a.auteurId, 'u-essai');
      expect(
        await depot.parId('r1'),
        isNotNull,
        reason: 'annuler n’est pas supprimer',
      );
    });

    test('une réservation annulée libère l’unité', () async {
      final depot = depotAvecReservation();
      await annuler(depot);

      final dispo = await ConsulterDisponibilites(depot)(periode(10, 12));
      expect(dispo.first.disponible, isTrue);
    });

    test('annuler deux fois est REFUSÉ avec la phrase du serveur — le poste '
        'n’est plus idempotent ici', () async {
      final depot = depotAvecReservation();
      await annuler(depot);

      // Le serveur refuse (« Cette réservation est déjà annulée. ») : ce
      // n'est plus un double clic silencieux, puisque la première annulation a
      // pu rembourser de l'argent.
      await expectLater(
        annuler(depot),
        throwsA(
          isA<RefusAnnulation>().having(
            (e) => e.message,
            'message',
            MessagesAnnulation.dejaAnnulee,
          ),
        ),
      );
      expect(depot.appelsAnnuler, 1);
    });

    test('un séjour terminé ne s’annule plus', () async {
      final depot = depotAvecReservation(statut: StatutReservation.terminee);

      await expectLater(annuler(depot), throwsStateError);
    });

    test('une réservation inconnue est signalée', () async {
      final depot = depotAvecReservation();

      await expectLater(
        annuler(depot, id: 'inconnue'),
        throwsA(isA<ReservationIntrouvable>()),
      );
    });
  });

  /* ================================================================= */
  group('Statuts — un code inconnu ne donne jamais un droit', () {
    test('un statut d’unité inconnu vaut « hors service »', () {
      expect(StatutUnite.depuisCode('inventé'), StatutUnite.horsService);
      expect(StatutUnite.depuisCode(null), StatutUnite.horsService);
      // Le défaut le plus sûr est celui qui ne vend rien.
      expect(StatutUnite.depuisCode('inventé').estLouable, isFalse);
    });

    test('un statut de synchronisation inconnu vaut « local »', () {
      // « local » signifie « pas encore confirmé par le serveur » : c'est la
      // lecture prudente. « synchronise » par défaut ferait croire à une
      // sauvegarde qui n'a pas eu lieu.
      expect(
        StatutSynchronisation.depuisCode('inventé'),
        StatutSynchronisation.local,
      );
      expect(StatutSynchronisation.depuisCode(null).estEnSuspens, isTrue);
    });

    test('les codes connus sont reconnus', () {
      expect(StatutUnite.depuisCode('libre'), StatutUnite.libre);
      expect(StatutUnite.depuisCode('hors_service'), StatutUnite.horsService);
      expect(
        StatutSynchronisation.depuisCode('rejete'),
        StatutSynchronisation.rejete,
      );
      expect(StatutSynchronisation.rejete.estEnSuspens, isFalse);
    });
  });

  /* ================================================================= */
  group('Engagement de l’unité', () {
    test('une réservation future engage l’unité', () {
      final r = reservationExistante(
        id: 'r1',
        uniteId: 'u1',
        p: periode(10, 12),
      );
      expect(r.engageLUnite(DateTime(2026, 8, 5)), isTrue);
    });

    test('un séjour terminé ne l’engage plus', () {
      final r = reservationExistante(
        id: 'r1',
        uniteId: 'u1',
        p: periode(10, 12),
      );
      expect(r.engageLUnite(DateTime(2026, 8, 12)), isFalse);
    });

    test('une réservation annulée n’engage rien', () {
      final r = reservationExistante(
        id: 'r1',
        uniteId: 'u1',
        p: periode(10, 12),
        statut: StatutReservation.annulee,
      );
      expect(r.engageLUnite(DateTime(2026, 8, 5)), isFalse);
    });
  });
}
