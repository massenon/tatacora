/// RÉCONCILIATION du schéma : la base du poste est comparée à
/// `allSchemaEntities` et complétée de ce qui lui manque (PRD réinstallation,
/// exigence R2).
///
/// Pourquoi : `user_version` dit « v44 » ; il ne dit pas que les 77 tables, leurs
/// colonnes, leurs index et les gardes RG-11 existent. Une base à paliers sautés
/// ou issue d'une branche parallèle échouait au premier accès (`no such table`,
/// `no such column`).
///
/// ## Règles
///
/// - Table absente -> `createTable` (définition courante : rien ne l'a jamais
///   contenue sur ce poste).
/// - Colonne absente -> `ALTER TABLE ... ADD COLUMN`, nullable, ou avec un
///   `DEFAULT` explicite pour un `NOT NULL` (SQLite refuse sinon).
/// - Index et déclencheurs RG-11 absents -> recréés (`creerDeclencheursComptables`
///   est idempotent).
/// - **JAMAIS destructive** : une table ou une colonne EN TROP est laissée en
///   place et seulement journalisée. La donnée non synchronisée est la seule
///   copie qui existe.
/// - Tout ce qui est posé est écrit au journal de démarrage (`demarrage.log`).
library;

import 'package:drift/drift.dart';

import 'app_database.dart';
import 'declencheurs_comptables.dart';
import 'elargir_types_operations_sync.dart';

/// Ce qu'a fait une réconciliation.
class RapportReconciliation {
  final List<String> tablesCreees = [];
  final List<String> colonnesAjoutees = [];
  final List<String> indexCrees = [];
  final List<String> declencheursCrees = [];
  final List<String> tablesRecopiees = [];
  final List<String> enTrop = [];

  bool get aPose =>
      tablesCreees.isNotEmpty ||
      tablesRecopiees.isNotEmpty ||
      colonnesAjoutees.isNotEmpty ||
      indexCrees.isNotEmpty ||
      declencheursCrees.isNotEmpty;
}

/// Les déclencheurs que le schéma attend (RG-11).
const List<String> declencheursAttendus = [
  'rg11_ecriture_validee_immuable',
  'rg11_brouillon_exercice_clos_maj',
  'rg11_exercice_clos_ajout',
  'rg11_ecriture_jamais_supprimee',
];

Future<Set<String>> _noms(AppDatabase db, String type) async {
  final lignes = await db
      .customSelect(
        'SELECT name FROM sqlite_master WHERE type = ? '
        "AND name NOT LIKE 'sqlite_%'",
        variables: [Variable.withString(type)],
      )
      .get();
  return {for (final l in lignes) l.data['name'] as String};
}

/// Contrôle RAPIDE : noms de tables, d'index, de déclencheurs, et nombre de
/// colonnes de chaque table, en une requête chacun. `true` s'il y a un écart.
Future<bool> ecartRapide(AppDatabase db) async {
  final tables = db.allTables.toList();
  final presentes = await _noms(db, 'table');
  final attendues = {for (final t in tables) t.actualTableName};
  if (!presentes.containsAll(attendues)) return true;
  final index = await _noms(db, 'index');
  for (final e in db.allSchemaEntities.whereType<Index>()) {
    if (!index.contains(e.entityName)) return true;
  }
  if (await _fileAEtroite(db)) return true;
  final declencheurs = await _noms(db, 'trigger');
  if (!declencheurs.containsAll(declencheursAttendus)) return true;
  final comptes = await db
      .customSelect(
        'SELECT m.name AS nom, COUNT(p.name) AS n FROM sqlite_master m, '
        "pragma_table_info(m.name) p WHERE m.type = 'table' GROUP BY m.name",
      )
      .get();
  final parTable = {
    for (final l in comptes) l.data['nom'] as String: l.data['n'] as int,
  };
  for (final t in tables) {
    if ((parTable[t.actualTableName] ?? 0) < t.$columns.length) return true;
  }
  return false;
}

