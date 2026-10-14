import 'package:flutter/widgets.dart';

import '../theme/app_breakpoints.dart';

export '../theme/app_breakpoints.dart';

/// Points de rupture — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// **Les valeurs ne vivent plus ici.** Elles vivent dans [AppBreakpoints], avec
/// les autres jetons du système de design, et sont relevées dans le bundle
/// Tailwind réellement servi par le maître. Ce fichier ne garde que la
/// **décision de palier**, qui est du code, pas un jeton.
///
/// Les deux seuils étaient auparavant écrits en dur ici, hors du système de
/// design : c'est ce qui les avait laissés hors du balayage de conformité, et
/// donc invérifiables. Deux endroits qui décrivent la même chose divergent, ce
/// n'est qu'une question de temps (Article 10).
enum Palier { mobile, tablette, desktop }

abstract final class Breakpoints {
  /// `md:` du maître.
  static const double tablette = AppBreakpoints.md;

  /// `lg:` du maître — le seul seuil qui change l'ossature de l'écran.
  static const double desktop = AppBreakpoints.lg;

  static Palier depuisLargeur(double largeur) {
    if (largeur >= desktop) return Palier.desktop;
    if (largeur >= tablette) return Palier.tablette;
    return Palier.mobile;
  }

  static Palier de(BuildContext context) =>
      depuisLargeur(MediaQuery.sizeOf(context).width);

  /// La navigation basse ne s'affiche qu'en deçà du seuil desktop.
  static bool navigationBasse(BuildContext context) =>
      de(context) != Palier.desktop;
}
