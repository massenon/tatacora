/// La SIGNATURE et le CACHET des documents A4 (factures, proformas) SUR CE POSTE
/// (PO, 07/11/2026) : déposés au serveur (Paramètres > Logo & Apparence), DESCENDUS
/// ici en lecture — le poste n'en dépose jamais.
///
/// Les fichiers vivent À CÔTÉ de `poste.json`, dans le dossier d'apparence (comme le
/// logo : `…/TATACORA/apparence/`), un SEUL par usage, au nom fixe
/// (`signature.<ext>`, `cachet.<ext>`) : en ranger un supprime d'abord toute variante.
/// L'empreinte courte (16 premiers caractères du SHA-256) est celle que le serveur rend :
/// elle dit au serveur qu'une image inchangée n'a pas à être renvoyée.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../parametres/data/apparence_poste.dart';

/// Les deux images d'un document.
enum ImageDocument {
  signature('signature'),
  cachet('cachet');

  const ImageDocument(this.nom);

  final String nom;
}

const List<String> _extensions = ['png', 'jpg', 'jpeg'];

/// L'extension d'une image d'après ses octets (`null` : ni PNG ni JPEG).
String? extensionImage(List<int> octets) {
  if (octets.length >= 8 &&
      octets[0] == 0x89 &&
      octets[1] == 0x50 &&
      octets[2] == 0x4E &&
      octets[3] == 0x47) {
    return 'png';
  }
  if (octets.length >= 3 &&
      octets[0] == 0xFF &&
      octets[1] == 0xD8 &&
      octets[2] == 0xFF) {
    return 'jpg';
  }
  return null;
}

final class ImagesDocumentPoste {
  const ImagesDocumentPoste(this._dossier);

  final Future<Directory> Function() _dossier;

  /// L'empreinte courte d'[octets] — la même que `empreinteImageDocument` du serveur.
  static String empreinteDe(List<int> octets) =>
      crypto.sha256.convert(octets).toString().substring(0, 16);

  Future<Uint8List?> lire(ImageDocument image) async {
    final f = await _fichier(image);
    return f?.readAsBytesSync();
  }

  Future<String?> empreinte(ImageDocument image) async {
    final octets = await lire(image);
    return octets == null ? null : empreinteDe(octets);
  }

  /// Range [octets] (PNG ou JPEG, 400 Ko au plus — la borne du serveur). Rien n'est écrit
  /// sur un refus ; rend `false` dans ce cas.
  Future<bool> ranger(ImageDocument image, List<int> octets) async {
    final extension = extensionImage(octets);
    if (extension == null || octets.isEmpty || octets.length > 400 * 1024) {
      return false;
    }
    final dossier = await _dossier();
    dossier.createSync(recursive: true);
    _supprimer(dossier, image);
    File(
      p.join(dossier.path, '${image.nom}.$extension'),
    ).writeAsBytesSync(octets, flush: true);
    return true;
  }

  /// Le serveur n'a plus d'image : le poste n'en garde pas.
  Future<void> retirer(ImageDocument image) async {
    final dossier = await _dossier();
    if (dossier.existsSync()) _supprimer(dossier, image);
  }

  Future<File?> _fichier(ImageDocument image) async {
    final dossier = await _dossier();
    if (!dossier.existsSync()) return null;
    for (final e in _extensions) {
      final f = File(p.join(dossier.path, '${image.nom}.$e'));
      if (f.existsSync()) return f;
    }
    return null;
  }

  void _supprimer(Directory dossier, ImageDocument image) {
    for (final e in _extensions) {
      final f = File(p.join(dossier.path, '${image.nom}.$e'));
      if (f.existsSync()) f.deleteSync();
    }
  }
}

final imagesDocumentPosteProvider = Provider<ImagesDocumentPoste>(
  (ref) => ImagesDocumentPoste(ref.watch(dossierApparenceProvider)),
);

/// Les octets de la signature descendue (`null` : aucune). Relu après chaque descente.
final signatureDocumentProvider = FutureProvider<Uint8List?>(
  (ref) => ref.watch(imagesDocumentPosteProvider).lire(ImageDocument.signature),
);

final cachetDocumentProvider = FutureProvider<Uint8List?>(
  (ref) => ref.watch(imagesDocumentPosteProvider).lire(ImageDocument.cachet),
);
