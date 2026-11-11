import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/caisse/domain/montant_caisse.dart';

/// Un montant DÛ ne cache jamais un centime (PO, 10/11/2026 : « 30 000 » affiché pour un reste de
/// 29 999,99). Même forme que `MontantFcfa::formatExact` du web.
void main() {
  test('un franc entier garde sa forme, un centime se dit', () {
    expect(formaterCentimesExact(3000000), '30 000 FCFA');
    expect(formaterCentimesExact(2999999), '29 999,99 FCFA');
    expect(formaterCentimesExact(100550), '1 005,50 FCFA');
    expect(formaterCentimesExact(-1), '-0,01 FCFA');
    // L'arrondi au franc de `formaterCentimesEnFcfa` est inchangé (parité avec `MontantFcfa::format`).
    expect(formaterCentimesEnFcfa(2999999), '30 000 FCFA');
  });
}
