import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';

import '../../outils/echantillons_presentation.dart';

/// Les échantillons du poste (`presentation/`) : régénérés EN MÉMOIRE puis dans un dossier
/// temporaire (jamais dans `presentation/`) — PDF ouverts, non vides, filigranés, QR sur les
/// normalisés SEULEMENT.
void main() {
  late List<EchantillonPoste> echantillons;

  setUpAll(() async {
    echantillons = await genererEchantillonsPoste(
      logo: File(AppAssets.logo).readAsBytesSync(),
    );
  });

  EchantillonPoste de(String nom) =>
      echantillons.firstWhere((e) => e.nom == nom);

  test('quatre échantillons, PDF valides et non vides', () {
    expect(echantillons.map((e) => e.nom), [
      '03_ticket_thermique_poste_simple.pdf',
      '04_facture_A4_poste_simple.pdf',
      '03_ticket_thermique_poste_normalisee.pdf',
      '04_facture_A4_poste_normalisee.pdf',
    ]);
    for (final e in echantillons) {
      expect(String.fromCharCodes(e.pdf.take(4)), '%PDF', reason: e.nom);
      expect(e.pdf.length, greaterThan(2000), reason: e.nom);
      expect(
        e.textes.any(
          (t) => t.contains('ECHANTILLON') || t.contains('ÉCHANTILLON'),
        ),
        isTrue,
        reason: '${e.nom} porte la mention d\'échantillon',
      );
      expect(e.textes.join('\n'), contains('SANS VALEUR FISCALE'));
    }
  });

  test('le QR n\'existe que sur les normalisés, avec un contenu factice', () {
    for (final e in echantillons) {
      final normalisee = e.nom.contains('normalisee');
      expect(e.qrCode != null, normalisee, reason: e.nom);
      if (normalisee) {
        expect(e.qrCode, qrFactice);
        expect(e.qrCode, startsWith('F;ECHANTILLON;'));
        expect(e.textes.join('\n'), contains(nimTcFactice));
      } else {
        final texte = e.textes.join('\n');
        expect(texte, isNot(contains(nimTcFactice)));
        expect(texte, isNot(contains('MECeF')));
        expect(texte, isNot(contains('Facture en attente')));
      }
    }
  });

  test('le contenu : client fictif, lignes du Gîte, total 33 500 FCFA', () {
    for (final e in echantillons) {
      final texte = e.textes.join('\n');
      expect(texte, contains('Client Exemple'));
      expect(texte, contains('33 500 FCFA'));
    }
    final a4 = de('04_facture_A4_poste_normalisee.pdf').textes.join('\n');
    expect(a4, contains('0000000000000'));
    expect(a4, contains('Taxe de séjour'));
  });

  test(
    'le texte réellement imprimé est dans le PDF (pdftotext, si présent)',
    () async {
      final which = await Process.run('which', ['pdftotext']);
      if (which.exitCode != 0) return;
      final dossier = Directory.systemTemp.createTempSync('echantillons_');
      addTearDown(() => dossier.deleteSync(recursive: true));
      for (final e in echantillons) {
        final f = File('${dossier.path}/${e.nom}')..writeAsBytesSync(e.pdf);
        final r = await Process.run('pdftotext', ['-layout', f.path, '-']);
        final sortie = '${r.stdout}';
        expect(sortie, contains('SANS VALEUR FISCALE'), reason: e.nom);
        expect(sortie, contains('Client Exemple'), reason: e.nom);
        expect(sortie.contains(nimTcFactice), e.nom.contains('normalisee'));
      }
    },
  );
}
