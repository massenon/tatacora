import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/crm/domain/historique_client.dart';
import 'package:tatacora_flutter/features/crm/impression/releve_client.dart';
import 'package:tatacora_flutter/features/crm/presentation/ecran_clients.dart';
import 'package:tatacora_flutter/features/crm/presentation/providers_crm.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';

import '../facturation/support/outils_encaissement.dart';

/// Ce que l'écran Clients & Créances rend DEPUIS le 21/10/2026, en plus de
/// l'encaissement : la modale « Historique d'un client », son « Imprimer PDF »,
/// le bouton « Détail » du suivi des dettes, et le tableau des avances.
///
/// Les relances, elles, restent refusées : ces cas protègent aussi que la modale
/// DIT qu'elle ne les porte pas — « Aucun mouvement » sans cette mention se
/// lirait comme « jamais relancé ».
void main() {
  late AppDatabase db;
  late List<ReleveClient> releves;

  setUp(() async {
    db = await baseEncaissement();
    releves = [];
  });

  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...surchargesEncaissement(db),
          // Le relevé est une ACTION injectée : un test de widget n'a pas de
          // fenêtre « Enregistrer sous ».
          exporterReleveClientProvider.overrideWithValue((releve) async {
            releves.add(releve);
            return 'C:/Documents/releve_client.pdf';
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranClients()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrirOnglet(WidgetTester tester, String cle) async {
    await tester.tap(find.byKey(Key('clients-onglet-$cle')));
    await tester.pumpAndSettle();
  }

  /* ================================================================== */
  group('La modale « Historique d’un client »', () {
    testWidgets('« Historique » ouvre la modale au nom du client, ses cinq '
        'colonnes et ses encaissements', (tester) async {
      final c = await creerClient(db);
      final f = await emettreFacture(db, montant: 30000, clientId: c.id);
      await ouvrirCaissePour(db);
      await paiementsDaoSur(db).encaisser(
        pieceId: f.id,
        montant: '12000',
        mode: 'mobile_money',
        auteurId: caissierEssai,
      );
      await monter(tester);

      await tester.tap(find.byKey(Key('clients-historique-${c.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-historique-client')), findsOneWidget);
      for (final t in const ['DATE', 'TYPE', 'LIBELLÉ', 'DÉTAIL', 'MONTANT']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      Finder dansLaModale(String texte) => find.descendant(
        of: find.byKey(const Key('modale-historique-client')),
        matching: find.text(texte),
      );
      expect(dansLaModale('Encaissement'), findsOneWidget);
      expect(dansLaModale(f.numero), findsOneWidget);
      expect(dansLaModale('Mobile Money'), findsOneWidget);
      expect(dansLaModale('12 000 FCFA'), findsOneWidget);
      expect(find.byKey(const Key('historique-client-vide')), findsNothing);
      expect(find.text('Imprimer PDF'), findsOneWidget);
    });

    testWidgets('un client sans mouvement le DIT, et dit que les relances ne '
        'sont pas portées', (tester) async {
      final c = await creerClient(db);
      await monter(tester);

      await tester.tap(find.byKey(Key('clients-historique-${c.id}')));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(find.byKey(const Key('historique-client-vide')))
            .data,
        'Aucun mouvement pour ce client.',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('historique-client-mention')))
            .data,
        ReleveClient.mentionRelances,
      );
    });

    testWidgets('l’historique d’un client ne montre PAS les encaissements d’un '
        'autre', (tester) async {
      final k = await creerClient(db, nom: 'KORA');
      final y = await creerClient(db, nom: 'YAYI', telephone: '96000000');
      final fy = await emettreFacture(db, montant: 7000, clientId: y.id);
      await ouvrirCaissePour(db);
      await paiementsDaoSur(db).encaisser(
        pieceId: fy.id,
        montant: '7000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await monter(tester);

      await tester.tap(find.byKey(Key('clients-historique-${k.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('historique-client-vide')), findsOneWidget);
    });

    testWidgets('« Détail » du suivi des dettes ouvre la même modale', (
      tester,
    ) async {
      final c = await creerClient(db);
      await emettreFacture(db, montant: 30000, clientId: c.id);
      await monter(tester);
      await ouvrirOnglet(tester, 'dettes');

      await tester.tap(find.byKey(Key('clients-detail-${c.id}')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-historique-client')), findsOneWidget);
      // Le titre de la modale est le nom du client.
      expect(
        find.descendant(
          of: find.byKey(const Key('modale-historique-client')),
          matching: find.text('KORA'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('« Imprimer PDF » compose le relevé du client et le DIT', (
      tester,
    ) async {
      final c = await creerClient(db);
      final f = await emettreFacture(db, montant: 30000, clientId: c.id);
      await ouvrirCaissePour(db);
      await paiementsDaoSur(db).encaisser(
        pieceId: f.id,
        montant: '12000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await monter(tester);
      await tester.tap(find.byKey(Key('clients-historique-${c.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('historique-client-imprimer')));
      await tester.pumpAndSettle();

      expect(releves, hasLength(1));
      expect(releves.single.clientNom, 'KORA');
      expect(releves.single.mouvements.single.montantCentimes, 1200000);
      expect(releves.single.mouvements.single.type, 'Encaissement');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('historique-client-enregistre')))
            .data,
        'Export enregistré : releve_client.pdf',
      );
    });

    testWidgets('« Fermer » referme la modale sans rien écrire', (
      tester,
    ) async {
      final c = await creerClient(db);
      await monter(tester);
      await tester.tap(find.byKey(Key('clients-historique-${c.id}')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('historique-client-fermer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-historique-client')), findsNothing);
      expect(releves, isEmpty);
    });
  });

  /* ================================================================== */
  group('Le relevé de compte client (document remis au client)', () {
    test('trois colonnes, des montants en FCFA, une mention sur les '
        'relances', () {
      final releve = ReleveClient(
        clientNom: 'KORA Jean',
        editeLe: DateTime(2026, 10, 21),
        mouvements: [
          (
            date: DateTime(2026, 10, 12),
            type: 'Encaissement',
            montantCentimes: 5600000,
          ),
        ],
      );

      expect(ReleveClient.entetes, ['Date', 'Type', 'Montant']);
      expect(releve.lignes.single, [
        '12/10/2026',
        'Encaissement',
        '56 000 FCFA',
      ]);
      expect(releve.estVide, isFalse);
      expect(
        ReleveClient.mentionRelances,
        contains('Les relances ne sont pas'),
      );
    });

    test('le PDF se compose, vide comme plein', () async {
      for (final mouvements in [
        <MouvementReleve>[],
        [
          (
            date: DateTime(2026, 10, 12),
            type: 'Encaissement',
            montantCentimes: 100000,
          ),
        ],
      ]) {
        final octets = await ReleveClient(
          clientNom: 'KORA',
          editeLe: DateTime(2026, 10, 21),
          mouvements: mouvements,
        ).pdf();
        expect(String.fromCharCodes(octets.take(4)), '%PDF');
      }
    });

    test('la composition ne retient QUE les encaissements du client, du plus '
        'récent au plus ancien, annulés compris', () async {
      final c = await creerClient(db);
      final autre = await creerClient(db, nom: 'YAYI', telephone: '96000000');
      final f = await emettreFacture(db, montant: 30000, clientId: c.id);
      final g = await emettreFacture(db, montant: 9000, clientId: autre.id);
      await ouvrirCaissePour(db);
      final dao = paiementsDaoSur(db);
      final premier = await dao.encaisser(
        pieceId: f.id,
        montant: '1000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      await dao.encaisser(
        pieceId: g.id,
        montant: '9000',
        mode: 'especes',
        auteurId: caissierEssai,
      );
      final paiements = await dao.paiements();
      final mouvements = composerHistoriqueClient(
        clientId: c.id,
        paiements: paiements,
        creances: [
          CreanceFacture(
            piece: f,
            ttcCentimes: 3000000,
            avoirsCentimes: 0,
            paiementsActifsCentimes: 100000,
            acomptesCentimes: 0,
          ),
          CreanceFacture(
            piece: g,
            ttcCentimes: 900000,
            avoirsCentimes: 0,
            paiementsActifsCentimes: 900000,
            acomptesCentimes: 0,
          ),
        ],
      );

      expect(mouvements, hasLength(1));
      expect(mouvements.single.libelle, f.numero);
      expect(mouvements.single.montantCentimes, 100000);
      expect(premier.mode, ModePaiementFacture.especes);
    });
  });

  /* ================================================================== */
  group('Le tableau « Avances et acomptes »', () {
    testWidgets(
      'une réservation à acompte y figure : arrivée, client, origine, '
      'avance et reste dû',
      (tester) async {
        final c = await creerClient(db);
        await semerReservation(
          db,
          id: 'r1',
          clientId: c.id,
          acompte: 20000,
          total: 80000,
        );
        await monter(tester);
        await ouvrirOnglet(tester, 'avances');

        expect(find.text('Avances et acomptes (1)'), findsOneWidget);
        final ligne = find.byKey(const Key('clients-avance-ligne-r1'));
        String lu(Finder f) => tester
            .widgetList<Text>(
              find.descendant(of: f, matching: find.byType(Text)),
            )
            .map((t) => t.data)
            .join(' | ');
        expect(
          lu(ligne),
          '20/10/2026 | KORA | Physique | 20 000 FCFA | 60 000 FCFA',
        );
      },
    );

    testWidgets('un acompte qui couvre tout le séjour rend « Soldé »', (
      tester,
    ) async {
      final c = await creerClient(db);
      await semerReservation(
        db,
        id: 'r1',
        clientId: c.id,
        acompte: 80000,
        total: 80000,
      );
      await monter(tester);
      await ouvrirOnglet(tester, 'avances');

      expect(
        find.descendant(
          of: find.byKey(const Key('clients-avance-ligne-r1')),
          matching: find.text('Soldé'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('sans acompte, ou annulée, une réservation n’y figure PAS', (
      tester,
    ) async {
      final c = await creerClient(db);
      await semerReservation(db, id: 'sans', clientId: c.id, total: 80000);
      // Un acompte versé, mais la réservation est ANNULÉE : `whereNot('statut',
      // 'annulee')` de la vue l'écarte.
      await semerReservation(
        db,
        id: 'annulee',
        clientId: c.id,
        acompte: 10000,
        total: 80000,
      );
      await db.customStatement(
        "UPDATE reservations_local SET statut = 'annulee' WHERE id = 'annulee'",
      );
      await monter(tester);
      await ouvrirOnglet(tester, 'avances');

      expect(find.byKey(const Key('clients-avance-ligne-sans')), findsNothing);
      expect(
        find.byKey(const Key('clients-avance-ligne-annulee')),
        findsNothing,
      );
      expect(find.byKey(const Key('clients-avances-vide')), findsOneWidget);
      expect(find.text('Aucune avance enregistrée.'), findsOneWidget);
    });

    testWidgets('un montant INCONNU (tarif zéro, aucune ligne) rend « — », '
        'jamais une dette négative', (tester) async {
      final c = await creerClient(db);
      await semerReservation(db, id: 'r1', clientId: c.id, acompte: 5000);
      // Une réservation descendue d'un autre poste : ni tarif ni ligne.
      await db.customStatement('DELETE FROM lignes_reservation_local');
      await db.customStatement(
        'UPDATE reservations_local SET tarif_nuit = 0 WHERE id = ?',
        ['r1'],
      );
      await monter(tester);
      await ouvrirOnglet(tester, 'avances');

      final ligne = find.byKey(const Key('clients-avance-ligne-r1'));
      expect(ligne, findsOneWidget);
      expect(
        find.descendant(of: ligne, matching: find.text('—')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: ligne, matching: find.textContaining('-')),
        findsNothing,
      );
    });
  });
}
