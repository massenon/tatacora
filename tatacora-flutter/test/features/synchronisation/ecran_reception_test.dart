import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/data/coherence_persistee.dart';
import 'package:tatacora_flutter/features/synchronisation/data/controle_coherence.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/journal_reception_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/journal_reception.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/ecran_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import 'support/faux_transport.dart';

/// La partie « Réception » de l'écran de synchronisation (26/10/2026) : le
/// journal des éléments reçus, ses compteurs, ses filtres, le détail d'un
/// élément avec sa CAUSE en français, « Relancer », « Relancer tout »,
/// « Corriger » — et, côté Envoi, la cause d'un refus, l'historique des
/// tentatives et la correction de la charge.
void main() {
  late BancSync b;
  String? auteur;
  late FauxCatalogue catalogue;
  late FauxTransport transport;
  late DescenteCatalogue descente;

  setUp(() async {
    b = await BancSync.creer();
    auteur = null;
    catalogue = FauxCatalogue(const []);
    transport = FauxTransport(
      (r) => r.methode == 'GET' ? catalogue.repondre(r) : reponseLot(r),
    );
    descente = DescenteCatalogue(
      db: b.db,
      transport: transport,
      auteur: () async => auteur,
      maintenant: () => b.maintenant,
    );
  });
  tearDown(() => b.fermer());

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  Future<void> descendre(WidgetTester tester, List<Map<String, Object?>> els) =>
      tester.runAsync(() async {
        catalogue = FauxCatalogue(els);
        await DescenteCatalogueDao(b.db).effacerCurseur();
        await descente.descendre(
          (await b.lecteur.appairage())!,
          surRefus: (_) async {},
        );
      });

  Future<void> monter(
    WidgetTester tester, {
    String role = 'administrateur',
    List<String> routesVues = const [],
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 4000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': 'C'});
    final routeur = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => const Scaffold(body: EcranSynchronisation()),
        ),
        GoRoute(
          path: '/comptes-utilisateurs',
          builder: (c, s) => const Scaffold(
            body: Text('Écran des comptes', key: Key('ecran-comptes')),
          ),
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
              role: role,
              droits: droits,
            ),
          ),
          transportSynchronisationProvider.overrideWithValue(transport),
          urlServeurSynchronisationProvider.overrideWithValue(
            BancSync.urlServeur,
          ),
          cheminConfigurationPosteProvider.overrideWithValue(b.chemin),
          descenteCatalogueProvider.overrideWithValue(descente),
        ],
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await laisserTourner(tester);
    await tester.tap(find.byKey(const Key('sync-onglet-reception')));
    await laisserTourner(tester);
  }

  String texteDe(WidgetTester tester, Key cle) =>
      tester.widget<Text>(find.byKey(cle)).data!;

  /// Un catalogue varié : un point de stockage aligné, une unité sans sa
  /// catégorie (en attente), un article à valeur inconnue (refusé), un menu
  /// sans compte local pour l'écrire (en attente).
  List<Map<String, Object?>> varie() => [
    element('points_stockage', 'ps-1', {
      'libelle': 'Magasin',
      'type': 'magasin',
    }),
    element('articles', 'art-9', {
      'libelle': 'Huile',
      'categorie': 'Épicerie',
      'unite_mesure': 'l',
      'suivi': 'quotidien-fou',
      'seuil_alerte': '1.00',
    }),
    element('menus', 'm-1', {'libelle': 'Midi', 'type': 'local'}),
    element('unites_hebergement', 'u-1', {
      'categorie_id': 'cat-1',
      'numero': '101',
      'statut': 'libre',
    }),
  ];

  testWidgets('compteurs, liste, causes en FRANÇAIS — aucun nom de table '
      'brut, aucun code', (tester) async {
    await descendre(tester, varie());
    await monter(tester);

    expect(texteDe(tester, const Key('recep-compteur-recus')), '4');
    expect(texteDe(tester, const Key('recep-compteur-aligne')), '1');
    expect(texteDe(tester, const Key('recep-compteur-conserve')), '0');
    expect(texteDe(tester, const Key('recep-compteur-attente')), '2');
    expect(texteDe(tester, const Key('recep-compteur-refuse')), '1');

    expect(
      texteDe(tester, const Key('recep-table-articles-art-9')),
      'Articles de stock',
    );
    expect(
      texteDe(tester, const Key('recep-issue-articles-art-9')),
      'Refusée par ce poste',
    );
    expect(
      texteDe(tester, const Key('recep-cause-articles-art-9')),
      'Valeur inconnue de ce poste',
    );
    expect(texteDe(tester, const Key('recep-element-articles-art-9')), 'Huile');
    expect(
      texteDe(tester, const Key('recep-cause-unites_hebergement-u-1')),
      'Élément lié manquant',
    );
    expect(
      texteDe(tester, const Key('recep-cause-menus-m-1')),
      'Aucun compte sur ce poste',
    );
    expect(texteDe(tester, const Key('recep-cause-points_stockage-ps-1')), '—');

    final tout = [
      for (final t in tester.widgetList<Text>(find.byType(Text)))
        if (t.data != null) t.data!,
    ].join('\n');
    for (final brut in [
      'unites_hebergement',
      'points_stockage',
      'dependance_manquante',
      'valeur_inconnue',
      'element_differe',
    ]) {
      expect(tout, isNot(contains(brut)), reason: brut);
    }
    // « Synchronisé » ne se dit pas ici de ce qui est seulement reçu.
    expect(tout, isNot(contains('Tout est synchronisé')));
  });

  testWidgets('filtres : par issue (compteur), par table (liste), '
      '« Effacer les filtres »', (tester) async {
    await descendre(tester, varie());
    await monter(tester);

    await tester.tap(find.byKey(const Key('recep-filtre-refuse')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('recep-issue-articles-art-9')), findsOneWidget);
    expect(find.byKey(const Key('recep-issue-menus-m-1')), findsNothing);
    expect(
      find.byKey(const Key('recep-issue-points_stockage-ps-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('recep-filtre-effacer')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('recep-issue-menus-m-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('recep-filtre-table')));
    await laisserTourner(tester);
    await tester.tap(find.text('Menus').last);
    await laisserTourner(tester);
    expect(find.byKey(const Key('recep-issue-menus-m-1')), findsOneWidget);
    expect(find.byKey(const Key('recep-issue-articles-art-9')), findsNothing);
  });

  testWidgets('le DÉTAIL d’un élément dit sa cause et comment la corriger', (
    tester,
  ) async {
    await descendre(tester, varie());
    await monter(tester);

    await tester.tap(find.byKey(const Key('recep-detail-articles-art-9')));
    await laisserTourner(tester);
    expect(
      texteDe(tester, const Key('recep-detail-issue')),
      'Refusée par ce poste',
    );
    expect(
      texteDe(tester, const Key('recep-detail-cause')),
      allOf(contains('Suivi'), contains('quotidien-fou')),
    );
    expect(
      texteDe(tester, const Key('recep-detail-correction')),
      contains('Mettez le logiciel du poste à jour'),
    );
    expect(texteDe(tester, const Key('recep-detail-tentatives')), '1');
    await tester.tap(find.byKey(const Key('recep-detail-fermer')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('recep-detail')), findsNothing);
  });

  testWidgets('« Relancer » un élément : sans compte il reste en attente '
      '(2 tentatives), avec un compte il est ALIGNÉ', (tester) async {
    await descendre(tester, varie());
    await monter(tester);

    await tester.tap(find.byKey(const Key('recep-relancer-menus-m-1')));
    await laisserTourner(tester);
    expect(find.textContaining('Toujours en attente'), findsOneWidget);
    final enBase = await tester.runAsync(
      () => JournalReceptionDao(b.db).lire('menus', 'm-1'),
    );
    expect(enBase!.tentatives, 2);
    expect(texteDe(tester, const Key('recep-essais-menus-m-1')), '2');

    auteur = 'u-admin';
    await tester.runAsync(b.semerAuteur);
    await tester.tap(find.byKey(const Key('recep-relancer-menus-m-1')));
    await laisserTourner(tester);
    expect(
      find.textContaining('Élément aligné : il est à jour'),
      findsOneWidget,
    );
    expect(texteDe(tester, const Key('recep-issue-menus-m-1')), 'Alignée');
    expect(texteDe(tester, const Key('recep-compteur-aligne')), '2');
    expect(find.byKey(const Key('recep-relancer-menus-m-1')), findsNothing);
  });

  testWidgets('« Relancer tout » : les éléments gardés sont repris, un '
      'passage complet est lancé', (tester) async {
    await descendre(tester, varie());
    await monter(tester);
    auteur = 'u-admin';
    await tester.runAsync(b.semerAuteur);

    await tester.tap(find.byKey(const Key('recep-relancer-tout')));
    await laisserTourner(tester);
    expect(
      find.textContaining('élément(s) restent à traiter'),
      findsOneWidget,
      reason: 'l’article refusé et l’unité sans catégorie restent',
    );
    expect(texteDe(tester, const Key('recep-compteur-aligne')), '2');
    expect(texteDe(tester, const Key('recep-compteur-refuse')), '1');
    expect(
      transport.descentes,
      isNotEmpty,
      reason: 'un passage complet reprend la réception depuis le curseur',
    );
  });

  testWidgets('« Corriger » : la cause exacte, le lien qui mène à ce qui '
      'manque (ici l’écran des comptes), puis « Relancer »', (tester) async {
    await descendre(tester, varie());
    await monter(tester);

    await tester.tap(find.byKey(const Key('recep-corriger-menus-m-1')));
    await laisserTourner(tester);
    expect(
      texteDe(tester, const Key('recep-correction-cause')),
      contains('aucun compte actif'),
    );
    expect(
      texteDe(tester, const Key('recep-correction-etapes')),
      contains('Créez un compte actif'),
    );
    await tester.tap(find.byKey(const Key('recep-correction-ecran')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('ecran-comptes')), findsOneWidget);
  });

  testWidgets('« Corriger » une dépendance manquante : voir les éléments '
      'liés filtre le journal sur leur table', (tester) async {
    await descendre(tester, varie());
    await monter(tester);

    await tester.tap(
      find.byKey(const Key('recep-corriger-unites_hebergement-u-1')),
    );
    await laisserTourner(tester);
    expect(
      texteDe(tester, const Key('recep-correction-cause')),
      contains('Catégories d\'hébergement'),
    );
    // Voir les éléments liés : le journal se filtre sur leur table — et
    // montre que l'élément lié n'est même pas arrivé.
    await tester.tap(find.byKey(const Key('recep-correction-liens')));
    await laisserTourner(tester);
    expect(find.byKey(const Key('recep-vide')), findsOneWidget);
    expect(find.byKey(const Key('recep-filtre-effacer')), findsOneWidget);
    expect(
      find.byKey(const Key('recep-issue-unites_hebergement-u-1')),
      findsNothing,
    );
  });

  testWidgets('un NON-administrateur lit le journal : aucun geste ne lui '
      'est offert, et l’écran le dit', (tester) async {
    await descendre(tester, varie());
    await monter(tester, role: 'caissier');

    expect(
      find.byKey(const Key('recep-detail-articles-art-9')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('recep-relancer-articles-art-9')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('recep-corriger-articles-art-9')),
      findsNothing,
    );
    expect(
      tester
          .widget<BoutonStandard>(find.byKey(const Key('recep-relancer-tout')))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('recep-reserve')), findsOneWidget);
  });

  testWidgets('annonces du serveur, dernier contrôle de cohérence et ses '
      'écarts sont visibles', (tester) async {
    await tester.runAsync(() async {
      await DescenteCatalogueDao(b.db).retenirAnnoncesServeur({
        'x-tatacora-phase-essais': '1',
        'x-tatacora-generation': 'g-1',
      });
      await DescenteCatalogueDao(b.db).consignerCoherence(
        coherenceVersJson(
          const CoherenceMesuree(
            du: '2026-10-19',
            au: '2026-10-25',
            tables: ['ventes'],
            enAttente: 0,
            ecarts: [
              EcartCoherence(
                table: 'ventes',
                jour: '2026-10-24',
                serveur: (nombre: 3, total: 450000),
                poste: (nombre: 2, total: 300000),
              ),
            ],
          ),
          DateTime(2026, 10, 25, 9, 30),
        ),
      );
    });
    await monter(tester);

    expect(
      texteDe(tester, const Key('recep-annonce-essais')),
      contains('phase d’essais'),
    );
    expect(
      texteDe(tester, const Key('recep-annonce-generation')),
      contains('génération courante'),
    );
    expect(
      texteDe(tester, const Key('sync-ecran-coherence-dernier')),
      contains('25/10/2026'),
    );
    expect(
      texteDe(tester, const Key('sync-ecran-ecart-0')),
      contains('Ventes'),
    );
    expect(
      texteDe(tester, const Key('sync-ecran-coherence-bilan')),
      contains('écart(s)'),
    );
  });

  group('Envoi : cause, historique, correction de la charge', () {
    /// Un client rejeté pour donnée invalide, avec les phrases du serveur.
    Future<String> semerRejet() async {
      final ids = await b.enfilerClients(1);
      final o = await b.operationDe(ids.single);
      await b.dao.marquerResultat(
        o.uuidOperation,
        codeHttp: 200,
        resultat: {
          'uuid_operation': o.uuidOperation,
          'statut': 'rejete',
          'entite_id': ids.single,
          'motif': 'Le téléphone est trop court.',
          'code_motif': 'donnees_invalides',
          'erreurs': {
            'telephone': ['Le téléphone est trop court.'],
          },
        },
      );
      return o.uuidOperation;
    }

    Future<void> monterEnvoi(WidgetTester tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('sync-onglet-envoi')));
      await laisserTourner(tester);
    }

    testWidgets('la CAUSE lisible, la phrase du serveur par champ, les '
        'tentatives et le dernier code', (tester) async {
      final uuid = (await tester.runAsync(semerRejet))!;
      await monterEnvoi(tester);

      expect(
        texteDe(tester, Key('sync-cause-$uuid')),
        'Donnée refusée par le serveur',
      );
      expect(
        texteDe(tester, Key('sync-motif-$uuid')),
        'Le téléphone est trop court.',
      );
      expect(
        texteDe(tester, Key('sync-erreur-champ-$uuid-0')),
        'Téléphone : Le téléphone est trop court.',
      );
      expect(
        texteDe(tester, Key('sync-tentatives-$uuid')),
        '0 tentative(s) — dernier code 200',
      );

      await tester.tap(find.byKey(Key('sync-detail-$uuid')));
      await laisserTourner(tester);
      expect(
        texteDe(tester, const Key('envoi-detail-conseil')),
        contains('Corrigez les champs signalés'),
      );
      expect(texteDe(tester, const Key('envoi-detail-http')), '200');
      expect(
        texteDe(tester, const Key('envoi-detail-historique-0')),
        contains('Rejetée'),
      );
    });

    testWidgets('« Corriger » : le formulaire est généré de la charge, '
        'validé, puis l’opération repart sous un NOUVEL uuid avec la charge '
        'corrigée ; l’ancienne reste rejetée et remplacée', (tester) async {
      final uuid = (await tester.runAsync(semerRejet))!;
      await monterEnvoi(tester);

      await tester.tap(find.byKey(Key('sync-corriger-$uuid')));
      await laisserTourner(tester);
      expect(find.byKey(const Key('envoi-saisie-nom')), findsOneWidget);
      expect(find.byKey(const Key('envoi-saisie-telephone')), findsOneWidget);
      expect(
        texteDe(tester, const Key('envoi-correction-erreur-serveur-0')),
        'Téléphone : Le téléphone est trop court.',
      );

      // Validation du contrat : un nom vide est refusé AVANT l'envoi.
      await tester.enterText(find.byKey(const Key('envoi-saisie-nom')), ' ');
      await tester.tap(find.byKey(const Key('envoi-correction-valider')));
      await laisserTourner(tester);
      expect(
        texteDe(tester, const Key('envoi-erreur-nom')),
        'Nom est obligatoire.',
      );
      expect(find.byKey(const Key('envoi-correction')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('envoi-saisie-nom')),
        'Kossi',
      );
      await tester.enterText(
        find.byKey(const Key('envoi-saisie-telephone')),
        '97001234',
      );
      await tester.tap(find.byKey(const Key('envoi-correction-valider')));
      await laisserTourner(tester);
      expect(find.byKey(const Key('envoi-correction')), findsNothing);
      expect(find.textContaining('Charge corrigée'), findsOneWidget);

      final ops = (await tester.runAsync(() => b.dao.operations()))!;
      expect(ops, hasLength(2));
      final ancienne = ops.first;
      final nouvelle = ops.last;
      expect(ancienne.statut, StatutOperationSync.rejete);
      expect(nouvelle.statut, StatutOperationSync.enAttente);
      expect(nouvelle.uuidOperation, isNot(ancienne.uuidOperation));
      final charge = jsonDecode(nouvelle.payload) as Map<String, Object?>;
      expect(charge['nom'], 'Kossi');
      expect(charge['telephone'], '97001234');
      expect(
        (jsonDecode(ancienne.payload) as Map)['nom'],
        'C0',
        reason: 'l’ancienne charge reste, intacte',
      );
      expect((await tester.runAsync(() => b.dao.remplacees()))!.keys, [
        ancienne.uuidOperation,
      ]);
      // La ligne quitte « À traiter » : la remplaçante est en attente.
      expect(find.byKey(Key('sync-corriger-$uuid')), findsNothing);
    });

    testWidgets('un non-administrateur ne voit pas « Corriger »', (
      tester,
    ) async {
      final uuid = (await tester.runAsync(semerRejet))!;
      await monter(tester, role: 'caissier');
      await tester.tap(find.byKey(const Key('sync-onglet-envoi')));
      await laisserTourner(tester);
      expect(find.byKey(Key('sync-detail-$uuid')), findsOneWidget);
      expect(find.byKey(Key('sync-corriger-$uuid')), findsNothing);
    });
  });

  test(
    'le journal ne reçoit rien de la file : aucune opération enfilée',
    () async {
      final dao = JournalReceptionDao(b.db);
      expect(await dao.compter(), isA<CompteursReception>());
      expect(await b.dao.operations(), isEmpty);
      expect(IssueReception.values, hasLength(4));
    },
  );
}
