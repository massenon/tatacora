import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/acces_rapide.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';

import '../../support/vue_blade.dart';

/// Le panneau « Accès rapides » confronté à la VUE (lot 3, 13/10/2026) : le
/// registre PHP `App\Pwa\Support\AccesRapide` (exécuté), le partiel
/// `partials/acces-rapide` (relu) et les vues qui l'incluent (balayées).
///
/// La copie de `core/navigation/acces_rapide.dart` n'est pas une source : le
/// jour où le serveur change une entrée, un libellé, une icône ou la liste des
/// pages qui portent le panneau, ce test rougit et dit au Flutter de suivre.
/// Tout est ÉCHEC, jamais saut : PHP absent ou registre illisible font rougir.

/// Les constantes de `AccesRapide` et `MenuLateral::NAVIGATION`, lues par PHP
/// (un `require` du fichier : les constantes ne demandent pas Laravel).
Map<String, dynamic> _registrePhp() {
  final script = File(
    '${Directory.systemTemp.path}/acces_rapide_registre_$pid.php',
  )..writeAsStringSync(_script);
  final ProcessResult r;
  try {
    r = Process.runSync(
      'php',
      [script.path, VueBlade.racine],
      runInShell: true,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
  } on ProcessException catch (e) {
    fail('PHP est introuvable : le registre ne se vérifie pas.\n$e');
  }
  if (r.exitCode != 0) {
    fail('Registre AccesRapide illisible :\n${r.stdout}${r.stderr}');
  }
  return jsonDecode(r.stdout as String) as Map<String, dynamic>;
}

const _script = r'''<?php
require $argv[1] . "/app/Pwa/Support/AccesRapide.php";
require $argv[1] . "/app/Pwa/Support/MenuLateral.php";
echo json_encode([
  "actions" => \App\Pwa\Support\AccesRapide::ACTIONS_PAR_PAGE,
  "universels" => \App\Pwa\Support\AccesRapide::RACCOURCIS_UNIVERSELS,
  "icones" => \App\Pwa\Support\AccesRapide::ICONES,
  "navigation" => \App\Pwa\Support\MenuLateral::NAVIGATION,
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
''';

/// Une entrée, sous la forme où le serveur l'écrit.
Map<String, dynamic> _commeServeur(EntreeAccesRapide e) => {
  'libelle': e.libelle,
  'route': e.routePwa,
  if (e.params.isNotEmpty) 'params': e.params,
  'module': e.module.code,
  'icone': e.icone,
};

/// Les vues qui portent le panneau, et l'écran Flutter de chacune. Les noms
/// de vue sont écrits sans préfixe ni suffixe (PA-187).
const Map<String, String> _vuesPorteuses = {
  'livewire/accueil': '/tableau-de-bord',
  'hebergement/reservations': '/hebergement/reservations',
  'hebergement/hebergement': '/hebergement',
  'bar/carte': '/bar',
  'restaurant/carte': '/restaurant',
  'restaurant/restauration': '/restaurant/plats',
  'vehicules/locations': '/vehicules',
  'tourisme/departs': '/tourisme',
  'transverse/parametres': '/parametres',
  'depenses/depenses': '/depenses',
  'pos/historique-ventes': '/historique-ventes',
};

void main() {
  final registre = _registrePhp();
  final actionsServeur = registre['actions'] as Map<String, dynamic>;
  final universelsServeur = registre['universels'] as List<dynamic>;
  final iconesServeur = (registre['icones'] as Map<String, dynamic>)
      .cast<String, String>();

  test('la lecture du registre n’est pas vide (plancher)', () {
    expect(actionsServeur.length, greaterThanOrEqualTo(10));
    expect(universelsServeur.length, greaterThanOrEqualTo(8));
    expect(iconesServeur.length, greaterThanOrEqualTo(15));
  });

  group('Le registre du poste EST celui du serveur', () {
    test('« Sur cette page » : mêmes pages, même ordre, mêmes entrées', () {
      expect(actionsParPage.keys.toList(), actionsServeur.keys.toList());
      for (final page in actionsServeur.keys) {
        expect(
          [for (final e in actionsParPage[page]!) _commeServeur(e)],
          actionsServeur[page],
          reason: 'ACTIONS_PAR_PAGE[$page]',
        );
      }
    });

    test('« Aller à » : les huit raccourcis universels, dans l’ordre', () {
      expect([
        for (final e in raccourcisUniversels) _commeServeur(e),
      ], universelsServeur);
    });

    test('les tracés des icônes, au caractère près', () {
      expect(iconesAccesRapide, iconesServeur);
    });

    test('chaque icône désignée par une entrée existe', () {
      for (final e in [
        ...raccourcisUniversels,
        for (final l in actionsParPage.values) ...l,
      ]) {
        expect(iconesAccesRapide.containsKey(e.icone), isTrue, reason: e.icone);
      }
    });
  });

  group('Chaque destination a un écran, ou le dit', () {
    final routeur = File('lib/core/router/app_router.dart').readAsStringSync();
    bool routeServie(String chemin) {
      // Une route imbriquée (`/hebergement` › `reservations`) se lit par son
      // dernier segment, au registre du routeur relu dans son code source
      // (piège 12 : une cohérence s'ancre sur une source extérieure).
      // Le paramètre d'onglet (`?onglet=journal`, D424) n'est pas une route :
      // le hub le lit de `state.uri.queryParameters['onglet']`.
      final route = chemin.split('?').first;
      if (chemin.contains('?onglet=') &&
          !routeur.contains("queryParameters['onglet']")) {
        return false;
      }
      final segments = route.split('/')..removeWhere((s) => s.isEmpty);
      return routeur.contains("path: '$route'") ||
          (segments.length > 1 &&
              routeur.contains("path: '${segments.last}'") &&
              routeur.contains("path: '/${segments.first}'"));
    }

    test('toute route PWA du registre est connue du poste', () {
      for (final e in [
        ...raccourcisUniversels,
        for (final l in actionsParPage.values) ...l,
      ]) {
        expect(
          routesFlutterParRoutePwa.containsKey(e.routePwa),
          isTrue,
          reason: '« ${e.libelle} » → ${e.routePwa} : écran non décidé',
        );
      }
    });

    test('un écran annoncé est une route réellement servie', () {
      for (final cible in routesFlutterParRoutePwa.values.whereType<String>()) {
        expect(routeServie(cible), isTrue, reason: cible);
      }
    });

    test('depuis le portage du hub Comptabilité (14/10/2026, D417/D424), '
        'AUCUNE route du panneau n’est sans écran, et le menu mène au même '
        'écran', () {
      expect(
        routesFlutterParRoutePwa.entries
            .where((e) => e.value == null)
            .map((e) => e.key),
        isEmpty,
      );
      expect(
        toutesLesDestinations.firstWhere((d) => d.nom == 'Comptabilité').route,
        '/comptabilite',
      );
      expect(
        routesFlutterParRoutePwa.entries
            .where((e) => e.key.startsWith('pwa.comptabilite.'))
            .every((e) => e.value!.startsWith('/comptabilite')),
        isTrue,
      );
    });
  });

  group('Les pages qui portent le panneau', () {
    test('ce sont EXACTEMENT les vues qui incluent le partiel', () {
      final racine = Directory('${VueBlade.racine}/resources/views/pwa');
      final porteuses = <String>{};
      for (final f in racine.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.blade.php')) continue;
        final source = f.readAsStringSync();
        if (!source.contains("@include('pwa.partials.acces-rapide')")) {
          continue;
        }
        final relatif = f.path
            .replaceAll(r'\', '/')
            .split('/resources/views/pwa/')
            .last
            .replaceAll('.blade.php', '');
        porteuses.add(relatif);
      }
      // Le corps partagé des cartes porte l'inclusion pour ses DEUX vues.
      expect(porteuses.remove('carte/corps'), isTrue);
      for (final v in const ['bar/carte', 'restaurant/carte']) {
        expect(
          VueBlade.brute(v),
          contains("@include('pwa.carte.corps'"),
          reason: v,
        );
        porteuses.add(v);
      }
      expect(porteuses.length, greaterThanOrEqualTo(8), reason: 'plancher');
      expect(porteuses, _vuesPorteuses.keys.toSet());
    });

    test('le poste rend le bouton sur leurs écrans, et seulement là', () {
      expect(pagesAvecAccesRapide.keys.toSet(), _vuesPorteuses.values.toSet());
    });

    test('chaque page désigne une route PWA réellement déclarée', () {
      final web = VueBlade.fichier('routes/web.php');
      for (final nom in pagesAvecAccesRapide.values) {
        final segments = nom.split('.');
        final prefixe = segments.sublist(0, segments.length - 1).join('.');
        expect(
          web.contains("name('$nom')") ||
              (web.contains("name('$prefixe.')") &&
                  web.contains("name('${segments.last}')")),
          isTrue,
          reason: nom,
        );
      }
    });

    test('le sous-titre est le nom de l’entrée de NAVIGATION qui porte la '
        'route, sinon la marque (`libelleRoute`)', () {
      final navigation = <({String route, String nom})>[];
      for (final e in registre['navigation'] as List<dynamic>) {
        final m = e as Map<String, dynamic>;
        final items = (m['items'] as List<dynamic>?) ?? [m];
        for (final i in items.cast<Map<String, dynamic>>()) {
          navigation.add((
            route: i['route'] as String,
            nom: i['nom'] as String,
          ));
        }
      }
      expect(navigation.length, greaterThanOrEqualTo(20), reason: 'plancher');
      final tout = GardeAcces({
        for (final m in ModuleTatacora.values) m.code: 'C',
      });
      for (final page in pagesAvecAccesRapide.entries) {
        final attendu = navigation
            .where((n) => n.route == page.value)
            .map((n) => n.nom)
            .firstOrNull;
        expect(
          sousTitreAccesRapide(tout, page.key, marque: 'MARQUE'),
          attendu ?? 'MARQUE',
          reason: page.key,
        );
      }
    });
  });

  group('Le partiel, relu', () {
    final partiel = VueBlade.brute('partials/acces-rapide');

    test('ses libellés, au mot', () {
      for (final t in [
        LibellesAccesRapide.titre,
        'title="${LibellesAccesRapide.titreBouton}"',
        'aria-label="${LibellesAccesRapide.etiquetteBouton}"',
        'aria-label="${LibellesAccesRapide.fermer}"',
        LibellesAccesRapide.aucun,
        '>${LibellesAccesRapide.surCettePage}<',
        '>${LibellesAccesRapide.allerA}<',
        '>${LibellesAccesRapide.toucheAlt}</kbd> ${LibellesAccesRapide.plus}',
        '>${LibellesAccesRapide.toucheA}</kbd> '
            '${LibellesAccesRapide.pourOuvrir}',
        '>${LibellesAccesRapide.toucheEchap}</kbd> '
            '${LibellesAccesRapide.pourFermer}',
      ]) {
        expect(partiel, contains(t));
      }
      // Les titres de section sont MIS en capitales par la classe, pas écrits.
      expect(partiel, contains('uppercase tracking-wider'));
      // Le repli du sous-titre : la marque.
      expect(partiel, contains("__('pwa.marque')"));
    });

    test('ses tracés et leurs attributs de trait', () {
      expect(
        partiel,
        contains(
          'stroke-width="2" stroke-linecap="round">'
          '${TracesAccesRapide.eclair}',
        ),
      );
      expect(
        partiel,
        contains(
          'stroke-width="2" stroke-linecap="round">'
          '${TracesAccesRapide.fermer}',
        ),
      );
      expect(
        partiel,
        contains(
          'stroke-width="2" class="opacity-30">${TracesAccesRapide.chevron}',
        ),
      );
      expect(
        partiel,
        contains('stroke-linecap="round" stroke-linejoin="round">{!!'),
        reason: 'les icônes des entrées héritent des DEUX attributs',
      );
    });

    test('ses mesures, reportées dans les jetons', () {
      String px(double v) => v.toInt().toString();
      for (final t in [
        'w-[${px(MesuresAccesRapide.largeurPanneau)}px]',
        'max-w-[${(MesuresAccesRapide.largeurMaxPanneau * 100).round()}vw]',
        'w-14 h-14', // 56 = 14 × 4
        'bottom-6 right-6', // 24 = 6 × 4
        'hover:scale-105 active:scale-95',
        'bg-black/40',
        'shadow-xl',
        'shadow-2xl',
        'duration-200',
        'px-4 py-3.5',
        'py-3 px-2',
        'px-3 mb-1.5 text-[10px] font-bold',
        'px-3 py-2.5 rounded-lg text-left text-[13px] text-slate-700',
        'px-3 py-8 text-center text-[13px] text-slate-400',
        'px-4 py-2.5 border-t border-slate-200',
        'px-1.5 py-0.5 bg-slate-100 rounded',
        'width="${px(MesuresAccesRapide.iconeBoutonFlottant)}"',
        'width="${px(MesuresAccesRapide.iconeFermer)}"',
        'width="${px(MesuresAccesRapide.iconeEntree)}"',
        'width="${px(MesuresAccesRapide.iconeChevron)}"',
        'opacity-${(OpacitesAccesRapide.chevron * 100).round()}',
      ]) {
        expect(partiel, contains(t));
      }
      expect(MesuresAccesRapide.boutonFlottant, 14 * AppSpacing.unit);
      expect(MesuresAccesRapide.margeBoutonFlottant, 6 * AppSpacing.unit);
    });

    test('ses deux écoutes clavier sont au niveau de la FENÊTRE', () {
      expect(
        partiel,
        contains('@keydown.window.alt.a="openDrawer = !openDrawer"'),
      );
      expect(partiel, contains('@keydown.escape.window="openDrawer = false"'));
      expect(partiel, contains('x-data="{ openDrawer: false }"'));
    });

    test('DÉFAUT DE LA VUE épinglé : `group-hover:text-white` sans parent '
        '`group` — l’icône reste dorée au survol (reproduit tel quel ; ce '
        'test rougit le jour où la vue pose `group`)', () {
      expect(partiel, contains('group-hover:text-white'));
      expect(RegExp(r'class="[^"]*\bgroup\b[^-]').hasMatch(partiel), isFalse);
    });

    test('le RBAC du panneau est `moduleAccessible` seul — aucun masquage '
        'par rôle (`ROUTES_MASQUEES_PAR_ROLE` n’y figure pas)', () {
      final classe = VueBlade.fichier('app/Pwa/Support/AccesRapide.php');
      expect(classe, contains('MenuLateral::moduleAccessible('));
      expect(classe, isNot(contains('ROUTES_MASQUEES_PAR_ROLE')));
      expect(classe, isNot(contains('routeMasqueePourRole')));
    });

    test('la barre latérale, ELLE, cache au gérant les quatre routes de '
        '« Aller à » que le panneau lui montre (D346 : l’incohérence est '
        'relue au serveur, pas supposée)', () {
      final menu = VueBlade.fichier('app/Pwa/Support/MenuLateral.php');
      final bloc = RegExp(
        r"'gerant'\s*=>\s*\[([^\]]*)\]",
      ).firstMatch(menu)?.group(1);
      expect(bloc, isNotNull, reason: 'ROUTES_MASQUEES_PAR_ROLE introuvable');
      for (final route in const [
        'pwa.clients',
        'pwa.facturation',
        'pwa.comptabilite.hub',
        'pwa.etats.studio',
      ]) {
        expect(bloc, contains("'$route'"), reason: route);
        expect(
          raccourcisUniversels.any((e) => e.routePwa == route),
          isTrue,
          reason: route,
        );
      }
    });
  });
}
