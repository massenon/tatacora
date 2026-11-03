/// Le nom d'un AUTEUR de saisie tel que les listes l'affichent (décision du PO du
/// 03/11/2026, « supprimer un compte ») : son login, suivi de « (compte supprimé) »
/// quand le compte l'est. Ce qu'un compte supprimé a saisi (ventes, dépenses,
/// écritures, mouvements) garde son nom — la phrase est celle de
/// `pwa.comptes.auteur_supprime` du serveur.
///
/// Auteur unique de la phrase : les DAO la demandent ici, aucun ne la recopie.
String libelleAuteurCompte(String login, {DateTime? supprimeLe}) =>
    supprimeLe == null ? login : '$login (compte supprimé)';
