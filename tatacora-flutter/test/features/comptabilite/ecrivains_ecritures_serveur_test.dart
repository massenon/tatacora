import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `EcrituresServeurDao` est le SEUL code de `lib/` qui écrit
/// `ecritures_serveur_local`, le miroir de LECTURE des écritures validées du
/// serveur (v34). Deux auteurs divergeraient ; un auteur qui toucherait aussi
/// `ecritures_local` mêlerait les pièces du poste à celles du serveur, et
/// chaque vente serait comptée deux fois dans les états financiers.
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*ecrituresServeurLocal\b'),
  RegExp(r'\bEcrituresServeurLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*ecrituresServeurLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+ecritures_serveur_local',
    caseSensitive: false,
  ),
];

const _dao = 'lib/features/comptabilite/data/ecritures_serveur_dao.dart';

String _code(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _p(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final fichiers = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();

  test('le balayage n’est pas vide, et ses motifs mordent', () {
    expect(fichiers.length, greaterThan(200));
    for (final factice in [
      'await db.into(db.ecrituresServeurLocal).insert(x);',
      'await (update(db.ecrituresServeurLocal)..where(w)).write(y);',
      'final c = EcrituresServeurLocalCompanion.insert(a);',
      "await customStatement('delete from ECRITURES_SERVEUR_LOCAL');",
    ]) {
      expect(
        _ecrivains.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    expect(
      _ecrivains.any(
        (r) => r.hasMatch('select(db.ecrituresServeurLocal).get()'),
      ),
      isFalse,
      reason: 'une lecture n’est pas une écriture',
    );
  });

  test('un seul fichier de lib/ écrit le miroir : le DAO', () {
    final auteurs = [
      for (final f in fichiers)
        if (_ecrivains.any((r) => r.hasMatch(_code(f)))) _p(f),
    ];
    expect(auteurs, [_dao]);
  });

  test('ce DAO n’écrit pas le journal du poste et n’enfile rien', () {
    final code = _code(File(_dao));
    expect(code, isNot(contains('ecrituresLocal')));
    expect(code, isNot(contains('MoteurComptable')));
    expect(code, isNot(contains('operationsSync')));
    expect(code, isNot(contains('enfiler')));
  });
}
