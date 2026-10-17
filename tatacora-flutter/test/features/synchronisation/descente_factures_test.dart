import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/paiements_facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// Lots F5c et F5d (décisions du PO du 17/10/2026) : les factures, avoirs et
/// encaissements des AUTRES postes descendent au registre de ce poste, sous
/// le numéro du serveur et sans pièce (Q1) ; ceux de CE poste reviennent et
/// lui apportent le numéro du serveur (Q2 : « les postes s'actualisent du
/// numéro que le serveur a attribué »).
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<int> compte(String table) async =>
      (await b.db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Map<String, Object?> doc(String table, String id, Map<String, Object?> d) => {
    ...element(table, id, d),
    'poste_origine': 'POSTE-A',
  };

  Map<String, Object?> facture(
    String id, {
    String? numero = 'F-2026-00003',
    String clientId = 'cl-1',
  }) => doc('factures', id, {
    'numero': numero,
    'origine': 'facture_directe',
    'client_id': clientId,
    'date_emission': '2026-10-15',
    'montant_ht': '25423.73',
    'montant_tva': '4576.27',
    'montant_ttc': '30000.00',
    'statut': 'en_attente_certification',
    'lignes': [
      {
        'source_module': 'M8',
        'source_id': id,
        'libelle': 'Location 4x4',
        'quantite': '1.00',
        'prix_unitaire': '25423.73',
        'prix_catalogue': '30000.00',
        'montant': '25423.73',
      },
    ],
  });

  final decor = [
    element('clients', 'cl-1', {
      'nom': 'Sabi',
      'telephone': '96000003',
      'type_client': 'groupe',
    }),
    doc('sessions_caisse', 'sess-1', {
      'point_vente': 'bar',
      'date_ouverture': '2026-10-15 07:00:00',
      'montant_fond': '10000.00',
      'date_cloture': null,
      'montant_theorique': null,
      'montant_constate': null,
    }),
  ];

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test('la facture, l’avoir partiel et l’encaissement d’un autre poste : '
      'au registre, au prix vendu, comptés au reste dû, SANS pièce', () async {
    final bilan = await descendre([
      ...decor,
      facture('f-1'),
      doc('avoirs', 'av-1', {
        'facture_id': 'f-1',
        'numero': 'AV-2026-00001',
        'motif': 'Geste commercial',
        'montant': '5000.00',
        'date_emission': '2026-10-15',
      }),
      doc('paiements', 'pay-1', {
        'facture_id': 'f-1',
        'session_id': 'sess-1',
        'mode_paiement': 'especes',
        'montant': '10000.00',
        'date_paiement': '2026-10-15 09:15:00',
        'statut': 'actif',
        'motif_annulation': null,
        'date_annulation': null,
      }),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
    expect(bilan.enAttenteDeDependance, 0);

    final f = (await FactureDao(b.db).parId('f-1'))!;
    expect(f.numero, 'F-2026-00003');
    expect(f.clientNom, 'Sabi');
    expect(f.montantTotal, 30000, reason: 'le PRIX VENDU, jamais le HT');
    expect(f.estEmise, isTrue, reason: 'un avoir partiel n’annule pas');

    final avoir = (await FactureDao(b.db).avoirsDe('F-2026-00003')).single;
    expect(avoir.numero, 'AV-2026-00001');
    expect(avoir.montantTotal, -5000);

    final creance = await PaiementsFactureDao(b.db).creanceDe(f);
    expect(creance.resteDuCentimes, 1500000, reason: '30 000 − 5 000 − 10 000');

    expect(await compte('ecritures_local'), 0, reason: 'Q1 : aucune pièce');
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });

  test('un avoir du TTC entier annule la facture ; un encaissement annulé '
      'au serveur suit, jamais à rebours', () async {
    final paiement = doc('paiements', 'pay-1', {
      'facture_id': 'f-1',
      'session_id': 'sess-1',
      'mode_paiement': 'especes',
      'montant': '10000.00',
      'date_paiement': '2026-10-15 09:15:00',
      'statut': 'actif',
      'motif_annulation': null,
      'date_annulation': null,
    });
    await descendre([...decor, facture('f-1'), paiement]);
    await descendre([
      doc('avoirs', 'av-1', {
        'facture_id': 'f-1',
        'numero': 'AV-2026-00001',
        'motif': 'Erreur',
        'montant': '30000.00',
        'date_emission': '2026-10-15',
      }),
      {
        ...paiement,
        'donnees': {
          ...paiement['donnees']! as Map<String, Object?>,
          'statut': 'annule',
          'motif_annulation': 'Doublon',
          'date_annulation': '2026-10-15 11:00:00',
        },
      },
    ]);

    expect((await FactureDao(b.db).parId('f-1'))!.estAnnulee, isTrue);
    final p = (await PaiementsFactureDao(b.db).parId('pay-1'))!;
    expect(p.statut, StatutPaiementFacture.annule);
  });

  test('sans son client, la facture ATTEND ; une ancienne facture avec TVA '
      'et sans prix vendu est refusée, jamais recalculée', () async {
    final attente = await descendre([facture('f-1', clientId: 'cl-x')]);
    expect(attente.enAttenteDeDependance, 1);

    final ancienne = facture('f-2', numero: null);
    final lignes =
        ((ancienne['donnees']! as Map<String, Object?>)['lignes']! as List)
            .cast<Map<String, Object?>>();
    final bilan = await descendre([
      ...decor,
      {
        ...ancienne,
        'donnees': {
          ...ancienne['donnees']! as Map<String, Object?>,
          'lignes': [
            {...lignes.single, 'prix_catalogue': null},
          ],
        },
      },
    ]);
    expect(bilan.refuses, 1);
    expect(await FactureDao(b.db).parId('f-2'), isNull);
  });

  test('la facture de CE poste revient : le numéro du serveur remplace le '
      'provisoire ; son avoir provisoire reçoit le sien', () async {
    await descendre(decor);
    final dao = FactureDao(b.db);
    final f = await dao.emettre(
      const BrouillonFacture(
        origine: OrigineFacture.factureDirecte,
        clientNom: 'Sabi',
        clientId: 'cl-1',
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m8Vehicules,
            libelle: 'Location 4x4',
            prixUnitaire: 30000,
            quantite: 1,
          ),
        ],
      ),
    );
    await dao.annuler(f.id, 'Erreur');
    expect(f.estProvisoire, isTrue);
    // Le poste a envoyé ; les réponses ont été perdues.
    await (b.db.update(b.db.operationsSyncLocal)).write(
      OperationsSyncLocalCompanion(
        statut: Value(StatutOperationSync.synchronise.code),
      ),
    );

    final bilan = await descendre([
      facture(f.id, numero: 'F-2026-00009'),
      doc('avoirs', 'av-serveur', {
        'facture_id': f.id,
        'numero': 'AV-2026-00004',
        'motif': 'Erreur',
        'montant': '30000.00',
        'date_emission': '2026-10-15',
      }),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    expect((await dao.parId(f.id))!.numero, 'F-2026-00009');
    final avoirs = await dao.avoirsDe('F-2026-00009');
    expect(avoirs.single.numero, 'AV-2026-00004');
    expect(await dao.parId('av-serveur'), isNull, reason: 'jamais doublé');
  });

  test('la réponse de l’envoi régularise aussitôt le numéro', () async {
    await descendre(decor);
    final dao = FactureDao(b.db);
    final f = await dao.emettre(
      const BrouillonFacture(
        origine: OrigineFacture.factureDirecte,
        clientNom: 'Sabi',
        clientId: 'cl-1',
        lignes: [
          LigneBrouillon(
            module: ModuleFacturable.m8Vehicules,
            libelle: 'Location 4x4',
            prixUnitaire: 30000,
            quantite: 1,
          ),
        ],
      ),
    );
    final t = FauxTransport(
      (r) => reponseLot(
        r,
        particulier: (o) => o['entite_id'] == f.id
            ? {
                'uuid_operation': o['uuid_operation'],
                'statut': 'synchronise',
                'entite_id': f.id,
                'numero': 'F-2026-00011',
                'montant_ttc': '30000.00',
              }
            : null,
      ),
    );
    await b.manager(t).synchroniserMaintenant();

    expect((await dao.parId(f.id))!.numero, 'F-2026-00011');
  });
}
