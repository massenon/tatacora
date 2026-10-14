import 'package:flutter/widgets.dart';

/// Le TRACÉ d'une icône de la vue, dessiné tel quel — brique commune de la
/// coquille (12/10/2026, lot 1 de `INSTRUCTION.txt`).
///
/// ## Pourquoi ce fichier existe
///
/// La vue dessine chaque icône du châssis en SVG inline, `viewBox="0 0 24 24"`,
/// `fill="none" stroke="currentColor" stroke-width="2"` : les tracés de la
/// barre latérale vivent dans `MenuLateral::ICONES` (`app/Pwa/Support/`), ceux
/// de la barre supérieure et du menu de compte dans la vue elle-même. Le client
/// Flutter leur substituait des icônes Material « de même sens » — un autre
/// dessin, un autre trait, et la partition des icônes était la seule chose qui
/// en était vérifiée. Ce widget rejoue le tracé de la vue, octet pour octet :
/// la chaîne qu'il reçoit est celle de la vue, et un test la confronte au
/// registre PHP (`coquille_conformite_test.dart`).
///
/// ## Ce qu'il sait lire — et ce qu'il refuse
///
/// Les trois éléments employés par la vue : `path` (attribut `d`), `rect`
/// (`x y width height rx`) et `circle` (`cx cy r`), avec `stroke-linecap` et
/// `stroke-linejoin` par élément (la vue ne les pose que sur ses `<path>`). Les
/// commandes de chemin `M L H V C S Q A Z` (absolues et relatives), drapeaux
/// d'arc collés compris (`a2 2 0 011.82…`, la forme compacte des tracés de la
/// vue). Toute autre commande, tout élément inconnu LÈVE : un tracé mal lu
/// doit faire échouer, jamais dessiner autre chose en silence — la même règle
/// que la vue, qui a retiré son repli d'icône le 31/08/2026
/// (`entree-menu.blade.php`, docblock).
final class TraceSvg {
  TraceSvg._(this.elements);

  /// Lit un tracé (le contenu d'un `<svg>` de la vue). Mis en cache : la
  /// barre latérale redessine vingt-quatre icônes à chaque navigation.
  factory TraceSvg.lire(String trace) =>
      _cache.putIfAbsent(trace, () => TraceSvg._(_lireElements(trace)));

  static final Map<String, TraceSvg> _cache = {};

  final List<ElementTrace> elements;
}

/// Un élément du tracé : sa géométrie et ses terminaisons de trait.
final class ElementTrace {
  const ElementTrace(this.chemin, {required this.cap, required this.join});

  final Path chemin;
  final StrokeCap cap;
  final StrokeJoin join;
}

/// L'icône dessinée — `<svg width=taille height=taille viewBox="0 0 24 24"
/// fill="none" stroke=couleur stroke-width=epaisseur>`.
class IconeTrace extends StatelessWidget {
  const IconeTrace({
    required this.trace,
    required this.taille,
    required this.couleur,
    this.epaisseur = epaisseurTraceVue,
    super.key,
  });

  /// `stroke-width="2"` — l'épaisseur de TOUTES les icônes de la vue, sauf le
  /// bouton « Vente » de la barre supérieure (2,5).
  static const double epaisseurTraceVue = 2;

  /// Le côté de la `viewBox` de la vue (`0 0 24 24`).
  static const double coteViewBox = 24;

  final String trace;
  final double taille;
  final Color couleur;
  final double epaisseur;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: taille,
    height: taille,
    child: CustomPaint(
      painter: _PeintreTrace(TraceSvg.lire(trace), couleur, epaisseur),
    ),
  );
}

class _PeintreTrace extends CustomPainter {
  _PeintreTrace(this.trace, this.couleur, this.epaisseur);

