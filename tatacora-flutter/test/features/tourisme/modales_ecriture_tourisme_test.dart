import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/restaurant/presentation/widgets/coquille_modale_restaurant.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/ecran_tourisme.dart';

/// Les gestes d'écriture de l'écran Tourisme du poste, par les boutons
/// « + Prestation » et « + Réservation » : thème « Autre », libellé du prix,
/// guide à ajouter depuis la réservation. Chaque écriture est relue dans la
/// base ET dans la file d'envoi.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db
        .into(db.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
            duree: const Value('Journée'),
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> monter(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 3000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(GardeAcces(const {'M9': 'C'})),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranTourisme()),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester t, String cle, String texte) async {
    await t.enterText(find.byKey(Key(cle)), texte);
    await t.pump();
  }

  Future<void> toucher(WidgetTester t, String cle) async {
    final f = find.byKey(Key(cle));
    await t.ensureVisible(f);
    await t.pumpAndSettle();
    await t.tap(f);
    await t.pumpAndSettle();
  }

  Future<List<String>> operations() async => [
    for (final o in await OperationsSyncDao(db).operations())
      '${o.type.code} ${o.table.nomServeur}',
  ];

  List<String> etiquettes(WidgetTester t) => [
    for (final e in t.widgetList<EtiquetteChampRestaurant>(
      find.byType(EtiquetteChampRestaurant),
    ))
      e.texte,
  ];

  group('« + Prestation »', () {
    testWidgets('le thème « Autre » est offert, enregistré et enfilé', (
      t,
    ) async {
      await monter(t);
      await toucher(t, 'tourisme-onglet-catalogue');
      await toucher(t, 'tourisme-nouvelle-prestation');

      expect(find.text('Nouvelle prestation au catalogue'), findsOneWidget);

      await saisir(t, 'tourisme-prestation-nom', 'Soirée contes');
      await toucher(t, 'tourisme-prestation-theme');
      expect(find.text('Autre'), findsWidgets);
      await t.tap(find.text('Autre').last);
      await t.pumpAndSettle();
      await saisir(t, 'tourisme-prestation-zone', 'Atacora');
      await saisir(t, 'tourisme-prestation-prix', '5000');
      await saisir(t, 'tourisme-prestation-capacite', '20');
      await toucher(t, 'tourisme-prestation-valider');

      final c = await (db.select(
        db.circuitsLocal,
      )..where((x) => x.nom.equals('Soirée contes'))).getSingle();
      expect(c.theme, 'autre');
      expect(await operations(), contains('creation circuits'));
    });

    testWidgets('le prix se nomme « Prix par personne », sans unité', (
      t,
    ) async {
      await monter(t);
      await toucher(t, 'tourisme-onglet-catalogue');
      await toucher(t, 'tourisme-nouvelle-prestation');

      final libelles = etiquettes(t);
      expect(libelles, contains('Prix par personne'));
      expect(libelles.any((l) => l.contains('FCFA')), isFalse);
    });

    testWidgets('l\'édition d\'une prestation garde son thème', (t) async {
      await monter(t);
      await toucher(t, 'tourisme-onglet-catalogue');
      await toucher(t, 'tourisme-editer-cir-1');

      expect(find.text('Éditer la prestation'), findsOneWidget);
      expect(find.text('nature'), findsWidgets);
    });
  });

  group('« + Réservation » — le guide', () {
    testWidgets('sans guide : la phrase de la vue, sans note technique, et un '
        'bouton « Ajouter »', (t) async {
      await monter(t);
      await toucher(t, 'tourisme-nouvelle-reservation');

      expect(
        find.text(
          'Aucun guide au référentiel — une réservation ne peut pas être '
          'prise sans lui.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('NOT NULL'), findsNothing);
      expect(find.textContaining('guide_id'), findsNothing);
      expect(
        find.byKey(const Key('tourisme-resa-guide-ajouter')),
        findsOneWidget,
      );
    });

    testWidgets('le guide ajouté est écrit, enfilé et sélectionné dans la '
        'foulée ; la réservation passe', (t) async {
      await monter(t);
      await toucher(t, 'tourisme-nouvelle-reservation');
      await toucher(t, 'tourisme-resa-guide-ajouter');

      expect(find.text('Ajouter un guide touristique'), findsOneWidget);

      // Le nom et le tarif sont obligatoires.
      await toucher(t, 'tourisme-guide-valider');
      expect(
        find.byKey(const Key('tourisme-modale-ajout-guide-refus')),
        findsOneWidget,
      );

      await saisir(t, 'tourisme-guide-nom', 'KOTO Jean');
      await saisir(t, 'tourisme-guide-certification', 'Guide national');
      await saisir(t, 'tourisme-guide-zone', 'Nord Bénin');
      await saisir(t, 'tourisme-guide-tarif', '20000');
      await toucher(t, 'tourisme-guide-valider');

      // La modale du guide est fermée, celle de la réservation reste ouverte.
      expect(find.text('Ajouter un guide touristique'), findsNothing);
      expect(
        find.byKey(const Key('tourisme-modale-reservation')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('tourisme-aucun-guide')), findsNothing);
      // Sélectionné : le champ le montre.
      expect(
        find.descendant(
          of: find.byKey(const Key('tourisme-resa-guide')),
          matching: find.text('KOTO Jean'),
        ),
        findsOneWidget,
      );

      final g = await db.select(db.guidesLocal).getSingle();
      expect((g.nom, g.zoneCompetence), ('KOTO Jean', 'Nord Bénin'));
      expect(await operations(), contains('creation guides'));

      // On réserve avec ce guide, et le cumul est refusé au dépassement.
      await saisir(t, 'tourisme-resa-nb-personnes', '13');
      await toucher(t, 'tourisme-resa-valider');
      expect(
        find.byKey(const Key('tourisme-modale-reservation-refus')),
        findsOneWidget,
      );
      expect(await db.select(db.reservationsTourLocal).get(), isEmpty);

      await saisir(t, 'tourisme-resa-nb-personnes', '4');
      await toucher(t, 'tourisme-resa-valider');
      final r = await db.select(db.reservationsTourLocal).getSingle();
      expect((r.guideId, r.nbParticipants), (g.id, 4));
      expect(await operations(), contains('creation reservations_tour'));
    });

    testWidgets('un guide déjà au référentiel : le champ est un choix, et '
        '« Ajouter » reste offert', (t) async {
      await db
          .into(db.guidesLocal)
          .insert(GuidesLocalCompanion.insert(id: 'gui-1', nom: 'ADJOVI Paul'));
      await monter(t);
      await toucher(t, 'tourisme-nouvelle-reservation');

      expect(find.byKey(const Key('tourisme-resa-guide')), findsOneWidget);
      expect(
        find.byKey(const Key('tourisme-resa-guide-ajouter')),
        findsOneWidget,
      );
    });

    testWidgets('un homonyme est refusé dans la modale du guide', (t) async {
      await db
          .into(db.guidesLocal)
          .insert(GuidesLocalCompanion.insert(id: 'gui-1', nom: 'ADJOVI Paul'));
      await monter(t);
      await toucher(t, 'tourisme-nouvelle-reservation');
      await toucher(t, 'tourisme-resa-guide-ajouter');
      await saisir(t, 'tourisme-guide-nom', 'adjovi paul');
      await saisir(t, 'tourisme-guide-tarif', '1000');
      await toucher(t, 'tourisme-guide-valider');

      expect(find.textContaining('existe déjà'), findsOneWidget);
      expect(await db.select(db.guidesLocal).get(), hasLength(1));
    });
  });
}
