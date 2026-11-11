import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration -> v57 (09/11/2026 : la VALEUR D'ACHAT DE RÉFÉRENCE d'un article,
/// colonnes « Valeur d'achat » des modèles d'import) : UNE colonne nullable,
/// `articles_local.prix_achat_reference`, aucune table, aucune valeur fabriquée
/// (`null` = « — »). Le curseur de descente est oublié. Éprouvée sur un FICHIER
/// RÉEL portant des données, y compris en sautant des versions (piège 2).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v57_');
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

  for (final depart in const [56, 54, 49, 44]) {
    test('v$depart -> v57 : la colonne est ajoutée vide, les articles et '
        'leurs mouvements restent, le curseur est oublié', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      expect(
        await lignes(
          avant,
          "SELECT name FROM pragma_table_info('articles_local') "
          "WHERE name = 'prix_achat_reference'",
        ),
        isEmpty,
        reason: 'la fixture v$depart n’a pas la colonne',
      );
      await avant.customStatement(
        "INSERT INTO points_stockage_local (id, libelle) VALUES ('p-1', 'Bar')",
      );
      await avant.customStatement(
        "INSERT INTO articles_local (id, libelle, categorie, unite_mesure, "
        "seuil_alerte, suivi, point_stockage_id) "
        "VALUES ('a-1', 'Café double', '', 'tasse', 5, 'permanent', 'p-1')",
      );
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'c42', 0), ('autre.cle', 'garde', 0)",
      );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(apres.schemaVersion, greaterThanOrEqualTo(57));

      final colonne = await lignes(
        apres,
        "SELECT name FROM pragma_table_info('articles_local') "
        "WHERE name = 'prix_achat_reference'",
      );
      expect(colonne, hasLength(1));
      final article = (await lignes(
        apres,
        "SELECT libelle, seuil_alerte, prix_achat_reference "
        "FROM articles_local WHERE id = 'a-1'",
      )).single;
      expect(article['libelle'], 'Café double');
      expect(article['seuil_alerte'], 5);
      expect(
        article['prix_achat_reference'],
        isNull,
        reason: 'aucune valeur n’est fabriquée : « — »',
      );
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
