import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
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
  group('PA-50 — l’annulation d’un contrat N’EXISTE PAS', () {
    test('aucune méthode d’annulation n’est exposée par le DAO', () {
      // ⚠ Ce cas relit le CODE SOURCE, et c'est délibéré : on ne peut pas
      // prouver l'absence d'une méthode en l'appelant. L'ancrage est extérieur
      // au fichier testé (piège 12) — c'est le texte du DAO lui-même.
      //
      // « Une méthode qui ne libère rien laisserait croire que le cas est
      // traité » : tant qu'aucune colonne de statut n'existe, un `annuler()`
      // ne pourrait qu'effacer la ligne, et la suppression est interdite sur
      // une table transactionnelle.
      final source = File('lib/features/vehicules/data/vehicule_dao.dart');
      expect(
        source.existsSync(),
        isTrue,
        reason: 'le DAO est introuvable : ce cas ne vérifierait rien',
      );

      final texte = source.readAsStringSync();

      // Prouvé non vide : sans ce contrôle, un fichier renommé rendrait le
      // balayage vert à vide.
      expect(texte, contains('creerContrat'));
      expect(
        RegExp(r'Future<[^>]*>\s+annuler').hasMatch(texte),
        isFalse,
        reason:
            'Une méthode d’annulation est apparue sans colonne de statut pour '
            'la porter : elle ne libérerait aucun véhicule (PA-50).',
      );
    });

    test('`contrats_location_local` n’a aucune colonne de statut', () {
      // La raison du refus, relue à sa source. Le jour où cette colonne
      // apparaîtra, ce cas échouera — et c'est ce qu'on veut : il faudra
      // rouvrir la décision plutôt que la laisser périmée (PA-144).
      final source = File('lib/core/database/tables/vehicules_tables.dart');
      expect(source.existsSync(), isTrue);

      final texte = source.readAsStringSync();
      final bloc = texte.substring(
        texte.indexOf('class ContratsLocationLocal'),
      );

      expect(bloc, contains('dateDebut'));
      // `statutSync` et `statutUploadPieces` existent ; une colonne `statut`
      // métier, non.
      expect(
        RegExp(r'get\s+statut\s*=>').hasMatch(bloc),
        isFalse,
        reason:
            'Une colonne `statut` est apparue : l’annulation devient possible, '
            'et le refus affiché à l’écran est désormais faux (PA-50).',
      );
    });

    test('le refus est une phrase, et elle dit pourquoi', () {
      // Dit en clair, sans référence interne (consigne du PO, 14/10/2026) :
      // le contrat ne s'annule pas, et le véhicule reste engagé.
      expect(refusAnnulationContrat, isNot(contains('PA-50')));
      expect(refusAnnulationContrat, contains('ne peut pas être annulé'));
      expect(refusAnnulationContrat, contains('reste engagé'));
    });

    test(
      'un contrat erroné bloque son véhicule — la limite est réelle',
      () async {
        // Le cas qui donne sa mesure à la lacune : une fois le contrat saisi, il
        // n'existe AUCUN geste pour libérer le véhicule sur la période.
        final v = await creerVehicule();
        await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

        // Même l'archivage est refusé : le véhicule est engagé.
        await expectLater(
          dao.archiverVehicule(v.id, aujourdHui: DateTime(2026, 9, 1)),
          throwsA(
            isA<RefusVehicule>().having(
              (e) => e.message,
              'message',
              contains('engagé'),
            ),
          ),
        );

        // Et la période reste prise.
        final d = await dao.disponibilite(
          vehiculeId: v.id,
          debut: DateTime(2026, 9, 12),
          fin: DateTime(2026, 9, 14),
        );
        expect(d.calendrierLibre, isFalse);
      },
    );
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
      'le montant suit le tarif COURANT — la lacune est reproduite',
      () async {
        // ⚠ Ce cas FIGE un défaut connu, il ne le célèbre pas : aucune colonne
        // ne porte le tarif d'une location, donc changer la grille réécrit le
        // montant d'un contrat déjà signé (PA-55 appliqué à M8). Le jour où la
        // colonne existera, ce cas échouera — et ce sera la bonne nouvelle.
        final v = await creerVehicule(tarif: 25000);
        await louer(v.id, debut: '2026-09-10', fin: '2026-09-15');

        expect((await dao.contrats()).single.montant, '125000.00');

        await dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'AB 1234 RB',
          categorie: CategorieVehicule.voiture,
          tarifJour: 30000,
        );

        expect((await dao.contrats()).single.montant, '150000.00');
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

      // Bornes demi-ouvertes : au 15, la restitution a eu lieu.
      await dao.archiverVehicule(v.id, aujourdHui: DateTime(2026, 9, 15));

      expect((await dao.parc()).single.statut, StatutVehicule.horsService);
    });
  });
}
