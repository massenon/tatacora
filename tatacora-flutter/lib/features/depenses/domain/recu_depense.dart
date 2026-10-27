/// Le REÇU en image d'une dépense (lot L4, décision du PO du 27/10/2026 : la
/// dépense du poste accepte, comme l'écran web, un reçu en image, et le fichier
/// voyage par la synchronisation).
///
/// Ce fichier est PUR (aucune E/S) : les bornes, les refus et l'état d'un reçu.
///
/// ## Les bornes sont celles du web
///
/// `Depenses::enregistrerDepense` valide `photoRecu` par `nullable|image|max:400` :
/// un fichier IMAGE (jpg, jpeg, png, gif, bmp, webp — jamais svg) d'au plus
/// 400 kilo-octets, jugé sur son CONTENU et non sur son nom. Ce poste juge de
/// même ([verifierRecu]) et dit les MÊMES phrases (celles de `validation.image`
/// et `validation.max.file`, avec l'attribut `photo recu` que Laravel fabrique
/// du nom `photoRecu`). Le serveur rejuge au dépôt avec sa propre règle ;
/// `depenses_recu_contre_serveur_test.dart` confronte les deux sur un corpus.
///
/// ## L'état d'un reçu ne se dit que s'il est VRAI
///
/// [StatutRecu.envoye] n'est écrit qu'après l'ACCUSÉ du serveur (le 200 du
/// dépôt, ou la référence du reçu qui redescend du serveur avec la même
/// empreinte). Un reçu hors réseau, ou une synchronisation éteinte, reste
/// [StatutRecu.enAttente] : jamais « envoyé » sur la foi d'un envoi tenté.
library;

import 'dart:typed_data';

/// La taille maximale du reçu — `Depenses::RECU_MAX_KO`, `max:400` du web.
const int tailleMaxRecuKo = 400;

/// …en octets (400 × 1024, comme le validateur de Laravel : un fichier PILE à
/// la borne passe, un octet de plus est refusé).
const int tailleMaxRecuOctets = tailleMaxRecuKo * 1024;

/// Le nom du dossier des reçus, à côté de `poste.json` — celui du disque public
/// du serveur (`RecuDepenseService::DOSSIER`).
const String dossierRecusDepenses = 'recus_depenses';

/// Les types d'image que la règle `image` de Laravel accepte (svg exclu).
enum TypeRecu {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  gif('image/gif', 'gif'),
  bmp('image/bmp', 'bmp'),
  webp('image/webp', 'webp');

  const TypeRecu(this.mime, this.extension);

  final String mime;
  final String extension;

  /// Les extensions que la fenêtre « Ouvrir » propose (`accept="image/*"` du
  /// web, restreint à ce que le serveur accepte).
  static const List<String> extensionsProposees = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'bmp',
    'webp',
  ];

  static TypeRecu? depuisMime(String? mime) {
    for (final t in values) {
      if (t.mime == mime) return t;
    }
    return null;
  }
}

/// Les phrases du web (`validation.image`, `validation.max.file`) et celles du
/// dépôt, au mot.
abstract final class TextesRecu {
  /// `Le champ :attribute doit être une image.` — attribut `photo recu`.
  static const String nonImage = 'Le champ photo recu doit être une image.';

  /// `Le fichier :attribute ne peut pas peser plus de :max kilo-octets.`
  static const String tropLourd =
      'Le fichier photo recu ne peut pas peser plus de $tailleMaxRecuKo '
      'kilo-octets.';

  /// Un fichier sans octet (`depenses.recu_vide`).
  static const String vide = 'Le reçu est vide : aucun octet reçu.';
}

/// Les causes que le POSTE dit lui-même (le serveur, lui, dit les siennes).
abstract final class TextesRecuPoste {
  /// La référence redescendue porte une autre empreinte que le fichier de ce
  /// poste : le serveur détenait déjà un autre reçu pour cette dépense.
  static const String autreRecuAuServeur =
      'Le serveur détient déjà un autre reçu pour cette dépense : un reçu ne '
      'se remplace pas.';

  /// Le fichier rangé sur ce poste a disparu avant son envoi.
  static const String fichierIntrouvable =
      'Le fichier du reçu est introuvable sur ce poste : il n’a pas pu être '
      'envoyé.';

  /// Le fichier rangé n'est plus celui qui a été joint (empreinte différente).
  static const String fichierModifie =
      'Le fichier du reçu a changé sur ce poste depuis qu’il a été joint : il '
      'n’a pas été envoyé.';

  /// Le serveur a refusé sans phrase lisible.
  static String refuseParLeServeur(int codeHttp) =>
      'Refusé par le serveur (HTTP $codeHttp).';
}

/// L'issue du contrôle d'un fichier choisi.
sealed class IssueRecu {
  const IssueRecu();
}

final class RecuAccepte extends IssueRecu {
  const RecuAccepte(this.type);

  final TypeRecu type;
}

