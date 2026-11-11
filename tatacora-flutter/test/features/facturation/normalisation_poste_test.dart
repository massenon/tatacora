import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/lecteur_mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/data/pilote_boitier.dart';
import 'package:tatacora_flutter/features/facturation/data/service_normalisation.dart';
import 'package:tatacora_flutter/features/facturation/domain/client_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/ifu_client.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/domain/statut_normalisation.dart';
import 'package:tatacora_flutter/features/facturation/impression/ticket_facture.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import '../../support/faux_pilote_boitier.dart';
import 'support/outils_encaissement.dart';

/// La normalisation d'une pièce de CE poste par son boîtier CC300, sur une base
/// réelle et un FAUX pilote HTTP : mode, issue rangée, pièce figée, avoir,
/// protocole de la réponse perdue, file d'envoi vers le serveur.
void main() {
  HttpOverrides.global = null;

  late AppDatabase db;
  late FauxPilote faux;
  late Directory dossier;
  late String cheminPoste;

  /// Les paramètres que le serveur a descendus : mode « boîtier », IFU,
  /// opérateur, TVA 18 % en TTC.
  Future<void> configurer({
    String mode = 'boitier',
    String ifu = '3201910768821',
    bool tva = true,
    String convention = 'ttc',
    bool operateur = true,
  }) async {
    final depot = ParametresDepotLocal(db);
    await depot.inscrireDescendue('facturation_mode', mode);
    await depot.inscrireDescendue('entreprise_ifu', ifu);
    if (operateur) {
      await depot.inscrireDescendue('mecef_operateur_id', 'RECEPTION01');
      await depot.inscrireDescendue('mecef_operateur_nom', 'Réception');
    }
    await depot.inscrireDescendue('tva_active', tva ? 'true' : 'false');
    await depot.inscrireDescendue('taux_tva', '18');
    await depot.inscrireDescendue('convention_prix', convention);
  }

  setUp(() async {
    db = await baseEncaissement();
    faux = await FauxPilote.demarrer();
    faux.surBill = (_) =>
        (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
    dossier = await Directory.systemTemp.createTemp('tatacora-normalisation-');
    cheminPoste = '${dossier.path}/poste.json';
    await configurer();
  });

  tearDown(() async {
    await faux.arreter();
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  ServiceNormalisation service({
    Duration delaiEnvoi = const Duration(seconds: 5),
  }) => ServiceNormalisation(
    db,
    lecteur: LecteurModeFacturation(
      db,
      lecteur: LecteurConfigurationPoste(chemin: () async => cheminPoste),
    ),
    fabriquePilote: (_) => PiloteBoitier(
      racine: faux.racine,
      delaiEnvoi: delaiEnvoi,
      delaiInfo: const Duration(seconds: 5),
    ),
    attenteApresDelai: Duration.zero,
    factures: factureDaoSur(db),
  );

  /// Une vente au comptant de 30 000 FCFA, réglée en espèces.
  Future<PieceFacturation> venteComptant({int montant = 30000}) async {
    final dao = factureDaoSur(db);
    return dao.emettre(
      BrouillonFacture(
        origine: OrigineFacture.posComptant,
        clientNom: 'Client de passage',
        modePaiement: 'especes',
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: montant ~/ 3,
            quantite: 3,
          ),
        ],
      ),
    );
  }

  Future<PieceFacturation> relire(PieceFacturation p) async =>
      (await factureDaoSur(db).parId(p.id))!;

  Future<List<Map<String, Object?>>> chargesEnFile() async => [
    for (final o in await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.factures))
      jsonDecode(o.payload) as Map<String, Object?>,
  ];

  group('aucune requête si le mode de ce poste n’est pas « boîtier »', () {
    for (final cas in {
      'désactivé': ('desactive', null),
      'e-MECeF (le serveur certifie)': ('emecef', null),
      'surcharge locale « rien »': ('boitier', 'rien'),
      'surcharge locale « serveur »': ('boitier', 'serveur'),
    }.entries) {
      test(cas.key, () async {
        await configurer(mode: cas.value.$1);
        if (cas.value.$2 != null) {
          File(cheminPoste).writeAsStringSync(
            jsonEncode({'facturation_surcharge': cas.value.$2}),
          );
        }
        final p = await venteComptant();
        final r = await service().normaliser(p.id);

        expect(r, isA<NormalisationIgnoree>());
        expect(faux.requetes, isEmpty, reason: 'AUCUNE requête au pilote');
        expect((await relire(p)).normalisationStatut, isNull);
        expect(await chargesEnFile(), hasLength(1), reason: 'création seule');
      });
    }

    test(
      'la surcharge « boîtier » l’emporte sur un serveur désactivé',
      () async {
        await configurer(mode: 'desactive');
        File(
          cheminPoste,
        ).writeAsStringSync(jsonEncode({'facturation_surcharge': 'boitier'}));
        final p = await venteComptant();
        final r = await service().normaliser(p.id);
        expect(r, isA<NormalisationFaite>());
        expect(faux.requetes, isNotEmpty);
      },
    );
  });

  group('le succès', () {
    test('NIM-TC, QR, code, date, voie rangés ; la pièce est NORMALISÉE ; '
        'elle part au serveur', () async {
      final p = await venteComptant();
      final r = await service().normaliser(p.id);

      expect(r, isA<NormalisationFaite>());
      final n = await relire(p);
      expect(n.normalisationStatut, StatutNormalisation.normalisee);
      expect(n.estNormalisee, isTrue);
      expect(n.numeroMecef, 'ED04000623-41');
      expect(n.normalisationCompteur, '41');
      expect(n.codeMecef, 'NW34NID6ZHANFNMZ2IU7LL3H');
      expect(n.qrCodeFiscal, qrDuPilote());
      expect(n.normalisationMode, VoieNormalisation.boitier);
      expect(n.normaliseeLe, DateTime(2026, 11, 7, 10));
      expect(n.normalisationCompteurAvant, isNull);
      expect(n.normalisationMotif, isNull);

      // Le serveur reçoit le RÉSULTAT (il le range, il ne re-certifie pas).
      final charges = await chargesEnFile();
      expect(charges, hasLength(2));
      expect(charges.last, {
        'normalisation': {
          'statut': 'normalisee',
          'mode': 'boitier',
          'numero_mecef': 'ED04000623-41',
          'qr_code': qrDuPilote(),
          'code_mecef': 'NW34NID6ZHANFNMZ2IU7LL3H',
          'compteur': '41',
          'date': '2026-11-07 10:00:00',
        },
      });
      final op = (await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.factures)).last;
      expect(op.entiteId, p.id);
      expect(op.type, TypeOperationSync.modification);
    });

    test('TVA active : groupe B ; inactive : groupe A ; la taxe de séjour : '
        'F nommée TAXE DE SEJOUR', () async {
      final p = await venteComptant();
      await service().normaliser(p.id);
      var corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      expect(((corps['products'] as List).single as Map)['tax'], 'B');
      expect(corps['payments'], [
        {'mode': 'E', 'amount': 30000},
      ]);
      expect(corps['vt'], 'FV');
      expect(corps['seller_id'], 'RECEPTION01');

      await configurer(tva: false);
      final q = await venteComptant();
      await service().normaliser(q.id);
      corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      expect(((corps['products'] as List).single as Map)['tax'], 'A');

      final sejour = await factureDaoSur(db).emettre(
        BrouillonFacture(
          origine: OrigineFacture.posComptant,
          clientNom: 'Hôte',
          modePaiement: 'especes',
          lignes: [
            LigneBrouillon(
              module: ModuleFacturable.m1Hebergement,
              libelle: 'Taxe de séjour (2 nuits)',
              prixUnitaire: 500,
              quantite: 2,
            ),
          ],
        ),
      );
      await service().normaliser(sejour.id);
      corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      final produit = (corps['products'] as List).single as Map;
      expect(produit['tax'], 'F');
      expect(produit['label'], 'TAXE DE SEJOUR');
    });

    test('les règlements actifs de la facture, un par mode', () async {
      final p = await emettreFacture(db, montant: 10000);
      final session = await ouvrirCaissePour(db);
      Future<void> regler(String id, String mode, int centimes) =>
          db.customStatement(
            'INSERT INTO paiements_facture_local (id, piece_id, session_id, '
            'mode_paiement, montant_centimes, date_paiement, statut, '
            'utilisateur_creation_id) VALUES '
            "('$id', '${p.id}', '${session.id}', '$mode', $centimes, 0, "
            "'actif', '$caissierEssai')",
          );
      await regler('pa-1', 'especes', 400000);
      await regler('pa-2', 'mobile_money', 600000);
      await regler('pa-3', 'carte', 100000);
      await db.customStatement(
        "UPDATE paiements_facture_local SET statut = 'annule', "
        "motif_annulation = 'Erreur', annule_par_id = '$caissierEssai', "
        'date_annulation = 0 '
        "WHERE id = 'pa-3'",
      );

      await service().normaliser(p.id);
      final corps = jsonDecode(faux.corpsPost.single) as Map<String, dynamic>;
      expect(corps['payments'], [
        {'mode': 'E', 'amount': 4000},
        {'mode': 'M', 'amount': 6000},
      ]);
    });

    test('un ticket et une facture A4 de la pièce normalisée portent le QR '
        'rendu par le boîtier ; un PDF se produit', () async {
      final p = await venteComptant();
      await service().normaliser(p.id);
      final n = await relire(p);
      final ticket = TicketFacture.composer(n);
      expect(ticket.qrCode, qrDuPilote());
      expect(ticket.texteBrut, contains('NIM-TC : ED04000623-41'));
      expect((await ticket.pdf()).length, greaterThan(500));

      // Une pièce NON normalisée : aucun QR, aucune mention de démonstration (facture
      // simple), « en attente de normalisation » seulement si le poste normalise.
      final autre = await venteComptant();
      final simple = TicketFacture.composer(autre);
      expect(simple.qrCode, isNull);
      expect(simple.texteBrut, isNot(contains('DÉMONSTRATION')));
      expect(simple.texteBrut, isNot(contains('attente de normalisation')));
      final attente = TicketFacture.composer(autre, normalisable: true);
      expect(attente.qrCode, isNull);
      expect(
        attente.texteBrut,
        contains('Facture en attente de normalisation'),
      );
    });
  });

  group('une pièce NORMALISÉE est figée', () {
    test('« Normaliser » une seconde fois ne refait rien : aucune requête, '
        'aucune opération de plus', () async {
      final p = await venteComptant();
      await service().normaliser(p.id);
      final requetes = faux.requetes.length;
      final charges = (await chargesEnFile()).length;

      final r = await service().normaliser(p.id);
      expect(r, isA<DejaNormalisee>());
      expect(faux.requetes, hasLength(requetes));
      expect(await chargesEnFile(), hasLength(charges));
    });

    test('le DAO refuse d’écraser une normalisation, de la renoter ou de la '
        'remplacer — la pièce reste telle quelle', () async {
      final p = await venteComptant();
      await service().normaliser(p.id);
      final avant = await relire(p);
      final dao = factureDaoSur(db);

      await expectLater(
        dao.enregistrerIssueNormalisation(
          p.id,
          const EnAttente('Boîtier absent'),
          voie: VoieNormalisation.boitier,
        ),
        throwsA(isA<FactureDejaNormalisee>()),
      );
      await expectLater(
        dao.enregistrerIssueNormalisation(
          p.id,
          Certifiee(
            CertificationMecefResultat(
              nim: 'ZZ99999999',
              compteur: 7,
              codeMecef: 'AUTRE',
              qrCode: 'F;ZZ99999999;AUTRE;3201910768821;20261107100000',
              dateCertification: DateTime(2026, 11, 8),
            ),
          ),
          voie: VoieNormalisation.boitier,
        ),
        throwsA(isA<FactureDejaNormalisee>()),
      );
      await expectLater(
        dao.noterTentativeNormalisation(
          p.id,
          compteurAvant: '99',
          voie: VoieNormalisation.boitier,
        ),
        throwsA(isA<FactureDejaNormalisee>()),
      );

      final apres = await relire(p);
      expect(apres.numeroMecef, avant.numeroMecef);
      expect(apres.qrCodeFiscal, avant.qrCodeFiscal);
      expect(apres.normalisationStatut, StatutNormalisation.normalisee);
      expect(apres.normalisationCompteur, '41');
    });

    test('une normalisation descendue d’ailleurs n’écrase jamais celle de ce '
        'poste', () async {
      final p = await venteComptant();
      await service().normaliser(p.id);
      await factureDaoSur(db).adopterNormalisationDescendue(
        p.id,
        statut: StatutNormalisation.normalisee,
        voie: VoieNormalisation.emecef,
        numeroMecef: 'AUTRE-9',
        qrCode: 'F;AUTRE;X;3201910768821;20261107100000',
      );
      final n = await relire(p);
      expect(n.numeroMecef, 'ED04000623-41');
      expect(n.normalisationMode, VoieNormalisation.boitier);
    });

    test(
      'adopter une normalisation d’ailleurs (e-MECeF) sur une pièce qui n’en '
      'a pas ; un « en attente » du serveur n’écrase pas un « à vérifier »',
      () async {
        final a = await venteComptant();
        await factureDaoSur(db).adopterNormalisationDescendue(
          a.id,
          statut: StatutNormalisation.normalisee,
          voie: VoieNormalisation.emecef,
          numeroMecef: 'EM12345-77',
          qrCode: 'F;EM12345;CODE;3201910768821;20261107100000',
          codeMecef: 'CODE',
          compteur: '77',
          date: DateTime(2026, 11, 7, 9),
        );
        final n = await relire(a);
        expect(n.estNormalisee, isTrue);
        expect(n.normalisationMode, VoieNormalisation.emecef);
        // Adoptée, jamais renvoyée : aucune opération de plus.
        expect(await chargesEnFile(), hasLength(1));

        final b = await venteComptant();
        faux.couperApresTraitement = true;
        await service().normaliser(b.id);
        expect(
          (await relire(b)).normalisationStatut,
          StatutNormalisation.aVerifier,
        );
        await factureDaoSur(db).adopterNormalisationDescendue(
          b.id,
          statut: StatutNormalisation.enAttente,
          voie: VoieNormalisation.boitier,
          motif: 'Autre poste',
        );
        expect(
          (await relire(b)).normalisationStatut,
          StatutNormalisation.aVerifier,
        );
      },
    );

    test(
      'une facture ANCIENNE (jamais transmise) se normalise sans rien mettre '
      'en file',
      () async {
        await db.customStatement(
          'INSERT INTO pieces_facturation_local (id, numero, origine, '
          'date_emission, client_nom, statut, mode_paiement, '
          'statut_transmission) VALUES '
          "('anc-1', 'F-2026-00001', 'pos_comptant', 0, 'ANCIEN', 'emise', "
          "'especes', 'non_transmissible')",
        );
        await db.customStatement(
          'INSERT INTO lignes_piece_facturation_local (id, piece_id, '
          'module_source, libelle, prix_unitaire, quantite, ordre) VALUES '
          "('anc-1:0', 'anc-1', 'M5', 'Bière', 1000, 2, 0)",
        );
        final r = await service().normaliser('anc-1');
        expect(r, isA<NormalisationFaite>());
        expect((await factureDaoSur(db).parId('anc-1'))!.estNormalisee, isTrue);
        expect(await chargesEnFile(), isEmpty);
      },
    );
  });

  group(
    'les échecs laissent la pièce « en attente », avec un motif français',
    () {
      test('appareil absent : en attente, rejouable, rien d’envoyé', () async {
        faux.appareilAbsent = true;
        final p = await venteComptant();
        final r = await service().normaliser(p.id) as NormalisationFaite;
        expect(r.issue, isA<EnAttente>());

        final n = await relire(p);
        expect(n.normalisationStatut, StatutNormalisation.enAttente);
        expect(n.normalisationMotif, contains('n’est pas branché'));
        expect(n.normalisationStatut!.rejouable, isTrue);
        expect(n.estNormalisee, isFalse);
        expect(n.numeroMecef, isNull);
        expect(n.normalisationCompteurAvant, isNull);
        expect(faux.corpsPost, isEmpty);

        // « Réessayer » : le boîtier est rebranché.
        faux.appareilAbsent = false;
        final r2 = await service().normaliser(p.id) as NormalisationFaite;
        expect(r2.issue, isA<Certifiee>());
        expect((await relire(p)).estNormalisee, isTrue);
        expect((await relire(p)).normalisationMotif, isNull);
      });

      test('le motif part au serveur avec le statut', () async {
        faux.appareilAbsent = true;
        final p = await venteComptant();
        await service().normaliser(p.id);
        final n = (await chargesEnFile()).last['normalisation'] as Map;
        expect(n['statut'], 'en_attente');
        expect(n['mode'], 'boitier');
        expect(n['motif'], contains('n’est pas branché'));
        expect(n.containsKey('numero_mecef'), isFalse);
        expect(n.containsKey('qr_code'), isFalse);
      });

      test(
        '400 : « refusée », rejouable ; IFU différent, IFU absent, '
        'opérateur absent, règlement absent : en attente, aucune requête',
        () async {
          faux.surBill = (_) =>
              (statut: 400, corps: jsonEncode({'errors': '[label: too long]'}));
          final p = await venteComptant();
          await service().normaliser(p.id);
          var n = await relire(p);
          expect(n.normalisationStatut, StatutNormalisation.refusee);
          expect(n.normalisationMotif, startsWith('Le boîtier a refusé'));
          expect(n.normalisationStatut!.rejouable, isTrue);

          // IFU différent : le pilote est interrogé (info), jamais posté.
          faux.corpsPost.clear();
          faux.surBill = (_) => (statut: 200, corps: '{}');
          await configurer(ifu: '0202011344660');
          final q = await venteComptant();
          await service().normaliser(q.id);
          expect(
            (await relire(q)).normalisationMotif,
            contains('IFU du boîtier'),
          );
          expect(faux.corpsPost, isEmpty);

          // IFU invalide : aucune requête du tout.
          faux.requetes.clear();
          await configurer(ifu: '123');
          final r = await venteComptant();
          await service().normaliser(r.id);
          expect((await relire(r)).normalisationMotif, contains('13 chiffres'));
          expect(faux.requetes, isEmpty);

          // Opérateur absent.
          await configurer(operateur: false);
          await db.customStatement(
            "DELETE FROM parametres_systeme_local WHERE cle LIKE 'mecef_operateur%'",
          );
          final s = await venteComptant();
          await service().normaliser(s.id);
          expect((await relire(s)).normalisationMotif, contains('opérateur'));
          expect(faux.requetes, isEmpty);

          // Une facture sans règlement ni mode : pas normalisable.
          await configurer();
          final sansReglement = await emettreFacture(db);
          await service().normaliser(sansReglement.id);
          expect(
            (await relire(sansReglement)).normalisationMotif,
            contains('n’est pas réglée'),
          );
          expect(faux.requetes, isEmpty);
        },
      );

      test('la convention HT est refusée avec sa phrase', () async {
        await configurer(convention: 'ht');
        final p = await venteComptant();
        await service().normaliser(p.id);
        expect(
          (await relire(p)).normalisationMotif,
          contains('convention de prix « HT »'),
        );
        expect(faux.requetes, isEmpty);
      });

      test(
        'un règlement par virement part en mode V (aucun repli sur espèces)',
        () async {
          final p = await emettreFacture(db, montant: 10000);
          final session = await ouvrirCaissePour(db);
          await db.customStatement(
            'INSERT INTO paiements_facture_local (id, piece_id, session_id, '
            'mode_paiement, montant_centimes, date_paiement, statut, '
            'utilisateur_creation_id) VALUES '
            "('pa-1', '${p.id}', '${session.id}', 'virement', 1000000, 0, "
            "'actif', '$caissierEssai')",
          );
          await service().normaliser(p.id);
          expect((await relire(p)).normalisationStatut, isNotNull);
          // Le virement est un mode connu : la requête part.
          expect(faux.corpsPost, hasLength(1));
          expect((jsonDecode(faux.corpsPost.single) as Map)['payments'], [
            {'mode': 'V', 'amount': 10000},
          ]);
        },
      );
    },
  );

  group('la réponse PERDUE : ne jamais facturer deux fois', () {
    test('coupure après traitement : « à vérifier », compteur noté ; '
        '« Réessayer » ne reposte PAS', () async {
      faux
        ..couperApresTraitement = true
        ..surBill = (_) => (statut: 200, corps: '{}');
      final p = await venteComptant();
      await service().normaliser(p.id);

      var n = await relire(p);
      expect(n.normalisationStatut, StatutNormalisation.aVerifier);
      expect(n.normalisationCompteurAvant, '40');
      expect(n.normalisationStatut!.rejouable, isFalse);
      expect(n.normalisationMotif, contains('compteur 40 → 41'));
      expect(n.estNormalisee, isFalse);
      expect(faux.corpsPost, hasLength(1));

      faux.couperApresTraitement = false;
      faux.surBill = (_) =>
          (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
      await service().normaliser(p.id);
      n = await relire(p);
      expect(n.normalisationStatut, StatutNormalisation.aVerifier);
      expect(faux.corpsPost, hasLength(1), reason: 'AUCUN second POST');
    });

    test('délai sans effet au boîtier : « en attente », le compteur reste '
        'noté ; le rejeu poste UNE fois', () async {
      faux
        ..incrementerCompteurAuPost = false
        ..delaiPost = const Duration(milliseconds: 600)
        ..surBill = (_) => (statut: 200, corps: '{}');
      final p = await venteComptant();
      await service(
        delaiEnvoi: const Duration(milliseconds: 200),
      ).normaliser(p.id);
      var n = await relire(p);
      expect(n.normalisationStatut, StatutNormalisation.enAttente);
      expect(n.normalisationCompteurAvant, '40');

      // Le boîtier est revenu : le compteur n'a pas bougé, le rejeu poste.
      faux
        ..delaiPost = Duration.zero
        ..incrementerCompteurAuPost = true
        ..surBill = (_) =>
            (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
      await service().normaliser(p.id);
      n = await relire(p);
      expect(n.estNormalisee, isTrue);
      expect(n.normalisationCompteurAvant, isNull);
    });

    test('le compteur est noté SUR LA PIÈCE avant que le POST parte', () async {
      int? noteAuMomentDuPost;
      final p = await venteComptant();
      faux.surBill = (_) async {
        final ligne = await db
            .customSelect(
              'SELECT normalisation_compteur_avant AS c FROM '
              "pieces_facturation_local WHERE id = '${p.id}'",
            )
            .getSingle();
        noteAuMomentDuPost = int.tryParse('${ligne.data['c']}');
        return (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
      };
      await service().normaliser(p.id);
      expect(noteAuMomentDuPost, 40);
    });
  });

  group('un avoir : correction d’une facture normalisée', () {
    test('DÉCISION DU PO (07/11/2026) : l’annulation ET l’avoir partiel d’une '
        'facture normalisée sont REFUSÉS au DAO, avec la phrase, et RIEN n’est '
        'écrit localement', () async {
      final f = await venteComptant();
      await service().normaliser(f.id);
      final apres = await relire(f);
      expect(apres.estNormalisee, isTrue);

      final piecesAvant = await factureDaoSur(db).pieces();
      final fileAvant = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.factures);

      await expectLater(
        factureDaoSur(db).annuler(f.id, 'Erreur'),
        throwsA(
          isA<AvoirEnLigneRequis>().having(
            (e) => '$e',
            'phrase',
            'Un avoir sur une facture normalisée se fait en ligne : '
                'reconnectez le poste au serveur.',
          ),
        ),
      );
      await expectLater(
        factureDaoSur(db).emettreAvoirPartiel(f.id, 1000, 'Geste'),
        throwsA(isA<AvoirEnLigneRequis>()),
      );

      // RIEN d'écrit : ni avoir, ni statut annulée, ni opération en file.
      final piecesApres = await factureDaoSur(db).pieces();
      expect(piecesApres, hasLength(piecesAvant.length));
      expect(piecesApres.where((p) => p.estAvoir), isEmpty);
      final relue = await relire(f);
      expect(relue.estAnnulee, isFalse);
      expect(relue.estNormalisee, isTrue);
      final fileApres = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.factures);
      expect(fileApres, hasLength(fileAvant.length));
    });

    test('l’avoir créé AU SERVEUR descend (identifiant serveur), naît « en attente » '
        'quand le serveur le dit, et passe par le boîtier (rt = FA, rn = NIM-TC) ; '
        'la facture ne bouge pas', () async {
      final f = await venteComptant();
      await service().normaliser(f.id);
      final facture = await relire(f);
      final dao = factureDaoSur(db);

      // Ce que la descente fait d'un avoir créé au serveur (mode boîtier : en attente).
      const idServeur = 'avoir-serveur-0001';
      await dao.inscrireAvoirDescendu(
        id: idServeur,
        factureId: f.id,
        numero: 'AV-2026-00007',
        motif: 'Erreur',
        montant: facture.montantTotal,
        dateEmission: DateTime(2026, 11, 7, 10),
      );
      await dao.adopterNormalisationDescendue(
        idServeur,
        statut: StatutNormalisation.enAttente,
        voie: VoieNormalisation.boitier,
        motif:
            'En attente de normalisation par le poste de la réception (boîtier CC300).',
      );
      final avoir = (await dao.parId(idServeur))!;
      expect(avoir.normalisationStatut, StatutNormalisation.enAttente);
      expect(
        (await relire(f)).estAnnulee,
        isTrue,
        reason: 'avoir du TTC entier',
      );

      final r = await service().normaliser(avoir.id) as NormalisationFaite;
      expect(r.issue, isA<Certifiee>());
      final corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      expect(corps['rt'], 'FA');
      expect(corps['rn'], 'ED04000623-41');
      expect(corps.containsKey('vt'), isFalse);
      // Positifs : le sens se dit par rt/rn, pas par un montant négatif.
      expect(((corps['products'] as List).single as Map)['price'], 10000);
      expect(corps['payments'], [
        {'mode': 'E', 'amount': 30000},
      ]);

      final apres = await relire(avoir);
      expect(apres.estNormalisee, isTrue);
      expect(apres.numeroMecef, 'ED04000623-1', reason: 'compteur des AVOIRS');
      // La facture d'origine est intacte (RG-03).
      final f2 = await relire(f);
      expect(f2.numeroMecef, facture.numeroMecef);
      expect(f2.qrCodeFiscal, facture.qrCodeFiscal);

      // Vers le serveur : sur la FACTURE, avec l'identifiant SERVEUR de l'avoir.
      final ops = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.factures);
      final derniere = ops.last;
      expect(derniere.entiteId, f.id);
      final charge = jsonDecode(derniere.payload) as Map<String, Object?>;
      expect(charge['avoir_id'], idServeur);
      expect((charge['normalisation'] as Map)['numero_mecef'], 'ED04000623-1');
      // Aucune annulation ne part par la file : l'avoir est né au serveur.
      expect(
        ops.where(
          (o) =>
              (jsonDecode(o.payload) as Map).containsKey('statut') &&
              (jsonDecode(o.payload) as Map)['statut'] == 'annulee',
        ),
        isEmpty,
      );
    });

    test('l’avoir d’une facture NON normalisée n’a rien à normaliser ; le '
        'normaliser est refusé sans requête', () async {
      final f = await venteComptant();
      final avoir = (await factureDaoSur(db).annuler(f.id, 'Doublon')).avoir;
      expect(avoir.normalisationStatut, isNull);

      final r = await service().normaliser(avoir.id) as NormalisationFaite;
      expect(r.issue, isA<EnAttente>());
      expect(
        (await relire(avoir)).normalisationMotif,
        contains('n’est pas normalisée'),
      );
      expect(faux.requetes, isEmpty);
    });

    test('une facture ANNULÉE ne se normalise pas', () async {
      final f = await venteComptant();
      await factureDaoSur(db).annuler(f.id, 'Doublon');
      final r = await service().normaliser(f.id) as NormalisationFaite;
      expect(r.issue, isA<EnAttente>());
      expect((await relire(f)).normalisationMotif, contains('est annulée'));
      expect(faux.requetes, isEmpty);
    });
  });

  /* ================================================================== */
  group('l’IFU du CLIENT (décision du PO du 07/11/2026)', () {
    Future<PieceFacturation> venteAvec({
      String? ifu,
      String? nom,
      String clientNom = 'Client de passage',
      bool retenir = false,
    }) => factureDaoSur(db).emettre(
      BrouillonFacture(
        origine: OrigineFacture.posComptant,
        clientNom: clientNom,
        modePaiement: 'especes',
        acheteurIfu: ifu,
        acheteurNom: nom,
        retenirIfu: retenir,
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m5Bar,
            libelle: 'Béninoise 33cl',
            prixUnitaire: 1000,
            quantite: 3,
          ),
        ],
      ),
    );

    test('IFU renseigné : rangé sur la pièce, parti au serveur avec le nom et '
        '« Retenir pour ce client »', () async {
      final p = await venteAvec(
        ifu: '3201 9107 68821',
        nom: ' SARL Atacora ',
        retenir: true,
      );

      expect(p.acheteurIfu, '3201910768821', reason: 'séparateurs ôtés');
      expect(p.acheteurNom, 'SARL Atacora');
      final charge = (await chargesEnFile()).single;
      expect(charge['acheteur_ifu'], '3201910768821');
      expect(charge['acheteur_nom'], 'SARL Atacora');
      expect(charge['retenir_ifu'], isTrue);
    });

    test(
      'vide : client SANS IFU — aucune clé envoyée, « Retenir » sans objet',
      () async {
        final p = await venteAvec(ifu: '  ', retenir: true);

        expect(p.acheteurIfu, isNull);
        final charge = (await chargesEnFile()).single;
        expect(charge.containsKey('acheteur_ifu'), isFalse);
        expect(charge.containsKey('acheteur_nom'), isFalse);
        expect(charge.containsKey('retenir_ifu'), isFalse);
      },
    );

    test(
      '« Retenir pour ce client » est décoché par défaut : jamais envoyé',
      () async {
        await venteAvec(ifu: '3201910768821');
        expect(
          (await chargesEnFile()).single.containsKey('retenir_ifu'),
          isFalse,
        );
      },
    );

    test(
      '12, 14 chiffres, lettres : refusé avec LA phrase, RIEN n’est écrit',
      () async {
        for (final mauvais in [
          '320191076882',
          '32019107688211',
          '32019107688AB',
        ]) {
          await expectLater(
            venteAvec(ifu: mauvais),
            throwsA(
              isA<IfuClientInvalide>().having(
                (e) => '$e',
                'phrase',
                'L\'IFU du client doit compter exactement 13 chiffres (laissez '
                    'vide pour un client sans IFU).',
              ),
            ),
            reason: mauvais,
          );
        }
        expect(await factureDaoSur(db).pieces(), isEmpty);
        expect(await chargesEnFile(), isEmpty);
      },
    );

    test('le boîtier reçoit buyer_ifu et buyer_name saisis ; sans IFU la clé '
        'buyer_ifu est ABSENTE (facultative) et le nom reste', () async {
      final avec = await venteAvec(ifu: '3201910768821', nom: 'SARL Atacora');
      await service().normaliser(avec.id);
      var corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      expect(corps['buyer_ifu'], '3201910768821');
      expect(corps['buyer_name'], 'SARL Atacora');

      final sans = await venteAvec();
      await service().normaliser(sans.id);
      corps = jsonDecode(faux.corpsPost.last) as Map<String, dynamic>;
      expect(corps.containsKey('buyer_ifu'), isFalse);
      expect(corps['buyer_name'], 'Client de passage');
    });

    test(
      '« Client divers » : seulement quand ni nom saisi ni nom de pièce',
      () {
        expect(IfuClient.nomPourNormalisation('SARL Atacora'), 'SARL Atacora');
        expect(
          IfuClient.nomPourNormalisation('  ', repli: 'KORA Jean'),
          'KORA Jean',
        );
        expect(IfuClient.nomPourNormalisation(null), 'Client divers');
        expect(
          IfuClient.nomPourNormalisation(' ', repli: ' '),
          'Client divers',
        );
      },
    );

    test('un IFU invalide déjà rangé n’est jamais envoyé au boîtier', () async {
      final p = await venteAvec();
      await db.customStatement(
        "UPDATE pieces_facturation_local SET acheteur_ifu = '123' WHERE id = '${p.id}'",
      );
      final r = await service().normaliser(p.id) as NormalisationFaite;
      expect(r.issue, isA<EnAttente>());
      expect(faux.corpsPost, isEmpty);
      expect((await relire(p)).normalisationMotif, TextesIfuClient.invalide);
    });
  });
}
