import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/numero_proforma.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// La facture proforma du POSTE : hors ligne, écrivain unique, file d'envoi dans la même
/// transaction, numéro provisoire jamais définitif, conversion en vraie facture locale
/// (une seule fois), jamais fiscale (PO, 07/11/2026).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProformaDao dao;
  late OperationsSyncDao file;
  var maintenant = DateTime(2026, 11, 7, 10);

  const lignes = [
    (designation: 'Chambre double', quantite: 4, prixUnitaire: 25000),
    (designation: 'Petit déjeuner', quantite: 8, prixUnitaire: 2500),
  ];

  setUp(() {
    maintenant = DateTime(2026, 11, 7, 10);
    db = AppDatabase.enMemoire();
    dao = ProformaDao(db, maintenant: () => maintenant);
    file = OperationsSyncDao(db);
  });
  tearDown(() => db.close());

  Future<Map<String, Object?>> derniereCharge() async =>
      jsonDecode(
            (await file.operations(
              table: TableSynchronisee.proformas,
            )).last.payload,
          )
          as Map<String, Object?>;

  test(
    'hors ligne : un brouillon se crée sans numéro et part dans la file',
    () async {
      final p = await dao.creer(
        clientNom: 'SARL KORA',
        objet: 'Atelier',
        lignes: lignes,
      );

      expect(p.numero, isNull);
      expect(p.statut, StatutProforma.brouillon.code);
      expect(p.total, 120000);
      expect(await dao.lignes(p.id), hasLength(2));

      final ops = await file.operations(table: TableSynchronisee.proformas);
      expect(ops, hasLength(1));
      expect(ops.single.type, TypeOperationSync.creation);
      final charge = await derniereCharge();
      expect(charge['client_nom'], 'SARL KORA');
      expect(charge.containsKey('emettre'), isFalse);
      expect(charge.containsKey('numero'), isFalse);
    },
  );

  test(
    'l\'émission pose un numéro PROVISOIRE continu, jamais définitif',
    () async {
      final a = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
      final b = await dao.creer(clientNom: 'B', lignes: lignes, emettre: true);

      expect(a.numero, 'PROV-FP-2026-00001');
      expect(b.numero, 'PROV-FP-2026-00002');
      expect(estNumeroProformaProvisoire(a.numero!), isTrue);
      expect(a.statut, StatutProforma.emise.code);
      expect(a.dateEmission, DateTime(2026, 11, 7));
      // Rejeu : même numéro, pas de numéro brûlé.
      expect((await dao.emettre(a.id)).numero, 'PROV-FP-2026-00001');
      final c = await dao.creer(clientNom: 'C', lignes: lignes, emettre: true);
      expect(c.numero, 'PROV-FP-2026-00003');

      final charge = await derniereCharge();
      expect(charge['statut'], 'emise');
      expect(
        charge.containsKey('valide_jusqu_au'),
        isTrue,
      ); // décidée au poste, même null
    },
  );

  test('un brouillon abandonné ne brûle aucun numéro', () async {
    await dao.creer(clientNom: 'Abandon', lignes: lignes);
    final p = await dao.creer(clientNom: 'Réel', lignes: lignes, emettre: true);
    expect(p.numero, 'PROV-FP-2026-00001');
  });

  test('la validité est calculée à l\'émission et ENREGISTRÉE', () async {
    final sans = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
    expect(sans.valideJusquAu, isNull);

    final reglages = ReglagesDocuments.depuis({
      ClesReglagesDocuments.validiteAffichee: 'true',
      ClesReglagesDocuments.validiteJours: '15',
      ClesReglagesDocuments.villeEmission: 'Natitingou',
      ClesReglagesDocuments.referenceFacture: 'abc',
    });
    final avec = await dao.creer(
      clientNom: 'B',
      lignes: lignes,
      emettre: true,
      reglages: reglages,
    );
    expect(avec.valideJusquAu, DateTime(2026, 11, 22));
    expect(avec.ville, 'Natitingou');
    expect(avec.reference, 'ABC');
    expect((await derniereCharge())['valide_jusqu_au'], '2026-11-22');

    // « Expirée » : dérivé, jamais stocké ; la conversion reste possible.
    maintenant = DateTime(2026, 11, 22, 18);
    expect(dao.estExpiree((await dao.parId(avec.id))!), isFalse);
    maintenant = DateTime(2026, 11, 23, 8);
    final relue = (await dao.parId(avec.id))!;
    expect(dao.estExpiree(relue), isTrue);
    expect(relue.statut, StatutProforma.emise.code);
    expect(await dao.convertirEnFacture(avec.id), isNotEmpty);
  });

  test(
    'une modification ne renvoie que les champs changés ; refusée une fois convertie',
    () async {
      final p = await dao.creer(
        clientNom: 'A',
        objet: 'Avant',
        lignes: lignes,
        emettre: true,
      );
      await dao.modifier(p.id, objet: 'Après');
      expect(await derniereCharge(), {'objet': 'Après'});

      final m = await dao.modifier(
        p.id,
        lignes: [(designation: 'Forfait', quantite: 1, prixUnitaire: 400000)],
      );
      expect(m.total, 400000);
      expect(await dao.lignes(p.id), hasLength(1));

      await dao.convertirEnFacture(p.id);
      expect(
        () => dao.modifier(p.id, objet: 'Trop tard'),
        throwsA(isA<RefusProforma>()),
      );
    },
  );

  test(
    'l\'annulation exige un motif, garde le numéro, interdit la conversion',
    () async {
      final p = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
      expect(() => dao.annuler(p.id, '  '), throwsA(isA<RefusProforma>()));

      final a = await dao.annuler(p.id, 'Client désisté');
      expect(a.statut, StatutProforma.annulee.code);
      expect(a.numero, 'PROV-FP-2026-00001');
      expect(
        (await dao.annuler(p.id, 'autre')).statut,
        StatutProforma.annulee.code,
      );
      expect(await derniereCharge(), {
        'statut': 'annulee',
        'motif': 'Client désisté',
      });
      expect(() => dao.convertirEnFacture(p.id), throwsA(isA<RefusProforma>()));
    },
  );

  test(
    'la conversion crée UNE vraie facture locale, mêmes lignes et montants, idempotente',
    () async {
      final p = await dao.creer(
        clientNom: 'SARL KORA',
        clientIfu: '0202011344660',
        sourceModule: 'location',
        lignes: lignes,
        emettre: true,
      );
      final factureId = await dao.convertirEnFacture(p.id);

      final facture = (await FactureDao(
        db,
        maintenant: () => maintenant,
      ).parId(factureId))!;
      expect(facture.montantTotal, 120000);
      expect(facture.lignes, hasLength(2));
      expect(facture.acheteurIfu, '0202011344660');
      expect(facture.acheteurNom, 'SARL KORA');
      // Jamais fiscale : la facture simple n'a aucune normalisation.
      expect(facture.numeroMecef, isNull);
      expect(facture.normalisationStatut, isNull);

      final relue = (await dao.parId(p.id))!;
      expect(relue.statut, StatutProforma.convertie.code);
      expect(relue.factureId, factureId);

      // Le lien part APRÈS la facture, dans la file.
      final tout = await file.operations();
      final iFacture = tout.indexWhere(
        (o) => o.table == TableSynchronisee.factures,
      );
      final iLien = tout.lastIndexWhere(
        (o) => o.table == TableSynchronisee.proformas,
      );
      expect(iFacture, greaterThan(-1));
      expect(iLien, greaterThan(iFacture));
      expect(await derniereCharge(), {
        'statut': 'convertie',
        'facture_id': factureId,
      });

      // Une seule fois : le rejeu rend la même facture, sans doublon.
      expect(await dao.convertirEnFacture(p.id), factureId);
      expect(await FactureDao(db).pieces(), hasLength(1));
    },
  );

  test('un brouillon ne se convertit pas', () async {
    final p = await dao.creer(clientNom: 'A', lignes: lignes);
    expect(() => dao.convertirEnFacture(p.id), throwsA(isA<RefusProforma>()));
  });

  test(
    'l\'accusé remplace le provisoire ; jamais deux numéros définitifs identiques',
    () async {
      final a = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
      final b = await dao.creer(clientNom: 'B', lignes: lignes, emettre: true);

      await dao.regulariserNumero(a.id, 'N°0001 FP-GCN/2026');
      expect((await dao.parId(a.id))!.numero, 'N°0001 FP-GCN/2026');
      await dao.regulariserNumero(a.id, 'N°0001 FP-GCN/2026'); // idempotent
      // Un provisoire n'est jamais posé comme définitif.
      await dao.regulariserNumero(b.id, 'PROV-FP-2026-00099');
      expect((await dao.parId(b.id))!.numero, 'PROV-FP-2026-00002');
      // Le même définitif sur une AUTRE proforma : refusé, rien n'est écrit.
      expect(
        () => dao.regulariserNumero(b.id, 'N°0001 FP-GCN/2026'),
        throwsStateError,
      );
      expect((await dao.parId(b.id))!.numero, 'PROV-FP-2026-00002');
    },
  );

  test('atomicité : une file en panne défait la proforma', () async {
    await db.customStatement(
      'CREATE TRIGGER panne BEFORE INSERT ON operations_sync_local '
      "BEGIN SELECT RAISE(ABORT, 'file en panne'); END",
    );
    await expectLater(
      dao.creer(clientNom: 'A', lignes: lignes),
      throwsA(anything),
    );
    expect(await dao.liste(), isEmpty);
    expect(await db.select(db.lignesProformaLocal).get(), isEmpty);
  });

  test('les refus de saisie', () async {
    expect(
      () => dao.creer(clientNom: ' ', lignes: lignes),
      throwsA(isA<RefusProforma>()),
    );
    expect(
      () => dao.creer(clientNom: 'A', lignes: const []),
      throwsA(isA<RefusProforma>()),
    );
    expect(
      () => dao.creer(clientNom: 'A', clientIfu: '123', lignes: lignes),
      throwsA(isA<RefusProforma>()),
    );
    expect(
      () => dao.creer(
        clientNom: 'A',
        lignes: const [(designation: 'X', quantite: 0, prixUnitaire: 100)],
      ),
      throwsA(isA<RefusProforma>()),
    );
    expect(await dao.liste(), isEmpty);
  });

  test('les réglages : défauts et lecture', () {
    const d = ReglagesDocuments.parDefaut;
    expect(d.referenceFacture, 'GCN');
    expect(d.validiteAffichee, isFalse);
    expect(d.validiteJours, 30);
    expect(d.signatureAffichee, isFalse);
    expect(blocSignature(d), isNull);

    final r = ReglagesDocuments.depuis({
      ClesReglagesDocuments.signatureAffichee: 'true',
      ClesReglagesDocuments.signataireNom: 'NABOGOU Winribassé Noël',
      ClesReglagesDocuments.signataireFonction: 'Directeur Général',
      ClesReglagesDocuments.validiteJours: '0',
    });
    expect(blocSignature(r), (
      nom: 'NABOGOU Winribassé Noël',
      fonction: 'Directeur Général',
    ));
    expect(r.validiteJours, 30); // 0 n'est pas une durée
  });
}
