import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// PHASE 1A — l'EMPLACEMENT, mesuré sur le rendu et non sur le source.
///
/// `tool/conformite_blade/t-blade-flutter.js` lit le code : il dit ce qui
/// MANQUE, jamais si ce qui est là est bien PLACÉ, et une chaîne citée en
/// commentaire ou en note le satisfait autant qu'un texte affiché. Ce module
/// fait le contraire : il MONTE l'écran dans un test de widget, relève chaque
/// texte réellement affiché avec sa position, et le confronte à la structure
/// que la vue Blade a RENDUE (`ExtraireStructureBladeTest`, côté
/// `tatacora-api`), dans l'ordre du document.
///
/// ## Ce que cette mesure couvre — et ne couvre pas
///
/// Couvre : la présence EXACTE d'un texte de la vue, son ORDRE de lecture
/// (de haut en bas, puis de gauche à droite), et le caractère CLIQUABLE d'un
/// onglet. Ne couvre pas : le nombre de colonnes d'une grille, les tailles,
/// l'alignement au pixel — c'est la Phase 1D (captures comparées). Un taux
/// d'emplacement de 100 % ne dit donc PAS « identique à la vue » : il dit
/// « rien n'est dans le désordre ».
///
/// ## Tout est ÉCHEC, jamais saut
///
/// Une structure introuvable fait rougir le test (une garde dont la source
/// manque passe à vide).

/// Un texte affiché, avec sa boîte.
class ElementRendu {
  const ElementRendu(this.texte, this.boite);

  final String texte;
  final Rect boite;
}

/// Un texte relevé sur la vue Blade rendue.
class ElementBlade {
  const ElementBlade(this.type, this.texte, {this.cle});

  final String type;
  final String texte;

  /// Pour un bouton d'onglet : la clé que la vue passe à `$set('onglet', …)`.
  final String? cle;
}

