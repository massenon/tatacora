import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// PA-182 / PA-183 — le client Flutter se conforme à la VUE BLADE de la PWA.
///
/// Décision du Product Owner du 10/09/2026 : la vue Blade de `tatacora-api`
/// porte la dernière version de chaque écran ; `prototype_v2/` est une
/// ancienne version qui ne fait plus foi. La règle est écrite dans huit
/// documents — ce test est l'endroit où elle est VÉRIFIÉE, à chaque
/// `flutter test`.
///
/// Le comparateur vit dans `tool/conformite_blade/t-blade-flutter.js`. Il est
/// écrit en JavaScript parce qu'il doit résoudre les clés de langue de la PWA
/// par PHP et déplier des gabarits Blade, ce qu'aucun paquet Dart du projet ne
/// sait faire. Ce test l'exécute et exige qu'il sorte en code 0 : aucun écran
/// porté n'a reculé depuis la dernière mesure, et la dette figée dans
/// `tool/conformite_blade/dette-blade-flutter.json` n'a ni monté, ni baissé
/// sans être resserrée.
///
/// ## Il échoue quand Node ou PHP manquent — il ne saute pas
///
/// Une garde dont la source manque passe à vide, et le vert qu'elle affiche
/// est le plus dangereux du dépôt. Sur un poste sans Node ou sans PHP, ce test
/// ROUGIT en disant quoi installer.
void main() {
  test(
    'chaque écran porté rend les libellés de sa vue Blade, ou nomme ses refus',
    () {
      final ProcessResult resultat;
      try {
        resultat = Process.runSync('node', [
          'tool/conformite_blade/t-blade-flutter.js',
        ], runInShell: true);
      } on ProcessException catch (e) {
        fail(
          'Node est introuvable : ce test exécute '
          'tool/conformite_blade/t-blade-flutter.js et ne peut pas passer à '
          'vide.\n$e',
        );
      }

      final sortie = '${resultat.stdout}${resultat.stderr}'.replaceAll(
        RegExp(r'\x1b\[[0-9;]*m'),
        '',
      );
      final ecarts = sortie
          .split('\n')
          .where(
            (l) =>
                l.contains('ECART') ||
                l.contains('illisibles') ||
                l.contains('introuvable'),
          )
          .take(25)
          .join('\n');

      expect(
        resultat.exitCode,
        0,
        reason:
            'Le comparateur Blade -> Flutter a relevé des écarts.\n'
            'Détail : node tool/conformite_blade/t-blade-flutter.js --detail\n\n'
            '$ecarts',
      );

      // La garde de la garde : un comparateur qui n'a rien mesuré ne passe
      // pas pour un comparateur satisfait.
      expect(sortie, contains('BLADE -> FLUTTER : PASS'));
      expect(RegExp(r'\d+ vue\(s\) Blade servies').hasMatch(sortie), isTrue);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
