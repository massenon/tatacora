import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les faits de structure que le règlement fournisseur tient — et qui se
/// périment en silence si personne ne les garde (PA-144, piège 9).
///
/// 1. **Un seul auteur** : `ReglementsFournisseurDao` est le SEUL code de `lib/`
///    qui écrit `reglements_fournisseur_local` (« un référentiel a UN SEUL
///    AUTEUR »). `AchatsDao` la LIT, pour chiffrer « Réglé » et « Reste dû ».
/// 2. **La pièce comptable est dans la même transaction que le règlement** : le
///    seul `insert` de la table et le seul `passerEtValider` du DAO sont dans le
///    MÊME bloc `transaction(...)` (règle du PO du 31/08/2026). Un balayage de
///    texte ne prouve pas le comportement — `reglements_fournisseur_dao_test.dart`
///    le fait en refusant la pièce et en comptant les lignes — mais il empêche
///    qu'un second chemin d'écriture sans pièce apparaisse sans bruit.
/// 3. **Le reste dû est relu DANS la transaction** : un contrôle fait avant
///    laisserait passer deux règlements concurrents (D255).
/// 4. **L'annulation n'a aucun appelant de production**, comme au serveur : le
///    service `annuler()` existe (PA-168), ni la vue Approvisionnement ni aucune
///    route ne l'appelle (D257). Un bouton « Annuler le règlement » qui
///    apparaîtrait ici sans que la vue le porte serait une invention ; le jour où
///    la vue le portera, ce cas doit être retiré AVEC le geste.
/// 5. **Aucun réseau, aucune synchronisation** : le règlement reste sur le poste.
///
/// Le balayage s'ANCRE sur le texte du code et prouve qu'il n'est pas vide : un
/// plancher de fichiers, et un échantillon fabriqué que les mêmes motifs doivent
/// dénoncer (sinon la garde serait verte à vide).
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*reglementsFournisseurLocal\b'),
  RegExp(r'\bReglementsFournisseurLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*reglementsFournisseurLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+reglements_fournisseur_local',
    caseSensitive: false,
  ),
  // Le DAO écrit par `into(_reglements)` / `update(_reglements)` : son alias.
  RegExp(r'\b(into|update|delete)\(\s*_reglements\s*\)'),
];

/// Le miroir du serveur (lot F4), second auteur DÉCLARÉ.
const String _miroir =
    'lib/features/synchronisation/data/aligneur_documents.dart';

const String _dao = 'lib/features/achats/data/reglements_fournisseur_dao.dart';

String _code(File f) =>
    f.readAsLinesSync().where((l) => !l.trimLeft().startsWith('//')).join('\n');

List<File> _fichiers(Directory racine) => racine
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList();

