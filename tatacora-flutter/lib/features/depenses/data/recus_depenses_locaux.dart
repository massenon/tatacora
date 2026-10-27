/// Le RANGEMENT des reçus de dépenses sur le poste (lot L4, 27/10/2026).
///
/// Le fichier n'est JAMAIS dans la base : il est rangé dans `recus_depenses/` à
/// côté de `poste.json` — comme les archives de clôture (`archives/`) et les
/// captures du formulaire de contact (`captures_editeur/`) — sous le nom
/// `<id de la dépense>.<extension>`. `depenses_local` n'en garde que la
/// RÉFÉRENCE (nom, empreinte SHA-256, taille, type, état). Le dossier est hors
/// de la sauvegarde de la base : à copier avec elle.
///
/// ## Écriture atomique
///
/// Le fichier est écrit sous un nom provisoire puis RENOMMÉ : un arrêt en plein
/// rangement ne laisse jamais un fichier tronqué sous le nom définitif, que
/// l'envoi prendrait pour le reçu.
///
/// ## Un nom ne sort jamais du dossier
///
/// Le nom vient de la base du poste, mais un nom qui porterait un séparateur
/// n'ouvre rien hors du dossier : [fichier] refuse tout nom qui n'est pas un
/// simple nom de fichier.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import '../domain/recu_depense.dart';

/// Un reçu rangé : le nom du fichier, son empreinte et sa taille.
final class RecuRange {
  const RecuRange({
    required this.nom,
    required this.sha256,
    required this.taille,
  });

  final String nom;
  final String sha256;
  final int taille;
}

class RecusDepensesLocaux {
  /// [racine] : le dossier des reçus (créé au besoin).
  RecusDepensesLocaux(this._racine);

  final Future<Directory> Function() _racine;

  /// L'empreinte SHA-256 hexadécimale de [octets].
  static String empreinte(List<int> octets) =>
      crypto.sha256.convert(octets).toString();

  /// Le nom du fichier du reçu de [depenseId].
  static String nomDe(String depenseId, TypeRecu type) =>
      '$depenseId.${type.extension}';

  /// Range [octets] comme le reçu de [depenseId] (le précédent, s'il y en a un
  /// sous un autre nom, est retiré).
  Future<RecuRange> ranger(
    String depenseId,
    TypeRecu type,
    List<int> octets,
  ) async {
    final nom = nomDe(depenseId, type);
    final dossier = await _racine();
    await dossier.create(recursive: true);
    final provisoire = File(p.join(dossier.path, '$nom.tmp'));
    await provisoire.writeAsBytes(octets, flush: true);
    final definitif = File(p.join(dossier.path, nom));
    await provisoire.rename(definitif.path);
    for (final autre in TypeRecu.values) {
      if (autre == type) continue;
      final ancien = File(p.join(dossier.path, nomDe(depenseId, autre)));
      if (ancien.existsSync()) await ancien.delete();
    }
    return RecuRange(
      nom: nom,
      sha256: empreinte(octets),
      taille: octets.length,
    );
  }

  /// Le fichier [nom], ou `null` s'il n'existe pas (ou si [nom] n'est pas un
  /// simple nom de fichier). Un dossier illisible n'est jamais une erreur : le
  /// reçu est alors « introuvable », et l'écran le dit.
  Future<File?> fichier(String? nom) async {
    if (nom == null || nom.isEmpty || p.basename(nom) != nom) return null;
    try {
      final f = File(p.join((await _racine()).path, nom));
      return f.existsSync() ? f : null;
    } on Object {
      return null;
    }
  }

  /// Les octets du fichier [nom], ou `null`.
  Future<Uint8List?> lire(String? nom) async {
    final f = await fichier(nom);
    if (f == null) return null;
    try {
      return await f.readAsBytes();
    } on Object {
      return null;
    }
  }

  Future<void> retirer(String? nom) async {
    final f = await fichier(nom);
    if (f != null) await f.delete();
  }
}
