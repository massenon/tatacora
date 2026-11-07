import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/service_facturation_en_ligne.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/domain/statut_normalisation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import '../synchronisation/support/faux_transport.dart';
import 'support/outils_encaissement.dart';

/// Les deux gestes EN LIGNE du poste (décisions du PO du 07/11/2026) : l'avoir d'une facture
/// normalisée et la normalisation e-MECeF demandée au serveur — contre un FAUX serveur, une
/// vraie base et un vrai `poste.json`.
///
/// Mutation qui mord (a) : si l'avoir hors ligne ÉCRIVAIT localement (une pièce-avoir, la
/// facture « annulée » ou une opération en file), les cas « RIEN n'est écrit » rougissent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const phraseAvoir =
      'Un avoir sur une facture normalisée se fait en ligne : reconnectez le '
      'poste au serveur.';
  const phraseNormalisation =
      'La normalisation e-MECeF se fait en ligne : reconnectez le poste au '
      'serveur.';

  late AppDatabase db;
  late Directory dossier;
  late FauxTransport transport;
  late EcrivainConfigurationPoste ecrivain;
  late int descentes;
  late int envois;

  String cheminPoste() => '${dossier.path}/poste.json';

  setUp(() async {
    db = await baseEncaissement();
    dossier = await Directory.systemTemp.createTemp('tatacora-en-ligne-');
    ecrivain = EcrivainConfigurationPoste(chemin: () async => cheminPoste());
    await ecrivain.enregistrerAppairage(
      AppairagePoste(
        posteId: 'COMPTOIR-ESSAI',
        jetonApi: '7|jeton-essai',
        serveur: 'https://serveur.essai/api/v1',
        appaireLe: DateTime(2026, 11, 7),
        compte: 'gerant',
      ),
    );
    descentes = 0;
    envois = 0;
    transport = FauxTransport(
      (_) => const ReponseHttp(statut: 500, corps: null),
    );
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  ServiceFacturationEnLigne service({
    String? url = 'https://serveur.essai/api/v1',
  }) => ServiceFacturationEnLigne(
    transport: transport,
    url: url,
    base: db,
    lecteur: LecteurConfigurationPoste(chemin: () async => cheminPoste()),
    envoyerLaFile: () async => envois++,
    descendre: () async => descentes++,
  );

  FauxTransport faux() => transport;

  /// Une facture NORMALISÉE (le résultat du boîtier, posé en base).
  Future<String> factureNormalisee() async {
    final f = await emettreFacture(db, montant: 30000);
    await db.customStatement(
      'UPDATE pieces_facturation_local SET normalisation_statut = '
      "'normalisee', normalisation_mode = 'boitier', numero_mecef = "
      "'ED04000623-41', qr_code_fiscal = 'F;ED04000623;ABC;3201910768821;"
      "20261107100000', code_mecef = 'ABC' WHERE id = '${f.id}'",
    );
    return f.id;
  }

  Future<int> nombrePieces() async => (await factureDaoSur(db).pieces()).length;

  Future<int> nombreOperations() async => (await OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.factures)).length;

  Future<void> eteindreLaSynchronisation() =>
      ecrivain.enregistrerSynchronisationActivee(
        false,
        par: 'gerant',
        le: DateTime(2026, 11, 7),
      );

  ReponseHttp avoirCree({String statut = 'normalisee', bool rejeu = false}) =>
      ReponseHttp(
        statut: 200,
        corps: {
          'data': {
            'facture_id': 'x',
            'avoir_id': 'avoir-serveur-1',
            'numero_avoir': 'AV-2026-00007',
            'montant': '30000.00',
            'entier': true,
            'normalisation_statut': statut,
            'normalisation_mode': 'emecef',
            'rejeu': rejeu,
          },
        },
      );

  /* ================================================================== */
  group('l’avoir d’une facture normalisée : EN LIGNE seulement', () {
    test('hors ligne (serveur injoignable) : refusé avec la phrase, et RIEN '
        'n’est écrit localement', () async {
      final id = await factureNormalisee();
      transport = FauxTransport((_) => const ServeurInjoignable('delai'));
      final piecesAvant = await nombrePieces();
      final opsAvant = await nombreOperations();

      final r = await service().avoir(id, motif: 'Erreur');

      expect(r, isA<RefusEnLigne>());
      expect((r as RefusEnLigne).phrase, phraseAvoir);
      expect(await nombrePieces(), piecesAvant, reason: 'aucune pièce-avoir');
      expect(await nombreOperations(), opsAvant, reason: 'rien en file');
      final apres = (await FactureDao(db).parId(id))!;
      expect(apres.estAnnulee, isFalse);
      expect(apres.estNormalisee, isTrue);
    });

    test('interrupteur « Synchronisation activée » ÉTEINT : aucune requête, la '
        'phrase, rien d’écrit', () async {
      final id = await factureNormalisee();
      await eteindreLaSynchronisation();
      final piecesAvant = await nombrePieces();

      final r = await service().avoir(id, motif: 'Erreur');

      expect((r as RefusEnLigne).phrase, phraseAvoir);
      expect(
        faux().requetes,
        isEmpty,
        reason: 'aucun réseau, interrupteur éteint',
      );
      expect(await nombrePieces(), piecesAvant);
    });

    test(
      'poste non appairé ou démonstration : aucune requête, la phrase',
      () async {
        final id = await factureNormalisee();
        await ecrivain.retirerAppairage();
        var r = await service().avoir(id, motif: 'Erreur');
        expect((r as RefusEnLigne).phrase, phraseAvoir);

        r = await service(url: null).avoir(id, motif: 'Erreur');
        expect((r as RefusEnLigne).phrase, phraseAvoir);
        expect(faux().requetes, isEmpty);
      },
    );

    test('en ligne : le serveur crée l’avoir (identifiant serveur), le poste '
        'n’écrit RIEN lui-même et déclenche la descente', () async {
      final id = await factureNormalisee();
      transport = FauxTransport((_) => avoirCree());
      final piecesAvant = await nombrePieces();
      final opsAvant = await nombreOperations();

      final r = await service().avoir(id, motif: 'Erreur de saisie');

      expect(r, isA<AvoirCree>());
      final cree = r as AvoirCree;
      expect(cree.numeroAvoir, 'AV-2026-00007');
      expect(cree.entier, isTrue);
      expect(cree.normalisationStatut, 'normalisee');

      // La requête : jeton d'appairage, poste, motif, PAS de montant (TTC entier), jamais
      // d'identifiant d'avoir né sur le poste.
      final req = faux().requetes.single;
      expect(req.methode, 'POST');
      expect(req.url.path, '/api/v1/sync/factures/$id/avoir');
      expect(req.jeton, '7|jeton-essai');
      expect(req.corps!['poste_id'], 'COMPTOIR-ESSAI');
      expect(req.corps!['motif'], 'Erreur de saisie');
      expect(req.corps!.containsKey('montant'), isFalse);
      expect(req.corps!.containsKey('avoir_id'), isFalse);
      expect(req.corps!['demande_id'], isA<String>());

      // RIEN d'écrit localement : l'avoir descendra.
      expect(await nombrePieces(), piecesAvant);
      expect(await nombreOperations(), opsAvant);
      expect((await FactureDao(db).parId(id))!.estAnnulee, isFalse);
      expect(descentes, 1);
    });

    test(
      'avoir partiel : le montant part en francs entiers ; un montant nul ou '
      'excessif est refusé AVANT toute requête',
      () async {
        final id = await factureNormalisee();
        transport = FauxTransport((_) => avoirCree());

        await expectLater(
          service().avoir(id, motif: 'Geste', montantFrancs: 0),
          throwsA(isA<AvoirMontantNul>()),
        );
        await expectLater(
          service().avoir(id, motif: 'Geste', montantFrancs: 30001),
          throwsA(isA<AvoirExcessif>()),
        );
        await expectLater(
          service().avoir(id, motif: '  '),
          throwsA(isA<MotifAnnulationRequis>()),
        );
        expect(faux().requetes, isEmpty);

        await service().avoir(id, motif: 'Geste', montantFrancs: 4000);
        expect(faux().requetes.single.corps!['montant'], 4000);
      },
    );

    test('la facture pas encore montée : le poste envoie sa file puis réessaie '
        'UNE fois', () async {
      final id = await factureNormalisee();
      var appels = 0;
      transport = FauxTransport((_) {
        appels++;
        return appels == 1
            ? const ReponseHttp(
                statut: 404,
                corps: {'code': 'facture_inconnue', 'message': 'inconnue'},
              )
            : avoirCree();
      });

      final r = await service().avoir(id, motif: 'Erreur');

      expect(r, isA<AvoirCree>());
      expect(envois, 1);
      expect(faux().requetes, hasLength(2));
    });

    test(
      'les refus du serveur se disent en français : droit, poste, plafond',
      () async {
        final id = await factureNormalisee();
        transport = FauxTransport(
          (_) => const ReponseHttp(
            statut: 422,
            corps: {
              'message':
                  'Le montant de l\'avoir ne peut pas dépasser celui de la facture.',
            },
          ),
        );
        final r = await service().avoir(id, motif: 'X');
        expect(
          (r as RefusEnLigne).phrase,
          'Le montant de l\'avoir ne peut pas dépasser celui de la facture.',
        );

        transport = FauxTransport(
          (_) => const ReponseHttp(statut: 403, corps: null),
        );
        final droit = await service().avoir(id, motif: 'X');
        expect((droit as RefusEnLigne).phrase, contains('pas le droit'));
        expect(await nombrePieces(), 1);
      },
    );

    test('une pièce d’avant la synchronisation n’est pas connue du serveur : '
        'refus, rien d’envoyé', () async {
      await db.customStatement(
        'INSERT INTO pieces_facturation_local (id, numero, origine, '
        'date_emission, client_nom, statut, statut_transmission) VALUES '
        "('anc', 'F-2026-00001', 'facture_directe', 0, 'ANCIEN', 'emise', "
        "'non_transmissible')",
      );
      await db.customStatement(
        'INSERT INTO lignes_piece_facturation_local (id, piece_id, '
        'module_source, libelle, prix_unitaire, quantite, ordre) VALUES '
        "('anc:0', 'anc', 'M5', 'Bière', 1000, 2, 0)",
      );
      final r = await service().avoir('anc', motif: 'Doublon');
      expect(r, isA<RefusEnLigne>());
      expect(faux().requetes, isEmpty);
    });
  });

  /* ================================================================== */
  group('la normalisation e-MECeF demandée au serveur', () {
    ReponseHttp normalisee({bool rejeu = false}) => ReponseHttp(
      statut: 200,
      corps: {
        'data': {
          'facture_id': 'x',
          'normalisation_statut': 'normalisee',
          'normalisation_mode': 'emecef',
          'normalisation_motif': null,
          'numero_mecef': 'ED04000999-12',
          'qr_code': 'F;ED04000999;ABCD-EFGH;0202011344660;20261107100000',
          'code_mecef': 'ABCD-EFGH',
          'compteur': '12',
          'date': '2026-11-07T10:00:03+01:00',
          'rejeu': rejeu,
        },
      },
    );

    Future<String> factureSimple() async =>
        (await emettreFacture(db, montant: 10000)).id;

    test('en ligne : le RÉSULTAT revient et est écrit sur la facture du poste, '
        'sans repartir au serveur', () async {
      final id = await factureSimple();
      transport = FauxTransport((_) => normalisee());
      final opsAvant = await nombreOperations();

      final r = await service().normaliserParLeServeur(id);

      expect(r, isA<NormalisationServeur>());
      final p = (r as NormalisationServeur).piece;
      expect(p.estNormalisee, isTrue);
      expect(p.numeroMecef, 'ED04000999-12');
      expect(p.codeMecef, 'ABCD-EFGH');
      expect(p.qrCodeFiscal, startsWith('F;ED04000999;'));
      expect(p.normalisationMode, VoieNormalisation.emecef);
      expect(p.normalisationCompteur, '12');
      expect(p.normaliseeLe, isNotNull);
      expect(
        await nombreOperations(),
        opsAvant,
        reason: 'le serveur le détient déjà',
      );

      final req = faux().requetes.single;
      expect(req.url.path, '/api/v1/sync/factures/$id/normalisation');
      expect(req.jeton, '7|jeton-essai');
    });

    test('hors ligne : refusé avec la phrase, rien d’écrit de faux, la facture '
        'reste « en attente »', () async {
      final id = await factureSimple();
      transport = FauxTransport((_) => const ServeurInjoignable('reseau'));

      final r = await service().normaliserParLeServeur(id);

      expect((r as RefusEnLigne).phrase, phraseNormalisation);
      final p = (await FactureDao(db).parId(id))!;
      expect(p.normalisationStatut, isNull);
      expect(p.numeroMecef, isNull);
      expect(p.qrCodeFiscal, isNull);
    });

    test('interrupteur éteint : AUCUNE requête, la phrase', () async {
      final id = await factureSimple();
      await eteindreLaSynchronisation();

      final r = await service().normaliserParLeServeur(id);

      expect((r as RefusEnLigne).phrase, phraseNormalisation);
      expect(faux().requetes, isEmpty);
    });

    test('un refus de la DGI (rendu par le serveur) se range en français, la '
        'facture reste émise et rejouable', () async {
      final id = await factureSimple();
      transport = FauxTransport(
        (_) => const ReponseHttp(
          statut: 200,
          corps: {
            'data': {
              'facture_id': 'x',
              'normalisation_statut': 'refusee',
              'normalisation_mode': 'emecef',
              'normalisation_motif':
                  'La DGI a refusé la facture : IFU du client invalide',
              'numero_mecef': null,
              'qr_code': null,
            },
          },
        ),
      );

      final r =
          await service().normaliserParLeServeur(id) as NormalisationServeur;

      expect(r.statut, StatutNormalisation.refusee);
      expect(r.piece.estNormalisee, isFalse);
      expect(r.piece.normalisationMotif, contains('IFU du client invalide'));
      expect(r.piece.numeroMecef, isNull);
    });

    test('un « normalisée » SANS numéro ni QR valides n’est PAS écrit comme '
        'tel', () async {
      final id = await factureSimple();
      transport = FauxTransport(
        (_) => const ReponseHttp(
          statut: 200,
          corps: {
            'data': {
              'normalisation_statut': 'normalisee',
              'numero_mecef': 'pas une identité',
              'qr_code': '',
            },
          },
        ),
      );

      final r =
          await service().normaliserParLeServeur(id) as NormalisationServeur;

      expect(r.piece.estNormalisee, isFalse);
      expect(r.statut, StatutNormalisation.enAttente);
    });

    test(
      'rejeu idempotent : une facture déjà normalisée n’est jamais écrasée',
      () async {
        final id = await factureSimple();
        transport = FauxTransport((_) => normalisee());
        await service().normaliserParLeServeur(id);

        transport = FauxTransport(
          (_) => const ReponseHttp(
            statut: 200,
            corps: {
              'data': {
                'normalisation_statut': 'refusee',
                'normalisation_motif': 'autre chose',
                'rejeu': true,
              },
            },
          ),
        );
        final r =
            await service().normaliserParLeServeur(id) as NormalisationServeur;

        expect(r.piece.estNormalisee, isTrue);
        expect(r.piece.numeroMecef, 'ED04000999-12');
      },
    );

    test('le mode désactivé côté serveur (422) est dit avec SA phrase', () async {
      final id = await factureSimple();
      transport = FauxTransport(
        (_) => const ReponseHttp(
          statut: 422,
          corps: {
            'message':
                'La facturation normalisée est désactivée : cette facture reste un document non normalisé.',
          },
        ),
      );
      final r = await service().normaliserParLeServeur(id);
      expect((r as RefusEnLigne).phrase, contains('désactivée'));
    });
  });
}
