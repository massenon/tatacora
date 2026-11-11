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

  /// Largeur du logo sur une facture / un avoir / une proforma A4, en POINTS
  /// (PDF). Demande PO 09/11/2026 : 144 px CSS côté serveur
  /// (`ReportHeaderService::LOGO_FACTURE_A4_LARGEUR_PX`) x 0,75 = 108 pt ; la
  /// hauteur suit les proportions du PNG (735 x 403), jamais étirée.
  static const double logoFactureA4LargeurPt = 108;

  /// Hauteur correspondante (735 x 403) : un `pw.Image` sans hauteur borne
  /// prend toute la place verticale disponible, d'ou une hauteur explicite.
  static const double logoFactureA4HauteurPt =
      logoFactureA4LargeurPt * 403 / 735;

  /// La photo du gîte du panneau gauche de la connexion (119 Ko, déjà sous le
  /// seuil des 400 Ko : livrée telle quelle, copie octet pour octet de celle de
  /// la PWA). EMBARQUÉE : le poste est hors ligne.
  static const String couvertureConnexion = 'assets/img/gite-cover.jpg';

  /// L'aperçu social (1280 × 640), même fichier que la PWA
  /// (`tatacora-api/public/assets/img/social-preview.png`). Embarqué, jamais téléchargé.
  static const String apercuSocial = 'assets/img/social-preview.png';
}
