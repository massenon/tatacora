/// Les styles de texte des MODALES de M4.
///
/// ## Un fichier à part, et ce n'est pas un rangement
///
/// `app.css` l.166-197 remappe l'échelle typographique **à l'intérieur de
/// `<main>`** : `text-[13px]` y rend 12,5 px. Les conteneurs de modales du
/// maître sont hors `</main>` — `crud-ui.js` les injecte dans
/// `#crud-modales-zone`, frère de `<main>` — et gardent donc l'échelle
/// **déclarée**, [Tailles].
///
/// Les deux familles vivaient d'abord dans le même fichier. `echelle_contenu_
/// test.dart` l'a refusé, et il a raison : un fichier qui emploie les deux
/// échelles ne peut être classé dans aucun camp, et plus personne ne sait
/// laquelle s'applique où. La frontière du maître est donc une frontière de
/// fichiers.
library;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

abstract final class TextesModaleRestaurant {
  /// `text-base font-bold` — le titre d'une modale (`crud-ui.js` l.91,
  /// `carte-module.js` l.226). Échelle **déclarée** : les conteneurs de modales
  /// sont hors de la portée du remappage.
  static const TextStyle titre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t16,
    fontWeight: FontWeight.bold,
    color: AppColors.navy,
  );

  /// `text-[12px] text-slate-500` — le sous-titre d'une modale
  /// (`carte-module.js` l.227).
  static const TextStyle sousTitre = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c500,
  );

  /// `text-[13px] font-semibold text-slate-700` — l'étiquette d'un champ
  /// (`carte-module.js` l.234).
  static const TextStyle etiquette = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t13,
    fontWeight: FontWeight.w600,
    color: Ardoise.c700,
  );

  /// `text-[11px] text-slate-400` — l'aide sous un champ (l.240).
  static const TextStyle aide = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t11,
    color: Ardoise.c400,
  );

  /// `text-sm font-semibold` — un bouton de pied de modale
  /// (`crud-ui.js` l.98-99).
  static const TextStyle bouton = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t14,
    fontWeight: FontWeight.w600,
  );

  /// `text-sm text-slate-500` — un corps de texte de modale
  /// (`crud-ui.js` l.132 et l.151).
  static const TextStyle corps = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t14,
    color: Ardoise.c500,
  );

  /// `text-xs text-slate-400` — une note de pied de modale (`crud-ui.js` l.156).
  static const TextStyle note = TextStyle(
    fontFamily: AppTextStyles.police,
    fontSize: Tailles.t12,
    color: Ardoise.c400,
  );
}