/// Le texte tel que les deux côtés le comparent : l'apostrophe typographique
/// est la droite, les espaces insécables des espaces, la casse et les
/// ponctuations de fin (`:` `*`) ne comptent pas.
String normaliser(String brut) {
  var t = brut
      .replaceAll('’', "'")
      .replaceAll(' ', ' ')
      .replaceAll(' ', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase();
  t = t.replaceAll(RegExp(r'[\s:*]+$'), '');
  return t;
}

/// Tous les textes visibles, dans l'ordre de lecture.
List<ElementRendu> collecterRendu(WidgetTester tester) {
  final bruts = <ElementRendu>[];

  final textes = find.byType(Text);
  for (var i = 0; i < textes.evaluate().length; i++) {
    final f = textes.at(i);
    final w = tester.widget<Text>(f);
    final contenu = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (contenu.trim().isEmpty) continue;
    bruts.add(ElementRendu(contenu, tester.getRect(f)));
  }

  final champs = find.byType(TextField);
  for (var i = 0; i < champs.evaluate().length; i++) {
    final f = champs.at(i);
    final w = tester.widget<TextField>(f);
    final invite = w.decoration?.hintText;
    if (invite != null && invite.trim().isNotEmpty) {
      bruts.add(ElementRendu(invite, tester.getRect(f)));
    }
  }

  // Lecture : de haut en bas par LIGNES (6 px de tolérance), puis de gauche à
  // droite — l'ordre dans lequel une personne parcourt la page.
  bruts.sort((a, b) {
    final dy = a.boite.top - b.boite.top;
    if (dy.abs() > 6) return dy < 0 ? -1 : 1;
    return a.boite.left.compareTo(b.boite.left);
  });
  return bruts;
}

/// Comme [collecterRendu], mais la boîte d'un texte est celle de ses GLYPHES
/// peints (`RenderParagraph.getBoxesForSelection`), pas celle du widget : un
/// `Text` centré dans une colonne étirée occupe toute la largeur, alors que le
/// navigateur mesure le texte lui-même (`Range.getBoundingClientRect`). Les
/// champs gardent leur boîte de champ, comme la vue (`<input>`).
List<ElementRendu> collecterGlyphes(WidgetTester tester) {
  final elements = <ElementRendu>[];

  final textes = find.byType(Text);
  for (var i = 0; i < textes.evaluate().length; i++) {
    final f = textes.at(i);
    final w = tester.widget<Text>(f);
    final contenu = w.data ?? w.textSpan?.toPlainText() ?? '';
    if (contenu.trim().isEmpty) continue;
    final rendu = tester.renderObject(f);
    if (rendu is! RenderParagraph) {
      elements.add(ElementRendu(contenu, tester.getRect(f)));
      continue;
    }
    final boites = rendu.getBoxesForSelection(
      TextSelection(
        baseOffset: 0,
        extentOffset: rendu.text.toPlainText().length,
      ),
    );
    if (boites.isEmpty) continue;
    var union = boites.first.toRect();
    for (final b in boites.skip(1)) {
      union = union.expandToInclude(b.toRect());
    }
    final origine = rendu.localToGlobal(Offset.zero);
    elements.add(ElementRendu(contenu, union.shift(origine)));
  }

  final champs = find.byType(TextField);
  for (var i = 0; i < champs.evaluate().length; i++) {
    final f = champs.at(i);
    final w = tester.widget<TextField>(f);
    final invite = w.decoration?.hintText;
    if (invite != null && invite.trim().isNotEmpty) {
      elements.add(ElementRendu(invite, tester.getRect(f)));
    }
  }

  elements.sort((a, b) {
    final dy = a.boite.top - b.boite.top;
    if (dy.abs() > 6) return dy < 0 ? -1 : 1;
    return a.boite.left.compareTo(b.boite.left);
  });
  return elements;
}

/// La structure rendue d'une vue Blade : onglet -> éléments.
Map<String, List<ElementBlade>> structureBlade(String vue) {
  final fichier = File(
    'tool/conformite_blade/structure/${vue.replaceAll('/', '__')}.json',
  );
  if (!fichier.existsSync()) {
    fail(
      'Structure introuvable : ${fichier.path}.\n'
      'La générer : STRUCTURE_BLADE_SORTIE=../tatacora-flutter/tool/'
      'conformite_blade/structure php artisan test '
      '--filter=ExtraireStructureBladeTest (depuis tatacora-api/).',
    );
  }
  final json = jsonDecode(fichier.readAsStringSync()) as Map<String, dynamic>;
  final onglets = json['onglets'] as Map<String, dynamic>;
  return {
    for (final e in onglets.entries)
      e.key: [
        for (final x in e.value as List<dynamic>)
          ElementBlade(
            (x as Map<String, dynamic>)['type'] as String,
            x['texte'] as String,
            cle: x['cle'] as String?,
          ),
      ],
  };
}

/// Le résultat d'une comparaison d'ordre.
class MesureEmplacement {
  MesureEmplacement({
    required this.blade,
    required this.presents,
    required this.ordonnes,
    required this.deplaces,
    required this.absents,
  });

  /// Éléments de la vue Blade confrontés.
  final int blade;

  /// Présents à l'écran avec exactement ce texte.
  final int presents;

  /// Présents ET dans le même ordre de lecture (plus longue sous-suite commune).
  final int ordonnes;

  /// Présents mais hors d'ordre.
  final List<String> deplaces;

  /// Absents de l'écran rendu.
  final List<String> absents;

  double get tauxStrict => blade == 0 ? 100 : ordonnes * 100 / blade;
}

/// Confronte l'ordre de la vue à l'ordre du rendu : plus longue sous-suite
/// commune sur les textes normalisés.
MesureEmplacement comparerOrdre(
  List<ElementBlade> blade,
  List<ElementRendu> rendu,
) {
  final b = [for (final e in blade) normaliser(e.texte)];
  final r = [for (final e in rendu) normaliser(e.texte)];
  final presentsEnsemble = r.toSet();

  final n = b.length;
  final m = r.length;
  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = 1; i <= n; i++) {
    for (var j = 1; j <= m; j++) {
      table[i][j] = b[i - 1] == r[j - 1]
          ? table[i - 1][j - 1] + 1
          : (table[i - 1][j] >= table[i][j - 1]
                ? table[i - 1][j]
                : table[i][j - 1]);
    }
  }

  // Remonte la sous-suite pour savoir QUELS éléments sont dans l'ordre.
  final dansLOrdre = <int>{};
  var i = n;
  var j = m;
  while (i > 0 && j > 0) {
    if (b[i - 1] == r[j - 1]) {
      dansLOrdre.add(i - 1);
      i--;
      j--;
    } else if (table[i - 1][j] >= table[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }

  final deplaces = <String>[];
  final absents = <String>[];
  var presents = 0;
  for (var k = 0; k < n; k++) {
    if (!presentsEnsemble.contains(b[k])) {
      absents.add(blade[k].texte);
    } else {
      presents++;
      if (!dansLOrdre.contains(k)) deplaces.add(blade[k].texte);
    }
  }

  return MesureEmplacement(
    blade: n,
    presents: presents,
    ordonnes: dansLOrdre.length,
    deplaces: deplaces,
    absents: absents,
  );
}

/// Le texte [libelle], comparé comme la mesure le compare (apostrophe,
/// casse, ponctuation de fin) : `find.text` exigerait le caractère exact et
/// diraient « absent » un texte que la mesure vient de trouver.
Finder trouverTexte(String libelle) {
  final cible = normaliser(libelle);
  return find.byWidgetPredicate(
    (w) => w is Text && normaliser(w.data ?? '') == cible,
  );
}

/// Un onglet est CLIQUABLE si son libellé exact est porté par un widget
/// tactile. Un texte qui NOMME l'onglet sans pouvoir l'ouvrir — une note dans
/// un panneau — ne l'est pas.
bool ongletCliquable(String libelle) {
  final textes = trouverTexte(libelle);
  if (textes.evaluate().isEmpty) return false;
  return find
      .ancestor(
        of: textes,
        matching: find.byWidgetPredicate(
          (w) =>
              w is InkWell ||
              w is GestureDetector ||
              w is ButtonStyleButton ||
              w is Tab,
        ),
      )
      .evaluate()
      .isNotEmpty;
}
