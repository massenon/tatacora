import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/data/piece_de_la_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/indicateurs_depenses.dart';
import 'package:tatacora_flutter/features/depenses/impression/etat_depenses.dart';
import 'package:tatacora_flutter/features/depenses/presentation/providers_depenses.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_depenses.dart';

/// La dépense ET sa pièce comptable : le chemin RÉEL (`DepenseDao` -> moteur
/// comptable -> base), jamais un dépôt bouché.
///
/// Règle du 31/08/2026 : tout mouvement d'argent produit sa pièce comptable
/// dans la MÊME transaction, et si la pièce est refusée rien n'est écrit. Les
/// cas ci-dessous la prouvent sur une vraie base — pièces relues, compteurs de
/// séquence relevés — et chaque comportement a été MUTÉ pour prouver que son
/// assertion n'est pas vide (voir le ticket).
void main() {
  late AppDatabase db;
  late DepenseDao dao;
  late ComptabiliteDao compta;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = await baseDepenses();
    dao = depenseDaoSur(db);
    compta = ComptabiliteDao(db);
  });

  tearDown(() => db.close());

  SaisieLigneDepense achat(
    String compte,
    int montant, {
    String libelle = 'Achat',
    NatureDepense nature = NatureDepense.tomate,
  }) => SaisieLigneDepense(
    libelle: libelle,
    compteCharge: compte,
    nature: nature,
    montant: montant,
  );

  Future<Depense> depenser(
    List<SaisieLigneDepense> lignes, {
    TresorerieDepense tresorerie = TresorerieDepense.caisse,
    String? centre = 'Restaurant',
    DateTime? date,
    String libelle = 'Marché du matin',
  }) async => dao.enregistrer(
    dateTransaction: date ?? DateTime(2026, 9, 10),
    tresorerie: tresorerie,
    libelle: libelle,
    lignes: lignes,
    auteurId: auteurDepense,
    centreId: centre == null ? null : await centreDe(db, centre),
  );

  Future<List<EcritureComptable>> piece(String numero) =>
      compta.lignesDeLaPiece(numero);

  /// Ce qu'un refus ne doit pas avoir fait bouger : la dépense, ses lignes, les
  /// écritures ET le compteur de séquence.
  Future<Map<String, int>> releve() async => {
    'depenses': await compter(db, 'depenses_local'),
    'lignes': await compter(db, 'lignes_depense_local'),
    'ecritures': await compter(db, 'ecritures_local'),
    'sequences': await compter(db, 'sequences_piece_local'),
  };

  group('La pièce : une fonction pure, la contrepartie ajoutée ICI', () {
    test(
      'charges au débit, trésorerie seule au crédit du total, en centimes',
      () {
        final p = pieceDeLaDepense(
          tresorerie: TresorerieDepense.momo,
          dateIso: '2026-09-10',
          libelleDepense: 'Minibus',
          lignes: const [
            (libelle: 'Location', compte: '6223', montant: 25000),
            (libelle: 'Péage', compte: '6223', montant: 1500),
          ],
          centreId: 'c-tourisme',
        );

        expect(p.journal, 'BQ');
        expect(p.date, '2026-09-10');
        expect(p.libelle, 'Dépense — Minibus');
        expect(p.lignes, hasLength(3));
        expect(p.lignes[0].debitCentimes, 2500000);
        expect(p.lignes[1].debitCentimes, 150000);
        expect(p.lignes[2].compte, '552');
        expect(p.lignes[2].creditCentimes, 2650000);
        expect(p.lignes[2].debitCentimes, 0);
        expect(p.lignes[2].libelle, 'Minibus');
        // Le centre explicite s'applique à CHAQUE ligne, trésorerie comprise.
        expect(p.lignes.map((l) => l.centreId), everyElement('c-tourisme'));
      },
    );

    test('un libellé de ligne vide prend celui de la dépense', () {
      final p = pieceDeLaDepense(
        tresorerie: TresorerieDepense.caisse,
        dateIso: '2026-09-10',
        libelleDepense: 'Gaz',
        lignes: const [(libelle: '  ', compte: '6052', montant: 7000)],
      );
      expect(p.lignes.first.libelle, 'Gaz');
      expect(p.lignes.first.centreId, isNull);
    });

    test('le total est la somme des lignes — aucun total n’est reçu', () {
      final p = pieceDeLaDepense(
        tresorerie: TresorerieDepense.banque,
        dateIso: '2026-09-10',
        libelleDepense: 'x',
        lignes: [
          for (var i = 1; i <= 10; i++)
            (libelle: 'l$i', compte: '6052', montant: i * 1000),
        ],
      );
      expect(p.lignes.last.creditCentimes, 5500000);
      expect(
        p.lignes.fold<int>(0, (s, l) => s + l.debitCentimes),
        p.lignes.last.creditCentimes,
      );
    });
  });

  group('La dépense et sa pièce sont écrites ENSEMBLE', () {
    test('une dépense à trois lignes : quatre écritures validées, équilibrées, '
        'sous un seul numéro', () async {
      final d = await depenser([
        achat('6011', 15000, libelle: 'Oignons'),
        achat('6011', 8500, libelle: 'Tomates'),
        achat('6223', 3500, libelle: 'Transport'),
      ]);

      expect(d.montantTotal, 27000);
      expect(d.estComptabilisee, isTrue);
      expect(d.numeroPiece, 'CAI-2026-00001');

      final lignes = await piece('CAI-2026-00001');
      expect(lignes, hasLength(4));
      expect(lignes.every((l) => l.estValidee), isTrue);
      expect(lignes.every((l) => l.creePar == auteurDepense), isTrue);
      expect(lignes.map((l) => l.dateEcriture), everyElement('2026-09-10'));
      // Montants en CENTIMES exacts : 27 000 F = 2 700 000 centimes.
      expect(lignes.fold<int>(0, (s, l) => s + l.debitCentimes), 2700000);
      expect(lignes.fold<int>(0, (s, l) => s + l.creditCentimes), 2700000);
      final debits = [for (final l in lignes) l.debitCentimes]..sort();
      expect(debits, [0, 350000, 850000, 1500000]);
    });

    test(
      'ecriture_id désigne la ligne de TRESORERIE (la seule au crédit)',
      () async {
        final d = await depenser([achat('6011', 15000), achat('6011', 8500)]);
        final tresorerie = (await compta.ecriture(d.ecritureId!))!;
        expect(tresorerie.creditCentimes, 2350000);
        expect(tresorerie.debitCentimes, 0);
        expect((await compta.compteParId(tresorerie.compteId))!.numero, '5711');
      },
    );

    for (final cas in [
      (TresorerieDepense.caisse, '5711', 'CAI'),
      (TresorerieDepense.momo, '552', 'BQ'),
      (TresorerieDepense.banque, '5211', 'BQ'),
    ]) {
      test('${cas.$1.libelle} : compte ${cas.$2}, journal ${cas.$3}', () async {
        final d = await depenser([achat('6052', 12000)], tresorerie: cas.$1);
        final lignes = await piece(d.numeroPiece!);
        final tres = lignes.firstWhere((l) => l.creditCentimes > 0);
        expect((await compta.compteParId(tres.compteId))!.numero, cas.$2);
        final journaux = {
          for (final j in await compta.journaux()) j.id: j.code,
        };
        expect(lignes.map((l) => journaux[l.journalId]), everyElement(cas.$3));
        expect(d.numeroPiece, startsWith('${cas.$3}-2026-'));
      });
    }

    test('la charge est imputée au compte SAISI, au centre choisi', () async {
      final d = await depenser([achat('6052', 45000)], centre: 'Structure');
      final lignes = await piece(d.numeroPiece!);
      final charge = lignes.firstWhere((l) => l.debitCentimes > 0);
      expect((await compta.compteParId(charge.compteId))!.numero, '6052');
      expect(charge.centreId, await centreDe(db, 'Structure'));
    });

    test(
      'sans centre, le défaut du compte joue ; la caisse porte Hébergement',
      () async {
        await donnerCentreParDefaut(db, '6052', 'Tourisme');
        final d = await depenser([achat('6052', 5000)], centre: null);
        final lignes = await piece(d.numeroPiece!);
        final charge = lignes.firstWhere((l) => l.debitCentimes > 0);
        final tres = lignes.firstWhere((l) => l.creditCentimes > 0);
        expect(charge.centreId, await centreDe(db, 'Tourisme'));
        expect(tres.centreId, await centreDe(db, 'Hébergement'));
      },
    );

    test('les rangs de séquence avancent par journal', () async {
      final a = await depenser([achat('6052', 1000)]);
      final b = await depenser([achat('6052', 2000)]);
      final c = await depenser([
        achat('6052', 3000),
      ], tresorerie: TresorerieDepense.banque);
      expect(
        [a.numeroPiece, b.numeroPiece, c.numeroPiece],
        ['CAI-2026-00001', 'CAI-2026-00002', 'BQ-2026-00001'],
      );
    });
  });

  group('Si la pièce est refusée, RIEN n’est écrit', () {
    test(
      'exercice absent (2035) : la phrase du serveur, aucune écriture',
      () async {
        final avant = await releve();
        final r = await expectRefus(
          depenser([achat('6052', 5000)], date: DateTime(2035, 1, 1)),
        );
        expect(r.motif, MotifRefus.exerciceAbsent);
        expect(
          r.message,
          MessagesComptables.dire('depenses.exercice_absent', {
            'date': '2035-01-01',
          }),
        );
        expect(await releve(), avant);
      },
    );

    test(
      'centre absent (RG-12) : la phrase du serveur, aucune écriture',
      () async {
        final avant = await releve();
        final r = await expectRefus(
          depenser([achat('6011', 5000)], centre: null),
        );
        expect(r.motif, MotifRefus.centreAbsent);
        expect(
          r.message,
          MessagesComptables.dire('depenses.centre_absent', {'numero': '6011'}),
        );
        expect(await releve(), avant);
        // Le compteur n'a pas bougé : le prochain numéro est le PREMIER.
        expect(
          (await depenser([achat('6011', 1)])).numeroPiece,
          'CAI-2026-00001',
        );
      },
    );

    test('compte inconnu : refusé à la saisie, aucune écriture', () async {
      final avant = await releve();
      await expectLater(
        depenser([achat('999999', 5000)]),
        throwsA(
          isA<RefusDepense>().having(
            (e) => e.message,
            'message',
            "Ligne 1 : ce compte n'existe pas au plan comptable.",
          ),
        ),
      );
      expect(await releve(), avant);
    });

    test(
      'un compte de DIVISION (601) est refusé par le moteur, rien d’écrit',
      () async {
        final avant = await releve();
        final r = await expectRefus(depenser([achat('601', 5000)]));
        expect(r.motif, MotifRefus.compteDivision);
        expect(await releve(), avant);
      },
    );

    test('exercice non ouvert (en clôture) : aucune écriture', () async {
      await db.customStatement(
        "UPDATE exercices_local SET statut = 'en_cloture' WHERE annee = 2026",
      );
      final avant = await releve();
      final r = await expectRefus(depenser([achat('6052', 5000)]));
      expect(r.motif, MotifRefus.exerciceNonOuvert);
      expect(await releve(), avant);
    });

    test(
      'sans auteur, la pièce est refusée (RG-15) et rien n’est écrit',
      () async {
        final avant = await releve();
        try {
          await dao.enregistrer(
            dateTransaction: DateTime(2026, 9, 10),
            tresorerie: TresorerieDepense.caisse,
            libelle: 'x',
            lignes: [achat('6052', 5000)],
            auteurId: '',
            centreId: await centreDe(db, 'Structure'),
          );
          fail('Un refus était attendu.');
        } on RefusComptable catch (e) {
          expect(e.motif, MotifRefus.auteurAbsent);
        }
        expect(await releve(), avant);
      },
    );

    test('une panne à l’écriture des LIGNES annule la dépense, la pièce ET le '
        'compteur — une seule transaction', () async {
      // Le trigger lève APRÈS que la pièce et l'en-tête de la dépense sont
      // écrits : sans une transaction commune, l'argent resterait enregistré
      // sans ses lignes, ou la pièce sans sa dépense.
      await db.customStatement(
        'CREATE TRIGGER panne_lignes BEFORE INSERT ON lignes_depense_local '
        "BEGIN SELECT RAISE(ABORT, 'panne simulée'); END",
      );
      final avant = await releve();
      await expectLater(
        depenser([
          achat('6052', 5000),
          achat('6052', 6000),
        ], centre: 'Structure'),
        throwsA(anything),
      );
      expect(await releve(), avant);
      expect(avant['ecritures'], 0);
      expect(avant['sequences'], 0);

      await db.customStatement('DROP TRIGGER panne_lignes');
      expect(
        (await depenser([
          achat('6052', 5000),
        ], centre: 'Structure')).numeroPiece,
        'CAI-2026-00001',
        reason: 'le rang a été rendu',
      );
    });

    test(
      'sans moteur branché, écrire une dépense LÈVE et n’écrit rien',
      () async {
        final sansMoteur = DepenseDao(db);
        final avant = await releve();
        await expectLater(
          sansMoteur.enregistrer(
            dateTransaction: DateTime(2026, 9, 10),
            tresorerie: TresorerieDepense.caisse,
            libelle: 'x',
            lignes: [achat('6052', 5000)],
            auteurId: auteurDepense,
            centreId: await centreDe(db, 'Structure'),
          ),
          throwsStateError,
        );
        expect(await releve(), avant);
      },
    );
  });

  group('Le rattrapage d’une dépense ANTÉRIEURE', () {
    // Le centre est un paramètre OBLIGATOIRE du geste (10/10/2026) : aucun
    // `donnerCentreParDefaut` posé à la main, le centre vient de l'appelant.
    test('passe la pièce, une seule, à la date de la dépense — centre sur '
        'les charges ET la trésorerie', () async {
      await semerDepenseAncienne(db);
      final structure = await centreDe(db, 'Structure');

      final d = await dao.comptabiliser(
        'dep-ancienne',
        auteurId: auteurDepense,
        centreId: structure,
      );
      expect(d.estComptabilisee, isTrue);
      expect(d.numeroPiece, 'CAI-2026-00001');
      expect(d.ecritureRefus, isNull);
      final lignes = await piece('CAI-2026-00001');
      expect(lignes, hasLength(2));
      expect(lignes.map((l) => l.dateEcriture), everyElement('2026-08-20'));
      expect(lignes.map((l) => l.centreId), everyElement(structure));

      // Idempotent : repasser (même avec un autre centre) ne crée pas une
      // seconde pièce et ne change pas la première.
      final avant = await releve();
      await dao.comptabiliser(
        'dep-ancienne',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Tourisme'),
      );
      expect(await releve(), avant);
      expect(
        (await piece('CAI-2026-00001')).map((l) => l.centreId),
        everyElement(structure),
      );
    });

    test('le centre EXPLICITE l’emporte sur le défaut du compte', () async {
      await semerDepenseAncienne(db);
      await donnerCentreParDefaut(db, '6052', 'Structure');

      await dao.comptabiliser(
        'dep-ancienne',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Tourisme'),
      );
      final lignes = await piece('CAI-2026-00001');
      expect(
        lignes.map((l) => l.centreId),
        everyElement(await centreDe(db, 'Tourisme')),
        reason: 'charge ET trésorerie portent le centre choisi',
      );
    });

    test('SANS centre : refus RG-12 avec la phrase du serveur, raison '
        'consignée, rien d’écrit ; AVEC centre, la raison disparaît', () async {
      await semerDepenseAncienne(db);
      final avant = await releve();

      final r = await expectRefus(
        dao.comptabiliser(
          'dep-ancienne',
          auteurId: auteurDepense,
          centreId: '',
        ),
      );
      expect(r.motif, MotifRefus.centreAbsent);
      final phrase = MessagesComptables.dire('depenses.centre_absent', {
        'numero': '6052',
      });
      expect(r.message, phrase);
      expect(await releve(), avant);
      final relue = (await dao.parId('dep-ancienne'))!;
      expect(relue.estComptabilisee, isFalse);
      expect(relue.ecritureRefus, phrase);

      final faite = await dao.comptabiliser(
        'dep-ancienne',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Structure'),
      );
      expect(faite.estComptabilisee, isTrue);
      expect(faite.ecritureRefus, isNull);
    });

    test('un autre refus (compte inconnu) consigne sa raison et n’écrit rien; '
        'le succès l’efface', () async {
      await semerDepenseAncienne(db, compte: '601100');
      final avant = await releve();
      final r = await expectRefus(
        dao.comptabiliser(
          'dep-ancienne',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Structure'),
        ),
      );
      final phrase = MessagesComptables.dire('depenses.compte_inconnu', {
        'numero': '601100',
      });
      expect(r.message, phrase);
      expect(await releve(), avant);
      final relue = (await dao.parId('dep-ancienne'))!;
      expect(relue.estComptabilisee, isFalse);
      expect(relue.ecritureRefus, phrase);

      // Corrigé (le compte de la ligne devient celui du plan), le rattrapage
      // aboutit et la raison disparaît.
      await db.customStatement(
        "UPDATE lignes_depense_local SET compte_charge = '6052'",
      );
      final faite = await dao.comptabiliser(
        'dep-ancienne',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Structure'),
      );
      expect(faite.estComptabilisee, isTrue);
      expect(faite.ecritureRefus, isNull);
    });

    test('une dépense inconnue est refusée en clair', () async {
      await expectLater(
        dao.comptabiliser(
          'n-existe-pas',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Structure'),
        ),
        throwsA(isA<RefusDepense>()),
      );
    });
  });

  group('Ce que l’écran lit', () {
    test(
      'le numéro de pièce est LU de l’écriture, la colonne ne le stocke pas',
      () async {
        final d = await depenser([achat('6052', 5000)], centre: 'Structure');
        final colonnes =
            (await db.customSelect('PRAGMA table_info(depenses_local)').get())
                .map((c) => c.data['name'])
                .toSet();
        expect(colonnes, containsAll(['ecriture_id', 'ecriture_refus']));
        expect(colonnes.any((c) => '$c'.contains('numero')), isFalse);
        expect(d.numeroPiece, 'CAI-2026-00001');
      },
    );

    test(
      '« Sans écriture » compte les dépenses sans pièce — et seulement elles',
      () async {
        await depenser([achat('6052', 5000)], centre: 'Structure');
        await semerDepenseAncienne(db);
        final k = IndicateursDepenses.calculer(await dao.depenses());
        expect(k.nombre, 2);
        expect(k.sansEcriture, 1);

        // Une fois rattrapée, plus aucune.
        await dao.comptabiliser(
          'dep-ancienne',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Structure'),
        );
        expect(
          IndicateursDepenses.calculer(await dao.depenses()).sansEcriture,
          0,
        );
      },
    );

    test('le total décaissé ne change pas avec la pièce (même somme)', () async {
      await depenser([
        achat('6052', 5000),
        achat('6052', 7000),
      ], centre: 'Structure');
      await semerDepenseAncienne(db);
      final k = IndicateursDepenses.calculer(await dao.depenses());
      expect(k.total, 24000);
      // Chaque ligne compte dans SA famille : la tomate en « Marché », l'entretien
      // hérité en « Services ».
      expect(k.marche, 12000);
      expect(k.services, 12000);
    });
  });

  group('L’export CSV porte la comptabilisation (de bout en bout)', () {
    test('bytes UTF-8 avec BOM, colonne « Comptabilisation » et numéro de '
        'pièce', () async {
      await depenser([achat('6052', 45000)], centre: 'Structure');
      await semerDepenseAncienne(db);
      final liste = await dao.depenses();

      final octets = EtatDepenses(
        lignes: liste,
        portee: 'Registre entier, aucun filtre appliqué',
      ).csvOctets();

      // Le BOM est ENCODÉ (utf8.encode), pas un caractère recopié dans une
      // chaîne : un tableur en configuration française lit ces trois octets.
      expect(octets.take(3), utf8.encode('\u{FEFF}'));
      final texte = utf8.decode(octets);
      final lignes = const LineSplitter()
          .convert(texte.substring(1))
          .where((l) => l.isNotEmpty)
          .toList();
      final entete = lignes.firstWhere((l) => l.startsWith('Date;'));
      expect(
        entete,
        'Date;Libellé;Nature;Charge (SYSCOHADA);Trésorerie;Montant (FCFA);'
        'Comptabilisation;Pièce comptable',
      );
      final corps = lignes.skipWhile((l) => l != entete).skip(1).toList();
      expect(corps, hasLength(2));
      final avecPiece = corps.firstWhere((l) => l.contains('CAI-2026-00001'));
      expect(avecPiece, contains(';comptabilisée;CAI-2026-00001'));
      expect(avecPiece, contains(';45000;'));
      final sansPiece = corps.firstWhere((l) => !l.contains('CAI-2026-00001'));
      expect(sansPiece, endsWith(';non comptabilisée;—'));
      // Aucune mention ne prétend que ce poste ne tient pas de comptabilité.
      expect(texte, isNot(contains('ne tient ni plan comptable')));
    });
  });

  group('La chaîne de production : fournisseurs -> moteur réel -> base', () {
    test(
      'depotDepensesProvider branche le moteur sur l’horloge réelle',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final reelle = AppDatabase.enMemoire();
        addTearDown(reelle.close);
        await reelle.customStatement('SELECT 1');
        await semerAuteur(reelle);
        final conteneur = ProviderContainer(
          overrides: [baseLocaleProvider.overrideWithValue(reelle)],
        );
        addTearDown(conteneur.dispose);

        // Aucun moteur n'est surchargé : l'asset du plan est lu par `rootBundle`,
        // le référentiel installé à la date réelle, puis la dépense passée.
        final centre = await conteneur
            .read(centresDeCoutProvider.future)
            .then((c) => c.firstWhere((x) => x.libelle == 'Restaurant').id);
        final maintenant = DateTime.now();
        final d = await conteneur
            .read(depotDepensesProvider)
            .enregistrer(
              dateTransaction: maintenant,
              tresorerie: TresorerieDepense.caisse,
              libelle: 'Marché',
              lignes: [achat('6011', 8500)],
              auteurId: auteurDepense,
              centreId: centre,
            );
        expect(d.estComptabilisee, isTrue);
        expect(d.numeroPiece, 'CAI-${maintenant.year}-00001');
        expect(await compter(reelle, 'ecritures_local'), 2);

        final comptes = await conteneur.read(comptesDeChargeProvider.future);
        expect(comptes.every((c) => c.numero.length == 4), isTrue);
        expect(comptes.every((c) => c.numero.startsWith('6')), isTrue);
        expect(comptes.any((c) => c.numero == '6011'), isTrue);
        // Aucune division, aucun compte à trois chiffres.
        expect(comptes.any((c) => c.numero == '601'), isFalse);
      },
    );
  });
}

/// Attend un [RefusComptable] et le rend.
Future<RefusComptable> expectRefus(Future<Object?> action) async {
  try {
    await action;
  } on RefusComptable catch (e) {
    return e;
  }
  fail('Un refus comptable était attendu.');
}
