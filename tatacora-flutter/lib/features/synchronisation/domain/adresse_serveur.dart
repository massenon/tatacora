/// L'ADRESSE DU SERVEUR que le poste interroge — sa saisie, sa validation, sa
/// normalisation (29/10/2026, demande du Product Owner : la modifier à tout
/// moment, sans toucher au code ni recompiler).
///
/// ## Où elle vit
///
/// Dans `poste.json`, clé `serveur` (la clé de l'appairage, voir
/// `ClesAppairage.serveur`), au format de l'API : `<racine>/api/v1`. L'écran
/// montre et saisit la RACINE (l'« adresse de l'espace web »), sans `/api/v1` :
/// c'est ce qu'un opérateur connaît. Jamais dans le code source, jamais dans la
/// base métier ; la valeur livrée est dans `installer/poste.example.json`.
///
/// ## Les règles (un seul endroit, pour l'écran ET le service)
///
///  * schéma `http://` ou `https://` obligatoire ;
///  * `https` exigé sauf pour `localhost`, `127.0.0.1`, `10.x.x.x` et
///    `192.168.x.x` (poste de développement ou serveur du réseau local) : un
///    jeton Sanctum ne circule pas en clair sur Internet ;
///  * ni espace, ni identifiants (`user:pass@`), ni paramètres, ni ancre ;
///  * pas de chemin superflu : la barre finale et un éventuel `/api` ou
///    `/api/v1` sont retirés, tout autre chemin est refusé ;
///  * 255 caractères au plus.
library;

/// La longueur maximale de la saisie.
const int longueurMaxAdresseServeur = 255;

/// Le suffixe de l'API ajouté à la racine.
const String suffixeApiServeur = '/api/v1';

/// Une adresse VALIDE et normalisée.
final class AdresseServeur {
  const AdresseServeur._(this.racine);

  /// `https://hote[:port]` — sans barre finale, sans `/api`.
  final String racine;

  /// L'adresse de l'API, telle qu'elle s'écrit dans `poste.json` (`serveur`).
  String get urlApi => '$racine$suffixeApiServeur';

  /// L'endroit où le serveur répond « je suis là » sans jeton (`/up`).
  String get urlSante => '$racine/up';

  @override
  bool operator ==(Object other) =>
      other is AdresseServeur && other.racine == racine;

  @override
  int get hashCode => racine.hashCode;

  @override
  String toString() => racine;
}

/// L'issue d'une validation.
sealed class ResultatAdresse {
  const ResultatAdresse();
}

final class AdresseValide extends ResultatAdresse {
  const AdresseValide(this.adresse);

  final AdresseServeur adresse;
}

final class AdresseInvalide extends ResultatAdresse {
  const AdresseInvalide(this.message);

  /// Une phrase de [TextesAdresseServeur], en français.
  final String message;
}

/// Les phrases de la validation et de l'enregistrement.
abstract final class TextesAdresseServeur {
  static const vide = 'Saisissez l’adresse du serveur.';
  static const tropLongue =
      'L’adresse du serveur est trop longue (255 caractères au plus).';
  static const espaces = 'L’adresse du serveur ne doit contenir aucun espace.';
  static const schema =
      'L’adresse doit commencer par http:// ou https:// '
      '(par exemple https://logirestock.digitonpro.com).';
  static const illisible =
      'Cette adresse n’est pas valide : vérifiez-la '
      '(par exemple https://logirestock.digitonpro.com).';
  static const httpsExige =
      'L’adresse doit commencer par https:// : http:// n’est accepté que '
      'pour un serveur local (localhost, 127.0.0.1, 10.x ou 192.168.x).';
  static const identifiants =
      'L’adresse ne doit pas contenir d’identifiant ni de mot de passe.';
  static const parametres =
      'L’adresse ne doit contenir ni paramètre (?) ni ancre (#).';
  static const chemin =
      'L’adresse ne doit pas contenir de chemin : saisissez seulement '
      'l’adresse de l’espace web (par exemple '
      'https://logirestock.digitonpro.com).';
}

/// Valide et normalise [saisie].
ResultatAdresse validerAdresseServeur(String? saisie) {
  final texte = (saisie ?? '').trim();
  if (texte.isEmpty) return const AdresseInvalide(TextesAdresseServeur.vide);
  if (texte.length > longueurMaxAdresseServeur) {
    return const AdresseInvalide(TextesAdresseServeur.tropLongue);
  }
  if (RegExp(r'\s').hasMatch(texte)) {
    return const AdresseInvalide(TextesAdresseServeur.espaces);
  }
  final minuscules = texte.toLowerCase();
  if (!minuscules.startsWith('http://') && !minuscules.startsWith('https://')) {
    return const AdresseInvalide(TextesAdresseServeur.schema);
  }
  final Uri uri;
  try {
    uri = Uri.parse(texte);
  } on FormatException {
    return const AdresseInvalide(TextesAdresseServeur.illisible);
  }
  final hote = uri.host.toLowerCase();
  if (hote.isEmpty || !_hoteLisible(hote)) {
    return const AdresseInvalide(TextesAdresseServeur.illisible);
  }
  if (uri.userInfo.isNotEmpty) {
    return const AdresseInvalide(TextesAdresseServeur.identifiants);
  }
  if (uri.hasQuery || uri.hasFragment || texte.endsWith('?')) {
    return const AdresseInvalide(TextesAdresseServeur.parametres);
  }
  var chemin = uri.path;
  while (chemin.endsWith('/')) {
    chemin = chemin.substring(0, chemin.length - 1);
  }
  final bas = chemin.toLowerCase();
  if (bas == '/api/v1') {
    chemin = '';
  } else if (bas == '/api') {
    chemin = '';
  }
  if (chemin.isNotEmpty) {
    return const AdresseInvalide(TextesAdresseServeur.chemin);
  }
  final schema = uri.scheme.toLowerCase();
  if (schema == 'http' && !_estLocal(hote)) {
    return const AdresseInvalide(TextesAdresseServeur.httpsExige);
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final machine = hote.contains(':') ? '[$hote]' : hote;
  return AdresseValide(AdresseServeur._('$schema://$machine$port'));
}

/// Un nom de machine ou une adresse IP plausibles (lettres, chiffres, `-`,
/// `.`, ou une adresse IPv6).
bool _hoteLisible(String hote) =>
    hote.contains(':') ||
    RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(hote);

/// Les hôtes où `http` reste permis : le poste lui-même et le réseau local.
bool _estLocal(String hote) {
  if (hote == 'localhost' || hote == '127.0.0.1') return true;
  final octets = RegExp(
    r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$',
  ).firstMatch(hote);
  if (octets == null) return false;
  final a = int.parse(octets.group(1)!);
  final b = int.parse(octets.group(2)!);
  return a == 10 || (a == 192 && b == 168);
}

/// La racine à montrer pour une adresse d'API enregistrée (`…/api/v1`), ou
/// `null` si elle n'est pas lisible. N'impose pas les règles de saisie : une
/// adresse déjà enregistrée s'affiche telle qu'elle est.
String? racineDepuisUrlApi(String? urlApi) {
  if (urlApi == null || urlApi.trim().isEmpty) return null;
  var r = urlApi.trim();
  while (r.endsWith('/')) {
    r = r.substring(0, r.length - 1);
  }
  for (final suffixe in const [suffixeApiServeur, '/api']) {
    if (r.toLowerCase().endsWith(suffixe)) {
      r = r.substring(0, r.length - suffixe.length);
      break;
    }
  }
  return r.isEmpty ? null : r;
}
