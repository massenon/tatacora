import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/identifiant_memorise.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_changement_mot_de_passe.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_code_secours.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/parametres/data/apparence_poste.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';

/// Police du poste (PO, 09/11/2026) : sur la connexion et ses écrans voisins,
/// le libellé des boutons et les liens texte sortaient dans la police par
/// défaut, pas en Inter.
///
/// Cause : `ButtonStyle.textStyle` REMPLACE le style de texte du bouton, il ne
/// se fusionne pas avec le thème. Un `TextStyle(fontSize: …)` sans
/// `fontFamily` perdait donc la famille du `ThemeData`. Le thème ne peut pas la
/// réimposer : un style local l'emporte sur le `textButtonTheme`. Chaque style
/// local de bouton porte donc le jeton `AppTextStyles.police`.
///
/// Le test lit le style EFFECTIF de chaque paragraphe rendu (celui que le
/// moteur peint, fusion du thème et du style local comprise) : il ne dépend
/// pas de la police chargée, et sous test la famille reste lisible.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    base = AppDatabase.enMemoire();
    await RolesDao(base).installerSocle();
  });
  tearDown(() async => base.close());

  Future<void> monter(
    WidgetTester tester,
    String depart, {
    bool aucunCompte = false,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final routeur = GoRouter(
      initialLocation: depart,
      routes: [
        GoRoute(path: '/connexion', builder: (_, _) => const EcranConnexion()),
        GoRoute(
          path: '/code-secours',
          builder: (_, _) => const EcranCodeSecours(),
        ),
        GoRoute(
          path: '/changement',
          builder: (_, _) => const EcranChangementMotDePasse(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(base),
          aucunCompteProvider.overrideWith((ref) async => aucunCompte),
          logoTeleverseProvider.overrideWith((ref) async => null),
          dossierConnexionProvider.overrideWithValue(
            () async => throw StateError('pas de dossier en essai'),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Les paragraphes rendus dont la famille N'EST PAS Inter (les pictogrammes
  /// Material, qui portent leur propre police d'icônes, sont écartés).
  List<String> horsInter(WidgetTester tester) {
    final fautifs = <String>[];
    for (final p in tester.widgetList<RichText>(find.byType(RichText))) {
      final famille = p.text.style?.fontFamily;
      final texte = p.text.toPlainText();
      if (famille == 'MaterialIcons' || texte.trim().isEmpty) continue;
      if (famille != AppTextStyles.police) {
        fautifs.add('« $texte » : ${famille ?? 'aucune famille'}');
      }
    }
    return fautifs;
  }

  /// Le style EFFECTIF du libellé d'un bouton ou d'un lien.
  String? familleDe(WidgetTester tester, Finder bouton) {
    final texte = find.descendant(of: bouton, matching: find.byType(RichText));
    return tester
        .widgetList<RichText>(texte)
        .firstWhere((r) => r.text.toPlainText().trim().isNotEmpty)
        .text
        .style
        ?.fontFamily;
  }

  testWidgets(
    'connexion : bouton, lien « mot de passe oublié » et tout texte en Inter',
    (tester) async {
      await monter(tester, '/connexion');
      expect(
        familleDe(tester, find.byType(ElevatedButton)),
        AppTextStyles.police,
        reason: 'le bouton « Se connecter » n\'est pas en Inter',
      );
      final oublie = find.byType(TextButton);
      expect(oublie, findsWidgets);
      for (final lien in oublie.evaluate()) {
        expect(
          familleDe(tester, find.byWidget(lien.widget)),
          AppTextStyles.police,
          reason: 'un lien texte de la connexion n\'est pas en Inter',
        );
      }
      expect(horsInter(tester), isEmpty);
    },
  );

  testWidgets('connexion, premier compte : bouton et textes en Inter', (
    tester,
  ) async {
    await monter(tester, '/connexion', aucunCompte: true);
    expect(find.byType(ElevatedButton), findsWidgets);
    expect(
      familleDe(tester, find.byType(ElevatedButton).first),
      AppTextStyles.police,
    );
    expect(horsInter(tester), isEmpty);
  });

  testWidgets(
    'code de secours : bouton, lien « Retour à la connexion » et textes en Inter',
    (tester) async {
      await monter(tester, '/code-secours');
      expect(
        familleDe(tester, find.byKey(const Key('code-secours-retour'))),
        AppTextStyles.police,
        reason: 'le lien « Retour à la connexion » n\'est pas en Inter',
      );
      expect(
        familleDe(tester, find.byType(ElevatedButton)),
        AppTextStyles.police,
        reason: 'le bouton de réinitialisation n\'est pas en Inter',
      );
      expect(horsInter(tester), isEmpty);
    },
  );

  testWidgets(
    'changement de mot de passe obligatoire : bouton, lien et textes en Inter',
    (tester) async {
      await monter(tester, '/changement');
      expect(
        familleDe(tester, find.byKey(const Key('changement-se-deconnecter'))),
        AppTextStyles.police,
        reason: 'le lien « Se déconnecter » n\'est pas en Inter',
      );
      expect(horsInter(tester), isEmpty);
    },
  );
}
