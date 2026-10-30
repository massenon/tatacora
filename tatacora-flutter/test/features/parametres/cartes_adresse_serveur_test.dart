import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/cartes_adresse_serveur.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/onglet_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/frequence_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

import '../synchronisation/support/faux_transport.dart';

/// Les cartes « Adresse du serveur » et « Synchronisation automatique »
/// (29/10/2026), par l'écran, sur une base FICHIER et un `poste.json` réels —
/// seul le réseau est simulé.
void main() {
  const urlBuild = 'https://serveur.essai/api/v1';
  const jeton = '21|jeton-secret-ecran';

  late Directory dossier;
  late AppDatabase db;
  late String cheminPoste;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = await Directory.systemTemp.createTemp('tatacora-cartes-adresse-');
    cheminPoste = '${dossier.path}/poste.json';
    db = AppDatabase.surFichier(File('${dossier.path}/tatacora.sqlite'));
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  // Synchrone : une écriture asynchrone ne se termine pas sous l'horloge
  // simulée d'un testWidgets.
  void poser(Map<String, Object?> contenu) =>
      File(cheminPoste).writeAsStringSync(jsonEncode(contenu));

  Future<Map<String, Object?>> fichier() async =>
      jsonDecode(await File(cheminPoste).readAsString())
          as Map<String, Object?>;

  Future<void> appairer() =>
      EcrivainConfigurationPoste(
        chemin: () async => cheminPoste,
      ).enregistrerAppairage(
        AppairagePoste(
          posteId: 'PC-1',
          jetonApi: jeton,
          serveur: urlBuild,
          appaireLe: DateTime.utc(2026, 10, 15),
          compte: 'gerant',
        ),
      );

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  Future<void> monter(
    WidgetTester tester,
    FauxTransport transport, {
    String role = 'administrateur',
    double largeur = 1000,
    bool onglet = true,
  }) async {
    tester.view
      ..physicalSize = Size(largeur, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces({'PARAM': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild(
            (ref, n) => Session(
              utilisateurId: 'u-1',
              login: 'admin-essai',
              nom: 'Essai',
              role: role,
              droits: droits,
            ),
          ),
          transportSynchronisationProvider.overrideWithValue(transport),
          urlServeurSynchronisationProvider.overrideWithValue(urlBuild),
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => cheminPoste,
          ),
          nomPosteParDefautProvider.overrideWithValue('PC-1'),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: onglet
                  ? const OngletSynchronisation()
                  : const CartesAdresseServeur(),
            ),
          ),
        ),
      ),
    );
    await laisserTourner(tester);
  }

  Future<void> saisir(WidgetTester tester, String texte) async {
    await tester.enterText(find.byKey(const Key('sync-adresse-champ')), texte);
    await tester.pump();
  }

  Future<void> toucher(WidgetTester tester, String cle) async {
    final cible = find.byKey(Key(cle));
    await tester.ensureVisible(cible);
    await tester.pump();
    await tester.tap(cible);
    await laisserTourner(tester);
  }

  FauxTransport serveur() =>
      FauxTransport((_) => const ReponseHttp(statut: 200, corps: null));

  String champ(WidgetTester tester) => tester
      .widget<TextField>(find.byKey(const Key('sync-adresse-champ')))
      .controller!
      .text;

  testWidgets('préremplissage : l’adresse du build, « Actuelle : », l’aide', (
    tester,
  ) async {
    await monter(tester, serveur());
    expect(champ(tester), 'https://serveur.essai');
    expect(find.text('Actuelle : https://serveur.essai'), findsOneWidget);
    expect(find.text('Adresse de l’espace web LogiReStock.'), findsOneWidget);
    expect(find.text('ADRESSE DU SERVEUR'), findsOneWidget);
    expect(find.text('SYNCHRONISATION AUTOMATIQUE'), findsOneWidget);
    expect(find.text('Enregistrer'), findsOneWidget);
    expect(find.text('Tester la connexion'), findsWidgets);
  });

  testWidgets('préremplissage : l’adresse déjà choisie dans poste.json', (
    tester,
  ) async {
    poser({
      'serveur': 'https://choisi.essai/api/v1',
      'serveur_modifie_le': '2026-10-29T08:00:00.000Z',
    });
    await monter(tester, serveur());
    expect(champ(tester), 'https://choisi.essai');
    expect(find.text('Actuelle : https://choisi.essai'), findsOneWidget);
  });

  testWidgets('enregistrer : message, poste.json, journal — sans réseau', (
    tester,
  ) async {
    poser({'smtp_mot_de_passe': 'smtp-123', 'synchronisation_activee': false});
    final t = serveur();
    await monter(tester, t);
    await saisir(tester, '  https://nouveau.essai/api/  ');
    await toucher(tester, 'sync-adresse-enregistrer');

    expect(
      find.text('Adresse du serveur enregistrée : https://nouveau.essai.'),
      findsOneWidget,
    );
    expect(find.text('Actuelle : https://nouveau.essai'), findsOneWidget);
    expect(champ(tester), 'https://nouveau.essai');
    final f = await tester.runAsync(fichier);
    expect(f!['serveur'], 'https://nouveau.essai/api/v1');
    expect(f['smtp_mot_de_passe'], 'smtp-123');
    expect(f['synchronisation_activee'], isFalse);
    expect(t.requetes, isEmpty, reason: 'enregistrer ne touche pas le réseau');
    final lignes = await tester.runAsync(
      () => db.select(db.journalSecuriteLocal).get(),
    );
    expect(lignes, hasLength(1));
    expect(lignes!.single.action, 'adresse_serveur_modifiee');
    expect(lignes.single.auteurLogin, 'admin-essai');
    expect(
      lignes.single.cibleLogin,
      'https://serveur.essai → https://nouveau.essai',
    );
  });

  testWidgets('adresse invalide : phrase française, rien d’écrit', (
    tester,
  ) async {
    await monter(tester, serveur());
    for (final (saisie, phrase) in [
      ('', 'Saisissez l’adresse du serveur.'),
      ('logirestock.com', 'L’adresse doit commencer par http:// ou https://'),
      ('http://logirestock.com', 'L’adresse doit commencer par https://'),
      ('https://a b.com', 'ne doit contenir aucun espace'),
      ('https://logirestock.com/app', 'ne doit pas contenir de chemin'),
    ]) {
      await saisir(tester, saisie);
      await toucher(tester, 'sync-adresse-enregistrer');
      final texte = tester
          .widget<Text>(find.byKey(const Key('sync-adresse-message')))
          .data!;
      expect(texte, contains(phrase), reason: saisie);
    }
    expect(File(cheminPoste).existsSync(), isFalse);
    expect(
      await tester.runAsync(() => db.select(db.journalSecuriteLocal).get()),
      isEmpty,
    );
  });

  testWidgets('même adresse : le dit, n’écrit rien', (tester) async {
    await monter(tester, serveur());
    await toucher(tester, 'sync-adresse-enregistrer');
    expect(find.text('Cette adresse est déjà celle du poste.'), findsOneWidget);
    expect(File(cheminPoste).existsSync(), isFalse);
  });

  group('poste appairé : le jeton de l’ancien serveur', () {
    testWidgets('avertissement, « Garder le jeton »', (tester) async {
      await tester.runAsync(appairer);
      await monter(tester, serveur());
      await saisir(tester, 'https://nouveau.essai');
      await toucher(tester, 'sync-adresse-enregistrer');

      expect(find.text('Le poste est déjà appairé'), findsOneWidget);
      expect(
        find.textContaining('appartient à l’ancien serveur'),
        findsOneWidget,
      );
      // Rien n'est écrit avant le choix.
      expect((await tester.runAsync(fichier))!['serveur'], urlBuild);

      await toucher(tester, 'sync-adresse-garder-jeton');
      final f = (await tester.runAsync(fichier))!;
      expect(f['serveur'], 'https://nouveau.essai/api/v1');
      expect(f['jeton_api'], jeton);
      expect(
        find.textContaining('Le jeton d’appairage est conservé'),
        findsOneWidget,
      );
    });

    testWidgets('« Annuler » : rien n’est enregistré', (tester) async {
      await tester.runAsync(appairer);
      await monter(tester, serveur());
      await saisir(tester, 'https://nouveau.essai');
      await toucher(tester, 'sync-adresse-enregistrer');
      await toucher(tester, 'sync-adresse-annuler');
      expect((await tester.runAsync(fichier))!['serveur'], urlBuild);
      expect(
        await tester.runAsync(() => db.select(db.journalSecuriteLocal).get()),
        isEmpty,
      );
    });

    testWidgets('« Effacer le jeton et réappairer » demande une confirmation', (
      tester,
    ) async {
      await tester.runAsync(appairer);
      await monter(tester, serveur());
      await saisir(tester, 'https://nouveau.essai');
      await toucher(tester, 'sync-adresse-enregistrer');
      await toucher(tester, 'sync-adresse-effacer-jeton');

      expect(find.text('Effacer le jeton ?'), findsOneWidget);
      expect((await tester.runAsync(fichier))!['jeton_api'], jeton);

      // Refuser la confirmation : le jeton reste, l'adresse ne change pas.
      await toucher(tester, 'sync-adresse-effacer-annuler');
      final intact = (await tester.runAsync(fichier))!;
      expect(intact['jeton_api'], jeton);
      expect(intact['serveur'], urlBuild);

      await toucher(tester, 'sync-adresse-enregistrer');
      await toucher(tester, 'sync-adresse-effacer-jeton');
      await toucher(tester, 'sync-adresse-effacer-confirmer');
      final f = (await tester.runAsync(fichier))!;
      expect(f.containsKey('jeton_api'), isFalse);
      expect(f['serveur'], 'https://nouveau.essai/api/v1');
      expect(find.textContaining('Le jeton a été effacé'), findsOneWidget);
      // Le poste n'est plus appairé : le formulaire propose d'appairer.
      expect(find.text('Appairer le poste'), findsOneWidget);
    });

    testWidgets('le jeton n’est ni affiché ni journalisé', (tester) async {
      await tester.runAsync(appairer);
      await monter(tester, serveur());
      await saisir(tester, 'https://nouveau.essai');
      await toucher(tester, 'sync-adresse-enregistrer');
      expect(find.textContaining('jeton-secret'), findsNothing);
      await toucher(tester, 'sync-adresse-garder-jeton');
      expect(find.textContaining('jeton-secret'), findsNothing);
      final lignes = await tester.runAsync(
        () => db.select(db.journalSecuriteLocal).get(),
      );
      for (final l in lignes!) {
        expect(jsonEncode(l.toJson()), isNot(contains('jeton-secret')));
      }
    });
  });

  group('« Tester la connexion » de l’adresse', () {
    testWidgets('GET <racine>/up, rien d’écrit, rien tracé', (tester) async {
      final t = serveur();
      await monter(tester, t);
      await saisir(tester, 'https://autre.essai/api');
      await toucher(tester, 'sync-adresse-tester');
      expect(t.requetes.single.url.toString(), 'https://autre.essai/up');
      expect(t.requetes.single.jeton, isNull);
      expect(
        find.textContaining('Le serveur répond à cette adresse'),
        findsOneWidget,
      );
      expect(File(cheminPoste).existsSync(), isFalse);
      expect(
        await tester.runAsync(() => db.select(db.journalSecuriteLocal).get()),
        isEmpty,
      );
    });

    testWidgets('serveur injoignable : la phrase le dit', (tester) async {
      await monter(tester, FauxTransport((_) => const ServeurInjoignable('x')));
      await toucher(tester, 'sync-adresse-tester');
      expect(find.textContaining('Serveur injoignable'), findsOneWidget);
    });
  });

  group('synchronisation automatique', () {
    testWidgets('liste les options supportées, 5 minutes par défaut', (
      tester,
    ) async {
      await monter(tester, serveur());
      expect(find.text('Toutes les 5 minutes (défaut)'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sync-frequence')));
      await tester.pumpAndSettle();
      for (final f in FrequenceSynchronisation.values) {
        expect(find.text(f.libelle), findsWidgets, reason: f.libelle);
      }
      expect(find.text('Manuelle seulement'), findsWidgets);
    });

    testWidgets('choisir une fréquence l’écrit dans poste.json', (
      tester,
    ) async {
      poser({'smtp_mot_de_passe': 'smtp-123'});
      await monter(tester, serveur());
      await tester.ensureVisible(find.byKey(const Key('sync-frequence')));
      await tester.tap(find.byKey(const Key('sync-frequence')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Toutes les 15 minutes').last);
      await laisserTourner(tester);
      final f = (await tester.runAsync(fichier))!;
      expect(f['synchronisation_frequence_minutes'], 15);
      expect(f['smtp_mot_de_passe'], 'smtp-123');
      expect(
        find.text('Fréquence enregistrée : Toutes les 15 minutes'),
        findsOneWidget,
      );
    });

    testWidgets('l’aide dit ce que le poste fait réellement', (tester) async {
      await monter(tester, serveur());
      final aide = tester
          .widget<Text>(find.byKey(const Key('sync-frequence-aide')))
          .data!;
      expect(aide, startsWith('Toutes les 5 minutes par défaut.'));
      expect(aide, contains('clôture de caisse'));
      expect(
        aide,
        contains('30 s, 2 min, 5 min, 15 min, puis toutes les heures'),
      );
      expect(aide, contains('réappairage'));
    });
  });

  group('droits', () {
    testWidgets('un non-administrateur ne voit aucune des deux cartes', (
      tester,
    ) async {
      await monter(tester, serveur(), role: 'caissier');
      expect(find.byKey(const Key('sync-carte-adresse')), findsNothing);
      expect(find.byKey(const Key('sync-carte-frequence')), findsNothing);
      expect(find.byKey(const Key('sync-adresse-enregistrer')), findsNothing);
      expect(find.byKey(const Key('sync-reserve')), findsOneWidget);
    });

    testWidgets('les cartes seules refusent aussi un non-administrateur', (
      tester,
    ) async {
      await monter(tester, serveur(), role: 'caissier', onglet: false);
      expect(find.byKey(const Key('sync-carte-adresse')), findsNothing);
    });
  });

  group('aucun débordement, 320 → large', () {
    for (final largeur in [320.0, 360.0, 480.0, 768.0, 1024.0, 1600.0]) {
      testWidgets('largeur $largeur', (tester) async {
        await tester.runAsync(appairer);
        await monter(tester, serveur(), largeur: largeur);
        // Les deux messages les plus longs sont affichés.
        await saisir(tester, 'https://nouveau.essai');
        await toucher(tester, 'sync-adresse-enregistrer');
        expect(
          find.byKey(const Key('sync-adresse-dialogue-jeton')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull, reason: 'dialogue $largeur');
        await toucher(tester, 'sync-adresse-garder-jeton');
        await tester.ensureVisible(
          find.byKey(const Key('sync-frequence-aide')),
        );
        expect(tester.takeException(), isNull, reason: 'cartes $largeur');
        await tester.tap(find.byKey(const Key('sync-frequence')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'liste $largeur');
      });
    }
  });
}
