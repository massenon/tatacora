/// Une rangée `display: flex; flex-wrap: wrap` AVEC croissance — celle de la
/// barre de filtres des Stocks (`stocks.blade.php` l.182-246).
///
/// ## Pourquoi ce fichier existe (09/10/2026)
///
/// La vue pose, dans une seule rangée repliable, une recherche `flex-1
/// min-w-[220px]`, quatre listes, un espace `flex-1` et trois boutons. À
/// 1 383 px de fenêtre, la rangée NE TIENT PAS : le navigateur passe à la ligne
/// avant le deuxième bouton, et la recherche et l'espace se partagent ce qui
/// reste de la première ligne. Flutter n'a pas d'équivalent :
///
///  * un `Wrap` replie mais ne fait pas grandir ses éléments ;
///  * un `Row` de `Expanded` fait grandir mais ne replie pas — il déborde.
///
/// La première version de cet écran choisissait l'un ou l'autre selon un seuil
/// de largeur écrit à la main. Le seuil était faux (il aurait débordé entre
/// 1 000 et 1 100 px) et ne reproduisait pas le repli du navigateur. Ce
/// composant mesure au lieu de supposer.
///
/// ## L'algorithme est celui du navigateur
///
/// CSS Flexbox §9.3 et §9.7, restreint au cas qui compte :
///
///  1. chaque élément RIGIDE prend sa largeur naturelle ; chaque élément
///     élastique (`flex-1`) compte pour son plancher (`min-w`) dans le calcul
///     des lignes ;
///  2. une ligne se ferme quand l'élément suivant (plus l'écart) ne tient plus ;
///  3. sur chaque ligne, l'espace libre est partagé à égalité entre ses
///     éléments élastiques, qu'un plancher peut figer ([partagerCroissance]).
///
/// Les éléments d'une ligne sont centrés verticalement (`items-center`).
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Les largeurs des éléments élastiques d'une ligne : [libre] pixels à partager
/// à égalité, aucun élément ne descendant sous son plancher.
///
/// Un élément que la part égale mettrait sous son plancher est FIGÉ à ce
/// plancher, et le reste est repartagé entre ceux qui restent (§9.7). Fonction
/// pure : elle se teste sans widget.
List<double> partagerCroissance({
  required List<double> planchers,
  required double libre,
}) {
  final tailles = List<double>.filled(planchers.length, 0);
  final figes = List<bool>.filled(planchers.length, false);

  var reste = libre;
  var restants = planchers.length;

  // Au plus un tour par élément : chaque tour en fige un, ou sort.
  for (var tour = 0; tour <= planchers.length; tour++) {
    if (restants == 0) break;
    final part = reste / restants;

    var nouveauFige = false;
    for (var i = 0; i < planchers.length; i++) {
      if (figes[i] || planchers[i] <= part) continue;
      figes[i] = true;
      tailles[i] = planchers[i];
      reste -= planchers[i];
      restants--;
      nouveauFige = true;
    }
    if (!nouveauFige) {
      for (var i = 0; i < planchers.length; i++) {
        if (!figes[i]) tailles[i] = part < 0 ? 0 : part;
      }
      break;
    }
  }
  return tailles;
}

/// Marque un enfant de [RangeeFlexWrap] comme ÉLASTIQUE (`flex-1`) : il grandit
/// avec l'espace libre de sa ligne, sans descendre sous [largeurMin]
/// (`min-w-[…]`).
///
/// Sans cette enveloppe, un enfant est rigide : il garde sa largeur naturelle.
class ElementElastique extends ParentDataWidget<_DonneesRangee> {
  const ElementElastique({
    super.key,
    this.largeurMin = 0,
    required super.child,
  });

  final double largeurMin;

  @override
  void applyParentData(RenderObject renderObject) {
    final donnees = renderObject.parentData! as _DonneesRangee;
    if (donnees.largeurMin != largeurMin || !donnees.elastique) {
      donnees
        ..elastique = true
        ..largeurMin = largeurMin;
      renderObject.parent?.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RangeeFlexWrap;
}

class _DonneesRangee extends ContainerBoxParentData<RenderBox> {
  bool elastique = false;
  double largeurMin = 0;
}

/// La rangée elle-même. [ecart] sépare deux éléments d'une ligne (`gap-x`),
/// [ecartLignes] deux lignes (`gap-y`).
class RangeeFlexWrap extends MultiChildRenderObjectWidget {
  const RangeeFlexWrap({
    super.key,
    this.ecart = 0,
    this.ecartLignes = 0,
    super.children,
  });

  final double ecart;
  final double ecartLignes;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenduRangee(ecart: ecart, ecartLignes: ecartLignes);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenduRangee)
      ..ecart = ecart
      ..ecartLignes = ecartLignes;
  }
}