/// La file d'envoi garde-t-elle l'ancien `CHECK` du type (sans `suppression`) ?
/// Cas RÉEL trouvé par les vraies bases (R3) : une base marquée v44 par le
/// commit où la v43 n'existait pas encore n'a jamais eu la copie de la v43.
Future<bool> _fileAEtroite(AppDatabase db) async {
  final ligne = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' "
        "AND name = 'operations_sync_local'",
      )
      .getSingleOrNull();
  final sql = ligne?.read<String?>('sql');
  return sql != null && !sql.contains("'suppression'");
}

String _defautPour(GeneratedColumn<Object> c) => switch (c.type) {
  DriftSqlType.string => "''",
  DriftSqlType.blob => "x''",
  _ => '0',
};

/// Complète la base de ce qui manque, sans rien retirer. Idempotente.
Future<RapportReconciliation> reconcilierSchema(AppDatabase db) async {
  final rapport = RapportReconciliation();
  final m = Migrator(db);
  final journal = db.journalDemarrage;

  final tablesPresentes = await _noms(db, 'table');
  final attendues = <String>{};
  for (final t in db.allTables) {
    final nom = t.actualTableName;
    attendues.add(nom);
    if (!tablesPresentes.contains(nom)) {
      await m.createTable(t);
      rapport.tablesCreees.add(nom);
      continue;
    }
    final existantes = {
      for (final c in await db.customSelect('PRAGMA table_info("$nom")').get())
        c.data['name'] as String,
    };
    for (final col in t.$columns) {
      if (existantes.contains(col.$name)) continue;
      final contexte = GenerationContext.fromDb(db);
      col.writeColumnDefinition(contexte);
      var definition = contexte.sql;
      final majuscule = definition.toUpperCase();
      if (majuscule.contains('NOT NULL') && !majuscule.contains('DEFAULT')) {
        definition = '$definition DEFAULT ${_defautPour(col)}';
      }
      await db.customStatement('ALTER TABLE "$nom" ADD COLUMN $definition');
      rapport.colonnesAjoutees.add('$nom.${col.$name}');
    }
    final noms = {for (final c in t.$columns) c.$name};
    for (final extra in existantes.difference(noms)) {
      rapport.enTrop.add('colonne $nom.$extra');
    }
  }
  for (final extra in tablesPresentes.difference(attendues)) {
    rapport.enTrop.add('table $extra');
  }

  // Copie de table conditionnelle de la v43 (types de la file d'envoi), pour
  // les bases qui l'ont manquée ; sans effet si le `CHECK` est déjà large.
  if (await _fileAEtroite(db)) {
    await elargirTypesOperationsSync(m, db.operationsSyncLocal);
    rapport.tablesRecopiees.add('operations_sync_local');
  }

  final index = await _noms(db, 'index');
  for (final e in db.allSchemaEntities.whereType<Index>()) {
    if (index.contains(e.entityName)) continue;
    await db.customStatement(e.createStatementsByDialect[SqlDialect.sqlite]!);
    rapport.indexCrees.add(e.entityName);
  }

  final avant = await _noms(db, 'trigger');
  await creerDeclencheursComptables(db);
  final apres = await _noms(db, 'trigger');
  rapport.declencheursCrees.addAll(apres.difference(avant));

  if (journal != null) {
    if (rapport.aPose) {
      journal(
        'Réconciliation du schéma : tables créées ${rapport.tablesCreees}, '
        'tables recopiées (CHECK élargi) ${rapport.tablesRecopiees}, '
        'colonnes ajoutées ${rapport.colonnesAjoutees}, index créés '
        '${rapport.indexCrees}, déclencheurs créés ${rapport.declencheursCrees}',
      );
    }
    if (rapport.enTrop.isNotEmpty) {
      journal('Réconciliation : éléments en trop LAISSÉS ${rapport.enTrop}');
    }
  }
  return rapport;
}
