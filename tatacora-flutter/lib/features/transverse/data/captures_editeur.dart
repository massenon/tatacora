/// Les captures d'écran jointes aux signalements de bug — « Capture d'écran
/// (optionnel) » de « Signaler un bug ».
///
/// Le serveur range le fichier sur son disque public (`captures_bug`) et le
/// courriel le joint. Ce poste le range à côté de `poste.json`, sous
/// `captures_editeur/<id du message>.<png|jpg>` : AUCUNE colonne de plus
/// (le schéma de la base ne bouge pas) — le message sait qu'il porte une
/// capture parce que le fichier de son identifiant existe. Le fichier survit
/// au redémarrage, donc à la relance d'un envoi resté en file.
///
/// Les bornes sont celles du serveur (`ContactEditeur::CAPTURE_MAX_KO` = 2048,
/// `mimes:png,jpg,jpeg`).
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'configuration_poste.dart';

/// Les bornes de la capture — `ContactEditeur::CAPTURE_MAX_KO` et ses `mimes`.
abstract final class BornesCapture {
  static const int maxKo = 2048;
  static const List<String> extensions = ['png', 'jpg', 'jpeg'];
}

/// Pourquoi une capture est refusée — les phrases du serveur
/// (`validation.image`, `validation.max.file`).
abstract final class TextesCapture {
  static const String nonImage =
      "Le champ capture d'écran doit être une image PNG ou JPG.";
  static String tropLourde() =>
      "Le fichier capture d'écran ne peut pas peser plus de "
      '${BornesCapture.maxKo} kilo-octets.';
}

/// L'issue du contrôle d'une capture : la phrase du refus, ou `null`.
String? verifierCapture(String nom, int octets) {
  final extension = p.extension(nom).replaceFirst('.', '').toLowerCase();
  if (!BornesCapture.extensions.contains(extension)) {
    return TextesCapture.nonImage;
  }
  if (octets > BornesCapture.maxKo * 1024) return TextesCapture.tropLourde();
  return null;
}

/// Le rangement des captures.
class CapturesEditeur {
  CapturesEditeur({Future<String> Function()? cheminConfiguration})
    : _chemin = cheminConfiguration ?? cheminConfigurationPoste;

  final Future<String> Function() _chemin;

  Future<Directory> _dossier() async =>
      Directory(p.join(p.dirname(await _chemin()), 'captures_editeur'));

  /// Range la capture du message [idMessage] (la précédente est remplacée).
  Future<File> joindre(
    String idMessage, {
    required String nom,
    required List<int> octets,
  }) async {
    final refus = verifierCapture(nom, octets.length);
    if (refus != null) throw ArgumentError(refus);
    final dossier = await _dossier();
    await dossier.create(recursive: true);
    await retirer(idMessage);
    final extension = p.extension(nom).toLowerCase();
    final fichier = File(p.join(dossier.path, '$idMessage$extension'));
    await fichier.writeAsBytes(octets, flush: true);
    return fichier;
  }

  /// Le fichier de la capture de [idMessage], ou `null`.
  ///
  /// Une capture introuvable n'est JAMAIS une erreur d'envoi : dossier absent,
  /// chemin de configuration illisible (un banc sans greffon) — le message
  /// part sans elle, comme le serveur quand le fichier manque.
  Future<File?> de(String idMessage) async {
    final Directory dossier;
    try {
      dossier = await _dossier();
    } on Object {
      return null;
    }
    if (!dossier.existsSync()) return null;
    for (final extension in BornesCapture.extensions) {
      final fichier = File(p.join(dossier.path, '$idMessage.$extension'));
      if (fichier.existsSync()) return fichier;
    }
    return null;
  }

  /// Parmi [ids], ceux qui portent une capture.
  Future<Set<String>> avecCapture(Iterable<String> ids) async => {
    for (final id in ids)
      if (await de(id) != null) id,
  };

  Future<void> retirer(String idMessage) async {
    final fichier = await de(idMessage);
    if (fichier != null) await fichier.delete();
  }
}
