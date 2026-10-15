import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/shared_widgets/pied_pagination.dart';

/// La tranche d'une page, en fonction pure : les bornes que l'écran ne montre
/// qu'une à une.
void main() {
  TranchePage t(int total, int page, [int parPage = 10]) =>
      TranchePage.de(total: total, page: page, parPage: parPage);

  test('liste vide : une page, décompte 0-0, rien à découper', () {
    final v = t(0, 1);
    expect((v.page, v.pages, v.debut, v.fin, v.total), (1, 1, 0, 0, 0));
    expect(v.decouper(<int>[]), isEmpty);
  });

  test(
    'pile dix : une seule page ; onze : deux pages, la seconde d’un seul',
    () {
      expect(t(10, 1).pages, 1);
      final onze = t(11, 2);
      expect((onze.pages, onze.debut, onze.fin), (2, 11, 11));
      expect(onze.decouper(List.generate(11, (i) => i)), [10]);
    },
  );

  test('une page hors bornes est RAMENÉE dans [1, pages]', () {
    expect(t(23, 9).page, 3);
    expect(t(23, 0).page, 1);
    expect(t(23, -4).page, 1);
    expect(t(0, 5).page, 1);
  });

  test('les tranches se suivent sans trou ni doublon', () {
    final liste = List.generate(23, (i) => i);
    final vus = [
      for (var p = 1; p <= t(23, 1).pages; p++) ...t(23, p).decouper(liste),
    ];
    expect(vus, liste);
    expect(t(23, 3).decouper(liste), [20, 21, 22]);
    expect((t(23, 2).debut, t(23, 2).fin), (11, 20));
  });

  test('un autre pas de page', () {
    final v = t(7, 2, 3);
    expect((v.pages, v.debut, v.fin), (3, 4, 6));
  });
}
