/// Les mesures des TROIS BOUTONS DE FENÊTRE du poste Windows (réduire,
/// agrandir / restaurer, fermer) et de la zone de déplacement de la barre
/// supérieure — demande du PO du 09/11/2026.
///
/// La vue Blade n'a pas ces boutons (c'est une page de navigateur) : ces
/// mesures ne se relèvent donc pas sur elle. Elles reprennent le gabarit des
/// boutons de légende de Windows, que le PO a montrés en capture (« — ❐ ✕ »).
library;

abstract final class MesuresFenetre {
  /// La largeur d'un bouton de légende de Windows (46 px logiques) ; la
  /// hauteur est celle de la barre supérieure.
  static const double largeurBouton = 46;

  /// La largeur d'un bouton en barre COMPACTE (fenêtre étroite) : la hauteur
  /// minimale d'une cible, ni plus, ni moins.
  static const double largeurBoutonCompact = hauteurMinimale;

  /// Sous cette largeur de fenêtre, la barre supérieure d'un poste qui porte
  /// les boutons passe en mode COMPACT : boutons de 32 px et identité du compte
  /// (login, rôle) masquée — l'avatar, le chevron et l'infobulle restent. Mesuré
  /// le 09/11/2026 : la barre, avec les boutons, tient à partir de 1160 px ;
  /// en dessous elle débordait à droite et la croix aurait été coupée, sur le
  /// portable 1366 x 768 à 125 % (1093 px logiques) que vise le poste.
  static const double seuilBarreCompacte = 1160;

  /// Une cible tactile / souris ne descend jamais sous cette hauteur.
  static const double hauteurMinimale = 32;

  /// Le côté du tracé — plus petit que les 22 px des boutons de la vue : une
  /// légende de fenêtre est discrète.
  static const double icone = 16;

  /// Le trait des quatre tracés (réduire, agrandir, restaurer, fermer).
  static const double epaisseurTrace = 1.5;

  /// La taille minimale commandée au contrôle de fenêtre : sous elle, les
  /// écrans à plusieurs colonnes se chevauchent (le runner la tient déjà, à
  /// 1024 x 640 ; cette valeur n'est qu'un repère pour les tests).
  static const double largeurFenetreMinimale = 1024;
}
