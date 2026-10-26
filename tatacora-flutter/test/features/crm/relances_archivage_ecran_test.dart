import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/crm/impression/releve_client.dart';
import 'package:tatacora_flutter/features/crm/presentation/ecran_clients.dart';
import 'package:tatacora_flutter/features/crm/presentation/providers_crm.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_paiements.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart' show moteurSur;
import '../facturation/support/outils_encaissement.dart';

/// Les relances et l'archivage d'un client, JOUÉS sur l'écran « Clients &
/// Créances » : le geste de l'opérateur, ce que la base écrit, ce que la file
/// d'envoi reçoit. (Les règles seules : `relances_clients_dao_test.dart` et
/// `archivage_clients_dao_test.dart`.)
void main() {
  late AppDatabase db;
  late List<ReleveClient> releves;

  setUp(() async {
    db = await baseEncaissement();
    releves = [];
  });
  tearDown(() => db.close());

  List<Override> surcharges({
    String role = 'administrateur',
    Map<String, String> droits = const {'M3': 'C', 'M2': 'C'},
  }) {
    final h = jourEncaissement;
    final garde = GardeAcces.depuisJson(droits);
    return [
      baseLocaleProvider.overrideWithValue(db),
      factureDaoProvider.overrideWithValue(factureDaoSur(db)),
      paiementsFactureDaoProvider.overrideWithValue(paiementsDaoSur(db)),
      moteurComptableProvider.overrideWith(
        (ref) async => moteurSur(db, maintenant: () => h),
      ),
      horlogeCreancesProvider.overrideWithValue(() => h),
      droitsProvider.overrideWithValue(garde),
      sessionProvider.overrideWithBuild(
        (ref, notifier) => Session(
          utilisateurId: caissierEssai,
          login: 'amina',
          nom: 'Amina',
          role: role,
          droits: garde,
        ),
      ),
      exporterReleveClientProvider.overrideWithValue((releve) async {
        releves.add(releve);
        return 'C:/Documents/releve_client.pdf';
      }),
    ];
  }

  Future<void> monter(
    WidgetTester tester, {
    String role = 'administrateur',
    Map<String, String> droits = const {'M3': 'C', 'M2': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: surcharges(role: role, droits: droits),
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranClients()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> onglet(WidgetTester tester, String cle) async {
    await tester.tap(find.byKey(Key('clients-onglet-$cle')));
    await tester.pumpAndSettle();
  }

  Future<List<OperationSync>> file(TableSynchronisee t) =>
      OperationsSyncDao(db).operations(table: t);

  /* ================================================================== */
  group('Relances', () {
    testWidgets('un débiteur jamais relancé est « à relancer », compté par la '
        'carte et par le titre', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9), // 41 jours
      );
      await monter(tester);

      expect(
        find.descendant(
          of: find.byKey(const Key('clients-kpi-4')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await onglet(tester, 'relances');

      expect(find.text('Clients à relancer (1)'), findsOneWidget);
      final ligne = find.byKey(Key('clients-arelancer-${c.id}'));
      expect(ligne, findsOneWidget);
      expect(
        find.descendant(of: ligne, matching: find.text('50 000 FCFA')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ligne, matching: find.text('41 j')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ligne, matching: find.text('Jamais relancé')),
        findsOneWidget,
      );
      expect(find.byKey(Key('clients-relancer-${c.id}')), findsOneWidget);
      expect(find.text('Historique des relances (0)'), findsOneWidget);
      expect(
        find.byKey(const Key('clients-historique-relances-vide')),
        findsOneWidget,
      );
    });

    testWidgets('« Relancer » ouvre la modale pré-remplie du solde, aux cinq '
        'canaux, et l’enregistrement ÉCRIT, ENFILE et RETIRE le client de la '
        'liste', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9),
      );
      await monter(tester);
      await onglet(tester, 'relances');

      await tester.tap(find.byKey(Key('clients-relancer-${c.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-relance')), findsOneWidget);
      expect(find.text('Tracer une relance'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('relance-client'))).data,
        'KORA',
      );
      // Le montant réclamé est le SOLDE vivant du client.
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('relance-montant')))
            .controller!
            .text,
        '50000.00',
      );
      expect(
        find.text(
          'Cet écran enregistre une relance déjà effectuée. Il n\'envoie aucun message : aucun canal n\'est branché sur ce système.',
        ),
        findsOneWidget,
      );
      // Les cinq canaux du registre fermé.
      await tester.tap(find.byKey(const Key('relance-canal')));
      await tester.pumpAndSettle();
      for (final libelle in [
        'Appel téléphonique',
        'WhatsApp',
        'E-mail',
        'Courrier remis en main propre',
        'Visite',
      ]) {
        expect(find.text(libelle), findsWidgets, reason: libelle);
      }
      await tester.tap(find.text('WhatsApp').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('relance-commentaire')),
        'Rappelle vendredi',
      );
      await tester.enterText(
        find.byKey(const Key('relance-promesse')),
        '2026-10-30',
      );
      await tester.tap(find.byKey(const Key('relance-enregistrer')));
      await tester.pumpAndSettle();

      // Le fait est écrit…
      final ligne = await db.select(db.relancesClientsLocal).getSingle();
      expect(ligne.clientId, c.id);
      expect(ligne.canal, 'whatsapp');
      expect(ligne.montantReclameCentimes, 5000000);
      expect(ligne.promesse, '2026-10-30');
      expect(ligne.commentaire, 'Rappelle vendredi');
      expect(ligne.creePar, 'amina');
      // …et enfilé.
      expect(await file(TableSynchronisee.relancesClients), hasLength(1));
      // La modale est fermée, le succès est dit.
      expect(find.byKey(const Key('modale-relance')), findsNothing);
      expect(find.text('Relance de « KORA » enregistrée.'), findsOneWidget);
      // Le client n'est plus « à relancer » (relancé il y a 0 jour)…
      expect(find.text('Clients à relancer (0)'), findsOneWidget);
      expect(find.byKey(Key('clients-arelancer-${c.id}')), findsNothing);
      // …et l'historique le porte, avec les colonnes de la vue.
      expect(find.text('Historique des relances (1)'), findsOneWidget);
      final h = find.byKey(Key('clients-relance-ligne-${ligne.id}'));
      for (final texte in [
        '12/10/2026',
        'KORA',
        'WhatsApp',
        '50 000 FCFA',
        '30/10/2026',
        'amina',
      ]) {
        expect(
          find.descendant(of: h, matching: find.text(texte)),
          findsOneWidget,
          reason: texte,
        );
      }
    });

    testWidgets('un montant vide est refusé SOUS le champ, la saisie reste, '
        'rien n’est écrit', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9),
      );
      await monter(tester);
      await onglet(tester, 'relances');
      await tester.tap(find.byKey(Key('clients-relancer-${c.id}')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('relance-montant')), '');
      await tester.enterText(
        find.byKey(const Key('relance-commentaire')),
        'à garder',
      );
      await tester.tap(find.byKey(const Key('relance-enregistrer')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('relance-refus'))).data,
        'Le champ relance montant est obligatoire.',
      );
      expect(find.byKey(const Key('modale-relance')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('relance-commentaire')))
            .controller!
            .text,
        'à garder',
      );
      expect(await db.select(db.relancesClientsLocal).get(), isEmpty);
      expect(await file(TableSynchronisee.relancesClients), isEmpty);
    });

    testWidgets('une promesse illisible est refusée sous son champ', (
      tester,
    ) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9),
      );
      await monter(tester);
      await onglet(tester, 'relances');
      await tester.tap(find.byKey(Key('clients-relancer-${c.id}')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('relance-promesse')),
        'bientôt',
      );
      await tester.tap(find.byKey(const Key('relance-enregistrer')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('relance-erreur-promesse')))
            .data,
        'Le champ relance promesse n\'est pas une date valide.',
      );
      expect(await db.select(db.relancesClientsLocal).get(), isEmpty);
    });

    testWidgets('sans écriture sur M3, « Relancer » n’est pas offert', (
      tester,
    ) async {
      final c = await creerClient(db);
      await emettreFacture(
        db,
        montant: 50000,
        clientId: c.id,
        horloge: DateTime(2026, 9, 1, 9),
      );
      await monter(tester, droits: const {'M3': 'L', 'M2': 'C'});
      await onglet(tester, 'relances');

      expect(find.byKey(Key('clients-arelancer-${c.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-relancer-${c.id}')), findsNothing);
    });

    testWidgets(
      'l’historique d’un client ET son relevé PDF portent la relance',
      (tester) async {
        final c = await creerClient(db);
        await emettreFacture(
          db,
          montant: 50000,
          clientId: c.id,
          horloge: DateTime(2026, 9, 1, 9),
        );
        await monter(tester);
        await onglet(tester, 'relances');
        await tester.tap(find.byKey(Key('clients-relancer-${c.id}')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('relance-enregistrer')));
        await tester.pumpAndSettle();

        await onglet(tester, 'clients');
        await tester.tap(find.byKey(Key('clients-historique-${c.id}')));
        await tester.pumpAndSettle();

        final modale = find.byKey(const Key('modale-historique-client'));
        expect(
          find.descendant(of: modale, matching: find.text('Relance')),
          findsNWidgets(2), // la pastille du type, puis le libellé
        );
        expect(
          find.descendant(
            of: modale,
            matching: find.text('Appel téléphonique'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: modale, matching: find.text('50 000 FCFA')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('historique-client-vide')), findsNothing);

        await tester.tap(find.byKey(const Key('historique-client-imprimer')));
        await tester.pumpAndSettle();
        expect(releves, hasLength(1));
        expect(releves.single.mouvements.single.type, 'Relance');
        expect(releves.single.mouvements.single.montantCentimes, 5000000);
        expect(releves.single.lignes.single, [
          '12/10/2026',
          'Relance',
          '50 000 FCFA',
        ]);
      },
    );
  });

  /* ================================================================== */
  group('Archivage', () {
    testWidgets('l’administrateur voit la case et « Supprimer »', (
      tester,
    ) async {
      final c = await creerClient(db);
      await monter(tester);
      expect(find.byKey(Key('clients-case-${c.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-supprimer-${c.id}')), findsOneWidget);
    });

    testWidgets('un rôle sans la bascule ne voit NI la case NI « Supprimer »', (
      tester,
    ) async {
      final c = await creerClient(db);
      await monter(tester, role: 'gerant');
      expect(find.byKey(Key('clients-ligne-${c.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-case-${c.id}')), findsNothing);
      expect(find.byKey(Key('clients-supprimer-${c.id}')), findsNothing);
    });

    testWidgets('« Supprimer » → confirmation → ARCHIVE : badge, « Restaurer », '
        'file, et la fiche reste', (tester) async {
      final c = await creerClient(db);
      await monter(tester);

      await tester.tap(find.byKey(Key('clients-supprimer-${c.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Confirmer la suppression'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('achats-archivage-question'))),
        isA<Text>(),
      );
      expect(find.textContaining('Voulez-vous archiver'), findsOneWidget);
      expect(
        find.byKey(const Key('achats-archivage-confirmer')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
      await tester.pumpAndSettle();

      expect(
        (await db.select(db.clientsLocal).getSingle()).actif,
        isFalse,
        reason: 'la fiche est archivée, pas effacée',
      );
      expect(find.byKey(Key('clients-archive-${c.id}')), findsOneWidget);
      expect(find.text('Archivé'), findsOneWidget);
      expect(
        find.text('Client archivé — il reste restaurable.'),
        findsOneWidget,
      );
      // Plus de case ni de « Supprimer » sur un archivé ; « Restaurer » à la place.
      expect(find.byKey(Key('clients-case-${c.id}')), findsNothing);
      expect(find.byKey(Key('clients-supprimer-${c.id}')), findsNothing);
      expect(find.byKey(Key('clients-restaurer-${c.id}')), findsOneWidget);
      final ops = await file(TableSynchronisee.clients);
      expect(ops.last.payload, '{"actif":false}');

      // Le message de succès laisse la place au suivant (4 s).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('clients-restaurer-${c.id}')));
      await tester.pumpAndSettle();
      expect((await db.select(db.clientsLocal).getSingle()).actif, isTrue);
      expect(find.byKey(Key('clients-archive-${c.id}')), findsNothing);
      expect(find.text('Client « KORA » restauré.'), findsOneWidget);
      expect(
        (await file(TableSynchronisee.clients)).last.payload,
        '{"actif":true}',
      );
    });

    testWidgets('un client ENGAGÉ : « Archivage impossible », ses motifs, et '
        'PAS de bouton de confirmation', (tester) async {
      final c = await creerClient(db);
      await emettreFacture(db, montant: 5000, clientId: c.id);
      await monter(tester);

      await tester.tap(find.byKey(Key('clients-supprimer-${c.id}')));
      await tester.pumpAndSettle();

      expect(find.text('Archivage impossible'), findsOneWidget);
      expect(
        find.textContaining('KORA — Il porte 1 facture(s) non soldée(s)'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('achats-archivage-confirmer')), findsNothing);
      expect(
        (await db.select(db.clientsLocal).getSingle()).actif,
        isNot(false),
      );
    });

    testWidgets('la sélection groupée : « N sélectionné(s) », « Supprimer », '
        'archive les cochés seulement', (tester) async {
      final a = await creerClient(db, nom: 'ALPHA');
      final b = await creerClient(db, nom: 'BETA', telephone: '2');
      final g = await creerClient(db, nom: 'GAMMA', telephone: '3');
      await monter(tester);
      expect(find.byKey(const Key('clients-barre-selection')), findsNothing);

      await tester.tap(find.byKey(Key('clients-case-${a.id}')));
      await tester.tap(find.byKey(Key('clients-case-${b.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('clients-barre-selection')), findsOneWidget);
      expect(find.textContaining('sélectionné(s)'), findsOneWidget);

      await tester.tap(find.byKey(const Key('clients-selection-supprimer')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Voulez-vous archiver les'), findsOneWidget);
      await tester.tap(find.byKey(const Key('achats-archivage-confirmer')));
      await tester.pumpAndSettle();

      final lignes = {
        for (final l in await db.select(db.clientsLocal).get()) l.id: l.actif,
      };
      expect(lignes[a.id], isFalse);
      expect(lignes[b.id], isFalse);
      expect(lignes[g.id], isNot(false));
      expect(
        find.text('2 clients archivés — ils restent restaurables.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('clients-barre-selection')), findsNothing);
    });

    testWidgets('un rôle qui écrit sur M3 sans droit d’archiver RESTAURE '
        'quand même', (tester) async {
      final c = await creerClient(db);
      await db
          .update(db.clientsLocal)
          .write(const ClientsLocalCompanion(actif: Value(false)));
      await monter(tester, role: 'gerant');

      expect(find.byKey(Key('clients-archive-${c.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-restaurer-${c.id}')), findsOneWidget);
      expect(find.byKey(Key('clients-supprimer-${c.id}')), findsNothing);
    });
  });
}
