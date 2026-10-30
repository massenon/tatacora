import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:tatacora_flutter/core/database/app_database.dart';

/// R3 (PRD réinstallation) : la migration est prouvée depuis de VRAIES anciennes
/// bases, pas depuis le schéma courant ramené en arrière (piège 3 du CLAUDE.md).
///
/// Chaque `test/fixtures/schemas_anciens/vNN.sql` est le `sqlite_master` d'une
/// base construite avec le code du commit où `schemaVersion` est devenu NN
/// (`tool/migration/extraire_schemas_anciens.dart`). Le test reconstruit un
/// fichier depuis le dump, y sème des lignes, l'ouvre avec le code courant
/// (`onUpgrade` + réconciliation) et compare TABLES, COLONNES (nom, type, NOT
/// NULL, défaut, clé), INDEX et DÉCLENCHEURS à ceux d'une base neuve : écart
/// zéro, et aucune ligne perdue.
///
/// Les deux formes de base réelle y passent : les paliers sautés (v26 -> courant
/// d'un coup) et la copie de table de la v43 (`operations_sync_local` recopiée
/// depuis une base réelle v42).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const dossierDumps = 'test/fixtures/schemas_anciens';

  /// Les versions exigées par le PRD (R3). Chacune a un dump, OU figure dans
  /// [exceptions] avec sa raison : jamais sautée en silence.
  const exigees = [10, 14, 20, 26, 30, 35, 38, 40, 43];

  /// Versions dont aucun dump ne peut être extrait de l'historique git.
  /// Mesuré le 28/10/2026 : le dépôt est né le 14/10/2026 (« Initialisation
  /// monorepo », 0d8d53e) à `schemaVersion = 24`, et aucun commit n'a porté 41
  /// ni 43 (42 -> 44 en un commit, la copie de v43 est arrivée dans le suivant).
  /// Pour 43, la copie de `operations_sync_local` est exercée depuis la base
  /// RÉELLE v42 (voir plus bas). Quand un dump apparaît, l'exception doit être
  /// retirée : un test le vérifie.
  const exceptions = <int, String>{
    10: 'antérieure à l’initialisation du dépôt (v24, 14/10/2026) : aucun commit',
    14: 'antérieure à l’initialisation du dépôt (v24, 14/10/2026) : aucun commit',
    20: 'antérieure à l’initialisation du dépôt (v24, 14/10/2026) : aucun commit',
    41: 'aucun commit n’a porté la v41 (40 -> 42 en un commit, 27/10/2026)',
    43:
        'aucun commit n’a porté la v43 (42 -> 44 en un commit, 28/10/2026) ; '
        'sa copie de table est prouvée depuis la v42 réelle',
  };

  /// Tables dont la migration retire volontairement des lignes (nommées).
  const lignesRetireesVoulues = <String, String>{
    'etat_synchronisation_local':
        'v27/v44 : le curseur de descente est oublié exprès',
  };

  final dumps = <int, File>{};
  final racine = Directory(dossierDumps);
  if (racine.existsSync()) {
    for (final f in racine.listSync().whereType<File>()) {
      final m = RegExp(r'v(\d+)\.sql$').firstMatch(f.path);
      if (m != null) dumps[int.parse(m[1]!)] = f;
    }
  }

  late Directory tmp;
  setUpAll(() => tmp = Directory.systemTemp.createTempSync('anciens_'));
  tearDownAll(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Verrou Windows : sans conséquence.
    }
  });

  // ------------------------------------------------------------- mécanique

  File construire(int version) {
    final fichier = File('${tmp.path}/v$version.sqlite');
    final db = sql.sqlite3.open(fichier.path);
    final texte = dumps[version]!.readAsStringSync();
    for (final bloc in texte.split('-- ----\n').skip(1)) {
      db.execute(bloc);
    }
    db.execute('PRAGMA user_version = $version');
    db.close();
    return fichier;
  }

  /// Sème des lignes typées sur chaque table. Deux essais par ligne (toutes les
  /// colonnes, puis les seules obligatoires) ; une table qui refuse les deux
  /// (CHECK métier) reste vide, et le test exige un plancher de tables garnies.
  Map<String, int> semer(File fichier) {
    final db = sql.sqlite3.open(fichier.path);
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String)
        .toList();
    final comptes = <String, int>{};
    // La file d'envoi (v26+) porte des CHECK métier que le semis générique ne
    // sait pas remplir : deux opérations RÉALISTES, dont les `seq` doivent
    // survivre à la copie de table de la v43.
    if (tables.contains('operations_sync_local')) {
      for (final (seq, type, statut) in [
        (5, 'creation', 'en_attente'),
        (9, 'modification', 'rejete'),
      ]) {
        db.execute(
          'INSERT INTO operations_sync_local (seq, uuid_operation, '
          'table_serveur, entite_id, type, payload, horodatage_client, statut, '
          'cree_le) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [seq, 'u$seq', 'clients', 'c$seq', type, '{}', 'h', statut, 1],
        );
      }
    }
    for (final t in tables) {
      final cols = db.select('PRAGMA table_info("$t")');
      for (var i = 1; i <= 2; i++) {
        for (final tous in [true, false]) {
          final choisies = cols
              .where(
                (c) => tous || (c['notnull'] == 1 && c['dflt_value'] == null),
              )
              .toList();
          if (choisies.isEmpty) continue;
          final valeurs = [
            for (final c in choisies) _valeur(t, c['type'] as String, i),
          ];
          try {
            db.execute(
              'INSERT INTO "$t" (${choisies.map((c) => '"${c['name']}"').join(',')}) '
              'VALUES (${List.filled(choisies.length, '?').join(',')})',
              valeurs,
            );
            break;
          } on sql.SqliteException {
            continue;
          }
        }
      }
      comptes[t] =
          db.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int;
    }
    db.close();
    return comptes;
  }

  Map<String, int> compter(File fichier) {
    final db = sql.sqlite3.open(fichier.path, mode: sql.OpenMode.readOnly);
    final tables = db
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String);
    final r = {
      for (final t in tables)
        t: db.select('SELECT COUNT(*) AS n FROM "$t"').first['n'] as int,
    };
    db.close();
    return r;
  }

  Future<void> ouvrirAvecLeCodeCourant(File fichier) async {
    final db = AppDatabase.surFichier(fichier);
    await db.customSelect('SELECT 1').get();
    await db.close();
  }

  Map<String, String> empreinte(File fichier) {
    final db = sql.sqlite3.open(fichier.path, mode: sql.OpenMode.readOnly);
    final r = <String, String>{};
    for (final t in db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%'",
    )) {
      final nom = t['name'] as String;
      final cols = [
        for (final c in db.select('PRAGMA table_info("$nom")'))
          '${c['name']} ${(c['type'] as String).toUpperCase()} '
              'nn=${c['notnull']} dflt=${c['dflt_value']} pk=${c['pk']}',
      ]..sort();
      // Les CHECK ne sont pas dans `table_info` : un CHECK resté étroit (cas
      // réel de la file d'envoi) passerait inaperçu sans cette lecture du SQL.
      final ddl =
          db.select(
                "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
                [nom],
              ).first['sql']
              as String;
      final checks =
          RegExp(r'CHECK\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)')
              .allMatches(ddl)
              .map((m) => m[1]!.replaceAll(RegExp(r'\s+'), ' ').trim())
              .toList()
            ..sort();
      r['table $nom'] = '${cols.join(' | ')} || checks=${checks.join(' ; ')}';
      for (final i in db.select('PRAGMA index_list("$nom")')) {
        final n = i['name'] as String;
        if (n.startsWith('sqlite_autoindex')) continue;
        final colonnes = db
            .select('PRAGMA index_info("$n")')
            .map((c) => c['name'])
            .join(',');
        r['index $n'] = '$nom unique=${i['unique']} ($colonnes)';
      }
    }
    for (final d in db.select(
      "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
    )) {
      r['trigger ${d['name']}'] = (d['sql'] as String).replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
    }
    db.close();
    return r;
  }

  Future<File> baseNeuve() async {
    final f = File('${tmp.path}/neuve.sqlite');
    if (!f.existsSync()) await ouvrirAvecLeCodeCourant(f);
    return f;
  }

  List<String> ecarts(Map<String, String> neuve, Map<String, String> migree) {
    final r = <String>[];
    for (final k in {...neuve.keys, ...migree.keys}.toList()..sort()) {
      if (neuve[k] != migree[k]) {
        r.add('$k\n   neuve  : ${neuve[k]}\n   migrée : ${migree[k]}');
      }
    }
    return r;
  }

  // ------------------------------------------------------------------ tests

  test('chaque version exigée a un dump réel OU une exception nommée', () {
    for (final v in exigees) {
      expect(
        dumps.containsKey(v) || exceptions.containsKey(v),
        isTrue,
        reason: 'v$v : ni dump ni exception nommée',
      );
    }
    for (final v in exceptions.keys) {
      expect(
        dumps.containsKey(v),
        isFalse,
        reason: 'v$v a désormais un dump : retirer son exception',
      );
    }
    expect(
      dumps.length,
      greaterThanOrEqualTo(15),
      reason: 'dumps réels trouvés : ${dumps.keys.toList()..sort()}',
    );
  });

  for (final version in (dumps.keys.toList()..sort())) {
    test(
      'v$version (base réelle) -> courante : écart zéro, aucune ligne perdue',
      () async {
        final fichier = construire(version);
        final avant = semer(fichier);
        expect(
          avant.values.where((n) => n > 0).length,
          greaterThanOrEqualTo(10),
          reason: 'trop peu de tables garnies : le test serait presque à vide',
        );
        await ouvrirAvecLeCodeCourant(fichier);

        final apres = compter(fichier);
        for (final e in avant.entries) {
          if (lignesRetireesVoulues.containsKey(e.key)) continue;
          expect(
            apres[e.key] ?? 0,
            greaterThanOrEqualTo(e.value),
            reason: 'v$version : lignes perdues dans ${e.key}',
          );
        }
        if (avant.containsKey('operations_sync_local')) {
          final db = sql.sqlite3.open(fichier.path);
          expect(
            db
                .select(
                  'SELECT seq, type, statut FROM operations_sync_local '
                  'WHERE seq IN (5, 9) ORDER BY seq',
                )
                .map((r) => '${r['seq']} ${r['type']} ${r['statut']}')
                .toList(),
            ['5 creation en_attente', '9 modification rejete'],
            reason: 'v$version : la file d envoi doit garder ses opérations',
          );
          // La v43 élargit le CHECK du type : `suppression` est admis.
          db.execute(
            'INSERT INTO operations_sync_local (uuid_operation, '
            'table_serveur, entite_id, type, payload, horodatage_client, '
            "cree_le) VALUES ('us', 'vehicules', 'v', 'suppression', '{}', "
            "'h', 1)",
          );
          db.close();
        }
        final diff = ecarts(empreinte(await baseNeuve()), empreinte(fichier));
        expect(diff, isEmpty, reason: 'v$version :\n${diff.join('\n')}');

        final db = sql.sqlite3.open(fichier.path, mode: sql.OpenMode.readOnly);
        // La version COURANTE (47 depuis la description d'un plat, 30/10/2026 ; 46 depuis le mot de passe perdu sans e-mail,
        // 29/10/2026).
        expect(db.select('PRAGMA user_version').first.values.first, 47);
        db.close();
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}

Object _valeur(String table, String type, int i) {
  final t = type.toUpperCase();
  if (t.contains('INT') || t.contains('BOOL')) return i == 1 ? 1 : 0;
  if (t.contains('REAL') || t.contains('FLOA') || t.contains('DOUB')) {
    return 1.5 * i;
  }
  return 'v-$table-$i';
}
