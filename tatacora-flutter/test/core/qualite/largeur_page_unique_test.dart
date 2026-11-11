import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/mesures_transverses.dart';

import '../../support/vue_blade.dart';

/// Directive du PO du 26/10/2026 : le premier `<div>` après `<main>` de TOUTE
/// vue de la PWA porte `max-w-[1440px] mx-auto p-5 lg:p-8`, et le poste n'a
/// qu'UN jeton de largeur de page : [AppLayout.maxContentWidth].
void main() {
  const conteneur = 'max-w-[1440px] mx-auto p-5 lg:p-8';

  /// Vues à `<main>` plein cadre, sans conteneur de page (la caisse et le
  /// studio d'états) — miroir de `LargeurDePageUniformePwaTest.php`.
  const sansConteneur = {
    'pwa/pos/comptant.blade.php',
    'pwa/pos/heberges.blade.php',
    'pwa/etats/studio.blade.php',
  };

  test(
    'le premier div après <main> de chaque vue porte le conteneur uniforme',
    () {
      final racine = VueBlade.racine;
      final vues = Directory('$racine/resources/views/pwa')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.blade.php'));
      var lues = 0;
      final ecarts = <String>[];
      for (final f in vues) {
        final source = f.readAsStringSync();
        final main = RegExp(
          r'^[ \t]*<main\b[^>]*>',
          multiLine: true,
        ).firstMatch(source);
        if (main == null) continue;
        final relatif = f.path.substring('$racine/resources/views/'.length);
        if (sansConteneur.contains(relatif)) continue;
        lues++;
        final div = RegExp(
          r'<div\b[^>]*>',
        ).firstMatch(source.substring(main.end));
        final classe = RegExp(
          r'class="([^"]*)"',
        ).firstMatch(div?.group(0) ?? '');
        final c = classe?.group(1) ?? '';
        if (c != conteneur && !c.startsWith('$conteneur ')) {
          ecarts.add('$relatif : « $c »');
        }
      }
      expect(lues, greaterThanOrEqualTo(30), reason: 'balayage vide');
      expect(ecarts, isEmpty);
    },
  );

  test('preuve par mutation : une autre largeur serait dénoncée', () {
    bool conforme(String c) => c == conteneur || c.startsWith('$conteneur ');
    expect(conforme(conteneur), isTrue);
    expect(conforme('$conteneur zone-impression'), isTrue);
    expect(conforme(conteneur.replaceFirst('1440', '1500')), isFalse);
    expect(conforme('max-w-[1440px] mx-auto p-4 sm:p-5 lg:p-8'), isFalse);
  });

  test('un seul jeton de largeur de page au poste : 1440', () {
    expect(AppLayout.maxContentWidth, 1440);
    final jetons = <String, double>{
      'pageHistoriqueVentes': AppLayout.pageHistoriqueVentes,
      'pageCarteRestaurant': AppLayout.pageCarteRestaurant,
      'pageCarteBar': AppLayout.pageCarteBar,
      'pageVehicules': AppLayout.pageVehicules,
      'pageCongesPlannings': AppLayout.pageCongesPlannings,
      'pageNotifications': AppLayout.pageNotifications,
      'pageTourisme': AppLayout.pageTourisme,
      'pageDepenses': AppLayout.pageDepenses,
      'pageHebergement': AppLayout.pageHebergement,
      'pagePaie': AppLayout.pagePaie,
      'MesuresAccueil.page': MesuresAccueil.page,
      'pageEtroite': MesuresTransverses.pageEtroite,
      'pageProfil': MesuresTransverses.pageProfil,
      'pageLarge': MesuresTransverses.pageLarge,
      'pageComptabilite': MesuresTransverses.pageComptabilite,
    };
    for (final e in jetons.entries) {
      expect(e.value, AppLayout.maxContentWidth, reason: e.key);
    }
  });
}