  final TraceSvg trace;
  final Color couleur;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / IconeTrace.coteViewBox);
    for (final e in trace.elements) {
      canvas.drawPath(
        e.chemin,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = couleur
          // L'épaisseur est en unités de `viewBox`, comme `stroke-width` : la
          // mise à l'échelle du canevas la réduit avec le dessin.
          ..strokeWidth = epaisseur
          ..strokeCap = e.cap
          ..strokeJoin = e.join
          // `stroke-miterlimit` par défaut de SVG.
          ..strokeMiterLimit = 4
          ..isAntiAlias = true,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PeintreTrace ancien) =>
      ancien.trace != trace ||
      ancien.couleur != couleur ||
      ancien.epaisseur != epaisseur;
}

final RegExp _balise = RegExp(r'<\s*([a-zA-Z]+)\b([^>]*?)/?>');
final RegExp _attribut = RegExp(r'([a-zA-Z][\w-]*)\s*=\s*"([^"]*)"');

List<ElementTrace> _lireElements(String trace) {
  final elements = <ElementTrace>[];
  for (final m in _balise.allMatches(trace)) {
    final nom = m.group(1)!;
    final attrs = {
      for (final a in _attribut.allMatches(m.group(2)!))
        a.group(1)!: a.group(2)!,
    };
    double nombre(String cle, {double? defaut}) {
      final v = attrs[cle];
      if (v == null) {
        if (defaut != null) return defaut;
        throw FormatException('Attribut « $cle » absent de <$nom>.', trace);
      }
      return double.parse(v);
    }

    final Path chemin;
    switch (nom) {
      case 'path':
        chemin = cheminDepuisD(attrs['d'] ?? '');
      case 'rect':
        final rx = nombre('rx', defaut: 0);
        chemin = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                nombre('x', defaut: 0),
                nombre('y', defaut: 0),
                nombre('width'),
                nombre('height'),
              ),
              Radius.circular(rx),
            ),
          );
      case 'circle':
        chemin = Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(nombre('cx'), nombre('cy')),
              radius: nombre('r'),
            ),
          );
      default:
        throw FormatException(
          'Élément SVG non pris en charge : <$nom>.',
          trace,
        );
    }
    elements.add(
      ElementTrace(
        chemin,
        cap: switch (attrs['stroke-linecap']) {
          'round' => StrokeCap.round,
          'square' => StrokeCap.square,
          _ => StrokeCap.butt,
        },
        join: switch (attrs['stroke-linejoin']) {
          'round' => StrokeJoin.round,
          'bevel' => StrokeJoin.bevel,
          _ => StrokeJoin.miter,
        },
      ),
    );
  }
  if (elements.isEmpty) {
    throw FormatException('Tracé SVG vide ou illisible.', trace);
  }
  return elements;
}

const String _commandes = 'MmLlHhVvCcSsQqAaZz';

