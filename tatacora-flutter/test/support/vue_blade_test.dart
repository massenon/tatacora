import 'package:flutter_test/flutter_test.dart';

import 'vue_blade.dart';

/// La garde de l'outil qui lit la vue Blade (PA-183).
///
/// Tous les tests de conformité lisent la vue par [VueBlade]. Si la
/// résolution des libellés se cassait — un motif retouché, PHP qui répond
/// vide —, ils compareraient le Flutter à un texte creux, et chacun le ferait
/// en silence. Ces cas prouvent que l'outil rend quelque chose de RÉEL.
void main() {
  test('les libellés de la PWA sont lus, et ils sont nombreux', () {
    final chaines = VueBlade.langue().values.whereType<String>().length;
    expect(chaines, greaterThanOrEqualTo(1000));
  });

  test('une vue se lit résolue : la clé disparaît, le libellé apparaît', () {
    final titre = VueBlade.libelle('pwa.clients.titre');
    expect(titre, isNotNull, reason: 'La clé du titre des clients a disparu.');

    final brute = VueBlade.brute('crm/clients-creances');
    final resolue = VueBlade.resolue('crm/clients-creances');

    expect(brute, contains("__('pwa.clients.titre')"));
    expect(resolue, isNot(contains("__('pwa.clients.titre')")));
    expect(resolue, contains(titre));
  });

  test('un libellé accentué arrive INTACT, tel qu’écrit dans lang/fr', () {
    // La garde qui manquait : une sortie PHP décodée dans le mauvais
    // encodage corrompt la clé ET la valeur de la même façon, et le cas
    // précédent reste vert. Ici, la valeur est confrontée au fichier source
    // relu en UTF-8 — une corruption ne peut plus s’y retrouver.
    final titre = VueBlade.libelle('pwa.clients.titre')!;
    expect(
      titre,
      contains('é'),
      reason: 'Le titre des clients porte un accent.',
    );
    expect(VueBlade.fichier('lang/fr/pwa.php'), contains("'$titre'"));
  });

  test('une clé inconnue reste visible, jamais remplacée par du vide', () {
    const source = "<th>{{ __('pwa.cle_qui_n_existe_pas') }}</th>";
    expect(VueBlade.resoudre(source), source);
  });
}
