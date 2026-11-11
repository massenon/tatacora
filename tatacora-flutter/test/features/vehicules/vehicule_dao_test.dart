import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

/// Le DAO de M8 contre une **vraie base Drift**.
///
/// RG-08 et RG-09 se tenaient au serveur, sous verrou pessimiste. Depuis le
/// passage zéro réseau (14/09/2026), elles se tiennent ici — et un refus se
/// prouve dans la transaction qui insère, pas au-dessus d'elle : un contrôle
/// juste posé sur une lecture périmée ne protège rien.
void main() {
  late AppDatabase db;
  late VehiculeDao dao;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = VehiculeDao(db);

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

  Future<Vehicule> creerVehicule({
    String immatriculation = 'AB 1234 RB',
    CategorieVehicule categorie = CategorieVehicule.voiture,
    int tarif = 25000,
  }) => dao.enregistrerVehicule(
    immatriculation: immatriculation,
    categorie: categorie,
    tarifJour: tarif,
  );

  Future<ContratLocation> louer(
    String vehiculeId, {
    required String debut,
    required String fin,
    String piece = 'CNI-123',
    String? permis = 'PC-456',
  }) => dao.creerContrat(
    SaisieContrat(
      vehiculeId: vehiculeId,
      clientId: 'cli-1',
      debut: DateTime.parse(debut),
      fin: DateTime.parse(fin),
      pieceIdentite: piece,
      permisConduire: permis,
    ),
  );

  /* ================================================================== */
  group('Créer un véhicule — le parc se saisit SUR LE POSTE', () {
    test('un véhicule créé est relu, avec son tarif en francs entiers', () async {
      // Le défaut que ce cas ferme : `vehicules_local` descendait du serveur et
      // n'avait plus AUCUN écrivain depuis le passage zéro réseau. Un poste
      // neuf n'avait pas un véhicule, donc pas un contrat possible.
      final cree = await creerVehicule();

      final parc = await dao.parc();
      expect(parc, hasLength(1));
      expect(parc.single.id, cree.id);
      expect(parc.single.immatriculation, 'AB 1234 RB');
      expect(parc.single.tarifJour, '25000.00');
      expect(parc.single.statut, StatutVehicule.disponible);
    });

    test('rééditer la même fiche ne duplique pas la ligne', () async {
      final cree = await creerVehicule();

      await dao.enregistrerVehicule(
        id: cree.id,
        immatriculation: 'AB 1234 RB',
        categorie: CategorieVehicule.pickup,
        tarifJour: 30000,
      );

      final parc = await dao.parc();
      expect(parc, hasLength(1));
      expect(parc.single.categorie, CategorieVehicule.pickup);
      expect(parc.single.tarifJour, '30000.00');
    });

    test('deux véhicules ne partagent pas une immatriculation', () async {
      // L'immatriculation est la colonne « Véhicule » de tous les tableaux :
      // deux homonymes rendraient le planning et les contrats illisibles. La
      // table locale ne porte PAS la contrainte `unique()` du serveur — ce
      // contrôle est le seul qui existe.
      await creerVehicule();

      await expectLater(
        creerVehicule(),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            contains('existe déjà au parc'),
          ),
        ),
      );

      expect(await dao.parc(), hasLength(1));
    });

    test('un tarif nul ou négatif est refusé', () async {
      // C'est le tarif qui donne son montant au contrat : à zéro, la location
      // serait facturée gratuitement sans que rien ne le signale.
      await expectLater(creerVehicule(tarif: 0), throwsA(isA<RefusVehicule>()));
      await expectLater(
        creerVehicule(tarif: -500),
        throwsA(isA<RefusVehicule>()),
      );
      expect(await dao.parc(), isEmpty);
    });

    test('une immatriculation vide est refusée', () async {
      await expectLater(
        creerVehicule(immatriculation: '   '),
        throwsA(isA<RefusVehicule>()),
      );
    });

    test('le filtre de catégorie porte sur la valeur STOCKÉE', () async {
      await creerVehicule(immatriculation: 'AA 1 RB');
      await creerVehicule(
        immatriculation: 'MM 2 RB',
        categorie: CategorieVehicule.moto,
      );

      final motos = await dao.parc(categorie: CategorieVehicule.moto);
      expect(motos, hasLength(1));
      expect(motos.single.immatriculation, 'MM 2 RB');
    });
  });

  /* ================================================================== */
  group('RG-08 — le chevauchement est refusé DANS la transaction', () {
    test('deux locations qui se recouvrent : la seconde est refusée', () async {
      final v = await creerVehicule();
      await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

      await expectLater(
        louer(v.id, debut: '2026-09-12', fin: '2026-09-18'),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            MessagesVehicules.chevauchement,
          ),
        ),
      );

      // Et rien n'a été écrit : le refus n'insère pas « à moitié ».
      final contrats = await dao.contrats();
      expect(contrats, hasLength(1));
    });

    test('un véhicule rendu le 15 est relouable dès le 15', () async {
      // Bornes demi-ouvertes, comme le `CHECK (date_fin > date_debut)` du
      // schéma. Les fermer ferait refuser une location parfaitement possible,
      // et immobiliserait le parc un jour sur deux.
      final v = await creerVehicule();
      await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

      await louer(v.id, debut: '2026-09-15', fin: '2026-09-18');

      expect(await dao.contrats(), hasLength(2));
    });

    test('le chevauchement est propre à CHAQUE véhicule', () async {
      final a = await creerVehicule(immatriculation: 'AA 1 RB');
      final b = await creerVehicule(immatriculation: 'BB 2 RB');

      await louer(a.id, debut: '2026-09-10', fin: '2026-09-15');
      await louer(b.id, debut: '2026-09-10', fin: '2026-09-15');

      expect(await dao.contrats(), hasLength(2));
    });

    test('une restitution qui ne suit pas le départ est refusée', () async {
      final v = await creerVehicule();

      await expectLater(
        louer(v.id, debut: '2026-09-10', fin: '2026-09-10'),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            MessagesVehicules.finApresDebut,
          ),
        ),
      );
    });

    test(
      'un véhicule immobilisé ne se loue pas, calendrier libre ou non',
      () async {
        // « C'est précisément parce qu'il est immobilisé que son calendrier
        // l'est » : un calendrier vide ne rend pas louable un véhicule au garage.
        final v = await creerVehicule();
        await dao.changerStatut(v.id, StatutVehicule.entretien);

        await expectLater(
          louer(v.id, debut: '2026-09-10', fin: '2026-09-15'),
          throwsA(
            isA<RefusVehicule>().having(
              (e) => e.message,
              'message',
              contains('indisponible'),
            ),
          ),
        );
      },
    );

    test('la disponibilité distingue le CALENDRIER du STATUT', () async {
      // Deux booléens, jamais un seul : les fondre ferait proposer à la
      // location un véhicule au garage dont le calendrier est vide.
      final v = await creerVehicule();
      await dao.changerStatut(v.id, StatutVehicule.entretien);

      final d = await dao.disponibilite(
        vehiculeId: v.id,
        debut: DateTime(2026, 9, 10),
        fin: DateTime(2026, 9, 15),
      );

      expect(d.calendrierLibre, isTrue);
      expect(d.statutLouable, isFalse);
      expect(d.disponible, isFalse);
    });

    test(
      'un client inconnu est refusé — la clé étrangère est réelle',
      () async {
        final v = await creerVehicule();

        await expectLater(
          dao.creerContrat(
            SaisieContrat(
              vehiculeId: v.id,
              clientId: 'cli-fantome',
              debut: DateTime(2026, 9, 10),
              fin: DateTime(2026, 9, 15),
              pieceIdentite: 'CNI-123',
              permisConduire: 'PC-456',
            ),
          ),
          throwsA(
            isA<RefusVehicule>().having(
              (e) => e.message,
              'message',
              MessagesVehicules.clientInexistant,
            ),
          ),
        );
      },
    );
  });

  /* ================================================================== */
  group('RG-09 — le permis dépend de la CATÉGORIE, la pièce jamais', () {
    test('une voiture sans permis est refusée', () async {
      final v = await creerVehicule();

      await expectLater(
        louer(v.id, debut: '2026-09-10', fin: '2026-09-15', permis: null),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            contains('permis de conduire est obligatoire'),
          ),
        ),
      );

      expect(await dao.contrats(), isEmpty);
    });

    test(
      'une MOTO se loue sans permis — la seule catégorie dispensée',
      () async {
        final moto = await creerVehicule(
          immatriculation: 'MM 2 RB',
          categorie: CategorieVehicule.moto,
          tarif: 8000,
        );

        final contrat = await louer(
          moto.id,
          debut: '2026-09-10',
          fin: '2026-09-15',
          permis: null,
        );

        expect(contrat.nombreJours, 5);
        expect(await dao.contrats(), hasLength(1));
      },
    );

    test(
      'un SCOOTER exige un permis — l’écart de PA-50 est appliqué',
      () async {
        // ⚠ Le cas qui compte. L'ancien prototype écrivait « moto, scooter et
        // vélo en sont dispensés » ; le schéma de référence ne dispense que la
        // moto. Suivre le prototype laisserait louer un scooter sans permis,
        // contre la règle que l'arbitrage n'a pas encore levée.
        final scooter = await creerVehicule(
          immatriculation: 'SC 3 RB',
          categorie: CategorieVehicule.scooter,
          tarif: 6000,
        );

        await expectLater(
          louer(
            scooter.id,
            debut: '2026-09-10',
            fin: '2026-09-15',
            permis: null,
          ),
          throwsA(isA<RefusVehicule>()),
        );

        final velo = await creerVehicule(
          immatriculation: 'VL 4 RB',
          categorie: CategorieVehicule.velo,
          tarif: 2000,
        );

        await expectLater(
          louer(velo.id, debut: '2026-09-10', fin: '2026-09-15', permis: null),
          throwsA(isA<RefusVehicule>()),
        );
      },
    );

    test('la pièce d’identité est exigée même sur une moto', () async {
      final moto = await creerVehicule(
        immatriculation: 'MM 2 RB',
        categorie: CategorieVehicule.moto,
      );

      await expectLater(
        louer(
          moto.id,
          debut: '2026-09-10',
          fin: '2026-09-15',
          piece: '  ',
          permis: null,
        ),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            MessagesVehicules.pieceIdentiteRequise,
          ),
        ),
      );
    });

    test('`exigePermis` de l’entité suit la même règle que le refus', () async {
      // Si les deux divergeaient, l'écran masquerait le champ « Permis » et
      // l'écriture le réclamerait : l'utilisateur chercherait un défaut
      // d'écran là où il y a un désaccord de règle.
      await creerVehicule(immatriculation: 'AA 1 RB');
      await creerVehicule(
        immatriculation: 'MM 2 RB',
        categorie: CategorieVehicule.moto,
      );

      final parc = await dao.parc();
      final voiture = parc.firstWhere((v) => v.immatriculation == 'AA 1 RB');
      final moto = parc.firstWhere((v) => v.immatriculation == 'MM 2 RB');

      expect(voiture.exigePermis, isTrue);
      expect(moto.exigePermis, isFalse);
    });
  });

  /* ================================================================== */
  group('Annuler un contrat — PA-50 levé (v38, 26/10/2026)', () {
    test('le contrat passe « annulé », reste LISIBLE, et libère son véhicule '
        '(RG-08)', () async {
      final v = await creerVehicule();
      final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
      expect(c.statut, statutContratActif);

      // Pris : un second contrat sur la même plage est refusé.
      await expectLater(
        louer(v.id, debut: '2026-09-12', fin: '2026-09-14'),
        throwsA(isA<RefusVehicule>()),
      );

      final annule = await dao.annulerContrat(c.id);

      expect(annule.annule, isTrue);
      expect(annule.id, c.id);
      // Rien n'est supprimé : la pièce reste au registre, avec son statut.
      final lignes = await db.select(db.contratsLocationLocal).get();
      expect(lignes.single.statut, 'annule');
      expect((await dao.contrats()).single.annule, isTrue);
      // La plage est libre : disponibilité ET création.
      final d = await dao.disponibilite(
        vehiculeId: v.id,
        debut: DateTime(2026, 9, 12),
        fin: DateTime(2026, 9, 14),
      );
      expect(d.calendrierLibre, isTrue);
      await louer(v.id, debut: '2026-09-12', fin: '2026-09-14');
      expect(await dao.contrats(), hasLength(2));
    });

    test('un contrat déjà annulé, ou inconnu, est refusé avec la phrase de la '
        'vue', () async {
      final v = await creerVehicule();
      final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
      await dao.annulerContrat(c.id);

      await expectLater(
        dao.annulerContrat(c.id),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            MessagesVehicules.contratDejaAnnule,
          ),
        ),
      );
      await expectLater(
        dao.annulerContrat('inconnu'),
        throwsA(
          isA<RefusVehicule>().having(
            (e) => e.message,
            'message',
            MessagesVehicules.contratInexistant,
          ),
        ),
      );
    });

    test(
      'un contrat ANNULÉ n’engage plus le véhicule : il s’archive',
      () async {
        final v = await creerVehicule();
        final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
        await expectLater(
          dao.archiverVehicule(v.id, aujourdHui: DateTime(2026, 9, 1)),
          throwsA(isA<RefusVehicule>()),
        );

        await dao.annulerContrat(c.id);

        final archive = await dao.archiverVehicule(
          v.id,
          aujourdHui: DateTime(2026, 9, 1),
        );
        expect(archive.statut, StatutVehicule.horsService);
      },
    );

    test(
      'l’annulation part dans la file, en modification, DANS la même '
      'transaction — et seulement si le serveur détient le contrat',
      () async {
        final v = await creerVehicule();
        final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
        final file = OperationsSyncDao(db);

        await dao.annulerContrat(c.id);

        final operations = (await file.operations())
            .where((o) => o.table == TableSynchronisee.contratsLocation)
            .toList();
        expect(operations.map((o) => o.type), [
          TypeOperationSync.creation,
          TypeOperationSync.modification,
        ]);
        expect(jsonDecode(operations.last.payload), {'statut': 'annule'});
        expect(operations.last.entiteId, c.id);
      },
    );

    test('une création REJETÉE par le serveur : l’annulation reste locale, '
        'rien ne part qu’il rejetterait', () async {
      final v = await creerVehicule();
      final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
      await db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete' "
        "WHERE table_serveur = 'contrats_location' AND entite_id = '${c.id}'",
      );

      await dao.annulerContrat(c.id);

      expect(
        (await OperationsSyncDao(db).operations())
            .where((o) => o.table == TableSynchronisee.contratsLocation)
            .map((o) => o.type),
        [TypeOperationSync.creation],
      );
      expect((await dao.contrats()).single.annule, isTrue);
    });

    test('une annulation qui échoue n’écrit rien (transaction)', () async {
      final v = await creerVehicule();
      final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
      // Une file sans défaut : la table d'opérations disparaît, l'enfilement
      // lève, et le statut ne doit pas avoir bougé.
      await db.customStatement('ALTER TABLE operations_sync_local RENAME TO x');
      await expectLater(dao.annulerContrat(c.id), throwsA(anything));
      await db.customStatement('ALTER TABLE x RENAME TO operations_sync_local');

      expect(
        (await db.select(db.contratsLocationLocal).get()).single.statut,
        statutContratActif,
      );
    });

    test('un contrat d’avant la v38 (sans statut) est actif', () async {
      final v = await creerVehicule();
      final c = await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
      await db.customStatement(
        "UPDATE contrats_location_local SET statut = NULL WHERE id = '${c.id}'",
      );

      final relu = (await dao.contrats()).single;
      expect(relu.statut, isNull);
      expect(relu.annule, isFalse);
      // Il bloque encore le véhicule, comme avant.
      await expectLater(
        louer(v.id, debut: '2026-09-12', fin: '2026-09-14'),
        throwsA(isA<RefusVehicule>()),
      );
    });
  });

  /* ================================================================== */
  group('Ce qui est écrit en base, et ce qui ne doit PAS l’être', () {
    test('statutSync vaut « local », jamais « synchronise »', () async {
      // ⚠ Le DÉFAUT du schéma est `synchronise` sur cette table : il serait
      // faux — rien n'a jamais été synchronisé, et il n'existe plus de file du
      // tout. On l'écrase à l'insertion plutôt que de le laisser mentir en
      // base (même discipline que PA-134).
      final v = await creerVehicule();
      await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

      final ligne = (await db.select(db.contratsLocationLocal).get()).single;
      expect(ligne.statutSync, VehiculeDao.statutSyncLocal);
      expect(ligne.statutSync, isNot('synchronise'));
    });

    test('les dates sont normalisées au JOUR', () async {
      final v = await creerVehicule();
      await dao.creerContrat(
        SaisieContrat(
          vehiculeId: v.id,
          clientId: 'cli-1',
          debut: DateTime(2026, 9, 10, 16, 45),
          fin: DateTime(2026, 9, 15, 9, 30),
          pieceIdentite: 'CNI-123',
          permisConduire: 'PC-456',
        ),
      );

      final ligne = (await db.select(db.contratsLocationLocal).get()).single;
      expect(ligne.dateDebut, DateTime(2026, 9, 10));
      expect(ligne.dateFin, DateTime(2026, 9, 15));
    });

    test('le nom du client est résolu — jamais un UUID à l’écran', () async {
      final v = await creerVehicule();
      await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

      final contrat = (await dao.contrats()).single;
      expect(contrat.clientNom, 'KORA');
      expect(contrat.immatriculation, 'AB 1234 RB');
      expect(contrat.montant, '125000.00'); // 25 000 × 5 jours
    });

    test(
      'le montant est FIGÉ à la signature — changer la grille ne réécrit pas un '
      'contrat signé (v41), et un contrat d’avant reste sans montant',
      () async {
        final v = await creerVehicule(tarif: 25000);
        await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');
        // Un contrat d'AVANT la v41 : colonnes nulles, rien n'est déduit.
        final ancien = await louer(
          v.id,
          debut: '2026-10-01',
          fin: '2026-10-03',
        );
        await db.customStatement(
          'UPDATE contrats_location_local SET montant = NULL, acompte = NULL, '
          "remise = NULL WHERE id = '${ancien.id}'",
        );

        expect((await dao.contrats()).map((c) => c.montant), [
          null,
          '125000.00',
        ]);

        await dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'AB 1234 RB',
          categorie: CategorieVehicule.voiture,
          tarifJour: 30000,
        );

        // Le contrat signé garde son montant ; l'ancien reste « — » (jamais le
        // tarif d'aujourd'hui, 30 000 x 2 = 60 000, qui serait plausible et faux).
        final apres = await dao.contrats();
        expect(apres.map((c) => c.montant), [null, '125000.00']);
        expect(apres.first.resteDu, isNull);
        expect(apres.last.resteDu, '125000.00');
      },
    );

    test(
      'archiver n’est pas supprimer : la ligne reste, le statut change',
      () async {
        final v = await creerVehicule();

        await dao.archiverVehicule(v.id);

        final parc = await dao.parc();
        expect(parc, hasLength(1));
        expect(parc.single.statut, StatutVehicule.horsService);
        expect(parc.single.estLouable, isFalse);
      },
    );

    test('un contrat passé n’empêche plus d’archiver', () async {
      final v = await creerVehicule();
      await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

      // Règle unique avec le serveur (`date_fin >= aujourd'hui`) : le jour de
      // restitution ENGAGE encore ; le lendemain, plus rien.
      await expectLater(
        dao.archiverVehicule(v.id, aujourdHui: DateTime(2026, 9, 15)),
        throwsA(isA<RefusVehicule>()),
      );
      await dao.archiverVehicule(v.id, aujourdHui: DateTime(2026, 9, 16));

      expect((await dao.parc()).single.statut, StatutVehicule.horsService);
    });
  });
}
