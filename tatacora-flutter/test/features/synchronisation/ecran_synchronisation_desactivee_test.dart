import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import 'support/faux_transport.dart';

/// L'écran de synchronisation, synchronisation DÉSACTIVÉE : il le dit, et son
/// bouton « Synchroniser maintenant » ne s'offre pas (aucune requête ne part).
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1800, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': 'C'});
    final t = FauxTransport((r) => throw StateError('RÉSEAU : ${r.url}'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(b.db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild(
            (ref, n) => Session(
              utilisateurId: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: 'administrateur',
              droits: droits,
            ),
          ),
          transportSynchronisationProvider.overrideWithValue(t),
          urlServeurSynchronisationProvider.overrideWithValue(
            BancSync.urlServeur,
          ),
          cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranSynchronisation()),
        ),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  testWidgets('désactivée : l’écran le dit et le bouton est grisé', (
    tester,
  ) async {
    await b.ecrivain.enregistrerSynchronisationActivee(
      false,
      par: 'essai',
      le: DateTime(2026, 10, 26),
    );
    await monter(tester);

    expect(find.byKey(const Key('sync-ecran-desactivee')), findsOneWidget);
    final bouton = tester.widget<BoutonStandard>(
      find.byKey(const Key('sync-ecran-maintenant')),
    );
    expect(bouton.onPressed, isNull);
  });

  testWidgets('activée : aucune mention, le bouton est offert', (tester) async {
    await monter(tester);

    expect(find.byKey(const Key('sync-ecran-desactivee')), findsNothing);
    final bouton = tester.widget<BoutonStandard>(
      find.byKey(const Key('sync-ecran-maintenant')),
    );
    expect(bouton.onPressed, isNotNull);
  });
}
