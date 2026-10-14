/// Une trace de l'historique des prix d'une boisson — `HistoriquePrixResource`.
///
/// Les valeurs restent BRUTES, en chaîne `decimal:2` : c'est l'écran qui les
/// dit (« Oui » / « Non », montant en FCFA), comme la modale de la PWA. Le
/// client ne calcule rien dessus.
final class TracePrix {
  const TracePrix({
    required this.id,
    required this.date,
    required this.champ,
    required this.ancien,
    required this.nouveau,
    required this.par,
  });

  /// La marque « corrigé à la main » — `HistoriquePrixCarte::CHAMP_PRIX_CORRIGE_MAIN`.
  static const String champCorrigeMain = 'prix_corrige_main';

  final String id;

  /// `null` si la réponse n'en portait pas de lisible : « — », jamais une
  /// date inventée.
  final DateTime? date;

  /// `prix_vente` ou `prix_corrige_main`.
  final String champ;

  /// `null` : il n'y avait pas de valeur — « — », jamais « 0 ».
  final String? ancien;
  final String? nouveau;

  /// L'identifiant de connexion de l'auteur, ou `null`.
  final String? par;
}
