import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';

import '../../support/coquille_montee.dart';
import '../../support/structure_rendue.dart';

/// PHASE 1B — la BARRE LATÉRALE mesurée sur le RENDU, pour chacun des rôles.
///
/// Côté Laravel, `ExtraireBarreLateraleTest` connecte chaque rôle et relève la
/// barre que la PWA rend (`structure/barre-laterale.json`) : entrées
/// épinglées, titres de groupe, entrées, badges, entrée allumée, tracé des
/// icônes. Ici, `CoquilleApplication` est montée avec la MÊME matrice de
/// droits et l'on confronte :
///
///  1. la SÉQUENCE des textes (groupes, entrées, badges), dans l'ordre ;
///  2. l'ENSEMBLE des entrées visibles — où se voit le masquage par rôle
///     (`MenuLateral::ROUTES_MASQUEES_PAR_ROLE`) ;
///  3. l'ÉTAT ACTIF — une et une seule entrée allumée par page ;
///  4. la PARTITION des icônes — quelles entrées partagent le même dessin ;
///  5. les entrées INERTES (sans route) et le pied (identité, déconnexion).
///
/// ## Le cliquet
///
/// `structure/dette-barre-laterale.json` fige les écarts (par rôle). Il
/// échoue sur un recul et sur un progrès non resserré
/// (`FIGER_BARRE=1 flutter test test/core/qualite/barre_laterale_blade_test.dart`).
///
/// ## Limites
///
/// Ni tailles, ni couleurs, ni espacements : Phase 1D.

File get _fichierDette =>
    File('tool/conformite_blade/structure/dette-barre-laterale.json');

