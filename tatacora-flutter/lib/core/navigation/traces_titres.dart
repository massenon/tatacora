/// Les TRACÉS SVG des icônes de titre de page ajoutées le 26/10/2026
/// (directive du PO : « l'icône du titre est manquante » sur l'historique des
/// ventes, les dépenses et le tableau de bord).
///
/// Chaque chaîne est le contenu du `<svg width="24" height="24"
/// viewBox="0 0 24 24" fill="none" stroke="var(--navy)" stroke-width="2">`
/// posé par la vue Blade avant le `<h1>`, caractère pour caractère ; la garde
/// `test/core/qualite/icones_titre_test.dart` relit les vues et exige que
/// chaque chaîne y figure. Le tableau de bord, lui, reprend le tracé
/// `dashboard` de la barre latérale (`TracesAccueil.titre`).
abstract final class TraceIconesTitre {
  /// `pwa/pos/historique-ventes.blade.php` — une horloge (l'historique).
  static const String historiqueVentes =
      '<circle cx="12" cy="12" r="10"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6l4 2"/>';

  /// `pwa/depenses/depenses.blade.php` — une carte de paiement.
  static const String depenses =
      '<rect x="1" y="4" width="22" height="16" rx="2"/>'
      '<path stroke-linecap="round" stroke-linejoin="round" d="M1 10h22"/>';
}
