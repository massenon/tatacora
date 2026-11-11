import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/ecran_vehicules.dart';
import 'package:tatacora_flutter/features/vehicules/presentation/providers_vehicules.dart';

/// Les MODALES de M8 qui portent les champs du web ajoutés à la v41 (27/10/2026),
/// montées pour de vrai, contre une vraie base : « Places », « Année »,
/// « Transmission » du véhicule, « Remise », « Acompte » et « Reste à payer » du
/// contrat. Les bornes et les phrases sont éprouvées contre le VRAI serveur par
/// `champs_location_contre_serveur_test.dart` ; ici, ce que l'ÉCRAN en fait — la
/// phrase sous le bon champ, l'aperçu qui suit la saisie, la valeur qui arrive en
/// base et dans la file d'envoi.
void main() {
  late AppDatabase db;
  late VehiculeDao dao;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = VehiculeDao(db);
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
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
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson(const {'M8': 'C', 'M3': 'C'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranVehicules()),
        ),
      ),
    );
    await tester.pump();
    // L'horloge est posée, pas lue : trois jours, du 14 au 17 septembre 2026.
    ProviderScope.containerOf(
        tester.element(find.byType(EcranVehicules)),
      ).read(periodeVehiculesProvider.notifier)
      ..definirDebut('2026-09-14')
      ..definirFin('2026-09-17');
    await tester.pumpAndSettle();
  }

  Future<void> laisserEcrire(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 150)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, String cle, String texte) async {
    await tester.enterText(find.byKey(Key(cle)), texte);
    await tester.pump();
  }

  String texteDe(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  /// Les espaces (insécables compris) ne comptent pas dans un montant formaté.
  String compact(String s) => s.replaceAll(RegExp(r'\s'), '');

  Future<List<OperationSync>> file() =>
      OperationsSyncDao(db).operations(table: TableSynchronisee.vehicules);

  group('Modale « Nouveau véhicule » : Places, Année, Transmission', () {
    Future<void> ouvrir(WidgetTester tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('vehicules-nouveau-vehicule')));
      await tester.pumpAndSettle();
    }

    Future<void> remplirBase(WidgetTester tester) async {
      await saisir(tester, 'modale-vehicule-immatriculation', 'AB 1234 RB');
      await saisir(tester, 'modale-vehicule-tarif', '25000');
    }

    Future<void> enregistrer(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('modale-vehicule-enregistrer')));
      await laisserEcrire(tester);
    }

    testWidgets('les trois champs de la vue sont là, aux mots de la vue : '
        'Places et Année obligatoires, Transmission facultative', (
      tester,
    ) async {
      await ouvrir(tester);
      for (final cle in ['capacite', 'annee', 'transmission']) {
        expect(find.byKey(Key('modale-vehicule-$cle')), findsOneWidget);
      }
      expect(
        find.text('Places *', findRichText: true),
        findsOneWidget,
        reason: 'obligatoire',
      );
      expect(find.text('Année *', findRichText: true), findsOneWidget);
      expect(find.text('Transmission', findRichText: true), findsOneWidget);
      // Rien n'est pré-rempli : ni « 5 places », ni l'année courante.
      for (final cle in ['capacite', 'annee', 'transmission']) {
        expect(
          tester
              .widget<TextField>(find.byKey(Key('modale-vehicule-$cle')))
              .controller!
              .text,
          isEmpty,
          reason: cle,
        );
      }
    });

    testWidgets('Places et Année vides : la phrase du serveur sous CHAQUE '
        'champ, rien n’est écrit', (tester) async {
      await ouvrir(tester);
      await remplirBase(tester);
      await enregistrer(tester);

      expect(find.text('Le champ Places est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ Année est obligatoire.'), findsOneWidget);
      expect(find.byKey(const Key('modale-vehicule')), findsOneWidget);
      expect(await dao.parc(), isEmpty);
      expect(await file(), isEmpty);
    });

    testWidgets('les bornes : Places 1 à 99, Année 1950 à l’an prochain, '
        'Transmission 255 caractères', (tester) async {
      await ouvrir(tester);
      await remplirBase(tester);
      final anProchain = DateTime.now().year + 1;

      Future<void> essayer(
        String places,
        String annee,
        String transmission,
        List<String> phrases,
      ) async {
        await saisir(tester, 'modale-vehicule-capacite', places);
        await saisir(tester, 'modale-vehicule-annee', annee);
        await saisir(tester, 'modale-vehicule-transmission', transmission);
        await enregistrer(tester);
        for (final p in phrases) {
          expect(find.text(p), findsOneWidget, reason: p);
        }
      }

      await essayer('0', '1949', 'x' * 256, [
        'Le champ Places doit etre au minimum de 1.',
        'Le champ Année doit etre au minimum de 1950.',
        'Le champ Transmission ne peut pas contenir plus de 255 caracteres.',
      ]);
      await essayer('100', '${anProchain + 1}', '', [
        'Le champ Places ne peut pas etre superieur a 99.',
        'Le champ Année ne peut pas etre superieur a $anProchain.',
      ]);
      await essayer('cinq', 'deux mille', '', [
        'Le champ Places doit être un entier.',
        'Le champ Année doit être un entier.',
      ]);
      expect(await dao.parc(), isEmpty, reason: 'aucune saisie hors bornes');
    });

    testWidgets('une saisie valide arrive en base ET dans la création '
        'enfilée', (tester) async {
      await ouvrir(tester);
      await remplirBase(tester);
      await saisir(tester, 'modale-vehicule-capacite', '5');
      await saisir(tester, 'modale-vehicule-annee', '2022');
      await saisir(tester, 'modale-vehicule-transmission', 'Automatique');
      await enregistrer(tester);

      expect(find.byKey(const Key('modale-vehicule')), findsNothing);
      final v = (await dao.parc()).single;
      expect((v.capacite, v.annee, v.transmission), (5, 2022, 'Automatique'));
      final creation = (await file()).single;
      expect(creation.type, TypeOperationSync.creation);
      expect(creation.payload, contains('"annee":2022'));
      expect(creation.payload, contains('"capacite":5'));
      expect(creation.payload, contains('"transmission":"Automatique"'));
    });

    testWidgets('la transmission est FACULTATIVE : vide, le véhicule s’écrit '
        'sans', (tester) async {
      await ouvrir(tester);
      await remplirBase(tester);
      await saisir(tester, 'modale-vehicule-capacite', '7');
      await saisir(tester, 'modale-vehicule-annee', '2019');
      await enregistrer(tester);

      final v = (await dao.parc()).single;
      expect((v.capacite, v.annee), (7, 2019));
      expect(v.transmission, anyOf(isNull, isEmpty));
    });

    testWidgets('l’édition s’ouvre avec les valeurs ENREGISTRÉES ; vider la '
        'transmission l’efface (jamais « inchangée »)', (tester) async {
      final v = await dao.enregistrerVehicule(
        immatriculation: 'CD 5678 RB',
        categorie: CategorieVehicule.quatreQuatre,
        tarifJour: 40000,
        annee: 2021,
        capacite: 7,
        transmission: 'Manuelle',
      );
      await monter(tester);
      await tester.tap(find.byKey(Key('vehicules-editer-${v.id}')));
      await tester.pumpAndSettle();

      String champ(String cle) => tester
          .widget<TextField>(find.byKey(Key('modale-vehicule-$cle')))
          .controller!
          .text;
      expect(
        [champ('capacite'), champ('annee'), champ('transmission')],
        ['7', '2021', 'Manuelle'],
      );

      await saisir(tester, 'modale-vehicule-transmission', '');
      await saisir(tester, 'modale-vehicule-annee', '2020');
      await enregistrer(tester);

      final relu = (await dao.parc()).single;
      expect((relu.annee, relu.capacite), (2020, 7));
      expect(relu.transmission, anyOf(isNull, isEmpty));
      final modification = (await file()).last;
      expect(modification.type, TypeOperationSync.modification);
      expect(modification.payload, contains('"annee":2020'));
    });

    testWidgets('un véhicule d’AVANT la v41 s’ouvre avec Places et Année '
        'VIDES : rien n’est inventé, l’enregistrement les exige', (
      tester,
    ) async {
      final v = await dao.enregistrerVehicule(
        immatriculation: 'EF 9012 RB',
        categorie: CategorieVehicule.voiture,
        tarifJour: 25000,
        annee: 2020,
        capacite: 5,
      );
      await db.customStatement(
        'UPDATE vehicules_local SET annee = NULL, capacite = NULL '
        "WHERE id = '${v.id}'",
      );
      await monter(tester);
      await tester.tap(find.byKey(Key('vehicules-editer-${v.id}')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('modale-vehicule-annee')))
            .controller!
            .text,
        isEmpty,
      );
      await enregistrer(tester);
      expect(find.text('Le champ Places est obligatoire.'), findsOneWidget);
      expect(find.text('Le champ Année est obligatoire.'), findsOneWidget);
    });
  });

  group('Modale « Nouveau contrat de location » : Remise, Acompte, Reste', () {
    late Vehicule voiture;

    setUp(() async {
      // 25 000 F par jour x 3 jours (14 -> 17 septembre) = 75 000 F.
      voiture = await dao.enregistrerVehicule(
        immatriculation: 'AB 1234 RB',
        categorie: CategorieVehicule.voiture,
        tarifJour: 25000,
        annee: 2022,
        capacite: 5,
      );
    });

    Future<void> ouvrir(WidgetTester tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('vehicules-nouveau-contrat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-contrat-vehicule')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('AB 1234 RB').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-contrat-client')));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('KORA').last);
      await tester.pumpAndSettle();
      await saisir(tester, 'modale-contrat-piece', 'CNI-123');
      await saisir(tester, 'modale-contrat-permis', 'P-9');
    }

    Future<void> etablir(WidgetTester tester) async {
      await tester.ensureVisible(
        find.byKey(const Key('modale-contrat-etablir')),
      );
      await tester.tap(find.byKey(const Key('modale-contrat-etablir')));
      await laisserEcrire(tester);
    }

    testWidgets('l’aperçu SUIT la saisie : montant brut, remise, acompte, '
        'reste à payer', (tester) async {
      await ouvrir(tester);

      // Sans remise ni acompte : tout reste dû.
      expect(texteDe(tester, 'modale-contrat-apercu-montant'), '75000.00');
      expect(
        compact(texteDe(tester, 'modale-contrat-apercu-reste')),
        '75000FCFA',
      );

      await saisir(tester, 'modale-contrat-remise', '5000');
      await saisir(tester, 'modale-contrat-acompte', '20000');
      expect(
        compact(texteDe(tester, 'modale-contrat-apercu-remise')),
        '−5000FCFA',
      );
      expect(
        compact(texteDe(tester, 'modale-contrat-apercu-acompte')),
        '−20000FCFA',
      );
      // 75 000 - 5 000 - 20 000.
      expect(
        compact(texteDe(tester, 'modale-contrat-apercu-reste')),
        '50000FCFA',
      );

      await saisir(tester, 'modale-contrat-remise', '');
      expect(
        compact(texteDe(tester, 'modale-contrat-apercu-reste')),
        '55000FCFA',
        reason: 'une remise vidée vaut zéro',
      );
    });

    testWidgets('les libellés de la vue : « Remise (FCFA) » et « Acompte reçu '
        '(FCFA) », « Reste à payer »', (tester) async {
      await ouvrir(tester);
      expect(find.text('Remise (FCFA)', findRichText: true), findsOneWidget);
      expect(
        find.text('Acompte reçu (FCFA)', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Reste à payer'), findsOneWidget);
    });

    testWidgets('une remise supérieure au brut : la phrase du DAO sous le '
        'champ, aucun contrat', (tester) async {
      await ouvrir(tester);
      await saisir(tester, 'modale-contrat-remise', '80000');
      await etablir(tester);

      expect(
        find.text(
          'Le champ Remise (FCFA) doit être inférieur ou égal à 75000.00.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modale-contrat')), findsOneWidget);
      expect(await dao.contrats(), isEmpty);
    });

    testWidgets('un acompte supérieur au net (brut - remise) : la phrase sous '
        'l’acompte', (tester) async {
      await ouvrir(tester);
      await saisir(tester, 'modale-contrat-remise', '5000');
      await saisir(tester, 'modale-contrat-acompte', '80000');
      await etablir(tester);

      expect(
        find.text(
          'Le champ Acompte reçu (FCFA) doit être inférieur ou égal à 70000.00.',
        ),
        findsOneWidget,
      );
      expect(await dao.contrats(), isEmpty);
    });

    testWidgets('un montant négatif ou illisible est refusé avant le DAO, '
        'aux phrases du serveur', (tester) async {
      await ouvrir(tester);
      await saisir(tester, 'modale-contrat-remise', '-5');
      await saisir(tester, 'modale-contrat-acompte', 'beaucoup');
      await etablir(tester);

      expect(
        find.text('Le champ Remise (FCFA) doit etre au minimum de 0.'),
        findsOneWidget,
      );
      expect(
        find.text('Le champ Acompte reçu (FCFA) doit être un entier.'),
        findsOneWidget,
      );
      expect(await dao.contrats(), isEmpty);
    });

    testWidgets('un contrat remisé et acompté : montant NET, acompte, reste dû '
        'en base, dans la file, et lisibles dans la liste', (tester) async {
      await ouvrir(tester);
      await saisir(tester, 'modale-contrat-remise', '5000');
      await saisir(tester, 'modale-contrat-acompte', '20000');
      await etablir(tester);

      expect(find.byKey(const Key('modale-contrat')), findsNothing);
      final contrat = (await dao.contrats()).single;
      // Le montant d'un contrat est le NET : 75 000 - 5 000.
      expect(contrat.montant, '70000.00');
      expect(contrat.acompte, '20000.00');
      expect(contrat.remise, '5000.00');
      expect(contrat.immatriculation, voiture.immatriculation);

      final creation = (await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.contratsLocation)).single;
      expect(creation.payload, contains('"remise":5000'));
      expect(creation.payload, contains('"acompte":20000'));

      await tester.tap(find.byKey(const Key('vehicules-onglet-contrats')));
      await tester.pumpAndSettle();
      expect(
        compact(texteDe(tester, 'vehicules-contrat-acompte-${contrat.id}')),
        contains('20000'),
      );
      expect(
        compact(texteDe(tester, 'vehicules-contrat-reste-${contrat.id}')),
        contains('50000'),
      );
    });
  });
}
