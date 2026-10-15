import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Les faits de structure que l'encaissement de facture tient — et qui se
/// périment en silence si personne ne les garde (PA-144, piège 9).
///
/// 1. **Un seul auteur** : `PaiementsFactureDao` est le SEUL code de `lib/` qui
///    écrit `paiements_facture_local` (« un référentiel a UN SEUL AUTEUR »).
/// 2. **La pièce comptable est dans la même transaction que le paiement** : le
///    seul `insert` de la table et le seul `passerEtValider` du DAO sont dans le
///    MÊME bloc `transaction(...)` (règle du PO du 31/08/2026). Un balayage de
///    texte ne prouve pas le comportement — `paiements_facture_dao_test.dart`
///    le fait en refusant la pièce et en comptant les lignes — mais il empêche
///    qu'un second chemin d'écriture sans pièce apparaisse sans bruit.
/// 3. **L'annulation n'a aucun appelant de production**, comme au serveur : le
///    service `annuler()` existe, la vue `clients-creances` n'expose aucun geste
///    d'annulation. Un bouton « Annuler » qui apparaîtrait ici sans que la vue
///    le porte serait une invention ; le jour où la vue le portera, ce cas doit
///    être retiré AVEC le geste.
/// 4. **Un seul auteur de la session d'encaissement** : seul `PanierDao` écrit
///    `session_encaissement_id`.
/// 5. **Aucun réseau, aucune synchronisation** : le paiement reste sur le poste.
///
/// Le balayage s'ANCRE sur le texte du code et prouve qu'il n'est pas vide : un
/// plancher de fichiers, et un échantillon fabriqué que les mêmes motifs doivent
/// dénoncer (sinon la garde serait verte à vide).
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*paiementsFactureLocal\b'),
  RegExp(r'\bPaiementsFactureLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*paiementsFactureLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+paiements_facture_local',
    caseSensitive: false,
  ),
  // Le DAO écrit par `into(_paiements)` / `update(_paiements)` : son alias.
  RegExp(r'\b(into|update|delete)\(\s*_paiements\s*\)'),
];

const String _dao = 'lib/features/facturation/data/paiements_facture_dao.dart';

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
      'await db.into(db.paiementsFactureLocal).insert(x);',
      'await (update(db.paiementsFactureLocal)..where(w)).write(y);',
      'final c = PaiementsFactureLocalCompanion.insert(a);',
      "await db.customStatement('INSERT INTO paiements_facture_local VALUES (1)');",
      "await customStatement('update PAIEMENTS_FACTURE_LOCAL set x = 1');",
      'await into(_paiements).insert(z);',
      'await (update(_paiements)..where(w)).write(y);',
    ]) {
      expect(
        _ecrivains.any((r) => r.hasMatch(factice)),
        isTrue,
        reason: 'le motif ne dénonce pas : $factice',
      );
    }
    // Une lecture n'est pas une écriture.
    expect(
      _ecrivains.any((r) => r.hasMatch('final l = select(_paiements);')),
      isFalse,
    );
  });

  test('un seul auteur : PaiementsFactureDao écrit paiements_facture_local', () {
    final auteurs = <String>[];
    for (final f in _fichiers(lib)) {
      if (_p(f).contains('lib/core/database/')) continue;
      if (_ecrivains.any((r) => r.hasMatch(_code(f)))) auteurs.add(_p(f));
    }
    // Le DAO écrit : sans cette ligne, un motif cassé ferait croire que PERSONNE
    // n'écrit — et le test serait vert sur une table sans auteur.
    expect(auteurs, contains(_dao));
    expect(
      auteurs.where((a) => a != _dao),
      isEmpty,
      reason:
          'Un second auteur de `paiements_facture_local` est apparu : deux '
          'chemins d’écriture divergeront, et l’un d’eux n’aura peut-être pas '
          'sa pièce comptable (règle du 31/08/2026).',
    );
  });

  test('le paiement et sa pièce sont dans la MÊME transaction', () {
    final code = _code(File(_dao));
    final encaisser = code.substring(
      code.indexOf('Future<PaiementFacture> encaisser('),
    );
    final fin = encaisser.indexOf('Future<PaiementFacture> annuler(');
    final corps = encaisser.substring(0, fin);

    // Exactement UN insert du paiement, UN appel de pièce.
    expect(RegExp(r'into\(_paiements\)').allMatches(corps), hasLength(1));
    expect(RegExp(r'\.passerEtValider\(').allMatches(corps), hasLength(1));

    // L'insert et la pièce sont À L'INTÉRIEUR du bloc `transaction(`, et le
    // paiement précède la pièce (comme le serveur : il crée le Paiement puis
    // passe la pièce, dans `DB::transaction`).
    final debut = corps.indexOf('transaction(');
    final insert = corps.indexOf('into(_paiements)');
    final piece = corps.indexOf('.passerEtValider(');
    expect(debut, greaterThanOrEqualTo(0));
    expect(insert, greaterThan(debut));
    expect(piece, greaterThan(insert));

    // Et rien n'est écrit APRÈS la transaction : la relecture est une lecture.
    final apres = corps.substring(corps.indexOf('return (await parId(id))!;'));
    expect(apres, isNot(contains('into(')));
    expect(apres, isNot(contains('.passerEtValider(')));
  });

  test('l’annulation n’a AUCUN appelant de production, comme au serveur', () {
    final appelants = <String>[];
    for (final f in _fichiers(lib)) {
      final chemin = _p(f);
      if (chemin == _dao ||
          chemin.endsWith('paiements_facture_repository.dart')) {
        continue;
      }
      // `.annuler(` sur un paiement : le DAO des encaissements ou son dépôt.
      final code = _code(f);
      if (RegExp(
        r'(depotPaiementsFacture|paiementsFactureDao|PaiementsFactureDao|PaiementsFactureRepository)[^;]{0,80}\.annuler\(',
        dotAll: true,
      ).hasMatch(code)) {
        appelants.add(chemin);
      }
    }
    expect(
      appelants,
      isEmpty,
      reason:
          'Un appelant de `PaiementsFactureRepository.annuler` est apparu : la '
          'vue `clients-creances.blade.php` n’offre AUCUN geste d’annulation '
          '(le service existe, la vue ne l’appelle pas). Retirez ce cas avec le '
          'geste, et portez le libellé de la vue.',
    );
  });

  test('seul PanierDao écrit session_encaissement_id', () {
    final auteurs = <String>[];
    for (final f in _fichiers(lib)) {
      if (_p(f).contains('lib/core/database/')) continue;
      if (RegExp(
        r'sessionEncaissementId:\s*Value\(|session_encaissement_id\s*=',
      ).hasMatch(_code(f))) {
        auteurs.add(_p(f));
      }
    }
    expect(auteurs, ['lib/features/pos/data/panier_dao.dart']);
  });

  test('aucun réseau, aucune synchronisation dans l’encaissement', () {
    final fichiers = [
      _dao,
      'lib/features/facturation/domain/creances.dart',
      'lib/features/facturation/domain/regles_encaissement.dart',
      'lib/features/facturation/domain/messages_encaissement.dart',
      'lib/features/facturation/presentation/providers_paiements.dart',
      'lib/features/crm/presentation/widgets/modale_recouvrement.dart',
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
}
