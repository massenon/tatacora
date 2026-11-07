import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/data/client_mecef_boitier.dart';
import 'package:tatacora_flutter/features/facturation/data/pilote_boitier.dart';
import 'package:tatacora_flutter/features/facturation/domain/client_mecef.dart';
import 'package:tatacora_flutter/features/facturation/domain/conversion_boitier.dart';

import '../../support/faux_pilote_boitier.dart';

/// `ClientMecefBoitier` contre un FAUX pilote HTTP sur la boucle locale (un vrai
/// serveur dart:io, de vraies requêtes TCP) qui reproduit les défauts du vrai :
/// 200 sur un échec, corps vide ou erroné, réponse perdue.
void main() {
  HttpOverrides.global = null;

  late FauxPilote faux;

  setUp(() async => faux = await FauxPilote.demarrer());
  tearDown(() async => faux.arreter());

  DemandeNormalisation demande({String? reference, int prix = 15000}) =>
      DemandeNormalisation(
        pieceId: 'p-1',
        numero: 'F-2026-00001',
        lignes: [
          LigneDemande(
            libelle: 'Nuitée chambre 3',
            prixUnitaire: prix,
            quantite: 2,
            groupe: GroupeTaxe.b,
          ),
        ],
        paiements: [
          PaiementDemande(mode: ModePaiementPilote.especes, montant: prix * 2),
        ],
        clientNom: 'Client de passage',
        operateurId: 'RECEPTION01',
        operateurNom: 'Réception',
        referenceAvoir: reference,
      );

  ClientMecefBoitier client({
    Duration delaiEnvoi = const Duration(seconds: 5),
    String ifu = '3201910768821',
    Duration attente = Duration.zero,
  }) => ClientMecefBoitier(
    attenteApresDelai: attente,
    pilote: PiloteBoitier(
      racine: faux.racine,
      delaiEnvoi: delaiEnvoi,
      delaiInfo: const Duration(seconds: 5),
    ),
    ifuEntreprise: ifu,
  );

  FutureOr<({int statut, String corps})?> Function(String) succes() =>
      (_) => (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));

  group('le succès', () {
    test(
      'info avant, POST, info après : NIM, code, QR, date, compteur',
      () async {
        faux.surBill = succes();
        final issue = await client().certifier(demande());

        expect(issue, isA<Certifiee>());
        final r = (issue as Certifiee).resultat;
        expect(r.nim, 'ED04000623');
        expect(r.compteur, 41, reason: 'compteur 40 avant, 41 après');
        expect(r.numeroMecef, 'ED04000623-41');
        expect(r.codeMecef, 'NW34NID6ZHANFNMZ2IU7LL3H');
        expect(
          r.qrCode,
          'F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20261107100000',
        );
        expect(r.dateCertification, DateTime(2026, 11, 7, 10));
        expect(faux.requetes, ['GET /info', 'POST /bill', 'GET /info']);
        final corps = jsonDecode(faux.corpsPost.single) as Map<String, dynamic>;
        expect(corps['vt'], 'FV');
        expect(corps['seller_id'], 'RECEPTION01');
        expect(ClientMecefBoitier.verrouPris, isFalse, reason: 'verrou rendu');
      },
    );

    test(
      'un avoir : rt = FA, rn = NIM-TC, et le compteur des AVOIRS',
      () async {
        faux.surBill = succes();
        final issue = await client().certifier(
          demande(reference: 'ED04000623-17'),
        );
        expect(issue, isA<Certifiee>());
        expect((issue as Certifiee).resultat.compteur, 1);
        final corps = jsonDecode(faux.corpsPost.single) as Map<String, dynamic>;
        expect(corps['rt'], 'FA');
        expect(corps['rn'], 'ED04000623-17');
        expect(corps.containsKey('vt'), isFalse);
        expect(faux.compteurVentes, 40, reason: 'les ventes n’ont pas bougé');
      },
    );

    test('le compteur est noté AVANT que le POST parte', () async {
      String? notePendantLePost;
      var note = '';
      faux.surBill = (_) {
        notePendantLePost = note;
        return (statut: 200, corps: jsonEncode({'qr_code': qrDuPilote()}));
      };
      await client().certifier(demande(), surEnvoi: (c) => note = c);
      expect(notePendantLePost, '40');
    });
  });

  group('les échecs CERTAINS : rien n’est facturé, la pièce se rejoue', () {
    test('503 : appareil absent, aucun POST', () async {
      faux.appareilAbsent = true;
      final issue = await client().certifier(demande());
      expect(issue, isA<EnAttente>());
      expect((issue as EnAttente).motif, contains('n’est pas branché'));
      expect(faux.requetes, ['GET /info']);
      expect(faux.corpsPost, isEmpty);
    });

    test('pilote éteint : phrase claire, aucun POST', () async {
      await faux.arreter();
      final issue = await client().certifier(demande());
      expect(issue, isA<EnAttente>());
      expect((issue as EnAttente).motif, contains('ne répond pas'));
    });

    test(
      'IFU du boîtier ≠ IFU de l’entreprise : refusé AVANT tout POST',
      () async {
        faux.surBill = succes();
        final issue = await client(ifu: '0202011344660').certifier(demande());
        expect(issue, isA<EnAttente>());
        expect(
          (issue as EnAttente).motif,
          'L’IFU du boîtier (3201910768821) n’est pas celui de l’entreprise '
          '(0202011344660).',
        );
        expect(faux.corpsPost, isEmpty);
      },
    );

    test(
      'montants incohérents ou trop grands : AUCUNE requête du tout',
      () async {
        final incoherent = DemandeNormalisation(
          pieceId: 'p-1',
          numero: 'F-1',
          lignes: const [
            LigneDemande(
              libelle: 'x',
              prixUnitaire: 1000,
              quantite: 1,
              groupe: GroupeTaxe.a,
            ),
          ],
          paiements: const [
            PaiementDemande(mode: ModePaiementPilote.especes, montant: 900),
          ],
          clientNom: 'c',
          operateurId: 'o',
          operateurNom: 'n',
        );
        final issue = await client().certifier(incoherent);
        expect(issue, isA<EnAttente>());
        expect(
          (issue as EnAttente).motif,
          contains('Les montants ne concordent pas'),
        );
        expect(faux.requetes, isEmpty);
      },
    );

    test('400 : refusée par le boîtier, avec le détail, jamais rejouée à '
        'l’aveugle', () async {
      faux.incrementerCompteurAuPost = false;
      faux.surBill = (_) => (
        statut: 400,
        corps: jsonEncode({'errors': '[label: Does not match]'}),
      );
      final issue = await client().certifier(demande());
      expect(issue, isA<Refusee>());
      expect(
        (issue as Refusee).motif,
        startsWith('Le boîtier a refusé la facture :'),
      );
      expect(issue.motif, contains('label'));
    });
  });

  group('200 sur un échec : le corps se VALIDE, le compteur tranche', () {
    final corpsInvalides = <String, String>{
      'corps vide': '',
      'qr_code vide': '{"qr_code":""}',
      'pas du JSON': 'plantage du pilote',
      'erreur du pilote non JSON':
          '{error_message: device initialization failed}',
      'qr_code contenant E:': '{"qr_code":"E: device initialization failed"}',
      'qr_code sans F;':
          '{"qr_code":"X;ED04000623;ABC;3201910768821;20261107100000"}',
      'qr_code à quatre champs': '{"qr_code":"F;ED04000623;ABC;3201910768821"}',
      'qr_code d’un autre boîtier':
          '{"qr_code":"F;ZZ99999999;ABC;3201910768821;20261107100000"}',
      'pas de clé qr_code': '{"status":"ok"}',
    };

    corpsInvalides.forEach((nom, corps) {
      test('$nom, compteur INCHANGÉ : en attente, rejouable', () async {
        faux.incrementerCompteurAuPost = false;
        faux.surBill = (_) => (statut: 200, corps: corps);
        final issue = await client().certifier(demande());
        expect(issue, isA<EnAttente>(), reason: nom);
        expect(
          (issue as EnAttente).motif,
          'Le boîtier a répondu sans code de facture valide : la facture '
          'n’est pas normalisée.',
        );
        expect(faux.requetes, ['GET /info', 'POST /bill', 'GET /info']);
      });

      test('$nom, compteur AVANCÉ : à vérifier, JAMAIS rejouée', () async {
        faux.incrementerCompteurAuPost = true;
        faux.surBill = (_) => (statut: 200, corps: corps);
        final issue = await client().certifier(demande());
        expect(issue, isA<AVerifier>(), reason: nom);
        final v = issue as AVerifier;
        expect(v.compteurAvant, '40');
        expect(v.compteurApres, '41');
        expect(v.motif, contains('compteur 40 → 41'));
        expect(v.qrCode, isNull);
      });
    });
  });

  group('la réponse PERDUE', () {
    test(
      'délai : compteur inchangé → en attente ; avancé → à vérifier',
      () async {
        faux
          ..delaiPost = const Duration(milliseconds: 1500)
          ..incrementerCompteurAuPost = false
          ..surBill = (_) => (statut: 200, corps: '{}');
        var issue = await client(
          delaiEnvoi: const Duration(milliseconds: 300),
          attente: const Duration(milliseconds: 1600),
        ).certifier(demande());
        expect(issue, isA<EnAttente>());
        expect((issue as EnAttente).motif, contains('30 secondes'));
        expect(issue.incertaine, isTrue, reason: 'la requête est partie');
        expect(
          issue.compteurAvant,
          '40',
          reason: 'le compteur reste noté pour le rejeu',
        );

        faux.incrementerCompteurAuPost = true;
        issue = await client(
          delaiEnvoi: const Duration(milliseconds: 300),
          attente: const Duration(milliseconds: 1600),
        ).certifier(demande());
        expect(
          issue,
          isA<AVerifier>(),
          reason: 'le boîtier a facturé, réponse perdue',
        );
        expect((issue as AVerifier).compteurApres, '41');
      },
    );

    test('connexion coupée après traitement : à vérifier, puis le REJEU '
        'refuse de reposter tant que le compteur a avancé', () async {
      faux
        ..couperApresTraitement = true
        ..surBill = (_) => (statut: 200, corps: '{}');
      final premiere = await client().certifier(demande());
      expect(premiere, isA<AVerifier>());
      expect(faux.corpsPost, hasLength(1));
      final avant = (premiere as AVerifier).compteurAvant;
      expect(avant, '40');

      // « Réessayer » : le compteur noté par la tentative dit qu'elle a abouti.
      faux.couperApresTraitement = false;
      final rejeu = await client().certifier(
        demande(),
        compteurAvantPrecedent: avant,
      );
      expect(rejeu, isA<AVerifier>());
      expect(faux.corpsPost, hasLength(1), reason: 'AUCUN second POST');
    });

    test(
      'rejeu quand le compteur n’a PAS bougé : on poste, une seule fois',
      () async {
        faux.incrementerCompteurAuPost = false;
        faux.surBill = (_) => (statut: 200, corps: '{"qr_code":""}');
        final premiere = await client().certifier(demande());
        expect(premiere, isA<EnAttente>());

        faux.incrementerCompteurAuPost = true;
        faux.surBill = succes();
        final rejeu = await client().certifier(
          demande(),
          compteurAvantPrecedent: '40',
        );
        expect(rejeu, isA<Certifiee>());
        expect(faux.corpsPost, hasLength(2));
      },
    );

    test('succès net mais compteur incohérent après : à vérifier, le QR est '
        'conservé', () async {
      faux
        ..incrementerCompteurAuPost = false
        ..surBill = succes();
      final issue = await client().certifier(demande());
      expect(issue, isA<AVerifier>());
      final v = issue as AVerifier;
      expect(v.qrCode, qrDuPilote());
      expect(v.nim, 'ED04000623');
      expect(v.compteurAvant, '40');
    });
  });

  group('jamais deux POST /bill en parallèle', () {
    test(
      'le second appel rend « déjà en cours » sans toucher au boîtier',
      () async {
        faux
          ..delaiPost = const Duration(milliseconds: 400)
          ..surBill = succes();
        final c1 = client();
        final c2 = client();
        final premier = c1.certifier(demande());
        // Laisse le premier prendre le verrou.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(ClientMecefBoitier.verrouPris, isTrue);
        final second = await c2.certifier(demande());
        expect(second, isA<EnAttente>());
        expect((second as EnAttente).motif, contains('déjà en cours'));

        expect(await premier, isA<Certifiee>());
        expect(faux.maxEnParallele, 1);
        expect(faux.corpsPost, hasLength(1));
        expect(ClientMecefBoitier.verrouPris, isFalse);
      },
    );

    test('le verrou est rendu même quand tout échoue', () async {
      faux.appareilAbsent = true;
      await client().certifier(demande());
      expect(ClientMecefBoitier.verrouPris, isFalse);
      faux.appareilAbsent = false;
      faux.surBill = succes();
      expect(await client().certifier(demande()), isA<Certifiee>());
    });
  });

  group('les montants envoyés', () {
    test(
      'entiers FCFA exacts, sans décimale, dans le JSON réellement posté',
      () async {
        faux.surBill = succes();
        await client().certifier(demande(prix: 7500));
        final texte = faux.corpsPost.single;
        expect(texte, contains('"price":7500'));
        expect(texte, contains('"items":2'));
        expect(texte, contains('"amount":15000'));
        expect(texte, isNot(contains('.0')));
      },
    );
  });
}