String _p(File f) => f.path.replaceAll(r'\', '/');

void main() {
  final lib = Directory('lib');

  test('le balayage n’est pas vide, et ses motifs mordent', () {
    expect(_fichiers(lib).length, greaterThan(300));

    for (final factice in [
      'await db.into(db.reglementsFournisseurLocal).insert(x);',
      'await (update(db.reglementsFournisseurLocal)..where(w)).write(y);',
      'final c = ReglementsFournisseurLocalCompanion.insert(a);',
      "await db.customStatement('INSERT INTO reglements_fournisseur_local VALUES (1)');",
      "await customStatement('update REGLEMENTS_FOURNISSEUR_LOCAL set x = 1');",
      'await into(_reglements).insert(z);',
      'await (update(_reglements)..where(w)).write(y);',
    ]) {
      expect(
        _ecrivains.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    // Une lecture n'est pas une écriture.
    expect(
      _ecrivains.any((r) => r.hasMatch('final l = select(_reglements);')),
      isFalse,
    );
    expect(
      _ecrivains.any(
        (r) =>
            r.hasMatch('select(attachedDatabase.reglementsFournisseurLocal)'),
      ),
      isFalse,
    );
  });

  test('un seul auteur : ReglementsFournisseurDao écrit '
      'reglements_fournisseur_local', () {
    final auteurs = <String>[];
    for (final f in _fichiers(lib)) {
      if (_p(f).contains('lib/core/database/')) continue;
      if (_ecrivains.any((r) => r.hasMatch(_code(f)))) auteurs.add(_p(f));
    }
    // Le DAO écrit : sans cette ligne, un motif cassé ferait croire que PERSONNE
    // n'écrit — et le test serait vert sur une table sans auteur.
    expect(auteurs, contains(_dao));
    // Lot F4 (17/10/2026) : le MIROIR du serveur — les documents des autres
    // postes descendent par l'aligneur, SANS pièce (décision Q1 du PO : le
    // serveur a passé la sienne). Il ne fait aucun geste, il recopie un état ;
    // le cas « le miroir ne passe aucune pièce » le tient.
    expect(auteurs, contains(_miroir));
    expect(
      auteurs.where((a) => a != _dao && a != _miroir),
      isEmpty,
      reason:
          'Un second auteur de `reglements_fournisseur_local` est apparu : '
          'deux chemins d’écriture divergeront, et l’un d’eux n’aura peut-être '
          'pas sa pièce comptable (règle du 31/08/2026).',
    );
  });

  test('AchatsDao LIT les règlements et n’en écrit aucun', () {
    final code = _code(File('lib/features/achats/data/achats_dao.dart'));
    expect(code, contains('reglementsFournisseurLocal'));
    expect(_ecrivains.any((r) => r.hasMatch(code)), isFalse);
  });

  String corpsDeReglerParLeService() {
    final code = _code(File(_dao));
    final debut = code.indexOf(
      'Future<ReglementFournisseur> reglerParLeService(',
    );
    final fin = code.indexOf('Future<ReglementFournisseur> annuler(');
    expect(debut, greaterThanOrEqualTo(0));
    expect(fin, greaterThan(debut));
    return code.substring(debut, fin);
  }

  test('le règlement et sa pièce sont dans la MÊME transaction', () {
    final corps = corpsDeReglerParLeService();

    // Exactement UN insert du règlement, UN appel de pièce.
    expect(RegExp(r'into\(_reglements\)').allMatches(corps), hasLength(1));
    expect(RegExp(r'\.passerEtValider\(').allMatches(corps), hasLength(1));

    // L'insert et la pièce sont À L'INTÉRIEUR du bloc `transaction(`, et le
    // règlement précède la pièce (comme le serveur : il crée le règlement puis
    // passe la pièce, dans `DB::transaction`).
    final debut = corps.indexOf('transaction(');
    final insert = corps.indexOf('into(_reglements)');
    final piece = corps.indexOf('.passerEtValider(');
    expect(debut, greaterThanOrEqualTo(0));
    expect(insert, greaterThan(debut));
    expect(piece, greaterThan(insert));

    // Et rien n'est écrit APRÈS la transaction : la relecture est une lecture.
    final apres = corps.substring(corps.indexOf('return (await parId(id))!;'));
    expect(apres, isNot(contains('into(')));
    expect(apres, isNot(contains('.passerEtValider(')));
  });

  test('le reste dû est relu DANS la transaction, avant l’écriture', () {
    final corps = corpsDeReglerParLeService();
    final debut = corps.indexOf('transaction(');
    final lecture = corps.indexOf('resteDuDe(');
    final insert = corps.indexOf('into(_reglements)');
    expect(lecture, greaterThan(debut));
    expect(lecture, lessThan(insert));
  });

  test('l’annulation n’a AUCUN appelant de production, comme au serveur', () {
    final appelants = <String>[];
    for (final f in _fichiers(lib)) {
      final chemin = _p(f);
      if (chemin == _dao) continue;
      final code = _code(f);
      if (RegExp(
        r'(reglementsFournisseurDaoProvider|ReglementsFournisseurDao|_reglementsObligatoires)[^;]{0,80}\.annuler\(',
        dotAll: true,
      ).hasMatch(code)) {
        appelants.add(chemin);
      }
    }
    expect(
      appelants,
      isEmpty,
      reason:
          'Un appelant de `ReglementsFournisseurDao.annuler` est apparu : la '
          'vue `approvisionnement.blade.php` n’offre AUCUN geste d’annulation '
          '(le service existe, la vue ne l’appelle pas — D257). Retirez ce cas '
          'avec le geste, et portez le libellé de la vue.',
    );
    // `AchatsApi` n'expose pas l'annulation non plus.
    expect(
      _code(File('lib/features/achats/data/achats_api.dart')),
      isNot(contains('.annuler(')),
    );
  });

  test('aucun réseau, aucune synchronisation dans le règlement', () {
    final fichiers = [
      _dao,
      'lib/features/achats/data/piece_du_reglement.dart',
      'lib/features/achats/domain/regles_reglement.dart',
      'lib/features/achats/domain/messages_reglement.dart',
      'lib/features/achats/domain/dettes_fournisseurs.dart',
      'lib/features/achats/presentation/geste_reglement.dart',
      'lib/features/achats/presentation/widgets/modale_reglement.dart',
    ];
    for (final chemin in fichiers) {
      final code = _code(File(chemin)).toLowerCase();
      expect(
        RegExp(
          r"import\s+'package:(dio|http)/|httpclient|localhost|/api/",
        ).hasMatch(code),
        isFalse,
        reason: '$chemin parle au réseau',
      );
      expect(code.contains('statutsync'), isFalse, reason: chemin);
      expect(code.contains("'en_attente"), isFalse, reason: chemin);
    }
  });

  test('le miroir du serveur (lot F4) ne passe aucune pièce', () {
    final code = _code(File(_miroir));
    expect(code, isNot(contains('MoteurComptable')));
    expect(code, isNot(contains('passerEtValider')));
    expect(code, isNot(contains('ecritureId')));
  });
}
