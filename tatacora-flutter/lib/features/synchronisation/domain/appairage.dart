/// L'APPAIRAGE du poste au serveur (lot F2a, 15/10/2026) : ses règles et ses
/// phrases.
///
/// Un Administrateur saisit UNE fois par poste l'identifiant et le mot de
/// passe d'un compte du serveur, et le nom du poste. Le poste appelle
/// `POST /api/v1/login` (`AuthController::connexion`) avec `poste` = ce nom :
/// le jeton rendu porte ce nom, et le serveur exige qu'il soit le `poste_id`
/// de chaque lot (`PosteDuJeton::concorde`, 403 sinon). Le mot de passe n'est
/// ni stocké ni journalisé ; seul le jeton l'est, dans `poste.json`.
library;

/// La longueur maximale d'un nom de poste — `ConnexionRequest` : `poste`
/// `max:100`.
const int longueurMaxNomPoste = 100;

/// Le nom du poste, NETTOYÉ : lettres non accentuées, chiffres, `-`, `_` et
/// `.` ; les blancs deviennent `-` ; les accents sont retirés ; 100 caractères
/// au plus. `null` s'il ne reste rien.
///
/// Pourquoi nettoyer : ce nom est le NOM du jeton au serveur et le
/// `poste_id` de chaque lot, recopié dans les traces (`journal_audit`,
/// `sessions_synchronisation`) et comparé À L'OCTET près. Un espace final
/// ou une apostrophe typographique saisis par mégarde feraient un poste que
/// personne ne saurait retaper.
String? nettoyerNomPoste(String? saisie) {
  if (saisie == null) return null;
  const accents = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', //
    'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', //
    'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i', //
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', //
    'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u', //
    'ÿ': 'y', 'ñ': 'n',
  };
  final tampon = StringBuffer();
  for (final rune in saisie.trim().runes) {
    var c = String.fromCharCode(rune);
    final bas = c.toLowerCase();
    if (accents.containsKey(bas)) {
      final sans = accents[bas]!;
      c = c == bas ? sans : sans.toUpperCase();
    }
    if (RegExp(r'^[A-Za-z0-9._-]$').hasMatch(c)) {
      tampon.write(c);
    } else if (c.trim().isEmpty) {
      tampon.write('-');
    }
  }
  var nom = tampon.toString().replaceAll(RegExp('-{2,}'), '-');
  nom = nom.replaceAll(RegExp(r'^[-.]+|[-.]+$'), '');
  if (nom.length > longueurMaxNomPoste) {
    nom = nom.substring(0, longueurMaxNomPoste);
  }
  return nom.isEmpty ? null : nom;
}

/// L'issue d'un appairage.
sealed class ResultatAppairage {
  const ResultatAppairage();
}

final class AppairageReussi extends ResultatAppairage {
  const AppairageReussi({required this.posteId, required this.compte});

  final String posteId;
  final String compte;
}

final class AppairageRefuse extends ResultatAppairage {
  const AppairageRefuse(this.message);

  /// Une phrase de [TextesAppairage] — JAMAIS le corps de la réponse.
  final String message;
}

/// Les phrases de l'appairage. Aucune ne recopie la réponse du serveur : son
/// corps peut porter une trace technique, et l'opérateur doit savoir QUOI
/// faire, pas lire un JSON.
abstract final class TextesAppairage {
  static const identifiantsRefuses =
      'Identifiants refusés par le serveur : vérifiez l’identifiant et le mot '
      'de passe du compte serveur.';
  static const compteDesactive =
      'Ce compte est désactivé sur le serveur : demandez à un administrateur '
      'du serveur de le réactiver, ou utilisez un autre compte.';
  static const tropDeTentatives =
      'Trop de tentatives : le serveur bloque ce compte pendant quelques '
      'minutes. Réessayez plus tard.';
  static const serveurInjoignable =
      'Serveur injoignable : vérifiez la connexion Internet du poste, puis '
      'réessayez.';
  static const saisieRefusee =
      'Le serveur a refusé la saisie : identifiant, mot de passe et nom du '
      'poste sont obligatoires.';
  static String erreurServeur(int code) =>
      'Le serveur a rencontré une erreur (code $code). Réessayez plus tard.';
  static String reponseInattendue(int code) =>
      'Réponse inattendue du serveur (code $code) : l’appairage n’a pas été '
      'enregistré.';
  static const desactivee =
      'La synchronisation est désactivée sur ce poste : aucune connexion au '
      'serveur n’est tentée. Activez-la pour appairer ou tester la connexion.';
  static const demonstration =
      'La démonstration ne se synchronise jamais : aucun appairage possible.';
  static const champsObligatoires =
      'Saisissez l’identifiant, le mot de passe et le nom du poste.';
  static const nomPosteInvalide =
      'Nom du poste invalide : utilisez des lettres, des chiffres, « - », '
      '« _ » ou « . ».';

  static const nonAppaire = 'Ce poste n’est pas appairé au serveur.';
  static String connexionEtablie(String compte) =>
      'Connexion établie : le serveur reconnaît le jeton de ce poste '
      '(compte $compte).';
  static const jetonRefuse =
      'Jeton refusé par le serveur — réappairer le poste.';
  static const dissocie =
      'Poste dissocié : le jeton a été retiré de ce poste. Les opérations en '
      'attente restent sur le poste.';
}

/// La phrase d'un refus de `POST /login`, selon le code HTTP.
String messageRefusConnexion(int code) => switch (code) {
  401 => TextesAppairage.identifiantsRefuses,
  403 => TextesAppairage.compteDesactive,
  429 => TextesAppairage.tropDeTentatives,
  422 => TextesAppairage.saisieRefusee,
  >= 500 => TextesAppairage.erreurServeur(code),
  _ => TextesAppairage.reponseInattendue(code),
};
