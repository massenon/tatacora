import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/canaux_reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_canaux.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/onglet_canaux.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../facturation/support/outils_encaissement.dart'
    show semerReservation, creerClient;

/// Paramètres › « Canaux de réservation » (21/10/2026) : ajout, renommage,
/// désactivation (avec confirmation quand le canal est employé) et
/// réactivation sont PORTÉS — table locale, file d'envoi, plus de refus.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.enMemoire());
  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester, {bool peutEcrire = true}) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [baseLocaleProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: SingleChildScrollView(
              child: OngletCanaux(peutEcrire: peutEcrire),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<List<OperationSync>> file() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.canauxReservation);

  testWidgets('le tableau montre le jeu initial, « actif », et les boutons '
      'de la vue pour qui écrit', (tester) async {
    await monter(tester);
    expect(find.text('Physique'), findsOneWidget);
    expect(find.text('Agence partenaire'), findsOneWidget);
    expect(find.text('actif'), findsNWidgets(7));
    expect(find.text('Ajouter un canal'), findsOneWidget);
    expect(find.text('Renommer'), findsNWidgets(7));
    expect(find.text('Désactiver'), findsNWidgets(7));
    // Plus aucune mention de refus.
    expect(find.textContaining('se font sur le serveur'), findsNothing);
  });

  testWidgets('sans droit d’écriture : pas de bouton, « — » en actions', (
    tester,
  ) async {
    await monter(tester, peutEcrire: false);
    expect(find.text('Ajouter un canal'), findsNothing);
    expect(find.text('Renommer'), findsNothing);
    expect(find.text('—'), findsWidgets);
  });

  testWidgets('« Ajouter un canal » : la modale de la vue, le canal naît et '
      'part au serveur', (tester) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('param-canal-ajouter')));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau canal de réservation'), findsOneWidget);
    expect(
      find.text(
        'Le nom tel qu’il apparaîtra dans les formulaires de réservation.',
      ),
      findsOneWidget,
    );
    expect(find.text('Nom du canal'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('param-canal-nom')), 'Salon');
    await tester.tap(find.byKey(const Key('param-canal-valider')));
    await tester.pumpAndSettle();

    expect(find.text('Salon'), findsOneWidget);
    expect(find.text(MessagesCanaux.enregistre), findsOneWidget);
    final ops = await file();
    expect(ops.single.type, TypeOperationSync.creation);
  });

  testWidgets('un nom déjà pris est refusé SOUS le champ, la fenêtre reste '
      'ouverte', (tester) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('param-canal-ajouter')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('param-canal-nom')),
      'whatsapp',
    );
    await tester.tap(find.byKey(const Key('param-canal-valider')));
    await tester.pumpAndSettle();
    expect(
      find.text(MessagesCanaux.nomDejaUtilise('whatsapp')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('param-modale-canal')), findsOneWidget);
    expect(await file(), isEmpty);

    await tester.enterText(find.byKey(const Key('param-canal-nom')), '  ');
    await tester.tap(find.byKey(const Key('param-canal-valider')));
    await tester.pumpAndSettle();
    expect(find.text(MessagesCanaux.nomRequis), findsOneWidget);
  });

  testWidgets('« Renommer » reprend le nom, l’aide dit que le passé n’est '
      'pas réécrit', (tester) async {
    await monter(tester);
    final tous = await CanauxReservationDao(db).tous();
    await tester.tap(find.byKey(Key('param-canal-renommer-${tous[0].code}')));
    await tester.pumpAndSettle();
    expect(find.text('Renommer le canal'), findsOneWidget);
    expect(
      find.textContaining('renommer ne réécrit pas le passé'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const Key('param-canal-nom')),
      'Comptoir',
    );
    await tester.tap(find.byKey(const Key('param-canal-valider')));
    await tester.pumpAndSettle();
    expect(find.text('Comptoir'), findsOneWidget);
    expect(find.text('Physique'), findsNothing);
  });

  testWidgets('désactiver un canal SANS réservation bascule d’un geste, puis '
      '« Réactiver »', (tester) async {
    await monter(tester);
    final tous = await CanauxReservationDao(db).tous();
    await tester.tap(find.byKey(Key('param-canal-basculer-${tous[5].code}')));
    await tester.pumpAndSettle();
    expect(find.text('désactivé'), findsOneWidget);
    expect(find.text('Réactiver'), findsOneWidget);
    expect(find.text(MessagesCanaux.bascule), findsOneWidget);

    await tester.tap(find.byKey(Key('param-canal-basculer-${tous[5].code}')));
    await tester.pumpAndSettle();
    expect(find.text('désactivé'), findsNothing);
    expect((await file()).length, 2);
  });

  testWidgets('désactiver un canal EMPLOYÉ demande confirmation, avec le '
      'compte réel de réservations', (tester) async {
    final tous = await CanauxReservationDao(db).tous();
    final client = await creerClient(db);
    await semerReservation(db, id: 'res-1', clientId: client.id);
    await db.customStatement(
      "UPDATE reservations_local SET canal = '${tous[3].code}'",
    );
    await monter(tester);
    expect(find.text('1'), findsOneWidget, reason: 'colonne Réservations');

    await tester.tap(find.byKey(Key('param-canal-basculer-${tous[3].code}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('param-modale-desactivation')), findsOneWidget);
    expect(
      find.text(
        'Désactiver « Booking.com » ? 1 réservation(s) l’emploient. Elles le '
        'conserveront ; il ne sera simplement plus proposé aux nouvelles saisies.',
      ),
      findsOneWidget,
    );
    expect(await file(), isEmpty, reason: 'rien tant qu’on n’a pas confirmé');

    await tester.tap(
      find.byKey(const Key('param-canal-desactivation-annuler')),
    );
    await tester.pumpAndSettle();
    expect(find.text('désactivé'), findsNothing);

    await tester.tap(find.byKey(Key('param-canal-basculer-${tous[3].code}')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('param-canal-desactivation-confirmer')),
    );
    await tester.pumpAndSettle();
    expect(find.text('désactivé'), findsOneWidget);
    expect((await file()).single.type, TypeOperationSync.modification);
  });
}
