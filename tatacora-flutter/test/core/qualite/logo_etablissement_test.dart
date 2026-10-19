import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:tatacora_flutter/core/impression/entete_a4.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';

import '../../support/vue_blade.dart';

/// Le logo de l'établissement est le PNG du Product Owner — décision du
/// 14/10/2026 (dans le chat au lead), ticket D392, PA-210.
///
/// La vue d'abord, le Flutter suit : le fichier embarqué est OCTET POUR OCTET
/// celui que sert la vue (`tatacora-api/public/assets/img/logo.png`), le seul
/// chemin du code est `AppAssets.logo`, et plus aucune ligne de code ne
/// désigne l'ancien `logo.jpg`. Le rendu dans les cadres (`BoxFit.contain`)
/// est éprouvé écran par écran : `coquille_rendu_test`,
/// `ecran_demarrage_test`, `ecran_connexion_test`.
void main() {
  final ancienLogo = RegExp(r'logo\.jpe?g', caseSensitive: false);

  /// Les lignes de CODE d'un fichier Dart — commentaires de ligne retirés :
  /// raconter l'historique du logo n'est pas l'afficher.
  String code(File f) => const LineSplitter()
      .convert(f.readAsStringSync())
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  List<File> dart(String racine) =>
      Directory(racine)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  test('le logo embarqué est, octet pour octet, celui que sert la vue', () {
    final vue = File('${VueBlade.racine}/public/assets/img/logo.png');
    expect(
      vue.existsSync(),
      isTrue,
      reason: 'tatacora-api/public/assets/img/logo.png introuvable',
    );
    final embarque = File(AppAssets.logo).readAsBytesSync();

    expect(AppAssets.logo, 'assets/img/logo.png');
    expect(embarque, vue.readAsBytesSync());
    // Signature PNG, puis largeur et hauteur de l'en-tête IHDR (big-endian) :
    // le paysage 735 × 403 du PO.
    expect(embarque.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final ihdr = ByteData.sublistView(embarque, 16, 24);
    expect([ihdr.getUint32(0), ihdr.getUint32(4)], [735, 403]);
  });

  test('pubspec embarque le PNG, et plus l’ancien JPEG', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declarations = const LineSplitter()
        .convert(pubspec)
        .where((l) => l.trimLeft().startsWith('- assets/img/'))
        .map((l) => l.trim())
        .toList();

    expect(declarations, contains('- assets/img/logo.png'));
    expect(declarations.where(ancienLogo.hasMatch), isEmpty);
  });

  test('aucune ligne de code ne désigne plus l’ancien logo', () {
    final fichiers = [...dart('lib'), ...dart('integration_test')];
    // Plancher mesuré le 14/10/2026 : plus de 600 fichiers relus.
    expect(fichiers.length, greaterThan(400), reason: 'balayage vide');

    final fautifs = [
      for (final f in fichiers)
        if (ancienLogo.hasMatch(code(f))) f.path,
    ];
    expect(fautifs, isEmpty, reason: 'logo.jpg encore désigné');
  });

  test('le chemin du logo n’a qu’un auteur : AppAssets', () {
    final auteurs = [
      for (final f in dart('lib'))
        if (code(f).contains('assets/img/logo')) f.path.replaceAll('\\', '/'),
    ];
    expect(auteurs, ['lib/core/theme/app_assets.dart']);
  });

  test(
    'un état A4 composé avec le logo le porte réellement, à sa taille native',
    () async {
      final logo = File(AppAssets.logo).readAsBytesSync();

      Future<String> composer(Uint8List? image) async {
        final doc = pw.Document()
          ..addPage(
            pw.Page(
              build: (_) => enTeteA4(
                entete: const EnteteEtablissement(),
                titre: 'Essai du logo',
                sousTitre: 'Octobre 2026',
                logo: image,
              ),
            ),
          );
        return latin1.decode(await doc.save());
      }

      final avec = await composer(logo);
      final sans = await composer(null);

      expect(avec, startsWith('%PDF'));
      expect(avec, contains(RegExp(r'/Subtype\s*/Image')));
      expect(avec, contains(RegExp(r'/Width\s+735\b')));
      expect(avec, contains(RegExp(r'/Height\s+403\b')));
      expect(sans, isNot(contains(RegExp(r'/Subtype\s*/Image'))));
    },
  );
}
