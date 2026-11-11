@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/archivage_clients.dart';
import 'package:tatacora_flutter/features/crm/data/relances_clients_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../facturation/support/outils_encaissement.dart';
import 'support/scenario_file.dart';

/// L'ANCRAGE EXTÉRIEUR des relances, de l'archivage d'un client et de l'avoir
/// partiel (21/10/2026, piège 12) : les opérations écrites par les VRAIS
/// écrivains du poste sont poussées TELLES QUELLES au vrai
/// `SynchronisationService` du serveur (`tool/sync/valider_charge.php`, règles de
/// l'API, services de domaine, base `tatacora_test` annulée à la fin).
///
/// Ce que le serveur a ÉCRIT est relu : une relance dont le montant serait parti
/// en centimes, un archivage qui n'écrirait pas `actif`, un avoir partiel qui
/// annulerait la facture — tout cela se lit dans `etats`, pas dans le statut.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<Map<String, Object?>> operations;
  late List<Map<String, dynamic>> resultats;
  late Map<String, dynamic> etats;

  late String clientDebiteur;
  late String clientLibre;
  late String facture;
  late String avoirPartiel;
  late String relanceId;
  late String factureLibre;

  setUpAll(() async {
    db = await baseEncaissement();
    final c = await creerClient(db, nom: 'KORA');
    final l = await creerClient(db, nom: 'LIBRE', telephone: '96000000');
    clientDebiteur = c.id;
    clientLibre = l.id;

    // Une facture de 10 000 F au nom du débiteur.
    final f = await emettreFacture(db, montant: 10000, clientId: c.id);
    facture = f.id;

    final relance =
        await RelancesClientsDao(
          db,
          maintenant: () => jourEncaissement,
        ).enregistrer(
          clientId: c.id,
          canal: 'whatsapp',
          montantReclameCentimes:
              1000050, // 10 000,50 F : la chaîne décimale exacte
          promesse: DateTime(2026, 10, 30),
          commentaire: 'Rappelle vendredi',
          auteurLogin: 'amina',
        );
    relanceId = relance.id;

    avoirPartiel = (await FactureDao(
      db,
      maintenant: () => jourEncaissement,
    ).emettreAvoirPartiel(facture, 3000, 'Bière tiède')).id;

    // Le client libre est archivé par le geste du poste.
    await ArchivageClients(
      db,
      maintenant: () => jourEncaissement,
      creances: () async => const [],
    ).archiverUn(l.id);

    // Une facture du client libre, puis un avoir qui DÉPASSE le TTC : le poste
    // ne l'écrirait jamais ; on l'enfile à la main pour entendre le serveur.
    final f2 = await emettreFacture(db, montant: 2000, clientId: l.id);
    factureLibre = f2.id;
    await db.transaction(
      () => OperationsSyncDao(db).enfiler(
        table: TableSynchronisee.factures,
        entiteId: factureLibre,
        type: TypeOperationSync.modification,
        payload: const {'montant': 2001, 'motif': 'Trop', 'avoir_id': null},
      ),
    );

    operations = await fileAuProtocole(db);
    await db.close();

    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-12',
        'poste_id': 'poste-essai-relances',
        'operations': operations,
      },
    );
    expect(sortie['enveloppe'], isEmpty);
    resultats = [
      for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
    ];
    etats = sortie['etats'] as Map<String, dynamic>;
  });

  Map<String, dynamic> resultatDe(String table, String type, String id) {
    final rang = operations.indexWhere(
      (o) => o['table'] == table && o['type'] == type && o['entite_id'] == id,
    );
    expect(rang, isNot(-1), reason: 'aucune opération $type $table $id');
    return resultats[rang];
  }

  test('la file a produit les gestes dans l’ordre des écritures', () {
    expect(operations.map((o) => '${o['type']} ${o['table']}').toList(), [
      'creation clients',
      'creation clients',
      'creation factures',
      'creation relances_clients',
      'modification factures',
      'modification clients',
      'creation factures',
      'modification factures',
    ]);
  });

  test('la relance est écrite par le service : montant EXACT, canal, promesse, '
      'commentaire', () {
    final r = resultatDe('relances_clients', 'creation', relanceId);
    expect(r['statut'], 'synchronise', reason: '${r['motif']}');
    final ligne = etats['relances_clients:$relanceId'] as Map<String, dynamic>;
    expect(ligne['client_id'], clientDebiteur);
    expect(ligne['canal'], 'whatsapp');
    // 1 000 050 centimes -> « 10000.50 » : jamais un double, jamais x100.
    expect(ligne['montant_reclame'], '10000.50');
    expect(ligne['date_relance'], startsWith('2026-10-12'));
    expect(ligne['promesse'], startsWith('2026-10-30'));
    expect(ligne['commentaire'], 'Rappelle vendredi');
  });

  test('l’archivage du client libre pose actif=0 au serveur', () {
    final r = resultatDe('clients', 'modification', clientLibre);
    expect(r['statut'], 'synchronise', reason: '${r['motif']}');
    final ligne = etats['clients:$clientLibre'] as Map<String, dynamic>;
    expect(ligne['actif'], 0);
    // Le débiteur, lui, reste actif.
    expect((etats['clients:$clientDebiteur'] as Map)['actif'], 1);
  });

  test('l’avoir PARTIEL naît sous l’identifiant du poste, rend son numéro, et '
      'n’annule pas la facture', () {
    final r = resultatDe('factures', 'modification', facture);
    expect(r['statut'], 'synchronise', reason: '${r['motif']}');
    expect(r['avoir_id'], avoirPartiel);
    expect(r['numero_avoir'], matches(RegExp(r'^AV-2026-\d{5}$')));
    final f = etats['factures:$facture'] as Map<String, dynamic>;
    expect(f['montant_ttc'], '10000.00');
    expect(f['statut'], isNot('annulee'));
  });

  test('un avoir au-delà du TTC est REJETÉ avec la phrase du service, que le '
      'poste dit à l’identique', () {
    final r = resultatDe('factures', 'modification', factureLibre);
    expect(r['statut'], 'rejete');
    expect(r['motif'], const AvoirExcessif().toString());
  });
}
