import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../synchronisation/support/faux_transport.dart';
import 'support/outils_comptabilite.dart';

/// D246 ROUVERT par le PO (28/10/2026) — côté POSTE : un compte du plan créé à
/// la main et une pièce saisie à la main partent au serveur ; ce qui descend ne
/// repart jamais ; rien n'est compté deux fois.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final maintenant = DateTime(2031, 6, 15, 10);

  late BancSync b;
  late MoteurComptable moteur;
  late ComptabiliteDao dao;
  late String bar;

  setUp(() async {
    b = await BancSync.creer();
    await semerAuteur(b.db);
    await baseInstalleeSur(b.db, maintenant);
    moteur = moteurSur(b.db, maintenant: () => maintenant);
    dao = ComptabiliteDao(b.db);
    bar = (await dao.centres()).firstWhere((c) => c.libelle == 'Bar').id;
  });
  tearDown(() => b.fermer());

  Future<List<OperationSync>> file(TableSynchronisee t) =>
      b.dao.operations(table: t);

  DemandePiece demande({
    int debit = 150000,
    int credit = 150000,
    String date = '2031-06-10',
  }) => DemandePiece(
    journal: 'OD',
    date: date,
    libelle: 'Régularisation',
    lignes: [
      LigneDemandee(compte: '5711', debitCentimes: debit, creditCentimes: 0),
      LigneDemandee(
        compte: '7011',
        debitCentimes: 0,
        creditCentimes: credit,
        libelle: 'Vente bar',
        centreId: bar,
      ),
    ],
  );

  group('Le compte du plan', () {
    test(
      'créé à la main, il est enfilé dans la transaction (création seule)',
      () async {
        final c = await moteur.creerCompte(
          '6099',
          ' Charges diverses ',
          'charge',
        );
        final ops = await file(TableSynchronisee.planComptable);
        expect(ops, hasLength(1));
        expect(ops.single.type, TypeOperationSync.creation);
        expect(ops.single.entiteId, c.id);
        expect(jsonDecode(ops.single.payload), {
          'numero_compte': '6099',
          'libelle': 'Charges diverses',
          'nature': 'charge',
        });
      },
    );

    test('un refus (format, libellé, nature, doublon) n’enfile rien', () async {
      for (final essai in <Future<Object?> Function()>[
        () => moteur.creerCompte('60999', 'X', 'charge'),
        () => moteur.creerCompte('6098', '  ', 'charge'),
        () => moteur.creerCompte('6097', 'X', 'magie'),
        () => moteur.creerCompte('5711', 'X', 'actif'),
      ]) {
        await expectLater(essai(), throwsA(isA<RefusComptable>()));
      }
      expect(await file(TableSynchronisee.planComptable), isEmpty);
    });

    test(
      'synchronisation éteinte : le compte reste local, rien n’est enfilé',
      () async {
        final hors = AppDatabase.enMemoire(fileSynchronisation: false);
        await semerAuteur(hors);
        await baseInstalleeSur(hors, maintenant);
        final m = moteurSur(hors, maintenant: () => maintenant);
        await m.creerCompte('6099', 'Charges diverses', 'charge');
        expect(await OperationsSyncDao(hors).operations(), isEmpty);
        expect(await ComptabiliteDao(hors).compteParNumero('6099'), isNotNull);
        await hors.close();
      },
    );

    test(
      'le compte descendu est ajouté, jamais réécrit, rien n’est enfilé',
      () async {
        await moteur.creerCompte('6099', 'Mon libellé', 'charge');
        final avant = (await file(TableSynchronisee.planComptable)).length;

        Future<void> descendre(List<Map<String, Object?>> e) async {
          await DescenteCatalogueDao(b.db).effacerCurseur();
          final bilan = await b
              .descente(FauxTransport((r) => FauxCatalogue(e).repondre(r)))
              .descendre(
                (await b.lecteur.appairage())!,
                surRefus: (_) async {},
              );
          expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
        }

        await descendre([
          element('plan_comptable', 'srv-1', {
            'numero_compte': '6098',
            'libelle': 'Du serveur',
            'classe': '6',
            'nature': 'charge',
          }),
          // Même numéro qu'un compte créé ICI et pas encore accepté : le libellé
          // local est conservé, c'est l'envoi qui arbitrera.
          element('plan_comptable', 'srv-2', {
            'numero_compte': '6099',
            'libelle': 'Libellé différent du serveur',
            'classe': '6',
            'nature': 'charge',
          }),
        ]);
        expect((await dao.compteParNumero('6098'))!.libelle, 'Du serveur');
        expect((await dao.compteParNumero('6098'))!.id, 'srv-1');
        expect((await dao.compteParNumero('6099'))!.libelle, 'Mon libellé');
        expect(await file(TableSynchronisee.planComptable), hasLength(avant));

        // Illisible : classe qui n'est pas le premier chiffre, nature inconnue,
        // numéro mal formé — refusés, pas devinés.
        for (final d in [
          {
            'numero_compte': '6097',
            'libelle': 'X',
            'classe': '7',
            'nature': null,
          },
          {
            'numero_compte': '6096',
            'libelle': 'X',
            'classe': '6',
            'nature': 'x',
          },
          {
            'numero_compte': '06',
            'libelle': 'X',
            'classe': '0',
            'nature': null,
          },
        ]) {
          await DescenteCatalogueDao(b.db).effacerCurseur();
          final bilan = await b
              .descente(
                FauxTransport(
                  (r) => FauxCatalogue([
                    element('plan_comptable', 'srv-x', d),
                  ]).repondre(r),
                ),
              )
              .descendre(
                (await b.lecteur.appairage())!,
                surRefus: (_) async {},
              );
          expect(bilan.refuses, 1, reason: '$d');
          expect(await dao.compteParNumero('${d['numero_compte']}'), isNull);
        }
      },
    );
  });

  group('La pièce saisie à la main', () {
    test(
      'brouillon : la SOURCE part en centimes, le poste la marque',
      () async {
        final piece = await moteur.saisirPiece(
          demande(),
          auteurId: auteurEssai,
          valider: false,
        );
        expect(piece.every((l) => !l.estValidee), isTrue);
        final ops = await file(TableSynchronisee.piecesSaisie);
        expect(ops, hasLength(1));
        expect(ops.single.type, TypeOperationSync.creation);
        expect(ops.single.dateMetier, '2031-06-10');
        expect(jsonDecode(ops.single.payload), {
          'journal': 'OD',
          'date': '2031-06-10',
          'libelle': 'Régularisation',
          'statut': 'brouillon',
          'lignes': [
            {'compte': '5711', 'debit': 150000, 'credit': 0},
            {
              'compte': '7011',
              'debit': 0,
              'credit': 150000,
              'libelle': 'Vente bar',
              'centre': 'Bar',
            },
          ],
        });
        final marquees = await b.db.select(b.db.piecesSaisieLocal).get();
        expect(marquees.single.id, ops.single.entiteId);
        expect(marquees.single.numeroPiece, piece.first.numeroPiece);
        expect(marquees.single.statut, 'brouillon');
      },
    );

    test(
      'validée d’un geste : statut `validee`, pièce validée localement',
      () async {
        final piece = await moteur.saisirPiece(
          demande(),
          auteurId: auteurEssai,
          valider: true,
        );
        expect(piece.every((l) => l.estValidee), isTrue);
        final p = jsonDecode(
          (await file(TableSynchronisee.piecesSaisie)).single.payload,
        );
        expect(p['statut'], 'validee');
      },
    );

    test(
      'un refus du moteur (équilibre, exercice) n’enfile ni ne marque rien',
      () async {
        await expectLater(
          moteur.saisirPiece(
            demande(credit: 100000),
            auteurId: auteurEssai,
            valider: true,
          ),
          throwsA(isA<RefusComptable>()),
        );
        await expectLater(
          moteur.saisirPiece(
            demande(date: '2019-01-05'),
            auteurId: auteurEssai,
            valider: true,
          ),
          throwsA(isA<RefusComptable>()),
        );
        expect(await file(TableSynchronisee.piecesSaisie), isEmpty);
        expect(await b.db.select(b.db.piecesSaisieLocal).get(), isEmpty);
      },
    );

    test(
      'les pièces des MODULES ne partent jamais (le serveur les recrée)',
      () async {
        await moteur.passer(demande(), auteurId: auteurEssai);
        await moteur.passerEtValider(demande(), auteurId: auteurEssai);
        expect(await file(TableSynchronisee.piecesSaisie), isEmpty);
        expect(await b.db.select(b.db.piecesSaisieLocal).get(), isEmpty);
      },
    );

    test('un rôle comptable n’est pas une saisie manuelle', () async {
      expect(
        () => moteur.saisirPiece(
          DemandePiece(
            journal: 'OD',
            date: '2031-06-10',
            libelle: 'x',
            lignes: const [LigneDemandee(role: 'caisse', debitCentimes: 1)],
          ),
          auteurId: auteurEssai,
          valider: true,
        ),
        throwsArgumentError,
      );
    });

    test(
      'redescendue, la pièce est RECONNUE par son origine : jamais deux fois',
      () async {
        final piece = await moteur.saisirPiece(
          demande(),
          auteurId: auteurEssai,
          valider: true,
        );
        final origine =
            (await b.db.select(b.db.piecesSaisieLocal).get()).single.id;
        expect(await dao.piecesSaisiesNonReprises(), hasLength(1));

        // Le serveur passe SA pièce (autres identifiants) et la renvoie avec
        // l'identifiant d'origine, plus une pièce d'un autre poste.
        Map<String, Object?> ligne(
          String id,
          String compte,
          String classe,
          String debit,
          String credit, {
          String? piece,
          String? orig,
        }) => element('ecritures_comptables', id, {
          'annee': 2031,
          'code_journal': 'OD',
          'numero_compte': compte,
          'libelle_compte': compte,
          'classe': classe,
          'date_ecriture': '2031-06-10',
          'libelle': 'Régularisation',
          'debit': debit,
          'credit': credit,
          'numero_piece': piece,
          'ecriture_contrepassee_id': null,
          'piece_origine_id': orig,
        });

        final elements = [
          ligne(
            's1',
            '5711',
            '5',
            '1500.00',
            '0.00',
            piece: 'OD-2031-00001',
            orig: origine,
          ),
          ligne(
            's2',
            '7011',
            '7',
            '0.00',
            '1500.00',
            piece: 'OD-2031-00001',
            orig: origine,
          ),
          ligne('s3', '5711', '5', '200.00', '0.00', piece: 'OD-2031-00002'),
          ligne('s4', '7011', '7', '0.00', '200.00', piece: 'OD-2031-00002'),
        ];
        await DescenteCatalogueDao(b.db).effacerCurseur();
        final bilan = await b
            .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
            .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
        expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

        // Reconnue : plus « en attente de reprise ».
        expect(await dao.piecesSaisiesNonReprises(), isEmpty);
        // Le miroir est la SEULE source des états : 1500 + 200 au produit, une fois.
        final lignes = await EcrituresServeurDao(b.db).deLAnnee(2031);
        expect(lignes, hasLength(4));
        expect(
          lignes
              .where((l) => l.numeroCompte == '7011')
              .fold<int>(0, (s, l) => s + l.creditCentimes),
          170000,
        );
        // Et la pièce du poste n'a pas bougé : ni renvoyée, ni réécrite.
        expect(await file(TableSynchronisee.piecesSaisie), hasLength(1));
        expect(
          (await dao.lignesDeLaPiece(piece.first.numeroPiece!)),
          hasLength(2),
        );
        // Rejouée : toujours quatre lignes (insert-if-absent).
        await DescenteCatalogueDao(b.db).effacerCurseur();
        await b
            .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
            .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
        expect(await EcrituresServeurDao(b.db).deLAnnee(2031), hasLength(4));
      },
    );
  });

  group('L’ordre : les comptes avant les pièces qui les citent', () {
    test(
      'file du poste : le compte est enfilé AVANT la pièce qui le cite',
      () async {
        await moteur.creerCompte('6099', 'Charges diverses', 'charge');
        await moteur.saisirPiece(
          DemandePiece(
            journal: 'OD',
            date: '2031-06-10',
            libelle: 'Charge',
            lignes: [
              LigneDemandee(
                compte: '6099',
                debitCentimes: 5000,
                creditCentimes: 0,
                centreId: bar,
              ),
              const LigneDemandee(
                compte: '5711',
                debitCentimes: 0,
                creditCentimes: 5000,
              ),
            ],
          ),
          auteurId: auteurEssai,
          valider: true,
        );
        final tables = [for (final o in await b.dao.operations()) o.table];
        expect(tables, [
          TableSynchronisee.planComptable,
          TableSynchronisee.piecesSaisie,
        ]);
      },
    );

    test('tables : plan avant pièces avant immobilisations ; descente : plan '
        'après les exercices et avant les écritures', () {
      final t = TableSynchronisee.values;
      expect(
        t.indexOf(TableSynchronisee.planComptable),
        lessThan(t.indexOf(TableSynchronisee.piecesSaisie)),
      );
      expect(
        t.indexOf(TableSynchronisee.piecesSaisie),
        lessThan(t.indexOf(TableSynchronisee.immobilisations)),
      );
      final d = TableDescendue.values;
      expect(
        d.indexOf(TableDescendue.planComptable),
        greaterThan(d.indexOf(TableDescendue.exercicesComptables)),
      );
      expect(
        d.indexOf(TableDescendue.planComptable),
        lessThan(d.indexOf(TableDescendue.ecrituresComptables)),
      );
      // Une pièce n'est PAS descendue : le miroir seul la porte.
      expect(
        TableDescendue.values.map((x) => x.nomServeur),
        isNot(contains('pieces_saisie')),
      );
    });
  });
}
