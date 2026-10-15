import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/presentation/ecran_clients.dart';

/// La modale **« Nouveau client »** du registre — `m3-clients-creances.html`,
/// balisage en `m3-clients-creances.js` l.609-650.
///
/// ## Ce que ces cas protègent
///
/// **Que l'écran du registre ouvre SA modale, pas celle de la réservation.**
/// Jusqu'au 26/08/2026 il ouvrait `dialogue_nouveau_client.dart`, écrit pour
/// `reservations.html` : le bouton marchait, et les mots affichés — « Ajouter
/// un client », « Nom », « Ajouter le client » — n'étaient ceux d'aucune des
/// deux pages à la fois. L'Article 1 interdit de changer un libellé, même pour
/// un synonyme : les deux modales coexistent, chacune fidèle à sa page.
///
/// **Que RG-18 soit réellement APPELÉE.** `doublonsPotentiels` était écrite et
/// n'avait aucun appelant — ni code, ni test. Une règle écrite n'est pas une
/// règle appliquée (piège 1).
///
/// **Que le doublon avertisse sans bloquer**, comme le maître l'écrit
/// lui-même : deux homonymes existent, et refuser le second ferait saisir
/// « KORA Jean 2 » — le référentiel unique que RG-18 protège serait perdu par
/// le geste censé le protéger.
///
/// **Que « Entreprise » s'écrive `structure` en base.** Deux registres de
/// types cohabitent (PA-116), et les confondre casse la synchronisation.
///
/// **Que le client parte en file.** Client et entrée de file s'écrivent dans
/// la même transaction, et le `statutSync` naît à `en_attente_synchronisation`
/// — le défaut `synchronise` du schéma convient à un client descendu du
/// serveur, jamais à un client saisi au comptoir.
void main() {
  late AppDatabase db;
  late ClientDao clients;

  setUp(() {
    db = AppDatabase.enMemoire();
    clients = ClientDao(db);
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
            GardeAcces.depuisJson(const {'M3': 'C'}),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranClients()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> ouvrir(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('clients-nouveau')));
    await tester.pumpAndSettle();
  }

  Future<void> saisir(
    WidgetTester tester, {
    required String nom,
    required String telephone,
  }) async {
    await tester.enterText(find.byKey(const Key('client-registre-nom')), nom);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('client-registre-telephone')),
      telephone,
    );
    await tester.pumpAndSettle();
  }

  final modale = find.byKey(const Key('modale-client-registre'));
  final creer = find.byKey(const Key('client-registre-creer'));

  /* ================================================================== */
  group('Les mots du maître', () {
    testWidgets('le registre ouvre SA modale, pas celle de la réservation', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      expect(modale, findsOneWidget);
      // Les trois libellés du maître (l.615, l.620, l.646).
      expect(find.text('Nouveau client'), findsOneWidget);
      expect(find.text('Créer le client'), findsOneWidget);
      expect(
        find.byKey(const Key('client-registre-nom')),
        findsOneWidget,
        reason: 'Le champ « Nom / Raison sociale » du registre est absent.',
      );

      // …et surtout AUCUN mot de la modale de la fiche de réservation.
      expect(find.text('Ajouter un client'), findsNothing);
      expect(find.text('Ajouter le client'), findsNothing);
    });

    testWidgets('les champs sont ceux du maître, dans SON ordre', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      // Nom / Raison sociale, puis la rangée Téléphone + Type (l.625-636).
      final nom = tester.getTopLeft(
        find.byKey(const Key('client-registre-nom')),
      );
      final tel = tester.getTopLeft(
        find.byKey(const Key('client-registre-telephone')),
      );
      final type = tester.getTopLeft(
        find.byKey(const Key('client-registre-type')),
      );

      expect(nom.dy, lessThan(tel.dy), reason: 'Le nom vient en premier.');
      expect(
        tel.dy,
        type.dy,
        reason: 'Téléphone et Type sont sur la MÊME rangée au maître (l.625).',
      );
      expect(
        tel.dx,
        lessThan(type.dx),
        reason: 'Le téléphone est la colonne de GAUCHE.',
      );
    });

    testWidgets('sa largeur est celle MESURÉE au maître, pas approchée', (
      tester,
    ) async {
      // `style="max-width:560px"` (l.611). 560 ne vient d'aucune échelle :
      // Tailwind passe de `max-w-lg` (512) à `max-w-xl` (576).
      await monter(tester);
      await ouvrir(tester);

      expect(AppLayout.modaleClientCrm, 560);
      final boite = tester.widget<SizedBox>(
        find.byKey(const Key('client-registre-colonne')),
      );
      expect(boite.width, AppLayout.modaleClientCrm);
    });

    testWidgets('« Ville » est REFUSÉE et nommée, pas silencieusement omise', (
      tester,
    ) async {
      // Aucune colonne `ville` n'existe, ni en local ni au serveur. Offrir le
      // champ collecterait une saisie ignorée à la validation (Article 6).
      await monter(tester);
      await ouvrir(tester);

      expect(
        find.byKey(const Key('client-registre-ville-absente')),
        findsOneWidget,
      );
      expect(find.textContaining('Ville'), findsOneWidget);
    });

    testWidgets('la touche d’ÉCHAPPEMENT ferme la modale (Article 4.6)', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(modale, findsNothing);
      expect(await clients.clients(), isEmpty);
    });
  });

  /* ================================================================== */
  group('RG-18 — la détection de doublon', () {
    testWidgets('un homonyme AVERTIT, il ne bloque pas', (tester) async {
      await clients.creer(
        nom: 'KORA Jean',
        telephone: '97111111',
        type: TypeClientReferentiel.particulier,
      );
      await monter(tester);
      await ouvrir(tester);

      await saisir(tester, nom: 'kora jean', telephone: '90000000');

      // L'avertissement du maître (l.679).
      expect(find.byKey(const Key('client-registre-doublon')), findsOneWidget);
      expect(find.text('Un client existant correspond déjà'), findsOneWidget);

      // Le bouton est désactivé tant que la case n'est pas cochée — mais il
      // reste là : le maître n'interdit pas la création, il la fait confirmer.
      expect(tester.widget<FilledButton>(creer).onPressed, isNull);

      await tester.tap(
        find.byKey(const Key('client-registre-confirmer-doublon')),
      );
      await tester.pumpAndSettle();

      // Le second libellé du maître (l.688).
      expect(find.text('Créer malgré le doublon'), findsOneWidget);
      expect(tester.widget<FilledButton>(creer).onPressed, isNotNull);

      await tester.tap(creer);
      await tester.pumpAndSettle();

      expect(await clients.clients(), hasLength(2));
    });

    testWidgets('sans doublon, le bouton n’est JAMAIS désactivé', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);
      await saisir(tester, nom: 'ADJOVI Paul', telephone: '97222222');

      expect(find.byKey(const Key('client-registre-doublon')), findsNothing);
      expect(find.text('Créer le client'), findsOneWidget);
      expect(tester.widget<FilledButton>(creer).onPressed, isNotNull);
    });

    testWidgets('corriger la saisie REDEMANDE la confirmation', (tester) async {
      // Quelqu'un qui coche puis change le nom aurait sinon une confirmation
      // acquise sur un doublon qu'il n'a jamais relu.
      await clients.creer(
        nom: 'KORA Jean',
        telephone: '97111111',
        type: TypeClientReferentiel.particulier,
      );
      await monter(tester);
      await ouvrir(tester);
      await saisir(tester, nom: 'KORA Jean', telephone: '90000000');

      await tester.tap(
        find.byKey(const Key('client-registre-confirmer-doublon')),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(creer).onPressed, isNotNull);

      // La saisie change, et reste un doublon (le nom est le même).
      await tester.enterText(
        find.byKey(const Key('client-registre-telephone')),
        '90000001',
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<FilledButton>(creer).onPressed,
        isNull,
        reason:
            'La confirmation est restée acquise après une modification de la '
            'saisie.',
      );
    });
  });

  /* ================================================================== */
  group('Ce qui est réellement ENREGISTRÉ', () {
    testWidgets('« Entreprise » s’écrit `structure`, et part en file', (
      tester,
    ) async {
      await monter(tester);
      await ouvrir(tester);
      await saisir(tester, nom: 'Agence Bénin Tour', telephone: '97333333');

      await tester.tap(find.byKey(const Key('client-registre-type')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Entreprise').last);
      await tester.pumpAndSettle();

      await tester.tap(creer);
      await tester.pumpAndSettle();

      final cree = (await clients.clients()).single;
      expect(cree.nom, 'Agence Bénin Tour');
      // ⚠ Les deux registres de types (PA-116) : l'écran dit « Entreprise »,
      // le schéma stocke `structure`.
      expect(cree.type, TypeClientReferentiel.structure);
      expect(cree.type.code, 'structure');

      // Créé au comptoir, donc **enregistré sur ce poste** — et il n'attend
      // rien. La valeur était `en_attente_synchronisation` tant qu'une file
      // existait ; zéro réseau (14/09/2026), plus rien à attendre.
      expect(cree.statutSync, 'local');

      // ⚠ Ce cas vérifiait aussi l'entrée de FILE : sans elle, le client ne
      // partait jamais, et la première réservation qui le référence était
      // rejetée par le serveur sur une clé étrangère (PA-116/PA-127). Il n'y a
      // plus de file, donc plus d'ordre de départ à garantir.
    });

    testWidgets('un nom vide REFUSE, et n’enregistre rien', (tester) async {
      await monter(tester);
      await ouvrir(tester);
      await saisir(tester, nom: '   ', telephone: '97444444');

      await tester.tap(creer);
      await tester.pumpAndSettle();

      expect(modale, findsOneWidget, reason: 'La modale doit rester ouverte.');
      expect(await clients.clients(), isEmpty);
    });

    testWidgets('« Annuler » n’enregistre rien', (tester) async {
      await monter(tester);
      await ouvrir(tester);
      await saisir(tester, nom: 'ADJOVI Paul', telephone: '97222222');

      await tester.tap(find.byKey(const Key('client-registre-annuler')));
      await tester.pumpAndSettle();

      expect(modale, findsNothing);
      expect(await clients.clients(), isEmpty);
    });
  });
}
