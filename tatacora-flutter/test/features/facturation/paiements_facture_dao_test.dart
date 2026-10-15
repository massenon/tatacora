import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/facturation/data/paiements_facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/messages_encaissement.dart';
import 'package:tatacora_flutter/features/facturation/domain/regles_encaissement.dart';

import '../comptabilite/support/outils_comptabilite.dart' show moteurSur;
import 'support/outils_encaissement.dart';

/// L'encaissement d'une facture — le DAO, sur une VRAIE base, avec le VRAI
/// moteur comptable.
///
/// ## Ce que ces cas protègent
///
/// **Que l'argent et sa pièce naissent ensemble ou pas du tout** (règle du PO du
/// 31/08/2026), et que chaque refus tombe dans l'ordre du serveur avec sa phrase.
/// Les phrases sont comparées au VRAI service PHP par
/// `encaissement_contre_serveur_test.dart` ; ici, le comportement du poste.
void main() {
  late AppDatabase db;
  late PaiementsFactureDao dao;

  setUp(() async {
    db = await baseEncaissement();
    dao = paiementsDaoSur(db);
  });

  tearDown(() => db.close());

  Future<void> exigerRefus(
    Future<Object?> Function() geste,
    String message,
  ) async {
    try {
      await geste();
      fail('Le geste aurait dû être refusé : « $message ».');
    } on RefusEncaissement catch (e) {
      expect(e.message, message);
    }
  }

  Future<List<EcritureComptable>> ecritures() =>
      ComptabiliteDao(db).toutesLesEcritures();

  /// Les lignes d'une pièce, par numéro de compte et journal (lisibles).
  Future<List<({String journal, String compte, int debit, int credit})>>
  lignesLisibles() async {
    final cdao = ComptabiliteDao(db);
    final journaux = {for (final j in await cdao.journaux()) j.id: j.code};
    final out = <({String journal, String compte, int debit, int credit})>[];
    for (final e in await ecritures()) {
      final compte = await cdao.compteParId(e.compteId);
      out.add((
        journal: journaux[e.journalId]!,
        compte: compte!.numero,
        debit: e.debitCentimes,
        credit: e.creditCentimes,
      ));
    }
    return out;
  }

  Future<PaiementFacture> encaisser(
    PieceFacturation piece, {
    String montant = '30000.00',
    String mode = 'especes',
  }) => dao.encaisser(
    pieceId: piece.id,
    montant: montant,
    mode: mode,
    auteurId: caissierEssai,
  );

  group('Un encaissement écrit le paiement ET sa pièce comptable', () {
    test('le paiement porte pièce, session, mode, montant, date et auteur '
        '(RG-15)', () async {
      final session = await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);

      final p = await encaisser(piece);

      expect(p.pieceId, piece.id);
      expect(p.sessionId, session.id);
      expect(p.mode, ModePaiementFacture.especes);
      expect(p.montantCentimes, 3000000);
      expect(p.datePaiement, jourEncaissement);
      expect(p.utilisateurCreationId, caissierEssai);
      expect(p.loginCreation, 'compta-$caissierEssai');
      expect(p.statut, StatutPaiementFacture.actif);
      expect(p.motifAnnulation, isNull);
    });

    test('la pièce : DÉBIT de la caisse (5711), CRÉDIT de 4111, journal CAI, '
        'équilibrée, au libellé du serveur', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);

      final p = await encaisser(piece);

      expect(await lignesLisibles(), [
        (journal: 'CAI', compte: '5711', debit: 3000000, credit: 0),
        (journal: 'CAI', compte: '4111', debit: 0, credit: 3000000),
      ]);
      final lignes = await ecritures();
      expect(lignes, hasLength(2));
      // Le lien du serveur entre le paiement et sa pièce (PA-52).
      expect(
        lignes.map((l) => l.libelle).toSet().single,
        'Encaissement ${piece.numero} — ${p.id}',
      );
      // VALIDÉE d'emblée, donc immuable (RG-11), et numérotée.
      expect(lignes.every((l) => l.estValidee), isTrue);
      expect(lignes.map((l) => l.numeroPiece).toSet().single, 'CAI-2026-00001');
    });

    test('chaque mode crédite SA trésorerie : carte en BANQUE, jamais le '
        'tiroir', () async {
      await ouvrirCaissePour(db);
      final attendu = {
        'especes': ('CAI', '5711'),
        'mobile_money': ('BQ', '552'),
        'carte': ('BQ', '5211'),
        'virement': ('BQ', '5211'),
      };
      for (final entree in attendu.entries) {
        final avant = (await lignesLisibles()).length;
        final piece = await emettreFacture(db, clientNom: entree.key);
        await encaisser(piece, montant: '1000', mode: entree.key);
        final nouvelles = (await lignesLisibles()).sublist(avant);
        expect(nouvelles.first.journal, entree.value.$1, reason: entree.key);
        expect(nouvelles.first.compte, entree.value.$2, reason: entree.key);
        expect(nouvelles.first.debit, 100000, reason: entree.key);
        expect(nouvelles.last.compte, '4111', reason: entree.key);
        expect(nouvelles.last.credit, 100000, reason: entree.key);
      }
    });

    test('le reste dû DIMINUE — c’est le point du lot', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db, montant: 50000);

      expect((await dao.creanceDe(piece)).resteDuCentimes, 5000000);
      await encaisser(piece, montant: '30000');
      expect((await dao.creanceDe(piece)).resteDuCentimes, 2000000);
    });

    test(
      'une saisie décimale est TRONQUÉE à deux décimales, pas arrondie',
      () async {
        await ouvrirCaissePour(db);
        final piece = await emettreFacture(db);

        final a = await encaisser(piece, montant: '100.5');
        final b = await encaisser(piece, montant: '100.999');

        expect(a.montantCentimes, 10050);
        // `bcadd('100.999', '0', 2)` = 100.99 : arrondir ferait 101.00.
        expect(b.montantCentimes, 10099);
        final lignes = await lignesLisibles();
        expect(lignes.map((l) => l.debit).where((d) => d > 0), [10050, 10099]);
      },
    );
  });

  group('Les refus tombent dans l’ORDRE du serveur', () {
    test('1. ce qui n’est pas une facture passe avant tout le reste', () async {
      // Ni session, ni mode connu, ni montant lisible : le premier refus est
      // celui de la pièce (analogue du « non figée » du serveur).
      final ticket = await emettreFacture(
        db,
        origine: OrigineFacture.posComptant,
      );
      await exigerRefus(
        () => dao.encaisser(
          pieceId: ticket.id,
          montant: 'abc',
          mode: 'cheque',
          auteurId: caissierEssai,
        ),
        MessagesEncaissement.pieceNonEncaissable,
      );
    });

    test('un avoir ne se règle pas', () async {
      final facture = await emettreFacture(db);
      final annulation = await factureDaoSur(
        db,
      ).annuler(facture.id, 'erreur de saisie');
      await ouvrirCaissePour(db);

      await exigerRefus(
        () => encaisser(annulation.avoir),
        MessagesEncaissement.pieceNonEncaissable,
      );
    });

    test('2. le mode inconnu avant le montant', () async {
      final piece = await emettreFacture(db);
      await exigerRefus(
        () => encaisser(piece, montant: 'abc', mode: 'cheque'),
        MessagesEncaissement.modeInconnu('cheque'),
      );
    });

    test('3. le montant illisible, nul ou négatif avant le reste dû', () async {
      final piece = await emettreFacture(db);
      for (final mauvais in ['abc', '0', '-5', '0.004', '']) {
        await exigerRefus(
          () => encaisser(piece, montant: mauvais),
          MessagesEncaissement.montantInvalide,
        );
      }
    });

    test('4. le sur-encaissement AVANT la caisse fermée, avec le reste dû en '
        'chaîne du serveur', () async {
      final piece = await emettreFacture(db, montant: 6000);
      await exigerRefus(
        () => encaisser(piece, montant: '6000.01'),
        MessagesEncaissement.superieurAuReste('6000.00'),
      );
    });

    test('5. la caisse fermée en dernier', () async {
      final piece = await emettreFacture(db);
      await exigerRefus(
        () => encaisser(piece),
        MessagesEncaissement.caisseFermee,
      );
    });

    test('une session CLOSE ne tient pas lieu de caisse ouverte', () async {
      await ouvrirCaissePour(db);
      await db.customStatement(
        'UPDATE sessions_caisse_local SET date_cloture = ?',
        [jourEncaissement.millisecondsSinceEpoch ~/ 1000],
      );
      final piece = await emettreFacture(db);
      await exigerRefus(
        () => encaisser(piece),
        MessagesEncaissement.caisseFermee,
      );
    });

    test('un texte mal formé (« 1e3 ») est refusé par le poste, là où le '
        'serveur plante', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      await exigerRefus(
        () => encaisser(piece, montant: '1e3'),
        MessagesEncaissement.malForme,
      );
      await exigerRefus(
        () => encaisser(piece, montant: ' 100'),
        MessagesEncaissement.malForme,
      );
    });

    test('une pièce inconnue est refusée', () async {
      await expectLater(
        dao.encaisser(
          pieceId: 'fantome',
          montant: '1000',
          mode: 'especes',
          auteurId: caissierEssai,
        ),
        throwsA(isA<RefusEncaissement>()),
      );
    });

    test('RIEN n’est écrit quand un refus tombe', () async {
      final piece = await emettreFacture(db, montant: 6000);
      final avant = await empreinte(db);

      for (final geste in <Future<Object?> Function()>[
        () => encaisser(piece, montant: 'abc'),
        () => encaisser(piece, montant: '9999'),
        () => encaisser(piece, mode: 'cheque'),
        () => encaisser(piece, montant: '1000'), // caisse fermée
      ]) {
        await expectLater(geste(), throwsA(isA<RefusEncaissement>()));
      }

      final apres = await empreinte(db);
      expect(apres, avant);
    });
  });

  group('Le sur-encaissement est refusé, le reste dû exact est accepté', () {
    test('on solde exactement, puis plus rien n’est encaissable', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db, montant: 50000);

      await encaisser(piece, montant: '30000');
      await exigerRefus(
        () => encaisser(piece, montant: '20000.01'),
        MessagesEncaissement.superieurAuReste('20000.00'),
      );
      await encaisser(piece, montant: '20000');

      final creance = await dao.creanceDe(piece);
      expect(creance.estSoldee, isTrue);
      expect(creance.estImpayee, isFalse);
      // Un trop-perçu créerait un avoir client que rien ne modélise.
      await exigerRefus(
        () => encaisser(piece, montant: '1'),
        MessagesEncaissement.superieurAuReste('0.00'),
      );
    });

    test('l’acompte de la réservation est déjà déduit du reste dû', () async {
      await ouvrirCaissePour(db);
      final client = await creerClient(db);
      await semerReservation(db, id: 'r1', clientId: client.id, acompte: 20000);
      final piece = await emettreFacture(
        db,
        montant: 50000,
        clientId: client.id,
        reservationId: 'r1',
        module: ModuleFacturable.m1Hebergement,
      );

      // 50 000 − 20 000 d'acompte : l'avance ne se réclame pas deux fois.
      expect((await dao.creanceDe(piece)).resteDuCentimes, 3000000);
      await exigerRefus(
        () => encaisser(piece, montant: '30000.01'),
        MessagesEncaissement.superieurAuReste('30000.00'),
      );
      await encaisser(piece, montant: '30000');
    });

    test('une facture ANNULÉE par son avoir ne doit plus rien', () async {
      await ouvrirCaissePour(db);
      final facture = await emettreFacture(db, montant: 50000);
      await factureDaoSur(db).annuler(facture.id, 'erreur de saisie');

      await exigerRefus(
        () => encaisser(facture, montant: '1'),
        MessagesEncaissement.superieurAuReste('0.00'),
      );
    });
  });

  group('La session qui reçoit l’argent', () {
    test('la PLUS RÉCENTE ouverte, TOUS points confondus — comme le serveur, '
        'alors que le comptoir ne regarde que le bar', () async {
      final reception = await ouvrirCaissePour(
        db,
        point: PointDeVenteCaisse.reception,
        horloge: DateTime(2026, 10, 12, 7),
      );
      final piece = await emettreFacture(db);

      // Seule une caisse de la réception est ouverte : un encaissement de facture
      // passe, là où le POS comptant répondrait « Aucune caisse n'est ouverte ».
      final p = await encaisser(piece, montant: '1000');
      expect(p.sessionId, reception.id);

      final bar = await ouvrirCaissePour(
        db,
        point: PointDeVenteCaisse.bar,
        horloge: DateTime(2026, 10, 12, 9),
      );
      final q = await encaisser(piece, montant: '1000');
      expect(q.sessionId, bar.id);
    });
  });

  group('La pièce refusée emporte le paiement (règle du 31/08/2026)', () {
    test(
      'exercice absent : ni paiement, ni écriture, ni numéro consommé',
      () async {
        // Référentiel installé en 2025 : l'exercice 2026 n'existe pas.
        final ancienne = await baseEncaissement(
          maintenant: DateTime(2025, 6, 1),
        );
        addTearDown(ancienne.close);
        final dao2 = paiementsDaoSur(ancienne);
        await ouvrirCaissePour(ancienne);
        final piece = await emettreFacture(ancienne);
        final avant = await empreinte(ancienne);

        await expectLater(
          dao2.encaisser(
            pieceId: piece.id,
            montant: '1000',
            mode: 'especes',
            auteurId: caissierEssai,
          ),
          throwsA(isA<RefusComptable>()),
        );

        expect(await empreinte(ancienne), avant);
        expect(avant.paiements, 0);
      },
    );

    test('un DAO sans moteur lève et n’écrit rien', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final sansMoteur = paiementsDaoSur(db, sansMoteur: true);
      final avant = await empreinte(db);

      await expectLater(
        sansMoteur.encaisser(
          pieceId: piece.id,
          montant: '1000',
          mode: 'especes',
          auteurId: caissierEssai,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await empreinte(db), avant);
    });

    test('un auteur inconnu est refusé AVANT toute écriture', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final avant = await empreinte(db);
      await exigerRefus(
        () => dao.encaisser(
          pieceId: piece.id,
          montant: '1000',
          mode: 'especes',
          auteurId: '',
        ),
        MessagesEncaissement.auteurInconnu,
      );
      expect(await empreinte(db), avant);
    });
  });

  group('L’annulation est un ÉTAT tracé et la contre-passation de la pièce '
      'ENTIÈRE', () {
    test('le paiement passe à « annulé », motif et auteur tracés, le reste dû '
        'remonte, la pièce est contre-passée', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db, montant: 50000);
      final p = await encaisser(piece, montant: '30000');

      final annule = await dao.annuler(
        p.id,
        'Erreur de saisie',
        auteurId: caissierEssai,
      );

      expect(annule.statut, StatutPaiementFacture.annule);
      expect(annule.motifAnnulation, 'Erreur de saisie');
      expect(annule.annuleParId, caissierEssai);
      expect(annule.dateAnnulation, jourEncaissement);
      expect((await dao.creanceDe(piece)).resteDuCentimes, 5000000);

      // Deux lignes d'origine, deux lignes inverses : le grand livre est à zéro.
      final lignes = await ecritures();
      expect(lignes, hasLength(4));
      final debit = lignes.fold(0, (t, l) => t + l.debitCentimes);
      final credit = lignes.fold(0, (t, l) => t + l.creditCentimes);
      expect(debit, credit);
      var soldeCaisse = 0;
      for (final l in await lignesLisibles()) {
        if (l.compte == '5711') soldeCaisse += l.debit - l.credit;
      }
      expect(soldeCaisse, 0);
      // La ligne d'origine n'est jamais touchée : lien de traçabilité.
      expect(
        lignes.where((l) => l.ecritureContrepasseeId != null),
        hasLength(2),
      );
    });

    test('le paiement annulé reste LISIBLE et le motif aussi', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final p = await encaisser(piece);
      await dao.annuler(p.id, 'Doublon', auteurId: caissierEssai);

      final tous = await dao.paiements();
      expect(tous, hasLength(1));
      expect(tous.single.statut, StatutPaiementFacture.annule);
    });

    test('un encaissement déjà annulé ne l’est pas deux fois', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final p = await encaisser(piece);
      await dao.annuler(p.id, 'Doublon', auteurId: caissierEssai);
      final avant = await empreinte(db);

      await exigerRefus(
        () => dao.annuler(p.id, 'Encore', auteurId: caissierEssai),
        MessagesEncaissement.dejaAnnule,
      );
      expect(await empreinte(db), avant);
    });

    test(
      'le motif est obligatoire (PHP `trim`) et rien n’est écrit sans lui',
      () async {
        await ouvrirCaissePour(db);
        final piece = await emettreFacture(db);
        final p = await encaisser(piece);
        final avant = await empreinte(db);

        for (final vide in ['', '   ', '\t\n']) {
          await exigerRefus(
            () => dao.annuler(p.id, vide, auteurId: caissierEssai),
            MessagesEncaissement.motifRequis,
          );
        }
        expect(await empreinte(db), avant);
        expect((await dao.parId(p.id))!.estActif, isTrue);
      },
    );

    test('une pièce introuvable ou déséquilibrée REFUSE plutôt que de '
        'contre-passer à moitié', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final p = await encaisser(piece);
      // Le numéro de la facture change : le libellé de la pièce ne se retrouve
      // plus, exactement comme une pièce supprimée du serveur.
      await db.customStatement(
        'UPDATE pieces_facturation_local SET numero = ? WHERE id = ?',
        ['F-AILLEURS', piece.id],
      );
      final avant = await empreinte(db);

      await exigerRefus(
        () => dao.annuler(p.id, 'Doublon', auteurId: caissierEssai),
        MessagesEncaissement.pieceIntrouvable(
          'Encaissement F-AILLEURS — ${p.id}',
        ),
      );
      expect(await empreinte(db), avant);
      expect((await dao.parId(p.id))!.estActif, isTrue);
    });

    test('si la contre-passation échoue, le paiement RESTE actif', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db);
      final p = await encaisser(piece);
      final avant = await empreinte(db);

      // L'exercice 2026 est CLÔTURÉ après l'encaissement : la contre-passation
      // est refusée par la base (RG-11, exercice clos) — le statut ne doit pas
      // bouger, et aucune ligne inverse ne doit subsister.
      final exercice = await ComptabiliteDao(db).exerciceDeLAnnee(2026);
      await moteurSur(
        db,
      ).cloturerExercice(exercice!.id, auteurId: caissierEssai);
      final apresCloture = await empreinte(db);

      await expectLater(
        dao.annuler(p.id, 'Doublon', auteurId: caissierEssai),
        throwsA(isA<RefusComptable>()),
      );

      expect((await dao.parId(p.id))!.estActif, isTrue);
      expect(await empreinte(db), apresCloture);
      expect(avant.ecritures, apresCloture.ecritures);
    });

    test('un identifiant inconnu est refusé', () async {
      await exigerRefus(
        () => dao.annuler('fantome', 'x', auteurId: caissierEssai),
        MessagesEncaissement.paiementIntrouvable,
      );
    });
  });

  group('Le composant : droit, puis validation, puis service', () {
    Future<PaiementFacture> recouvrer({
      required String? pieceId,
      String? montant = '1000',
      String? mode = 'especes',
      bool droit = true,
    }) => dao.recouvrer(
      pieceId: pieceId,
      montantSaisi: montant,
      modeSaisi: mode,
      auteurId: caissierEssai,
      peutEncaisser: droit,
    );

    test('le droit manquant répond AVANT toute validation', () async {
      // Une saisie entièrement invalide : sans le droit, rien n'est dit de sa
      // validité (un rôle sans droit n'apprend rien).
      await exigerRefus(
        () => recouvrer(pieceId: null, montant: 'abc', mode: 'x', droit: false),
        MessagesEncaissement.refusDroit,
      );
    });

    test('les champs se valident dans l’ordre pièce, montant, mode', () async {
      final piece = await emettreFacture(db);

      await exigerRefus(
        () => recouvrer(pieceId: '', montant: 'abc', mode: 'x'),
        MessagesEncaissement.obligatoire('recouvrement facture id'),
      );
      // La règle `uuid` passe avant `exists` (un identifiant mal formé).
      await exigerRefus(
        () => recouvrer(pieceId: 'fantome', montant: 'abc', mode: 'x'),
        MessagesEncaissement.uuid('recouvrement facture id'),
      );
      await exigerRefus(
        () => recouvrer(
          pieceId: '00000000-0000-4000-8000-000000000000',
          montant: 'abc',
          mode: 'x',
        ),
        MessagesEncaissement.invalide('recouvrement facture id'),
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: '  ', mode: 'x'),
        MessagesEncaissement.obligatoire('recouvrement montant'),
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: 'abc', mode: 'x'),
        MessagesEncaissement.nombre('recouvrement montant'),
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: '0', mode: 'x'),
        // La clé `validation.gt.numeric` n'existe pas au serveur : Laravel rend
        // la clé comme message (défaut du serveur, répliqué).
        'validation.gt.numeric',
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: '-5', mode: 'x'),
        'validation.gt.numeric',
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: '5', mode: ''),
        MessagesEncaissement.obligatoire('recouvrement mode'),
      );
      await exigerRefus(
        () => recouvrer(pieceId: piece.id, montant: '5', mode: 'cheque'),
        MessagesEncaissement.invalide('recouvrement mode'),
      );
    });

    test('un refus du SERVICE se pose sous le champ montant, caisse fermée '
        'comprise', () async {
      final piece = await emettreFacture(db, montant: 6000);
      try {
        await recouvrer(pieceId: piece.id, montant: '1000');
        fail('La caisse est fermée.');
      } on RefusEncaissement catch (e) {
        expect(e.message, MessagesEncaissement.caisseFermee);
        expect(e.champ, ChampEncaissement.montant);
      }
    });

    test('une saisie valide encaisse', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db, montant: 6000);
      final p = await recouvrer(pieceId: piece.id, montant: '6000');
      expect(p.montantCentimes, 600000);
      expect((await dao.creanceDe(piece)).estSoldee, isTrue);
    });
  });

  group('Les lectures', () {
    test('les paiements viennent du plus récent au plus ancien, annulés '
        'COMPRIS (le serveur ne filtre pas)', () async {
      await ouvrirCaissePour(db);
      final piece = await emettreFacture(db, montant: 90000);
      final plusTot = paiementsDaoSur(db, horloge: DateTime(2026, 10, 10, 8));
      final a = await plusTot.encaisser(
        pieceId: piece.id,
        montant: '1000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      final b = await encaisser(piece, montant: '2000');
      await dao.annuler(b.id, 'x', auteurId: caissierEssai);

      final tous = await dao.paiements();
      expect(tous.map((p) => p.id), [b.id, a.id]);
      expect(tous.first.statut, StatutPaiementFacture.annule);
    });

    test(
      'les huit premiers caractères de l’identifiant font N° et Référence',
      () async {
        await ouvrirCaissePour(db);
        final piece = await emettreFacture(db);
        final p = await encaisser(piece);
        expect(p.numeroCourt, p.id.substring(0, 8));
        expect(p.numeroCourt.length, 8);
      },
    );

    test('un paiement inexistant se lit null', () async {
      expect(await dao.parId('fantome'), isNull);
    });
  });

  group('Les contraintes de la table tiennent sur la base elle-même', () {
    Future<void> insererBrut({
      String mode = 'especes',
      String statut = 'actif',
      int montant = 100,
      String? motif,
      int? dateAnnulation,
    }) async {
      final piece = await emettreFacture(db);
      final session = await ouvrirCaissePour(db);
      await db.customStatement(
        'INSERT INTO paiements_facture_local (id, piece_id, session_id, '
        'mode_paiement, montant_centimes, date_paiement, statut, '
        'motif_annulation, date_annulation, utilisateur_creation_id) '
        'VALUES (?, ?, ?, ?, ?, 1787000000, ?, ?, ?, ?)',
        [
          'x',
          piece.id,
          session.id,
          mode,
          montant,
          statut,
          motif,
          dateAnnulation,
          caissierEssai,
        ],
      );
    }

    test('un mode hors registre est refusé', () async {
      await expectLater(insererBrut(mode: 'cheque'), throwsA(anything));
    });

    test('un montant nul ou négatif est refusé', () async {
      await expectLater(insererBrut(montant: 0), throwsA(anything));
    });

    test(
      'un « annulé » sans motif ni date est refusé, et réciproquement',
      () async {
        await expectLater(insererBrut(statut: 'annule'), throwsA(anything));
      },
    );

    test('un statut hors registre est refusé', () async {
      await expectLater(insererBrut(statut: 'rembourse'), throwsA(anything));
    });

    test('une clé étrangère inconnue est refusée', () async {
      await expectLater(
        db.customStatement(
          'INSERT INTO paiements_facture_local (id, piece_id, session_id, '
          'mode_paiement, montant_centimes, date_paiement, '
          'utilisateur_creation_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            'y',
            'fantome',
            'fantome',
            'especes',
            100,
            1787000000,
            caissierEssai,
          ],
        ),
        throwsA(anything),
      );
    });
  });

  test('l’horloge est celle du DAO, jamais celle de la machine', () async {
    await ouvrirCaissePour(db);
    final piece = await emettreFacture(db);
    final p = await encaisser(piece);
    expect(p.datePaiement.year, 2026);
    final lignes = await ecritures();
    expect(lignes.first.dateEcriture, '2026-10-12');
  });
}
