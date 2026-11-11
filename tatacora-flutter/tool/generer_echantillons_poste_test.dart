/// Régénère les échantillons du POSTE dans `presentation/` (racine du dépôt) :
///
///     flutter test tool/generer_echantillons_poste_test.dart
///
/// Variable facultative `PRESENTATION_DIR` : autre dossier de sortie. Ce fichier n'est PAS
/// dans `test/` : `flutter test` seul ne l'exécute jamais, il n'écrit donc jamais dans le dépôt
/// par accident. Les vérifications vivent dans
/// `test/features/facturation/echantillons_presentation_test.dart`.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';

import '../test/outils/echantillons_presentation.dart';
import '../test/outils/kit_essai_boitier.dart';

void main() {
  test('écrit les échantillons du poste dans presentation/', () async {
    final sortie = Directory(
      Platform.environment['PRESENTATION_DIR'] ?? '../presentation',
    )..createSync(recursive: true);
    final logo = File(AppAssets.logo).readAsBytesSync();

    for (final e in await genererEchantillonsPoste(logo: logo)) {
      File('${sortie.path}/${e.nom}').writeAsBytesSync(e.pdf);
      // ignore: avoid_print
      print('${e.nom} — ${e.pdf.length} octets');
    }

    final kit = Directory('${sortie.path}/05_essai_boitier')
      ..createSync(recursive: true);
    for (final e in jsonDuKit().entries) {
      File('${kit.path}/${e.key}').writeAsStringSync(e.value);
      // ignore: avoid_print
      print('05_essai_boitier/${e.key}');
    }
  });
}
