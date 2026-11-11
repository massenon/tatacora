import '../../../core/rbac/garde_acces.dart';

/// Session authentifiee.
///
/// Le jeton n'est PAS porte par cet objet : il vit exclusivement dans le
/// stockage securise (`SessionRepository`). Le faire transiter dans l'etat
/// Riverpod l'exposerait a toute capture d'ecran de debogage et a tout
/// `toString()` accidentel dans un log.
final class Session {
  const Session({
    required this.utilisateurId,
    required this.login,
    required this.nom,
    required this.role,
    required this.droits,
    this.changementObligatoire = false,
  });

  final String utilisateurId;

  /// Identifiant de connexion. Distinct du [nom] : un compte technique n'a pas
  /// de fiche employe, et le serveur renvoie alors le login en guise de nom.
  final String login;

  final String nom;
  final String role;
  final GardeAcces droits;

  /// Le compte doit définir un nouveau mot de passe avant tout accès aux
  /// modules (v46, 29/10/2026) : un administrateur l'a réinitialisé. La garde du
  /// routeur n'ouvre alors QUE l'écran de changement.
  final bool changementObligatoire;

  // ⚠ Le champ `horsLigne` est RETIRÉ le 12/10/2026 (contrôle du lot 1
  // « coquille », B-7) : depuis « zéro réseau » (14/09/2026), aucun code ne
  // l'écrivait (toujours `false` par défaut) et, depuis le retrait de la
  // pastille « Hors ligne » de la barre supérieure (D311), aucun ne le lisait.
  // Un drapeau que rien n'alimente est la famille PA-126 : il ne revient que
  // le jour où un écrivain réel existe.

  /// Initiales pour l'avatar, derivees du nom plutot que stockees.
  String get initiales {
    final mots = nom.trim().split(RegExp(r'\s+')).where((m) => m.isNotEmpty);
    if (mots.isEmpty) return '?';
    if (mots.length == 1) return mots.first.substring(0, 1).toUpperCase();
    return (mots.first.substring(0, 1) + mots.last.substring(0, 1))
        .toUpperCase();
  }
}
