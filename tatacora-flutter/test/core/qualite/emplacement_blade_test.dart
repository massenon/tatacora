import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import '../../support/structure_rendue.dart';
import '../../support/cas_ecrans.dart';

/// PHASE 1A — l'EMPLACEMENT mesuré sur le RENDU, écran par écran. Voir
/// `test/support/structure_rendue.dart` pour la méthode et ses limites, et
/// `docs/AUDIT_FIDELITE_FLUTTER_BLADE_2026-10-08.md` (§4quater) pour le plan.
///
/// ## Ce que ce test protège
///
/// Le comparateur de libellés lit le SOURCE : il dit que les quatre onglets de
/// Clients & Créances sont « portés » parce que leurs noms figurent dans le
/// code. Ici l'écran est monté pour de vrai, et l'on constate qu'aucun n'est
/// cliquable — le texte qui les nomme est une note. Chaque cas ci-dessous est
/// une vue, un jeu de données IDENTIQUE à celui que la vue Blade a rendu
/// (`ExtraireStructureBladeTest`), et l'écran Flutter qui la porte.
///
/// ## Le cliquet
///
/// `tool/conformite_blade/structure/dette-emplacement.json` fige, par vue, le
/// nombre d'éléments bien placés. Il échoue sur un recul ET sur un progrès non
/// resserré (`FIGER_EMPLACEMENT=1`). Ajouter un écran : une entrée de [casEcrans],
/// la vue étant déclarée dans `PAGES` du générateur.

File get _fichierCliquet =>
    File('tool/conformite_blade/structure/dette-emplacement.json');

