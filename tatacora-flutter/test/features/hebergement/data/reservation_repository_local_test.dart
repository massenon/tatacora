// `drift` exporte `isNull` et `isNotNull` comme constructeurs d'expression SQL,
// homonymes des matchers de `flutter_test`. On masque les siens : ici on ecrit
// des assertions, pas des requetes. Le meme conflit avait deja ete rencontre au
// Sprint 0 sur `isNull`.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/disponibilite.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/repositories/reservation_repository.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/annuler_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/consulter_disponibilites.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';

import '../../comptabilite/support/outils_comptabilite.dart'
    show auteurEssai, semerAuteur;

/// Persistance locale — vraie base SQLite en mémoire, aucun réseau.
///
/// Le jour 2-3 du sprint demande de « créer une réservation en base locale et
/// la relire, sans qu'aucun code réseau n'existe ». Ces tests le vérifient
/// contre le moteur réel, pas contre un double : c'est la seule façon de
/// prouver que le SQL de chevauchement dit bien la même chose que
/// `PeriodeSejour.chevauche`.
void main() {
  late AppDatabase db;
  late ReservationDao dao;
  late ReservationRepositoryLocal depot;

  final maintenant = DateTime(2026, 8, 1);
  DateTime horloge() => maintenant;

  PeriodeSejour periode(int arrivee, int depart) => PeriodeSejour(
    arrivee: DateTime(2026, 8, arrivee),
    depart: DateTime(2026, 8, depart),
  );

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = ReservationDao(db);
    depot = ReservationRepositoryLocal(dao);
    // L'annulation nomme celui qui annule (RG-15, clé étrangère réelle).
    await db.customStatement('SELECT 1');
    await semerAuteur(db);

    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-bungalow',
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          ),
        );
    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-chambre',
            libelle: 'Chambre',
            capaciteMax: 2,
            tarifBase: 18000,
          ),
        );

    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-bng-01',
            categorieId: 'cat-bungalow',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-ch-101',
            categorieId: 'cat-chambre',
            numero: 'CH-101',
            statut: 'libre',
          ),
        );
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-hs',
            categorieId: 'cat-chambre',
            numero: 'CH-999',
            statut: 'hors_service',
          ),
        );

    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-2',
            nom: 'DOSSOU',
            prenom: const Value('Marie'),
            telephone: '+229 01 00 00 00 02',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() async => db.close());

  Future<UniteHebergement> unite(String numero) async =>
      (await depot.unites()).firstWhere((u) => u.numero == numero);

  /// [quand] permet de dater explicitement la creation : l'horloge du test est
  /// figee, sans quoi deux reservations porteraient le meme instant et leur
  /// ordre serait indefini.
  Future<Reservation> creer({
    String numeroUnite = 'BNG-01',
    String clientId = 'cli-1',
    String clientNom = 'Jean KORA',
    required PeriodeSejour p,
    int acompte = 0,
    DateTime? quand,
  }) async =>
      CreerReservation(
        depot,
        maintenant: quand == null ? horloge : () => quand,
      )(
        unite: await unite(numeroUnite),
        clientId: clientId,
        clientNom: clientNom,
        periode: p,
        acompte: acompte,
        auteurId: auteurEssai,
      );

  /// Une annulation sans argent : commission de 50 %, rien à rembourser.
  Future<Reservation> annuler(String id) => AnnulerReservation(depot)(
    id,
    tauxSaisi: '50',
    modeRemboursement: 'montant',
    valeurRemboursement: '0',
    auteurId: auteurEssai,
  );

  /* ================================================================== */
  group('Le parc, lu depuis la base', () {
    test(
      'les unités portent le libellé et le tarif de leur catégorie',
      () async {
        final parc = await depot.unites();

        expect(parc, hasLength(3));
        final bng = parc.firstWhere((u) => u.numero == 'BNG-01');
        expect(bng.categorieLibelle, 'Bungalow');
        expect(bng.tarifBase, 28000);
        expect(bng.capaciteMax, 2);
      },
    );

    test('un statut inconnu en base ne rend pas l’unité vendable', () async {
      await db
          .into(db.unitesHebergementLocal)
          .insert(
            UnitesHebergementLocalCompanion.insert(
              id: 'u-bizarre',
              categorieId: 'cat-chambre',
              numero: 'CH-000',
              statut: 'valeur_jamais_vue',
            ),
          );

      final u = (await depot.unites()).firstWhere((x) => x.numero == 'CH-000');
      expect(u.statut, StatutUnite.horsService);
      expect(u.statut.estLouable, isFalse);
    });
  });

  /* ================================================================== */
  group('Écriture puis relecture', () {
    test('une réservation créée se relit à l’identique', () async {
      final creee = await creer(p: periode(10, 12), acompte: 20000);

      final relue = await depot.parId(creee.id);

      expect(relue, isNotNull);
      expect(relue!.id, creee.id);
      expect(relue.clientNom, 'KORA Jean');
      expect(relue.nuits, 2);
      expect(relue.tarifNuit, 28000);
      expect(relue.montantTotal, 56000);
      expect(relue.acompte, 20000);
      expect(relue.resteAPayer, 36000);
    });

    test('elle naît « local », jamais « synchronise »', () async {
      final creee = await creer(p: periode(10, 12));
      final relue = await depot.parId(creee.id);

      // Le défaut de colonne a été ramené de 'synchronise' à 'local' au
      // schéma v2 : une réservation qui n'a jamais touché le serveur ne doit
      // pas se déclarer synchronisée.
      expect(relue!.statutSynchronisation, StatutSynchronisation.local);
    });

    test(
      'le tarif est figé : changer la grille ne réécrit pas le passé',
      () async {
        final creee = await creer(p: periode(10, 12));

        await (db.update(
          db.categoriesHebergementLocal,
        )..where((c) => c.id.equals('cat-bungalow'))).write(
          const CategoriesHebergementLocalCompanion(tarifBase: Value(35000)),
        );

        final relue = await depot.parId(creee.id);
        expect(relue!.tarifNuit, 28000, reason: 'tarif figé à la réservation');
        expect(relue.montantTotal, 56000);
        expect(
          (await unite('BNG-01')).tarifBase,
          35000,
          reason: 'la grille, elle, a bien changé',
        );
      },
    );

    test(
      'les réservations sortent de la plus récente à la plus ancienne',
      () async {
        final a = await creer(
          p: periode(10, 12),
          quand: DateTime(2026, 8, 1, 9),
        );
        final b = await creer(
          numeroUnite: 'CH-101',
          p: periode(10, 12),
          quand: DateTime(2026, 8, 1, 14),
        );

        final liste = await depot.reservations();
        expect(liste.map((r) => r.id).toList(), [b.id, a.id]);
      },
    );

    test('deux créations du même instant gardent un ordre stable', () async {
      // Sans départage explicite, SQLite est libre de renvoyer l'un ou l'autre
      // en premier, et la liste « bouge » d'un rafraîchissement au suivant.
      final memeInstant = DateTime(2026, 8, 1, 10);
      await creer(p: periode(10, 12), quand: memeInstant);
      await creer(
        numeroUnite: 'CH-101',
        p: periode(10, 12),
        quand: memeInstant,
      );

      final premier = (await depot.reservations()).map((r) => r.id).toList();
      final second = (await depot.reservations()).map((r) => r.id).toList();
      expect(premier, second);
    });
  });

  /* ================================================================== */
  // ⚠ LE GROUPE « File de synchronisation » A ÉTÉ RETIRÉ ICI le 14/09/2026,
  // avec la file elle-même (décision « zéro réseau » du Product Owner).
  //
  // Ses cinq cas gardaient des garanties qui n'ont plus d'objet, mais qui
  // méritent d'être nommées — le jour où un serveur reviendra, elles
  // reviendront avec lui :
  //
  //  1. toute écriture déposait une opération en file, sinon la réservation
  //     ne partait jamais — perdue sans erreur, découverte des semaines plus
  //     tard par un client muni d'une confirmation ;
  //  2. `uuid_operation` identifiait la TENTATIVE, `entite_id` l'enregistrement
  //     métier. Les confondre cassait l'idempotence : la première version
  //     réutilisait l'identifiant de la réservation, l'annulation devait le
  //     suffixer, et « {uuid}:annulation » n'est pas un UUID — le serveur
  //     rejetait le LOT ENTIER en 422 ;
  //  3. la charge utile portait des dates SANS heure : une heure exposait à un
  //     décalage de fuseau qui déplaçait le séjour d'un jour ;
  //  4. une annulation AJOUTAIT son opération sans écraser la création, sinon
  //     un poste hors ligne depuis la veille poussait une modification portant
  //     sur une réservation inconnue du serveur.
  //
  // Ce qui reste vérifiable — que la réservation écrite est bien celle qu'on
  // relit — est conservé ci-dessous.
  group('Modification', () {
    test('la modification enregistrée est bien celle qu’on relit', () async {
      final creee = await creer(p: periode(10, 12));

      await depot.modifier(
        Reservation(
          id: creee.id,
          reference: creee.reference,
          clientId: creee.clientId,
          clientNom: creee.clientNom,
          uniteId: creee.uniteId,
          periode: creee.periode,
          tarifNuit: creee.tarifNuit,
          statut: creee.statut,
          statutSynchronisation: StatutSynchronisation.local,
          creeeLe: creee.creeeLe,
          acompte: 15000,
          lignes: creee.lignes,
        ),
      );

      // UNE seule réservation en base : une modification qui insérerait une
      // seconde ligne laisserait deux réservations sur la même chambre, et le
      // contrôle de chevauchement les verrait se contredire.
      final enBase = await db.select(db.reservationsLocal).get();
      expect(enBase, hasLength(1));

      final relue = await depot.parId(creee.id);
      expect(relue!.acompte, 15000);
      expect(relue.statutSynchronisation, StatutSynchronisation.local);
    });

    test('chaque réservation est écrite, et n’attend RIEN', () async {
      // ⚠ Ce cas vérifiait « autant d'entrées de file que de réservations ».
      // La file a été supprimée le 14/09/2026 (zéro réseau) : son sujet
      // n'existe plus. Le supprimer aurait retiré un cas sans le remplacer —
      // ce qui reste à garantir, c'est que l'écriture est complète ET que rien
      // ne se dit en attente d'un départ qui n'aura pas lieu.
      await creer(p: periode(10, 12));
      await creer(numeroUnite: 'CH-101', p: periode(15, 17));

      final reservations = await db.select(db.reservationsLocal).get();
      expect(reservations.length, 2);

      // `local` — jamais `en_attente`. Un poste sans serveur qui afficherait
      // « en attente de synchronisation » annoncerait une attente sans fin
      // (PA-59/60/61), et c'est précisément pourquoi la file a été retirée
      // plutôt que laissée à grossir.
      for (final r in reservations) {
        expect(r.statutSync, StatutSynchronisation.local.code);
      }
    });
  });

  /* ================================================================== */
  group('Disponibilité — le SQL dit la même chose que le domaine', () {
    test(
      'une unité réservée n’est plus proposée sur la même période',
      () async {
        await creer(
          p: periode(10, 13),
          clientId: 'cli-2',
          clientNom: 'Marie DOSSOU',
        );

        final dispo = await ConsulterDisponibilites(depot)(periode(11, 14));
        final bng = dispo.firstWhere((d) => d.unite.numero == 'BNG-01');

        expect(bng.disponible, isFalse);
        expect(bng.motif, MotifIndisponibilite.dejaReservee);
        expect(bng.reservationEnConflit?.clientNom, 'DOSSOU Marie');
      },
    );

    /// Le cas décisif, en SQL cette fois : un départ le 12 et une arrivée le
    /// 12 ne se chevauchent pas. Une inégalité stricte mal placée dans la
    /// requête refuserait des réservations parfaitement valides.
    test('un départ le 12 laisse l’unité libre à partir du 12', () async {
      await creer(p: periode(10, 12));

      final dispo = await ConsulterDisponibilites(depot)(periode(12, 14));
      expect(
        dispo.firstWhere((d) => d.unite.numero == 'BNG-01').disponible,
        isTrue,
      );
    });

    test('une arrivée le 12 laisse l’unité libre jusqu’au 12', () async {
      await creer(p: periode(12, 14));

      final dispo = await ConsulterDisponibilites(depot)(periode(10, 12));
      expect(
        dispo.firstWhere((d) => d.unite.numero == 'BNG-01').disponible,
        isTrue,
      );
    });

    test(
      'une unité hors service est indisponible quelle que soit la date',
      () async {
        final dispo = await ConsulterDisponibilites(depot)(periode(20, 22));
        final hs = dispo.firstWhere((d) => d.unite.numero == 'CH-999');

        expect(hs.disponible, isFalse);
        expect(hs.motif, MotifIndisponibilite.horsService);
      },
    );

    test('une réservation annulée libère l’unité', () async {
      final creee = await creer(p: periode(10, 12));
      await annuler(creee.id);

      final dispo = await ConsulterDisponibilites(depot)(periode(10, 12));
      expect(
        dispo.firstWhere((d) => d.unite.numero == 'BNG-01').disponible,
        isTrue,
      );
    });

    test('le conflit annoncé est le plus ancien, pas un au hasard', () async {
      await creer(
        p: periode(10, 12),
        clientId: 'cli-2',
        clientNom: 'Marie DOSSOU',
      );
      await creer(p: periode(13, 15));

      final dispo = await ConsulterDisponibilites(depot)(periode(9, 20));
      final bng = dispo.firstWhere((d) => d.unite.numero == 'BNG-01');

      // C'est ce nom que le réceptionniste cite au client : celui qui a la
      // priorité, pas celui que la base a renvoyé en premier.
      expect(bng.reservationEnConflit?.clientNom, 'DOSSOU Marie');
    });
  });

  /* ================================================================== */
  group('Le chevauchement est refusé de bout en bout', () {
    test('créer sur une unité déjà prise lève ChevauchementDetecte', () async {
      await creer(
        p: periode(10, 13),
        clientId: 'cli-2',
        clientNom: 'Marie DOSSOU',
      );

      await expectLater(
        creer(p: periode(12, 15)),
        throwsA(isA<ChevauchementDetecte>()),
      );

      // Et rien n'a été écrit : la seule réservation en base reste la
      // première. Un refus RG-01 qui laisserait une ligne derrière lui
      // bloquerait l'unité sans que personne puisse dire pourquoi.
      expect(await db.select(db.reservationsLocal).get(), hasLength(1));
    });

    test('la même période sur une AUTRE unité passe', () async {
      await creer(p: periode(10, 13));
      final seconde = await creer(numeroUnite: 'CH-101', p: periode(10, 13));

      expect(seconde.tarifNuit, 18000);
      expect(await db.select(db.reservationsLocal).get(), hasLength(2));
    });
  });

  /* ================================================================== */
  group('Annulation', () {
    test(
      'annuler conserve la ligne et FIXE ce que l’annulation a décidé',
      () async {
        final creee = await creer(p: periode(10, 12));
        await annuler(creee.id);

        final relue = await depot.parId(creee.id);
        expect(relue, isNotNull, reason: 'annuler n’est pas supprimer');
        expect(relue!.statut, StatutReservation.annulee);
        // Le motif n'existe plus au serveur : le geste ne l'écrit pas.
        expect(relue.motifAnnulation, isNull);
        final a = relue.annulation!;
        expect(a.totalCentimes, 5600000, reason: '2 nuits à 28 000 F');
        expect(a.commissionCentimes, 2800000, reason: '50 % du total');
        expect(a.rembourseCentimes, 0);
        expect(a.auteurId, auteurEssai);
        expect(a.auteurLogin, 'compta-$auteurEssai');
      },
    );

    test(
      'l’annulation repart en « local », même si la création était partie',
      () async {
        final creee = await creer(p: periode(10, 12));
        await dao.majStatutSync(creee.id, StatutSynchronisation.synchronise);
        expect(
          (await depot.parId(creee.id))!.statutSynchronisation,
          StatutSynchronisation.synchronise,
        );

        await annuler(creee.id);

        // `local` signifie désormais ce qu'il dit : cette ligne vit sur ce poste.
        expect(
          (await depot.parId(creee.id))!.statutSynchronisation,
          StatutSynchronisation.local,
        );
      },
    );

    test('une réservation sans montant total connu ne s’annule PAS : la '
        'commission serait un chiffre inventé', () async {
      // Une ligne reprise de la v1 : tarif figé à 0 et aucune ligne de service.
      await db.customStatement(
        'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
        'date_arrivee, date_depart, statut, tarif_nuit) VALUES '
        "('r-v1', 'MIG-R', 'cli-1', 'u-bng-01', 1785000000, 1785200000, "
        "'confirmee', 0)",
      );

      await expectLater(
        annuler('r-v1'),
        throwsA(
          isA<RefusAnnulation>().having(
            (e) => e.message,
            'message',
            MessagesAnnulation.montantTotalInconnu,
          ),
        ),
      );
      expect(
        (await depot.parId('r-v1'))!.statut,
        isNot(StatutReservation.annulee),
      );
    });
  });

  /* ================================================================== */
  group('Retour du serveur', () {
    test('un rejet conserve la réservation ET son motif', () async {
      final creee = await creer(p: periode(10, 12));

      await dao.majStatutSync(
        creee.id,
        StatutSynchronisation.rejete,
        motifRejet: 'Unité déjà réservée par un autre poste (RG-01).',
      );

      final relue = await depot.parId(creee.id);
      expect(
        relue,
        isNotNull,
        reason: 'une opération rejetée ne disparaît jamais',
      );
      expect(relue!.statutSynchronisation, StatutSynchronisation.rejete);
      expect(relue.motifRejet, contains('RG-01'));
    });

    // ⚠ UN CAS RETIRÉ le 14/09/2026 : « la mise à jour du statut ne remet PAS
    // d'opération en file ». Il empêchait qu'une réservation reparte
    // indéfiniment — chaque changement de statut ré-enfilant une opération qui
    // changeait le statut. Sans file, ni le geste ni le risque n'existent.

    test('« en suspens » ne retient que ce qui n’est pas tranché', () async {
      final a = await creer(p: periode(10, 12));
      final b = await creer(numeroUnite: 'CH-101', p: periode(10, 12));
      final c = await creer(numeroUnite: 'BNG-01', p: periode(20, 22));

      await dao.majStatutSync(a.id, StatutSynchronisation.synchronise);
      await dao.majStatutSync(
        b.id,
        StatutSynchronisation.rejete,
        motifRejet: 'Refusée',
      );

      final suspens = await depot.reservations(seulementEnSuspens: true);
      expect(suspens.map((r) => r.id), [c.id]);
    });
  });
}
