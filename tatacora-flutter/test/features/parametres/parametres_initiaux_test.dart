@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';
import 'package:tatacora_flutter/features/transverse/data/reinitialisation_locale.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'registre_serveur.dart';

/// Le POSTE VIERGE (Lot J2, directive du PO du 14/10/2026) : les vingt
/// paramètres d'établissement de `ParametresEtablissementSeeder::PARAMETRES`,
/// posés à la création du premier compte et après « Réinitialiser comme
/// neuf », clé ABSENTE seulement.
///
/// ## L'ancre est EXTÉRIEURE (piège 12)
///
/// La liste Dart [parametresEtablissementInitiaux] dit être une copie « À
/// L'IDENTIQUE » du seeder. La comparer à une liste recopiée dans ce test ne
/// vérifierait qu'elle-même : la référence est donc relue en EXÉCUTANT PHP
/// (`tool/parametres/exporter_parametres_initiaux.php`, la constante du
/// seeder par l'autoloader de Composer). PHP absent : ÉCHEC, pas un saut.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Le seeder du serveur, relu par PHP (une fois par exécution).
  List<Map<String, dynamic>>? cache;
  List<Map<String, dynamic>> seeder() {
    final deja = cache;
    if (deja != null) return deja;
    final r = Process.runSync('php', [
      'tool/parametres/exporter_parametres_initiaux.php',
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) {
      fail(
        'Le seeder du serveur n’a pas pu être relu (php, code '
        '${r.exitCode}) : ${r.stderr}. C’est un ÉCHEC, pas un saut.',
      );
    }
    final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    return cache = [
      for (final p in json['parametres'] as List<dynamic>)
        p as Map<String, dynamic>,
    ];
  }

  /// Les quatre clés de la paie que la liste pose (sur les cinq du registre).
  final clesPaie = [
    for (final p in parametresEtablissementInitiaux)
      if (RegistreParametresLocal.clesDeLaPaie.contains(p.cle)) p.cle,
  ];

  group('La liste du poste EST celle du seeder du serveur', () {
    test('le balayage n’est pas vide : 20 paramètres côté serveur', () {
      expect(seeder(), hasLength(20));
      expect(parametresEtablissementInitiaux, hasLength(20));
    });

    test('mêmes clés, mêmes valeurs, mêmes descriptions, dans le même '
        'ordre — EXACTEMENT', () {
      final serveur = seeder();
      for (final (i, p) in parametresEtablissementInitiaux.indexed) {
        final s = serveur[i];
        expect(p.cle, s['cle'], reason: 'rang $i');
        expect(p.valeur, s['valeur'], reason: p.cle);
        expect(p.description, s['description'], reason: p.cle);
      }
      expect(
        [for (final p in parametresEtablissementInitiaux) p.cle],
        [for (final s in serveur) s['cle']],
      );
    });

    test('chaque clé est au registre fermé du poste ; aucune n’est un '
        'secret (motifs relus du serveur)', () {
      final motifs = RegistreServeur.charger().motifsSecret;
      expect(motifs, isNotEmpty);
      for (final p in parametresEtablissementInitiaux) {
        expect(RegistreParametresLocal.existe(p.cle), isTrue, reason: p.cle);
        for (final m in motifs) {
          expect(p.cle, isNot(contains(m)), reason: '${p.cle} ~ $m');
        }
      }
    });

    test('aucun mot de passe SMTP, et PAS le taux de risques '
        'professionnels (PA-53)', () {
      final cles = {for (final p in parametresEtablissementInitiaux) p.cle};
      expect(cles.where((c) => c.startsWith('email_smtp')), {
        'email_smtp_hote',
        'email_smtp_port',
        'email_smtp_securite',
        'email_smtp_utilisateur',
      });
      expect(
        cles.where((c) => RegExp('mot_de_passe|password|mdp').hasMatch(c)),
        isEmpty,
      );
      expect(cles, isNot(contains('taux_cnss_risques_professionnels')));
      expect(clesPaie, [
        'taux_cnss_salarie',
        'taux_cnss_pension_employeur',
        'taux_cnss_prestations_familiales',
        'taux_vps',
      ]);
    });
  });

  group('L’installation sur une base', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase.enMemoire();
      await db.customStatement('SELECT 1');
    });
    tearDown(() => db.close());

    Future<Map<String, String>> paie() async => {
      for (final l in await db.select(db.tauxPaieLocal).get()) l.cle: l.valeur,
    };

    test('base vide : les 20 sont écrites — 4 taux de paie AVEC leur '
        'description dans taux_paie_local, 16 dans parametres_systeme_local, '
        'sans auteur', () async {
      expect(await paie(), isEmpty);
      expect(await ParametresDao(db).lireTout(), isEmpty);

      await ParametresDepotLocal(db).installerParametresInitiaux();

      final taux = await db.select(db.tauxPaieLocal).get();
      expect(
        {for (final t in taux) t.cle: (t.valeur, t.description)},
        {
          for (final p in parametresEtablissementInitiaux)
            if (clesPaie.contains(p.cle)) p.cle: (p.valeur, p.description),
        },
      );
      final ordinaires = await db.select(db.parametresSystemeLocal).get();
      expect(
        {for (final o in ordinaires) o.cle: o.valeur},
        {
          for (final p in parametresEtablissementInitiaux)
            if (!clesPaie.contains(p.cle)) p.cle: p.valeur,
        },
      );
      expect(ordinaires, hasLength(16));
      expect(ordinaires.every((o) => o.modifiePar == null), isTrue);

      // Relu par le dépôt de l'écran Paramètres : les vingt, et rien d'autre.
      expect(await ParametresDepotLocal(db).lireTout(), {
        for (final p in parametresEtablissementInitiaux) p.cle: p.valeur,
      });
    });

    test('une valeur déjà corrigée n’est JAMAIS réécrite ; une seconde '
        'installation ne change rien', () async {
      await semerAuteur(db);
      final depot = ParametresDepotLocal(db);
      await depot.ecrire({
        'taux_tva': '16.00',
        'entreprise_raison_sociale': 'Gîte corrigé',
        'taux_cnss_salarie': '4',
      }, auteurId: auteurEssai);

      await depot.installerParametresInitiaux();
      await depot.installerParametresInitiaux();

      final lu = await depot.lireTout();
      expect(lu['taux_tva'], '16.00');
      expect(lu['entreprise_raison_sociale'], 'Gîte corrigé');
      expect(lu['taux_cnss_salarie'], '4');
      // Les autres sont posées, une fois.
      expect(lu['entreprise_ifu'], '0202011344660');
      expect(lu['taux_vps'], '4');
      expect(lu, hasLength(20));
      expect(await db.select(db.tauxPaieLocal).get(), hasLength(4));
      expect(await db.select(db.parametresSystemeLocal).get(), hasLength(16));
      final tva = await (db.select(
        db.parametresSystemeLocal,
      )..where((p) => p.cle.equals('taux_tva'))).getSingle();
      expect(tva.modifiePar, auteurEssai, reason: 'l’auteur de la correction');
    });

    test('une clé ABSENTE est reposée, les autres ne bougent pas', () async {
      final depot = ParametresDepotLocal(db);
      await depot.installerParametresInitiaux();
      await db.customStatement(
        "DELETE FROM parametres_systeme_local WHERE cle = 'entreprise_rccm'",
      );
      await db.customStatement(
        "DELETE FROM taux_paie_local WHERE cle = 'taux_vps'",
      );
      await depot.installerParametresInitiaux();
      final lu = await depot.lireTout();
      expect(lu['entreprise_rccm'], 'RB/NAT/2020-A-137');
      expect(lu['taux_vps'], '4');
      expect(lu, hasLength(20));
    });
  });

  group('Les deux appelants, et eux seuls', () {
    testWidgets('la création du premier compte pose les vingt paramètres', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final db = AppDatabase.enMemoire();
      addTearDown(db.close);
      tester.view
        ..physicalSize = const Size(900, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [baseLocaleProvider.overrideWithValue(db)],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(
              body: SingleChildScrollView(child: FormulairePremierCompte()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final avant = await tester.runAsync(
        () => ParametresDepotLocal(db).lireTout(),
      );
      expect(avant, isEmpty);

      final champs = find.byType(TextFormField);
      await tester.enterText(champs.at(0), 'n.nabogou');
      await tester.enterText(champs.at(1), 'NABOGOU Noël');
      await tester.enterText(champs.at(2), 'motdepasse-solide');
      await tester.enterText(champs.at(3), 'motdepasse-solide');
      await tester.tap(find.text('Créer le compte administrateur'));

      Map<String, String> lu = const {};
      for (var i = 0; i < 50 && lu.length < 20; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        lu = (await tester.runAsync(
          () => ParametresDepotLocal(db).lireTout(),
        ))!;
      }
      expect(lu, {
        for (final p in parametresEtablissementInitiaux) p.cle: p.valeur,
      });
      final comptes = await tester.runAsync(
        () => db.select(db.utilisateursLocal).get(),
      );
      expect(comptes!.single.login, 'n.nabogou');
    });

    test('« Réinitialiser comme neuf » repose une clé vidée, sans réécrire '
        'une valeur saisie', () async {
      final db = await baseInstallee();
      addTearDown(db.close);
      final depot = ParametresDepotLocal(db);
      await depot.installerParametresInitiaux();
      await depot.ecrire({
        'taux_tva': '16.00',
        'taux_cnss_pension_employeur': '7',
      }, auteurId: auteurEssai);
      await db.customStatement(
        "DELETE FROM parametres_systeme_local WHERE cle = 'entreprise_ifu'",
      );
      await db.customStatement(
        "DELETE FROM taux_paie_local WHERE cle = 'taux_cnss_salarie'",
      );
      await ParametresDao(db).ecrire({
        OptionsSysteme.cleReinitialisationSeeders: '1',
      }, auteurId: null);

      await ReinitialisationLocale(db).executer(role: 'administrateur');

      final lu = await depot.lireTout();
      expect(lu['entreprise_ifu'], '0202011344660', reason: 'reposée');
      expect(lu['taux_cnss_salarie'], '3.6', reason: 'reposé');
      expect(lu['taux_tva'], '16.00', reason: 'saisie, jamais réécrite');
      expect(lu['taux_cnss_pension_employeur'], '7');
      expect(lu.keys.toSet(), {
        for (final p in parametresEtablissementInitiaux) p.cle,
      });
    });

    test('les appelants sont relus dans le code : premier compte et '
        'réinitialisation, jamais une migration ni le démarrage', () {
      final appelants = <String>[
        for (final f in Directory('lib').listSync(recursive: true))
          if (f is File &&
              f.path.endsWith('.dart') &&
              f.readAsStringSync().contains('.installerParametresInitiaux('))
            f.path.replaceAll(r'\', '/'),
      ]..sort();
      expect(appelants, [
        'lib/features/auth/presentation/formulaire_premier_compte.dart',
        'lib/features/transverse/data/reinitialisation_locale.dart',
      ]);
    });

    test('main.dart n’atteint JAMAIS le jeu de démonstration (core/dev), '
        'ni directement ni par ses imports', () {
      final atteints = _fermetureImports('lib/main.dart');
      expect(atteints.length, greaterThan(50), reason: 'balayage non vide');
      expect(atteints, contains('lib/core/di/providers.dart'));
      expect(atteints.where((f) => f.startsWith('lib/core/dev/')), isEmpty);
      // Et la preuve que la sonde VOIT core/dev quand il est importé.
      expect(
        _fermetureImports(
          'lib/main_demo.dart',
        ).where((f) => f.startsWith('lib/core/dev/')),
        isNotEmpty,
      );
    });
  });
}

/// Les fichiers de `lib/` qu'atteint [depart] par ses imports et exports,
/// transitivement (chemins relatifs et `package:tatacora_flutter/`).
Set<String> _fermetureImports(String depart) {
  final motif = RegExp(r'''^\s*(?:import|export|part)\s+['"]([^'"]+)['"]''');
  final vus = <String>{};
  final aVoir = [depart];
  while (aVoir.isNotEmpty) {
    final courant = aVoir.removeLast();
    if (!vus.add(courant)) continue;
    final fichier = File(courant);
    if (!fichier.existsSync()) continue;
    for (final ligne in fichier.readAsLinesSync()) {
      final m = motif.firstMatch(ligne);
      if (m == null) continue;
      final cible = m.group(1)!;
      String? chemin;
      if (cible.startsWith('package:tatacora_flutter/')) {
        chemin = 'lib/${cible.substring('package:tatacora_flutter/'.length)}';
      } else if (!cible.contains(':')) {
        chemin = Uri.file(courant).resolve(cible).toFilePath();
        chemin = _relatif(chemin);
      }
      if (chemin != null) aVoir.add(chemin);
    }
  }
  return vus;
}

String _relatif(String chemin) {
  final normal = chemin.replaceAll(r'\', '/');
  final i = normal.indexOf('lib/');
  return i < 0 ? normal : normal.substring(i);
}
