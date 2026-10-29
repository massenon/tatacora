/// « Se souvenir de moi » de l'écran de connexion — l'IDENTIFIANT seul.
///
/// Vue Blade maîtresse : l'écran de connexion de la PWA mémorise l'identifiant
/// dans le navigateur (`localStorage`, côté client) et JAMAIS le mot de passe.
/// Le poste fait la même chose dans un petit fichier à côté de `poste.json`
/// (`…/TATACORA/connexion/identifiant.txt`) : ni la base Drift (aucune
/// migration), ni le coffre `flutter_secure_storage` (un identifiant n'est pas
/// un secret, et il doit rester lisible avant toute session).
///
/// Ce n'est PAS une session persistante : rien ici n'authentifie, la
/// connexion repasse par `SessionRepository.connecter` à chaque fois.
///
/// E/S SYNCHRONES, comme `poste.json` et `ApparencePoste` : une file de
/// `Future` d'E/S s'est déjà bloquée sous le temps simulé des tests.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../transverse/data/configuration_poste.dart';

final class IdentifiantMemorise {
  const IdentifiantMemorise(this._dossier);

  final Future<Directory> Function() _dossier;

  static const String _nomFichier = 'identifiant.txt';

  /// L'identifiant mémorisé, `null` s'il n'y en a pas — ou si le disque ne
  /// répond pas : la mémoire est un confort, jamais un obstacle à la connexion.
  Future<String?> lire() async {
    try {
      final fichier = File(p.join((await _dossier()).path, _nomFichier));
      if (!fichier.existsSync()) return null;
      final valeur = fichier.readAsStringSync().trim();
      return valeur.isEmpty ? null : valeur;
    } on Object {
      return null;
    }
  }

  /// Mémorise [identifiant]. Une erreur d'écriture est avalée : se connecter
  /// prime sur se souvenir.
  Future<void> enregistrer(String identifiant) async {
    try {
      final dossier = await _dossier();
      dossier.createSync(recursive: true);
      File(
        p.join(dossier.path, _nomFichier),
      ).writeAsStringSync(identifiant.trim(), flush: true);
    } on Object {
      // Voir l'en-tête de la méthode.
    }
  }

  /// Oublie l'identifiant (case décochée).
  Future<void> oublier() async {
    try {
      final fichier = File(p.join((await _dossier()).path, _nomFichier));
      if (fichier.existsSync()) fichier.deleteSync();
    } on Object {
      // Idem.
    }
  }
}

/// Le dossier de la mémoire : à côté de `poste.json`. Surchargé par les tests.
final dossierConnexionProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join(p.dirname(await cheminConfigurationPoste()), 'connexion'),
      ),
);

final identifiantMemoriseProvider = Provider<IdentifiantMemorise>(
  (ref) => IdentifiantMemorise(ref.watch(dossierConnexionProvider)),
);
