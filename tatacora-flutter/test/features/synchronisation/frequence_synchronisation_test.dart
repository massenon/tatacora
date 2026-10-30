import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import 'support/faux_transport.dart';

/// Le planificateur lit la FRÉQUENCE de `poste.json` (29/10/2026) : le réveil
/// périodique suit le choix, y compris un choix fait pendant que l'application
/// tourne ; « Manuelle seulement » supprime ce réveil.
void main() {
  late BancSync b;
  var lotsAjoutes = 0;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  List<Override> surcharges(TransportSynchronisation t) => [
    baseLocaleProvider.overrideWithValue(b.db),
    transportSynchronisationProvider.overrideWithValue(t),
    urlServeurSynchronisationProvider.overrideWithValue(BancSync.urlServeur),
    cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
  ];

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  /// Une opération échue à chaque réveil, pour que chaque réveil se voie.
  Future<void> reveil(WidgetTester tester, FauxTransport t, Duration d) async {
    await tester.runAsync(() => b.enfilerClients(1));
    final avant = t.lots.length;
    await tester.pump(d);
    await laisserTourner(tester);
    // Le nombre de lots ajoutés par ce réveil.
    lotsAjoutes = t.lots.length - avant;
  }

  testWidgets('15 minutes : pas de réveil à 5 min, un réveil à 15 min', (
    tester,
  ) async {
    await tester.runAsync(
      () => b.ecrivain.enregistrerFrequenceSynchronisation(15),
    );
    final t = FauxTransport(reponseLot);
    final c = ProviderContainer(overrides: surcharges(t));
    c.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    final apresDemarrage = t.lots.length;

    await reveil(tester, t, const Duration(minutes: 5));
    expect(lotsAjoutes, 0, reason: '5 min : trop tôt pour 15 min');
    await reveil(tester, t, const Duration(minutes: 10));
    expect(lotsAjoutes, 1, reason: '15 min écoulées');
    expect(t.lots.length, apresDemarrage + 1);
    c.dispose();
  });

  testWidgets('manuelle seulement : plus de réveil périodique', (tester) async {
    await tester.runAsync(
      () => b.ecrivain.enregistrerFrequenceSynchronisation(0),
    );
    // Une opération échue AVANT le démarrage : il la voit.
    await tester.runAsync(() => b.enfilerClients(1));
    final t = FauxTransport(reponseLot);
    final c = ProviderContainer(overrides: surcharges(t));
    c.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    // Le démarrage reste un déclencheur (il n'est pas une fréquence).
    final apresDemarrage = t.lots.length;
    expect(apresDemarrage, 1);

    await reveil(tester, t, const Duration(hours: 3));
    expect(lotsAjoutes, 0);
    // Le geste manuel, lui, passe toujours.
    await tester.runAsync(
      () => c.read(syncManagerProvider).synchroniserMaintenant(),
    );
    expect(t.lots.length, apresDemarrage + 1);
    c.dispose();
  });

  testWidgets('un choix fait en cours d’exécution réarme le minuteur, sans '
      'nouvelle synchronisation immédiate', (tester) async {
    final t = FauxTransport(reponseLot);
    final c = ProviderContainer(overrides: surcharges(t));
    c.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    final apresDemarrage = t.lots.length;

    await tester.runAsync(
      () => b.ecrivain.enregistrerFrequenceSynchronisation(60),
    );
    c.invalidate(frequenceSynchronisationProvider);
    await laisserTourner(tester);
    // Dans l'application, la carte de Paramètres lit ce fournisseur (et la
    // trame suivante le rafraîchit) : ici, une lecture dans la zone du test.
    c.read(frequenceSynchronisationProvider);
    await laisserTourner(tester);
    expect(t.lots.length, apresDemarrage, reason: 'changer ne synchronise pas');

    await reveil(tester, t, const Duration(minutes: 30));
    expect(lotsAjoutes, 0, reason: '30 min : l’heure n’est pas écoulée');
    await reveil(tester, t, const Duration(minutes: 31));
    expect(lotsAjoutes, 1, reason: 'plus d’une heure : le réveil a eu lieu');
    c.dispose();
  });

  testWidgets('sans fichier : 5 minutes, comme avant', (tester) async {
    final t = FauxTransport(reponseLot);
    final c = ProviderContainer(overrides: surcharges(t));
    c.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    await reveil(tester, t, periodeSynchronisation);
    expect(lotsAjoutes, 1);
    c.dispose();
  });
}
