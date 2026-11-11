// Extrait le SCHÉMA RÉEL de chaque ancienne version de la base du poste.
//
// PRD réinstallation et démarrage résilient, exigence R3. Piège 3 du CLAUDE.md :
// une fixture « vN » fabriquée depuis le schéma COURANT n'imite pas une vN. Ici,
// pour chaque version N :
//
//   1. `git log -S"int get schemaVersion => N;"` retrouve le commit où
//      `schemaVersion` est devenu N (le plus ancien qui le porte) ;
//   2. `git archive <commit>` extrait le code de la base de CE commit
//      (`lib/core/database` + `lib/core/config/environnement.dart`) dans un
//      dossier temporaire HORS du dépôt ;
//   3. `build_runner` y génère le code Drift, puis un test jetable ouvre une base
//      neuve avec ce code et écrit `sqlite_master` ;
//   4. le dump texte est écrit dans `test/fixtures/schemas_anciens/vNN.sql`.
//
// Usage (depuis tatacora-flutter/, historique git complet, git + tar + flutter
// dans le PATH, pubspec.lock résolu hors ligne) :
//
//   dart run tool/migration/extraire_schemas_anciens.dart            # 24..44
//   dart run tool/migration/extraire_schemas_anciens.dart 26 30 40   # certaines
//
// Une version que l'historique ne porte pas (aucun commit ne l'a jamais eue) est
// SIGNALÉE, jamais fabriquée : le test de migration nomme ces exceptions.
// ignore_for_file: avoid_print
import 'dart:io';

const _fichierBase = 'tatacora-flutter/lib/core/database/app_database.dart';
const _sortie = 'test/fixtures/schemas_anciens';

const _testDump = r'''
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';

void main() {
  test('dump', () async {
    final f = File('${Directory.systemTemp.path}/dump_${pid}.sqlite');
    if (f.existsSync()) f.deleteSync();
    final db = AppDatabase.surFichier(f);
    final v = await db.customSelect('PRAGMA user_version').getSingle();
    final r = await db
        .customSelect(
          'SELECT type, name, sql FROM sqlite_master '
          "WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid",
        )
        .get();
    final sb = StringBuffer('-- user_version: ${v.data.values.first}\n');
    for (final l in r) {
      sb.write('-- ----\n${l.data['sql']};\n');
    }
    File(Platform.environment['SORTIE']!).writeAsStringSync(sb.toString());
    await db.close();
    f.deleteSync();
  });
}
''';

Future<String> _sh(
  String commande,
  List<String> args, {
  String? dans,
  Map<String, String>? env,
}) async {
  final r = await Process.run(
    commande,
    args,
    workingDirectory: dans,
    environment: env,
    runInShell: Platform.isWindows,
  );
  if (r.exitCode != 0) {
    throw ProcessException(
      commande,
      args,
      '${r.stdout}\n${r.stderr}',
      r.exitCode,
    );
  }
  return r.stdout as String;
}

Future<void> main(List<String> args) async {
  final racine = (await _sh('git', ['rev-parse', '--show-toplevel'])).trim();
  final projet = Directory('$racine/tatacora-flutter').absolute.path;
  final versions = args.isEmpty
      ? [for (var n = 24; n <= 44; n++) n]
      : args.map(int.parse).toList();
  Directory('$projet/$_sortie').createSync(recursive: true);
  final introuvables = <int>[];

  for (final n in versions) {
    final commits = (await _sh('git', [
      'log',
      '--reverse',
      '--format=%H',
      '-S',
      'int get schemaVersion => $n;',
      '--',
      _fichierBase,
    ], dans: racine)).trim().split('\n').where((l) => l.isNotEmpty).toList();
    String? commit;
    for (final c in commits) {
      final source = await _sh('git', [
        'show',
        '$c:$_fichierBase',
      ], dans: racine);
      if (source.contains('int get schemaVersion => $n;')) {
        commit = c;
        break;
      }
    }
    if (commit == null) {
      print('v$n : AUCUN commit ne porte cette version -> exception à nommer');
      introuvables.add(n);
      continue;
    }
    final date = (await _sh('git', [
      'log',
      '-1',
      '--format=%ad',
      '--date=short',
      commit,
    ], dans: racine)).trim();
    final dossier = Directory.systemTemp.createTempSync('schema_v${n}_');
    try {
      await _sh('sh', [
        '-c',
        'git archive $commit tatacora-flutter/lib/core/database '
            'tatacora-flutter/lib/core/config/environnement.dart '
            '| tar -x -C "${dossier.path}" --strip-components=1',
      ], dans: racine);
      final pubspec = File('$projet/pubspec.yaml').readAsStringSync();
      final coupe = pubspec.indexOf('\nflutter:\n');
      File('${dossier.path}/pubspec.yaml').writeAsStringSync(
        '${pubspec.substring(0, coupe)}\nflutter:\n  uses-material-design: false\n',
      );
      File('$projet/pubspec.lock').copySync('${dossier.path}/pubspec.lock');
      Directory('${dossier.path}/test').createSync();
      File('${dossier.path}/test/dump_test.dart').writeAsStringSync(_testDump);
      await _sh('flutter', ['pub', 'get', '--offline'], dans: dossier.path);
      await _sh('dart', [
        'run',
        'build_runner',
        'build',
        '--delete-conflicting-outputs',
      ], dans: dossier.path);
      final cible = '$projet/$_sortie/v${n.toString().padLeft(2, '0')}.sql';
      await _sh(
        'flutter',
        ['test', 'test/dump_test.dart'],
        dans: dossier.path,
        env: {'SORTIE': '${dossier.path}/sortie.sql'},
      );
      final dump = File('${dossier.path}/sortie.sql').readAsStringSync();
      File(cible).writeAsStringSync(
        '-- Schéma RÉEL v$n : commit ${commit.substring(0, 9)} ($date), '
        'construit avec le code de ce commit.\n'
        '-- Généré par tool/migration/extraire_schemas_anciens.dart : ne pas éditer.\n'
        '$dump',
      );
      print('v$n : commit ${commit.substring(0, 9)} ($date) -> $cible');
    } finally {
      dossier.deleteSync(recursive: true);
    }
  }
  if (introuvables.isNotEmpty) {
    print('Versions sans commit : $introuvables');
  }
}
