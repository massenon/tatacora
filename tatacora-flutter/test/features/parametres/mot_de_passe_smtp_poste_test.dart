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
import 'package:tatacora_flutter/features/parametres/presentation/widgets/champ_mot_de_passe_smtp.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

/// Paramètres → Email (SMTP) : le mot de passe SMTP du poste se SAISIT à
/// l'écran (décision du PO du 19/10/2026), s'écrit dans `poste.json` — un
/// vrai fichier ici —, jamais dans la base, et ne se réaffiche jamais.
void main() {
  const secret = 'Smtp-Poste-Jamais-Affiche-42';

  late Directory dossier;
  late File fichierBase;
  late AppDatabase db;
  late String cheminPoste;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    dossier = await Directory.systemTemp.createTemp('tatacora-smtp-poste-');
    fichierBase = File('${dossier.path}/tatacora.sqlite');
    cheminPoste = '${dossier.path}/poste.json';
    db = AppDatabase.surFichier(fichierBase);
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  Future<void> laisserTourner(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  Future<void> monter(
    WidgetTester tester, {
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
              utilisateurId: 'u-1',
              login: 'admin.gite',
              nom: 'Essai',
              role: role,
              droits: droits,
            ),
          ),
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => cheminPoste,
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranParametres()),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('param-onglet-email')));
    await laisserTourner(tester);
  }

  Map<String, Object?> fichier() =>
      jsonDecode(File(cheminPoste).readAsStringSync()) as Map<String, Object?>;

  testWidgets('un Administrateur le saisit : écrit dans poste.json avec '
      'son état, le reste du fichier gardé, jamais réaffiché ni en base', (
    tester,
  ) async {
    // Un appairage déjà là : il doit survivre à la saisie.
    File(cheminPoste).writeAsStringSync(
      jsonEncode({'poste_id': 'PC-1', 'jeton_api': '1|j', 'serveur': 'x'}),
    );
    await monter(tester);
    expect(find.text(TextesMotDePasseSmtp.absent), findsOneWidget);
    expect(find.byKey(const Key('param-smtp-effacer')), findsNothing);

    await tester.enterText(find.byKey(const Key('param-smtp-saisie')), secret);
    await tester.tap(find.byKey(const Key('param-smtp-enregistrer')));
    await laisserTourner(tester);

    final contenu = fichier();
    expect(contenu[cleMotDePasseSmtp], secret);
    expect(contenu[cleMotDePasseSmtpPar], 'admin.gite');
    expect(DateTime.tryParse('${contenu[cleMotDePasseSmtpLe]}'), isNotNull);
    expect(contenu['jeton_api'], '1|j');

    expect(find.text(TextesMotDePasseSmtp.enregistre), findsOneWidget);
    expect(find.textContaining('par admin.gite'), findsOneWidget);
    expect(find.text(secret), findsNothing);
    final champ = tester.widget<TextField>(
      find.byKey(const Key('param-smtp-saisie')),
    );
    expect(champ.controller!.text, isEmpty);
    expect(champ.obscureText, isTrue);

    // Ni la base ni son journal ne portent le secret (vraies E/S, hors de
    // la zone simulée du banc).
    await tester.runAsync(() async {
      for (final f in dossier.listSync().whereType<File>()) {
        if (!f.path.contains('tatacora.sqlite')) continue;
        final octets = latin1.decode(f.readAsBytesSync(), allowInvalid: true);
        expect(octets.contains(secret), isFalse, reason: f.path);
      }
      final lu = await LecteurConfigurationPoste(
        chemin: () async => cheminPoste,
      ).motDePasseSmtp();
      expect(lu, isA<MotDePasseLu>());
    });
  });

  testWidgets('effacer retire le secret et son état, l’appairage reste', (
    tester,
  ) async {
    File(cheminPoste).writeAsStringSync(
      jsonEncode({
        cleMotDePasseSmtp: secret,
        'poste_id': 'PC-1',
        'jeton_api': '1|j',
        'serveur': 'x',
      }),
    );
    await monter(tester);
    // Posé à la main : renseigné, sans date ni auteur.
    expect(find.textContaining('Renseigné le — par —'), findsOneWidget);

    await tester.tap(find.byKey(const Key('param-smtp-effacer')));
    await laisserTourner(tester);

    expect(fichier().containsKey(cleMotDePasseSmtp), isFalse);
    expect(fichier()['jeton_api'], '1|j');
    expect(find.text(TextesMotDePasseSmtp.absent), findsOneWidget);
  });

  testWidgets('vide : refusé, rien d’écrit', (tester) async {
    await monter(tester);
    await tester.tap(find.byKey(const Key('param-smtp-enregistrer')));
    await laisserTourner(tester);
    expect(find.text(TextesMotDePasseSmtp.vide), findsOneWidget);
    expect(File(cheminPoste).existsSync(), isFalse);
  });

  testWidgets('un poste.json illisible n’est pas écrasé', (tester) async {
    File(cheminPoste).writeAsStringSync('{ pas du json');
    await monter(tester);
    await tester.enterText(find.byKey(const Key('param-smtp-saisie')), secret);
    await tester.tap(find.byKey(const Key('param-smtp-enregistrer')));
    await laisserTourner(tester);
    expect(File(cheminPoste).readAsStringSync(), '{ pas du json');
    expect(find.textContaining('illisible'), findsWidgets);
  });

  testWidgets('hors Administrateur : aucun champ, la réserve est dite', (
    tester,
  ) async {
    await monter(tester, role: 'gerant');
    expect(find.byKey(const Key('param-smtp-saisie')), findsNothing);
    expect(find.text(TextesMotDePasseSmtp.reserve), findsOneWidget);
  });
}
