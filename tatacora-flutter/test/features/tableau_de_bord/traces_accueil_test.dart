import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/widgets/traces_accueil.dart';

import '../../support/vue_blade.dart';

/// Les TRACÉS et couleurs de la « Vue d'exploitation » sont ceux de la vue
/// d'accueil — relus dans la vue, jamais recopiés dans le test (piège 12).
void main() {
  late final String vue = VueBlade.fichier(
    'resources/views/pwa/livewire/accueil.blade.php',
    role: 'les tracés de la vue d accueil',
  );
  late final String partiel = VueBlade.fichier(
    'resources/views/pwa/livewire/accueil-cartes-kpi.blade.php',
    role: 'le partiel des cartes d indicateur',
  );

  const traces = {
    'titre': TracesAccueil.titre,
    'actualiser': TracesAccueil.actualiser,
    'document': TracesAccueil.document,
    'alerte': TracesAccueil.alerte,
    'reservation': TracesAccueil.reservation,
    'client': TracesAccueil.client,
    'depense': TracesAccueil.depense,
    'chiffreAffaires': TracesAccueil.chiffreAffaires,
    'occupation': TracesAccueil.occupation,
    'tresorerie': TracesAccueil.tresorerie,
    'depenses': TracesAccueil.depenses,
    'attente': TracesAccueil.attente,
    'facture': TracesAccueil.facture,
    'stock': TracesAccueil.stock,
    'employes': TracesAccueil.employes,
  };

  test('chaque tracé figure TEL QUEL dans la vue, et se lit', () {
    expect(traces, hasLength(15), reason: 'balayage non vide');
    for (final e in traces.entries) {
      expect(vue.contains(e.value), isTrue, reason: e.key);
      // Lisible par le peintre de la coquille : un tracé mal lu lève.
      expect(TraceSvg.lire(e.value).elements, isNotEmpty, reason: e.key);
    }
    // Le repli d'une clé inconnue est celui du partiel des cartes.
    expect(partiel.contains(TracesAccueil.inconnu), isTrue);
  });

  test('les huit icônes d’indicateur : une par clé du service, chaque tracé '
      'à côté de SA clé dans `\$iconesKpi`, avec sa couleur et son fond', () {
    expect(
      iconesIndicateurs.keys.toSet(),
      EcranTableauDeBord.libelles.keys.toSet(),
    );
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final variables = <Color, String>{
      AppColors.succes: 'var(--succes)',
      AppColors.navy: 'var(--navy)',
      AppColors.gold: 'var(--gold)',
      AppColors.erreur: 'var(--erreur)',
    };
    for (final e in iconesIndicateurs.entries) {
      final ligne = vue
          .split('\n')
          .firstWhere(
            (l) => l.contains("'${e.key}' => ["),
            orElse: () => fail('${e.key} absent de \$iconesKpi'),
          );
      expect(ligne.contains(e.value.trace), isTrue, reason: e.key);
      final couleur = variables[e.value.couleur] ?? hex(e.value.couleur);
      expect(
        ligne.toUpperCase().contains("'${couleur.toUpperCase()}'"),
        isTrue,
        reason: '${e.key} : couleur $couleur',
      );
      expect(
        ligne.toUpperCase().contains("'${hex(e.value.fond).toUpperCase()}'"),
        isTrue,
        reason: '${e.key} : fond ${hex(e.value.fond)}',
      );
    }
  });
}
