@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/scenario_file.dart';

/// L'ANCRAGE EXTÉRIEUR de la facture proforma du poste (PO, 07/11/2026) : ce que le poste
/// écrit HORS LIGNE (création, émission, annulation, conversion en facture locale) est
/// poussé TEL QUEL au VRAI moteur du serveur (`tool/sync/valider_charge.php` ->
/// `SynchronisationService::traiterLot` -> `GestionnaireProformas` -> `ProformaService`),
/// sur la base d'essai, puis annulé. Le numéro continu `N°0001 FP-GCN/2026` revient du
/// serveur, et le poste le pose à la place du provisoire.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProformaDao dao;
  late String idA;
  late String idB;
  late String idAnnulee;
  late String idConvertie;
  late String idFacture;
  late Map<String, dynamic> sortie;
  late List<Map<String, Object?>> operations;

  const lignes = [
    (designation: 'Chambre double', quantite: 4, prixUnitaire: 25000),
    (designation: 'Petit déjeuner', quantite: 8, prixUnitaire: 2500),
  ];

  setUpAll(() async {
    db = AppDatabase.enMemoire();
    dao = ProformaDao(db, maintenant: () => DateTime(2026, 11, 7, 10));
    final reglages = ReglagesDocuments.depuis({
      ClesReglagesDocuments.validiteAffichee: 'true',
      ClesReglagesDocuments.validiteJours: '15',
    });

    idA = (await dao.creer(
      clientNom: 'SARL KORA',
      clientIfu: '0202011344660',
      objet: 'Atelier',
      lignes: lignes,
      emettre: true,
      reglages: reglages,
    )).id;
    // Un brouillon, modifié, puis émis plus tard : le numéro naît à l'émission.
    idB = (await dao.creer(clientNom: 'B', lignes: lignes)).id;
    await dao.modifier(
      idB,
      objet: 'Révisé',
      lignes: [(designation: 'Forfait', quantite: 1, prixUnitaire: 400000)],
    );
    await dao.emettre(idB);
    idAnnulee = (await dao.creer(
      clientNom: 'C',
      lignes: lignes,
      emettre: true,
    )).id;
    await dao.annuler(idAnnulee, 'Client désisté');
    idConvertie = (await dao.creer(
      clientNom: 'D',
      sourceModule: 'location',
      lignes: lignes,
      emettre: true,
    )).id;
    idFacture = await dao.convertirEnFacture(idConvertie);

    operations = await fileAuProtocole(db);
    sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-11-07',
        'poste_id': 'poste-essai-proforma',
        'operations': operations,
      },
    );
  });

  tearDownAll(() => db.close());

  List<Map<String, dynamic>> resultats() => [
    for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
  ];

  Map<String, dynamic> etat(String table, String id) =>
      (sortie['etats'] as Map<String, dynamic>)['$table:$id']
          as Map<String, dynamic>;

  test('toutes les opérations du poste sont acceptées par le serveur', () {
    expect(sortie['enveloppe'], isEmpty);
    expect(operations.length, greaterThan(8));
    for (var i = 0; i < resultats().length; i++) {
      expect(
        resultats()[i]['statut'],
        'synchronise',
        reason:
            '${operations[i]['table']} ${operations[i]['type']} : ${resultats()[i]}',
      );
    }
  });

  test(
    'le serveur attribue le numéro continu à l\'émission, et le poste le pose',
    () async {
      final numeros = <String, String>{};
      for (var i = 0; i < operations.length; i++) {
        final n = resultats()[i]['numero'];
        if (operations[i]['table'] == 'proformas' && n is String) {
          numeros[operations[i]['entite_id']! as String] = n;
        }
      }
      // Quatre proformas émises (A, B, C, D), dans l'ordre d'émission de la file.
      expect(numeros[idA], 'N°0001 FP-GCN/2026');
      expect(numeros[idB], 'N°0002 FP-GCN/2026');
      expect(numeros[idAnnulee], 'N°0003 FP-GCN/2026');
      expect(numeros[idConvertie], 'N°0004 FP-GCN/2026');
      expect(
        numeros.values.toSet(),
        hasLength(4),
        reason: 'jamais deux numéros identiques',
      );

      expect((await dao.parId(idA))!.numero, startsWith('PROV-FP-'));
      for (final e in numeros.entries) {
        await dao.regulariserNumero(e.key, e.value);
      }
      expect((await dao.parId(idA))!.numero, 'N°0001 FP-GCN/2026');
      expect((await dao.parId(idConvertie))!.numero, 'N°0004 FP-GCN/2026');
    },
  );

  test(
    'ce que le serveur a écrit : montants, validité décidée au poste, statuts',
    () {
      final a = etat('proformas', idA);
      expect(a['statut'], 'emise');
      expect(a['total'], 120000);
      expect(a['client_ifu'], '0202011344660');
      expect(a['date_emission'], startsWith('2026-11-07'));
      expect(a['valide_jusqu_au'], startsWith('2026-11-22'));

      final b = etat('proformas', idB);
      expect(b['objet'], 'Révisé');
      expect(b['total'], 400000);
      expect(b['valide_jusqu_au'], isNull);

      expect(etat('proformas', idAnnulee)['statut'], 'annulee');
      expect(
        etat('proformas', idAnnulee)['motif_annulation'],
        'Client désisté',
      );
    },
  );

  test(
    'la conversion faite au poste LIE la facture, sans seconde facture',
    () async {
      final d = etat('proformas', idConvertie);
      expect(d['statut'], 'convertie');
      expect(d['facture_id'], idFacture);

      final f = etat('factures', idFacture);
      expect(f['proforma_id'], idConvertie);
      expect(double.parse('${f['montant_ttc']}'), 120000);
      expect(f['numero_mecef'], isNull);
      expect(f['qr_code_fiscal'], isNull);
      final factures = operations.where(
        (o) => o['table'] == 'factures' && o['type'] == 'creation',
      );
      expect(factures, hasLength(1));
      expect(await FactureDao(db).pieces(), hasLength(1));
    },
  );
}
