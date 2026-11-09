import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration -> v58 (09/11/2026 : l'AUTEUR D'UNE ANNULATION REÇUE du serveur) : UNE colonne
/// nullable, `reservations_local.auteur_annulation_login`, aucune table, aucune valeur
/// fabriquée. Le curseur de descente est oublié (les annulations déjà au serveur redescendent
/// complètes). Éprouvée sur un FICHIER RÉEL portant des données, y compris en sautant des
/// versions (piège 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v58_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<List<Map<String, Object?>>> lignes(AppDatabase db, String sql) async =>
      [for (final r in await db.customSelect(sql).get()) r.data];

  const colonneSql =
      "SELECT name FROM pragma_table_info('reservations_local') "
      "WHERE name = 'auteur_annulation_login'";

  for (final depart in const [57, 54, 49, 44]) {
    test('v$depart -> v58 : la colonne est ajoutée vide, les réservations '
        'restent, le curseur est oublié', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      expect(
        await lignes(avant, colonneSql),
        isEmpty,
        reason: 'la fixture v$depart n’a pas la colonne',
      );
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'c42', 0), ('autre.cle', 'garde', 0)",
      );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(apres.schemaVersion, greaterThanOrEqualTo(58));
      expect(await lignes(apres, colonneSql), hasLength(1));
      expect(
        await lignes(
          apres,
          "SELECT cle FROM etat_synchronisation_local ORDER BY cle",
        ),
        [
          {'cle': 'autre.cle'},
        ],
        reason: 'le curseur est oublié, aucun autre état n’est touché',
      );
      await apres.close();
    });
  }
}
