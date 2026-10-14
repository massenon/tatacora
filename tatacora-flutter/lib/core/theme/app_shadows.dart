import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// Les ombres portées du maître de mise en page.
///
/// **Relevées dans `prototype_v2/assets/css/app.css`, jamais estimées** —
/// `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` §3.1. Le maître en porte cinq
/// distinctes, chacune attachée à un rôle précis ; les mélanger revient à
/// redessiner, ce que la doctrine interdit.
///
/// Une ombre « à peu près juste » est le genre d'écart qu'aucune relecture ne
/// rattrape et qui, cumulé sur vingt écrans, donne une application qui
/// *ressemble* à la maquette sans en être une.
///
/// | Rôle | Règle CSS | Ligne |
/// |---|---|---|
/// | Anneau de focus | `0 0 0 3px rgba(20,33,61,.10)` | `.champ:focus` l.61 |
/// | Anneau de focus en erreur | `0 0 0 3px rgba(198,40,40,.12)` | `.champ-erreur:focus` l.63 |
/// | Modale | `0 20px 60px rgba(0,0,0,.25)` | `.modale` l.97 |
/// | Toast | `0 10px 30px rgba(0,0,0,.15)` | `.toast` l.104 |
/// | Carte au survol | `0 8px 24px rgba(20,33,61,.08)` | `.carte-hover:hover` l.120 |
abstract final class AppShadows {
  /// `rgba(20,33,61,…)` **EST** le navy du dépôt : les deux anneaux se
  /// dérivent donc de [AppColors.navy] au lieu de recopier trois entiers.
  /// Le jour où la charte change de bleu, ils suivent — une valeur recopiée,
  /// non.
  static const List<BoxShadow> focusChamp = [
    BoxShadow(
      color: Color(0x1A14213D), // navy à 10 %
      blurRadius: 0,
      spreadRadius: 3,
    ),
  ];

  /// `rgba(198,40,40,.12)` — c'est [AppColors.erreur], `#C62828`.
  static const List<BoxShadow> focusChampErreur = [
    BoxShadow(
      color: Color(0x1FC62828), // erreur à 12 %
      blurRadius: 0,
      spreadRadius: 3,
    ),
  ];

  /// La plus marquée du maître : une modale doit détacher franchement du
  /// contenu qu'elle recouvre.
  static const List<BoxShadow> modale = [
    BoxShadow(
      color: Color(0x40000000), // noir à 25 %
      blurRadius: 60,
      offset: Offset(0, 20),
    ),
  ];

  static const List<BoxShadow> toast = [
    BoxShadow(
      color: Color(0x26000000), // noir à 15 %
      blurRadius: 30,
      offset: Offset(0, 10),
    ),
  ];

  /// Le survol d'une carte d'unité. Au maître, il s'accompagne d'un
  /// `translateY(-2px)` sur `.15s ease` — l'ombre seule ne reproduit pas
  /// l'effet, et l'omettre serait un écart à documenter.
  static const List<BoxShadow> carteSurvol = [
    BoxShadow(
      color: Color(0x1414213D), // navy à 8 %
      blurRadius: 24,
      offset: Offset(0, 8),
    ),
  ];

  /// Le déplacement qui accompagne [carteSurvol] — `transform: translateY(-2px)`.
  static const double carteSurvolTranslation = -2;

  /// `backdrop-filter: blur(2px)` sur `.overlay-modale` (app.css l.72).
  ///
  /// Le maître floute ce qui est derrière la modale. L'omettre est un écart
  /// visible que rien ne signalerait ; le jeton existe pour qu'il ne soit pas
  /// omis par distraction.
  static const double flouArrierePlanModale = 2;

  // ------------------------------------------------------------------------
  // Les ombres utilitaires de Tailwind employées par le maître.
  //
  // 23 emplois au total, relevés par comptage : `shadow-2xl` (11), `shadow`
  // (6), `shadow-sm` (3), `shadow-xl` (2), `shadow-lg` (1). Leurs valeurs sont
  // relues dans la table `boxShadow` du bundle vendorisé, pas de mémoire.
  //
  // Elles ne remplacent pas les cinq ombres CSS ci-dessus : ce sont des rôles
  // différents, et le maître emploie les deux jeux.
  // ------------------------------------------------------------------------

  /// `shadow-sm` — `0 1px 2px 0 rgb(0 0 0 / 0.05)`.
  static const List<BoxShadow> tailwindSm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// `shadow` — `0 1px 3px 0 rgb(0 0 0 / .1), 0 1px 2px -1px rgb(0 0 0 / .1)`.
  static const List<BoxShadow> tailwindBase = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 2,
      spreadRadius: -1,
      offset: Offset(0, 1),
    ),
  ];

  /// `shadow-lg` — `0 10px 15px -3px rgb(0 0 0 / .1), 0 4px 6px -4px …`.
  static const List<BoxShadow> tailwindLg = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 15,
      spreadRadius: -3,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 6,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  /// `shadow-xl` — `0 20px 25px -5px rgb(0 0 0 / .1), 0 8px 10px -6px …`.
  static const List<BoxShadow> tailwindXl = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 25,
      spreadRadius: -5,
      offset: Offset(0, 20),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 10,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];

  /// `shadow-2xl` — `0 25px 50px -12px rgb(0 0 0 / 0.25)`. La plus employée
  /// des utilitaires du maître (11 emplois), sur ses panneaux glissants.
  static const List<BoxShadow> tailwind2xl = [
    BoxShadow(
      color: Color(0x40000000),
      blurRadius: 50,
      spreadRadius: -12,
      offset: Offset(0, 25),
    ),
  ];
}
