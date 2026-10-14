/// **Les actifs image embarqués — un seul auteur par chemin.**
///
/// Le logo s'affiche à quatre endroits (barre supérieure, démarrage,
/// connexion, facture A4) : quatre chaînes écrites à la main avaient chacune
/// à être retrouvée le jour où le fichier changerait — ce jour est arrivé.
library;

/// Chemins des actifs déclarés dans `pubspec.yaml`.
abstract final class AppAssets {
  /// Le logo de l'établissement.
  ///
  /// Décision du Product Owner du 14/10/2026 (ticket D392, PA-210) : nouveau
  /// logo, PNG PAYSAGE 735 × 403 à fond blanc opaque, qui remplace
  /// `logo.jpg` (rond, carré). Octet pour octet le fichier que sert la vue
  /// (`tatacora-api/public/assets/img/logo.png`, `ApparenceEtablissementService::ACTIF_LIVRE`)
  /// — `logo_etablissement_test` les compare.
  ///
  /// Dans les cadres CARRÉS de la vue, il s'affiche en `BoxFit.contain` (la
  /// vue écrit `object-contain`) : jamais rogné, jamais étiré.
  static const String logo = 'assets/img/logo.png';
}
