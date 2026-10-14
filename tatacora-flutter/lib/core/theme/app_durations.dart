import 'package:flutter/animation.dart';

/// Durées et courbes d'animation du maître — `DIRECTIVE_CONFORMITE_100.md`
/// Article 2, dernière ligne de la liste des jetons.
///
/// Ce jeton **manquait entièrement** au dépôt jusqu'au 26/08/2026 : deux durées
/// vivaient dans `AppShadows` (qui porte des ombres, pas du temps) et les
/// autres étaient écrites en dur dans les écrans. L'Article 1 n° 11 interdit
/// nommément de « raccourcir ou supprimer une animation », et l'Article 5
/// exige « mêmes durées, mêmes courbes » — ni l'un ni l'autre n'est
/// vérifiable tant qu'aucun endroit ne dit quelle est la durée juste.
///
/// ## D'où vient chaque valeur
///
/// | Durée | Règle du maître | Fichier |
/// |---|---|---|
/// | 100 ms | `transform .1s ease` | app.css l.55 (`.btn:active`) |
/// | 100 ms | `duration-100 ease-linear` | splash.html l.34 (barre de progression) |
/// | 120 ms | `transition: transform .12s ease, box-shadow .12s ease` | style en ligne, 2 emplois |
/// | 150 ms | `.15s ease` | app.css l.54, 60, 119, 126 — et la valeur par défaut de Tailwind |
/// | 200 ms | `transition: opacity .2s ease` | app.css l.72 (`.overlay-modale`) |
/// | 200 ms | `transition: transform .2s ease, opacity .2s ease` | app.css l.96 (`.boite-modale`) |
/// | 200 ms | `duration-200` | shell.js l.217 (barre latérale mobile) |
/// | 250 ms | `animation: entree-toast .25s ease forwards` | app.css l.107 |
/// | 4 000 ms | `animation: retrecir 4s linear forwards` | app.css l.115 |
/// | 600 ms | `animation: apparition .6s ease` | splash.html l.15-18 |
/// | 60 ms | `setInterval(…, 60)` | splash.html l.79 |
/// | 300 ms | `setTimeout(…, 300)` | splash.html l.77 |
///
/// ## Les courbes ne se devinent pas non plus
///
/// `ease` en CSS **n'est pas** la courbe par défaut de Tailwind. CSS `ease`
/// vaut `cubic-bezier(0.25, 0.1, 0.25, 1)` ; la valeur par défaut de la classe
/// `transition` de Tailwind vaut `cubic-bezier(0.4, 0, 0.2, 1)` — relevée dans
/// `transitionTimingFunction` du bundle vendorisé, pas de mémoire. Le maître
/// emploie les deux, selon qu'il écrit une règle CSS ou une classe utilitaire.
/// Les confondre change le ressenti de chaque ouverture de modale.
abstract final class AppDurations {
  // ----------------------------------------------------------------- Durées

  /// `.btn:active { transform: scale(0.98) }` sur `.1s` — app.css l.55.
  /// Sert aussi au `transition: background .1s ease, border-color .1s ease`
  /// posé en ligne sur les tuiles de sélection.
  static const Duration pression = Duration(milliseconds: 100);

  /// La barre de progression du démarrage — `duration-100 ease-linear`
  /// (`splash.html` l.34). Même valeur que [pression], rôle différent : elle
  /// lisse un pas de progression, elle ne répond pas à un doigt.
  static const Duration barreProgression = Duration(milliseconds: 100);

  /// `transition: transform .12s ease, box-shadow .12s ease` — le survol des
  /// tuiles de catalogue, posé en style en ligne (2 emplois).
  static const Duration survolTuile = Duration(milliseconds: 120);

  /// **La durée commune du maître.** Boutons (`filter`), champs
  /// (`border-color`, `box-shadow`), cartes au survol, zone de dépôt. C'est
  /// aussi la valeur par défaut de la classe `transition` de Tailwind, donc
  /// celle des 44 emplois de `transition-colors` / `transition-all` /
  /// `transition-transform` sans `duration-*` explicite.
  static const Duration courte = Duration(milliseconds: 150);