Map<String, dynamic> _lireBarre() {
  final f = File('tool/conformite_blade/structure/barre-laterale.json');
  if (!f.existsSync()) {
    fail(
      'Barre latérale introuvable : ${f.path}.\n'
      'La générer : STRUCTURE_BLADE_SORTIE=../tatacora-flutter/tool/'
      'conformite_blade/structure php artisan test '
      '--filter=ExtraireBarreLateraleTest (depuis tatacora-api/).',
    );
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// Les jetons de lecture de la barre Blade : titre de groupe, nom, badge.
List<String> _jetonsBlade(List<dynamic> entrees) => [
  for (final e in entrees.cast<Map<String, dynamic>>()) ...[
    e['nom'] as String,
    if (e['badge'] != null) e['badge'] as String,
  ],
];

Future<void> _monter(
  WidgetTester tester, {
  required String role,
  required Map<String, dynamic> droits,
  required String routeActive,
}) => monterCoquille(
  tester,
  role: role,
  droits: droits,
  routeActive: routeActive,
  // 1 400 → 1 500 le 21/10/2026 : « Congés & Plannings » (35 px) a fait passer
  // « Paramètres » sous le pied pour un administrateur, qui se comptait alors
  // MANQUANT alors qu'il est atteignable par défilement. La mesure porte sur
  // l'ordre et l'ensemble des entrées, pas sur la hauteur de la fenêtre.
  taille: const Size(1600, 1500),
);

List<DestinationMenu> get _toutes => toutesLesDestinations;

/// Les textes de la barre (zone de 264 px, sous la barre supérieure), dans
/// l'ordre de lecture, SANS le pied — et seulement ceux ENTIÈREMENT visibles
/// au-dessus de lui.
///
/// ⚠ Jusqu'au 15/10/2026, la limite était « 90 px au-dessus de
/// Déconnexion », une estimation de la hauteur du pied. L'entrée « Comptes
/// utilisateurs » (ajout du PO du 14/10/2026) a descendu « Paramètres » de
/// 35 px : entièrement visible (bas à 1 257 px, pied à 1 262 px), il tombait
/// sous l'estimation et se comptait MANQUANT. La limite est désormais le haut
/// du pied lui-même (`_PiedBarreLaterale`), mesuré sur le rendu.
List<String> _jetonsFlutter(WidgetTester tester) {
  final tous = collecterRendu(
    tester,
  ).where((e) => e.boite.left < 264 && e.boite.top >= 64).toList();
  final pied = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_PiedBarreLaterale',
  );
  expect(pied, findsOneWidget, reason: 'pied de la barre latérale introuvable');
  final limite = tester.getRect(pied).top;
  return [
    for (final e in tous)
      if (e.boite.bottom <= limite) e.texte,
  ];
}

/// Les noms d'entrées ALLUMÉES : le fond « actif » de `_LienLateral`.
List<String> _actifsFlutter(WidgetTester tester) {
  final actifs = find.byWidgetPredicate(
    (w) =>
        w is Material &&
        w.color == AppColors.goldActif &&
        w.borderRadius != null,
  );
  final noms = <String>[];
  for (var i = 0; i < actifs.evaluate().length; i++) {
    final textes = find.descendant(
      of: actifs.at(i),
      matching: find.byType(Text),
    );
    if (textes.evaluate().isNotEmpty) {
      noms.add(tester.widget<Text>(textes.first).data ?? '');
    }
  }
  return noms;
}

void main() {
  final barre = _lireBarre();
  final roles = (barre['roles'] as Map<String, dynamic>).keys.toList();
  final resultats = <String, Map<String, int>>{};

  test('les rôles et la barre sont relevés', () {
    expect(roles.length, greaterThanOrEqualTo(11), reason: 'plancher');
    for (final r in roles) {
      final role =
          (barre['roles'] as Map<String, dynamic>)[r] as Map<String, dynamic>;
      final entrees =
          (role['barre'] as Map<String, dynamic>)['entrees'] as List<dynamic>;
      expect(entrees, isNotEmpty, reason: 'Barre vide pour $r.');
    }
  });

  for (final role in roles) {
    testWidgets('barre latérale — rôle « $role »', (tester) async {
      final donnees =
          (barre['roles'] as Map<String, dynamic>)[role]
              as Map<String, dynamic>;
      final entreesBlade =
          (donnees['barre'] as Map<String, dynamic>)['entrees']
              as List<dynamic>;

      await _monter(
        tester,
        role: role,
        droits: donnees['droits'] as Map<String, dynamic>,
        routeActive: '/tableau-de-bord',
      );

      final attendu = _jetonsBlade(entreesBlade);
      final rendu = _jetonsFlutter(tester);
      final mesure = comparerOrdre(
        [for (final t in attendu) ElementBlade('t', t)],
        [
          for (var i = 0; i < rendu.length; i++)
            ElementRendu(rendu[i], Rect.fromLTWH(0, i * 20.0, 10, 10)),
        ],
      );

      final nomsBlade = {
        for (final e in entreesBlade.cast<Map<String, dynamic>>())
          if (e['type'] != 'groupe') normaliser(e['nom'] as String),
      };
      final nomsFlutter = {
        for (final d in _toutes)
          if (rendu.any((t) => normaliser(t) == normaliser(d.nom)))
            normaliser(d.nom),
      };
      final manquants = nomsBlade.difference(nomsFlutter);
      final enTrop = nomsFlutter.difference(nomsBlade);

      final inertes = [
        for (final e in entreesBlade.cast<Map<String, dynamic>>())
          if (e['type'] != 'groupe')
            if (_toutes
                .where(
                  (d) => normaliser(d.nom) == normaliser(e['nom'] as String),
                )
                .any((d) => d.route == null))
              e['nom'] as String,
      ];

      // ignore: avoid_print
      print(
        '\nBARRE — $role : ${mesure.blade} jetons, '
        '${mesure.presents} présents, ${mesure.ordonnes} dans l’ordre | '
        'entrées manquantes ${manquants.length}, en trop ${enTrop.length}, '
        'inertes ${inertes.length}'
        '${manquants.isEmpty ? '' : '\n  manquantes : ${manquants.join(' | ')}'}'
        '${enTrop.isEmpty ? '' : '\n  en trop : ${enTrop.join(' | ')}'}'
        '${mesure.absents.isEmpty ? '' : '\n  jetons absents : ${mesure.absents.take(6).join(' | ')}'}',
      );

      resultats[role] = {
        'jetons': mesure.blade,
        'ordonnes': mesure.ordonnes,
        'manquantes': manquants.length,
        'enTrop': enTrop.length,
        'inertes': inertes.length,
      };
    });
  }

  testWidgets('barre latérale — pied de barre (identité, déconnexion)', (
    tester,
  ) async {
    final donnees =
        (barre['roles'] as Map<String, dynamic>)['administrateur']
            as Map<String, dynamic>;
    final pied =
        (donnees['barre'] as Map<String, dynamic>)['pied']
            as Map<String, dynamic>;

    await _monter(
      tester,
      role: 'administrateur',
      droits: donnees['droits'] as Map<String, dynamic>,
      routeActive: '/tableau-de-bord',
    );
    final rendu = collecterRendu(
      tester,
    ).where((e) => e.boite.left < 264).map((e) => normaliser(e.texte)).toSet();

    final attendus = [
      for (final l in pied['lignes'] as List<dynamic>) l as String,
      pied['deconnexion'] as String,
    ];
    final absents = [
      for (final a in attendus)
        if (!rendu.contains(normaliser(a))) a,
    ];
    // ignore: avoid_print
    print(
      '\nPIED DE BARRE — ${attendus.length - absents.length}/'
      '${attendus.length} textes : absents ${absents.join(' | ')}',
    );
    resultats['_pied'] = {
      'attendus': attendus.length,
      'absents': absents.length,
    };
  });

  testWidgets('barre latérale — état actif et icônes (administrateur)', (
    tester,
  ) async {
    final donnees =
        (barre['roles'] as Map<String, dynamic>)['administrateur']
            as Map<String, dynamic>;
    final entrees =
        (donnees['barre'] as Map<String, dynamic>)['entrees'] as List<dynamic>;
    final actifBlade = barre['actif'] as Map<String, dynamic>;

    var visitees = 0;
    var concordent = 0;
    final divergences = <String>[];

    for (final nom in actifBlade.keys) {
      final d = _toutes
          .where((x) => normaliser(x.nom) == normaliser(nom))
          .firstOrNull;
      // Une entrée inerte (sans route) est comptée dans « inertes ».
      if (d == null || d.route == null) {
        continue;
      }
      visitees++;
      await _monter(
        tester,
        role: 'administrateur',
        droits: donnees['droits'] as Map<String, dynamic>,
        routeActive: d.route!,
      );
      final attendu = [
        for (final n in actifBlade[nom] as List<dynamic>)
          normaliser(n as String),
      ];
      final obtenu = [for (final n in _actifsFlutter(tester)) normaliser(n)];
      if (attendu.length == obtenu.length && attendu.every(obtenu.contains)) {
        concordent++;
      } else {
        divergences.add('$nom → attendu $attendu, obtenu $obtenu');
      }
    }

    // La PARTITION des icônes : quelles entrées partagent un même dessin.
    Map<String, Set<String>> partition(Iterable<(String, String)> paires) {
      final p = <String, Set<String>>{};
      for (final (nom, cle) in paires) {
        p.putIfAbsent(cle, () => {}).add(normaliser(nom));
      }
      return p;
    }

    final partBlade = partition([
      for (final e in entrees.cast<Map<String, dynamic>>())
        if (e['type'] != 'groupe') (e['nom'] as String, e['icone'] as String),
    ]);
    final partFlutter = partition([
      for (final e in entrees.cast<Map<String, dynamic>>())
        if (e['type'] != 'groupe')
          for (final d in _toutes.where(
            (x) => normaliser(x.nom) == normaliser(e['nom'] as String),
          ))
            // Le TRACÉ de la vue (12/10/2026) : la partition se compare
            // désormais sur le dessin lui-même, plus sur une icône Material.
            (e['nom'] as String, d.icone.trace),
    ]);
    String signature(Map<String, Set<String>> p) {
      final groupes = [
        for (final s in p.values.where((s) => s.length > 1))
          (s.toList()..sort()).join('+'),
      ]..sort();
      return groupes.join(' / ');
    }

    final sigBlade = signature(partBlade);
    final sigFlutter = signature(partFlutter);
    final partitionIdentique = sigBlade == sigFlutter;

    // ignore: avoid_print
    print(
      '\nÉTAT ACTIF — $concordent/$visitees pages concordent'
      '${divergences.isEmpty ? '' : '\n  ${divergences.take(6).join('\n  ')}'}'
      '\nICÔNES — partition ${partitionIdentique ? 'IDENTIQUE' : 'DIFFÉRENTE'}'
      '${partitionIdentique ? '' : '\n  vue    : $sigBlade\n  flutter: $sigFlutter'}',
    );

    resultats['_actif'] = {'visitees': visitees, 'concordent': concordent};
    resultats['_icones'] = {'identique': partitionIdentique ? 1 : 0};
  });

  test('consolidation et cliquet', () {
    final parRole = {
      for (final e in resultats.entries)
        if (!e.key.startsWith('_')) e.key: e.value,
    };
    expect(parRole.length, roles.length, reason: 'Un rôle n’a pas été mesuré.');

    var jetons = 0;
    var ordonnes = 0;
    for (final v in parRole.values) {
      jetons += v['jetons']!;
      ordonnes += v['ordonnes']!;
    }
    final courant = <String, dynamic>{
      'roles': {for (final e in parRole.entries) e.key: e.value},
      'pied': resultats['_pied'],
      'actif': resultats['_actif'],
      'icones': resultats['_icones'],
    };

    // ignore: avoid_print
    print(
      '\nBARRE LATÉRALE GLOBALE — $ordonnes / $jetons jetons dans l’ordre = '
      '${(ordonnes * 100 / jetons).toStringAsFixed(2)} % sur ${roles.length} rôles',
    );

    if (Platform.environment['FIGER_BARRE'] == '1') {
      _fichierDette.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'_lisez-moi': 'PRODUIT par FIGER_BARRE=1 flutter test test/core/qualite/barre_laterale_blade_test.dart. Cliquet de la barre latérale (Phase 1B) : recul et progrès non resserré font échouer.', ...courant})}\n',
      );
      return;
    }

    expect(_fichierDette.existsSync(), isTrue, reason: 'Cliquet introuvable.');
    final fige =
        jsonDecode(_fichierDette.readAsStringSync()) as Map<String, dynamic>;
    expect(
      jsonEncode(courant),
      jsonEncode({for (final k in courant.keys) k: fige[k]}),
      reason:
          'La barre latérale a changé par rapport au cliquet : un recul est '
          'une régression, un progrès se fige (FIGER_BARRE=1).',
    );
  });
}
