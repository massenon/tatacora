import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';
import 'retour_arriere_schema.dart';

/// Migration v39 -> v40 : UNE table neuve (`clotures_exercices_local`, la
/// clôture annuelle SYSCOHADA du poste, 26/10/2026), éprouvée sur un FICHIER
/// RÉEL portant des données (piège 2), y compris par un poste qui a sauté des
/// livraisons — et sur un poste qui portait déjà des pièces et un exercice
/// clôturé (descendu du serveur).
///
/// Additive : les écritures, les exercices et la file traversent intacts, la
/// table apparaît VIDE (aucune clôture n'est fabriquée pour un exercice déjà
/// clôturé), les clés étrangères tiennent, les gardes RG-11 survivent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v40_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> tables(AppDatabase db) async => {
    for (final l
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
      l.data['name'] as String,
  };

  Future<int> compte(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  Future<List<String>> colonnes(AppDatabase db, String table) async => [
    for (final c in await db.customSelect('PRAGMA table_info($table)').get())
      c.data['name'] as String,
  ];

  /// Un fichier ramené à [cible], avec un exercice CLÔTURÉ et une pièce — le
  /// poste qui travaillait déjà (le statut `cloture` descend du serveur).
  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    for (final t in tablesAjouteesEnV40) {
      expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$cible');
    }
    expect(await version(avant), cible);
    // Les exercices n'existent qu'à partir de la v15 : un poste de la v10 les
    // reçoit vides, et l'exercice clôturé n'a alors rien à porter.
    if (cible >= 15) {
      await avant.customStatement(
        'INSERT INTO exercices_local (id, annee, date_debut, date_fin, statut) '
        "VALUES ('x-2029', 2029, '2029-01-01', '2029-12-31', 'cloture')",
      );
    }
    await avant.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
    );
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [39, 38, 26, 10]) {
    test('v$depart -> courante : la table apparaît VIDE, les exercices et le '
        'parc sont INTACTS, aucune clôture n’est fabriquée', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(40));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV40]),
      );
      expect(await compte(apres, 'clotures_exercices_local'), 0);
      expect(await compte(apres, 'vehicules_local'), 1);
      // L'exercice clôturé d'avant est là, clôturé, SANS clôture locale : son
      // ouverture reste « inconnue », jamais zéro (on ne déduit pas de données).
      if (depart >= 15) {
        final e = await apres
            .customSelect(
              "SELECT statut FROM exercices_local WHERE id = 'x-2029'",
            )
            .getSingle();
        expect(e.data['statut'], 'cloture');
      }
      await apres.close();
    });
  }

  test('les colonnes de la table sont figées, et le résultat est en CENTIMES '
      'entiers', () async {
    final db = AppDatabase.surFichier(fichier);
    await db.customStatement('SELECT 1');
    expect(await colonnes(db, 'clotures_exercices_local'), [
      'id',
      'exercice_id',
      'piece_cloture',
      'piece_a_nouveaux',
      'resultat_centimes',
      'cloturee_par',
      'cloturee_le',
      'archive_chemin',
      'archive_empreinte',
      'rouverte_par',
      'rouverte_le',
      'motif_reouverture',
    ]);
    await db.close();
  });

  test('les clés étrangères tiennent : un exercice et un auteur INCONNUS sont '
      'refusés, la clôture d’un exercice réel passe', () async {
    final db = AppDatabase.surFichier(fichier);
    await semerAuteur(db);
    await installerReferentielComptable(
      db,
      contenuPlan: lirePlanEmbarque(),
      maintenant: DateTime(2031, 6, 15),
    );
    final exercice = (await ComptabiliteDao(db).exerciceDeLAnnee(2031))!;
    const colonnesInsert =
        'INSERT INTO clotures_exercices_local (id, exercice_id, '
        'resultat_centimes, cloturee_par, cloturee_le) VALUES ';

    await expectLater(
      db.customStatement(
        "$colonnesInsert('c-1', 'inconnu', 100, '$auteurEssai', 0)",
      ),
      throwsA(anything),
      reason: 'exercice inconnu',
    );
    await expectLater(
      db.customStatement(
        "$colonnesInsert('c-1', '${exercice.id}', 100, 'personne', 0)",
      ),
      throwsA(anything),
      reason: 'auteur inconnu (RG-15)',
    );
    await db.customStatement(
      "$colonnesInsert('c-1', '${exercice.id}', -2500, '$auteurEssai', 0)",
    );
    final ligne = await db
        .customSelect(
          'SELECT resultat_centimes, piece_cloture, archive_empreinte, '
          "rouverte_le FROM clotures_exercices_local WHERE id = 'c-1'",
        )
        .getSingle();
    expect(ligne.data['resultat_centimes'], -2500);
    expect(ligne.data['piece_cloture'], isNull);
    expect(ligne.data['archive_empreinte'], isNull);
    expect(ligne.data['rouverte_le'], isNull);
    await db.close();
  });

  test('les gardes de RG-11 survivent à la migration (triggers non recréés '
      'par la table neuve)', () async {
    await preparer(39);
    final apres = AppDatabase.surFichier(fichier);
    await apres.customStatement('SELECT 1');
    final declencheurs = await apres
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' "
          "AND name LIKE 'rg11_%'",
        )
        .get();
    expect(declencheurs, hasLength(4));
    await apres.close();
  });

  test('la migration rejouée sur un fichier déjà v40 mais marqué v39 ne plante '
      'pas, et ne perd rien (piège 3)', () async {
    final avant = AppDatabase.surFichier(fichier);
    await semerAuteur(avant);
    await installerReferentielComptable(
      avant,
      contenuPlan: lirePlanEmbarque(),
      maintenant: DateTime(2031, 6, 15),
    );
    final exercice = (await ComptabiliteDao(avant).exerciceDeLAnnee(2031))!;
    await avant.customStatement(
      'INSERT INTO clotures_exercices_local (id, exercice_id, '
      'resultat_centimes, cloturee_par, cloturee_le) VALUES '
      "('c-1', '${exercice.id}', 100, '$auteurEssai', 0)",
    );
    await avant.customStatement('PRAGMA user_version = 39');
    await avant.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(await compte(apres, 'clotures_exercices_local'), 1);
    await apres.close();
  });
}
