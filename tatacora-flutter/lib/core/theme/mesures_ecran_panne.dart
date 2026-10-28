/// Les mesures de l'écran de panne du démarrage (hors châssis métier : cet
/// écran n'a pas de vue Blade, il apparaît quand l'application ne peut pas
/// s'ouvrir).
abstract final class MesuresEcranPanne {
  /// Largeur maximale de la carte.
  static const double largeurCarte = 560;

  /// Hauteur maximale du détail défilant.
  static const double hauteurDetail = 180;

  /// Épaisseur de l'indicateur d'attente.
  static const double epaisseurAttente = 4;

  /// Côté de l'indicateur d'attente.
  static const double coteAttente = 40;
}