  /// L'ouverture et la fermeture d'une modale — `.overlay-modale` en opacité
  /// et `.boite-modale` en `transform` + `opacity`, toutes deux sur `.2s ease`.
  /// C'est aussi la durée du glissement de la barre latérale mobile
  /// (`duration-200`, shell.js l.217) et des deux `duration-200` des pages.
  static const Duration modale = Duration(milliseconds: 200);

  /// `x-transition` d'Alpine SANS durée explicite — la SORTIE : 75 ms
  /// (l'entrée vaut 150 ms, [courte]), courbe `cubic-bezier(0.4, 0, 0.2, 1)`
  /// ([tailwindDefaut]). Valeurs par défaut d'Alpine 3, servi par Livewire 3.
  /// Le voile du panneau « Accès rapides » (`x-transition.opacity`, partiel
  /// `acces-rapide`) — relevé le 13/10/2026.
  static const Duration sortieAlpine = Duration(milliseconds: 75);

  /// `@keyframes entree-toast` — l'entrée d'un toast, `.25s ease`.
  static const Duration toastEntree = Duration(milliseconds: 250);

  /// `@keyframes retrecir … 4s linear` — la barre de progression d'un toast
  /// couvre exactement sa durée de vie à l'écran.
  static const Duration toastVie = Duration(seconds: 4);

  /// `wire:model.live.debounce.250ms` — le délai de calme après lequel la
  /// recherche globale de la barre supérieure relit le terme saisi.
  static const Duration debounceRecherche = Duration(milliseconds: 250);

  // ------------------------------------------------- Écran de démarrage
  //
  // Le maître les pose sur quatre classes `.anim-1` à `.anim-4`, chacune de
  // `.6s ease` et décalée de 200 ms de plus que la précédente. L'Article 4.1
  // exige « mêmes durées, mêmes retards en cascade, même durée totale avant
  // bascule » : les quatre valeurs comptent, pas seulement la première.

  /// `animation: apparition .6s ease` — la durée d'apparition d'un bloc.
  static const Duration apparition = Duration(milliseconds: 600);

  /// Le pas entre deux blocs de la cascade — `.anim-2` à `.2s`, `.anim-3` à
  /// `.4s`, `.anim-4` à `.6s`.
  static const Duration pasCascade = Duration(milliseconds: 200);

  /// Les quatre retards, dans l'ordre des blocs du maître.
  static const List<Duration> cascadeApparition = [
    Duration.zero,
    Duration(milliseconds: 200),
    Duration(milliseconds: 400),
    Duration(milliseconds: 600),
  ];

  /// `setInterval(…, 60)` — la cadence de la barre de progression du démarrage.
  /// Elle avance de 4 % par pas, soit 25 pas et 1 500 ms jusqu'à 100 %.
  static const Duration pasProgression = Duration(milliseconds: 60);

  /// `setTimeout(…, 300)` — la pause entre 100 % et l'aiguillage.
  static const Duration pauseAvantAiguillage = Duration(milliseconds: 300);

  // ---------------------------------------------------------------- Courbes

  /// La courbe `ease` de CSS — `cubic-bezier(0.25, 0.1, 0.25, 1)`.
  ///
  /// `Curves.ease` de Flutter porte **exactement** ces quatre coefficients ;
  /// l'alias est donc une lecture, pas une approximation. C'est la courbe de
  /// toutes les règles écrites à la main dans `app.css`.
  static const Curve ease = Curves.ease;

  /// La courbe par défaut des classes `transition*` de Tailwind —
  /// `cubic-bezier(0.4, 0, 0.2, 1)`, relevée dans `transitionTimingFunction`
  /// du bundle vendorisé.
  ///
  /// `Curves.fastOutSlowIn` porte les mêmes coefficients. ⚠ Ce n'est **pas**
  /// [ease] : le maître emploie les deux selon qu'il écrit une règle CSS ou
  /// une classe utilitaire.
  static const Curve tailwindDefaut = Curves.fastOutSlowIn;

  /// `ease-linear` — la barre de progression du démarrage, seul emploi.
  static const Curve lineaire = Curves.linear;
}