final class RecuRefuse extends IssueRecu {
  const RecuRefuse(this.phrase);

  /// La phrase du web, dite telle quelle à l'opérateur.
  final String phrase;
}

/// Juge [octets] comme le fait l'écran web : image reconnue à son CONTENU,
/// d'au plus 400 Ko. L'ordre est celui de Laravel (type puis taille) pour la
/// phrase d'un fichier qui cumulerait les deux défauts : le type d'abord.
IssueRecu verifierRecu(List<int> octets) {
  if (octets.isEmpty) return const RecuRefuse(TextesRecu.vide);
  final type = typeRecuDepuisOctets(octets);
  if (type == null) return const RecuRefuse(TextesRecu.nonImage);
  if (octets.length > tailleMaxRecuOctets) {
    return const RecuRefuse(TextesRecu.tropLourd);
  }
  return RecuAccepte(type);
}

/// Le type d'image reconnu à l'EN-TÊTE du fichier, jamais à son nom — ou
/// `null`. Reprend les signatures que `finfo` (donc `guessExtension()` de
/// Laravel) exige : une simple signature sans la suite d'un vrai fichier
/// (`PNG` sans `IHDR`, `BM` sans en-tête DIB, `JPEG` sans marqueur) n'est PAS
/// une image pour le serveur, ni ici.
TypeRecu? typeRecuDepuisOctets(List<int> o) {
  bool debute(List<int> signature, [int decalage = 0]) {
    if (o.length < decalage + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (o[decalage + i] != signature[i]) return false;
    }
    return true;
  }

  // JPEG : FF D8 FF, puis l'octet d'un marqueur (APPn, DQT, SOFn…).
  if (debute(const [0xFF, 0xD8, 0xFF]) && o.length > 3 && o[3] >= 0xC0) {
    return TypeRecu.jpeg;
  }
  // PNG : la signature de huit octets, puis le bloc IHDR.
  if (debute(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) &&
      debute(const [0x49, 0x48, 0x44, 0x52], 12)) {
    return TypeRecu.png;
  }
  // GIF : GIF87a ou GIF89a.
  if (debute('GIF87a'.codeUnits) || debute('GIF89a'.codeUnits)) {
    return TypeRecu.gif;
  }
  // WebP : RIFF, quatre octets de taille, WEBP.
  if (debute('RIFF'.codeUnits) && debute('WEBP'.codeUnits, 8)) {
    return TypeRecu.webp;
  }
  // BMP : « BM », puis une taille d'en-tête DIB connue à l'octet 14.
  if (debute('BM'.codeUnits) && o.length >= 18) {
    final dib = ByteData.sublistView(
      Uint8List.fromList(o.sublist(14, 18)),
    ).getUint32(0, Endian.little);
    if (const {12, 40, 52, 56, 64, 108, 124}.contains(dib)) return TypeRecu.bmp;
  }
  return null;
}

/// L'état d'un reçu — ce qui se DIT à l'écran.
enum StatutRecu {
  /// Joint sur ce poste, pas encore accusé par le serveur : hors réseau,
  /// synchronisation éteinte, ou dépense pas encore acceptée.
  enAttente('en_attente'),

  /// Le serveur l'a accusé (200 du dépôt, ou sa référence redescendue avec la
  /// même empreinte).
  envoye('envoye'),

  /// Le serveur l'a refusé : la cause est dite ([RecuDepense.cause]).
  refuse('refuse'),

  /// Reçu d'une dépense venue d'un autre poste (ou saisie au serveur) : seule
  /// la référence est ici ; le fichier se télécharge À LA DEMANDE.
  duServeur('du_serveur');

  const StatutRecu(this.code);

  /// La valeur stockée dans `depenses_local.recu_statut`.
  final String code;

  static StatutRecu? depuisCode(String? code) {
    for (final s in values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Le reçu d'une dépense, tel que le poste le tient.
final class RecuDepense {
  const RecuDepense({
    required this.statut,
    this.nom,
    this.sha256,
    this.taille,
    this.type,
    this.cause,
  });

  final StatutRecu statut;

  /// Le fichier rangé sur ce poste (`recus_depenses/<nom>`), ou `null` tant
  /// qu'il n'a pas été téléchargé.
  final String? nom;

  /// L'empreinte SHA-256 du fichier — `null` pour un reçu que l'écran web du
  /// serveur a joint avant que les empreintes existent.
  final String? sha256;

  final int? taille;

  /// Le type MIME (`image/png`…).
  final String? type;

  /// La cause d'un refus du serveur, en français.
  final String? cause;

  /// Le fichier est-il sur ce poste ?
  bool get estLocal => nom != null;
}

/// Un fichier à joindre à la saisie : ses octets, déjà jugés par
/// [verifierRecu].
final class RecuAJoindre {
  RecuAJoindre({required this.nom, required this.octets, required this.type});

  /// Le nom d'origine, pour l'afficher dans la modale.
  final String nom;
  final Uint8List octets;
  final TypeRecu type;
}
