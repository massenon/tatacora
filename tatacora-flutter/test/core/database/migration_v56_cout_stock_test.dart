import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration -> v56 (09/11/2026 : le COÛT des entrées de stock descend du serveur) :
/// AUCUNE table, AUCUNE colonne — le curseur de descente est OUBLIÉ, pour que les
/// mouvements déjà passés par un curseur redescendent une fois avec leur coût.
/// Les données du poste (mouvements, file d'envoi) restent intactes. Éprouvée sur un
/// FICHIER RÉEL portant des données, y compris en sautant des versions (piège 2).
/// (v55 est réservée à un autre chantier.)
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v56_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<int> compte(AppDatabase db, String sql) async =>
      (await db.customSelect(sql).getSingle()).data['n']! as int;

  for (final depart in const [54, 53, 49, 44]) {
    test('v$depart -> v56 : le curseur est oublié, les mouvements et leur coût '
        'restent', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      await avant.customStatement(
        'INSERT INTO points_stockage_local (id, libelle) VALUES (\'p-1\', \'Bar\')',
      );
      await avant.customStatement(
        "INSERT INTO articles_local (id, libelle, categorie, unite_mesure, seuil_alerte, suivi, point_stockage_id) "
        "VALUES ('a-1', 'Café double', '', 'tasse', 5, 'permanent', 'p-1')",
      );
      await avant.customStatement(
        'INSERT INTO mouvements_stock_local (id, article_id, point_id, type_mouvement, '
        "quantite, motif, date_mouvement, statut_sync, cout_unitaire_dix_milliemes, ordre) "
        "VALUES ('m-1', 'a-1', 'p-1', 'entree', 15, 'Essai', 0, 'synchronise', 5000000, 1)",
      );
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'c42', 0), ('autre.cle', 'garde', 0)",
      );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(apres.schemaVersion, greaterThanOrEqualTo(56));

      expect(
        await compte(
          apres,
          "SELECT COUNT(*) AS n FROM etat_synchronisation_local WHERE cle = 'descente.curseur'",
        ),
        0,
        reason: 'le curseur est oublié : les mouvements redescendent',
      );
      expect(
        await compte(
          apres,
          "SELECT COUNT(*) AS n FROM etat_synchronisation_local WHERE cle = 'autre.cle'",
        ),
        1,
        reason: 'aucun autre état n’est touché',
      );
      expect(
        await compte(
          apres,
          'SELECT COUNT(*) AS n FROM mouvements_stock_local '
          'WHERE id = \'m-1\' AND cout_unitaire_dix_milliemes = 5000000',
        ),
        1,
        reason: 'le mouvement et son coût sont intacts',
      );
      await apres.close();
    });
  }
}
