import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/cloture_exercice.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart'
    show libelleTableServeur;
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/suivi_synchronisation.dart'
    show libelleDocument;

import 'support/outils_comptabilite.dart';

/// La clôture annuelle du poste, ses gardes et ses effets de bord — ce que la
/// confrontation au serveur (`cloture_contre_serveur_test.dart`) ne dit pas :
/// l'atomicité, la demande enfilée, le verrou RG-11bis de la base, la
/// correspondance des comptes de résultat, la liste de contrôle du référentiel.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late MoteurComptable moteur;
  late ClotureExerciceLocale service;
  late String id2031;

  final maintenant = DateTime(2031, 6, 15, 10);

  Future<void> exploiter({
    String vente = '100000.00',
    String charge = '30000.00',
  }) async {
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '2031-03-10',
        libelle: 'Ventes bar',
        lignes: [
          LigneDemandee(
            compte: '5711',
            debitCentimes: centimesDepuisChaine(vente),
            centreId: centres['Bar'],
          ),
          LigneDemandee(
            compte: '7011',
            creditCentimes: centimesDepuisChaine(vente),
            centreId: centres['Bar'],
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    await moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '2031-03-11',
        libelle: 'Marché',
        lignes: [
          LigneDemandee(
            compte: '6011',
            debitCentimes: centimesDepuisChaine(charge),
            centreId: centres['Restaurant'],
          ),
          LigneDemandee(
            compte: '5711',
            creditCentimes: centimesDepuisChaine(charge),
            centreId: centres['Restaurant'],
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
  }

  Future<List<OperationSync>> demandes() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.demandesClotureExercice);

  Future<int> nombreDeLignes() async => (await dao.toutesLesEcritures()).length;

  Future<void> poser(String cle, String valeur) => db
      .into(db.parametresSystemeLocal)
      .insertOnConflictUpdate(
        ParametresSystemeLocalCompanion.insert(
          cle: cle,
          valeur: valeur,
          modifieLe: maintenant,
        ),
      );

  setUp(() async {
    db = await baseInstallee(maintenant: maintenant);
    dao = ComptabiliteDao(db);
    moteur = moteurSur(db, maintenant: () => maintenant);
    service = ClotureExerciceLocale(db, moteur, maintenant: () => maintenant);
    id2031 = (await dao.exerciceDeLAnnee(2031))!.id;
  });
  tearDown(() => db.close());

  group('Chaque geste enfile UNE demande au serveur — jamais une pièce', () {
    test('démarrer, clôturer, rouvrir, reprendre : quatre demandes, dans '
        'l’ordre, avec l’année, l’action et le motif', () async {
      await exploiter();
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.reprendreSaisie(id2031, auteurId: auteurEssai);
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.cloturer(id2031, auteurId: auteurEssai);
      await service.rouvrir(
        id2031,
        auteurId: auteurEssai,
        motif: '  Facture oubliée en décembre  ',
      );

      final file = await demandes();
      expect(
        [
          for (final o in file)
            (jsonDecode(o.payload) as Map<String, dynamic>)['action'],
        ],
        ['demarrer', 'reprendre_saisie', 'demarrer', 'cloturer', 'rouvrir'],
      );
      for (final o in file) {
        expect(o.type, TypeOperationSync.creation);
        expect(o.statut, StatutOperationSync.enAttente);
        expect((jsonDecode(o.payload) as Map<String, dynamic>)['annee'], 2031);
      }
      // Le motif est celui du serveur : rogné, et SEULEMENT pour la réouverture.
      expect(
        (jsonDecode(file.last.payload) as Map<String, dynamic>)['motif'],
        'Facture oubliée en décembre',
      );
      expect(
        (jsonDecode(file.first.payload) as Map<String, dynamic>).containsKey(
          'motif',
        ),
        isFalse,
      );
      // Aucune autre table n'est enfilée : le serveur passe SES pièces (D246).
      expect(
        (await OperationsSyncDao(db).operations()).map((o) => o.table).toSet(),
        {TableSynchronisee.demandesClotureExercice},
      );
    });

    test('l’écran de synchronisation DIT chaque demande par le geste de '
        'l’onglet, aux mots de la vue', () async {
      await exploiter();
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.reprendreSaisie(id2031, auteurId: auteurEssai);
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.cloturer(id2031, auteurId: auteurEssai);
      await service.rouvrir(
        id2031,
        auteurId: auteurEssai,
        motif: 'Facture oubliée en décembre',
      );
      expect(
        [for (final o in await demandes()) libelleDocument(o)],
        [
          'Démarrer la clôture de l’exercice 2031',
          'Reprendre la saisie (2031)',
          'Démarrer la clôture de l’exercice 2031',
          'Clôturer définitivement l’exercice 2031',
          'Rouvrir l’exercice 2031',
        ],
      );
      expect(
        libelleTableServeur('demandes_cloture_exercice'),
        'Demandes de clôture d’exercice',
      );
    });

    test('un geste refusé n’enfile RIEN', () async {
      await expectLater(
        service.cloturer(id2031, auteurId: auteurEssai),
        throwsA(isA<RefusComptable>()),
      );
      await expectLater(
        service.reprendreSaisie(id2031, auteurId: auteurEssai),
        throwsA(isA<RefusComptable>()),
      );
      expect(await demandes(), isEmpty);
    });

    test(
      'hors file (démonstration), le geste se joue et n’enfile rien',
      () async {
        final demo = AppDatabase.enMemoire(fileSynchronisation: false);
        await demo.customStatement('SELECT 1');
        await semerAuteur(demo);
        await baseInstalleeSur(demo, maintenant);
        final s = ClotureExerciceLocale(
          demo,
          moteurSur(demo, maintenant: () => maintenant),
          maintenant: () => maintenant,
        );
        final id = (await ComptabiliteDao(demo).exerciceDeLAnnee(2031))!.id;
        await s.demarrer(id, auteurId: auteurEssai);
        expect(
          (await ComptabiliteDao(demo).exercice(id))!.statut,
          StatutExercice.enCloture,
        );
        expect(await OperationsSyncDao(demo).operations(), isEmpty);
        await demo.close();
      },
    );
  });

  group('Tout ou rien : un refus du moteur annule le geste ENTIER', () {
    test('une pièce de clôture refusée ne laisse ni pièce, ni clôture, ni '
        'demande — et N reste en clôture', () async {
      await exploiter();
      await service.demarrer(id2031, auteurId: auteurEssai);
      final apresDemarrer = (await demandes()).length;
      final lignes = await nombreDeLignes();
      // Le compte des bénéfices pointe une DIVISION du plan : le moteur refuse
      // la pièce de clôture, après que le geste a déjà ouvert N+1.
      await poser('compte_resultat_benefice', '13');

      final refus = await service
          .cloturer(id2031, auteurId: auteurEssai)
          .then<Object?>((_) => null, onError: (Object e) => e);
      expect(refus, isA<RefusComptable>());
      expect((refus! as RefusComptable).motif, MotifRefus.compteDivision);

      // N+1 existe : c'est « démarrer » (un geste à part) qui l'a ouvert.
      expect(await dao.exerciceDeLAnnee(2032), isNotNull);
      expect(await nombreDeLignes(), lignes);
      expect(await service.clotures(), isEmpty);
      expect(await demandes(), hasLength(apresDemarrer));
      expect((await dao.exercice(id2031))!.statut, StatutExercice.enCloture);
    });

    test('N+1, ouvert PAR le geste refusé, disparaît avec lui', () async {
      await exploiter();
      // Un exercice déjà en clôture, N+1 absent (état d'un poste dont le
      // statut descend du serveur) : seul « clôturer » ouvre N+1.
      await dao.changerStatutExercice(id2031, StatutExercice.enCloture);
      expect(await dao.exerciceDeLAnnee(2032), isNull);
      await poser('compte_resultat_benefice', '13');

      await expectLater(
        service.cloturer(id2031, auteurId: auteurEssai),
        throwsA(isA<RefusComptable>()),
      );
      expect(await dao.exerciceDeLAnnee(2032), isNull, reason: 'rollback');
      expect(await service.clotures(), isEmpty);
      expect(await demandes(), isEmpty);
    });
  });

  group('Le verrou RG-11bis : un exercice clôturé n’écrit plus', () {
    test('plus aucune pièce, par le moteur comme par la base', () async {
      await exploiter();
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.cloturer(id2031, auteurId: auteurEssai);
      final centres = {for (final c in await dao.centres()) c.libelle: c.id};

      Future<void> passer() => moteur.passerEtValider(
        DemandePiece(
          journal: 'OD',
          date: '2031-12-15',
          libelle: 'Tardive',
          statutsExerciceAdmis: const {
            StatutExercice.ouvert,
            StatutExercice.enCloture,
          },
          lignes: [
            LigneDemandee(
              compte: '6011',
              debitCentimes: 100,
              centreId: centres['Bar'],
            ),
            LigneDemandee(
              compte: '4011',
              creditCentimes: 100,
              centreId: centres['Structure'],
            ),
          ],
        ),
        auteurId: auteurEssai,
      );

      // Le moteur : « clôturé » n'est jamais un statut admis.
      await expectLater(
        passer(),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.motif,
            'motif',
            MotifRefus.exerciceNonOuvert,
          ),
        ),
      );
      // La base : le trigger refuse, même à qui contournerait le moteur.
      final journal = (await dao.journalParCode('OD'))!;
      final compte = (await dao.compteParNumero('6011'))!;
      await expectLater(
        dao.insererEcriture(
          exerciceId: id2031,
          journalId: journal.id,
          compteId: compte.id,
          centreId: centres['Bar']!,
          dateEcriture: '2031-12-15',
          libelle: 'Contournement',
          debitCentimes: 100,
          creditCentimes: 0,
          statut: StatutEcriture.brouillon,
          ecritureContrepasseeId: null,
          numeroPiece: null,
          creeLe: maintenant,
          creePar: auteurEssai,
        ),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.motif,
            'motif',
            MotifRefus.exerciceClos,
          ),
        ),
      );

      // La réouverture le rend de nouveau écrivable — dans l'exercice en clôture.
      await service.rouvrir(
        id2031,
        auteurId: auteurEssai,
        motif: 'Régularisation tardive',
      );
      await passer();
    });
  });

  group('La réouverture est au comptable, et se défait sans rien effacer', () {
    test(
      'un autre rôle est refusé, la pièce de clôture survit contre-passée',
      () async {
        await exploiter();
        await service.demarrer(id2031, auteurId: auteurEssai);
        final cloture = await service.cloturer(id2031, auteurId: auteurEssai);
        final avant = await nombreDeLignes();

        await db
            .into(db.utilisateursLocal)
            .insert(
              UtilisateursLocalCompanion.insert(
                id: 'u-gerant',
                login: 'gerant-essai',
                nom: 'Gérant',
                role: 'administrateur',
                droitsJson: '{}',
                sel: 's',
                empreinte: 'e',
                iterations: 1,
                dateCreation: DateTime(2026, 10, 1),
                dateMotDePasse: DateTime(2026, 10, 1),
              ),
            );
        await expectLater(
          service.rouvrir(
            id2031,
            auteurId: 'u-gerant',
            motif: 'Un motif assez long',
          ),
          throwsA(
            isA<RefusComptable>().having(
              (e) => e.motif,
              'motif',
              MotifRefus.reouvertureReservee,
            ),
          ),
        );
        expect(await nombreDeLignes(), avant, reason: 'rien n’a été écrit');

        await service.rouvrir(
          id2031,
          auteurId: auteurEssai,
          motif: 'Un motif assez long',
        );
        // RIEN ne s'efface : la pièce de clôture et celle d'à-nouveaux restent,
        // leurs contre-passations s'y AJOUTENT (RG-11).
        final lignes = await dao.toutesLesEcritures();
        expect(lignes.length, greaterThan(avant));
        final origines = {for (final l in lignes) l.id};
        final inverses = lignes.where((l) => l.ecritureContrepasseeId != null);
        expect(inverses, isNotEmpty);
        for (final i in inverses) {
          expect(origines, contains(i.ecritureContrepasseeId));
          expect(
            i.numeroPiece,
            isNull,
            reason: 'sans numéro, comme le serveur',
          );
          expect(i.estValidee, isTrue);
        }
        // La clôture rouverte reste en historique, avec son motif.
        final historique = await service.clotures();
        expect(historique, hasLength(1));
        expect(historique.single.id, cloture.id);
        expect(historique.single.estActive, isFalse);
        expect(historique.single.motifReouverture, 'Un motif assez long');
        expect(historique.single.rouvertePar, auteurEssai);
        expect(await service.clotureActive(id2031), isNull);
      },
    );
  });

  group('Les comptes de résultat suivent la correspondance des comptes', () {
    test(
      'un compte choisi reçoit le résultat ; son défaut n’est plus utilisé',
      () async {
        await exploiter(); // bénéfice : 70 000
        final autre = (await dao.comptesDeClasse(
          '1',
        )).firstWhere((c) => c.numero.length == 4 && c.numero.startsWith('13'));
        await poser('compte_resultat_benefice', autre.numero);
        await service.demarrer(id2031, auteurId: auteurEssai);
        await service.cloturer(id2031, auteurId: auteurEssai);

        final cl = [
          for (final l in await dao.lignesPourArchive(id2031))
            if (l.codeJournal == 'CL') l,
        ];
        expect(cl.where((l) => l.numeroCompte == autre.numero), hasLength(1));
        expect(cl.where((l) => l.numeroCompte == '131'), isEmpty);
        expect(
          cl.singleWhere((l) => l.numeroCompte == autre.numero).creditCentimes,
          7000000,
        );
        // Et les à-nouveaux reportent CE compte.
        final an = [
          for (final l in await dao.lignesPourArchive(
            (await dao.exerciceDeLAnnee(2032))!.id,
          ))
            if (l.codeJournal == 'AN') l,
        ];
        expect(an.any((l) => l.numeroCompte == autre.numero), isTrue);
      },
    );

    test(
      'un compte de résultat introuvable au plan BLOQUE (structurel)',
      () async {
        await poser('compte_resultat_perte', '9999');
        final etat = await service.etat(id2031);
        expect(etat.blocages, [BlocageCloture.comptesDeResultatAbsents]);
        expect(etat.blocages.single.structurel, isTrue);
        expect(etat.conditionsReunies, isFalse);
      },
    );
  });

  group('La liste de contrôle lit le référentiel', () {
    test(
      'journaux CL et AN, centre « Structure » : chacun bloque, nommé',
      () async {
        expect((await service.etat(id2031)).blocages, isEmpty);

        await db.customStatement(
          "DELETE FROM journaux_local WHERE code = 'AN'",
        );
        expect((await service.etat(id2031)).blocages, [
          BlocageCloture.journalANouveauxAbsent,
        ]);

        // La phrase du blocage est celle du serveur, dans le refus.
        await dao.changerStatutExercice(id2031, StatutExercice.enCloture);
        await expectLater(
          service.cloturer(id2031, auteurId: auteurEssai),
          throwsA(
            isA<RefusComptable>()
                .having(
                  (e) => e.motif,
                  'motif',
                  MotifRefus.clotureConditionsNonReunies,
                )
                .having(
                  (e) => e.message,
                  'message',
                  contains(
                    "Les journaux de clôture (CL) et d'à-nouveaux (AN) ne sont "
                    'pas tous deux au référentiel.',
                  ),
                ),
          ),
        );
      },
    );

    test('un exercice équilibré sans impôt avertit sans bloquer', () async {
      await exploiter();
      final etat = await service.etat(id2031);
      expect(etat.blocages, isEmpty);
      expect(etat.avertissements, [AvertissementCloture.impotNonComptabilise]);
      expect(etat.resultatAReporterCentimes, 7000000);
      expect(etat.compteDeDestination, '131');
    });
  });
}
