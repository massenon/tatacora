/// Les réglages de l'OPÉRATEUR que le boîtier exige (`seller_id`,
/// `seller_name`), reçus du serveur en lecture seule (`mecef_operateur_id`,
/// `mecef_operateur_nom`). Seul lecteur de ces deux clés sur ce poste.
library;

/// `seller_name` : 30 caractères au plus (`bill.spec.json` du pilote).
const int longueurMaxNomOperateur = 30;

final class OperateurFacturation {
  const OperateurFacturation({required this.id, required this.nom});

  final String id;
  final String nom;

  bool get complet => id.isNotEmpty && nom.isNotEmpty;

  /// Lit l'opérateur des paramètres reçus du serveur.
  factory OperateurFacturation.depuisParametres(Map<String, String> valeurs) =>
      OperateurFacturation(
        id: (valeurs['mecef_operateur_id'] ?? '').trim(),
        nom: (valeurs['mecef_operateur_nom'] ?? '').trim(),
      );
}
