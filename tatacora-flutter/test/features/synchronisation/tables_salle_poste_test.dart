import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/espace_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/unicite_panier_ouvert.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../pos/support/outils_ventes.dart' show panierDaoSur;
import 'support/faux_transport.dart';

/// L'arbitrage des tables entre postes, côté poste — lot F6, décision du PO
/// du 18/10/2026 (« il faut le créer »). La table et l'ouverture de son
/// addition partent ; le plan du serveur descend (sans doublon) ; une table
/// prise sur un autre poste est montrée prise ici et ne s'ouvre pas.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

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

  Future<String> tableR1() async => (await TablesPosDao(
    b.db,
  ).toutes()).firstWhere((t) => t.libelle == 'R1').id;

  Future<List<(String, TypeOperationSync, Map<String, Object?>)>>
  file() async => [
    for (final o in await b.dao.operations())
      if (o.table == TableSynchronisee.tablesSalle ||
          o.table == TableSynchronisee.paniers)
        (
          o.table.nomServeur,
          o.type,
          jsonDecode(o.payload) as Map<String, Object?>,
        ),
  ];

  test('ouvrir une table : la table (jeu initial) puis l’ouverture partent ; '
      'l’abandon la libère', () async {
    final r1 = await tableR1();
    final paniers = panierDaoSur(b.db);
    final p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Restaurant',
      tableId: r1,
      espace: 'restaurant',
    );
    await paniers.annuler(p.id, 'Client parti');

    expect(
      [
        for (final (t, type, c) in await file())
          '$t ${type.code} ${jsonEncode(c)}',
      ],
      [
        'tables_salle creation {"espace":"restaurant","numero":1,"places":4}',
        'paniers creation {"point_vente":"Restaurant","table_id":"$r1"}',
        'paniers modification {"statut":"cloture"}',
      ],
    );
  });

  test('le plan du serveur descend sans doublon : même espace, même numéro '
      '= la même table', () async {
    final r1 = await tableR1();
    final avant = (await TablesPosDao(b.db).toutes()).length;

    final bilan = await descendre([
      element('tables_salle', 'srv-r1', {
        'espace': 'restaurant',
        'numero': 1,
        'libelle': 'R1',
        'places': 6,
      }),
      element('tables_salle', 'srv-j9', {
        'espace': 'jardin',
        'numero': 9,
        'libelle': 'J9',
        'places': 4,
      }),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final tables = await TablesPosDao(b.db).toutes();
    expect(tables.length, avant + 1);
    expect(tables.firstWhere((t) => t.id == r1).places, 6);
    expect(tables.any((t) => t.id == 'srv-j9'), isTrue);
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });

  test('une table ouverte sur un AUTRE poste : prise ici, refusée ; libérée '
      'là-bas, libre ici', () async {
    final r1 = await tableR1();
    Map<String, Object?> occupation(String statut) => {
      ...element('paniers', 'p-autre', {
        'point_vente': 'Restaurant',
        'table_id': 'srv-r1',
        'statut': statut,
        'cloture_at': null,
      }),
      'poste_origine': 'POSTE-B',
    };
    final plan = element('tables_salle', 'srv-r1', {
      'espace': 'restaurant',
      'numero': 1,
      'libelle': 'R1',
      'places': 4,
    });

    await descendre([plan, occupation('ouvert')]);
    Future<bool> prise() async => (await TablesPosDao(b.db).salle())
        .expand((r) => r.cases)
        .firstWhere((c) => c.table.id == r1)
        .occupeeAilleurs;
    expect(await prise(), isTrue);
    await expectLater(
      panierDaoSur(b.db).ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Restaurant',
        tableId: r1,
        espace: EspacePos.restaurant.code,
      ),
      throwsA(isA<TableOccupeeAilleurs>()),
    );

    await descendre([plan, occupation('cloture')]);
    expect(await prise(), isFalse);
  });
}
