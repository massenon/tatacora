import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les ÉCRIVAINS de la clôture annuelle (26/10/2026) — qui écrit quoi, et rien
/// d'autre :
///
///  - `clotures_exercices_local` : `ClotureExerciceLocale`, seul ; `ArchiveClotureLocale`
///    n'y touche que par `consignerArchive`, jamais directement ;
///  - la clôture n'écrit AUCUNE ligne d'écriture (`ecritures_local`) : elle
///    demande ses pièces au moteur, seul écrivain (RG-11, RG-12, numéro) ;
///  - le statut d'un exercice ne change que par `ComptabiliteDao.changerStatutExercice`
///    (et l'installateur, qui en ouvre) ;
///  - la clôture n'enfile qu'UNE sorte de document : la DEMANDE — jamais une
///    pièce (D246) ;
///  - aucun accès réseau : la clôture se joue sur le poste, le serveur reçoit
///    une demande par la file.
final _ecrivainsClotures = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*cloturesExercicesLocal\b'),
  RegExp(r'\bCloturesExercicesLocalCompanion\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+clotures_exercices_local',
    caseSensitive: false,
  ),
];

const _service = 'lib/features/comptabilite/data/cloture_exercice_locale.dart';
const _archive = 'lib/features/comptabilite/data/archive_cloture_locale.dart';

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
      'await db.into(db.cloturesExercicesLocal).insert(x);',
      'await (_db.update(\n_db.cloturesExercicesLocal,\n)..where(w)).write(y);',
      'final c = CloturesExercicesLocalCompanion.insert(a);',
      "await customStatement('delete from CLOTURES_EXERCICES_LOCAL');",
    ]) {
      expect(
        _ecrivainsClotures.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    expect(
      _ecrivainsClotures.any(
        (r) => r.hasMatch('select(db.cloturesExercicesLocal).get()'),
      ),
      isFalse,
      reason: 'une lecture n’est pas une écriture',
    );
  });

  test(
    'un seul fichier de lib/ écrit les clôtures : le service des gestes',
    () {
      final auteurs = [
        for (final f in fichiers)
          if (_ecrivainsClotures.any((r) => r.hasMatch(_code(f)))) _p(f),
      ];
      expect(auteurs, [_service]);
    },
  );

  test('l’archive n’écrit pas la table : elle consigne par le service', () {
    final code = _code(File(_archive));
    expect(code, contains('consignerArchive('));
    expect(code, isNot(contains('cloturesExercicesLocal')));
    // …ni les écritures, ni la file.
    expect(code, isNot(contains('insererEcriture')));
    expect(code, isNot(contains('enfiler')));
  });

  test(
    'la clôture n’écrit aucune ligne d’écriture : elle passe par le moteur',
    () {
      final code = _code(File(_service));
      expect(code, isNot(contains('ecrituresLocal')));
      expect(code, isNot(contains('insererEcriture')));
      expect(code, isNot(contains('marquerValidee')));
      expect(code, isNot(contains('allouerRang')));
      expect(code, contains('_moteur.passerEtValider('));
      expect(code, contains('_moteur.contrepasserPieceADateDOrigine('));
    },
  );

  test('le statut d’un exercice change par le DAO comptable, et lui seul', () {
    final code = _code(File(_service));
    expect(code, isNot(contains('exercicesLocal')));
    expect(code, contains('changerStatutExercice('));
    final appelants = [
      for (final f in fichiers)
        if (_code(f).contains('.changerStatutExercice(')) _p(f),
    ];
    expect(appelants, [_service]);
  });

  test('la clôture n’enfile que des DEMANDES, jamais une pièce (D246)', () {
    final code = _code(File(_service));
    expect(
      RegExp(
        r'table:\s*TableSynchronisee\.(\w+)',
      ).allMatches(code).map((m) => m.group(1)).toSet(),
      {'demandesClotureExercice'},
    );
    // Un seul appel à `enfiler`, et dans la transaction du geste.
    expect(RegExp(r'\.enfiler\(').allMatches(code), hasLength(1));
    expect(code, contains('_demander(exercice.annee'));
  });

  test('aucun accès réseau dans la clôture', () {
    for (final f in [_service, _archive]) {
      final code = _code(File(f));
      for (final interdit in ['package:http', 'HttpClient', 'dio']) {
        expect(code, isNot(contains(interdit)), reason: '$f $interdit');
      }
    }
  });
}
