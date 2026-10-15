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
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/widgets/onglet_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import '../synchronisation/support/faux_transport.dart';

/// Paramètres → « Synchronisation » (lot F2a) : l'appairage du poste, par
/// l'écran, sur une base FICHIER et un `poste.json` réels — seul le réseau
/// est simulé.
void main() {
  const url = 'https://serveur.essai/api/v1';
  const secret = 'Mdp-Serveur-Jamais-Ecrit-77';

  late Directory dossier;
  late File fichierBase;
  late AppDatabase db;
  late String cheminPoste;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = await Directory.systemTemp.createTemp('tatacora-onglet-sync-');
    fichierBase = File('${dossier.path}/tatacora.sqlite');
    cheminPoste = '${dossier.path}/poste.json';
    db = AppDatabase.surFichier(fichierBase);
    for (final (id, role) in [
      ('u-admin', 'administrateur'),
      ('u-caisse', 'caissier'),
    ]) {
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: id,
              login: id,
              nom: id,
              role: role,
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 9),
              dateMotDePasse: DateTime(2026, 10, 9),
            ),
          );
    }
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  Future<void> monter(
    WidgetTester tester,
    FauxTransport transport, {
    String role = 'administrateur',
  }) async {
    tester.view
      ..physicalSize = const Size(1600, 1800)
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
              utilisateurId: role == 'administrateur' ? 'u-admin' : 'u-caisse',
              login: 'essai',
              nom: 'Essai',
              role: role,
              droits: droits,
            ),
          ),
          transportSynchronisationProvider.overrideWithValue(transport),
          urlServeurSynchronisationProvider.overrideWithValue(url),
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => cheminPoste,
          ),
          nomPosteParDefautProvider.overrideWithValue('PC-COMPTOIR'),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranParametres()),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
  }

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// Attend que [cible] apparaisse (entrées-sorties réelles du fichier).
  Future<void> attendre(WidgetTester tester, Finder cible) async {
    for (var i = 0; i < 200 && cible.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
    }
    expect(cible, findsWidgets);
  }

  Future<void> ouvrirOnglet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('param-onglet-synchronisation')));
    await laisserTourner(tester);
  }

  Future<void> saisirEtAppairer(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('sync-identifiant')), 'gerant');
    await tester.enterText(find.byKey(const Key('sync-mot-de-passe')), secret);
    await tester.tap(find.byKey(const Key('sync-appairer')));
    await laisserTourner(tester);
  }

  FauxTransport serveur({int statutLogin = 200}) => FauxTransport((r) {
    if (r.url.path.endsWith('/login')) {
      return statutLogin == 200
          ? const ReponseHttp(
              statut: 200,
              corps: {
                'token': '21|jeton-ecran',
                'utilisateur': {'login': 'gerant'},
              },
            )
          : ReponseHttp(
              statut: statutLogin,
              corps: const {'message': 'CORPS-BRUT-DU-SERVEUR'},
            );
    }
    if (r.url.path.endsWith('/utilisateur')) {
      return const ReponseHttp(statut: 200, corps: {'login': 'gerant'});
    }
    return const ReponseHttp(statut: 200, corps: {});
  });

  testWidgets('l’onglet n’existe que pour un Administrateur', (tester) async {
    await monter(tester, serveur(), role: 'caissier');
    expect(find.byKey(const Key('param-onglet-synchronisation')), findsNothing);
    expect(find.byKey(const Key('param-onglet-activation')), findsOneWidget);
  });

  testWidgets('appairer par l’écran : le jeton dans poste.json, le mot de '
      'passe NI dans le fichier NI dans la base, l’état affiché', (
    tester,
  ) async {
    final t = serveur();
    await monter(tester, t);
    await ouvrirOnglet(tester);
    expect(find.text(TextesOngletSynchronisation.nonAppaire), findsOneWidget);
    // Le nom Windows du poste est proposé.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-nom-poste')))
          .controller!
          .text,
      'PC-COMPTOIR',
    );

    await saisirEtAppairer(tester);

    expect(
      find.text('Poste « PC-COMPTOIR » appairé (compte « gerant »).'),
      findsOneWidget,
    );
    expect(t.requetes.single.corps!['mot_de_passe'], secret);
    final brut = await tester.runAsync(() => File(cheminPoste).readAsString());
    final contenu = jsonDecode(brut!) as Map<String, Object?>;
    expect(contenu['jeton_api'], '21|jeton-ecran');
    expect(contenu['poste_id'], 'PC-COMPTOIR');
    expect(contenu['serveur'], url);
    expect(brut, isNot(contains(secret)));
    // Le champ est vidé après le succès.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('sync-mot-de-passe')))
          .controller!
          .text,
      isEmpty,
    );
    await attendre(
      tester,
      find.textContaining('Appairé à $url — poste « PC-COMPTOIR »'),
    );

    // La base, octet par octet (WAL compris) : le mot de passe n'y est pas.
    await tester.runAsync(() async {
      await db.customStatement('PRAGMA wal_checkpoint(FULL)');
      final octetsSecret = utf8.encode(secret);
      for (final f in dossier.listSync().whereType<File>()) {
        final octets = await f.readAsBytes();
        expect(
          _contient(octets, octetsSecret),
          isFalse,
          reason: '${f.path} contient le mot de passe',
        );
      }
    });
    // La sonde n'est pas vide : elle TROUVE ce qui est écrit.
    final jeton = await tester.runAsync(
      () async => _contient(
        await File(cheminPoste).readAsBytes(),
        utf8.encode('21|jeton-ecran'),
      ),
    );
    expect(jeton, isTrue);
  });

  testWidgets('identifiants refusés (401) : la phrase française, jamais le '
      'corps du serveur ; rien n’est écrit', (tester) async {
    await monter(tester, serveur(statutLogin: 401));
    await ouvrirOnglet(tester);
    await saisirEtAppairer(tester);
    expect(find.text(TextesAppairage.identifiantsRefuses), findsOneWidget);
    expect(find.textContaining('CORPS-BRUT'), findsNothing);
    expect(File(cheminPoste).existsSync(), isFalse);
  });

  testWidgets('tester, synchroniser, dissocier', (tester) async {
    final t = serveur();
    await monter(tester, t);
    await ouvrirOnglet(tester);
    await saisirEtAppairer(tester);
    await attendre(tester, find.byKey(const Key('sync-tester')));

    await tester.tap(find.byKey(const Key('sync-tester')));
    await laisserTourner(tester);
    expect(
      find.text(TextesAppairage.connexionEtablie('gerant')),
      findsOneWidget,
    );
    expect(t.requetes.last.jeton, '21|jeton-ecran');

    // File vide : « Synchroniser maintenant » n'émet aucune requête.
    final avant = t.requetes.length;
    await tester.tap(find.byKey(const Key('sync-maintenant')));
    await laisserTourner(tester);
    expect(find.textContaining('Synchronisation à jour.'), findsOneWidget);
    expect(t.requetes.length, avant);

    await tester.ensureVisible(find.byKey(const Key('sync-dissocier')));
    await tester.tap(find.byKey(const Key('sync-dissocier')));
    await laisserTourner(tester);
    expect(find.text(TextesAppairage.dissocie), findsOneWidget);
    expect(t.requetes.last.url.path, endsWith('/logout'));
    expect(find.text(TextesOngletSynchronisation.nonAppaire), findsOneWidget);
    expect(find.byKey(const Key('sync-dissocier')), findsNothing);
  });
}

bool _contient(List<int> botte, List<int> aiguille) {
  outer:
  for (var i = 0; i + aiguille.length <= botte.length; i++) {
    for (var j = 0; j < aiguille.length; j++) {
      if (botte[i + j] != aiguille[j]) continue outer;
    }
    return true;
  }
  return false;
}
