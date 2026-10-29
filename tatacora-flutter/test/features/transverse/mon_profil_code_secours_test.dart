@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/mot_de_passe_perdu.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/auth/impression/feuille_code_secours.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_mon_profil.dart';
import 'package:tatacora_flutter/shared_widgets/affichage_secret_unique.dart';

/// « Mon profil → Code de secours » (PO, 29/10/2026, option A) : réservé aux
/// deux rôles d'administration, après confirmation du mot de passe, le code est
/// montré UNE fois (copier, imprimer) et seul son dérivé est stocké. Les anciens
/// comptes (avant la v46) n'ont pas de code : l'administrateur en génère un ici.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<String> copies;
  late List<(String, String)> impressions;
  const motDePasse = 'Admin-Secret-9';

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.enMemoire();
    copies = [];
    impressions = [];
    final depot = SessionRepositoryLocal(db);
    await depot.creerCompte(
      login: 'n.kora',
      nom: 'KORA Noël',
      motDePasse: motDePasse,
      role: 'administrateur',
      droits: const {'M1': 'C', 'ROLES': 'C'},
    );
    await depot.creerCompte(
      login: 'marie',
      nom: 'HOUNSOU Marie',
      motDePasse: motDePasse,
      role: 'receptionniste',
      droits: const {'M1': 'C'},
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (appel) async {
          if (appel.method == 'Clipboard.setData') {
            copies.add((appel.arguments as Map)['text'] as String);
          }
          return null;
        });
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    await db.close();
  });

  Future<void> monter(
    WidgetTester tester, {
    String login = 'n.kora',
    String role = 'administrateur',
  }) async {
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
              utilisateurId: login,
              login: login,
              nom: login,
              role: role,
              droits: GardeAcces.depuisJson(const {'M1': 'C', 'ROLES': 'C'}),
            ),
          ),
          imprimerCodeSecoursProvider.overrideWithValue(
            (code, compte) async => impressions.add((code, compte)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranMonProfil()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> attendre(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 900)),
    );
    await tester.pumpAndSettle();
  }

  Finder cle(String k) => find.byKey(Key(k));

  testWidgets('un rôle hors administration n’a PAS la carte « Code de '
      'secours »', (tester) async {
    await monter(tester, login: 'marie', role: 'receptionniste');
    expect(cle('profil-code-secours'), findsNothing);
    expect(find.text(MessagesMotDePassePerdu.codeSecoursTitre), findsNothing);
  });

  testWidgets('un super administrateur l’a', (tester) async {
    await monter(tester, role: 'super_admin');
    expect(cle('profil-code-secours'), findsOneWidget);
  });

  testWidgets('un administrateur l’a ; un ancien compte (avant la v46) n’a '
      'pas de code et le dit', (tester) async {
    await monter(tester);
    expect(cle('profil-code-secours'), findsOneWidget);
    expect(
      tester.widget<Text>(cle('profil-code-secours-etat')).data,
      MessagesMotDePassePerdu.codeSecoursAbsent,
    );
  });

  testWidgets('mot de passe FAUX : refusé dans la fenêtre, le champ est vidé, '
      'aucun code n’est posé', (tester) async {
    await monter(tester);
    await tester.ensureVisible(cle('profil-code-secours-ouvrir'));
    await tester.tap(cle('profil-code-secours-ouvrir'));
    await tester.pumpAndSettle();
    // Le bouton et le titre de la fenêtre portent le même mot, comme la vue.
    expect(
      find.text(MessagesMotDePassePerdu.codeSecoursModaleTitre),
      findsNWidgets(2),
    );

    await tester.enterText(
      cle('profil-code-secours-mot-de-passe'),
      'mauvais-123',
    );
    await tester.tap(cle('profil-code-secours-generer'));
    await attendre(tester);

    expect(find.text(MessagesMotDePassePerdu.mdpIncorrect), findsOneWidget);
    expect(
      tester
          .widget<TextField>(cle('profil-code-secours-mot-de-passe'))
          .controller!
          .text,
      isEmpty,
    );
    final ligne = await tester.runAsync(
      () => db
          .customSelect(
            'SELECT code_secours_empreinte AS e FROM utilisateurs_local '
            "WHERE login = 'n.kora'",
          )
          .getSingle(),
    );
    expect(ligne!.data['e'], isNull);
  });

  testWidgets('mot de passe juste : le code est montré UNE fois (copier, '
      'imprimer), l’état se met à jour, seul le dérivé est stocké', (
    tester,
  ) async {
    await monter(tester);
    await tester.ensureVisible(cle('profil-code-secours-ouvrir'));
    await tester.tap(cle('profil-code-secours-ouvrir'));
    await tester.pumpAndSettle();
    await tester.enterText(cle('profil-code-secours-mot-de-passe'), motDePasse);
    await tester.tap(cle('profil-code-secours-generer'));
    await attendre(tester);

    expect(
      find.text(MessagesMotDePassePerdu.codeSecoursAfficheTitre),
      findsOneWidget,
    );
    expect(
      find.text(MessagesMotDePassePerdu.codeSecoursConsigne),
      findsOneWidget,
    );
    final code = tester
        .widget<SelectableText>(cle('profil-code-secours-code-valeur'))
        .data!;
    expect(code, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));

    await tester.tap(cle('profil-code-secours-code-copier'));
    await tester.pump();
    expect(copies, [code]);
    expect(find.text(TextesSecretUnique.copie), findsOneWidget);
    await tester.tap(cle('profil-code-secours-code-imprimer'));
    await tester.pump();
    expect(impressions, [(code, 'n.kora')]);

    await tester.tap(find.text(MessagesMotDePassePerdu.codeSecoursFermer));
    await tester.pumpAndSettle();
    // Fermé, il ne revient plus ; l'état dit que le code est posé.
    expect(find.text(code), findsNothing);
    expect(
      tester.widget<Text>(cle('profil-code-secours-etat')).data,
      startsWith('Un code de secours est enregistré (posé le '),
    );

    final ligne = await tester.runAsync(
      () => db
          .customSelect(
            'SELECT code_secours_empreinte AS e, code_secours_sel AS s '
            "FROM utilisateurs_local WHERE login = 'n.kora'",
          )
          .getSingle(),
    );
    expect(ligne!.data['e'], isNotNull);
    expect(ligne.data['e'], isNot(contains(code)));
    expect(ligne.data['s'], isNot(contains(code)));
  });
}