/// L'attribut `d` d'un `<path>`, lu en [Path] — exposé pour les tests.
Path cheminDepuisD(String d) {
  final chemin = Path();
  var i = 0;
  String? commande;
  var x = 0.0, y = 0.0; // point courant
  var x0 = 0.0, y0 = 0.0; // départ du sous-chemin
  double? ctrlX, ctrlY; // dernier point de contrôle cubique (pour S)

  bool separateur(String c) =>
      c == ' ' || c == ',' || c == '\n' || c == '\r' || c == '\t';
  void sauter() {
    while (i < d.length && separateur(d[i])) {
      i++;
    }
  }

  bool chiffre(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  double lireNombre() {
    sauter();
    final debut = i;
    if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
    var point = false;
    var exposant = false;
    while (i < d.length) {
      final c = d[i];
      if (chiffre(c)) {
        i++;
      } else if (c == '.' && !point && !exposant) {
        point = true;
        i++;
      } else if ((c == 'e' || c == 'E') && !exposant) {
        exposant = true;
        i++;
        if (i < d.length && (d[i] == '-' || d[i] == '+')) i++;
      } else {
        break;
      }
    }
    if (i == debut) {
      throw FormatException('Nombre attendu dans le tracé.', d, i);
    }
    return double.parse(d.substring(debut, i));
  }

  // Un drapeau d'arc est UN caractère : `0 011.82` se lit 0, 1, 1.82.
  bool lireDrapeau() {
    sauter();
    if (i >= d.length) throw FormatException('Drapeau d’arc attendu.', d, i);
    final c = d[i++];
    if (c == '0') return false;
    if (c == '1') return true;
    throw FormatException('Drapeau d’arc invalide : « $c ».', d, i - 1);
  }

  bool encoreDesNombres() {
    sauter();
    return i < d.length && !_commandes.contains(d[i]);
  }

  while (true) {
    sauter();
    if (i >= d.length) break;
    final c = d[i];
    if (_commandes.contains(c)) {
      commande = c;
      i++;
    } else if (commande == null) {
      throw FormatException('Le tracé ne commence pas par une commande.', d, i);
    }
    final cmd = commande;
    final relatif = cmd == cmd.toLowerCase() && cmd != 'Z';
    double rx0() => relatif ? x : 0;
    double ry0() => relatif ? y : 0;
    var cubique = false;

    switch (cmd.toUpperCase()) {
      case 'M':
        x = rx0() + lireNombre();
        y = ry0() + lireNombre();
        chemin.moveTo(x, y);
        x0 = x;
        y0 = y;
        // Les paires suivantes d'un « M » sont des « L » implicites.
        commande = relatif ? 'l' : 'L';
      case 'L':
        x = rx0() + lireNombre();
        y = ry0() + lireNombre();
        chemin.lineTo(x, y);
      case 'H':
        x = rx0() + lireNombre();
        chemin.lineTo(x, y);
      case 'V':
        y = ry0() + lireNombre();
        chemin.lineTo(x, y);
      case 'C':
        final ox = rx0(), oy = ry0();
        final x1 = ox + lireNombre(), y1 = oy + lireNombre();
        final x2 = ox + lireNombre(), y2 = oy + lireNombre();
        x = ox + lireNombre();
        y = oy + lireNombre();
        chemin.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
        cubique = true;
      case 'S':
        final ox = rx0(), oy = ry0();
        // Premier contrôle = reflet du précédent si la commande précédente
        // était cubique, sinon le point courant (spécification SVG).
        final x1 = ctrlX == null ? x : 2 * x - ctrlX;
        final y1 = ctrlY == null ? y : 2 * y - ctrlY;
        final x2 = ox + lireNombre(), y2 = oy + lireNombre();
        x = ox + lireNombre();
        y = oy + lireNombre();
        chemin.cubicTo(x1, y1, x2, y2, x, y);
        ctrlX = x2;
        ctrlY = y2;
        cubique = true;
      case 'Q':
        final ox = rx0(), oy = ry0();
        final x1 = ox + lireNombre(), y1 = oy + lireNombre();
        x = ox + lireNombre();
        y = oy + lireNombre();
        chemin.quadraticBezierTo(x1, y1, x, y);
      case 'A':
        final ox = rx0(), oy = ry0();
        final rayonX = lireNombre().abs(), rayonY = lireNombre().abs();
        final rotation = lireNombre();
        final grandArc = lireDrapeau();
        final sensHoraire = lireDrapeau();
        x = ox + lireNombre();
        y = oy + lireNombre();
        if (rayonX == 0 || rayonY == 0) {
          chemin.lineTo(x, y);
        } else {
          chemin.arcToPoint(
            Offset(x, y),
            radius: Radius.elliptical(rayonX, rayonY),
            rotation: rotation,
            largeArc: grandArc,
            // `sweep-flag = 1` : sens des angles positifs, c'est-à-dire horaire
            // dans un repère dont l'axe y descend — celui de l'écran.
            clockwise: sensHoraire,
          );
        }
      case 'Z':
        chemin.close();
        x = x0;
        y = y0;
        commande = null;
      default:
        throw FormatException(
          'Commande de tracé non prise en charge : $cmd.',
          d,
        );
    }
    if (!cubique) {
      ctrlX = null;
      ctrlY = null;
    }
    if (commande == null && encoreDesNombres()) {
      throw FormatException('Nombres orphelins après « Z ».', d, i);
    }
  }
  return chemin;
}
