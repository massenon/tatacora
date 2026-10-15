import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/coquille_application.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';

/// Monte la COQUILLE (barre supérieure, barre latérale) pour un rôle, avec la
/// matrice de droits que la vue Blade a servie à ce rôle (`droits`, 16 modules).
///
/// Poste de travail uniquement : 1 600 px de large (décision du PO du
/// 08/10/2026, pas de Flutter mobile).
Future<void> monterCoquille(
  WidgetTester tester, {
  required String role,
  required Map<String, dynamic> droits,
  required String routeActive,
  Size taille = const Size(1600, 1400),
  String? login,
  Widget? enfant,
  List<Override> surcharges = const [],
  bool coquillePartagee = false,
}) async {
  tester.view
    ..physicalSize = taille
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Le rôle est passé BRUT, comme `SessionRepositoryLocal` le pose sur un vrai
  // poste (le code : « administrateur »). ⚠ Jusqu'au 12/10/2026 ce banc le
  // capitalisait lui-même, faisant le travail de l'écran : la barre affichait
  // « administrateur » en production et la mesure lisait « Administrateur ».
  final session = Session(
    utilisateurId: 'u-$role',
    login: login ?? 'barre.$role',
    nom: login ?? 'barre.$role',
    role: role,
    droits: GardeAcces.depuisJson({
      for (final e in droits.entries) e.key: e.value as String,
    }),
  );

  // L'indicateur de caisse de la barre supérieure lit `sessions_caisse_local`.
  // Sans surcharge fournie par l'appelant, une base EN MÉMOIRE (vide : « Caisse
  // fermée ») ; un appelant qui passe des surcharges fournit la sienne — tous
  // ceux d'aujourd'hui surchargent `baseLocaleProvider`.
  final AppDatabase? baseParDefaut = surcharges.isEmpty
      ? AppDatabase.enMemoire()
      : null;
  if (baseParDefaut != null) addTearDown(baseParDefaut.close);

  final routes = <String>{
    routeActive,
    for (final d in toutesLesDestinations)
      if (d.route != null) d.route!,
    // Le menu de compte mène aussi à des écrans (14/10/2026, D424).
    '/mon-profil',
    '/journal-audit',
    '/aide-a-propos',
    '/contact-editeur',
  };
  // `coquillePartagee` : la structure du VRAI routeur (`app_router.dart`), une
  // `ShellRoute` dont la coquille SURVIT à la navigation (son état reçoit
  // `didUpdateWidget`). Sans elle, chaque route monte sa propre coquille, et
  // chaque navigation repasse par `initState`. Les deux chemins existent en
  // production (navigation ; reconnexion) et se prouvent séparément.
  final routeur = GoRouter(
    initialLocation: routeActive,
    routes: coquillePartagee
        ? [
            ShellRoute(
              builder: (_, state, page) =>
                  CoquilleApplication(routeActive: state.uri.path, child: page),
              routes: [
                for (final r in routes)
                  GoRoute(
                    path: r,
                    builder: (_, _) => enfant ?? const SizedBox.expand(),
                  ),
              ],
            ),
          ]
        : [
            for (final r in routes)
              GoRoute(
                path: r,
                builder: (_, state) => CoquilleApplication(
                  routeActive: state.uri.path,
                  child: enfant ?? const SizedBox.expand(),
                ),
              ),
          ],
  );
  addTearDown(routeur.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithBuild((ref, notifier) => session),
        if (baseParDefaut != null)
          baseLocaleProvider.overrideWithValue(baseParDefaut),
        ...surcharges,
      ],
      // La frontière sert aux CAPTURES (Phase 1D), sans effet sur la mise en page.
      child: RepaintBoundary(
        key: const Key('capture-flutter'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.clair,
          routerConfig: routeur,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
