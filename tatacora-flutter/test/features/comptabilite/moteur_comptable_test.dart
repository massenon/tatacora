import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/database/declencheurs_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/plan_comptable_fichier.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// Le moteur comptable SUR UNE VRAIE BASE (Drift, SQLite, triggers compris) :
/// chaque refus du serveur, avec sa phrase exacte, et la preuve que rien n'a
/// été écrit (pièces ET compteur de séquence).
///
/// La confrontation champ à champ avec le VRAI service du serveur est dans
/// `moteur_contre_serveur_test.dart` ; ici, les cas que SQLite seul peut
/// éprouver (triggers, atomicité, compteur persisté).
void main() {
  late AppDatabase db;
  late ComptabiliteDao dao;
  late MoteurComptable moteur;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    dao = ComptabiliteDao(db);
    moteur = moteurSur(db);
  });

  tearDown(() => db.close());

  Future<DemandePiece> vente({
    String date = '2031-03-04',
    String journal = 'VTE',
    String libelle = 'Vente comptoir',
    int montant = 1250000,
  }) async {
    final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
    return DemandePiece(
      journal: journal,
      date: date,
      libelle: libelle,
      lignes: [
        // 5711 porte Hébergement par défaut ; 7061 n'en porte aucun.
        LigneDemandee(compte: '5711', debitCentimes: montant),
        LigneDemandee(
          compte: '7061',
          creditCentimes: montant,
          centreId: restaurant,
        ),
      ],
    );
  }

  Future<RefusComptable> refus(Future<Object?> action) async {
    try {
      await action;
    } on RefusComptable catch (e) {
      return e;
    }
    fail('Un refus était attendu.');
  }

  Future<int> nombreDEcritures() async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM ecritures_local')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<int> rang(String journal, int annee) async {
    final j = (await dao.journalParCode(journal))!;
    return dao.dernierRang(j.id, annee);
  }

  /// Rien n'a été écrit : aucune ligne, et le compteur n'a pas bougé.
  Future<void> exigerRienEcrit({
    String journal = 'VTE',
    int annee = 2031,
  }) async {
    expect(await nombreDEcritures(), 0, reason: 'aucune ligne ne doit rester');
    expect(
      await rang(journal, annee),
      0,
      reason: 'le compteur ne doit pas bouger',
    );
  }

  String phrase(String cle, [Map<String, String> v = const {}]) =>
      MessagesComptables.dire(cle, v);

  group('Passer une pièce — le brouillon', () {
    test(
      'deux lignes, un numéro de pièce, les centres du plan puis du choix',
      () async {
        final piece = await moteur.passer(await vente(), auteurId: auteurEssai);

        expect(piece, hasLength(2));
        expect(piece.map((l) => l.numeroPiece), everyElement('VTE-2031-00001'));
        expect(
          piece.map((l) => l.statut),
          everyElement(StatutEcriture.brouillon),
        );
        expect(piece.map((l) => l.creePar), everyElement(auteurEssai));
        expect(piece.map((l) => l.dateEcriture), everyElement('2031-03-04'));
        expect(piece.map((l) => l.libelle), everyElement('Vente comptoir'));
        expect(piece[0].debitCentimes, 1250000);
        expect(piece[0].creditCentimes, 0);
        expect(piece[1].debitCentimes, 0);
        expect(piece[1].creditCentimes, 1250000);
        expect(piece[0].debit, '12500.00');

        final heb = (await dao.centreParLibelle('Hébergement'))!.id;
        final res = (await dao.centreParLibelle('Restaurant'))!.id;
        expect(piece[0].centreId, heb, reason: 'défaut du compte 5711');
        expect(piece[1].centreId, res, reason: 'centre nommé par la ligne');

        final exercice = (await dao.exerciceDeLAnnee(2031))!;
        expect(piece.map((l) => l.exerciceId), everyElement(exercice.id));
        // Relue de la base, pas seulement rendue.
        expect((await dao.lignesDeLaPiece('VTE-2031-00001')), hasLength(2));
      },
    );

    test('le libellé d’une ligne l’emporte sur celui de la pièce', () async {
      final d = await vente();
      final piece = await moteur.passer(
        DemandePiece(
          journal: d.journal,
          date: d.date,
          libelle: d.libelle,
          lignes: [
            LigneDemandee(
              compte: '5711',
              debitCentimes: 100,
              libelle: 'Espèces',
            ),
            LigneDemandee(
              compte: '7061',
              creditCentimes: 100,
              centreId: d.lignes[1].centreId,
            ),
          ],
        ),
        auteurId: auteurEssai,
      );
      expect(piece.map((l) => l.libelle), ['Espèces', 'Vente comptoir']);
    });

    test('la séquence est PAR JOURNAL et PAR ANNÉE', () async {
      await moteur.ouvrirExercice(2032);
      final a = await moteur.passer(await vente(), auteurId: auteurEssai);
      final b = await moteur.passer(await vente(), auteurId: auteurEssai);
      final ach = await moteur.passer(
        await vente(journal: 'ACH'),
        auteurId: auteurEssai,
      );
      final suivante = await moteur.passer(
        await vente(date: '2032-01-02'),
        auteurId: auteurEssai,
      );
      expect(a.first.numeroPiece, 'VTE-2031-00001');
      expect(b.first.numeroPiece, 'VTE-2031-00002');
      expect(ach.first.numeroPiece, 'ACH-2031-00001');
      expect(suivante.first.numeroPiece, 'VTE-2032-00001');
    });

    test(
      'quatre pièces (cinq pour ACH) par journal et par année : rangs consécutifs, indépendants',
      () async {
        await moteur.ouvrirExercice(2032);
        final numeros = <String>[];
        // Entrelacé exprès : un compteur partagé ou figé se trahit.
        for (final (journal, date) in [
          ('VTE', '2031-03-04'),
          ('ACH', '2031-03-04'),
          ('VTE', '2032-01-02'),
          ('VTE', '2031-03-05'),
          ('ACH', '2031-03-06'),
          ('VTE', '2032-01-03'),
          ('VTE', '2031-03-07'),
          ('ACH', '2031-03-08'),
          ('VTE', '2032-01-04'),
          ('VTE', '2031-03-09'),
          ('ACH', '2031-03-10'),
          ('VTE', '2032-01-05'),
          ('ACH', '2031-03-11'),
        ]) {
          final p = await moteur.passer(
            await vente(journal: journal, date: date),
            auteurId: auteurEssai,
          );
          numeros.add(p.first.numeroPiece!);
        }
        List<String> de(String prefixe) =>
            numeros.where((n) => n.startsWith(prefixe)).toList();
        expect(de('VTE-2031-'), [
          'VTE-2031-00001',
          'VTE-2031-00002',
          'VTE-2031-00003',
          'VTE-2031-00004',
        ]);
        expect(de('VTE-2032-'), [
          'VTE-2032-00001',
          'VTE-2032-00002',
          'VTE-2032-00003',
          'VTE-2032-00004',
        ]);
        expect(de('ACH-2031-'), [
          for (var i = 1; i <= 5; i++) 'ACH-2031-0000$i',
        ]);
      },
    );

    test(
      'deux pièces CONCURRENTES sur le même journal : numéros distincts, sans trou',
      () async {
        final d = await vente();
        final r = await Future.wait([
          for (var i = 0; i < 6; i++) moteur.passer(d, auteurId: auteurEssai),
        ]);
        final numeros = r.map((p) => p.first.numeroPiece!).toList()..sort();
        expect(numeros, [
          for (var i = 1; i <= 6; i++)
            'VTE-2031-${i.toString().padLeft(5, '0')}',
        ]);
        expect(await rang('VTE', 2031), 6);
        // Chaque pièce garde ses deux lignes sous son seul numéro.
        for (final n in numeros) {
          expect(await dao.lignesDeLaPiece(n), hasLength(2));
        }
      },
    );

    test('un montant en centimes reste exact : 1 234 567 890,05 F', () async {
      final piece = await moteur.passer(
        await vente(montant: 123456789005),
        auteurId: auteurEssai,
      );
      expect(piece[0].debit, '1234567890.05');
      expect(piece[1].credit, '1234567890.05');
    });

    test(
      'passerEtValider : la pièce naît validée, auteur et instant relevés',
      () async {
        final piece = await moteur.passerEtValider(
          await vente(),
          auteurId: auteurEssai,
        );
        expect(
          piece.map((l) => l.statut),
          everyElement(StatutEcriture.validee),
        );
        expect(piece.map((l) => l.modifiePar), everyElement(auteurEssai));
        expect(
          piece.map((l) => l.modifieLe),
          everyElement(DateTime(2031, 6, 15, 10)),
        );
        expect(piece.map((l) => l.numeroPiece), everyElement('VTE-2031-00001'));
      },
    );
  });

  group('Les refus du serveur — phrase exacte, et RIEN d’écrit', () {
    test('journal inconnu', () async {
      final d = await vente(journal: 'ZZZ');
      final e = await refus(moteur.passer(d, auteurId: auteurEssai));
      expect(e.motif, MotifRefus.journalInconnu);
      expect(e.message, phrase('depenses.journal_inconnu', {'code': 'ZZZ'}));
      expect(e.motif.immuabilite, isFalse);
      await exigerRienEcrit();
    });

    test('compte inconnu', () async {
      final d = await vente();
      final e = await refus(
        moteur.passer(
          DemandePiece(
            journal: 'VTE',
            date: d.date,
            libelle: 'x',
            lignes: [
              d.lignes[0],
              const LigneDemandee(compte: '9999', creditCentimes: 1250000),
            ],
          ),
          auteurId: auteurEssai,
        ),
      );
      expect(e.motif, MotifRefus.compteInconnu);
      expect(e.message, phrase('depenses.compte_inconnu', {'numero': '9999'}));
      await exigerRienEcrit();
    });

    test('un compte de DIVISION est refusé : 60, 601, 4', () async {
      for (final division in ['60', '601', '4', '40', '411']) {
        final e = await refus(
          moteur.passer(
            DemandePiece(
              journal: 'ACH',
              date: '2031-03-04',
              libelle: 'x',
              lignes: [
                LigneDemandee(compte: division, debitCentimes: 100),
                const LigneDemandee(compte: '5711', creditCentimes: 100),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(e.motif, MotifRefus.compteDivision, reason: division);
        expect(
          e.message,
          phrase('comptabilite.compte_division', {'numero': division}),
          reason: division,
        );
      }
      await exigerRienEcrit(journal: 'ACH');
    });

    test(
      'les FEUILLES à moins de 4 chiffres restent imputables : 552, 131, 139',
      () async {
        for (final feuille in ['552', '131', '139']) {
          final piece = await moteur.passer(
            DemandePiece(
              journal: 'OD',
              date: '2031-03-04',
              libelle: 'Feuille $feuille',
              lignes: [
                LigneDemandee(compte: feuille, debitCentimes: 100),
                const LigneDemandee(compte: '5711', creditCentimes: 100),
              ],
            ),
            auteurId: auteurEssai,
          );
          expect(piece, hasLength(2), reason: feuille);
        }
      },
    );

    test(
      'centre absent : ni sur la ligne, ni par défaut au compte (RG-12)',
      () async {
        // 6011 (achats) n'a aucun centre par défaut au plan.
        final e = await refus(
          moteur.passer(
            const DemandePiece(
              journal: 'ACH',
              date: '2031-03-04',
              libelle: 'Achat',
              lignes: [
                LigneDemandee(compte: '6011', debitCentimes: 5000),
                LigneDemandee(compte: '5711', creditCentimes: 5000),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(e.motif, MotifRefus.centreAbsent);
        expect(e.message, phrase('depenses.centre_absent', {'numero': '6011'}));
        await exigerRienEcrit(journal: 'ACH');
      },
    );

    test(
      'aucun exercice ne couvre la date (y compris une date qui n’existe pas)',
      () async {
        for (final date in ['2035-01-01', '2031-02-30', 'hier', '']) {
          final d = await vente(date: date);
          final e = await refus(moteur.passer(d, auteurId: auteurEssai));
          expect(e.motif, MotifRefus.exerciceAbsent, reason: date);
          expect(e.message, phrase('depenses.exercice_absent', {'date': date}));
        }
        await exigerRienEcrit();
      },
    );

    test('les bornes de l’exercice sont COMPRISES : 01/01 et 31/12', () async {
      for (final date in ['2031-01-01', '2031-12-31']) {
        final piece = await moteur.passer(
          await vente(date: date),
          auteurId: auteurEssai,
        );
        expect(piece, hasLength(2), reason: date);
      }
      for (final date in ['2030-12-31', '2032-01-01']) {
        final e = await refus(
          moteur.passer(await vente(date: date), auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.exerciceAbsent, reason: date);
      }
    });

    test(
      'exercice en clôture ou clôturé : refusé, statut brut dans la phrase',
      () async {
        for (final statut in ['en_cloture', 'cloture']) {
          await db.customStatement(
            "UPDATE exercices_local SET statut = '$statut' WHERE annee = 2031",
          );
          final e = await refus(
            moteur.passer(await vente(), auteurId: auteurEssai),
          );
          expect(e.motif, MotifRefus.exerciceNonOuvert, reason: statut);
          expect(
            e.message,
            phrase('depenses.exercice_clos', {
              'annee': '2031',
              'statut': statut,
            }),
            reason: statut,
          );
        }
        await exigerRienEcrit();
      },
    );

    test('pièce vide', () async {
      final e = await refus(
        moteur.passer(
          const DemandePiece(
            journal: 'VTE',
            date: '2031-03-04',
            libelle: 'x',
            lignes: [],
          ),
          auteurId: auteurEssai,
        ),
      );
      expect(e.motif, MotifRefus.pieceVide);
      expect(e.message, phrase('comptabilite.piece_vide'));
      await exigerRienEcrit();
    });

    test('pièce déséquilibrée : l’écart dans les deux sens', () async {
      final d = await vente();
      for (final (debit, credit, ecart) in [
        (1000, 750, '2.50'),
        (750, 1000, '-2.50'),
      ]) {
        final e = await refus(
          moteur.passer(
            DemandePiece(
              journal: 'VTE',
              date: d.date,
              libelle: 'x',
              lignes: [
                LigneDemandee(compte: '5711', debitCentimes: debit),
                LigneDemandee(
                  compte: '7061',
                  creditCentimes: credit,
                  centreId: d.lignes[1].centreId,
                ),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(e.motif, MotifRefus.pieceDesequilibree);
        expect(
          e.message,
          phrase('comptabilite.piece_desequilibree', {
            'debit':
                '${debit ~/ 100}.${(debit % 100).toString().padLeft(2, '0')}',
            'credit':
                '${credit ~/ 100}.${(credit % 100).toString().padLeft(2, '0')}',
            'ecart': ecart,
          }),
        );
      }
      await exigerRienEcrit();
    });

    test('un centime d’écart suffit', () async {
      final d = await vente();
      final e = await refus(
        moteur.passer(
          DemandePiece(
            journal: 'VTE',
            date: d.date,
            libelle: 'x',
            lignes: [
              const LigneDemandee(compte: '5711', debitCentimes: 1001),
              LigneDemandee(
                compte: '7061',
                creditCentimes: 1000,
                centreId: d.lignes[1].centreId,
              ),
            ],
          ),
          auteurId: auteurEssai,
        ),
      );
      expect(e.motif, MotifRefus.pieceDesequilibree);
      expect(e.message, contains('écart de 0.01'));
    });

    test('pièce à zéro : équilibrée mais sans montant', () async {
      final d = await vente();
      final e = await refus(
        moteur.passer(
          DemandePiece(
            journal: 'VTE',
            date: d.date,
            libelle: 'x',
            lignes: [
              const LigneDemandee(compte: '5711'),
              LigneDemandee(compte: '7061', centreId: d.lignes[1].centreId),
            ],
          ),
          auteurId: auteurEssai,
        ),
      );
      expect(e.motif, MotifRefus.pieceSansMontant);
      expect(e.message, phrase('comptabilite.piece_sans_montant'));
      await exigerRienEcrit();
    });

    test(
      'ligne négative, ou débit ET crédit : refus de la base, phrase du poste',
      () async {
        final d = await vente();
        final negative = await refus(
          moteur.passer(
            DemandePiece(
              journal: 'VTE',
              date: d.date,
              libelle: 'x',
              lignes: [
                const LigneDemandee(compte: '5711', debitCentimes: -500),
                LigneDemandee(
                  compte: '7061',
                  debitCentimes: 0,
                  creditCentimes: -500,
                  centreId: d.lignes[1].centreId,
                ),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(negative.motif, MotifRefus.contrainteBase);
        expect(negative.message, PhrasesDuPoste.ligneNegative);

        final double = await refus(
          moteur.passer(
            DemandePiece(
              journal: 'VTE',
              date: d.date,
              libelle: 'x',
              lignes: [
                const LigneDemandee(
                  compte: '5711',
                  debitCentimes: 500,
                  creditCentimes: 500,
                ),
                LigneDemandee(compte: '7061', centreId: d.lignes[1].centreId),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(double.motif, MotifRefus.contrainteBase);
        expect(double.message, PhrasesDuPoste.debitEtCredit);
        await exigerRienEcrit();
      },
    );

    test(
      'un centre explicite INCONNU est refusé À L’ÉCRITURE, et tout est annulé',
      () async {
        final d = await vente();
        final e = await refus(
          moteur.passer(
            DemandePiece(
              journal: 'VTE',
              date: d.date,
              libelle: 'x',
              lignes: [
                d.lignes[0],
                const LigneDemandee(
                  compte: '7061',
                  creditCentimes: 1250000,
                  centreId: 'centre-qui-n-existe-pas',
                ),
              ],
            ),
            auteurId: auteurEssai,
          ),
        );
        expect(e.motif, MotifRefus.contrainteBase);
        expect(e.message, PhrasesDuPoste.referenceRefusee);
        // La première ligne a été écrite AVANT l'échec de la seconde, et le
        // compteur a été incrémenté : tout est rendu.
        await exigerRienEcrit();
      },
    );

    test('sans auteur, rien n’est écrit (RG-15)', () async {
      final e = await refus(moteur.passer(await vente(), auteurId: '  '));
      expect(e.motif, MotifRefus.auteurAbsent);
      await exigerRienEcrit();
    });

    test(
      'un auteur inconnu est refusé par la clé étrangère, rien d’écrit',
      () async {
        final e = await refus(
          moteur.passer(await vente(), auteurId: 'fantome'),
        );
        expect(e.motif, MotifRefus.contrainteBase);
        await exigerRienEcrit();
      },
    );
  });

  group('Tout ou rien — chaque geste tient dans UNE transaction', () {
    test('une panne à la 2e ligne annule la 1re ET le compteur', () async {
      await db.customStatement(
        'CREATE TRIGGER essai_panne BEFORE INSERT ON ecritures_local '
        "WHEN NEW.libelle = 'PIEGE' "
        "BEGIN SELECT RAISE(ABORT, 'panne simulee'); END",
      );
      final d = await vente();
      await expectLater(
        moteur.passer(
          DemandePiece(
            journal: 'VTE',
            date: d.date,
            libelle: 'x',
            lignes: [
              d.lignes[0],
              LigneDemandee(
                compte: '7061',
                creditCentimes: 1250000,
                centreId: d.lignes[1].centreId,
                libelle: 'PIEGE',
              ),
            ],
          ),
          auteurId: auteurEssai,
        ),
        throwsA(isNot(isA<RefusComptable>())),
      );
      await exigerRienEcrit();
      // Le compteur est rendu : la pièce suivante prend le numéro 1.
      final suivante = await moteur.passer(d, auteurId: auteurEssai);
      expect(suivante.first.numeroPiece, 'VTE-2031-00001');
    });

    test(
      'passerEtValider : si la validation tombe, la pièce n’existe pas',
      () async {
        await db.customStatement(
          'CREATE TRIGGER essai_panne_validation BEFORE UPDATE ON ecritures_local '
          "WHEN NEW.statut = 'validee' "
          "BEGIN SELECT RAISE(ABORT, 'panne simulee'); END",
        );
        await expectLater(
          moteur.passerEtValider(await vente(), auteurId: auteurEssai),
          throwsA(isNot(isA<RefusComptable>())),
        );
        await exigerRienEcrit();
      },
    );

    test('valider : un refus à la 2e ligne laisse la 1re en brouillon', () async {
      final a = await moteur.passer(await vente(), auteurId: auteurEssai);
      // La 2e ligne est validée « à la main » : valider() doit refuser.
      await db.customStatement(
        "UPDATE ecritures_local SET statut = 'validee' WHERE id = '${a[1].id}'",
      );
      final e = await refus(moteur.valider(a, auteurId: auteurEssai));
      expect(e.motif, MotifRefus.ecritureDejaValidee);
      expect(e.message, phrase('comptabilite.ecriture_deja_validee'));
      expect((await dao.ecriture(a[0].id))!.statut, StatutEcriture.brouillon);
    });

    test(
      'contrepasserPiece : un refus à la 2e ligne n’inverse pas la 1re',
      () async {
        final a = await moteur.passerEtValider(
          await vente(),
          auteurId: auteurEssai,
        );
        // La 2e ligne est déjà contre-passée toute seule.
        await moteur.contrepasserLigne(a[1], auteurId: auteurEssai);
        final avant = await nombreDEcritures();

        final e = await refus(
          moteur.contrepasserPiece(a, auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.dejaContrepassee);
        expect(await nombreDEcritures(), avant, reason: 'rien ne s’ajoute');
        expect(await dao.dejaContrepassee(a[0].id), isFalse);
      },
    );
  });

  group('Valider — le point de non-retour', () {
    test(
      'un brouillon devient validé ; une 2e validation est refusée',
      () async {
        final a = await moteur.passer(await vente(), auteurId: auteurEssai);
        final validees = await moteur.valider(a, auteurId: auteurEssai);
        expect(
          validees.map((l) => l.statut),
          everyElement(StatutEcriture.validee),
        );
        expect(validees.map((l) => l.modifiePar), everyElement(auteurEssai));

        final e = await refus(moteur.valider(a, auteurId: auteurEssai));
        expect(e.motif, MotifRefus.ecritureDejaValidee);
        expect(e.message, phrase('comptabilite.ecriture_deja_validee'));
      },
    );

    test(
      'une ligne devenue introuvable est un refus nommé, pas une panne',
      () async {
        final e = await refus(
          moteur.valider([
            EcritureComptable(
              id: 'fantome',
              exerciceId: 'x',
              journalId: 'x',
              compteId: 'x',
              centreId: 'x',
              dateEcriture: '2031-01-01',
              libelle: 'x',
              debitCentimes: 0,
              creditCentimes: 0,
              statut: StatutEcriture.brouillon,
              ecritureContrepasseeId: null,
              numeroPiece: null,
              creeLe: DateTime(2031),
              creePar: auteurEssai,
              modifieLe: null,
              modifiePar: null,
            ),
          ], auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.ecritureIntrouvable);
      },
    );

    test(
      'valider sur un exercice clôturé : l’observer (trigger) refuse',
      () async {
        final a = await moteur.passer(await vente(), auteurId: auteurEssai);
        await db.customStatement(
          "UPDATE exercices_local SET statut = 'cloture' WHERE annee = 2031",
        );
        final e = await refus(moteur.valider(a, auteurId: auteurEssai));
        expect(e.motif, MotifRefus.exerciceClos);
        expect(e.motif.immuabilite, isTrue);
        expect(e.message, phrase('comptabilite.exercice_clos'));
        expect((await dao.ecriture(a[0].id))!.statut, StatutEcriture.brouillon);
      },
    );
  });

  group('Contre-passer — la seule correction admise (RG-11)', () {
    test(
      'la pièce ENTIÈRE est inversée, liée, validée, datée du jour, sans numéro',
      () async {
        final a = await moteur.passerEtValider(
          await vente(),
          auteurId: auteurEssai,
        );
        final inverses = await moteur.contrepasserPiece(
          a,
          auteurId: auteurEssai,
        );

        expect(inverses, hasLength(2));
        for (var i = 0; i < 2; i++) {
          expect(inverses[i].debitCentimes, a[i].creditCentimes);
          expect(inverses[i].creditCentimes, a[i].debitCentimes);
          expect(inverses[i].ecritureContrepasseeId, a[i].id);
          expect(inverses[i].statut, StatutEcriture.validee);
          expect(inverses[i].numeroPiece, isNull);
          expect(inverses[i].dateEcriture, '2031-06-15');
          expect(inverses[i].libelle, 'Contre-passation — Vente comptoir');
          expect(inverses[i].compteId, a[i].compteId);
          expect(inverses[i].centreId, a[i].centreId);
          expect(inverses[i].exerciceId, a[i].exerciceId);
          expect(inverses[i].journalId, a[i].journalId);
          expect(inverses[i].creePar, auteurEssai);
          // L'origine n'est jamais touchée.
          final relue = (await dao.ecriture(a[i].id))!;
          expect(relue.statut, StatutEcriture.validee);
          expect(relue.debitCentimes, a[i].debitCentimes);
          expect(relue.creditCentimes, a[i].creditCentimes);
        }
        // Le solde de la pièce est nul : débit total = crédit total sur les 4 lignes
        // ET chaque compte revient à zéro.
        final toutes = await dao.toutesLesEcritures();
        expect(toutes, hasLength(4));
        for (final compte in toutes.map((l) => l.compteId).toSet()) {
          final solde = toutes
              .where((l) => l.compteId == compte)
              .fold<int>(0, (s, l) => s + l.debitCentimes - l.creditCentimes);
          expect(solde, 0);
        }
      },
    );

    test('le motif remplace le libellé, identique sur chaque ligne', () async {
      final a = await moteur.passerEtValider(
        await vente(),
        auteurId: auteurEssai,
      );
      final inverses = await moteur.contrepasserPiece(
        a,
        auteurId: auteurEssai,
        motif: 'Erreur de caisse',
      );
      expect(inverses.map((l) => l.libelle), everyElement('Erreur de caisse'));
    });

    test(
      'la date est celle du JOUR (horloge injectée), pas celle de la pièce',
      () async {
        final autre = moteurSur(
          db,
          maintenant: () => DateTime(2031, 11, 30, 23, 59),
        );
        final a = await autre.passerEtValider(
          await vente(date: '2031-02-01'),
          auteurId: auteurEssai,
        );
        final inverses = await autre.contrepasserPiece(
          a,
          auteurId: auteurEssai,
        );
        expect(inverses.map((l) => l.dateEcriture), everyElement('2031-11-30'));
      },
    );

    test('une double contre-passation est refusée', () async {
      final a = await moteur.passerEtValider(
        await vente(),
        auteurId: auteurEssai,
      );
      await moteur.contrepasserPiece(a, auteurId: auteurEssai);
      final e = await refus(moteur.contrepasserPiece(a, auteurId: auteurEssai));
      expect(e.motif, MotifRefus.dejaContrepassee);
      expect(e.motif.immuabilite, isTrue);
      expect(e.message, phrase('comptabilite.deja_contrepassee'));
      expect(await nombreDEcritures(), 4);
    });

    test(
      'un brouillon ne se contre-passe pas : il se corrige directement',
      () async {
        final a = await moteur.passer(await vente(), auteurId: auteurEssai);
        final e = await refus(
          moteur.contrepasserPiece(a, auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.contrepassationSurBrouillon);
        expect(e.message, phrase('comptabilite.contrepassation_sur_brouillon'));
        expect(await nombreDEcritures(), 2);
      },
    );

    test('une pièce vide : un refus, jamais un silence', () async {
      final e = await refus(
        moteur.contrepasserPiece([], auteurId: auteurEssai),
      );
      expect(e.motif, MotifRefus.pieceVide);
      expect(e.message, phrase('comptabilite.piece_vide'));
    });

    test('exercice clôturé : l’inverse est refusé par le trigger', () async {
      final a = await moteur.passerEtValider(
        await vente(),
        auteurId: auteurEssai,
      );
      await db.customStatement(
        "UPDATE exercices_local SET statut = 'cloture' WHERE annee = 2031",
      );
      final e = await refus(moteur.contrepasserPiece(a, auteurId: auteurEssai));
      expect(e.motif, MotifRefus.exerciceClos);
      expect(e.message, phrase('comptabilite.exercice_clos'));
      expect(await nombreDEcritures(), 2);
    });
  });

  group('RG-11 au niveau de la BASE — le trigger tient quel que soit le chemin', () {
    Future<RefusComptable> refusDeSql(String sql) async {
      try {
        await db.customStatement(sql);
      } catch (e) {
        final r = ComptabiliteDao.traduireRefusBase(e);
        if (r != null) return r;
        rethrow;
      }
      fail('La base devait refuser : $sql');
    }

    late List<EcritureComptable> validee;
    late List<EcritureComptable> brouillon;

    setUp(() async {
      validee = await moteur.passerEtValider(
        await vente(),
        auteurId: auteurEssai,
      );
      brouillon = await moteur.passer(
        await vente(libelle: 'Brouillon'),
        auteurId: auteurEssai,
      );
    });

    test(
      'une écriture validée ne se modifie sur AUCUNE de ses 14 colonnes',
      () async {
        final autreJournal = (await dao.journalParCode('ACH'))!.id;
        final autreCompte = (await dao.compteParNumero('7011'))!.id;
        final autreCentre = (await dao.centreParLibelle('Bar'))!.id;
        await moteur.ouvrirExercice(2032);
        final autreExercice = (await dao.exerciceDeLAnnee(2032))!.id;
        await semerAuteur(db, id: 'u-autre');

        final modifications = <String, String>{
          'id': "'autre-id'",
          'exercice_id': "'$autreExercice'",
          'journal_id': "'$autreJournal'",
          'compte_id': "'$autreCompte'",
          'centre_id': "'$autreCentre'",
          'date_ecriture': "'2031-03-05'",
          'libelle': "'Falsifié'",
          'debit_centimes': '999',
          'credit_centimes': '999',
          'statut': "'brouillon'",
          'ecriture_contrepassee_id': "'${brouillon[0].id}'",
          'numero_piece': "'VTE-2031-99999'",
          'cree_le': '0',
          'cree_par': "'u-autre'",
        };
        // Les 14 colonnes de la liste du trigger : aucune n'a été oubliée.
        expect(
          modifications.keys.toSet(),
          colonnesProtegeesApresValidation.toSet(),
        );

        for (final e in modifications.entries) {
          final r = await refusDeSql(
            'UPDATE ecritures_local SET ${e.key} = ${e.value} '
            "WHERE id = '${validee[0].id}'",
          );
          expect(r.motif, MotifRefus.ecritureImmuable, reason: e.key);
          expect(r.motif.immuabilite, isTrue);
          expect(
            r.message,
            phrase('comptabilite.ecriture_immuable'),
            reason: e.key,
          );
        }
        // Rien n'a bougé.
        final relue = (await dao.ecriture(validee[0].id))!;
        expect(relue.libelle, 'Vente comptoir');
        expect(relue.debitCentimes, 1250000);
      },
    );

    test('mais l’AUDIT (modifie_le, modifie_par) reste inscriptible', () async {
      await db.customStatement(
        'UPDATE ecritures_local SET modifie_le = 5, modifie_par = NULL '
        "WHERE id = '${validee[0].id}'",
      );
      expect((await dao.ecriture(validee[0].id))!.modifiePar, isNull);
    });

    test(
      'un UPDATE qui ne change AUCUNE valeur n’est pas une modification',
      () async {
        await db.customStatement(
          "UPDATE ecritures_local SET libelle = libelle WHERE id = '${validee[0].id}'",
        );
      },
    );

    test('un brouillon se modifie librement', () async {
      await db.customStatement(
        "UPDATE ecritures_local SET libelle = 'Corrigé' WHERE id = '${brouillon[0].id}'",
      );
      expect((await dao.ecriture(brouillon[0].id))!.libelle, 'Corrigé');
    });

    test('aucune écriture ne se supprime, validée ou non', () async {
      for (final l in [validee[0], brouillon[0]]) {
        final r = await refusDeSql(
          "DELETE FROM ecritures_local WHERE id = '${l.id}'",
        );
        expect(r.motif, MotifRefus.suppressionInterdite);
        expect(r.motif.immuabilite, isTrue);
        expect(
          r.message,
          phrase('comptabilite.ecriture_suppression_interdite'),
        );
      }
      expect(await nombreDEcritures(), 4);
    });

    test('exercice clôturé : ni ajout, ni modification d’un brouillon', () async {
      await db.customStatement(
        "UPDATE exercices_local SET statut = 'cloture' WHERE annee = 2031",
      );
      final ajout = await refusDeSql(
        'INSERT INTO ecritures_local (id, exercice_id, journal_id, compte_id, '
        'centre_id, date_ecriture, libelle, debit_centimes, credit_centimes, '
        "statut, cree_le, cree_par) SELECT 'neuve', exercice_id, journal_id, "
        "compte_id, centre_id, '2031-01-01', 'x', 1, 0, 'brouillon', 0, cree_par "
        "FROM ecritures_local WHERE id = '${brouillon[0].id}'",
      );
      expect(ajout.motif, MotifRefus.exerciceClos);
      expect(ajout.message, phrase('comptabilite.exercice_clos'));

      final modif = await refusDeSql(
        "UPDATE ecritures_local SET libelle = 'x' WHERE id = '${brouillon[0].id}'",
      );
      expect(modif.motif, MotifRefus.exerciceClos);

      // Une écriture VALIDÉE d'un exercice clos reste « immuable » d'abord.
      final validee0 = await refusDeSql(
        "UPDATE ecritures_local SET libelle = 'x' WHERE id = '${validee[0].id}'",
      );
      expect(validee0.motif, MotifRefus.ecritureImmuable);
    });

    test(
      'un exercice « en_cloture » n’est PAS fermé par l’observer (comme le serveur)',
      () async {
        await db.customStatement(
          "UPDATE exercices_local SET statut = 'en_cloture' WHERE annee = 2031",
        );
        await db.customStatement(
          "UPDATE ecritures_local SET libelle = 'x' WHERE id = '${brouillon[0].id}'",
        );
      },
    );

    test(
      'les contraintes CHECK de la base : négatif, débit ET crédit, statut',
      () async {
        Future<void> insere(
          String debit,
          String credit,
          String statut,
        ) => db.customStatement(
          'INSERT INTO ecritures_local (id, exercice_id, journal_id, '
          'compte_id, centre_id, date_ecriture, libelle, debit_centimes, '
          'credit_centimes, statut, cree_le, cree_par) '
          "SELECT 'c-${DateTime.now().microsecondsSinceEpoch}', exercice_id, "
          "journal_id, compte_id, centre_id, '2031-01-01', 'x', $debit, "
          "$credit, '$statut', 0, cree_par FROM ecritures_local "
          "WHERE id = '${brouillon[0].id}'",
        );
        await expectLater(insere('-1', '0', 'brouillon'), throwsA(anything));
        await expectLater(insere('0', '-1', 'brouillon'), throwsA(anything));
        await expectLater(insere('5', '5', 'brouillon'), throwsA(anything));
        await expectLater(insere('5', '0', 'annulee'), throwsA(anything));
        // Et la ligne conforme passe : le test n'est pas rouge pour une autre raison.
        await insere('5', '0', 'brouillon');
      },
    );

    test(
      'les triggers existent sur un fichier créé à neuf : exactement quatre',
      () async {
        final r = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'trigger' "
              "AND name LIKE 'rg11_%' ORDER BY name",
            )
            .get();
        expect(r.map((x) => x.data['name']), [
          'rg11_brouillon_exercice_clos_maj',
          'rg11_ecriture_jamais_supprimee',
          'rg11_ecriture_validee_immuable',
          'rg11_exercice_clos_ajout',
        ]);
      },
    );
  });

  group('Le compteur de séquence est PERSISTÉ, jamais recalculé', () {
    test(
      'le compteur fait autorité, pas le maximum des numéros écrits',
      () async {
        await moteur.passer(await vente(), auteurId: auteurEssai);
        await moteur.passer(await vente(), auteurId: auteurEssai);
        await db.customStatement(
          'UPDATE sequences_piece_local SET dernier_rang = 41',
        );
        final p = await moteur.passer(await vente(), auteurId: auteurEssai);
        expect(p.first.numeroPiece, 'VTE-2031-00042');
      },
    );

    test('au-delà de 99 999, le rang s’allonge sans tronquer', () async {
      await moteur.passer(await vente(), auteurId: auteurEssai);
      await db.customStatement(
        'UPDATE sequences_piece_local SET dernier_rang = 99999',
      );
      final p = await moteur.passer(await vente(), auteurId: auteurEssai);
      expect(p.first.numeroPiece, 'VTE-2031-100000');
    });

    test(
      'le compteur n’est pas déduit des écritures : sans pièce, il vaut zéro',
      () async {
        expect(await rang('VTE', 2031), 0);
        expect(await rang('ACH', 2031), 0);
        await moteur.passer(await vente(), auteurId: auteurEssai);
        expect(await rang('VTE', 2031), 1);
        expect(await rang('ACH', 2031), 0);
      },
    );
  });

  group('Exercices — ouvrir et clôturer', () {
    test(
      'ouvrir : l’année entière, ouvert ; bornes 2000 et 2100 admises',
      () async {
        final e = await moteur.ouvrirExercice(2032);
        expect(e.annee, 2032);
        expect(e.dateDebut, '2032-01-01');
        expect(e.dateFin, '2032-12-31');
        expect(e.statut, StatutExercice.ouvert);
        await moteur.ouvrirExercice(2000);
        await moteur.ouvrirExercice(2100);
      },
    );

    test(
      'ouvrir : hors de 2000-2100 ou déjà ouvert -> refus du serveur',
      () async {
        for (final annee in [1999, 2101, 226, 20266]) {
          final e = await refus(moteur.ouvrirExercice(annee));
          expect(e.motif, MotifRefus.exerciceAnneeInvalide, reason: '$annee');
          expect(e.message, phrase('comptabilite.exercice_annee_invalide'));
        }
        final e = await refus(moteur.ouvrirExercice(2031));
        expect(e.motif, MotifRefus.exerciceDejaExistant);
        expect(
          e.message,
          phrase('comptabilite.exercice_deja_existant', {'annee': '2031'}),
        );
      },
    );

    test(
      'clôturer : refusé tant qu’un brouillon subsiste, avec leur nombre',
      () async {
        await moteur.passer(await vente(), auteurId: auteurEssai);
        final exercice = (await dao.exerciceDeLAnnee(2031))!;
        final e = await refus(
          moteur.cloturerExercice(exercice.id, auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.clotureBrouillonsRestants);
        expect(
          e.message,
          phrase('comptabilite.cloture_brouillons_restants', {
            'nombre': '2',
            'annee': '2031',
          }),
        );
        expect(
          (await dao.exercice(exercice.id))!.statut,
          StatutExercice.ouvert,
        );
      },
    );

    test(
      'clôturer : statut, date et auteur écrits ; puis refusé s’il l’est déjà',
      () async {
        await moteur.passerEtValider(await vente(), auteurId: auteurEssai);
        final exercice = (await dao.exerciceDeLAnnee(2031))!;
        final c = await moteur.cloturerExercice(
          exercice.id,
          auteurId: auteurEssai,
        );
        expect(c.statut, StatutExercice.cloture);
        expect(c.dateCloture, DateTime(2031, 6, 15, 10));
        expect(c.utilisateurClotureId, auteurEssai);

        final e = await refus(
          moteur.cloturerExercice(exercice.id, auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.exerciceDejaCloture);
        expect(
          e.message,
          phrase('comptabilite.exercice_deja_cloture', {'annee': '2031'}),
        );

        // Et une pièce datée de cet exercice est désormais refusée.
        final p = await refus(
          moteur.passer(await vente(), auteurId: auteurEssai),
        );
        expect(p.motif, MotifRefus.exerciceNonOuvert);
        expect(
          p.message,
          phrase('depenses.exercice_clos', {
            'annee': '2031',
            'statut': 'cloture',
          }),
        );
      },
    );

    test('LE CAS DU 01/01/2027 : un poste laissé allumé la nuit du 31/12 — '
        'la PREMIÈRE pièce de 2027 ouvre l’exercice, sans redémarrage '
        '(passage d’année, 20/10/2026)', () async {
      // Un poste installé en 2026 : l'exercice 2026 est ouvert.
      final poste = await baseInstallee(maintenant: DateTime(2026, 12, 31));
      addTearDown(poste.close);
      final au2027 = moteurSur(
        poste,
        maintenant: () => DateTime(2027, 1, 1, 0, 30),
      );
      final dao2 = ComptabiliteDao(poste);
      final restaurant = (await dao2.centreParLibelle('Restaurant'))!.id;
      DemandePiece piece(String date) => DemandePiece(
        journal: 'VTE',
        date: date,
        libelle: 'Vente',
        lignes: [
          const LigneDemandee(compte: '5711', debitCentimes: 100),
          LigneDemandee(
            compte: '7061',
            creditCentimes: 100,
            centreId: restaurant,
          ),
        ],
      );

      // Le dernier jour de 2026 passe ; le premier de 2027 aussi — jusqu'au
      // 20/10/2026, il était refusé tant que le poste n'avait pas redémarré.
      expect(
        await au2027.passer(piece('2026-12-31'), auteurId: auteurEssai),
        hasLength(2),
      );
      expect(
        await au2027.passer(piece('2027-01-01'), auteurId: auteurEssai),
        hasLength(2),
      );
      final ouvert = (await dao2.exerciceDeLAnnee(2027))!;
      expect(ouvert.statut, StatutExercice.ouvert);
      expect(ouvert.dateDebut, '2027-01-01');
      expect(ouvert.dateFin, '2027-12-31');
      // 2026 reste ouvert : écritures d'inventaire en N pendant N+1.
      expect(
        (await dao2.exerciceDeLAnnee(2026))!.statut,
        StatutExercice.ouvert,
      );

      // Une date FANTAISISTE ou une année passée manquante n'ouvre rien.
      for (final date in ['2031-05-04', '2019-03-02']) {
        final e = await refus(
          au2027.passer(piece(date), auteurId: auteurEssai),
        );
        expect(e.motif, MotifRefus.exerciceAbsent, reason: date);
      }
      expect(await dao2.exerciceDeLAnnee(2031), isNull);
      expect(await dao2.exerciceDeLAnnee(2019), isNull);

      // Le démarrage suivant ne recrée rien (D197, option (b) : idempotent).
      final bilan = await installerReferentielComptable(
        poste,
        contenuPlan: lirePlanEmbarque(),
        maintenant: DateTime(2027, 1, 1),
      );
      expect(bilan.exerciceSeme, isNull);

      // Le geste explicite reste le chemin des AUTRES années, et refuse
      // d'ouvrir une année qui existe déjà.
      expect(
        (await refus(au2027.ouvrirExercice(2027))).motif,
        MotifRefus.exerciceDejaExistant,
      );
      await au2027.ouvrirExercice(2028);
    });
  });

  group('Plan comptable — créer un compte, lister les charges', () {
    test(
      'un compte de 2 à 4 chiffres : classe dérivée, aucun centre, nature posée',
      () async {
        final c = await moteur.creerCompte('6099', '  Divers  ', 'charge');
        expect(c.numero, '6099');
        expect(c.libelle, 'Divers');
        expect(c.classe, '6');
        expect(c.nature, 'charge');
        expect(c.centreCoutDefautId, isNull);
        // '10' n'est pas au plan du PO (le chiffre 1 est la classe, 11 à 19 les
        // divisions) : un compte à DEUX chiffres est admis.
        await moteur.creerCompte('10', 'Deux chiffres', 'actif');
      },
    );

    test(
      'numéro invalide, libellé vide, nature inconnue, compte déjà au plan',
      () async {
        for (final n in ['7', '12345', '0123', 'abcd', '', '60 99']) {
          final e = await refus(moteur.creerCompte(n, 'x', 'charge'));
          expect(e.motif, MotifRefus.compteNumeroInvalide, reason: n);
          expect(
            e.message,
            phrase('comptabilite.compte_numero_invalide', {'numero': n}),
          );
        }
        final v = await refus(moteur.creerCompte('6099', '   ', 'charge'));
        expect(v.motif, MotifRefus.compteLibelleRequis);
        expect(v.message, phrase('comptabilite.compte_libelle_requis'));

        final n = await refus(moteur.creerCompte('6099', 'x', 'bizarre'));
        expect(n.motif, MotifRefus.compteNatureInvalide);
        expect(
          n.message,
          phrase('comptabilite.compte_nature_invalide', {'nature': 'bizarre'}),
        );

        final d = await refus(moteur.creerCompte('4111', 'x', 'actif'));
        expect(d.motif, MotifRefus.compteDejaExistant);
        expect(
          d.message,
          phrase('comptabilite.compte_deja_existant', {'numero': '4111'}),
        );
        expect(await dao.compteParNumero('6099'), isNull);
      },
    );

    test(
      'comptes de charge : classe 6, 4 chiffres ou plus, triés — jamais une division',
      () async {
        final charges = await moteur.comptesDeCharge();
        // La source INDÉPENDANTE : le fichier, relu ici.
        final attendus =
            lirePlanComptable(lirePlanEmbarque())
                .where((c) => c.numero.startsWith('6') && c.numero.length >= 4)
                .map((c) => c.numero)
                .toList()
              ..sort();
        expect(attendus.length, greaterThan(50));
        expect(charges.map((c) => c.numero).toList(), attendus);
        expect(charges.map((c) => c.numero), isNot(contains('60')));
        expect(charges.map((c) => c.numero), isNot(contains('601')));
        expect(charges.map((c) => c.numero), contains('6011'));
      },
    );
  });
}
