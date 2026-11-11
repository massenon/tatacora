/// Les LIBELLÉS et les TRACÉS des boutons de fenêtre du poste (09/11/2026).
///
/// AJOUT du poste Windows : la barre supérieure de la vue n'a pas ces boutons
/// (`partials/barre-superieure` l.112, le `<header>` : un navigateur porte
/// déjà les siens). Ils n'existent pas dans les clés de langue de la PWA, ce
/// fichier est donc leur seule source ; les mots sont ceux de Windows.
/// Chemins écrits sans leur préfixe : ce fichier ne porte aucune vue de page.
library;

abstract final class LibellesFenetre {
  static const String reduire = 'Réduire';
  static const String agrandir = 'Agrandir';
  static const String restaurer = 'Restaurer';
  static const String fermer = 'Fermer';

  /// La croix du champ de recherche déplié (fenêtre étroite, mode icône).
  static const String fermerRecherche = 'Fermer la recherche';
}

/// Les tracés (`viewBox="0 0 24 24"`, lus par `IconeTrace`).
abstract final class TracesFenetre {
  static const String reduire = r'<path stroke-linecap="round" d="M5 12h14"/>';

  static const String agrandir =
      r'<rect x="5" y="5" width="14" height="14" rx="1"/>';

  /// Deux carrés qui se chevauchent : celui du fond n'est visible que par son
  /// angle haut-droit.
  static const String restaurer =
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M9 5h9a1 1 0 011 1v9"/><rect x="4" y="9" width="11" height="11" rx="1"/>';

  static const String fermer =
      r'<path stroke-linecap="round" d="M6 6l12 12M18 6L6 18"/>';
}
