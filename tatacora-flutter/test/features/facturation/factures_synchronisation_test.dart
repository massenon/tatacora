import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/outils_encaissement.dart';

/// Lots F5c et F5d (décisions du PO du 17/10/2026) : la facture du poste est
/// PROVISOIRE et part au serveur ; le numéro continu du serveur la
/// régularise ; l'encaissement suit sa facture. Une pièce ancienne (jamais
/// transmise) ne part pas.
void main() {
  late AppDatabase db;

  setUp(() async => db = await baseEncaissement());
  tearDown(() => db.close());

  Future<List<OperationSync>> file(TableSynchronisee table) =>
      OperationsSyncDao(db).operations(table: table);

  Map<String, Object?> charge(OperationSync o) =>
      jsonDecode(o.payload) as Map<String, Object?>;

  Future<String?> transmission(String id) async =>
      (await db
                  .customSelect(
                    'SELECT statut_transmission FROM pieces_facturation_local '
                    'WHERE id = ?',
                    variables: [Variable.withString(id)],
                  )
                  .getSingle())
              .data['statut_transmission']
          as String?;

  /// Une pièce ANCIENNE, émise avant la synchronisation des factures.
  Future<void> semerPieceAncienne(String id, String numero) async {
    await db.customStatement(
      'INSERT INTO pieces_facturation_local (id, numero, origine, '
      'date_emission, client_nom, statut, statut_transmission) VALUES '
      "('$id', '$numero', 'facture_directe', 0, 'ANCIEN', 'emise', "
      "'non_transmissible')",
    );
    await db.customStatement(
      'INSERT INTO lignes_piece_facturation_local (id, piece_id, '
      'module_source, libelle, prix_unitaire, quantite, ordre) VALUES '
      "('$id:0', '$id', 'M5', 'Bière', 1000, 2, 0)",
    );
  }

  group('Envoi (F5c)', () {
    test(
      'la facture naît PROVISOIRE et part au serveur, au prix vendu',
      () async {
        final f = await emettreFacture(db, montant: 30000);

        expect(f.numero, 'PROV-2026-00001');
        expect(f.estProvisoire, isTrue);
        expect(await transmission(f.id), 'en_attente');

        final op = (await file(TableSynchronisee.factures)).single;
        expect(op.entiteId, f.id);
        expect(op.type, TypeOperationSync.creation);
        expect(charge(op), {
          'origine': 'facture_directe',
          'date_emission': '2026-10-12',
          'client_id': null,
          'reservation_id': null,
          'panier_id': null,
          'lignes': [
            {
              'module': 'M5',
              'libelle': 'Prestation',
              'prix_unitaire': 30000,
              'quantite': 1,
            },
          ],
        });
      },
    );

    test('l’annulation part (la seule modification) ; l’avoir est '
        'provisoire', () async {
      final f = await emettreFacture(db);
      final r = await factureDaoSur(db).annuler(f.id, 'Erreur de chambre');

      expect(r.avoir.numero, 'PROV-2026-00002');
      final ops = await file(TableSynchronisee.factures);
      expect(ops, hasLength(2));
      expect(ops.last.type, TypeOperationSync.modification);
      expect(charge(ops.last), {
        'statut': 'annulee',
        'motif': 'Erreur de chambre',
      });
    });

    test('une pièce ANCIENNE ne part pas, son annulation non plus', () async {
      await semerPieceAncienne('anc-1', 'F-2026-00001');
      await factureDaoSur(db).annuler('anc-1', 'Doublon');

      expect(await file(TableSynchronisee.factures), isEmpty);
    });
  });

  group('Régularisation du numéro (F5c, Q2)', () {
    test('le numéro du serveur remplace le provisoire, l’avoir suit et '
        'désigne la facture par son NOUVEAU numéro', () async {
      final f = await emettreFacture(db);
      await factureDaoSur(db).annuler(f.id, 'Erreur');
      final dao = FactureDao(db);

      await dao.regulariserNumeros(
        f.id,
        numero: 'F-2026-00042',
        numeroAvoir: 'AV-2026-00007',
      );
      // Idempotent : un second passage (la descente) ne change rien.
      await dao.regulariserNumeros(f.id, numero: 'F-2026-00042');

      final facture = (await dao.parId(f.id))!;
      expect(facture.numero, 'F-2026-00042');
      expect(facture.estProvisoire, isFalse);
      final avoir = (await dao.avoirsDe('F-2026-00042')).single;
      expect(avoir.numero, 'AV-2026-00007');
      expect(await transmission(f.id), 'transmise');
      expect(await transmission(avoir.id), 'transmise');
    });

    test('une pièce ANCIENNE qui porte déjà ce numéro le cède : LOC-, '
        'ses avoirs suivent', () async {
      await semerPieceAncienne('anc-1', 'F-2026-00001');
      await factureDaoSur(db).annuler('anc-1', 'Doublon');
      final ancienAvoir = (await FactureDao(
        db,
      ).avoirsDe('F-2026-00001')).single;
      final f = await emettreFacture(db);

      await FactureDao(db).regulariserNumeros(f.id, numero: 'F-2026-00001');

      expect((await FactureDao(db).parId(f.id))!.numero, 'F-2026-00001');
      expect((await FactureDao(db).parId('anc-1'))!.numero, 'LOC-F-2026-00001');
      expect(
        (await FactureDao(db).parId(ancienAvoir.id))!.avoirDe,
        'LOC-F-2026-00001',
      );
    });

    test('un numéro déjà porté par une pièce TRANSMISE : refus, rien '
        'n’est écrit', () async {
      final a = await emettreFacture(db);
      final b = await emettreFacture(db);
      await FactureDao(db).regulariserNumeros(a.id, numero: 'F-2026-00001');

      await expectLater(
        FactureDao(db).regulariserNumeros(b.id, numero: 'F-2026-00001'),
        throwsStateError,
      );
      expect((await FactureDao(db).parId(b.id))!.numero, b.numero);
      expect(await transmission(b.id), 'en_attente');
    });
  });

  group('Encaissement (F5d)', () {
    test('l’encaissement d’une facture qui part, part aussi : centimes, '
        'caisse du poste ; son annulation aussi', () async {
      final caisse = await ouvrirCaissePour(db);
      final f = await emettreFacture(db, montant: 30000);
      final dao = paiementsDaoSur(db);

      final p = await dao.encaisser(
        pieceId: f.id,
        montant: '10000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      final op = (await file(TableSynchronisee.paiements)).single;
      expect(op.entiteId, p.id);
      expect(charge(op), {
        'facture_id': f.id,
        'session_id': caisse.id,
        'mode_paiement': 'especes',
        'montant': 1000000,
        'date_paiement': '2026-10-12 10:00:00',
      });

      await dao.annuler(p.id, 'Doublon', auteurId: caissierEssai);
      final ops = await file(TableSynchronisee.paiements);
      expect(ops.last.type, TypeOperationSync.modification);
      expect(charge(ops.last), {'statut': 'annule', 'motif': 'Doublon'});
    });

    test('sur une pièce ANCIENNE, l’encaissement reste local', () async {
      await ouvrirCaissePour(db);
      await semerPieceAncienne('anc-1', 'F-2026-00001');

      await paiementsDaoSur(db).encaisser(
        pieceId: 'anc-1',
        montant: '1000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      expect(await file(TableSynchronisee.paiements), isEmpty);
    });

    test('après régularisation, l’annulation retrouve la pièce passée sous '
        'le numéro PROVISOIRE et la contre-passe', () async {
      await ouvrirCaissePour(db);
      final f = await emettreFacture(db, montant: 30000);
      final dao = paiementsDaoSur(db);
      final p = await dao.encaisser(
        pieceId: f.id,
        montant: '10000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await FactureDao(db).regulariserNumeros(f.id, numero: 'F-2026-00042');

      final annule = await dao.annuler(
        p.id,
        'Doublon',
        auteurId: caissierEssai,
      );
      expect(annule.statut, StatutPaiementFacture.annule);
      expect(
        await ComptabiliteDao(
          db,
        ).lignesParLibelle('Encaissement PROV-2026-00001 — ${p.id}'),
        hasLength(2),
        reason: 'la pièce d’origine garde le numéro du jour',
      );
      final toutes = await ComptabiliteDao(db).toutesLesEcritures();
      expect(toutes.length, 4, reason: 'pièce + contre-passation entière');
    });
  });
}
