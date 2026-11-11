import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `AffectationsRecuesDao` est le SEUL code de `lib/` qui écrit
/// `affectations_resultat_local`, le miroir de LECTURE des affectations du résultat
/// que le serveur connaît (v53, 09/11/2026). Deux auteurs divergeraient ; et un
/// auteur qui enfilerait, ou qui toucherait aux écritures du poste, ferait remonter
/// ce qui descend ou compterait une affectation deux fois.
///
/// Seul appelant : l'aligneur du catalogue (`AligneurCatalogue._affectationRecue`),
/// qui n'enfile jamais. La carte (`AffectationResultatLocale`) LIT, rien de plus, et
/// ne dépend d'aucun transport : « le poste fonctionne SANS le serveur ».
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*affectationsResultatLocal\b'),
  RegExp(r'\bAffectationsResultatLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*affectationsResultatLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+affectations_resultat_local',
    caseSensitive: false,
  ),
];

const _dao = 'lib/features/comptabilite/data/affectations_recues_dao.dart';
const _carte =
    'lib/features/comptabilite/data/affectation_resultat_locale.dart';
const _aligneur = 'lib/features/synchronisation/data/aligneur_catalogue.dart';

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
      'await db.into(db.affectationsResultatLocal).insert(x);',
      'await (update(db.affectationsResultatLocal)..where(w)).write(y);',
      'final c = AffectationsResultatLocalCompanion.insert(a);',
      "await customStatement('delete from AFFECTATIONS_RESULTAT_LOCAL');",
    ]) {
      expect(
        _ecrivains.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    expect(
      _ecrivains.any(
        (r) => r.hasMatch('select(db.affectationsResultatLocal).get()'),
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

  test('le DAO n’enfile rien et ne touche ni le journal ni le réseau', () {
    final code = _code(File(_dao));
    expect(code, isNot(contains('ecrituresLocal')));
    expect(code, isNot(contains('MoteurComptable')));
    expect(code, isNot(contains('enfiler')));
    expect(code, isNot(contains('operationsSync')));
    expect(code, isNot(contains('Transport')));
  });

  test('seul l’aligneur du catalogue appelle l’écrivain', () {
    final appelants = [
      for (final f in fichiers)
        if (_p(f) != _dao && _code(f).contains('AffectationsRecuesDao(')) _p(f),
    ];
    expect(appelants..sort(), [_carte, _aligneur]..sort());
    // La carte ne fait que LIRE : aucune méthode d'écriture du DAO.
    final carte = _code(File(_carte));
    expect(carte, contains('AffectationsRecuesDao(_db).deLAnnee('));
    expect(carte, isNot(contains('.inscrire(')));
    expect(
      RegExp(r'\.inscrire\(').allMatches(_code(File(_aligneur))),
      hasLength(1),
    );
  });

  test('la lecture de la carte ne demande aucun réseau', () {
    final carte = _code(File(_carte));
    for (final interdit in [
      'Transport',
      'package:http',
      'package:dio',
      'HttpClient',
      'SyncManager',
      'Uri.parse',
    ]) {
      expect(carte, isNot(contains(interdit)), reason: interdit);
    }
  });
}
