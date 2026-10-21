/// Logo et favicon de l'établissement SUR CE POSTE (Paramètres → Logo &
/// Apparence), le pendant de `ApparenceEtablissementService` du serveur.
///
/// Les fichiers vivent À CÔTÉ de `poste.json` (`…/TATACORA/apparence/`), jamais
/// dans la base : ce sont des octets, pas des paramètres. Un SEUL fichier par
/// usage, au nom fixe (`logo.<ext>`, `favicon.<ext>`) : en enregistrer un
/// supprime d'abord toute variante existante, sinon le dossier accumulerait des
/// fichiers morts et la lecture pourrait rendre l'ancien. L'ancien fichier n'est
/// pas conservé (le serveur le dit aussi).
///
/// Tant que rien n'est téléversé, l'actif LIVRÉ (`AppAssets.logo`) reste le
/// repli de toutes les surfaces — le rendu par défaut est celui de la vue.
///
/// Écart nommé : l'en-tête des états imprimés (`entete_etablissement.dart`)
/// lit encore l'actif livré ; le logo téléversé n'est employé que par la barre
/// supérieure et cet onglet.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../core/fichiers/selecteur_fichiers.dart';
import '../../transverse/data/configuration_poste.dart';

/// Un refus de téléversement — la phrase est dite à l'écran.
final class RefusApparence implements Exception {
  const RefusApparence(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Quel fichier d'apparence.
enum UsageApparence {
  /// PNG ou JPG, 2 Mo au plus (`mimes:png,jpg,jpeg`, `max:2048`).
  logo('logo', ['png', 'jpg', 'jpeg'], 2048 * 1024),

  /// PNG, JPG ou ICO, 512 Ko au plus (`max:512`).
  favicon('favicon', ['png', 'jpg', 'jpeg', 'ico'], 512 * 1024);

  const UsageApparence(this.nom, this.extensions, this.tailleMax);

  final String nom;
  final List<String> extensions;
  final int tailleMax;
}

/// Les phrases de refus.
abstract final class TextesRefusApparence {
  static String format(UsageApparence u) => switch (u) {
    UsageApparence.logo => 'Le logo doit être un fichier PNG ou JPG.',
    UsageApparence.favicon =>
      'Le favicon doit être un fichier PNG, JPG ou ICO.',
  };

  static String taille(UsageApparence u) => switch (u) {
    UsageApparence.logo => 'Le logo ne doit pas dépasser 2 Mo.',
    UsageApparence.favicon => 'Le favicon ne doit pas dépasser 512 Ko.',
  };

  static const vide = 'Le fichier choisi est vide.';
}

final class ApparencePoste {
  const ApparencePoste(this._dossier);

  /// Le dossier des fichiers d'apparence.
  final Future<Directory> Function() _dossier;

  /// Les octets du fichier téléversé, `null` s'il n'y en a pas.
  Future<Uint8List?> lire(UsageApparence usage) async {
    final fichier = await _fichier(usage);
    return fichier?.readAsBytesSync();
  }

  /// Remplace le fichier de [usage] par [choisi] — après contrôle de son
  /// extension et de sa taille. Rien n'est écrit sur un refus.
  Future<void> enregistrer(UsageApparence usage, FichierLu choisi) async {
    final extension = p
        .extension(choisi.nom)
        .replaceFirst('.', '')
        .toLowerCase();
    if (!usage.extensions.contains(extension)) {
      throw RefusApparence(TextesRefusApparence.format(usage));
    }
    if (choisi.octets.isEmpty) {
      throw const RefusApparence(TextesRefusApparence.vide);
    }
    if (choisi.octets.length > usage.tailleMax) {
      throw RefusApparence(TextesRefusApparence.taille(usage));
    }

    final dossier = await _dossier();
    // E/S SYNCHRONES, comme `poste.json` : deux fichiers de quelques Ko, et
    // une file de `Future` d'E/S s'était bloquée sous le temps simulé des tests.
    dossier.createSync(recursive: true);
    _supprimerVariantes(dossier, usage);
    File(
      p.join(dossier.path, '${usage.nom}.$extension'),
    ).writeAsBytesSync(choisi.octets, flush: true);
  }

  Future<File?> _fichier(UsageApparence usage) async {
    final dossier = await _dossier();
    if (!dossier.existsSync()) return null;
    for (final extension in usage.extensions) {
      final f = File(p.join(dossier.path, '${usage.nom}.$extension'));
      if (f.existsSync()) return f;
    }
    return null;
  }

  void _supprimerVariantes(Directory dossier, UsageApparence usage) {
    for (final extension in usage.extensions) {
      final f = File(p.join(dossier.path, '${usage.nom}.$extension'));
      if (f.existsSync()) f.deleteSync();
    }
  }
}

/// Le dossier d'apparence : à côté de `poste.json`. Surchargé par les tests
/// (aucun greffon `path_provider` sous `flutter test`).
final dossierApparenceProvider = Provider<Future<Directory> Function()>(
  (ref) =>
      () async => Directory(
        p.join(p.dirname(await cheminConfigurationPoste()), 'apparence'),
      ),
);

final apparencePosteProvider = Provider<ApparencePoste>(
  (ref) => ApparencePoste(ref.watch(dossierApparenceProvider)),
);

/// Les octets du logo téléversé (`null` : l'actif livré). Relu après chaque
/// enregistrement (`ref.invalidate`).
final logoTeleverseProvider = FutureProvider<Uint8List?>(
  (ref) => ref.watch(apparencePosteProvider).lire(UsageApparence.logo),
);

/// Les octets du favicon téléversé (`null` : l'actif livré).
final faviconTeleverseProvider = FutureProvider<Uint8List?>(
  (ref) => ref.watch(apparencePosteProvider).lire(UsageApparence.favicon),
);
