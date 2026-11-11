import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/textes_proforma.dart';

/// Les libellés du poste sont ceux du web, au mot près (`lang/fr/proforma.php` relu du serveur).
void main() {
  test('chaque libellé de l\'écran Proformas est celui du web', () {
    final r = Process.runSync('php', [
      '-r',
      'echo json_encode(require "../tatacora-api/lang/fr/proforma.php", JSON_UNESCAPED_UNICODE);',
    ]);
    expect(r.exitCode, 0);
    final web = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final ui = (web['ui'] as Map).cast<String, String>();
    final statut = (web['statut'] as Map).cast<String, String>();
    expect(ui.length, greaterThan(40));
    expect(TextesProforma.ui, ui);
    expect(TextesProforma.statut, statut);
  });
}
