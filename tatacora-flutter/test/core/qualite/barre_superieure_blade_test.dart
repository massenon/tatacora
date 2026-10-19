import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/acces_rapide.dart';

import '../../support/coquille_montee.dart';
import '../../support/structure_rendue.dart';

/// PHASE 1C — la BARRE SUPÉRIEURE mesurée sur le RENDU, pour chaque rôle.
///
/// Côté Laravel, `ExtraireBarreSuperieureTest` connecte chaque rôle et relève
/// le `<header>` que la PWA rend (`structure/barre-superieure.json`) dans trois
/// états : la barre au repos, le menu de compte ouvert, le panneau de
/// notifications ouvert. Ici, `CoquilleApplication` est montée avec la même
/// matrice de droits ; l'on relève ses textes, ses info-bulles et ses invites
/// de champ, dans l'ordre de lecture, et l'on confronte par plus longue
/// sous-suite commune.
///
/// ## Ce que cette mesure dit de la barre
///
/// Depuis le lot 1 « coquille » (12/10/2026, D306-D315), la barre Flutter
/// porte la bascule plein écran, le logo, l'identité, l'indicateur de caisse,
/// « Vente » et le menu de compte. La recherche globale, la pastille réseau
/// et la cloche n'existent pas : chacune est un **absent** de la mesure. Les
/// entrées du menu de compte se mesurent après ouverture. (Ce paragraphe
/// disait « ne porte que le logo, l'identité et le menu de compte » : vrai
/// avant le lot 1.)
///
/// ## Deux limites connues de la mesure (12/10/2026, D79, D319)
///
/// - Hors production, la pastille « Environnement : … » est un élément EN
///   TROP de plus : le cliquet est figé SANS `--dart-define` (« en trop » 2,
///   3 pour `rh`) ; en `ENV=production` il vaut 1 (2 pour `rh`) et ce test
///   ROUGIT. La suite se lance sans define.
/// - Le tri de [_relever] n'est PAS un ordre total : deux éléments sont « sur
///   la même ligne » à moins de 14 px de centre, ce qui n'est pas transitif
///   (marque à 24, barre à 32, ligne de localisation à 44). Le résultat du tri
///   dépend alors de l'ordre d'entrée des éléments, et l'ajout ou le retrait
///   d'UN élément (la pastille) déplace « Vente — encaisser… » et
///   « Natitingou… » : c'est pourquoi le menu du barman vaut 17/24 sans
///   define et 18/24 en production. Mesuré, non corrigé.
///
/// ## Le cliquet
///
/// `structure/dette-barre-superieure.json` fige les résultats ; il échoue sur
/// toute variation (`FIGER_HAUT=1` pour refiger après un progrès).
///
/// Limites : ni tailles, ni couleurs, ni espacements (Phase 1D).

File get _fichierDette =>
    File('tool/conformite_blade/structure/dette-barre-superieure.json');

