import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/textes_registre_facture.dart';

/// Les phrases d'aide du registre vide sont celles du web, au mot près (`lang/fr/pwa.php` relu du serveur).
void main() {
  test('chaque phrase d\'aide du registre est celle du web', () {
    final r = Process.runSync('php', [
      '-r',
      'echo json_encode(require "../tatacora-api/lang/fr/pwa.php", JSON_UNESCAPED_UNICODE);',
    ]);
    expect(r.exitCode, 0);
    final web =
        ((jsonDecode(r.stdout as String) as Map<String, dynamic>)['facturation']
              as Map)
          ..length;
    expect(web['registre_vide_aide'], isNotNull);
    expect(TextesRegistreFacture.registreVideAide, web['registre_vide_aide']);
    expect(TextesRegistreFacture.registreVideLien, web['registre_vide_lien']);
    // La légende du numéro INTERNE (colonne « N° », PO 09/11/2026) : mêmes mots au web et au poste.
    expect(TextesRegistreFacture.numeroInterne, web['numero_interne']);
    expect(web['numero_interne'], 'n° interne');
    expect(
      TextesRegistreFacture.registreHorsExercice,
      web['registre_hors_exercice'],
    );
  });

  test('la phrase hors exercice se rend avec le nombre et l\'année', () {
    expect(
      TextesRegistreFacture.horsExercice(nombre: 3, annee: 2026),
      '3 facture(s) émise(s) en dehors de l\'exercice consulté (2026) : '
      'choisissez un autre exercice dans la barre supérieure.',
    );
  });
}
