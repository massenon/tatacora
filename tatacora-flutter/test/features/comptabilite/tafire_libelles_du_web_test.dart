import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/modales_etats_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/onglets_etats_financiers.dart';

/// Les lignes du flux de trésorerie (produits des cessions, emprunts, dividendes
/// versés et prélèvements de l'exploitant, dettes liées à des participations) et
/// le « dont dividendes à payer » du bilan portent les MÊMES MOTS sur le web et
/// sur le poste. Le poste relit le serveur : les libellés sont lus de
/// `lang/fr/comptabilite_pwa.php` (PHP exécuté), jamais recopiés dans le test ; la
/// vue du web doit, elle, les demander par leurs clés (aucun mot en dur).
void main() {
  const api = '../tatacora-api';

  Future<Map<String, dynamic>> langue() async {
    final r = await Process.run('php', [
      '-r',
      'echo json_encode(require "$api/lang/fr/comptabilite_pwa.php");',
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return jsonDecode(r.stdout as String) as Map<String, dynamic>;
  }

  test('le poste écrit, au mot près, les libellés du web', () async {
    final fr = await langue();
    final attendus = {
      'flux_produits_cessions': TextesEtatsComptables.produitsCessions,
      'flux_variation_emprunts': TextesEtatsComptables.variationEmprunts,
      'flux_dividendes_verses': TextesEtatsComptables.dividendesVerses,
      'flux_variation_dettes_participations':
          TextesEtatsComptables.variationDettesParticipations,
      'bilan_dont_dividendes_a_payer':
          TextesEtatsFinanciers.dontDividendesAPayer,
    };
    expect(attendus, hasLength(5));
    for (final e in attendus.entries) {
      expect(fr[e.key], isNotNull, reason: 'clé absente : ${e.key}');
      expect(e.value, fr[e.key], reason: e.key);
    }
  });

  test('la vue du web demande ces libellés à lang/fr, sans les écrire '
      'en dur', () async {
    final fr = await langue();
    final vue = File(
      '$api/resources/views/pwa/comptabilite/flux-tresorerie.blade.php',
    ).readAsStringSync();
    for (final cle in [
      'flux_produits_cessions',
      'flux_variation_emprunts',
      'flux_dividendes_verses',
      'flux_variation_dettes_participations',
    ]) {
      expect(vue, contains("__('comptabilite_pwa.$cle')"), reason: cle);
      expect(
        vue.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), ''),
        isNot(contains(fr[cle] as String)),
        reason: '$cle écrit en dur dans la vue',
      );
    }
  });

  test(
    'le « dont dividendes à payer » est demandé à lang/fr par les trois vues '
    'du bilan du web, jamais écrit en dur',
    () async {
      final fr = await langue();
      final mot = fr['bilan_dont_dividendes_a_payer'] as String;
      for (final vue in [
        'bilan.blade.php',
        'etats-financiers.blade.php',
        'onglets/bilan.blade.php',
      ]) {
        final source = File(
          '$api/resources/views/pwa/comptabilite/$vue',
        ).readAsStringSync();
        expect(
          source,
          contains("__('comptabilite_pwa.bilan_dont_dividendes_a_payer')"),
          reason: vue,
        );
        expect(
          source.replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), ''),
          isNot(contains(mot)),
          reason: '$vue : mot écrit en dur',
        );
      }
    },
  );
}
