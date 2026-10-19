import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le registre des paramètres du SERVEUR, relu en exécutant PHP.
///
/// `tool/parametres/exporter_registre.php` charge `RegistreParametres` par
/// l'autoloader de Composer (aucune base, aucun démarrage de l'application) et
/// rend les définitions, les motifs de secret et le fichier de langue
/// `lang/fr/parametres.php`. Les tests confrontent la copie locale à CETTE
/// sortie : une liste recopiée à la main dans un test ne vérifierait qu'elle-même
/// et resterait verte le jour où le serveur changerait.
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas — comme
/// le comparateur de conformité (un garde qui saute est vert à vide).
final class RegistreServeur {
  RegistreServeur._(this.definitions, this.motifsSecret, this.langue);

  final List<Map<String, dynamic>> definitions;
  final List<String> motifsSecret;
  final Map<String, dynamic> langue;

  static RegistreServeur? _cache;

  static RegistreServeur charger() {
    final deja = _cache;
    if (deja != null) return deja;

    final r = Process.runSync('php', [
      'tool/parametres/exporter_registre.php',
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) {
      fail(
        'Le registre du serveur n’a pas pu être relu (php, code '
        '${r.exitCode}) : ${r.stderr}. C’est un ÉCHEC, pas un saut.',
      );
    }
    final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    return _cache = RegistreServeur._(
      [
        for (final d in json['definitions'] as List<dynamic>)
          d as Map<String, dynamic>,
      ],
      [for (final m in json['motifs_secret'] as List<dynamic>) m as String],
      json['langue'] as Map<String, dynamic>,
    );
  }
}
