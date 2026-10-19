import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/bilan_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/voyant_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/bouton_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import 'support/faux_transport.dart';

/// Lot F3 — le bouton de synchronisation de la barre supérieure et sa
/// modale (demande du PO du 16/10/2026). Le voyant ne dit que ce qui est
/// vérifié ; le badge suit la file EN DIRECT ; « Synchroniser maintenant »
/// envoie pour de vrai ; le détail n'est offert qu'à qui y a accès.
void main() {
  group('le voyant (pur)', () {
    Map<StatutOperationSync, int> file({
      int attente = 0,
      int cours = 0,
      int ok = 0,
      int rejete = 0,
      int conflit = 0,
      int bloque = 0,
    }) => {
      StatutOperationSync.enAttente: attente,
      StatutOperationSync.enCours: cours,
      StatutOperationSync.synchronise: ok,
      StatutOperationSync.rejete: rejete,
      StatutOperationSync.conflit: conflit,
      StatutOperationSync.bloque: bloque,
    };

    VoyantSynchronisation v({
      bool interdite = false,
      bool appaire = true,
      bool refus = false,
      Map<StatutOperationSync, int>? comptes,
      BilanSynchronisation? bilan,
      bool enCours = false,
    }) => voyantDe(
      interdite: interdite,
      appaire: appaire,
      refusJeton: refus,
      comptes: comptes ?? file(),
      bilan: bilan,
      enCours: enCours,
    );

    const injoignable = BilanSynchronisation(
      etat: EtatSynchronisation.serveurIndisponible,
    );

    test('vert SEULEMENT quand rien n’attend et rien n’est à traiter', () {
      expect(
        v(comptes: file(ok: 12)),
        const VoyantSynchronisation(
          teinte: TeinteVoyant.vert,
          phrase: TextesVoyant.toutEnvoye,
        ),
      );
      expect(v(comptes: file(ok: 12, attente: 1)).teinte, TeinteVoyant.orange);
      expect(v(comptes: file(ok: 12, cours: 1)).teinte, TeinteVoyant.orange);
      expect(v(comptes: file(ok: 12, bloque: 1)).teinte, TeinteVoyant.rouge);
    });

    test('orange : le badge compte en attente + en cours ; serveur '
        'injoignable dit dans la phrase', () {
      final o = v(comptes: file(attente: 3, cours: 2));
      expect((o.teinte, o.badge), (TeinteVoyant.orange, 5));
      expect(o.phrase, TextesVoyant.enAttente(5));
      expect(
        v(comptes: file(attente: 3), bilan: injoignable).phrase,
        TextesVoyant.enAttenteInjoignable(3),
      );
    });

    test('rouge : à traiter PRIME sur l’attente ; le jeton refusé aussi', () {
      final r = v(comptes: file(attente: 4, rejete: 1, conflit: 1, bloque: 2));
      expect((r.teinte, r.badge), (TeinteVoyant.rouge, 4));
      expect(r.phrase, TextesVoyant.aTraiter(4));
      final j = v(refus: true, comptes: file(attente: 2));
      expect(
        (j.teinte, j.badge, j.phrase),
        (TeinteVoyant.rouge, 2, TextesVoyant.jetonRefuse),
      );
    });

    test('gris : démonstration, non appairé, injoignable sans attente ; '
        'jamais un badge « 0 »', () {
      expect(
        v(interdite: true, comptes: file(attente: 9)).teinte,
        TeinteVoyant.gris,
      );
      expect(v(interdite: true, comptes: file(attente: 9)).badge, isNull);
      final na = v(appaire: false, comptes: file(attente: 2));
      expect(
        (na.teinte, na.badge, na.phrase),
        (TeinteVoyant.gris, 2, TextesVoyant.nonAppaire),
      );
      expect(v(appaire: false).badge, isNull);
      final i = v(bilan: injoignable);
      expect(
        (i.teinte, i.badge, i.phrase),
        (TeinteVoyant.gris, null, TextesVoyant.injoignable),
      );
    });

    test(
      'pendant un envoi : orange « en cours », sauf s’il reste à traiter',
      () {
        expect(
          v(enCours: true, comptes: file(attente: 1)).phrase,
          TextesVoyant.enCours,
        );
        expect(
          v(enCours: true, comptes: file(rejete: 1)).teinte,
          TeinteVoyant.rouge,
        );
      },
    );
  });

  group('le bouton et la modale', () {
    late BancSync b;
    setUp(() async => b = await BancSync.creer());
    tearDown(() => b.fermer());

    Future<void> laisserTourner(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
    }

    Future<FauxTransport> monter(
      WidgetTester tester, {
      Map<String, String> droits = const {'PARAM': 'C'},
      String role = 'administrateur',
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 1200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final garde = GardeAcces(droits);
      final transport = FauxTransport(
        (r) => r.methode == 'GET'
            ? FauxCatalogue(const []).repondre(r)
            : reponseLot(r),
      );
      final routeur = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) =>
                const Scaffold(body: Center(child: BoutonSynchronisation())),
          ),
          GoRoute(
            path: '/synchronisation',
            builder: (_, _) =>
                const Scaffold(body: Text('écran détail', key: Key('detail'))),
          ),
        ],
      );
      addTearDown(routeur.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(b.db),
            droitsProvider.overrideWithValue(garde),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-essai',
                login: 'essai',
                nom: 'Essai',
                role: role,
                droits: garde,
              ),
            ),
            transportSynchronisationProvider.overrideWithValue(transport),
            urlServeurSynchronisationProvider.overrideWithValue(
              BancSync.urlServeur,
            ),
            cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
          ],
          child: MaterialApp.router(
            theme: AppTheme.clair,
            routerConfig: routeur,
          ),
        ),
      );
      await laisserTourner(tester);
      return transport;
    }

    testWidgets('le badge suit la file EN DIRECT : vert, puis orange « 2 », '
        'puis rouge quand une opération est rejetée', (tester) async {
      await monter(tester);
      expect(
        find.byKey(const Key('voyant-synchronisation-vert')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('badge-synchronisation')), findsNothing);

      final ids = (await tester.runAsync(() => b.enfilerClients(2)))!;
      await laisserTourner(tester);
      expect(
        find.byKey(const Key('voyant-synchronisation-orange')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('badge-synchronisation')))
            .data,
        '2',
      );

      // Une écriture DÉCLARÉE sur la table, comme toutes celles
      // d'OperationsSyncDao : un `customStatement` nu ne prévient pas Drift,
      // et aucun écrivain de la file n'en emploie.
      await tester.runAsync(
        () => b.db.customUpdate(
          "UPDATE operations_sync_local SET statut = 'rejete' "
          'WHERE entite_id = ?',
          variables: [Variable.withString(ids.first)],
          updates: {b.db.operationsSyncLocal},
        ),
      );
      await laisserTourner(tester);
      expect(
        find.byKey(const Key('voyant-synchronisation-rouge')),
        findsOneWidget,
      );
    });

    testWidgets('la modale : compteurs, puis « Synchroniser maintenant » '
        'envoie la file pour de vrai et le voyant repasse au vert', (
      tester,
    ) async {
      final transport = await monter(tester);
      await tester.runAsync(() => b.enfilerClients(3));
      await laisserTourner(tester);

      await tester.tap(find.byKey(const Key('bouton-synchronisation')));
      await laisserTourner(tester);
      expect(find.byKey(const Key('modale-synchronisation')), findsOneWidget);
      String compteur(String cle) =>
          tester.widget<Text>(find.byKey(Key(cle))).data!;
      expect(compteur('sync-modale-en-attente'), '3');
      expect(compteur('sync-modale-envoyees'), '0');
      expect(
        tester.widget<Text>(find.byKey(const Key('sync-modale-passage'))).data,
        TextesBoutonSynchronisation.aucunPassage,
      );

      await tester.tap(find.byKey(const Key('sync-modale-maintenant')));
      await laisserTourner(tester);
      await laisserTourner(tester);

      expect(
        transport.requetes.where((r) => r.methode == 'POST'),
        isNotEmpty,
        reason: 'aucun envoi réel',
      );
      expect(compteur('sync-modale-envoyees'), '3');
      expect(compteur('sync-modale-en-attente'), '0');
      expect(
        tester.widget<Text>(find.byKey(const Key('sync-modale-passage'))).data,
        startsWith('Dernier passage : ${EtatSynchronisation.termine.libelle}'),
      );
      expect(
        find.byKey(const Key('voyant-synchronisation-vert')),
        findsOneWidget,
      );
    });

    testWidgets('« Voir le détail » mène à /synchronisation ; absent pour un '
        'compte sans accès à Paramètres, qui peut quand même synchroniser', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('bouton-synchronisation')));
      await laisserTourner(tester);
      await tester.tap(find.byKey(const Key('sync-modale-detail')));
      await laisserTourner(tester);
      expect(find.byKey(const Key('detail')), findsOneWidget);
      expect(find.byKey(const Key('modale-synchronisation')), findsNothing);
    });

    testWidgets('sans droit sur Paramètres : pas de détail, mais le bouton '
        'd’envoi est actif', (tester) async {
      await monter(tester, droits: const {'M5': 'C'}, role: 'barman');
      await tester.tap(find.byKey(const Key('bouton-synchronisation')));
      await laisserTourner(tester);
      expect(find.byKey(const Key('sync-modale-detail')), findsNothing);
      expect(
        tester
            .widget<BoutonStandard>(
              find.byKey(const Key('sync-modale-maintenant')),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('poste non appairé : gris, et l’envoi est grisé', (
      tester,
    ) async {
      final nu = await tester.runAsync(() => BancSync.creer(appaire: false));
      addTearDown(() => nu!.fermer());
      final vrai = b;
      b = nu!;
      await monter(tester);
      b = vrai;
      expect(
        find.byKey(const Key('voyant-synchronisation-gris')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('bouton-synchronisation')));
      await laisserTourner(tester);
      expect(
        tester
            .widget<BoutonStandard>(
              find.byKey(const Key('sync-modale-maintenant')),
            )
            .onPressed,
        isNull,
      );
    });
  });

  test('le bouton est posé dans la barre supérieure, à gauche de la cloche '
      '(relu du code de la coquille)', () {
    final source = File(
      'lib/core/router/coquille_application.dart',
    ).readAsStringSync();
    final bouton = source.indexOf('const BoutonSynchronisation()');
    final cloche = source.indexOf('ClocheNotifications(routeActive');
    expect(bouton, greaterThan(0));
    expect(bouton, lessThan(cloche));
  });
}
