import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';

import 'support/faux_transport.dart';

/// 07/11/2026 : les proformas des AUTRES postes et de la PWA descendent avec leurs lignes, sous
/// le numéro du serveur ; une saisie locale en suspens n'est jamais écrasée ; jamais deux
/// numéros définitifs identiques.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Map<String, Object?> proforma(
    String id, {
    String numero = 'N°0007 FP-GCN/2026',
    String statut = 'emise',
    String? factureId,
  }) => {
    ...element('proformas', id, {
      'numero': numero,
      'annee': 2026,
      'rang': 7,
      'reference': 'GCN',
      'statut': statut,
      'client_id': null,
      'client_nom': 'SARL KORA',
      'client_telephone': '0190123456',
      'client_ifu': null,
      'objet': 'Atelier',
      'date_emission': '2026-11-02',
      'ville': 'Natitingou',
      'valide_jusqu_au': '2026-12-02',
      'total': 100000,
      'facture_id': factureId,
      'motif_annulation': null,
      'source_module': 'libre',
      'lignes': [
        {
          'position': '0',
          'designation': 'Salle',
          'quantite': '2',
          'prix_unitaire': '50000',
          'montant': '100000',
        },
      ],
    }),
    'poste_origine': 'POSTE-A',
  };

  Future<void> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    await b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test(
    'une proforma d\'un autre poste descend avec ses lignes, sous le numéro du serveur',
    () async {
      await descendre([proforma('p-1')]);

      final dao = ProformaDao(b.db);
      final p = (await dao.parId('p-1'))!;
      expect(p.numero, 'N°0007 FP-GCN/2026');
      expect(p.statut, 'emise');
      expect(p.total, 100000);
      expect(p.valideJusquAu, DateTime(2026, 12, 2));
      expect(p.ville, 'Natitingou');
      final lignes = await dao.lignes('p-1');
      expect(lignes.single.designation, 'Salle');
      expect(lignes.single.montant, 100000);
      // Reçue du serveur : rien à renvoyer.
      expect(
        await b.db
            .customSelect('SELECT COUNT(*) AS n FROM operations_sync_local')
            .getSingle()
            .then((r) => r.data['n']),
        0,
      );
    },
  );

  test(
    'un nouvel état du serveur (convertie) est adopté ; les lignes ne se doublent pas',
    () async {
      await descendre([proforma('p-1')]);
      await descendre([proforma('p-1', statut: 'convertie', factureId: 'f-9')]);

      final dao = ProformaDao(b.db);
      final p = (await dao.parId('p-1'))!;
      expect(p.statut, 'convertie');
      expect(p.factureId, 'f-9');
      expect(await dao.lignes('p-1'), hasLength(1));
    },
  );

  test('une saisie locale en suspens n\'est jamais écrasée', () async {
    final dao = ProformaDao(b.db);
    final locale = await dao.creer(
      clientNom: 'LOCALE',
      lignes: const [(designation: 'X', quantite: 1, prixUnitaire: 10)],
      id: 'p-2',
    );
    await descendre([proforma(locale.id, numero: 'N°0008 FP-GCN/2026')]);

    final relue = (await dao.parId('p-2'))!;
    expect(relue.clientNom, 'LOCALE');
    expect(relue.numero, isNull);
  });

  test(
    'jamais deux numéros définitifs identiques : le second est refusé',
    () async {
      await descendre([proforma('p-1')]);
      await descendre([proforma('p-3')]);

      final dao = ProformaDao(b.db);
      expect(await dao.parId('p-3'), isNull);
      expect((await dao.parId('p-1'))!.numero, 'N°0007 FP-GCN/2026');
    },
  );

  test(
    'l\'accusé remplace le numéro provisoire par celui du serveur (émission = modification)',
    () async {
      final dao = ProformaDao(b.db);
      final p = await dao.creer(
        clientNom: 'A',
        lignes: const [(designation: 'X', quantite: 1, prixUnitaire: 10)],
        emettre: true,
      );
      expect(p.numero, startsWith('PROV-FP-'));

      final t = FauxTransport(
        (r) => reponseLot(
          r,
          particulier: (o) =>
              o['table'] == 'proformas' && o['type'] == 'modification'
              ? {
                  'uuid_operation': o['uuid_operation'],
                  'statut': 'synchronise',
                  'entite_id': o['entite_id'],
                  'numero': 'N°0001 FP-GCN/2026',
                }
              : null,
        ),
      );
      await b.manager(t).synchroniserMaintenant();

      expect((await dao.parId(p.id))!.numero, 'N°0001 FP-GCN/2026');
    },
  );
}
