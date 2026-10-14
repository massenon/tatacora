/// Les rayons de bordure du maître — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// ## Mesurés, jamais supposés
///
/// Deux sources, toutes deux dans `prototype_v2/`, aucune dans un document :
///
/// 1. le **comptage des classes** `rounded-*` sur les 50 pages, `index.html` et
///    les scripts qui construisent du DOM ;
/// 2. la **table `borderRadius` du bundle Tailwind réellement servi**
///    (`assets/css/vendor/tailwind-play-cdn.js`), et non l'échelle de mémoire.
///
/// Le second point n'est pas une précaution de style. Ce dépôt a déjà payé la
/// supposition d'une échelle : neuf des dix tailles de police les plus
/// employées du maître sont des valeurs entre crochets, et les traduire par
/// l'échelle nommée aurait faussé plus de 900 occurrences. Les rayons, eux,
/// n'emploient **aucune** valeur entre crochets — c'est un fait mesuré, pas une
/// hypothèse, et c'est la garde qui le tient.
///
/// | Classe | Valeur | Emplois |
/// |---|---|---|
/// | `rounded-lg` | 0.5rem = **8 px** | **734** — le rayon du maître |
/// | `rounded-xl` | 0.75rem = 12 px | 189 (+ 14 `rounded-b-xl`) |
/// | `rounded` | 0.25rem = 4 px | 176 |
/// | `rounded-full` | 9999 px | 52 |
/// | `rounded-md` | 0.375rem = 6 px | 5 |
/// | `rounded-2xl` | 1rem = 16 px | 1 |
///
/// Et deux règles CSS explicites, qui confirment le comptage :
/// `.boite-modale { border-radius: 12px }` (app.css l.94) et
/// `.toast { border-radius: 8px }` (l.104).
///
/// ## Les noms courts sont des ALIAS, pas une seconde échelle
///
/// `sm`/`md`/`lg` sont conservés parce que trente fichiers les emploient, mais
/// ils **assignent** depuis les rayons ci-dessus au lieu de porter leurs
/// propres entiers. Une seule source de vérité par donnée (Article 10) — et
/// leur ancienne documentation mentait déjà à moitié : `md` valait 8, ce qui
/// est `rounded-lg` et non `rounded-md`.
abstract final class AppRadius {
  /// `rounded` — 0.25rem. Pastilles compactes, petits badges.
  static const double rounded = 4;

  /// `rounded-md` — 0.375rem.
  static const double roundedMd = 6;

  /// `rounded-lg` — 0.5rem. **Le rayon dominant du maître** : boutons, champs,
  /// cartes, pastilles de statut, toasts.
  static const double roundedLg = 8;

  /// `rounded-xl` — 0.75rem. Modales (`.boite-modale`), grandes cartes, logo.
  static const double roundedXl = 12;

  /// `rounded-2xl` — 1rem.
  static const double rounded2xl = 16;

  /// `rounded-full`. En Flutter, une valeur simplement plus grande que la
  /// moitié de la boîte suffit ; on garde celle du maître pour que la garde
  /// puisse la confronter au bundle.
  static const double roundedFull = 9999;

  // --------------------------------------------------------------- Alias
  /// Badges — `rounded`.
  static const double sm = rounded;

  /// Boutons, champs de saisie, cartes — `rounded-lg`.
  static const double md = roundedLg;

  /// Modales, grandes cartes — `rounded-xl`.
  static const double lg = roundedXl;

  /// `rounded-2xl`.
  static const double xl = rounded2xl;

  /// `rounded-full`.
  static const double pleine = roundedFull;
}
