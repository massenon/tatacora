import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/onglet_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/suivi_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import 'support/faux_transport.dart';

/// L'écran de SYNCHRONISATION (lot F2b) : compteurs, liste « À traiter »,
/// « Renvoyer » (nouvel uuid, historique gardé), « Débloquer », gestes
/// réservés aux Administrateurs, signalements du serveur, textes honnêtes.
void main() {
  late BancSync b;

  setUp(() async => b = await BancSync.creer());
  tearDown(() => b.fermer());

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> monter(
    WidgetTester tester, {
    String role = 'administrateur',
    TransportSynchronisation? transport,
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': 'C'});
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
              role: role,
              droits: droits,
            ),
          ),
          transportSynchronisationProvider.overrideWithValue(
            transport ?? FauxTransport(reponseLot),
          ),
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
    await laisserTourner(tester);
  }

  Future<void> statut(String entiteId, String s, {int rang = 0}) async {
    final o = await b.operationDe(entiteId, rang: rang);
    await b.db.customStatement(
      'UPDATE operations_sync_local SET statut = ? WHERE seq = ?',
      [s, o.seq],
    );
  }

  /// Une file variée : 2 en attente, 1 synchronisée avec signalements, 1
  /// rejetée (avec motif), 1 conflit, 1 bloquée derrière la rejetée.
  Future<({String rejetee, String bloquee, String conflit, String acceptee})>
  semerFile() async {
    final ids = await b.enfilerClients(5);
    await b.modifierClient(ids[2], 'Nouveau nom');
    await statut(ids[0], 'synchronise');
    await b.db.customStatement(
      'UPDATE operations_sync_local SET resultat_json = ? WHERE entite_id = ?',
      [
        '{"statut":"cloture_sans_session_serveur",'
            '"anomalies":["ecart_prix","plat_sans_composition"]}',
        ids[0],
      ],
    );
    await statut(ids[2], 'rejete');
    await b.db.customStatement(
      'UPDATE operations_sync_local SET derniere_erreur = ? WHERE entite_id = ? '
      "AND type = 'creation'",
      ['Refusée par le serveur (422) : Le téléphone est déjà pris.', ids[2]],
    );
    await statut(ids[2], 'bloque', rang: 1);
    await statut(ids[3], 'conflit');
    return (
      rejetee: (await b.operationDe(ids[2])).uuidOperation,
      bloquee: (await b.operationDe(ids[2], rang: 1)).uuidOperation,
      conflit: (await b.operationDe(ids[3])).uuidOperation,
      acceptee: (await b.operationDe(ids[0])).uuidOperation,
    );
  }

  String texteDe(WidgetTester tester, Key cle) =>
      tester.widget<Text>(find.byKey(cle)).data!;

  testWidgets('compteurs par statut, liste « À traiter » (table en français, '
      'document, motif), conflit sans action, signalements en clair', (
    tester,
  ) async {
    final f = await tester.runAsync(semerFile);
    await monter(tester);

    expect(texteDe(tester, const Key('sync-compteur-en_attente')), '2');
    expect(texteDe(tester, const Key('sync-compteur-synchronise')), '1');
    expect(texteDe(tester, const Key('sync-compteur-rejete')), '1');
    expect(texteDe(tester, const Key('sync-compteur-conflit')), '1');
    expect(texteDe(tester, const Key('sync-compteur-bloque')), '1');
    expect(texteDe(tester, const Key('sync-compteur-en_cours')), '0');

    expect(texteDe(tester, Key('sync-table-${f!.rejetee}')), 'Clients');
    expect(texteDe(tester, Key('sync-document-${f.rejetee}')), 'C2');
    expect(
      texteDe(tester, Key('sync-motif-${f.rejetee}')),
      contains('déjà pris'),
    );
    expect(texteDe(tester, Key('sync-statut-${f.rejetee}')), 'Rejetée');
    expect(
      texteDe(tester, Key('sync-motif-${f.conflit}')),
      texteConflitArbitrage,
    );
    expect(find.byKey(Key('sync-renvoyer-${f.conflit}')), findsNothing);
    expect(find.byKey(Key('sync-renvoyer-${f.rejetee}')), findsOneWidget);
    // Bloquée derrière un rejet non résolu : pas encore de « Débloquer ».
    expect(find.byKey(Key('sync-debloquer-${f.bloquee}')), findsNothing);
    expect(
      texteDe(tester, Key('sync-motif-${f.bloquee}')),
      contains('Bloquée'),
    );
    // L'acceptée n'est pas « à traiter ».
    expect(find.byKey(Key('sync-statut-${f.acceptee}')), findsNothing);

    final signalement = texteDe(tester, Key('sync-anomalie-${f.acceptee}'));
    expect(signalement, contains(libellesAnomalies['ecart_prix']));
    expect(signalement, contains(libellesAnomalies['plat_sans_composition']));
    expect(
      signalement,
      contains(libellesAnomalies['cloture_session_inconnue']),
    );
    expect(signalement, isNot(contains('ecart_prix')), reason: 'en français');
  });

  testWidgets(
    '« Renvoyer » (Administrateur) : une NOUVELLE opération sous un '
    'nouvel uuid, l’ancienne gardée rejetée ; la ligne quitte « À traiter »',
    (tester) async {
      final f = await tester.runAsync(semerFile);
      await monter(tester);
      await tester.ensureVisible(
        find.byKey(Key('sync-renvoyer-${f!.rejetee}')),
      );
      await tester.tap(find.byKey(Key('sync-renvoyer-${f.rejetee}')));
      await laisserTourner(tester);

      expect(find.text(TextesEcranSynchronisation.renvoyee), findsOneWidget);
      final ops = (await tester.runAsync(
        () => b.dao.operations(table: TableSynchronisee.clients),
      ))!;
      final ancienne = ops.firstWhere((o) => o.uuidOperation == f.rejetee);
      expect(ancienne.statut, StatutOperationSync.rejete, reason: 'historique');
      final remplacees = (await tester.runAsync(b.dao.remplacees))!;
      final nouvel = remplacees[f.rejetee]!;
      expect(nouvel, isNot(f.rejetee));
      expect(
        ops.firstWhere((o) => o.uuidOperation == nouvel).payload,
        ancienne.payload,
      );
      expect(find.byKey(Key('sync-renvoyer-${f.rejetee}')), findsNothing);
      expect(find.byKey(const Key('sync-compteur-remplacees')), findsOneWidget);
    },
  );

  testWidgets('« Débloquer » apparaît quand le blocage est levé, et remet '
      'l’opération en attente', (tester) async {
    final f = await tester.runAsync(semerFile);
    await tester.runAsync(() async {
      final nouvel = await b.dao.renvoyer(f!.rejetee);
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise' "
        'WHERE uuid_operation = ?',
        [nouvel],
      );
    });
    await monter(tester);
    final bouton = find.byKey(Key('sync-debloquer-${f!.bloquee}'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await laisserTourner(tester);

    expect(find.text(TextesEcranSynchronisation.debloquee), findsOneWidget);
    final o = (await tester.runAsync(
      () => b.dao.operations(table: TableSynchronisee.clients),
    ))!.firstWhere((o) => o.uuidOperation == f.bloquee);
    expect(o.statut, StatutOperationSync.enAttente);
    expect(find.byKey(Key('sync-statut-${f.bloquee}')), findsNothing);
  });

  testWidgets('NON administrateur : la liste se lit, aucun geste n’est offert '
      '— et l’écran le dit', (tester) async {
    final f = await tester.runAsync(() async {
      final r = await semerFile();
      final nouvel = await b.dao.renvoyer(r.rejetee);
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete' "
        'WHERE uuid_operation = ?',
        [nouvel],
      );
      return (r, nouvel);
    });
    await monter(tester, role: 'caissier');
    expect(find.byKey(Key('sync-statut-${f!.$2}')), findsOneWidget);
    expect(find.byKey(Key('sync-renvoyer-${f.$2}')), findsNothing);
    expect(find.text(TextesEcranSynchronisation.renvoyer), findsNothing);
    expect(find.text(TextesEcranSynchronisation.debloquer), findsNothing);
    expect(find.byKey(const Key('sync-ecran-reserve')), findsOneWidget);
  });

  testWidgets('« Synchroniser maintenant » : grisé sans appairage ; appairé, '
      'il se grise PENDANT l’envoi (progression), puis le bilan s’affiche', (
    tester,
  ) async {
    final nu = await tester.runAsync(() => BancSync.creer(appaire: false));
    addTearDown(() => nu!.fermer());
    final vraiB = b;
    b = nu!;
    await monter(tester);
    expect(
      tester
          .widget<BoutonStandard>(
            find.byKey(const Key('sync-ecran-maintenant')),
          )
          .onPressed,
      isNull,
    );
    expect(
      texteDe(tester, const Key('sync-ecran-etat')),
      TextesEcranSynchronisation.nonAppaire,
    );
    b = vraiB;

    await tester.runAsync(() => b.enfilerClients(1));
    final reponse = Completer<IssueHttp>();
    final t = FauxTransport(
      (r) => r.methode == 'GET'
          ? const ReponseHttp(statut: 503, corps: null)
          : reponse.future,
    );
    await tester.pumpWidget(const SizedBox());
    await monter(tester, transport: t);
    expect(
      texteDe(tester, const Key('sync-ecran-bilan')),
      TextesEcranSynchronisation.aucunBilan,
    );
    await tester.tap(find.byKey(const Key('sync-ecran-maintenant')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('sync-ecran-progression')), findsOneWidget);
    expect(
      tester
          .widget<BoutonStandard>(
            find.byKey(const Key('sync-ecran-maintenant')),
          )
          .onPressed,
      isNull,
      reason: 'pas deux envois à la fois',
    );

    reponse.complete(reponseLot(t.lots.single));
    await laisserTourner(tester);
    expect(find.byKey(const Key('sync-ecran-progression')), findsNothing);
    final bilan = texteDe(tester, const Key('sync-ecran-bilan'));
    expect(bilan, contains('acceptées 1'));
    expect(texteDe(tester, const Key('sync-compteur-synchronise')), '1');
    // Le catalogue reçu est rangé dans la partie « Réception » (26/10/2026).
    await tester.tap(find.byKey(const Key('sync-onglet-reception')));
    await laisserTourner(tester);
    expect(
      texteDe(tester, const Key('sync-ecran-descente')),
      contains('serveur injoignable ou indisponible'),
    );
  });

  testWidgets('textes HONNÊTES : une file en attente n’est jamais dite '
      '« synchronisée » ; seul le compteur des opérations CONFIRMÉES porte '
      'le mot', (tester) async {
    await tester.runAsync(() => b.enfilerClients(3));
    await monter(tester);
    final textes = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ];
    final avecLeMot = [
      for (final t in textes)
        if (RegExp(
          '(?<![a-z])synchronis(é|ée|és|ées|e|es)(?![a-zé])',
          caseSensitive: false,
        ).hasMatch(t))
          t,
    ];
    expect(avecLeMot, [
      libelleStatutFile(StatutOperationSync.synchronise),
    ], reason: '$avecLeMot');
    expect(
      libelleStatutFile(StatutOperationSync.synchronise),
      contains('confirmées par le serveur'),
    );
    expect(textes.join('\n'), isNot(contains('Tout est synchronisé')));
    expect(texteDe(tester, const Key('sync-compteur-en_attente')), '3');
  });

  group('ancrages extérieurs', () {
    test('la route /synchronisation sert l’écran de synchronisation, gardée '
        'par le module Paramètres', () {
      final routeur = File(
        'lib/core/router/app_router.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r"path: '/synchronisation',\s*builder: \(context, state\) => "
          r'const EcranSynchronisation\(\)',
        ).hasMatch(routeur),
        isTrue,
      );
      expect(routeur, isNot(contains('seulementEnSuspens')));
      expect(
        modulesDesRoutesHorsMenu['/synchronisation'],
        ModuleTatacora.parametres,
      );
    });

    test('chaque anomalie du SERVEUR (AnomalieSynchronisation) a son libellé '
        'français, et aucune n’est inventée', () {
      final source = File(
        '../tatacora-api/app/Shared/Sync/Models/AnomalieSynchronisation.php',
      ).readAsStringSync();
      final codes = {
        for (final m in RegExp(
          r"public const [A-Z_]+ = '([a-z_]+)';",
        ).allMatches(source))
          m.group(1)!,
      };
      expect(codes, hasLength(greaterThanOrEqualTo(8)), reason: 'plancher');
      expect(libellesAnomalies.keys.toSet(), codes);
    });
  });

  testWidgets('le lien de Paramètres → Synchronisation OUVRE l’écran', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1800, 3000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': 'C'});
    final routeur = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => const Scaffold(
            body: SingleChildScrollView(child: OngletSynchronisation()),
          ),
        ),
        GoRoute(
          path: '/synchronisation',
          builder: (c, s) => const Scaffold(body: EcranSynchronisation()),
        ),
      ],
    );
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
          transportSynchronisationProvider.overrideWithValue(
            FauxTransport(reponseLot),
          ),
          urlServeurSynchronisationProvider.overrideWithValue(
            BancSync.urlServeur,
          ),
          cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
          nomPosteParDefautProvider.overrideWithValue('PC'),
        ],
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await laisserTourner(tester);
    await tester.ensureVisible(find.byKey(const Key('sync-ouvrir-ecran')));
    await tester.tap(find.byKey(const Key('sync-ouvrir-ecran')));
    await laisserTourner(tester);
    expect(find.byType(EcranSynchronisation), findsOneWidget);
    expect(find.byKey(const Key('sync-compteur-en_attente')), findsOneWidget);
  });
}