Map<String, dynamic> _lireBarre() {
  final f = File('tool/conformite_blade/structure/barre-superieure.json');
  if (!f.existsSync()) {
    fail(
      'Barre supérieure introuvable : ${f.path}.\n'
      'La générer : STRUCTURE_BLADE_SORTIE=../tatacora-flutter/tool/'
      'conformite_blade/structure php artisan test '
      '--filter=ExtraireBarreSuperieureTest (depuis tatacora-api/).',
    );
  }
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// Les textes, info-bulles et invites de champ de la fenêtre, dans l'ordre de
/// lecture.
List<ElementRendu> _relever(WidgetTester tester) {
  final elements = <ElementRendu>[...collecterRendu(tester)];
  final bulles = find.byType(Tooltip);
  for (var i = 0; i < bulles.evaluate().length; i++) {
    final f = bulles.at(i);
    final message = tester.widget<Tooltip>(f).message;
    // Le relevé de la vue est celui du `<header>` (et de son menu) : le
    // bouton flottant « Accès rapides », inclus APRÈS `</main>` par la vue,
    // n'y figure pas. Son infobulle est écartée PAR SON IDENTITÉ (son
    // message), et AVANT le tri (13/10/2026, lot 3, D352 puis D355) : le tri
    // ci-dessous n'est pas transitif (D319), et un élément de plus, même
    // filtré ensuite, changeait l'ordre des autres — barman 17 → 18,
    // magasinier 17 → 18, cuisine 16 → 15 dans le menu de compte : un effet
    // de mesure, pas un changement de barre. Un premier filtre retirait tout
    // élément qui RECOUVRAIT le bouton : il aurait aussi effacé un élément
    // légitime posé au même endroit (un menu ouvert jusqu'en bas).
    if (message == LibellesAccesRapide.titreBouton) continue;
    if (message != null && message.trim().isNotEmpty) {
      elements.add(ElementRendu(message, tester.getRect(f)));
    }
  }
  // Une barre est UNE ligne : on range par CENTRE vertical (tolérance 14 px),
  // pas par haut de boîte — une icône de 22 px et un texte de 12 px alignés au
  // centre n'ont pas le même haut, et se liraient dans le désordre.
  elements.sort((a, b) {
    final dy = a.boite.center.dy - b.boite.center.dy;
    if (dy.abs() > 14) {
      return dy < 0 ? -1 : 1;
    }
    return a.boite.left.compareTo(b.boite.left);
  });
  return elements;
}

/// La seule barre supérieure : tout ce qui est au-dessus de 64 px.
List<ElementRendu> _barre(List<ElementRendu> tout) => [
  for (final e in tout)
    if (e.boite.top < 64) e,
];

void main() {
  final donnees = _lireBarre();
  final roles = (donnees['roles'] as Map<String, dynamic>).keys.toList();
  final resultats = <String, Map<String, dynamic>>{};

  List<ElementBlade> variante(String role, String nom) => [
    for (final x
        in ((donnees['roles'] as Map<String, dynamic>)[role]
                as Map<String, dynamic>)[nom]
            as List<dynamic>)
      ElementBlade(
        (x as Map<String, dynamic>)['type'] as String,
        x['texte'] as String,
      ),
  ];

  Map<String, dynamic> droitsDe(String role) =>
      _lireDroits()[role] as Map<String, dynamic>;

  test('les rôles et les variantes sont relevés', () {
    expect(roles.length, greaterThanOrEqualTo(11), reason: 'plancher');
    for (final r in roles) {
      for (final v in const ['barre', 'menu-profil', 'cloche']) {
        expect(
          variante(r, v).length,
          greaterThan(5),
          reason: 'Relevé vide : $r / $v.',
        );
      }
    }
  });

  for (final role in roles) {
    testWidgets('barre supérieure — rôle « $role »', (tester) async {
      await monterCoquille(
        tester,
        role: role,
        droits: droitsDe(role),
        routeActive: '/tableau-de-bord',
      );

      // --- Variante « barre » -------------------------------------------
      final repos = _barre(_relever(tester));
      final mesureBarre = comparerOrdre(variante(role, 'barre'), repos);
      final bladeBarre = {
        for (final e in variante(role, 'barre')) normaliser(e.texte),
      };
      final enTrop = [
        for (final e in repos)
          if (!bladeBarre.contains(normaliser(e.texte))) e.texte,
      ];

      // --- Variante « menu-profil » : on ouvre le menu --------------------
      final bouton = find.byType(PopupMenuButton<String>);
      expect(bouton, findsOneWidget, reason: 'Le menu de compte est absent.');
      await tester.tap(bouton);
      await tester.pumpAndSettle();
      final avecMenu = _relever(
        tester,
      ).where((e) => e.boite.left >= 264 || e.boite.top < 64).toList();
      final mesureMenu = comparerOrdre(variante(role, 'menu-profil'), avecMenu);

      // --- Variante « cloche » : aucune cloche, aucun panneau --------------
      final mesureCloche = comparerOrdre(variante(role, 'cloche'), repos);

      // ignore: avoid_print
      print(
        '\nHAUT — $role : barre ${mesureBarre.ordonnes}/${mesureBarre.blade} '
        '(en trop ${enTrop.length}) | menu ${mesureMenu.ordonnes}/'
        '${mesureMenu.blade} | cloche ${mesureCloche.ordonnes}/'
        '${mesureCloche.blade}'
        '${role == 'administrateur' ? '\n  barre absents : ${mesureBarre.absents.join(' | ')}\n  menu absents : ${mesureMenu.absents.join(' | ')}\n  en trop : ${enTrop.join(' | ')}' : ''}',
      );

      resultats[role] = {
        'barre': [mesureBarre.blade, mesureBarre.ordonnes],
        'menu': [mesureMenu.blade, mesureMenu.ordonnes],
        'cloche': [mesureCloche.blade, mesureCloche.ordonnes],
        'enTrop': enTrop.length,
      };
    });
  }

  test('consolidation et cliquet', () {
    expect(resultats.length, roles.length, reason: 'Un rôle n’est pas mesuré.');

    int somme(String cle, int i) =>
        resultats.values.fold(0, (s, v) => s + (v[cle] as List<int>)[i]);

    final tableau = {
      'barre': [somme('barre', 0), somme('barre', 1)],
      'menu': [somme('menu', 0), somme('menu', 1)],
      'cloche': [somme('cloche', 0), somme('cloche', 1)],
    };
    // ignore: avoid_print
    print(
      '\nBARRE SUPÉRIEURE GLOBALE — '
      'repos ${tableau['barre']![1]}/${tableau['barre']![0]}, '
      'menu de compte ${tableau['menu']![1]}/${tableau['menu']![0]}, '
      'cloche ${tableau['cloche']![1]}/${tableau['cloche']![0]} '
      '(éléments de la vue retrouvés dans l’ordre)',
    );

    final courant = <String, dynamic>{'roles': resultats, 'total': tableau};

    if (Platform.environment['FIGER_HAUT'] == '1') {
      _fichierDette.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert({'_lisez-moi': 'PRODUIT par FIGER_HAUT=1 flutter test test/core/qualite/barre_superieure_blade_test.dart. Cliquet de la barre supérieure (Phase 1C).', ...courant})}\n',
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
          'La barre supérieure a changé par rapport au cliquet : un recul est '
          'une régression, un progrès se fige (FIGER_HAUT=1).',
    );
  });
}

/// Les droits par rôle, relus du relevé de la barre latérale (même matrice
/// que `POST /login`, une seule source).
Map<String, dynamic> _lireDroits() {
  final f = File('tool/conformite_blade/structure/barre-laterale.json');
  if (!f.existsSync()) {
    fail('Droits introuvables : ${f.path} (échec, pas saut).');
  }
  final roles =
      (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>)['roles']
          as Map<String, dynamic>;
  return {
    for (final e in roles.entries)
      e.key: (e.value as Map<String, dynamic>)['droits'],
  };
}
