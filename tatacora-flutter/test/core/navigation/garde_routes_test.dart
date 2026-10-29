@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/app_router.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/recherche_globale/domain/recherche_globale.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

import '../../support/coquille_montee.dart';

/// La GARDE DES ROUTES (Lot J2, 14/10/2026) éprouvée sur le VRAI routeur :
/// `routeurProvider` est construit, et sa fonction `redirect` est appelée
/// telle que `go_router` l'appelle — avec un `GoRouterState` — pour CHAQUE
/// chemin que le routeur sert.
///
/// ## Ancrages extérieurs (piège 12)
///
/// * Les chemins sont relus dans le CODE SOURCE du routeur (`path:` littéraux,
///   sous-chemins relatifs recomposés), jamais recopiés ici : une route
///   ajoutée demain entre d'elle-même dans le balayage.
/// * Le module qui garde chaque chemin est TROUVÉ par l'essai : on retire un
///   module à la fois, et on regarde lequel fait refuser le chemin — puis on
///   le confronte à l'entrée du menu qui porte la route.
/// * Les routes ouvertes à tout compte sont relues dans `routes/web.php` du
///   serveur (celles du groupe `auth` sans middleware `module:`), et les rôles
///   d'administration dans `User::ROLES_ADMINISTRATION`, par PHP.
void main() {
  const repli = '/tableau-de-bord';

  /// Les chemins servis par le routeur, lus dans son source. Les sous-chemins
  /// relatifs (`path: 'heberges'`) sont rattachés au dernier chemin absolu
  /// qui les précède — c'est ainsi que `go_router` les compose ici.
  List<String> cheminsServis() {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final chemins = <String>[];
    String? parent;
    for (final m in RegExp(r"path: '([^']+)'").allMatches(source)) {
      final p = m.group(1)!;
      if (p.startsWith('/')) {
        parent = p;
        chemins.add(p);
      } else {
        chemins.add('$parent/$p');
      }
    }
    // Les écrans HORS coquille — démarrage, connexion, et depuis le 29/10/2026 les
    // deux écrans « invité » du mot de passe perdu — n'ont pas de module : leur
    // garde est celle de la session (`garde_mot_de_passe_perdu_test.dart`).
    const horsCoquille = {
      '/demarrage',
      '/connexion',
      '/changement-mot-de-passe',
      '/mot-de-passe-administrateur-perdu',
    };
    return chemins.where((c) => !horsCoquille.contains(c)).toList();
  }

  final codes = socleRbacCdcf['super_admin']!.keys.toList();
  Map<String, String> tout(String niveau) => {for (final c in codes) c: niveau};

  Session session(String role, Map<String, String> droits) => Session(
    utilisateurId: 'u-$role',
    login: 'u-$role',
    nom: 'u-$role',
    role: role,
    droits: GardeAcces.depuisJson(droits),
  );

  /// Un conteneur dont la session se change entre deux appels.
  late ProviderContainer conteneur;
  late GoRouter routeur;
  Session? courante;

  void connecter(Session? s) {
    courante = s;
    conteneur.invalidate(sessionProvider);
  }

  setUp(() {
    courante = null;
    conteneur = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild((ref, notifier) => courante),
      ],
    );
    routeur = conteneur.read(routeurProvider);
  });
  tearDown(() {
    routeur.dispose();
    conteneur.dispose();
  });

  /// Monte un messager (celui de l'application) et rend le contexte.
  Future<BuildContext> monterMessager(WidgetTester tester) async {
    late BuildContext contexte;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messagerApplication,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              contexte = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return contexte;
  }

  /// Le VRAI `redirect` du routeur, sur [chemin].
  Future<String?> rediriger(BuildContext contexte, String chemin) async {
    final etat = GoRouterState(
      routeur.configuration,
      uri: Uri.parse(chemin),
      matchedLocation: chemin,
      fullPath: chemin,
      pathParameters: const {},
      pageKey: ValueKey<String>(chemin),
    );
    return routeur.configuration.topRedirect(contexte, etat);
  }

  /// Le toast de la garde est-il affiché ? (puis l'efface).
  Future<bool> toastAffiche(WidgetTester tester) async {
    // En production, `redirect` tourne pendant une navigation, qui demande
    // une image ; appelé seul, il faut la demander pour que le rappel
    // d'après-image de la garde s'exécute.
    tester.binding.scheduleFrame();
    await tester.pump();
    await tester.pump();
    final vu =
        find.text(messageAccesRefuse).evaluate().isNotEmpty &&
        find.byKey(const Key('garde-acces-refuse')).evaluate().isNotEmpty;
    messagerApplication.currentState?.removeCurrentSnackBar();
    await tester.pump();
    return vu;
  }

  test('le balayage du routeur n’est PAS vide, et tout chemin servi est '
      'connu de la garde', () {
    final chemins = cheminsServis();
    // Plancher : 35 `path:` au 15/10/2026, dont /demarrage et /connexion.
    expect(chemins.length, greaterThanOrEqualTo(30));
    expect(chemins, containsAll(['/pos/heberges', '/comptes-utilisateurs']));
    for (final c in chemins) {
      expect(
        accesRoute(c, droits: GardeAcces.depuisJson(tout('C')), role: 'x'),
        isNot(AccesRoute.inconnu),
        reason: '$c est servi mais la garde ne le connaît pas',
      );
    }
  });

  testWidgets('CHAQUE route : un compte sans lecture sur son module est '
      'renvoyé au tableau de bord AVEC le toast ; avec le droit, il y entre', (
    tester,
  ) async {
    final contexte = await monterMessager(tester);
    final ouvertes = routesOuvertesATousLesComptes;
    var refusEprouves = 0;

    for (final chemin in cheminsServis()) {
      // Tous les droits, rôle d'administration : la route s'ouvre.
      connecter(session('administrateur', tout('C')));
      expect(await rediriger(contexte, chemin), isNull, reason: chemin);
      expect(await toastAffiche(tester), isFalse, reason: chemin);

      // Un module retiré à la fois : lesquels ferment ce chemin ?
      final fermants = <String>{};
      for (final code in codes) {
        connecter(session('administrateur', {...tout('C'), code: '-'}));
        final cible = await rediriger(contexte, chemin);
        if (cible == null) continue;
        expect(cible, repli, reason: '$chemin sans $code');
        expect(
          await toastAffiche(tester),
          isTrue,
          reason: '$chemin sans $code : refus muet',
        );
        fermants.add(code);
        refusEprouves++;
      }

      if (ouvertes.contains(chemin)) {
        expect(fermants, isEmpty, reason: '$chemin est ouvert à tous');
        continue;
      }
      expect(fermants, hasLength(1), reason: '$chemin : $fermants');
      // Le module trouvé est celui de l'entrée du menu qui porte la route
      // (ou de sa racine, pour une sous-route).
      final porteuse = toutesLesDestinations
          .where(
            (d) =>
                d.route != null &&
                (d.route == chemin || chemin.startsWith('${d.route}/')),
          )
          .fold<DestinationMenu?>(
            null,
            (m, d) => m == null || d.route!.length > m.route!.length ? d : m,
          );
      final attendu =
          porteuse?.module.code ?? modulesDesRoutesHorsMenu[chemin]?.code;
      expect(fermants.single, attendu, reason: chemin);
      // Lecture seule suffit pour entrer.
      connecter(session('administrateur', {...tout('C'), attendu!: 'L'}));
      expect(await rediriger(contexte, chemin), isNull, reason: chemin);
    }
    expect(refusEprouves, greaterThanOrEqualTo(25));
  });

  testWidgets('dans l’APPLICATION montée (MaterialApp.router, messager de '
      'l’application) : l’adresse refusée atterrit au tableau de bord avec '
      'le toast, l’adresse permise ouvre son écran', (tester) async {
    tester.view
      ..physicalSize = const Size(1600, 1200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    final recep = session('receptionniste', socleRbacCdcf['receptionniste']!);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild((ref, notifier) => recep),
        ],
        child: Consumer(
          builder: (context, ref, _) => MaterialApp.router(
            scaffoldMessengerKey: messagerApplication,
            theme: AppTheme.clair,
            routerConfig: ref.watch(routeurProvider),
          ),
        ),
      ),
    );
    await tester.pump();
    final app = ProviderScope.containerOf(
      tester.element(find.byType(Router<Object>)),
    ).read(routeurProvider);
    String ici() => app.routerDelegate.currentConfiguration.uri.path;

    Future<void> aller(String chemin) async {
      app.go(chemin);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // ROLES est fermé au réceptionniste, PARAM aussi.
    for (final refuse in [routeComptesUtilisateurs, '/parametres']) {
      await aller(refuse);
      expect(ici(), repli, reason: refuse);
      expect(find.byKey(const Key('garde-acces-refuse')), findsOneWidget);
      messagerApplication.currentState?.removeCurrentSnackBar();
      await tester.pump(const Duration(milliseconds: 500));
    }
    await aller('/hebergement');
    expect(ici(), '/hebergement');
    expect(find.byKey(const Key('garde-acces-refuse')), findsNothing);
  });

  testWidgets('/comptes-utilisateurs : SEULS les rôles d’administration '
      '(User::ROLES_ADMINISTRATION, relu par PHP), même avec ROLES lu par '
      'tous', (tester) async {
    final r = (await tester.runAsync(
      () => Process.run('php', [
        '-r',
        "require 'vendor/autoload.php'; "
            r'echo json_encode(\App\Models\User::ROLES_ADMINISTRATION);',
      ], workingDirectory: '../tatacora-api'),
    ))!;
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final admins = (jsonDecode(r.stdout as String) as List).cast<String>();
    expect(admins, isNotEmpty);

    final contexte = await monterMessager(tester);
    for (final role in socleRbacCdcf.keys) {
      connecter(session(role, {...socleRbacCdcf[role]!, 'ROLES': 'C'}));
      final cible = await rediriger(contexte, routeComptesUtilisateurs);
      if (admins.contains(role)) {
        expect(cible, isNull, reason: role);
        expect(await toastAffiche(tester), isFalse);
      } else {
        expect(cible, repli, reason: role);
        expect(await toastAffiche(tester), isTrue, reason: role);
      }
    }
    // Un administrateur SANS lecture sur ROLES n'entre pas non plus.
    connecter(session('administrateur', {...tout('C'), 'ROLES': '-'}));
    expect(await rediriger(contexte, routeComptesUtilisateurs), repli);
  });

  testWidgets('les routes ouvertes (relues dans routes/web.php) le sont à '
      'tout compte, même sans AUCUN droit', (tester) async {
    final web = File('../tatacora-api/routes/web.php').readAsStringSync();
    final debut = web.indexOf("Route::middleware('auth')->group");
    final fin = web.indexOf("Route::middleware('module:", debut);
    expect(debut, greaterThan(0));
    expect(fin, greaterThan(debut));
    final serveur = {
      for (final m in RegExp(
        r"Route::get\('(/[a-z-]*)'",
      ).allMatches(web.substring(debut, fin)))
        // `/` est l'accueil, le tableau de bord du poste.
        m.group(1) == '/' ? repli : m.group(1)!,
    };
    expect(serveur, hasLength(5));
    expect(routesOuvertesATousLesComptes, serveur);

    final contexte = await monterMessager(tester);
    for (final role in [...socleRbacCdcf.keys, 'role_inconnu']) {
      connecter(session(role, tout('-')));
      for (final chemin in serveur) {
        expect(
          await rediriger(contexte, chemin),
          isNull,
          reason: '$role $chemin',
        );
      }
      // Et un module fermé, lui, reste fermé.
      expect(await rediriger(contexte, '/stocks'), repli);
      expect(await toastAffiche(tester), isTrue);
    }
  });

  testWidgets('/journal-audit est gardé par M14, comme au serveur', (
    tester,
  ) async {
    final web = File('../tatacora-api/routes/web.php').readAsStringSync();
    final m = RegExp(
      r"middleware\('module:(\w+),L'\)\s*->get\('/journal-audit'",
    ).firstMatch(web);
    expect(m, isNotNull);
    expect(modulesDesRoutesHorsMenu['/journal-audit']!.code, m!.group(1));
  });

  testWidgets('chemin INCONNU : tableau de bord, SANS toast (ce n’est pas un '
      'refus de droit) ; déconnecté : la connexion', (tester) async {
    final contexte = await monterMessager(tester);
    connecter(session('administrateur', tout('C')));
    expect(await rediriger(contexte, '/nulle-part'), repli);
    expect(await toastAffiche(tester), isFalse);
    expect(await rediriger(contexte, '/connexion'), repli);

    connecter(null);
    expect(await rediriger(contexte, '/stocks'), '/connexion');
    expect(await rediriger(contexte, '/connexion'), isNull);
    expect(await rediriger(contexte, '/demarrage'), isNull);
    expect(await toastAffiche(tester), isFalse);
  });

  testWidgets('la barre latérale RENDUE montre exactement les entrées que la '
      'règle dit visibles — pour chaque rôle du socle', (tester) async {
    var vus = 0;
    for (final MapEntry(key: role, value: niveaux) in socleRbacCdcf.entries) {
      // Démonter d'abord : un `ProviderScope` mis à jour en place garderait
      // la session du rôle précédent.
      await tester.pumpWidget(const SizedBox.shrink());
      await monterCoquille(
        tester,
        role: role,
        droits: niveaux,
        routeActive: repli,
        taille: const Size(1600, 3000),
      );
      final droits = GardeAcces.depuisJson(niveaux);
      for (final d in toutesLesDestinations) {
        final rendue = find
            .byKey(Key('lien-lateral-${d.nom}'))
            .evaluate()
            .isNotEmpty;
        expect(
          rendue,
          destinationVisible(d, droits: droits, role: role),
          reason: '$role ${d.nom}',
        );
        if (rendue) vus++;
      }
    }
    expect(vus, greaterThan(40));
  });

  test('barre latérale, recherche globale et garde disent la MÊME chose : '
      'une entrée refusée par l’adresse n’est ni au menu ni trouvée, et '
      'une entrée du menu s’ouvre par son adresse', () {
    var masquees = 0;
    var visibles = 0;
    for (final MapEntry(key: role, value: niveaux) in socleRbacCdcf.entries) {
      final droits = GardeAcces.depuisJson(niveaux);
      for (final d in toutesLesDestinations) {
        final route = d.route;
        if (route == null) continue;
        final visible = destinationVisible(d, droits: droits, role: role);
        final trouvee = pagesCorrespondantes(
          droits: droits,
          role: role,
          terme: d.nom,
        ).any((p) => p.nom == d.nom);
        final verdict = accesRoute(route, droits: droits, role: role);

        expect(trouvee, visible, reason: '$role ${d.nom} : menu ≠ recherche');
        if (visible) {
          visibles++;
          expect(verdict, AccesRoute.autorise, reason: '$role ${d.nom}');
        }
        if (verdict == AccesRoute.refuse) {
          masquees++;
          expect(visible, isFalse, reason: '$role ${d.nom}');
          expect(trouvee, isFalse, reason: '$role ${d.nom}');
        }
        // L'accès (droit du module + rôle exigé) EST le verdict de la garde.
        expect(
          verdict == AccesRoute.autorise,
          destinationAccessible(d, droits: droits, role: role) ||
              routesOuvertesATousLesComptes.contains(route),
          reason: '$role ${d.nom}',
        );
      }
    }
    // Non vide dans les deux sens.
    expect(masquees, greaterThan(20));
    expect(visibles, greaterThan(20));
  });
}
