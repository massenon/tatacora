import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/caisse/presentation/providers_caisse.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import 'support/faux_transport.dart';

/// Les DÉCLENCHEURS de la synchronisation (lot F2a) — chacun par son VRAI
/// appelant (piège 1 : un commentaire qui décrit un déclencheur n'est pas un
/// déclencheur).
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  List<Override> surcharges(TransportSynchronisation t) => [
    baseLocaleProvider.overrideWithValue(b.db),
    transportSynchronisationProvider.overrideWithValue(t),
    urlServeurSynchronisationProvider.overrideWithValue(BancSync.urlServeur),
    cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
  ];

  /// Laisse tourner les entrées-sorties RÉELLES (fichier `poste.json`) sous
  /// l'horloge simulée du test.
  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  testWidgets('démarrage puis toutes les 5 minutes (main.dart) — aucune '
      'requête quand rien n’est échu ; arrêté avec son conteneur', (
    tester,
  ) async {
    await tester.runAsync(() => b.enfilerClients(2));
    final t = FauxTransport(reponseLot);
    final conteneur = ProviderContainer(overrides: surcharges(t));

    conteneur.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    expect(t.lots, hasLength(1), reason: 'synchronisation au démarrage');
    expect(
      conteneur.read(dernierBilanSynchronisationProvider)?.etat,
      EtatSynchronisation.termine,
    );

    // Cinq minutes, file vide : le réveil a lieu, AUCUNE requête.
    await tester.pump(periodeSynchronisation);
    await laisserTourner(tester);
    expect(t.lots, hasLength(1), reason: 'zéro réseau au repos');

    // Une saisie, puis cinq minutes : elle part.
    await tester.runAsync(() => b.enfilerClients(1));
    await tester.pump(periodeSynchronisation);
    await laisserTourner(tester);
    expect(t.lots, hasLength(2), reason: 'réveil périodique');

    conteneur.dispose();
    await tester.runAsync(() => b.enfilerClients(1));
    await tester.pump(const Duration(hours: 1));
    await laisserTourner(tester);
    expect(t.lots, hasLength(2), reason: 'minuteur arrêté');
  });

  test('main.dart démarre le réveil APRÈS la première image ; '
      'main_demo.dart, jamais', () {
    final prod = File('lib/main.dart').readAsStringSync();
    final demo = File('lib/main_demo.dart').readAsStringSync();
    final rappel = prod.indexOf('addPostFrameCallback');
    final lecture = prod.indexOf(
      'ref.read(synchronisationAutomatiqueProvider)',
    );
    expect(rappel, isNot(-1));
    expect(lecture, greaterThan(rappel));
    expect(demo, isNot(contains('synchronisation')));
    expect(demo, isNot(contains('SyncManager')));
  });

  testWidgets('démonstration : le réveil ne fait RIEN partir', (tester) async {
    await tester.runAsync(() => b.enfilerClients(2));
    final t = FauxTransport(reponseLot);
    final conteneur = ProviderContainer(
      overrides: [
        ...surcharges(t),
        synchronisationInterditeProvider.overrideWithValue(true),
      ],
    );
    conteneur.read(synchronisationAutomatiqueProvider);
    await laisserTourner(tester);
    await tester.pump(periodeSynchronisation);
    await laisserTourner(tester);
    expect(t.requetes, isEmpty);
    expect(
      conteneur.read(dernierBilanSynchronisationProvider)?.etat,
      EtatSynchronisation.demonstration,
    );
    conteneur.dispose();
  });

  group('la CLÔTURE de caisse déclenche une synchronisation, sans '
      'l’attendre ni en dépendre', () {
    /// Ouvre puis clôture la caisse du comptoir par les VRAIS gestes de
    /// l'écran (`ouvrirLaCaisse`, `cloturerLaCaisse`).
    Future<String> ouvrirPuisCloturer(
      WidgetTester tester,
      List<Override> overrides,
    ) async {
      late WidgetRef leRef;
      final droits = GardeAcces({'M5': 'C'});
      await tester.runAsync(
        () => b.db
            .into(b.db.utilisateursLocal)
            .insert(
              UtilisateursLocalCompanion.insert(
                id: 'u-caisse',
                login: 'caisse',
                nom: 'Caisse',
                role: 'caissier',
                droitsJson: '{}',
                sel: 's',
                empreinte: 'e',
                iterations: 1,
                dateCreation: DateTime(2026, 10, 9),
                dateMotDePasse: DateTime(2026, 10, 9),
              ),
            ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides,
            droitsProvider.overrideWithValue(droits),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-caisse',
                login: 'caisse',
                nom: 'Caisse',
                role: 'caissier',
                droits: droits,
              ),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              leRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      return (await tester.runAsync(() async {
        await ouvrirLaCaisse(leRef, '10000');
        // Une clôture qui ATTENDRAIT la synchronisation ne rendrait jamais la
        // main face à un serveur muet : elle échoue ici, vite.
        return cloturerLaCaisse(
          leRef,
          '10000',
        ).timeout(const Duration(seconds: 10));
      }))!;
    }

    testWidgets('serveur qui ne répond JAMAIS : la clôture rend la main, et '
        'le lot de la clôture est bien parti', (tester) async {
      final jamais = Completer<IssueHttp>();
      final t = FauxTransport((_) => jamais.future);
      final message = await ouvrirPuisCloturer(tester, surcharges(t));
      expect(message, isNotEmpty);
      await laisserTourner(tester);

      expect(t.lots, hasLength(1), reason: 'la clôture a déclenché un envoi');
      final ops = t.lots.single.operations;
      expect(ops.map((o) => '${o['type']} ${o['table']}'), [
        'creation sessions_caisse',
        'modification sessions_caisse',
      ]);
      // La clôture est ÉCRITE, quoi que fasse le réseau.
      final cloture = await tester.runAsync(
        () => b.dao.operations(table: TableSynchronisee.sessionsCaisse),
      );
      expect(cloture, hasLength(2));
    });

    testWidgets('transport qui LÈVE : la clôture réussit quand même', (
      tester,
    ) async {
      final t = FauxTransport((_) => throw const SocketException('panne'));
      final message = await ouvrirPuisCloturer(tester, surcharges(t));
      expect(message, isNotEmpty);
      await laisserTourner(tester);
      expect(t.lots, hasLength(1));
    });

    testWidgets('déclencheur qui lève lui-même : la clôture réussit quand '
        'même', (tester) async {
      final t = FauxTransport(reponseLot);
      final message = await ouvrirPuisCloturer(tester, [
        ...surcharges(t),
        declencheurSynchronisationProvider.overrideWithValue(
          () => throw StateError('déclencheur cassé'),
        ),
      ]);
      expect(message, isNotEmpty);
      expect(t.requetes, isEmpty);
    });

    testWidgets('serveur qui accepte : la clôture est synchronisée en tâche '
        'de fond', (tester) async {
      final t = FauxTransport(reponseLot);
      await ouvrirPuisCloturer(tester, surcharges(t));
      await laisserTourner(tester);
      final comptes = await tester.runAsync(() => b.comptes());
      expect(comptes![StatutOperationSync.synchronise], 2);
    });
  });
}
