import '../../../core/rbac/regle_archivage.dart' show roleNormalise;

/// Les pièces saisies à la main AVANT la v44 (28/10/2026, lot A3) : ni marquées,
/// ni envoyées. Un geste explicite du hub (« Envoyer mes anciennes pièces
/// saisies ») les marque puis les envoie ; rien ne le déduit en silence.
///
/// ## Ce qu'on propose, et ce qu'on ne propose JAMAIS
///
/// Une pièce n'est proposée que si rien ne la rattache à un module ni à une
/// clôture. Les modules écrivent dans `VTE`, `CAI` et `BQ` (ventes, trésorerie
/// des dépenses, règlements, encaissements, réservations), la clôture dans
/// `CL` et `AN` : ces cinq journaux ne sont donc JAMAIS proposés. Restent les
/// journaux que seule la saisie manuelle alimente (`ACH`, `OD`, tout journal
/// ajouté). Et, EN CAS DE DOUTE, la pièce n'est pas proposée : elle porte une
/// contre-passation (ou en subit une), ses lignes ne partagent pas le même
/// journal, exercice, statut ou date, elle est déséquilibrée ou n'a qu'une
/// ligne, son exercice est clôturé, ou une dépense / une réservation la cite.
/// Une pièce non proposée reste comptée au poste, jamais perdue.
const List<String> journauxDesModulesEtDeCloture = [
  'VTE',
  'CAI',
  'BQ',
  'CL',
  'AN',
];

/// Les rôles admis au geste : l'administration et le comptable
/// (`DocumentsAutresPostes.rolesAdmis`).
const Set<String> rolesEnvoiAnciennesPieces = {
  'administrateur',
  'super_admin',
  'comptable',
};

bool peutEnvoyerAnciennesPieces(String? role) =>
    rolesEnvoiAnciennesPieces.contains(roleNormalise(role));

/// Une ligne d'une ancienne pièce, telle que le poste l'a écrite.
final class LigneAnciennePiece {
  const LigneAnciennePiece({
    required this.compte,
    required this.debitCentimes,
    required this.creditCentimes,
    required this.libelle,
    required this.centreLibelle,
  });

  final String compte;
  final int debitCentimes;
  final int creditCentimes;
  final String libelle;
  final String centreLibelle;
}

/// Une ancienne pièce saisie à la main, proposée à l'envoi.
final class AnciennePieceSaisie {
  const AnciennePieceSaisie({
    required this.numeroPiece,
    required this.journal,
    required this.date,
    required this.libelle,
    required this.statut,
    required this.lignes,
  });

  final String numeroPiece;
  final String journal;

  /// `AAAA-MM-JJ`.
  final String date;

  /// Le libellé de la PREMIÈRE ligne : le poste n'a pas gardé celui de la pièce,
  /// et une ligne ne l'écrit qu'à part quand il diffère.
  final String libelle;

  /// `brouillon` | `validee`.
  final String statut;
  final List<LigneAnciennePiece> lignes;

  /// Le total de la pièce (somme des débits, égale à celle des crédits).
  int get totalCentimes => lignes.fold(0, (s, l) => s + l.debitCentimes);
}

/// Ce que la confirmation dit : combien de pièces et pour quel total.
int totalAnciennesPieces(List<AnciennePieceSaisie> pieces) =>
    pieces.fold(0, (s, p) => s + p.totalCentimes);
