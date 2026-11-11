import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/navigation/traces_titres.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/traces_accueil.dart';

import '../../support/vue_blade.dart';

/// Directive du PO du 26/10/2026 : l'historique des ventes, les dépenses et le
/// tableau de bord ont une icône devant leur titre, dans la vue ET au poste —
/// et c'est le MÊME tracé, relu dans la vue (jamais recopié dans le test).
void main() {
  final motif = RegExp(
    r'<div class="flex items-center gap-2\.5">\s*<svg width="24" height="24" '
    r'viewBox="0 0 24 24" fill="none" stroke="var\(--navy\)" '
    r'stroke-width="2">(.+?)</svg>\s*<h1\b',
    dotAll: true,
  );

  const cas = {
    'pwa/pos/historique-ventes.blade.php': TraceIconesTitre.historiqueVentes,
    'pwa/depenses/depenses.blade.php': TraceIconesTitre.depenses,
    'pwa/livewire/accueil.blade.php': TracesAccueil.titre,
  };

  test('le tracé du poste est celui de la vue, devant le <h1>', () {
    expect(cas, hasLength(3), reason: 'balayage non vide');
    for (final e in cas.entries) {
      final vue = VueBlade.fichier(
        'resources/views/${e.key}',
        role: 'icône de titre',
      );
      final m = motif.firstMatch(vue);
      expect(m, isNotNull, reason: '${e.key} : pas d’icône devant le <h1>');
      expect(m!.group(1)!.trim(), e.value, reason: e.key);
      expect(TraceSvg.lire(e.value).elements, isNotEmpty, reason: e.key);
    }
  });

  test('preuve par mutation : un titre sans icône est dénoncé', () {
    final vue = VueBlade.fichier(
      'resources/views/pwa/depenses/depenses.blade.php',
      role: 'icône de titre',
    );
    final mute = vue.replaceFirst(
      RegExp(r'<svg width="24" height="24".+?</svg>', dotAll: true),
      '',
    );
    expect(mute, isNot(vue));
    expect(motif.hasMatch(mute), isFalse);
  });
}
