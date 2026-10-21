import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/espace_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';

import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import '../pos/support/outils_ventes.dart';

/// « Rétablir le jeu initial » de Paramètres › Espaces & tables : les treize
/// tables du jeu initial, SANS suppression (`TableSalleService::
/// retablirJeuInitial`) — créer ce qui manque, réactiver et remettre à quatre
/// places, DÉSACTIVER ce qui est hors du jeu, tout refuser si un panier est
/// ouvert.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TablesPosDao tables;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db);
    tables = TablesPosDao(db);
    await ouvrirLaCaisseDuComptoir(db);
  });
  tearDown(() => db.close());

  Future<Map<String, ({int places, bool actif, String libelle})>>
  etat() async => {
    for (final t in await db.select(db.tablesLocal).get())
      '${t.espace}-${t.numero}': (
        places: t.places,
        actif: t.actif,
        libelle: t.libelle,
      ),
  };

  test('une table absente est créée, une présente réactivée et remise à '
      'quatre places, une table HORS du jeu désactivée — rien ne se '
      'supprime', () async {
    final toutes = await tables.toutes();
    final r2 = toutes.firstWhere((t) => t.libelle == 'R2');
    await tables.basculer(r2.id); // R2 désactivée
    final r1 = toutes.firstWhere((t) => t.libelle == 'R1');
    await (db.update(db.tablesLocal)..where((t) => t.id.equals(r1.id))).write(
      const TablesLocalCompanion(places: Value(9)),
    );
    final j4 = toutes.firstWhere((t) => t.libelle == 'J4');
    await db.customStatement('DELETE FROM tables_local WHERE id = ?', [j4.id]);
    await tables.creer(espace: EspacePos.plage, numero: 5, places: 2);

    await tables.retablirJeuInitial();

    final apres = await etat();
    expect(apres['restaurant-2']!.actif, isTrue, reason: 'réactivée');
    expect(apres['restaurant-1']!.places, 4, reason: 'remise à quatre places');
    expect(apres['jardin-4']!.actif, isTrue, reason: 'recréée');
    expect(apres['plage-5']!.actif, isFalse, reason: 'hors jeu : désactivée');
    expect(apres['plage-5']!.libelle, 'P5', reason: 'jamais supprimée');
    expect(apres.length, 14, reason: 'treize + la table hors jeu, conservée');
    expect(apres.values.where((t) => t.actif).length, 13);
  });

  test(
    'un panier OUVERT refuse l’opération ENTIÈRE, avant toute écriture',
    () async {
      final toutes = await tables.toutes();
      final r3 = toutes.firstWhere((t) => t.libelle == 'R3');
      final r2 = toutes.firstWhere((t) => t.libelle == 'R2');
      await tables.basculer(r2.id);
      await tables.creer(espace: EspacePos.plage, numero: 5);
      await panierDaoSur(db).ouvrir(
        typeVente: TypeVente.comptant,
        tableId: r3.id,
        espace: r3.espace.code,
      );
      final avant = await etat();

      await expectLater(
        tables.retablirJeuInitial(),
        throwsA(
          isA<JeuInitialRefuse>().having(
            (e) => e.toString(),
            'message',
            allOf(
              startsWith(
                'Impossible de rétablir le jeu initial : un panier est ',
              ),
              contains('ouvert sur R3'),
            ),
          ),
        ),
      );
      expect(await etat(), avant, reason: 'rien n’a bougé : ni R2, ni plage 5');
    },
  );
}
