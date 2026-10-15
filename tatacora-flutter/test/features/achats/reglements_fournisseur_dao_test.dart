import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/reglements_fournisseur_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/reglement_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_reglement.dart';
import 'package:tatacora_flutter/features/achats/domain/regles_reglement.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/facturation/domain/messages_encaissement.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// Le DAO des règlements, par la base : ce que le serveur fait, et ce que
/// `reglement_contre_serveur_test.dart` ne peut pas dire — l'ATOMICITÉ, la
/// concurrence, l'annulation et l'absence de moteur.
void main() {
  // Un second poste (sans exercice) est ouvert dans un cas : voulu.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ReglementsFournisseurDao dao;
  late String c1;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
    await semerAuteur(db);
    await baseInstalleeSur(db, jourReglement);
    dao = reglementsDaoSur(db);
    c1 = await semerCommande(db); // 4 000 F
  });

  tearDown(() => db.close());

  Future<int> compterEcritures() async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM ecritures_local')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<ReglementFournisseur> regler(
    String montant, {
    String tresorerie = 'caisse',
    String? commande,
  }) => dao.regler(
    commandeId: commande ?? c1,
    montantSaisi: montant,
    tresorerieSaisie: tresorerie,
    auteurId: auteurEssai,
  );

  group('Le règlement et sa pièce : tout ou rien', () {
    test('un règlement écrit DEUX lignes : Dr 4011 / Cr trésorerie, au '
        'journal de la trésorerie, validées', () async {
      final r = await regler('1500', tresorerie: 'momo');

      expect(r.montantCentimes, 150000);
      expect(r.tresorerie, TresorerieDepense.momo);
      expect(r.statut, StatutReglement.actif);
      expect(r.dateReglement, '2026-10-13');
      expect(r.utilisateurCreationId, auteurEssai);

      final compta = ComptabiliteDao(db);
      final lignes = await compta.lignesParLibelle(
        'Règlement fournisseur Grand Marche SARL — ${r.id}',
      );
      expect(lignes, hasLength(2));
      final journaux = {for (final j in await compta.journaux()) j.id: j.code};
      // Le mobile money entre au journal de BANQUE (D209 du serveur, répliqué).
      expect(lignes.map((l) => journaux[l.journalId]).toSet(), {'BQ'});
      final debit = lignes.firstWhere((l) => l.debitCentimes > 0);
      final credit = lignes.firstWhere((l) => l.creditCentimes > 0);
      expect((await compta.compteParId(debit.compteId))!.numero, '4011');
      expect((await compta.compteParId(credit.compteId))!.numero, '552');
      expect(debit.debitCentimes, 150000);
      expect(credit.creditCentimes, 150000);
      expect(lignes.every((l) => l.statut.name == 'validee'), isTrue);
    });

    test('une pièce REFUSÉE emporte le règlement ET la séquence : rien n’est '
        'écrit', () async {
      // Un exercice installé pour 2031 seulement : la pièce du 13/10/2026 n'a
      // aucun exercice où se poser.
      final autre = AppDatabase.enMemoire();
      addTearDown(autre.close);
      await autre.customStatement('SELECT 1');
      await semerAuteur(autre);
      await baseInstalleeSur(autre, DateTime(2031, 6, 15));
      final commande = await semerCommande(autre);
      final daoSansExercice = ReglementsFournisseurDao(
        autre,
        maintenant: () => jourReglement,
        moteur: () async => moteurSur(autre, maintenant: () => jourReglement),
      );

      await expectLater(
        daoSansExercice.regler(
          commandeId: commande,
          montantSaisi: '1000',
          tresorerieSaisie: 'caisse',
          auteurId: auteurEssai,
        ),
        throwsA(isA<RefusComptable>()),
      );

      expect(await compterReglements(autre), 0);
      final r = await autre
          .customSelect('SELECT COUNT(*) AS n FROM ecritures_local')
          .getSingle();
      expect(r.data['n'], 0);
      final s = await autre
          .customSelect('SELECT COUNT(*) AS n FROM sequences_piece_local')
          .getSingle();
      expect(s.data['n'], 0, reason: 'le compteur de séquence est défait');
    });

    test('sans moteur comptable, écrire LÈVE : jamais un règlement sans '
        'pièce', () async {
      final sansMoteur = ReglementsFournisseurDao(
        db,
        maintenant: () => jourReglement,
      );

      await expectLater(
        sansMoteur.regler(
          commandeId: c1,
          montantSaisi: '1000',
          tresorerieSaisie: 'caisse',
          auteurId: auteurEssai,
        ),
        throwsStateError,
      );
      expect(await compterReglements(db), 0);
    });

    test('un auteur vide est refusé : un règlement sans nom de qui l’a '
        'décaissé romprait RG-15', () async {
      await expectLater(
        dao.regler(
          commandeId: c1,
          montantSaisi: '1000',
          tresorerieSaisie: 'caisse',
          auteurId: '',
        ),
        throwsA(
          isA<RefusReglement>().having(
            (e) => e.message,
            'message',
            MessagesReglement.auteurInconnu,
          ),
        ),
      );
      expect(await compterReglements(db), 0);
      expect(await compterEcritures(), 0);
    });
  });

  group('L’ordre des contrôles est celui du serveur (D277, mutation M4)', () {
    // `enregistrerReglement` valide `regCommandeId`, `regMontant`, puis
    // `regTresorerie` — dans CET ordre. Quand deux champs sont faux ensemble,
    // le refus rendu en premier est celui du montant : valider la trésorerie
    // avant lui rendrait le mauvais refus sur une saisie à deux erreurs.
    test('montant ET trésorerie faux : le refus est celui du MONTANT, pas '
        'celui de la trésorerie', () async {
      await expectLater(
        regler('abc', tresorerie: 'cheque'),
        throwsA(
          isA<RefusReglement>()
              .having((e) => e.champ, 'champ', ChampReglement.montant)
              .having(
                (e) => e.message,
                'message',
                MessagesEncaissement.nombre(ChampReglement.montant.attribut),
              ),
        ),
      );
      expect(await compterReglements(db), 0);
    });

    test(
      'trésorerie fausse seule : le refus est celui de la trésorerie '
      '(le test précédent n’est donc pas vert parce que tout est refusé)',
      () async {
        await expectLater(
          regler('1000', tresorerie: 'cheque'),
          throwsA(
            isA<RefusReglement>().having(
              (e) => e.champ,
              'champ',
              ChampReglement.tresorerie,
            ),
          ),
        );
      },
    );

    test(
      'commande ET montant faux : la commande passe avant le montant',
      () async {
        await expectLater(
          dao.regler(
            commandeId: null,
            montantSaisi: 'abc',
            tresorerieSaisie: 'cheque',
            auteurId: auteurEssai,
          ),
          throwsA(
            isA<RefusReglement>().having(
              (e) => e.champ,
              'champ',
              ChampReglement.commande,
            ),
          ),
        );
      },
    );
  });

  group('La concurrence : le reste dû est relu DANS la transaction', () {
    test('deux règlements simultanés de 3 000 sur un reste de 4 000 : UN '
        'seul passe', () async {
      final issues = await Future.wait([
        regler('3000').then<Object>((r) => r).catchError((Object e) => e),
        regler(
          '3000',
          tresorerie: 'banque',
        ).then<Object>((r) => r).catchError((Object e) => e),
      ]);

      expect(issues.whereType<ReglementFournisseur>(), hasLength(1));
      final refus = issues.whereType<RefusReglement>().single;
      expect(refus.message, MessagesReglement.superieurAuReste('1000.00'));
      expect(await compterReglements(db), 1);
      // Une seule pièce : deux lignes.
      expect(await compterEcritures(), 2);
      expect(await dao.resteDuDe(c1), 100000);
    });

    test('deux annulations simultanées du MÊME règlement : UNE seule '
        'contre-passation (D252, D277)', () async {
      // `annuler` relit le règlement DANS la transaction. Relu hors d'elle
      // (mutation M15), les deux gestes voyaient « actif » et chacun inversait
      // la pièce : l'argent serait revenu deux fois pour un seul règlement.
      final r = await regler('1500');
      final avant = await compterEcritures();

      final issues = await Future.wait([
        dao
            .annuler(r.id, 'Doublon', auteurId: auteurEssai)
            .then<Object>((x) => x)
            .catchError((Object e) => e),
        dao
            .annuler(r.id, 'Doublon bis', auteurId: auteurEssai)
            .then<Object>((x) => x)
            .catchError((Object e) => e),
      ]);

      expect(issues.whereType<ReglementFournisseur>(), hasLength(1));
      final refus = issues.whereType<RefusReglement>().single;
      expect(refus.message, MessagesReglement.dejaAnnule);
      // Une seule pièce d'inversion : deux lignes de plus, pas quatre.
      expect(await compterEcritures(), avant + 2);
      expect((await dao.parId(r.id))!.statut, StatutReglement.annule);
      expect(await dao.resteDuDe(c1), 400000);
    });
  });

  group('L’annulation (PA-168) : un état tracé et une contre-passation', () {
    test('annule : statut, motif, auteur, date ; la pièce est contre-passée '
        'en ENTIER ; le reste dû revient', () async {
      final r = await regler('1500');
      expect(await dao.resteDuDe(c1), 250000);
      final avant = await compterEcritures();

      final annule = await dao.annuler(
        r.id,
        'Doublon de saisie',
        auteurId: auteurEssai,
      );

      expect(annule.statut, StatutReglement.annule);
      expect(annule.motifAnnulation, 'Doublon de saisie');
      expect(annule.annuleParId, auteurEssai);
      expect(annule.dateAnnulation, isNotNull);
      // Le règlement n'est jamais supprimé (RG-15) : il reste au registre.
      expect(await compterReglements(db), 1);
      // La pièce ENTIÈRE est inversée : deux lignes de plus, pas une.
      expect(await compterEcritures(), avant + 2);
      // Un annulé ne compte plus : le reste dû est redevenu le montant entier.
      expect(await dao.totalRegleCentimes(c1), 0);
      expect(await dao.resteDuDe(c1), 400000);
    });

    test(
      'les refus du service, dans son ordre : déjà annulé, motif, pièce',
      () async {
        final r = await regler('1500');

        await expectLater(
          dao.annuler(r.id, '   ', auteurId: auteurEssai),
          throwsA(
            isA<RefusReglement>().having(
              (e) => e.message,
              'message',
              MessagesReglement.motifRequis,
            ),
          ),
        );
        expect((await dao.parId(r.id))!.statut, StatutReglement.actif);

        await dao.annuler(r.id, 'Erreur', auteurId: auteurEssai);
        // Annulé ET motif vide : « déjà annulé » passe AVANT « motif requis ».
        await expectLater(
          dao.annuler(r.id, '', auteurId: auteurEssai),
          throwsA(
            isA<RefusReglement>().having(
              (e) => e.message,
              'message',
              MessagesReglement.dejaAnnule,
            ),
          ),
        );
      },
    );

    test('une pièce INTROUVABLE refuse l’annulation : rien n’est contre-passé '
        'à moitié', () async {
      final r = await regler('1500');
      // La pièce se retrouve par son libellé (PA-52), qui porte la raison sociale
      // du fournisseur : renommer le fournisseur après coup la rend introuvable
      // (même mécanisme que le numéro d'une facture renommée à l'encaissement).
      await db.customStatement(
        "UPDATE fournisseurs_local SET raison_sociale = 'Autre nom'",
      );
      final avant = await compterEcritures();

      await expectLater(
        dao.annuler(r.id, 'Erreur', auteurId: auteurEssai),
        throwsA(
          isA<RefusReglement>().having(
            (e) => e.message,
            'message',
            startsWith('La pièce comptable de ce règlement est introuvable'),
          ),
        ),
      );
      expect((await dao.parId(r.id))!.statut, StatutReglement.actif);
      expect(await compterEcritures(), avant);
    });

    test('un règlement inconnu est refusé', () async {
      await expectLater(
        dao.annuler('fantome', 'Erreur', auteurId: auteurEssai),
        throwsA(
          isA<RefusReglement>().having(
            (e) => e.message,
            'message',
            MessagesReglement.reglementIntrouvable,
          ),
        ),
      );
    });
  });

  group('Le reste dû et la commande', () {
    test('« Réglé » somme les règlements ACTIFS, par commande', () async {
      final c2 = await semerCommande(
        db,
        articleId: 'a-2',
        quantite: '1',
        prix: '700',
        date: '2026-10-02',
      );
      await regler('1000');
      final r2 = await regler('500', commande: c2);
      await regler('250');
      await dao.annuler(r2.id, 'Erreur', auteurId: auteurEssai);

      expect(await dao.totalRegleCentimes(c1), 125000);
      expect(await dao.totalRegleCentimes(c2), 0);
      expect(await dao.resteDuDe(c1), 275000);
      expect(await dao.resteDuDe(c2), 70000);

      final api = apiAchatsSur(db);
      final detail = recu(await api.commande(c1)).commande;
      expect(detail.montantRegle, '1250.00');
      expect(detail.resteDu, '2750.00');
      // Le règlement ANNULÉ de c2 ne compte plus : l'écran, lui, relit la même
      // somme (la liste et le détail ont chacun leur lecture).
      final annulee = recu(await api.commande(c2)).commande;
      expect(annulee.montantRegle, '0.00');
      expect(annulee.resteDu, '700.00');
      final liste = recu(await api.commandes()).elements;
      expect(liste.firstWhere((c) => c.id == c2).montantRegle, '0.00');
      expect(liste.firstWhere((c) => c.id == c1).montantRegle, '1250.00');
    });

    test('le serveur n’exige AUCUN statut : un brouillon, une réceptionnée et '
        'une clôturée se règlent', () async {
      for (final statut in ['brouillon', 'receptionnee', 'cloturee']) {
        final c = await semerCommande(
          db,
          articleId: 'a-$statut',
          quantite: '1',
          prix: '100',
          statut: statut,
        );
        final r = await regler('100', commande: c);
        expect(r.montantCentimes, 10000, reason: statut);
      }
    });

    test('un règlement tronque à DEUX décimales, comme bcmath, et la pièce '
        'porte le MÊME montant', () async {
      final r = await regler('100.999');
      expect(r.montantCentimes, 10099);

      final lignes = await ComptabiliteDao(
        db,
      ).lignesParLibelle('Règlement fournisseur Grand Marche SARL — ${r.id}');
      expect(lignes.map((l) => l.debitCentimes + l.creditCentimes), [
        10099,
        10099,
      ]);
    });

    test('les contrôles de la base tiennent aussi sans le DAO', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO reglements_fournisseur_local (id, commande_id, '
          'montant_centimes, tresorerie, date_reglement, '
          "utilisateur_creation_id) VALUES ('x', ?, 0, 'caisse', "
          "'2026-10-13', ?)",
          [c1, auteurEssai],
        ),
        throwsA(anything),
      );
      expect(await compterReglements(db), 0);
    });
  });
}
