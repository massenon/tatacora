@Timeout(Duration(minutes: 3))
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/archives_poste.dart';
import 'package:tatacora_flutter/features/transverse/domain/registre_archives.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_import.dart';

/// L'onglet « Restaurer » d'Import & Export : le registre DÉRIVÉ des unités et
/// véhicules `hors_service` (aucune table d'archives, comme le web), contre le
/// vrai composant du serveur, puis l'écran.
///
/// Base d'essai privée : `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  late AppDatabase db;
  late ParcDao parc;
  late VehiculeDao vehicules;
  late ArchivesPoste archives;
  final ids = <String, String>{};

  setUp(() async {
    db = await baseImport();
    db.auteurEcriture = () => (login: 'admin', poste: 'P1');
    parc = ParcDao(db);
    vehicules = VehiculeDao(db);
    archives = ArchivesPoste(db, parc: parc, vehicules: vehicules);
    ids.clear();

    final categorie = await parc.creerCategorie(
      libelle: 'Standard',
      capaciteMax: 2,
      tarifBase: 10000,
    );
    for (final numero in ['U1', 'U2', 'U3']) {
      ids[numero] = await parc.creerUnite(
        numero: numero,
        categorieId: categorie.id,
      );
    }
    for (final plaque in ['AB-123', 'CD-456']) {
      final v = await vehicules.enregistrerVehicule(
        immatriculation: plaque,
        categorie: CategorieVehicule.values.first,
        tarifJour: 20000,
      );
      ids[plaque] = v.id;
    }
    // Les archivages passent par les écrivains uniques (ils enfilent).
    await parc.archiver(ids['U1']!);
    await parc.archiver(ids['U2']!);
    await vehicules.archiverVehicule(ids['AB-123']!);
  });

  tearDown(() => db.close());

  String ligne(EntreeArchive e) =>
      '${e.type.code}|${e.libelle}|${e.type.codeModule}|${e.restaure}';

  group('Contre le VRAI composant du serveur', () {
    late List<Map<String, dynamic>> serveur;

    // Le même monde, côté serveur : U1 et U2 archivées, U3 libre ; AB-123
    // archivé, CD-456 disponible.
    final monde = {
      'unites': [
        {'numero': 'U1', 'archivee': true},
        {'numero': 'U2', 'archivee': true},
        {'numero': 'U3', 'archivee': false},
      ],
      'vehicules': [
        {'immatriculation': 'AB-123', 'archive': true},
        {'immatriculation': 'CD-456', 'archive': false},
      ],
    };
    final ops = <Map<String, Object?>>[
      {'op': 'vue', 'filtre': 'restaurables', 'recherche': ''},
      {'op': 'restaurer', 'type': 'unite_hebergement', 'ref': 'U1'},
      {'op': 'restaurer', 'type': 'vehicule', 'ref': 'AB-123'},
      {'op': 'restaurer', 'type': 'vehicule', 'ref': 'ZZZ'},
      for (final f in ['restaurables', 'toutes', 'restaurees'])
        for (final r in ['', 'u', 'M8', 'ab-', 'zzz'])
          {'op': 'vue', 'filtre': f, 'recherche': r},
      {'op': 'libelles'},
    ];

    setUpAll(() async {
      final r = await executerPhp(
        'rejouer_archives.php',
        dossier: 'transverse',
        entree: {'monde': monde, 'ops': ops},
      );
      serveur = [
        for (final e in r['resultats'] as List) e as Map<String, dynamic>,
      ];
    });

    List<Map<String, dynamic>> objets(Object? o) => [
      for (final e in o! as List) e as Map<String, dynamic>,
    ];

    test('le scénario est assez large pour que la comparaison compte', () {
      final initial = objets(serveur[0]['lignes']);
      expect(initial, hasLength(3));
      expect(
        {for (final l in initial) l['module']},
        {'M1', 'M8'},
        reason: 'les deux familles du registre',
      );
      final toutes = objets(serveur[4 + 5]['lignes']); // toutes, recherche ''
      expect(toutes.where((l) => l['restaure'] == true), hasLength(2));
      expect(toutes.where((l) => l['restaure'] == false), hasLength(1));
    });

    test('chaque vue (filtre x recherche) liste les MÊMES éléments', () async {
      // Le serveur reçoit les restaurations de ses ops ; le poste les rejoue.
      await archives.restaurer(TypeArchive.uniteHebergement, ids['U1']!);
      await archives.restaurer(TypeArchive.vehicule, ids['AB-123']!);

      final registre = await archives.registre();
      final ecarts = <String>[];
      for (var i = 4; i < ops.length - 1; i++) {
        final op = ops[i];
        final filtre = FiltreArchives.values.firstWhere(
          (f) => f.name == op['filtre'],
        );
        final poste = [
          for (final e in filtrerArchives(
            registre,
            filtre: filtre,
            recherche: op['recherche']! as String,
          ))
            ligne(e),
        ]..sort();
        final srv = [
          for (final l in objets(serveur[i]['lignes']))
            '${l['type']}|${l['libelle']}|${l['module']}|${l['restaure']}',
        ]..sort();
        if ('$poste' != '$srv') {
          ecarts.add(
            '${op['filtre']} / « ${op['recherche']} »\n  serveur : $srv\n  poste   : $poste',
          );
        }
      }
      expect(ecarts, isEmpty, reason: ecarts.join('\n'));
    });

    test(
      '« toutes » = les archivées PUIS les restaurées, comme array_merge',
      () async {
        await archives.restaurer(TypeArchive.uniteHebergement, ids['U1']!);
        await archives.restaurer(TypeArchive.vehicule, ids['AB-123']!);
        final poste = filtrerArchives(
          await archives.registre(),
          filtre: FiltreArchives.toutes,
        );
        expect([for (final e in poste) e.restaure], [false, true, true]);
        final srv = objets(serveur[4 + 5]['lignes']);
        expect([for (final l in srv) l['restaure']], [false, true, true]);
      },
    );

    test(
      'une restauration porte sa date ET son auteur, des deux côtés',
      () async {
        await archives.restaurer(TypeArchive.uniteHebergement, ids['U1']!);
        final r = (await archives.registre()).restaurees.single;
        expect(r.archiveLe, isNotNull);
        expect(r.archivePar, 'admin');
        for (final l in objets(serveur[4 + 5 + 4 + 5]['lignes'])) {
          // restaurees / '' côté serveur
          if (l['restaure'] == true) {
            expect(l['a_une_date'], true);
            expect(l['par_present'], true);
          }
        }
      },
    );

    test('les gestes : élément restauré, statut final, phrase, élément '
        'inconnu', () async {
      // Unité : revient `libre`, jamais l'état d'avant.
      expect(serveur[1]['statut_apres'], 'libre');
      expect(serveur[2]['statut_apres'], 'disponible');
      final u = await archives.restaurer(
        TypeArchive.uniteHebergement,
        ids['U1']!,
      );
      expect(u, 'U1');
      expect(
        (await (db.select(
          db.unitesHebergementLocal,
        )..where((x) => x.id.equals(ids['U1']!))).getSingle()).statut,
        'libre',
      );
      final v = await archives.restaurer(TypeArchive.vehicule, ids['AB-123']!);
      expect(v, 'AB-123');
      expect(
        (await (db.select(
          db.vehiculesLocal,
        )..where((x) => x.id.equals(ids['AB-123']!))).getSingle()).statut,
        'disponible',
      );
      // Inconnu : le serveur lève (404), le poste refuse en français.
      expect(serveur[3]['erreur'], isNotNull);
      await expectLater(
        archives.restaurer(TypeArchive.vehicule, 'zzz'),
        throwsA(isA<RefusArchive>()),
      );
      await expectLater(
        archives.restaurer(TypeArchive.uniteHebergement, 'zzz'),
        throwsA(
          isA<RefusArchive>().having(
            (e) => e.message,
            'message',
            MessagesArchives.elementIntrouvable,
          ),
        ),
      );
    });

    test('les mots de l\'onglet sont ceux du serveur', () {
      final mots = (serveur.last['mots'] as Map).cast<String, String>();
      expect(TextesImportExport.restaurerTitre, mots['restaurer_titre']);
      expect(TextesImportExport.restaurerTexte, mots['restaurer_texte']);
      expect(TextesImportExport.rechercheArchives, mots['recherche_archives']);
      expect(
        TextesImportExport.filtreRestaurables,
        mots['filtre_restaurables'],
      );
      expect(TextesImportExport.filtreToutes, mots['filtre_toutes']);
      expect(TextesImportExport.filtreRestaurees, mots['filtre_restaurees']);
      expect(TextesImportExport.colElement, mots['col_element']);
      expect(TextesImportExport.colModule, mots['col_module']);
      expect(TextesImportExport.colArchiveLe, mots['col_archive_le']);
      expect(TextesImportExport.colPar, mots['col_par']);
      expect(TextesImportExport.colAction, mots['col_action']);
      expect(TextesImportExport.archivesVide, mots['archives_vide']);
      expect(TextesImportExport.actionRestaurer, mots['action_restaurer']);
      expect(TextesImportExport.badgeRestaure, mots['badge_restaure']);
      expect(MessagesArchives.restauree(':element'), mots['archive_restauree']);
      expect([
        for (final t in TypeArchive.values) t.code,
      ], (serveur.last['types'] as List).cast<String>());
    });
  });

  group('Le registre DÉRIVÉ du poste', () {
    test('seules les unités et véhicules hors_service sont archivés, avec '
        'l\'instant et l\'auteur de l\'archivage', () async {
      final r = await archives.registre();
      expect(
        [for (final e in r.archivees) '${e.libelle}|${e.archivePar}']..sort(),
        ['AB-123|admin', 'U1|admin', 'U2|admin'],
      );
      expect(r.archivees.every((e) => e.archiveLe != null), isTrue);
      expect(r.restaurees, isEmpty);
    });

    test('un élément hors_service SANS opération locale rend « — » (jamais un '
        'nom ou une date devinés)', () async {
      await db.customStatement(
        "UPDATE unites_hebergement_local SET statut = 'hors_service' WHERE numero = 'U3'",
      );
      final u3 = (await archives.registre()).archivees.firstWhere(
        (e) => e.libelle == 'U3',
      );
      expect(u3.archiveLe, isNull);
      expect(u3.archivePar, isNull);
    });

    test('restaurer retire l\'élément des archivées et l\'ajoute aux '
        'restaurées (une seule fois par cycle)', () async {
      await archives.restaurer(TypeArchive.uniteHebergement, ids['U1']!);
      var r = await archives.registre();
      expect(r.archivees.map((e) => e.libelle), isNot(contains('U1')));
      expect(r.restaurees.map((e) => e.libelle), ['U1']);

      // Un second cycle : archiver puis restaurer de nouveau = deux entrées.
      await parc.archiver(ids['U1']!);
      expect(
        (await archives.registre()).archivees.map((e) => e.libelle),
        contains('U1'),
      );
      await archives.restaurer(TypeArchive.uniteHebergement, ids['U1']!);
      r = await archives.registre();
      expect(r.restaurees.map((e) => e.libelle), ['U1', 'U1']);
    });

    test('restaurer un élément qui n\'est PAS archivé n\'invente aucune '
        'restauration passée', () async {
      // Le véhicule CD-456 n'a jamais été archivé : « Remettre en service »
      // (de l'état entretien) ne doit pas se lire « restauré ».
      await vehicules.changerStatut(ids['CD-456']!, StatutVehicule.disponible);
      expect(
        (await archives.registre()).restaurees.map((e) => e.libelle),
        isNot(contains('CD-456')),
      );
    });

    test(
      'la recherche porte sur le libellé OU le code du module, sans casse',
      () async {
        final r = await archives.registre();
        List<String> cherche(String t) =>
            [for (final e in filtrerArchives(r, recherche: t)) e.libelle]
              ..sort();
        expect(cherche('u'), ['U1', 'U2']);
        expect(cherche('m8'), ['AB-123']);
        expect(cherche('M1'), ['U1', 'U2']);
        expect(cherche('zzz'), isEmpty);
        expect(cherche('  ab-  '), ['AB-123']);
      },
    );

    test('le plafond de cent restaurations (limit(100) du serveur)', () {
      final ops = [
        for (var i = 0; i < 120; i++) ...[
          (
            type: TypeArchive.uniteHebergement,
            entiteId: 'u',
            charge: <String, Object?>{'actif': false},
            instant: DateTime(2026, 1, 1, 0, i),
            auteur: 'a',
          ),
          (
            type: TypeArchive.uniteHebergement,
            entiteId: 'u',
            charge: <String, Object?>{'actif': true},
            instant: DateTime(2026, 1, 1, 0, i, 30),
            auteur: 'a',
          ),
        ],
      ];
      final r = composerRegistreArchives(
        unites: const [(id: 'u', libelle: 'U9', statut: 'libre')],
        vehicules: const [],
        operations: ops,
      );
      expect(r.restaurees, hasLength(plafondRestaurees));
      // La plus récente d'abord.
      expect(r.restaurees.first.archiveLe, DateTime(2026, 1, 1, 0, 119, 30));
    });
  });

  group('L\'écran', () {
    Future<void> monter(
      WidgetTester tester, {
      Map<String, String> droits = droitsImportComplets,
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 2600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: surchargesImport(db, droits: droits),
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranImportExport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ie-onglet-restaurer')));
      await tester.pumpAndSettle();
    }

    testWidgets('trois lignes « à restaurer », module en toutes lettres, '
        'auteur et un bouton « Restaurer » par ligne', (tester) async {
      await tester.runAsync(() async {});
      await monter(tester);
      for (final k in ['U1', 'U2', 'AB-123']) {
        expect(
          find.byKey(Key('ie-archive-restaurer-${ids[k]}')),
          findsOneWidget,
        );
      }
      expect(find.text('Hébergement'), findsNWidgets(2));
      expect(find.text('Véhicules'), findsOneWidget);
      expect(find.text('admin'), findsNWidgets(3));
      expect(find.byKey(const Key('ie-archives-vide')), findsNothing);
    });

    testWidgets('« Restaurer » remet l\'élément en place : toast, ligne '
        'retirée, statut écrit, file enfilée', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(Key('ie-archive-restaurer-${ids['U1']}')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('ie-archive-restauree')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'U1 remis en place.',
      );
      expect(
        find.byKey(Key('ie-archive-restaurer-${ids['U1']}')),
        findsNothing,
      );
      expect(
        (await db.select(db.unitesHebergementLocal).get())
            .firstWhere((u) => u.numero == 'U1')
            .statut,
        'libre',
      );
    });

    testWidgets('le filtre « Déjà restaurées » : badge RESTAURÉ, ligne '
        'estompée, aucun bouton', (tester) async {
      await archives.restaurer(TypeArchive.vehicule, ids['AB-123']!);
      await monter(tester);
      await tester.tap(find.byKey(const Key('ie-filtre-archives')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déjà restaurées').last);
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('ie-archive-badge-${ids['AB-123']}')),
        findsOneWidget,
      );
      expect(find.text('RESTAURÉ'), findsOneWidget);
      expect(
        find.byKey(Key('ie-archive-restaurer-${ids['AB-123']}')),
        findsNothing,
      );
      expect(
        tester
            .widget<Opacity>(
              find.byKey(Key('ie-archive-vehicule-${ids['AB-123']}')),
            )
            .opacity,
        0.6,
      );
    });

    testWidgets('la recherche filtre, et rien ne correspond : la phrase du '
        'serveur', (tester) async {
      await monter(tester);
      await tester.enterText(
        find.byKey(const Key('ie-recherche-archives')),
        'zzz',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-archives-vide'))).data,
        'Aucun élément archivé ne correspond.',
      );
    });

    testWidgets('sans le droit d\'écrire sur Paramètres : le registre se lit, '
        'AUCUN bouton « Restaurer »', (tester) async {
      await monter(tester, droits: const {'PARAM': 'L'});
      expect(find.text('U1'), findsOneWidget);
      expect(find.text('Restaurer'), findsOneWidget, reason: 'seul l\'onglet');
      expect(
        find.byKey(Key('ie-archive-restaurer-${ids['U1']}')),
        findsNothing,
      );
    });

    testWidgets('le texte « Sur ce poste : Aucune archive » n\'existe plus', (
      tester,
    ) async {
      await monter(tester);
      expect(find.text('Aucune archive.'), findsNothing);
    });
  });
}
