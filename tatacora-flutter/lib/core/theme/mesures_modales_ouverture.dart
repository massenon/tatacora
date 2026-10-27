import 'package:flutter/painting.dart';

import 'app_colors.dart';

/// Les mesures des DEUX MODALES d'ouverture de session —
/// `pwa/transverse/alertes-ouverture-modales.blade.php` et son partiel
/// `bloc-alerte-ouverture.blade.php` (hors `<main>` : échelle [Tailles]).
abstract final class MesuresModalesOuverture {
  /// `largeur="672px"` de `<x-pwa.modale>`.
  static const double largeurModale = 672;

  /// `style="background:{{ $couleur }}12"` — la teinte du bandeau : 0x12 = 18/255.
  static const double alphaBandeau = 18 / 255;

  /// `width="18" height="18"` — l'icône du bandeau, `stroke-width="2.2"`.
  static const double icone = 18;
  static const double epaisseurIcone = 2.2;

  /// `w-1.5 h-1.5` — la pastille de ligne (1,5 × 4 px).
  static const double pastille = 6;

  /// `max-h-64` — le défilement d'un bloc (64 × 4 px).
  static const double hauteurMaxBloc = 256;

  /// `border-t-2`... non : la bordure haute du lien de pied est de 1 px.
  /// Les trois couleurs de bloc de la vue : `#C62828`, `#1D4ED8`, `#ED6C02`.
  static const Color couleurStock = AppColors.erreur;
  static const Color couleurDeparts = AppColors.info;
  static const Color couleurCreances = AppColors.alerte;

  /// Les tracés des trois icônes de bloc (contenu des `<svg>` de la vue).
  static const String traceStock =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8M12 13v8"/>';
  static const String traceDeparts =
      '<rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/>';
  static const String traceCreances =
      '<path stroke-linecap="round" stroke-linejoin="round" d="M12 2v20M17 5H9.5a3.5 3.5 0 000 7h5a3.5 3.5 0 010 7H6"/>';
}
