import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/controle_coherence.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';

import 'support/faux_transport.dart';
import 'support/scenario_file.dart';

/// Le contrôle de cohérence (P1-1) : les comptes du serveur, par table et
/// par jour, contre ceux du poste — sur la journée complète du scénario
/// (ventes, dépenses, factures, encaissements, réservations, règlement,
/// mouvements).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late BancSync b;
  late AppDatabase db;

  setUp(() async {
    b = await BancSync.creer();
    db = AppDatabase.enMemoire();
    await jouerJourneeComplete(db);
  });
  tearDown(() async {
    await db.close();
    await b.fermer();
  });

  ControleCoherence controle(Map<String, Object?> tables) => ControleCoherence(
    db: db,
    transport: FauxTransport(
      (r) => ReponseHttp(
        statut: 200,
        corps: {
          'data': {'tables': tables},
        },
      ),
    ),
    urlServeur: BancSync.urlServeur,
    lecteur: b.lecteur,
  );

  Future<CoherenceMesuree> mesurer(Map<String, Object?> tables) async =>
      await controle(
            tables,
          ).controler(aujourdHui: DateTime(2026, 10, 22), jours: 14)
          as CoherenceMesuree;

  test(
    'un serveur VIDE : chaque document du poste est un écart, daté',
    () async {
      final m = await mesurer({
        for (final t in ControleCoherence.requetes.keys) t: <String, Object?>{},
      });

      expect(m.tables, ControleCoherence.requetes.keys.toList());
      final tablesEnEcart = {for (final e in m.ecarts) e.table};
      expect(
        tablesEnEcart,
        containsAll(['ventes', 'depenses', 'factures', 'paiements']),
      );
      final vente = m.ecarts.firstWhere((e) => e.table == 'ventes');
      expect(vente.serveur, (nombre: 0, total: 0));
      expect(vente.poste.nombre, greaterThan(0));
      expect(m.toutRecuJusquAu, isNot(m.au));
    },
  );

  test('le serveur rend les mêmes comptes : aucun écart, tout reçu ; une '
      'table non lue par le compte n’est pas comparée', () async {
    final vide = await mesurer({
      for (final t in ControleCoherence.requetes.keys) t: <String, Object?>{},
    });
    final miroir = <String, Map<String, Object?>>{
      for (final t in ControleCoherence.requetes.keys) t: {},
    };
    for (final e in vide.ecarts) {
      miroir[e.table]![e.jour] = {
        'nombre': e.poste.nombre,
        'total': e.poste.total,
      };
    }
    miroir.remove('mouvements_stock');

    final m = await mesurer(miroir);
    expect(m.ecarts, isEmpty);
    expect(m.toutRecuJusquAu, '2026-10-22');
    expect(m.tables, isNot(contains('mouvements_stock')));
  });

  test('serveur muet : la raison est dite', () async {
    final c = ControleCoherence(
      db: db,
      transport: FauxTransport((_) => const ServeurInjoignable('coupé')),
      urlServeur: BancSync.urlServeur,
      lecteur: b.lecteur,
    );
    final issue = await c.controler(aujourdHui: DateTime(2026, 10, 22));
    expect(issue, isA<CoherenceIndisponible>());
  });
}
