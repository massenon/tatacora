import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garde : AUCUN code de `lib/` n'écrit l'ANCIENNE `paiements_local`.
///
/// ## Ce que ce fichier gardait, et ce qu'il garde depuis le lot 5
///
/// Jusqu'au 12/10/2026, trois refus datés du 10/10/2026 (M14 « créances
/// clients », M11 « CA encaissé » et « Factures non soldées », D169) reposaient
/// sur ce fait : « `paiements_local` n'a aucun écrivain ». Le lot 5 a donné aux
/// paiements un écrivain — mais UNE AUTRE table : `paiements_facture_local`
/// (centimes entiers, session, statut d'annulation, auteur), seule écrite par
/// `PaiementsFactureDao`. Les trois refus sont levés ; leurs raisons ont été
/// retirées du code et ne sont plus à rouvrir.
///
/// L'ancienne table (schéma du Sprint 0 : `REAL`, ni session, ni statut) reste
/// déclarée — la supprimer exigerait une migration destructive — et RESTE sans
/// écrivain. C'est ce que cette garde tient : le jour où quelqu'un écrirait dans
/// `paiements_local` « parce qu'elle existe », le poste aurait DEUX registres
/// d'encaissements, dont un sans session ni pièce comptable ; le reste dû lirait
/// l'un et pas l'autre. Voir `ecrivains_paiements_facture_test.dart` pour la
/// garde de la table qui, elle, s'écrit.
///
/// Le balayage s'ANCRE sur le texte du code, et prouve qu'il n'est pas vide :
/// un plancher de fichiers, et une copie qui contient un écrivain factice, que
/// le même balayage doit dénoncer (sinon la garde serait verte à vide).
final _ecrivains = <RegExp>[
  RegExp(r'\b(into|update|delete)\(\s*(\w+\.)*paiementsLocal\b'),
  RegExp(r'\bPaiementsLocalCompanion\b'),
  RegExp(r'\bbatch\.\w+\(\s*(\w+\.)*paiementsLocal\b'),
  RegExp(
    r'(INSERT\s+(OR\s+\w+\s+)?INTO|UPDATE|DELETE\s+FROM)\s+paiements_local',
    caseSensitive: false,
  ),
  RegExp(r'\bcustomInsert\b[^;]*paiements_local'),
];

const String _message =
    'Un écrivain de l\'ancienne `paiements_local` est apparu. Les encaissements '
    'de factures s\'écrivent dans `paiements_facture_local`, par '
    '`PaiementsFactureDao` SEUL (avec sa pièce comptable, dans la même '
    'transaction). Deux registres d\'encaissements feraient lire un reste dû '
    'qui ignore l\'un des deux.';

/// Les fichiers de [racine] qui écrivent `paiements_local`, hors code généré.
List<String> ecrivainsDePaiements(Directory racine) {
  final trouves = <String>[];
  for (final f in racine.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
    // Commentaires exclus : on cherche du CODE.
    final code = f
        .readAsLinesSync()
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    if (_ecrivains.any((r) => r.hasMatch(code))) trouves.add(f.path);
  }
  return trouves;
}

int _nombreDeFichiers(Directory racine) => racine
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .length;

void main() {
  test('aucun écrivain de `paiements_local` dans lib/', () {
    final lib = Directory('lib');
    // Plancher : un dossier renommé rendrait le balayage vide, donc vert.
    expect(_nombreDeFichiers(lib), greaterThan(300));
    expect(ecrivainsDePaiements(lib), isEmpty, reason: _message);
  });

  test('la table existe bien (sinon la garde ne garderait rien)', () {
    final tables = File('lib/core/database/tables/facturation_tables.dart');
    expect(tables.readAsStringSync(), contains('class PaiementsLocal'));
  });

  group('preuve par mutation : un écrivain factice dans une COPIE', () {
    late Directory copie;

    setUp(() {
      copie = Directory.systemTemp.createTempSync('paiements_garde_');
      // Une copie fidèle de lib/, pour que le balayage soit celui du vrai.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final cible = File('${copie.path}/${f.path}')
          ..createSync(recursive: true);
        cible.writeAsStringSync(f.readAsStringSync());
      }
    });

    tearDown(() => copie.deleteSync(recursive: true));

    void ajouter(String contenu) =>
        File('${copie.path}/lib/features/faux_encaissement.dart')
          ..createSync(recursive: true)
          ..writeAsStringSync(contenu);

    test('la copie intacte est propre', () {
      expect(ecrivainsDePaiements(copie), isEmpty);
    });

    test('into(paiementsLocal) est dénoncé', () {
      ajouter('Future<void> f(db) => db.into(db.paiementsLocal).insert(x);');
      expect(
        ecrivainsDePaiements(copie).single,
        endsWith('faux_encaissement.dart'),
      );
    });

    test('PaiementsLocalCompanion est dénoncé', () {
      ajouter('final c = PaiementsLocalCompanion.insert(id: 1);');
      expect(ecrivainsDePaiements(copie), hasLength(1));
    });

    test('un INSERT SQL direct est dénoncé', () {
      ajouter("const s = 'INSERT INTO paiements_local (id) VALUES (1)';");
      expect(ecrivainsDePaiements(copie), hasLength(1));
    });

    test('un simple commentaire ne l\'est pas', () {
      ajouter('// into(paiementsLocal) : ne jamais écrire ici.');
      expect(ecrivainsDePaiements(copie), isEmpty);
    });
  });
}
