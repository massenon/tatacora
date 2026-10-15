import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';

import '../../support/vue_blade.dart';

/// Décision du Product Owner du 13/10/2026 (PA-209, D389) : « Système
/// d'Information Intégré » devient « Système de gestion Intégré », casse
/// exacte du PO, à l'écran comme sur le papier.
///
/// Le papier du poste (`EnteteEtablissement.sousTitre`) imprime la même ligne
/// que l'en-tête des états du serveur (`rapports.entete.localisation`) : le
/// cas la relit dans la langue résolue par PHP, il ne la recopie pas. Le
/// second cas balaie le code de `lib/` hors commentaires : un commentaire qui
/// raconte l'historique de la décision n'est pas un affichage.
void main() {
  final ancienneMention = RegExp(
    "syst[eèÈE]me\\s+d['’]\\s*information",
    caseSensitive: false,
  );

  test('le sous-titre de l’en-tête imprimé est la clé de localisation de la '
      'vue', () {
    final cle = VueBlade.libelle('rapports.entete.localisation');
    expect(cle, isNotNull, reason: 'clé rapports.entete.localisation absente');
    expect(cle, 'Natitingou, Bénin — Système de gestion Intégré');
    expect(const EnteteEtablissement().sousTitre, cle);
  });

  test('aucun code de lib/ n’écrit l’ancienne mention hors commentaire', () {
    final fautifs = <String>[];
    var relus = 0;
    for (final entite in Directory('lib').listSync(recursive: true)) {
      if (entite is! File || !entite.path.endsWith('.dart')) continue;
      relus++;
      final lignes = entite.readAsLinesSync();
      for (var i = 0; i < lignes.length; i++) {
        final ligne = lignes[i].trimLeft();
        if (ligne.startsWith('//')) continue;
        if (ancienneMention.hasMatch(ligne)) {
          fautifs.add('${entite.path}:${i + 1} : ${ligne.trim()}');
        }
      }
    }
    // Plancher : sans lui, un dossier renommé rendrait le balayage vide, donc
    // vert (mesuré le 13/10/2026 : 450 fichiers).
    expect(relus, greaterThan(300), reason: 'balayage de lib/ vide');
    expect(fautifs, isEmpty, reason: fautifs.join('\n'));
  });

  test('le motif reconnaît les graphies de l’ancienne mention', () {
    for (final graphie in const [
      "Système d'Information Intégré",
      'Système d’Information Intégré',
      "système d'information intégré",
      "Systeme d'information",
    ]) {
      expect(ancienneMention.hasMatch(graphie), isTrue, reason: graphie);
    }
    expect(ancienneMention.hasMatch('Système de gestion Intégré'), isFalse);
  });
}
