@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/auth/domain/session_repository.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';

/// « Mon profil » — le changement de mot de passe (14/10/2026), réplique
/// locale de `MonProfil::changerMotDePasse()`. Les messages sont relus dans
/// `lang/fr/pwa.php` par PHP ; la preuve d'un changement est la CONNEXION
/// par `SessionRepositoryLocal`, jamais une colonne relue.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// `pwa.profil.mdp_*` du serveur.
  late final Map<String, String> vue;

  setUpAll(() async {
    // La VRAIE police de l'application : la police d'essai (Ahem) donne à
    // chaque glyphe un cadratin entier et ferait déborder le pied de la
    // modale, qu'Inter laisse tenir — c'est Inter que le poste affiche.
    final inter = File('assets/fonts/Inter.ttf');
    expect(inter.existsSync(), isTrue, reason: 'police Inter introuvable');
    await (FontLoader(
          'Inter',
        )..addFont(Future.value(ByteData.view(inter.readAsBytesSync().buffer))))
        .load();

    final lang = File('../tatacora-api/lang/fr/pwa.php').absolute.path;
    final r = await Process.run('php', [
      '-r',
      r'$t = require $argv[1]; echo json_encode($t["profil"]);',
      lang,
    ], stdoutEncoding: utf8);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    vue = (jsonDecode(r.stdout as String) as Map).map(
      (k, v) => MapEntry('$k', '$v'),
    );
    for (final cle in [
      'mdp_note',
      'mdp_ancien_invalide',
      'mdp_identique',
      'mdp_confirmation_invalide',
      'mdp_regle',
    ]) {
      expect(vue[cle], isNotNull, reason: cle);
    }
  });

  late AppDatabase db;
  late SessionRepositoryLocal depot;
  const actuel = 'comptoir2026';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.enMemoire();
    depot = SessionRepositoryLocal(db);
    await depot.creerCompte(
      login: 'j.kora',
      nom: 'KORA Jean',
      motDePasse: actuel,
      role: 'receptionniste',
      droits: const {'M1': 'C'},
    );
  });
  tearDown(() => db.close());

  Future<bool> seConnecte(String mdp) async {
    try {
      await depot.connecter('j.kora', mdp);
      return true;
    } on EchecConnexion {
      return false;
    }
  }

  Future<String> refus(Future<void> geste) async {
    try {
      await geste;
    } on EchecConnexion catch (e) {
      return e.message;
    }
    fail('aucun refus');
  }

  group('SessionRepositoryLocal.changerMotDePasse', () {
    test('ancien FAUX : refusé (message de la vue), rien ne change', () async {
      expect(
        await refus(
          depot.changerMotDePasse(
            login: 'j.kora',
            ancien: 'mauvais123',
            nouveau: 'nouveau2026',
          ),
        ),
        vue['mdp_ancien_invalide'],
      );
      expect(await seConnecte(actuel), isTrue);
      expect(await seConnecte('nouveau2026'), isFalse);
    });

    test('moins de 8 caractères, ou identique à l’ancien : refusé', () async {
      expect(
        await refus(
          depot.changerMotDePasse(
            login: 'j.kora',
            ancien: actuel,
            nouveau: 'court',
          ),
        ),
        'Le mot de passe doit compter au moins 8 caractères.',
      );
      expect(
        await refus(
          depot.changerMotDePasse(
            login: 'j.kora',
            ancien: actuel,
            nouveau: actuel,
          ),
        ),
        vue['mdp_identique'],
      );
      expect(await seConnecte(actuel), isTrue);
    });

    test('réussi : le NOUVEAU ouvre, l’ANCIEN n’ouvre plus ; un compte '
        'désactivé ne change rien', () async {
      await depot.changerMotDePasse(
        login: 'j.kora',
        ancien: actuel,
        nouveau: 'nouveau2026',
      );
      expect(await seConnecte('nouveau2026'), isTrue);
      expect(await seConnecte(actuel), isFalse);

      await (db.update(db.utilisateursLocal)
            ..where((u) => u.login.equals('j.kora')))
          .write(const UtilisateursLocalCompanion(actif: Value(false)));
      expect(
        await refus(
          depot.changerMotDePasse(
            login: 'j.kora',
            ancien: 'nouveau2026',
            nouveau: 'troisieme26',
          ),
        ),
        vue['mdp_ancien_invalide'],
      );
    });
  });

  group('La modale de « Mon profil »', () {
    Future<void> monter(WidgetTester tester) async {
      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            sessionProvider.overrideWithBuild(
              (ref, notifier) => Session(
                utilisateurId: 'x',
                login: 'j.kora',
                nom: 'KORA Jean',
                role: 'receptionniste',
                droits: GardeAcces.depuisJson(const {'M1': 'C'}),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranMonProfil()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('profil-mdp-ouvrir')));
      await tester.tap(find.byKey(const Key('profil-mdp-ouvrir')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profil-mdp-modale')), findsOneWidget);
    }

    Future<void> saisir(
      WidgetTester tester,
      String ancien,
      String nouveau,
      String confirmation,
    ) async {
      await tester.enterText(
        find.byKey(const Key('profil-mdp-ancien')),
        ancien,
      );
      await tester.enterText(
        find.byKey(const Key('profil-mdp-nouveau')),
        nouveau,
      );
      await tester.enterText(
        find.byKey(const Key('profil-mdp-confirmation')),
        confirmation,
      );
      await tester.tap(find.byKey(const Key('profil-mdp-valider')));
      await tester.pumpAndSettle();
    }

    String champ(WidgetTester tester, String cle) =>
        tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

    testWidgets('ancien FAUX : refusé sous le champ, les TROIS saisies '
        'vidées, la modale reste, rien n’a changé', (tester) async {
      await monter(tester);
      await saisir(tester, 'mauvais123', 'nouveau2026', 'nouveau2026');
      expect(find.text(vue['mdp_ancien_invalide']!), findsOneWidget);
      expect(champ(tester, 'profil-mdp-ancien'), isEmpty);
      expect(champ(tester, 'profil-mdp-nouveau'), isEmpty);
      expect(champ(tester, 'profil-mdp-confirmation'), isEmpty);
      expect(find.byKey(const Key('profil-mdp-modale')), findsOneWidget);
      expect(await tester.runAsync(() => seConnecte(actuel)), isTrue);
    });

    testWidgets('moins de 8, confirmation différente, identique à l’ancien : '
        'chacun refusé avec le mot de la vue', (tester) async {
      await monter(tester);
      await saisir(tester, actuel, 'court', 'court');
      expect(
        find.text(vue['mdp_regle']!),
        findsNWidgets(2),
        reason:
            'aide '
            'permanente + erreur',
      );

      await saisir(tester, actuel, 'nouveau2026', 'nouveau2027');
      expect(find.text(vue['mdp_confirmation_invalide']!), findsOneWidget);

      await saisir(tester, actuel, actuel, actuel);
      expect(find.text(vue['mdp_identique']!), findsOneWidget);
      expect(find.byKey(const Key('profil-mdp-modale')), findsOneWidget);
      expect(await tester.runAsync(() => seConnecte(actuel)), isTrue);
    });

    testWidgets('réussi : la modale se ferme, toast ; le nouveau ouvre, '
        'l’ancien non', (tester) async {
      await monter(tester);
      await saisir(tester, actuel, 'nouveau2026', 'nouveau2026');
      expect(find.byKey(const Key('profil-mdp-modale')), findsNothing);
      expect(find.byKey(const Key('profil-mdp-mis-a-jour')), findsOneWidget);
      expect(await tester.runAsync(() => seConnecte('nouveau2026')), isTrue);
      expect(await tester.runAsync(() => seConnecte(actuel)), isFalse);
    });

    testWidgets('la modale NE dit PLUS que la vérification a lieu « côté '
        'serveur » (phrase de la vue, relue) : elle dit la vraie', (
      tester,
    ) async {
      await monter(tester);
      final textes = [
        for (final w in tester.allWidgets)
          if (w is Text) w.data ?? w.textSpan?.toPlainText() ?? '',
      ];
      final noteVue = vue['mdp_note']!;
      expect(noteVue, contains('serveur'), reason: 'la vue n’a pas changé');
      expect(textes, isNot(contains(noteVue)));
      expect(textes.where((t) => t.contains('côté serveur')), isEmpty);
      expect(textes.where((t) => t.contains('PBKDF2')), isEmpty);
    });
  });
}
