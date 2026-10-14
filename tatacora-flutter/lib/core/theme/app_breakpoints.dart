/// Les points de rupture du maître — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// ## Les cinq seuils, relevés dans le bundle réellement servi
///
/// Le maître ne redéfinit **pas** `theme.screens` : ses quinze blocs
/// `tailwind.config` n'étendent que `colors` (`navy`, `gold`). Les seuils sont
/// donc ceux de Tailwind, et ils ont été lus dans la table `screens` de
/// `prototype_v2/assets/css/vendor/tailwind-play-cdn.js` — pas de mémoire, et
/// pas depuis la documentation en ligne d'une autre version.
///
/// | Préfixe | Seuil |
/// |---|---|
/// | `sm:` | 640 px |
/// | `md:` | 768 px |
/// | `lg:` | 1024 px |
/// | `xl:` | 1280 px |
/// | `2xl:` | 1536 px |
///
/// **Les cinq comptent**, et c'est pourquoi ils figurent tous ici alors que
/// l'ossature ne bascule qu'à `lg`. Le point de vente pose ses deux panneaux
/// latéraux en `xl:w-[320px]` et `xl:w-[380px]` : un portage qui ne connaîtrait
/// que trois paliers les afficherait dès 1024 px, où la colonne du catalogue
/// n'a plus la place. L'Article 1 n° 12 interdit nommément de « changer un
/// point de rupture responsive » — encore faut-il les avoir tous.
///
/// ## La décision se prend sur la largeur de l'ÉCRAN
///
/// `MediaQuery`, jamais `constraints.maxWidth` d'un `LayoutBuilder` local. La
/// largeur du contenu n'est pas celle de la fenêtre : une barre latérale
/// déployée fausse tout. L'Article 5 le nomme « le bug de responsive numéro
/// un », et c'est la raison pour laquelle aucun accesseur de ce fichier ne
/// prend de contraintes.
abstract final class AppBreakpoints {
  /// `sm:` — 640 px.
  static const double sm = 640;

  /// `md:` — 768 px.
  static const double md = 768;

  /// `lg:` — 1024 px. **Le seul seuil qui change l'ossature** : au-delà, la
  /// navigation passe d'une barre inférieure à une barre latérale permanente.
  static const double lg = 1024;

  /// `xl:` — 1280 px. Les deux panneaux du point de vente.
  static const double xl = 1280;

  /// `2xl:` — 1536 px.
  static const double xxl = 1536;
}
