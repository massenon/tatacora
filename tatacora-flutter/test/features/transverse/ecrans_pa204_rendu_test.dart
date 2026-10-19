@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_aide_a_propos.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_contact_editeur.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_journal_audit.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_roles_permissions.dart';

import '../facturation/support/outils_encaissement.dart';

/// Les sept écrans portés le 14/10/2026 (PA-204, D417–D423) : chacun se rend
/// sans lever, porte le TITRE de sa vue (`<h1>`, clé de `lang/fr/pwa.php`), et
/// n'affiche AUCUNE référence interne — un numéro de point ouvert (`PA-…`),
/// de décision (`D4…`) ou un nom de table (`…_local`) est une note de
/// développeur, pas un texte pour le Gîte.
///
/// Le titre est relu de la VUE par PHP (`__()` exécuté) : un titre recopié ici
/// ne vérifierait que lui-même. Et une garde transverse refuse, dans tout
/// `lib/`, le bloc « Ce que cet écran ne rend pas » que le PO a fait retirer.
void main() {
  /// Les titres de la vue, résolus par le PHP du serveur.
  late final Map<String, String> titres;

  setUpAll(() async {
    const cles = {
      'comptabilite': 'pwa.comptabilite.titre_hub',
      'import_export': 'pwa.import_export.titre',
      'roles': 'pwa.roles.titre',
      'profil': 'pwa.profil.titre',
      'journal_audit': 'pwa.journal_audit.titre',
      'aide': 'pwa.aide.titre',
      'contact': 'pwa.contact.titre',
    };
    final lang = File('../tatacora-api/lang/fr/pwa.php').absolute.path;
    final code = StringBuffer(r'$t = require $argv[1];');
    for (final e in cles.entries) {
      final chemin = e.value.split('.').skip(1).map((s) => "['$s']").join();
      code.write(" echo '${e.key}=' . \$t$chemin . PHP_EOL;");
    }
    final r = await Process.run('php', [
      '-r',
      code.toString(),
      lang,
    ], stdoutEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    titres = {
      for (final l in (r.stdout as String).split('\n'))
        if (l.contains('='))
          l.split('=').first: l.substring(l.indexOf('=') + 1).trimRight(),
    };
    // Prouvé NON VIDE : sept titres lus, sinon la garde passerait à vide.
    expect(titres, hasLength(cles.length));
  });

  late AppDatabase db;
  setUp(() async => db = await baseEncaissement());
  tearDown(() => db.close());

  const tousDroits = {
    'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
    'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
    'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
  };

  /// Tous les textes RENDUS (Text, RichText, champs), jamais le code source.
  List<String> textesRendus(WidgetTester tester) => [
    for (final w in tester.allWidgets)
      ?switch (w) {
        Text(:final data?) => data,
        Text(:final textSpan?) => textSpan.toPlainText(),
        RichText(:final text) => text.toPlainText(),
        EditableText(:final controller) => controller.text,
        _ => null,
      },
  ];

  final interdit = RegExp(r'PA-\d|\bD\d|_local');

  final ecrans = <String, Widget>{
    'comptabilite': const EcranComptabilite(),
    'import_export': const EcranImportExport(),
    'roles': const EcranRolesPermissions(),
    'profil': const EcranMonProfil(),
    'journal_audit': const EcranJournalAudit(),
    'aide': const EcranAideAPropos(),
    'contact': const EcranContactEditeur(),
  };

  for (final MapEntry(key: cle, value: ecran) in ecrans.entries) {
    testWidgets('« $cle » : titre de la vue, aucune référence interne '
        'affichée', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: surchargesEncaissement(db, droits: tousDroits),
          child: MaterialApp(
            theme: AppTheme.clair,
            home: Scaffold(body: ecran),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final textes = textesRendus(tester);
      expect(textes, contains(titres[cle]), reason: 'titre de la vue');
      expect(
        textes.where(interdit.hasMatch).toList(),
        isEmpty,
        reason: 'référence interne affichée',
      );
    });
  }

  test('aucun écran ne rend « Ce que cet écran ne rend pas » (blocs retirés '
      'par le PO) — seuls les commentaires peuvent encore le nommer', () {
    final phrase = RegExp(r'Ce que cet [ée]cran ne rend pas');
    final fautifs = <String>[];
    var relus = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      relus++;
      final lignes = f.readAsLinesSync();
      for (final (i, l) in lignes.indexed) {
        if (l.trimLeft().startsWith('//')) continue;
        if (phrase.hasMatch(l)) fautifs.add('${f.path}:${i + 1}');
      }
    }
    // Plancher : un dossier renommé rendrait le balayage vide, donc vert.
    expect(relus, greaterThan(400));
    expect(fautifs, isEmpty);
  });
}
