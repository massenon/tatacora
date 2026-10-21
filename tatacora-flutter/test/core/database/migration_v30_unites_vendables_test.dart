import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

import 'retour_arriere_schema.dart';

/// Migration v29 -> v30 : UNE colonne nullable ajoutée à
/// `cartes_boisson_local` (`unites_vendables`, le facteur de conversion du
/// stock — 21/10/2026), éprouvée sur un FICHIER RÉEL portant des données
/// (piège 2), y compris par un poste qui a sauté des livraisons.
///
/// Rien n'est fabriqué : les boissons d'avant gardent `NULL` (un 1 par défaut
/// serait faux pour un casier de 24), et le curseur de descente est OUBLIÉ pour
/// que le catalogue redescende une fois.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v30_');
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
        in await db
            .customSelect('PRAGMA table_info(cartes_boisson_local)')
            .get())
      l.data['name'] as String,
  };

  for (final depart in const [29, 26, 10]) {
    test('v$depart -> courante : la colonne apparaît NULLE, les boissons et la '
        'file d’avant sont intactes, le curseur est oublié', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, depart);
      expect(await colonnes(avant), isNot(contains('unites_vendables')));
      await avant.customStatement(
        'INSERT INTO cartes_boisson_local (id, article_id, libelle, categorie, '
        "prix_vente) VALUES ('b-1', '', 'Flag', 'locale', 600)",
      );
      if (depart >= 27) {
        await avant.customStatement(
          'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
          "VALUES ('descente.curseur', 'abc', 0)",
        );
      }
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(apres.schemaVersion, greaterThanOrEqualTo(30));
      expect(await colonnes(apres), contains('unites_vendables'));
      final b = await apres
          .customSelect(
            'SELECT libelle, prix_vente, unites_vendables '
            'FROM cartes_boisson_local',
          )
          .getSingle();
      expect(b.data['libelle'], 'Flag');
      expect(b.data['prix_vente'], 600);
      expect(b.data['unites_vendables'], isNull);
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