void main() {
  // La mesure se prouve elle-même : une comparaison d'ordre qui ne verrait pas
  // un désordre ferait passer le cliquet à vide (même exigence que les
  // mutations des autres gardes de conformité).
  group('La comparaison d’ordre', () {
    const a = ElementBlade('h1', 'Titre');
    const b = ElementBlade('button', 'Exporter');
    const c = ElementBlade('th', 'Montant dû');
    ElementRendu r(String t, double top) =>
        ElementRendu(t, Rect.fromLTWH(0, top, 10, 10));

    test('le même ordre est entièrement ordonné', () {
      final m = comparerOrdre(
        [a, b, c],
        [r('Titre', 0), r('Exporter', 50), r('Montant dû', 100)],
      );
      expect(m.ordonnes, 3);
      expect(m.deplaces, isEmpty);
    });

    test('un élément déplacé est compté, pas absent', () {
      final m = comparerOrdre(
        [a, b, c],
        [r('Exporter', 0), r('Titre', 50), r('Montant dû', 100)],
      );
      expect(m.presents, 3);
      expect(m.ordonnes, 2);
      expect(m.deplaces, hasLength(1));
    });

    test('un texte absent est absent, et la casse ne compte pas', () {
      final m = comparerOrdre([a, b], [r('TITRE :', 0)]);
      expect(m.presents, 1);
      expect(m.absents, ['Exporter']);
    });
  });

  group('La consolidation', () {
    Map<String, dynamic> lireJson(String chemin) {
      final f = File(chemin);
      expect(f.existsSync(), isTrue, reason: '$chemin introuvable.');
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }

    test('toute vue portée est mesurée — et le taux global se dit', () {
      final table =
          lireJson('tool/conformite_blade/table-vue-ecran.json')['vues']
              as Map<String, dynamic>;
      final cliquet = lireJson(_fichierCliquet.path);
      final mesurees = cliquet.keys.where((k) => !k.startsWith('_')).toSet();
      final portees = {
        for (final e in table.entries)
          if ((e.value as List<dynamic>).isNotEmpty) e.key,
      };

      // Une vue portée sans mesure d'emplacement est un angle mort : le
      // comparateur de libellés la dit « portée », rien ne dit si elle est
      // bien placée.
      expect(
        portees.difference(mesurees),
        isEmpty,
        reason:
            'Vues portées sans mesure d’emplacement : '
            '${portees.difference(mesurees)}. Ajouter une entrée à `casEcrans` '
            'et à `PAGES` du générateur.',
      );
      expect(
        mesurees.difference(portees),
        isEmpty,
        reason: 'Mesures sans vue portée : ${mesurees.difference(portees)}.',
      );

      var blade = 0;
      var ordonnes = 0;
      for (final k in mesurees) {
        final v = cliquet[k] as Map<String, dynamic>;
        blade += v['blade'] as int;
        ordonnes += v['ordonnes'] as int;
      }
      // ignore: avoid_print
      print(
        '\nEMPLACEMENT GLOBAL — ${mesurees.length} vues portées : '
        '$ordonnes / $blade éléments bien placés = '
        '${(ordonnes * 100 / blade).toStringAsFixed(2)} %',
      );
      expect(blade, greaterThan(1000), reason: 'Mesure vide : plancher.');
    });
  });

  for (final cas in casEcrans) {
    testWidgets('${cas.vue} : emplacement des éléments de la vue', (
      tester,
    ) async {
      final db = AppDatabase.enMemoire();
      addTearDown(db.close);
      switch (cas.jeu) {
        case JeuEcran.clients:
          await semerClients(db);
        case JeuEcran.parc:
          await semerParc(db);
        case JeuEcran.vide:
          break;
      }

      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final surcharges = [
        baseLocaleProvider.overrideWithValue(db),
        droitsProvider.overrideWithValue(GardeAcces.depuisJson(cas.droits)),
        ...cas.surcharges(db),
      ];
      if (cas.parRouteur) {
        final routeur = GoRouter(
          initialLocation: '/ecran',
          routes: [
            GoRoute(path: '/ecran', builder: (_, _) => cas.ecran()),
            GoRoute(path: '/connexion', builder: (_, _) => const SizedBox()),
            GoRoute(path: '/hebergement', builder: (_, _) => const SizedBox()),
          ],
        );
        addTearDown(routeur.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: surcharges,
            child: MaterialApp.router(
              theme: AppTheme.clair,
              routerConfig: routeur,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      } else {
        await tester.pumpWidget(
          ProviderScope(
            overrides: surcharges,
            child: MaterialApp(
              theme: AppTheme.clair,
              home: Scaffold(body: cas.ecran()),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      final onglets = structureBlade(cas.vue);
      for (final e in onglets.entries) {
        expect(
          e.value.length,
          greaterThan(4),
          reason: 'Relevé de ${e.key} trop court : extraction cassée.',
        );
      }

      // Le socle COMMUN à toutes les variantes (en-tête, indicateurs, barre
      // d'onglets) se mesure une fois ; le reste est propre à chacune.
      final listes = onglets.values.toList();
      var commun = 0;
      while (listes.every(
        (l) =>
            l.length > commun &&
            normaliser(l[commun].texte) == normaliser(listes[0][commun].texte),
      )) {
        commun++;
      }

      final premiere = onglets.keys.first;
      final resultats = <String, MesureEmplacement>{
        '(commun)': comparerOrdre(
          listes[0].sublist(0, commun),
          collecterRendu(tester),
        ),
      };
      final ongletsNonCliquables = <String>[];

      // Les libellés de tous les boutons d'onglet de la vue.
      final boutons = <String, String>{
        for (final l in listes)
          for (final x in l)
            if (x.type == 'onglet' && x.cle != null) x.cle!: x.texte,
        ...cas.activations,
      };
      for (final libelle in boutons.values) {
        if (!ongletCliquable(libelle) &&
            !ongletsNonCliquables.contains(libelle)) {
          ongletsNonCliquables.add(libelle);
        }
      }

      for (final e in onglets.entries) {
        final propres = e.value.sublist(commun);
        final libelle = boutons[e.key];

        if (e.key == premiere) {
          resultats[e.key] = comparerOrdre(propres, collecterRendu(tester));
        } else if (libelle != null && ongletCliquable(libelle)) {
          await tester.tap(trouverTexte(libelle).first);
          await tester.pumpAndSettle();
          resultats[e.key] = comparerOrdre(propres, collecterRendu(tester));
        } else {
          // Aucun contrôle tactile ne porte son libellé : son contenu n'est
          // pas atteignable, donc il n'est pas rendu.
          resultats[e.key] = MesureEmplacement(
            blade: propres.length,
            presents: 0,
            ordonnes: 0,
            deplaces: const [],
            absents: [for (final p in propres) p.texte],
          );
        }
      }

      // Libère l'écran (minuteurs compris) avant la fin du cas.
      await tester.pumpWidget(const SizedBox());

      final totalBlade = resultats.values.fold<int>(0, (s, m) => s + m.blade);
      final totalOrdonnes = resultats.values.fold<int>(
        0,
        (s, m) => s + m.ordonnes,
      );

      // ignore: avoid_print
      print(
        '\nEMPLACEMENT — ${cas.vue}\n'
        '${resultats.entries.map((e) => '  ${e.key.padRight(14)} '
            'vue=${e.value.blade} présents=${e.value.presents} '
            'ordonnés=${e.value.ordonnes} '
            'déplacés=${e.value.deplaces.length}').join('\n')}\n'
        '  TAUX STRICT D’EMPLACEMENT : '
        '${(totalOrdonnes * 100 / totalBlade).toStringAsFixed(2)} % '
        '($totalOrdonnes / $totalBlade)\n'
        '  Onglets NON cliquables (${ongletsNonCliquables.length}) : '
        '${ongletsNonCliquables.join(' | ')}\n'
        '  Déplacés : '
        '${resultats.values.expand((m) => m.deplaces).take(8).join(' | ')}'
        '${Platform.environment['DETAIL_EMPLACEMENT'] == '1' ? '\n  Absents par variante :\n${resultats.entries.map((e) => '   [${e.key}] ${e.value.absents.join(' | ')}').join('\n')}' : ''}',
      );

      final courant = {
        'blade': totalBlade,
        'ordonnes': totalOrdonnes,
        'ongletsNonCliquables': ongletsNonCliquables.length,
      };

      if (Platform.environment['FIGER_EMPLACEMENT'] == '1') {
        final existant = _fichierCliquet.existsSync()
            ? jsonDecode(_fichierCliquet.readAsStringSync())
                  as Map<String, dynamic>
            : <String, dynamic>{};
        existant['_lisez-moi'] =
            'PRODUIT par FIGER_EMPLACEMENT=1 flutter test test/core/qualite/'
            'emplacement_blade_test.dart. Éléments de la vue bien placés, par '
            'écran. Le test échoue sur un recul et sur un progrès non '
            'resserré.';
        existant[cas.vue] = courant;
        _fichierCliquet.writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(existant)}\n',
        );
        return;
      }

      expect(
        _fichierCliquet.existsSync(),
        isTrue,
        reason: 'Le cliquet d’emplacement est introuvable (échec, pas saut).',
      );
      final fige =
          (jsonDecode(_fichierCliquet.readAsStringSync())
                  as Map<String, dynamic>)[cas.vue]
              as Map<String, dynamic>?;
      expect(
        fige,
        isNotNull,
        reason: '${cas.vue} n’a pas d’entrée au cliquet : FIGER_EMPLACEMENT=1.',
      );

      expect(
        totalOrdonnes,
        greaterThanOrEqualTo(fige!['ordonnes'] as int),
        reason:
            'L’emplacement a RECULÉ : $totalOrdonnes éléments bien placés '
            'contre ${fige['ordonnes']} figés.',
      );
      expect(
        totalOrdonnes,
        lessThanOrEqualTo(fige['ordonnes'] as int),
        reason:
            'Progrès non resserré : $totalOrdonnes contre '
            '${fige['ordonnes']}. FIGER_EMPLACEMENT=1 pour le figer.',
      );
      expect(
        ongletsNonCliquables.length,
        fige['ongletsNonCliquables'],
        reason: 'Le nombre d’onglets non cliquables a changé.',
      );
    });
  }
}
