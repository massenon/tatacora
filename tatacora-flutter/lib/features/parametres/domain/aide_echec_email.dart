/// L'AIDE lisible sous l'échec de « Envoyer un email de test » (09/11/2026) —
/// copie exacte de `AideEchecEmail` du serveur, même ordre, mêmes fragments,
/// mêmes phrases (`pwa.parametres.email_test_aide_*`) : le web et le poste
/// disent la même chose, confrontés par `aide_email_contre_serveur_test`.
///
/// Le message du transport reste affiché TEL QUEL (il est fidèle) ; l'aide vient
/// dessous. Trois cas, reconnus à des fragments du message — celui du poste (le
/// client SMTP de Dart) comme celui du serveur (Symfony Mailer) : nom du serveur
/// introuvable, identifiants refusés, connexion refusée ou expirée. Un message
/// inconnu n'a PAS d'aide : on ne devine pas. L'aide est une phrase fixe : elle
/// ne reprend jamais le message du transport, donc ni compte ni mot de passe.
library;

enum CasEchecEmail {
  hote('hote'),
  authentification('authentification'),
  connexion('connexion');

  const CasEchecEmail(this.code);

  final String code;
}

abstract final class AideEchecEmail {
  /// `AideEchecEmail::FRAGMENTS` du serveur, dans l'ordre d'examen : un nom
  /// introuvable est AUSSI « une connexion impossible » pour Symfony, il passe donc
  /// avant elle.
  static const Map<CasEchecEmail, List<String>> fragments = {
    CasEchecEmail.hote: [
      'failed host lookup',
      'getaddrinfo',
      'php_network_getaddresses',
      'name or service not known',
      'nodename nor servname',
      'no address associated with hostname',
      'temporary failure in name resolution',
      'could not resolve host',
      'nom d’hôte introuvable',
    ],
    CasEchecEmail.authentification: [
      'authenticat',
      'username and password not accepted',
      'invalid credentials',
      'bad credentials',
      'a refusé les identifiants',
      'code "535"',
      ' 535 ',
    ],
    CasEchecEmail.connexion: [
      'connection refused',
      'connection timed out',
      'timed out',
      'timeout',
      'connection could not be established',
      'connection reset',
      'connection closed',
      'network is unreachable',
      'no route to host',
      'handshake',
      'wrong version number',
      'n’a pas répondu à temps',
    ],
  };

  /// `pwa.parametres.email_test_aide_hote`.
  static const String hote =
      'Le nom du serveur de messagerie n\'existe pas ou n\'est pas joignable '
      'depuis ce poste. Vérifiez le nom du serveur (Paramètres > Email (SMTP)), '
      'la connexion Internet du poste, et le nom indiqué dans votre hébergeur '
      '(cPanel > Comptes de messagerie > Configurer le client de messagerie).';

  /// `pwa.parametres.email_test_aide_connexion`.
  static const String connexion =
      'Le serveur de messagerie a refusé la connexion ou n\'a pas répondu à '
      'temps. Vérifiez le port (465 avec le chiffrement SSL, 587 avec le '
      'chiffrement TLS) et le chiffrement choisi (Paramètres > Email (SMTP)), '
      'puis la connexion Internet du poste.';

  /// `pwa.parametres.email_test_aide_authentification`.
  static const String authentification =
      'Le serveur de messagerie a refusé l\'identifiant ou le mot de passe. '
      'Vérifiez l\'utilisateur SMTP (l\'adresse complète de la boîte) et le mot '
      'de passe (Paramètres > Email (SMTP)).';

  /// Le cas reconnu dans [erreur], ou `null`.
  static CasEchecEmail? cas(String erreur) {
    final texte = erreur.toLowerCase();
    for (final e in fragments.entries) {
      if (e.value.any(texte.contains)) return e.key;
    }
    return null;
  }

  /// La phrase d'aide à poser sous l'échec, ou `null` quand le message n'est
  /// pas reconnu.
  static String? pour(String erreur) => switch (cas(erreur)) {
    CasEchecEmail.hote => hote,
    CasEchecEmail.connexion => connexion,
    CasEchecEmail.authentification => authentification,
    null => null,
  };
}
