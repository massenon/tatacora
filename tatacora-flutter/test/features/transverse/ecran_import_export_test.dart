import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/transverse/data/sauvegardes_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';

import '../../support/selecteur_essai.dart';
import 'support/outils_import.dart';

/// L'écran Import & Export — onglets « Importer les données » et
/// « Sauvegardes de la base » — monté sur une VRAIE base en mémoire, ses
/// enregistrements passant par la vraie fenêtre « Enregistrer sous »
/// remplacée ([SelecteurEssai]) : le test emprunte le chemin de production
/// (composition, nom suggéré, type, toast) et relit ce qui « aurait été
/// écrit ».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory poste;

  setUp(() async {
    db = await baseImport();
    poste = Directory.systemTemp.createTempSync('poste_ie_');
  });
  tearDown(() async {
    await db.close();
    poste.deleteSync(recursive: true);
  });

  Future<SelecteurEssai> monter(
    WidgetTester tester, {
    Map<String, String> droits = droitsImportComplets,
    String? moduleInitial,
    FichierLu? fichier,
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final selecteur = SelecteurEssai(lu: fichier);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...surchargesImport(
            db,
            droits: droits,
            cheminPoste: '${poste.path}/poste.json',
          ),
          ...selecteur.surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: EcranImportExport(moduleInitial: moduleInitial)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selecteur;
  }

  /// Laisse du VRAI temps passer (base, fichier temporaire) jusqu'à ce que
  /// [condition] tienne — au plus quelques secondes.
  Future<void> attendre(WidgetTester tester, bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> cliquer(WidgetTester tester, Finder cible) async {
    await tester.ensureVisible(cible);
    await tester.pumpAndSettle();
    await tester.tap(cible);
    await tester.pumpAndSettle();
  }

  /// Les options du sélecteur de module, telles que le widget les porte.
  List<(String?, String)> optionsModule(WidgetTester tester) {
    final liste = tester.widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(const Key('ie-module-import')),
        matching: find.byType(DropdownButton<String>),
      ),
    );
    return [for (final i in liste.items!) (i.value, (i.child as Text).data!)];
  }

  Future<int> compter(WidgetTester tester, String table) async =>
      (await tester.runAsync(() => compterLignes(db, table)))!;

  group('« 1. Choisir le module à alimenter »', () {
    testWidgets('droits complets : les huit modules, dans l’ordre du '
        'serveur, nommés « code — nom »', (tester) async {
      await monter(tester);
      expect(optionsModule(tester), [
        for (final c in casImport) (c.cle, '${c.code} — ${c.nom}'),
      ]);
      expect(find.byKey(const Key('ie-aucun-module')), findsNothing);
    });

    testWidgets('seuls les modules où la session ÉCRIT sont listés (la '
        'lecture ne suffit pas)', (tester) async {
      await monter(
        tester,
        droits: const {
          'PARAM': 'C',
          'M3': 'C',
          'M8': 'C',
          'M6': 'L',
          'M1': 'L',
          'M9': 'L',
        },
      );
      expect(optionsModule(tester), [
        ('m3-clients', 'M3 — Clients'),
        ('m8-vehicules', 'M8 — Parc de véhicules'),
      ]);
    });

    testWidgets('aucun module en écriture : la liste est vide et l’écran le '
        'dit', (tester) async {
      await monter(tester, droits: const {'PARAM': 'C', 'M3': 'L'});
      expect(optionsModule(tester), isEmpty);
      expect(find.byKey(const Key('ie-aucun-module')), findsOneWidget);
    });
  });

  group('« Télécharger le modèle » passe par « Enregistrer sous »', () {
    for (final cas in casImport) {
      testWidgets('${cas.code} : nom du serveur, type CSV, BOM et en-tête du '
          'module, aucune ligne de données ; toast', (tester) async {
        final selecteur = await monter(tester, moduleInitial: cas.cle);
        await cliquer(tester, find.byKey(const Key('ie-modele')));
        await attendre(tester, () => selecteur.ecrits.isNotEmpty);

        final f = selecteur.dernier;
        expect(
          f.nom,
          cas.cle == 'm6-stocks'
              ? 'modele_import_articles.csv'
              : 'modele_import_${cas.cle}.csv',
        );
        expect(f.type, TypeFichierEnregistre.csv);
        expect(f.dossierInitial, SelecteurEssai.dossierDocuments);
        expect(f.octets.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
        expect(utf8.decode(f.octets.sublist(3)), '${cas.entete}\r\n');
        expect(find.byKey(const Key('ie-modele-enregistre')), findsOneWidget);
      });
    }

    testWidgets('« Annuler » dans la fenêtre : rien n’est écrit, aucun toast', (
      tester,
    ) async {
      final selecteur = await monter(tester, moduleInitial: 'm3-clients');
      selecteur.annuler = true;
      await cliquer(tester, find.byKey(const Key('ie-modele')));
      await attendre(tester, () => false);
      expect(selecteur.ecrits, isEmpty);
      expect(find.byKey(const Key('ie-modele-enregistre')), findsNothing);
    });
  });

  group('Dépôt, contrôle, import — le parcours réel', () {
    final cas = casImport.firstWhere((c) => c.cle == 'm9-tourisme');

    FichierLu lu(String contenu) => FichierLu(
      nom: 'circuits.csv',
      octets: Uint8List.fromList(utf8.encode(contenu)),
    );

    testWidgets('« Valider et contrôler » n’écrit RIEN ; la confirmation '
        'importe, le dit, et l’historique le garde', (tester) async {
      await monter(
        tester,
        moduleInitial: cas.cle,
        fichier: lu(cas.fichier(cas.valides, bom: true)),
      );
      final avant = await compter(tester, cas.table);

      await cliquer(tester, find.byKey(const Key('ie-zone-depot')));
      expect(find.byKey(const Key('ie-fichier-selectionne')), findsOneWidget);
      await cliquer(tester, find.byKey(const Key('ie-valider')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-rapport')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-rapport-verdict'))).data,
        TextesImportExport.rapportConforme,
      );
      expect(
        await compter(tester, cas.table),
        avant,
        reason: 'le contrôle simule, il n’écrit pas',
      );

      await cliquer(tester, find.byKey(const Key('ie-confirmer-import')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-import-fait')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-import-fait'))).data,
        TextesImportExport.importFait(2, cas.nom, 0),
      );
      expect(await compter(tester, cas.table), avant + 2);
      final noms = await tester.runAsync(
        () => valeursDe(db, cas.table, cas.colonne),
      );
      expect(noms, containsAll(cas.cles));
      expect(find.byKey(const Key('ie-historique-vide')), findsNothing);
    });

    testWidgets('un fichier fautif : le rapport nomme la LIGNE, rien n’est '
        'écrit, et rien ne se confirme', (tester) async {
      await monter(
        tester,
        moduleInitial: cas.cle,
        fichier: lu(cas.fichier([cas.valides[0], cas.fautive])),
      );
      final avant = await compter(tester, cas.table);
      await cliquer(tester, find.byKey(const Key('ie-zone-depot')));
      await cliquer(tester, find.byKey(const Key('ie-valider')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-rapport')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-rapport-verdict'))).data,
        TextesImportExport.rapportNonConforme,
      );
      final rapport = find.byKey(const Key('ie-rapport'));
      expect(
        find.descendant(
          of: rapport,
          matching: find.textContaining(TextesImportExport.rapportLigne(3)),
          skipOffstage: false,
        ),
        findsWidgets,
      );
      expect(find.byKey(const Key('ie-confirmer-import')), findsNothing);
      expect(await compter(tester, cas.table), avant);
    });
  });

  testWidgets('« aucun moteur d’import » n’apparaît sur AUCUN onglet', (
    tester,
  ) async {
    await monter(tester, moduleInitial: 'm1-hebergement');
    final motif = RegExp('aucun moteur d.import', caseSensitive: false);
    for (final onglet in ['importer', 'sauvegardes', 'restaurer', 'seeders']) {
      await cliquer(tester, find.byKey(Key('ie-onglet-$onglet')));
      expect(
        find.textContaining(motif, skipOffstage: false),
        findsNothing,
        reason: onglet,
      );
    }
  });

  test('« aucun moteur d’import » n’est écrit dans AUCUNE chaîne de lib/ '
      '(hors commentaires)', () {
    final motif = RegExp('aucun moteur d.import', caseSensitive: false);
    final fautifs = <String>[];
    var lus = 0;
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      lus++;
      for (final (i, ligne) in f.readAsLinesSync().indexed) {
        final code = ligne.trimLeft();
        if (code.startsWith('//')) continue;
        if (motif.hasMatch(code)) fautifs.add('${f.path}:${i + 1}');
      }
    }
    expect(lus, greaterThan(300), reason: 'balayage non vide');
    expect(fautifs, isEmpty);
  });

  group('« Sauvegardes de la base »', () {
    testWidgets('« Générer une sauvegarde de la base » : une base SQLite '
        'VALIDE, RANGÉE sur le poste, bandeau vert, ligne « non téléchargée »', (
      tester,
    ) async {
      await tester.runAsync(
        () => db.customStatement(
          'INSERT INTO clients_local (id, nom, telephone, type_client) '
          "VALUES ('cli-1', 'KORA', '+229 01 00 00 00 01', 'particulier')",
        ),
      );
      await monter(tester);
      await cliquer(tester, find.byKey(const Key('ie-onglet-sauvegardes')));
      expect(find.byKey(const Key('ie-sauvegardes-vide')), findsOneWidget);
      await cliquer(tester, find.byKey(const Key('ie-generer-sauvegarde')));
      await attendre(
        tester,
        () => find
            .byKey(const Key('ie-sauvegarde-generee'))
            .evaluate()
            .isNotEmpty,
      );

      final fichiers = Directory('${poste.path}/sauvegardes')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.sqlite'))
          .toList();
      expect(fichiers, hasLength(1));
      final nom = fichiers.single.path.split(RegExp(r'[\\/]')).last;
      expect(
        nom,
        matches(
          RegExp(
            r'^tatacora_sauvegarde_\d{4}-\d{2}-\d{2}_\d{2}h\d{2}m\d{2}\.sqlite$',
          ),
        ),
      );
      final octets = fichiers.single.readAsBytesSync();
      expect(ascii.decode(octets.sublist(0, 15)), 'SQLite format 3');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('ie-sauvegarde-generee')))
            .data,
        startsWith('Sauvegarde générée : $nom ('),
      );
      // Le bandeau vert, la ligne de la liste « non téléchargée », le compteur.
      expect(find.byKey(const Key('ie-bandeau-generee')), findsOneWidget);
      expect(find.text('Sauvegarde générée'), findsOneWidget);
      expect(find.byKey(Key('ie-sauvegarde-$nom')), findsOneWidget);
      expect(find.textContaining('non téléchargée'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-kpi-sauvegardes'))).data,
        '1',
      );

      final relu = await tester.runAsync(() async {
        final base = sqlite3.open(
          fichiers.single.path,
          mode: OpenMode.readOnly,
        );
        try {
          return base
              .select("SELECT nom FROM clients_local WHERE id = 'cli-1'")
              .single['nom'];
        } finally {
          base.close();
        }
      });
      expect(relu, 'KORA');
    });

    testWidgets('« Télécharger » écrit la copie par la fenêtre ET la marque '
        'téléchargée ; annuler dans la fenêtre ne marque rien', (tester) async {
      final selecteur = await monter(tester);
      await cliquer(tester, find.byKey(const Key('ie-onglet-sauvegardes')));
      await cliquer(tester, find.byKey(const Key('ie-generer-sauvegarde')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-bandeau-generee')).evaluate().isNotEmpty,
      );
      final nom = Directory('${poste.path}/sauvegardes')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.sqlite'))
          .path
          .split(RegExp(r'[\\/]'))
          .last;

      // Annulé : rien n'est écrit, la copie reste « non téléchargée ».
      selecteur.annuler = true;
      await cliquer(
        tester,
        find.byKey(const Key('ie-bandeau-generee-telecharger')),
      );
      await attendre(tester, () => false);
      expect(selecteur.ecrits, isEmpty);
      expect(find.textContaining('non téléchargée'), findsOneWidget);

      selecteur.annuler = false;
      await cliquer(tester, find.byKey(Key('ie-telecharger-$nom')));
      await attendre(
        tester,
        () => find
            .byKey(const Key('ie-sauvegarde-telechargee'))
            .evaluate()
            .isNotEmpty,
      );
      expect(selecteur.dernier.type, TypeFichierEnregistre.sauvegarde);
      expect(selecteur.dernier.nom, nom);
      expect(
        ascii.decode(selecteur.dernier.octets.sublist(0, 15)),
        'SQLite format 3',
      );
      expect(
        File('${poste.path}/sauvegardes/$nom.telechargee').existsSync(),
        isTrue,
      );
      expect(find.textContaining('non téléchargée'), findsNothing);
      expect(find.byKey(const Key('ie-bandeau-generee')), findsNothing);
    });

    testWidgets('une copie rangée jamais téléchargée : le bandeau OR de la '
        'vue, puis plus rien une fois téléchargée', (tester) async {
      final selecteur = await monter(tester);
      final copie = await tester.runAsync(
        () => SauvegardesPoste(
          db,
          cheminConfiguration: () async => '${poste.path}/poste.json',
        ).generer(),
      );
      await cliquer(tester, find.byKey(const Key('ie-onglet-sauvegardes')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-bandeau-rappel')).evaluate().isNotEmpty,
      );
      expect(
        find.text('Sauvegarde en attente de téléchargement'),
        findsOneWidget,
      );
      expect(find.textContaining("n'a pas été téléchargée."), findsOneWidget);
      await cliquer(
        tester,
        find.byKey(const Key('ie-bandeau-rappel-telecharger')),
      );
      await attendre(tester, () => selecteur.ecrits.isNotEmpty);
      expect(selecteur.dernier.nom, copie!.nom);
      await attendre(
        tester,
        () => find.byKey(const Key('ie-bandeau-rappel')).evaluate().isEmpty,
      );
      expect(find.byKey(const Key('ie-bandeau-rappel')), findsNothing);
    });

    testWidgets('« Retirer » une copie jamais téléchargée : la confirmation '
        'forte de la vue', (tester) async {
      await monter(tester);
      await cliquer(tester, find.byKey(const Key('ie-onglet-sauvegardes')));
      await cliquer(tester, find.byKey(const Key('ie-generer-sauvegarde')));
      await attendre(
        tester,
        () => find.byKey(const Key('ie-bandeau-generee')).evaluate().isNotEmpty,
      );
      final nom = Directory('${poste.path}/sauvegardes')
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.path.endsWith('.sqlite'))
          .path
          .split(RegExp(r'[\\/]'))
          .last;

      // « Retirer » d'une copie jamais téléchargée : la modale du maître.
      await cliquer(tester, find.byKey(Key('ie-retirer-$nom')));
      expect(find.byKey(const Key('ie-modale-retrait')), findsOneWidget);
      expect(find.text('Sauvegarde jamais téléchargée'), findsOneWidget);
      expect(
        find.text(
          'La retirer la perd définitivement : il n\'en existe aucune copie ailleurs.',
        ),
        findsOneWidget,
      );
      // Annuler : la copie reste.
      await cliquer(tester, find.byKey(const Key('ie-retrait-annuler')));
      expect(File('${poste.path}/sauvegardes/$nom').existsSync(), isTrue);

      // Confirmer : la copie et son témoin disparaissent, la liste est vide.
      await cliquer(tester, find.byKey(Key('ie-retirer-$nom')));
      await cliquer(tester, find.byKey(const Key('ie-retrait-confirmer')));
      await attendre(
        tester,
        () => find
            .byKey(const Key('ie-sauvegarde-retiree'))
            .evaluate()
            .isNotEmpty,
      );
      expect(File('${poste.path}/sauvegardes/$nom').existsSync(), isFalse);
      expect(find.byKey(const Key('ie-sauvegardes-vide')), findsOneWidget);
      expect(
        find.text(
          'Aucune sauvegarde. Utilisez le bouton ci-dessus pour en générer une.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('« Exporter une table existante » : utilisateurs_local '
        'n’est PAS proposée', (tester) async {
      await monter(tester);
      await cliquer(tester, find.byKey(const Key('ie-onglet-sauvegardes')));
      await cliquer(tester, find.byKey(const Key('ie-exporter-table')));
      expect(find.byKey(const Key('ie-modale-export-table')), findsOneWidget);
      final liste = tester.widget<DropdownButton<String>>(
        find.descendant(
          of: find.byKey(const Key('ie-export-table-choix')),
          matching: find.byType(DropdownButton<String>),
        ),
      );
      final tables = [for (final i in liste.items!) i.value];
      expect(tables, isNot(contains('utilisateurs_local')));
      expect(tables, containsAll(['clients_local', 'circuits_local']));
      expect(tables, hasLength(db.allTables.length - 1));
    });
  });
}