class _RenduRangee extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DonneesRangee>,
        RenderBoxContainerDefaultsMixin<RenderBox, _DonneesRangee> {
  _RenduRangee({required double ecart, required double ecartLignes}) {
    _ecart = ecart;
    _ecartLignes = ecartLignes;
  }

  double _ecart = 0;
  double get ecart => _ecart;
  set ecart(double v) {
    if (_ecart == v) return;
    _ecart = v;
    markNeedsLayout();
  }

  double _ecartLignes = 0;
  double get ecartLignes => _ecartLignes;
  set ecartLignes(double v) {
    if (_ecartLignes == v) return;
    _ecartLignes = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DonneesRangee) {
      child.parentData = _DonneesRangee();
    }
  }

  @override
  double computeMinIntrinsicWidth(double hauteur) {
    var plus = 0.0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final d = c.parentData! as _DonneesRangee;
      final w = d.elastique ? d.largeurMin : c.getMinIntrinsicWidth(hauteur);
      if (w > plus) plus = w;
    }
    return plus;
  }

  @override
  double computeMaxIntrinsicWidth(double hauteur) {
    var somme = 0.0;
    var n = 0;
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final d = c.parentData! as _DonneesRangee;
      somme += d.elastique ? d.largeurMin : c.getMaxIntrinsicWidth(hauteur);
      n++;
    }
    return somme + (n > 0 ? _ecart * (n - 1) : 0);
  }

  @override
  double computeMinIntrinsicHeight(double largeur) =>
      computeMaxIntrinsicHeight(largeur);

  @override
  double computeMaxIntrinsicHeight(double largeur) =>
      getDryLayout(BoxConstraints(maxWidth: largeur)).height;

  @override
  Size computeDryLayout(BoxConstraints contraintes) =>
      _mettreEnPage(contraintes, appliquer: false);

  @override
  void performLayout() {
    size = _mettreEnPage(constraints, appliquer: true);
  }

  Size _mettreEnPage(BoxConstraints contraintes, {required bool appliquer}) {
    final disponible = contraintes.hasBoundedWidth
        ? contraintes.maxWidth
        : double.infinity;

    // 1. Les largeurs HYPOTHÉTIQUES : naturelle pour un rigide, plancher pour
    //    un élastique.
    final enfants = <RenderBox>[];
    final hypothetiques = <double>[];
    for (var c = firstChild; c != null; c = childAfter(c)) {
      final d = c.parentData! as _DonneesRangee;
      enfants.add(c);
      if (d.elastique) {
        hypothetiques.add(d.largeurMin);
      } else {
        // Pour de vrai quand on pose (un enfant n'a pas toujours de mesure à
        // sec), à sec quand un parent ne fait que demander la taille.
        final cadre = BoxConstraints(maxWidth: disponible);
        if (appliquer) {
          c.layout(cadre, parentUsesSize: true);
          hypothetiques.add(c.size.width);
        } else {
          hypothetiques.add(c.getDryLayout(cadre).width);
        }
      }
    }

    // 2. Les lignes.
    final lignes = <List<int>>[];
    var courante = <int>[];
    var largeurCourante = 0.0;
    for (var i = 0; i < enfants.length; i++) {
      final ajout = hypothetiques[i] + (courante.isEmpty ? 0 : _ecart);
      if (courante.isNotEmpty && largeurCourante + ajout > disponible) {
        lignes.add(courante);
        courante = <int>[];
        largeurCourante = 0;
      }
      courante.add(i);
      largeurCourante += hypothetiques[i] + (courante.length > 1 ? _ecart : 0);
    }
    if (courante.isNotEmpty) lignes.add(courante);

    // 3. Largeurs finales, hauteurs de ligne, positions.
    var y = 0.0;
    var largeurMax = 0.0;
    for (var l = 0; l < lignes.length; l++) {
      final ligne = lignes[l];
      final ecarts = _ecart * (ligne.length - 1);
      final rigides = ligne
          .where((i) => !(enfants[i].parentData! as _DonneesRangee).elastique)
          .fold<double>(0, (a, i) => a + hypothetiques[i]);
      final elastiques = ligne
          .where((i) => (enfants[i].parentData! as _DonneesRangee).elastique)
          .toList();

      final tailles = <int, double>{};
      if (elastiques.isNotEmpty && disponible.isFinite) {
        final parts = partagerCroissance(
          planchers: [for (final i in elastiques) hypothetiques[i]],
          libre: disponible - rigides - ecarts,
        );
        for (var k = 0; k < elastiques.length; k++) {
          tailles[elastiques[k]] = parts[k];
        }
      } else {
        for (final i in elastiques) {
          tailles[i] = hypothetiques[i];
        }
      }

      // Hauteur de la ligne : la plus haute des tailles finales.
      var hauteur = 0.0;
      final dimensions = <int, Size>{};
      for (final i in ligne) {
        final largeur = tailles[i] ?? hypothetiques[i];
        final c = enfants[i];
        final taille = appliquer
            ? _poser(c, largeur, elastique: tailles.containsKey(i))
            : c.getDryLayout(
                tailles.containsKey(i)
                    ? BoxConstraints.tightFor(width: largeur)
                    : BoxConstraints(maxWidth: largeur),
              );
        dimensions[i] = taille;
        if (taille.height > hauteur) hauteur = taille.height;
      }

      var x = 0.0;
      for (final i in ligne) {
        final taille = dimensions[i]!;
        if (appliquer) {
          (enfants[i].parentData! as _DonneesRangee).offset = Offset(
            x,
            y + (hauteur - taille.height) / 2,
          );
        }
        x += taille.width + _ecart;
      }
      final largeurLigne = x - _ecart;
      if (largeurLigne > largeurMax) largeurMax = largeurLigne;
      y += hauteur + (l < lignes.length - 1 ? _ecartLignes : 0);
    }

    final largeur = disponible.isFinite ? disponible : largeurMax;
    return contraintes.constrain(Size(largeur, y));
  }

  Size _poser(RenderBox c, double largeur, {required bool elastique}) {
    c.layout(
      elastique
          ? BoxConstraints.tightFor(width: largeur)
          : BoxConstraints(maxWidth: largeur),
      parentUsesSize: true,
    );
    return c.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
