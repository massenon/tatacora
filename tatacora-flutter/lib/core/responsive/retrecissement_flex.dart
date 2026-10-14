/// Le partage de largeur d'une rangée `display: flex` quand elle ne tient pas.
///
/// ## Pourquoi ce fichier existe (09/10/2026)
///
/// La vue d'Hébergement pose, sur une seule ligne, un bloc titre + sous-titre
/// et la rangée de ses quatre onglets (`hebergement.blade.php` l.77-95) :
/// `flex flex-col lg:flex-row lg:items-center gap-4`, le bloc des onglets en
/// `lg:ml-auto flex gap-2`. À 1 383 px de fenêtre, la ligne ne tient pas : le
/// navigateur **rétrécit** ses éléments, et les onglets descendent jusqu'à la
/// largeur de leur plus long mot (« Plan d'Hébergement » se coupe en deux
/// lignes, « Disponibilités » reste sur une). Flutter n'a pas d'équivalent :
/// un `Row` de `Flexible` répartit un espace LIBRE, il ne rétrécit pas des
/// éléments à leur base en respectant un plancher. Sans ce partage, les
/// onglets gardent leur largeur naturelle et repoussent le sous-titre.
///
/// ## L'algorithme est celui du navigateur
///
/// CSS Flexbox, §9.7 « Resolving Flexible Lengths », restreint au cas qui
/// compte ici : pas de croissance (`flex-grow: 0`), facteur de rétrécissement
/// de 1 pondéré par la base, plancher = `min-content` (le `min-width: auto`
/// d'un élément flex). On répète : on répartit l'excédent au prorata des bases,
/// on fige tout élément que cette répartition mettrait sous son plancher, et
/// on recommence avec ceux qui restent.
///
/// Fonction pure : elle se teste sans widget (`retrecissement_flex_test.dart`).
library;

/// Un élément de la rangée : sa base (largeur « max-content ») et son
/// plancher (largeur « min-content »).
final class ElementFlex {
  const ElementFlex({required this.base, required this.minimum})
    : assert(base >= minimum, 'la base ne peut pas être sous le plancher');

  /// La largeur que l'élément prend quand rien ne le contraint.
  final double base;

  /// La largeur sous laquelle il ne peut pas descendre (son plus long mot).
  final double minimum;
}

/// Les largeurs finales de [elements] dans une rangée de [disponible] pixels,
/// [ecarts] étant la somme des `gap` entre eux.
///
/// Si tout tient, chaque élément garde sa base : une rangée ne s'étire pas.
List<double> partagerRetrecissement({
  required List<ElementFlex> elements,
  required double disponible,
  double ecarts = 0,
}) {
  final bases = [for (final e in elements) e.base];
  final somme = bases.fold<double>(0, (a, b) => a + b);
  if (somme + ecarts <= disponible) return bases;

  final tailles = List<double>.of(bases);
  final figes = List<bool>.filled(elements.length, false);

  // Au plus un passage par élément : chaque tour en fige au moins un, ou sort.
  for (var tour = 0; tour <= elements.length; tour++) {
    var tailleFigee = 0.0;
    var baseLibre = 0.0;
    for (var i = 0; i < elements.length; i++) {
      if (figes[i]) {
        tailleFigee += tailles[i];
      } else {
        baseLibre += bases[i];
      }
    }
    if (baseLibre == 0) break;

    // Négatif : c'est l'excédent à retrancher aux éléments encore libres.
    final libre = disponible - ecarts - tailleFigee - baseLibre;

    var violationTotale = 0.0;
    final cibles = List<double>.of(tailles);
    for (var i = 0; i < elements.length; i++) {
      if (figes[i]) continue;
      cibles[i] = bases[i] + libre * bases[i] / baseLibre;
      violationTotale += cibles[i] < elements[i].minimum
          ? elements[i].minimum - cibles[i]
          : 0;
    }

    if (violationTotale == 0) {
      return cibles;
    }

    // Une violation de plancher : on fige ces éléments à leur plancher et l'on
    // répartit de nouveau le reste.
    for (var i = 0; i < elements.length; i++) {
      if (figes[i]) continue;
      if (cibles[i] < elements[i].minimum) {
        tailles[i] = elements[i].minimum;
        figes[i] = true;
      }
    }
  }

  return tailles;
}
