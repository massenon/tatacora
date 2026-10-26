import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/transverse/data/reinitialisation_locale.dart';
import 'package:tatacora_flutter/features/transverse/data/sauvegardes_poste.dart';

/// Correction du Product Owner : « Quand je VIDE les seeders ou les données de
/// test, les données des tables PLATS, INGRÉDIENTS, ARTICLES, CARTES BOISSON et
/// leurs AUTRES TABLES LIÉES EN JOINTURE doivent être vidées AUSSI. »
///
/// Sur un FICHIER réel, clés étrangères actives. Aucune liste de tables n'est
/// recopiée : l'arbre du catalogue est ÉNUMÉRÉ par `PRAGMA foreign_key_list`
/// (et, pour les jointures SANS clé étrangère — `lignes_inventaire_local`,
/// `indisponibilites_carte_local`, `plats_local.article_id` —, par le NOM de
/// colonne), donc une table jointe ajoutée demain est exigée vide sans qu'on
/// y pense.
void main() {
  /// Les racines nommées par le PO (+ menus et recettes, parents de jointure).
  const racines = {
    'articles_local',
    'plats_local',
    'menus_local',
    'recettes_local',
    'ingredients_recette_local',
    'cartes_boisson_local',
    // Le parent des lignes d'inventaire : le comptage de ces articles.
    'inventaires_local',
  };

  /// Colonne de jointure sans clé étrangère -> la table qu'elle désigne.
  const jointuresParNom = {
    'article_id': 'articles_local',
    'plat_id': 'plats_local',
    'boisson_id': 'cartes_boisson_local',
    'recette_id': 'recettes_local',
    'menu_id': 'menus_local',
    'inventaire_id': 'inventaires_local',
  };

  /// Les seules valeurs qu'une contrainte CHECK impose (registres fermés).
  const surcharges = {'operations_sync_local.type': 'creation'};

  late Directory dossier;
  late AppDatabase db;

  setUp(() async {
    dossier = Directory.systemTemp.createTempSync('reinit_catalogue_');
    db = AppDatabase.surFichier(File('${dossier.path}/poste.sqlite'));
    await db.customStatement('SELECT 1');
  });
  tearDown(() async {
    await db.close();
    dossier.deleteSync(recursive: true);
  });

  Future<List<String>> toutesLesTables() async => [
    for (final l
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )
            .get())
      l.read<String>('name'),
  ];

  Future<int> compter(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM "$table"').getSingle())
              .data['n']
          as int;

  /// table -> (colonne -> table désignée), clés étrangères réelles + noms.
  Future<Map<String, Map<String, String>>> jointures({
    bool parNom = true,
  }) async {
    final res = <String, Map<String, String>>{};
    for (final t in await toutesLesTables()) {
      final m = <String, String>{};
      for (final c
          in await db.customSelect('PRAGMA foreign_key_list("$t")').get()) {
        m[c.read<String>('from')] = c.read<String>('table');
      }
      if (parNom) {
        for (final c
            in await db.customSelect('PRAGMA table_info("$t")').get()) {
          final nom = c.read<String>('name');
          final cible = jointuresParNom[nom];
          if (cible != null && cible != t) m.putIfAbsent(nom, () => cible);
        }
      }
      res[t] = m;
    }
    return res;
  }

  /// Les racines + toute table qui les désigne, transitivement.
  Future<Set<String>> arbre({bool parNom = true}) async {
    final liens = await jointures(parNom: parNom);
    final arbre = {...racines};
    var change = true;
    while (change) {
      change = false;
      liens.forEach((source, colonnes) {
        if (!arbre.contains(source) &&
            colonnes.values.any(arbre.contains)) {
          arbre.add(source);
          change = true;
        }
      });
    }
    return arbre;
  }

  /// Sème UNE ligne dans [table], ses parents d'abord (récursif, générique :
  /// aucune colonne recopiée ici, tout vient de `PRAGMA table_info`).
  Future<void> semer(
    String table,
    Map<String, Map<String, String>> liens, [
    Set<String>? enCours,
  ]) async {
    if (await compter(table) > 0) return;
    final pile = enCours ?? <String>{};
    if (!pile.add(table)) return;
    final colonnes = <String>[];
    final valeurs = <Object?>[];
    for (final c in await db.customSelect('PRAGMA table_info("$table")').get()) {
      final nom = c.read<String>('name');
      final type = c.read<String>('type').toUpperCase();
      final cible = liens[table]![nom];
      final obligatoire =
          c.read<int>('notnull') == 1 && c.data['dflt_value'] == null;
      if (cible != null) {
        await semer(cible, liens, pile);
        final ligne = await db
            .customSelect('SELECT id FROM "$cible" LIMIT 1')
            .getSingle();
        colonnes.add(nom);
        valeurs.add(ligne.data['id']);
      } else if (surcharges.containsKey('$table.$nom')) {
        colonnes.add(nom);
        valeurs.add(surcharges['$table.$nom']);
      } else if (nom == 'id') {
        colonnes.add(nom);
        valeurs.add('id-$table');
      } else if (obligatoire) {
        colonnes.add(nom);
        valeurs.add(
          type.contains('INT') || type.contains('BOOL')
              ? 1
              : type.contains('REAL') || type.contains('DOUBLE')
              ? 1.5
              : 'x-$nom',
        );
      }
    }
    await db.customStatement(
      'INSERT INTO "$table" (${colonnes.map((c) => '"$c"').join(', ')}) '
      'VALUES (${valeurs.map((_) => '?').join(', ')})',
      valeurs,
    );
  }

  test('catalogue complet semé sur fichier puis vidé : ZÉRO ligne dans chaque '
      'table de l\'arbre, lieux et référentiels gardés', () async {
    final liens = await jointures();
    final tree = await arbre();
    // La sonde voit bien les jointures qui comptent (sinon elle passerait à vide).
    expect(
      tree,
      containsAll([
        'mouvements_stock_local',
        'indisponibilites_carte_local',
        'lignes_inventaire_local',
        'inventaires_local',
        'lignes_vente_bar_local',
      ]),
    );

    for (final t in tree) {
      await semer(t, liens);
    }
    // Les lieux (gardés) et la file / le curseur de descente (vidés).
    await semer('points_stockage_local', liens);
    await semer('operations_sync_local', liens);
    await semer('etat_synchronisation_local', liens);
    for (final t in [...tree, 'operations_sync_local']) {
      expect(await compter(t), greaterThan(0), reason: 'non semée : $t');
    }

    await ParametresDao(
      db,
    ).ecrire({OptionsSysteme.cleReinitialisationSeeders: '1'}, auteurId: null);
    final avant = await compter('parametres_systeme_local');

    final bilan = await ReinitialisationLocale(
      db,
      sauvegardes: SauvegardesPoste(
        db,
        cheminConfiguration: () async => '${dossier.path}/poste.json',
      ),
    ).executer(role: 'administrateur');

    expect(bilan.sauvegarde, isNotNull, reason: 'sauvegarde de sûreté avant');
    for (final t in tree) {
      expect(await compter(t), 0, reason: '$t devait être vidée');
    }
    expect(await compter('operations_sync_local'), 0);
    expect(await compter('etat_synchronisation_local'), 0);
    // Les lieux et les réglages restent.
    expect(await compter('points_stockage_local'), greaterThan(0));
    expect(await compter('parametres_systeme_local'), greaterThanOrEqualTo(avant));
    // Les clés étrangères sont restées ACTIVES.
    final fk = await db.customSelect('PRAGMA foreign_keys').getSingle();
    expect(fk.data.values.single, 1);
  });

  test('aucune table liée au catalogue n\'est oubliée : l\'arbre énuméré par '
      'PRAGMA foreign_key_list est entièrement dans les tables vidées', () async {
    final moteur = ReinitialisationLocale(db);
    final effacables = (await moteur.tablesEffacables()).toSet();
    final gardees = (await moteur.tablesPreservees()).toSet();
    final tree = await arbre();

    for (final t in tree) {
      expect(effacables, contains(t), reason: '$t référence le catalogue');
      expect(tablesPreserveesLocales, isNot(contains(t)));
    }

    // Aucune table GARDÉE ne désigne le catalogue, par clé étrangère ou par
    // nom de colonne.
    final liens = await jointures();
    for (final t in gardees) {
      final vers = liens[t]!.values.where(tree.contains);
      expect(vers, isEmpty, reason: '$t (gardée) désigne le catalogue');
    }

    // Les lieux restent des référentiels, sans article.
    expect(gardees, containsAll(['points_stockage_local', 'tables_local']));

    // Et l'ordre de vidage place chaque enfant avant son parent (FK réelles).
    final ordre = await moteur.ordreDeVidage();
    final rang = {for (var i = 0; i < ordre.length; i++) ordre[i]: i};
    final fkSeules = await jointures(parNom: false);
    fkSeules.forEach((source, colonnes) {
      for (final cible in colonnes.values) {
        if (cible != source && rang.containsKey(source) && rang.containsKey(cible)) {
          expect(rang[source]!, lessThan(rang[cible]!), reason: '$source -> $cible');
        }
      }
    });
  });
}
