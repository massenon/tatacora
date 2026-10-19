import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/domain/motif_indisponibilite.dart';

import '../../support/vue_blade.dart';

/// Les motifs de retrait du client, confrontés au registre FERMÉ du serveur —
/// `IndisponibiliteCarte::MOTIFS`, relu dans le PHP.
///
/// ## Pourquoi relire le serveur plutôt que figer trois constantes
///
/// Une copie comparée à elle-même ne vérifie rien : le jour où un motif
/// changerait au serveur, ce test resterait vert et la modale partirait en 422
/// au comptoir. C'est la divergence exacte que la PWA a connue — `hors_saison`
/// / `retrait` contre `saison` / `retire`, pour des libellés identiques à
/// l'écran, donc invisible. Même principe que `conformite_stocks_test.dart`.
void main() {
  test('le registre du client est celui du serveur, dans son ordre', () {
    final source = VueBlade.fichier(
      'app/Domain/Carte/Models/IndisponibiliteCarte.php',
      role: 'le registre des motifs de retrait de la carte',
    );

    final motifs = RegExp(
      r"'(\w+)'\s*=>\s*\[\s*'libelle'\s*=>\s*'([^']+)'\s*,\s*'temporaire'\s*=>\s*(true|false)\s*\]",
    ).allMatches(source).map((m) => (m[1]!, m[2]!, m[3] == 'true')).toList();

    // Prouvé NON VIDE : une extraction qui ne trouverait rien — constante
    // renommée, forme changée — rendrait le test vert à vide.
    expect(
      motifs,
      isNotEmpty,
      reason: 'IndisponibiliteCarte::MOTIFS n’a pas pu être lu.',
    );

    expect([
      for (final m in MotifIndisponibilite.values)
        (m.code, m.libelle, m.temporaire),
    ], motifs);
  });
}
