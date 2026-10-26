import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v35 -> v36 : DEUX colonnes nullables ajoutées à `plats_local`
/// (`article_id`, `unites_vendables` — le lien direct plat -> article de stock,
/// 21/10/2026), éprouvées sur un FICHIER RÉEL portant des données (piège 2), y
/// compris par un poste qui a sauté des livraisons.
///
/// Rien n'est fabriqué : les plats d'avant n'ont AUCUN lien (`NULL`), un 1 par
/// défaut serait faux pour un casier de 24 ; le curseur de descente est OUBLIÉ
/// pour que le catalogue redescende une fois.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v36_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> colonnes(AppDatabase db) async => {
    for (final l
        in await db.customSelect('PRAGMA table_info(plats_local)').get())
      l.data['name'] as String,
  };

  for (final depart in const [35, 30, 14]) {
    test('v$depart -> courante : les colonnes apparaissent NULLES, le plat et '
        'la file d’avant sont intacts, le curseur est oublié', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      expect(await colonnes(avant), isNot(contains('article_id')));
      expect(await colonnes(avant), isNot(contains('unites_vendables')));
      // Les clés étrangères ne sont pas l'objet de ce cas.
      await avant.customStatement('PRAGMA foreign_keys = OFF');
      await avant.customStatement(
        'INSERT INTO plats_local (id, menu_id, recette_id, libelle, '
        'prix_vente, cree_le, cree_par) '
        "VALUES ('p-1', 'm-1', 'r-1', 'Poulet DG', 4500, 0, 'u-1')",
      );
      if (depart >= 27) {
        await avant.customStatement(
          'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
          "VALUES ('descente.curseur', 'abc', 0)",
        );
      }
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(apres.schemaVersion, greaterThanOrEqualTo(36));
      expect(
        await colonnes(apres),
        containsAll(['article_id', 'unites_vendables']),
      );
      final p = await apres
          .customSelect(
            'SELECT libelle, prix_vente, article_id, unites_vendables '
            'FROM plats_local',
          )
          .getSingle();
      expect(p.data['libelle'], 'Poulet DG');
      expect(p.data['prix_vente'], 4500);
      expect(p.data['article_id'], isNull);
      expect(p.data['unites_vendables'], isNull);
      final curseur = await apres
          .customSelect(
            'SELECT COUNT(*) AS n FROM etat_synchronisation_local '
            "WHERE cle = 'descente.curseur'",
          )
          .getSingle();
      expect(curseur.data['n'], 0);
      await apres.close();
    });
  }
}
