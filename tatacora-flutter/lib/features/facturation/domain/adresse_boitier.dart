/// L'ADRESSE DU PILOTE du boîtier CC300 — sa saisie, sa validation, sa
/// normalisation (07/11/2026). Même esprit que `adresse_serveur.dart` : vit
/// dans `poste.json`, modifiable sans recompiler.
///
/// Le pilote n'a AUCUNE authentification (`Readme.md` du pilote : « NOT YET
/// IMPLEMENTED ») : le client n'appelle donc que l'adresse réglée, et cette
/// adresse doit être le poste lui-même ou le réseau local.
///
/// Règles : `http://` ou `https://` ; `http` seulement pour `localhost`,
/// `127.0.0.1`, `10.x.x.x`, `192.168.x.x` ; ni espace, ni identifiants, ni
/// chemin, ni paramètres ; une barre finale est retirée ; 255 caractères.
library;

const String adresseBoitierParDefaut = 'http://localhost:38917';

const int longueurMaxAdresseBoitier = 255;

abstract final class TextesAdresseBoitier {
  static const vide = 'Saisissez l’adresse du pilote du boîtier.';
  static const tropLongue =
      'L’adresse du pilote est trop longue (255 caractères au plus).';
  static const espaces = 'L’adresse du pilote ne doit contenir aucun espace.';
  static const schema =
      'L’adresse doit commencer par http:// ou https:// '
      '(par exemple http://localhost:38917).';
  static const illisible =
      'Cette adresse n’est pas valide : vérifiez-la '
      '(par exemple http://localhost:38917).';
  static const httpLocalSeulement =
      'Le pilote n’a pas de mot de passe : http:// n’est accepté que pour ce '
      'poste ou le réseau local (localhost, 127.0.0.1, 10.x ou 192.168.x).';
  static const identifiants =
      'L’adresse ne doit pas contenir d’identifiant ni de mot de passe.';
  static const chemin =
      'L’adresse ne doit contenir ni chemin, ni paramètre, ni ancre : '
      'saisissez seulement l’hôte et le port.';
}

sealed class ResultatAdresseBoitier {
  const ResultatAdresseBoitier();
}

final class AdresseBoitierValide extends ResultatAdresseBoitier {
  const AdresseBoitierValide(this.racine);

  /// `http://hote:port`, sans barre finale.
  final String racine;
}

final class AdresseBoitierInvalide extends ResultatAdresseBoitier {
  const AdresseBoitierInvalide(this.message);
  final String message;
}

ResultatAdresseBoitier validerAdresseBoitier(String? saisie) {
  final texte = (saisie ?? '').trim();
  if (texte.isEmpty) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.vide);
  }
  if (texte.length > longueurMaxAdresseBoitier) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.tropLongue);
  }
  if (RegExp(r'\s').hasMatch(texte)) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.espaces);
  }
  final bas = texte.toLowerCase();
  if (!bas.startsWith('http://') && !bas.startsWith('https://')) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.schema);
  }
  final Uri uri;
  try {
    uri = Uri.parse(texte);
  } on FormatException {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.illisible);
  }
  final hote = uri.host.toLowerCase();
  if (hote.isEmpty ||
      !(hote.contains(':') ||
          RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(hote))) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.illisible);
  }
  if (uri.userInfo.isNotEmpty) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.identifiants);
  }
  var chemin = uri.path;
  while (chemin.endsWith('/')) {
    chemin = chemin.substring(0, chemin.length - 1);
  }
  if (chemin.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      texte.endsWith('?')) {
    return const AdresseBoitierInvalide(TextesAdresseBoitier.chemin);
  }
  final schema = uri.scheme.toLowerCase();
  if (schema == 'http' && !_estLocal(hote)) {
    return const AdresseBoitierInvalide(
      TextesAdresseBoitier.httpLocalSeulement,
    );
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  final machine = hote.contains(':') ? '[$hote]' : hote;
  return AdresseBoitierValide('$schema://$machine$port');
}

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
