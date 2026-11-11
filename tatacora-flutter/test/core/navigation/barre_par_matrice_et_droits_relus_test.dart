import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/navigation_tatacora.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/coquille_application.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';

import '../../support/coquille_montee.dart';
import '../../support/structure_rendue.dart';
import '../../support/vue_blade.dart';

/// 11/11/2026 (PO) : la barre latérale est pilotée UNIQUEMENT par le RBAC — plus aucun masquage
/// par nom de rôle — et se reconstruit, sans reconnexion, quand les droits de la session changent.
///
/// Source EXTÉRIEURE au poste : la matrice du seeder serveur (`RolePermissionSeeder::MATRICE`),
/// relue dans son fichier PHP, et la table « entrée → module » ci-dessous, recopiée à la main
/// (jamais dérivée de `toutesLesDestinations`, sinon le test se comparerait à lui-même).

/// Les 28 entrées de la barre, dans l'ordre : nom → module qui la commande.
const Map<String, String> _moduleParEntree = {
  'Tableau de bord': 'M11',
  'Point de vente': 'M5',
  'POS clients hébergés': 'M1',
  'Historique des ventes': 'M5',
  'Dépense courante': 'M10',
  'Réservations': 'M1',
  'Hébergement': 'M1',
  'Clients & Créances': 'M3',
  'Facturation': 'M2',
  'Stocks': 'M6',
  'Inventaires & Fiches': 'M6',
  'Approvisionnement': 'M7',
  'Fournisseurs': 'M7',
  'Restaurant': 'M4',
  'Bar': 'M5',
  'Tourisme': 'M9',
  'Véhicules & Locations': 'M8',
  'Comptabilité': 'M10',
  'Personnel & Paie': 'M13',
  'Congés & Plannings': 'M13',
  'États & Rapports': 'M14',
  'Notifications': 'M12',
  'Import & Export': 'IMPORT_EXPORT',
  'Rôles & Permissions': 'ROLES',
  'Comptes utilisateurs': 'ROLES',
  'Paramètres': 'PARAM',
  'Synchronisation': 'SYNCHRO',
  'Appairage Postes': 'APPAIRAGE',
};

/// L'entrée qui exige en plus un rôle d'administration.
const Set<String> _entreesAdministration = {'Comptes utilisateurs'};

/// La matrice du seeder, lue dans `RolePermissionSeeder.php` : rôle → module → niveau.
Map<String, Map<String, String>> _matriceDuSeeder() {
  final source = VueBlade.fichier('database/seeders/RolePermissionSeeder.php');
  final bloc = source.substring(source.indexOf('public const MATRICE'));
  final matrice = <String, Map<String, String>>{};
  final ligne = RegExp(r"'(\w+)'\s*=>\s*\[([^\]]*)\]");
  for (final m in ligne.allMatches(bloc.substring(0, bloc.indexOf('];')))) {
    matrice[m.group(1)!] = {
      for (final c in RegExp(r"'(\w+)'=>'([CL-])'").allMatches(m.group(2)!))
        c.group(1)!: c.group(2)!,
    };
  }
  return matrice;
}

List<String> _attendu(String role, Map<String, String> matrice) => [
  for (final e in _moduleParEntree.entries)
    if (matrice[e.value] != '-' &&
        (!_entreesAdministration.contains(e.key) ||
            const {'administrateur', 'super_admin'}.contains(role)))
      e.key,
];

/// Les entrées de la barre rendues (hors pied), dans l'ordre de lecture.
List<String> _entreesRendues(WidgetTester tester) {
  final noms = {for (final d in toutesLesDestinations) normaliser(d.nom)};
  final pied = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_PiedBarreLaterale',
  );
  final limite = tester.getRect(pied).top;
  return [
    for (final e in collecterRendu(tester))
      if (e.boite.left < 264 &&
          e.boite.top >= 64 &&
          e.boite.bottom <= limite &&
          noms.contains(normaliser(e.texte)))
        toutesLesDestinations
            .firstWhere((d) => normaliser(d.nom) == normaliser(e.texte))
            .nom,
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('la barre latérale rendue suit la matrice du seeder, par rôle', () {
    final matrice = _matriceDuSeeder();

    test('la matrice du seeder est lue en entier (plancher)', () {
      expect(matrice.length, 12);
      expect(matrice['gerant']!['M10'], 'C');
      expect(matrice['gerant']!['ROLES'], 'L');
      expect(matrice['comptable'], matrice['gerant']);
    });

    for (final role in const [
      'administrateur',
      'gerant',
      'comptable',
      'barman',
      'receptionniste',
    ]) {
      testWidgets('rôle « $role » : exactement les entrées de la matrice', (
        tester,
      ) async {
        await monterCoquille(
          tester,
          role: role,
          droits: matrice[role]!,
          routeActive: '/tableau-de-bord',
          taille: const Size(1600, 1500),
        );
        expect(_entreesRendues(tester), _attendu(role, matrice[role]!));
      });
    }

    testWidgets('le gérant voit Comptabilité, Personnel & Paie, Congés & '
        'Plannings, Tourisme, Véhicules, États, Notifications, Clients, '
        'Facturation, Rôles & Permissions et Paramètres', (tester) async {
      await monterCoquille(
        tester,
        role: 'gerant',
        droits: matrice['gerant']!,
        routeActive: '/tableau-de-bord',
        taille: const Size(1600, 1500),
      );
      expect(
        _entreesRendues(tester),
        containsAll(<String>[
          'Comptabilité',
          'Personnel & Paie',
          'Congés & Plannings',
          'Tourisme',
          'Véhicules & Locations',
          'États & Rapports',
          'Notifications',
          'Clients & Créances',
          'Facturation',
          'Rôles & Permissions',
          'Paramètres',
        ]),
      );
      // `rolesExiges` : « Comptes utilisateurs » reste réservé aux administrateurs.
      expect(_entreesRendues(tester), isNot(contains('Comptes utilisateurs')));
    });

    test('MUTATION : un masquage par nom de rôle remis ferait rougir ce '
        'fichier (la source n’en porte plus la trace)', () {
      final source = File(
        'lib/core/'
        'navigation/navigation_tatacora.dart',
      ).readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      expect(source, isNot(contains('nomsMasquesParRole')));
      expect(source, isNot(contains('entreeMasqueePourRole')));
    });

    test(
      'MUTATION de droit : retirer M10 au gérant lui retire Comptabilité',
      () {
        final sans = GardeAcces.depuisJson({...matrice['gerant']!, 'M10': '-'});
        final d = toutesLesDestinations.singleWhere(
          (x) => x.nom == 'Comptabilité',
        );
        expect(destinationVisible(d, droits: sans, role: 'gerant'), isFalse);
        final avec = GardeAcces.depuisJson(matrice['gerant']!);
        expect(destinationVisible(d, droits: avec, role: 'gerant'), isTrue);
      },
    );
  });

  group('la barre se reconstruit quand les droits de la session changent', () {
    const entrees = [
      'Véhicules & Locations',
      'Tourisme',
      'Comptabilité',
      'Personnel & Paie',
      'Congés & Plannings',
    ];
    const retires = {'M8': '-', 'M9': '-', 'M10': '-', 'M13': '-'};
    const rendus = {'M8': 'C', 'M9': 'C', 'M10': 'C', 'M13': 'C'};

    Session gerant(Map<String, String> surcharge) => Session(
      utilisateurId: 'u-gerard',
      login: 'gerard',
      nom: 'GERARD',
      role: 'gerant',
      droits: GardeAcces.depuisJson({
        ..._matriceDuSeeder()['gerant']!,
        ...surcharge,
      }),
    );

    testWidgets('la barre lit la session EN DIRECT : un gérant connecté dont '
        'M8/M9/M10/M13 passent de « - » à « C » voit les entrées apparaître '
        'puis disparaître, sans reconnexion', (tester) async {
      tester.view
        ..physicalSize = const Size(1600, 1500)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final base = AppDatabase.enMemoire();
      addTearDown(base.close);
      final routeur = GoRouter(
        initialLocation: '/tableau-de-bord',
        routes: [
          for (final r in {
            '/tableau-de-bord',
            for (final d in toutesLesDestinations)
              if (d.route != null) d.route!,
          })
            GoRoute(
              path: r,
              builder: (_, state) => CoquilleApplication(
                routeActive: state.uri.path,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      );
      addTearDown(routeur.dispose);
      late ProviderContainer c;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(base),
            sessionProvider.overrideWithBuild(
              (ref, notifier) => ref.watch(_sessionPosee),
            ),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return MaterialApp.router(
                theme: AppTheme.clair,
                routerConfig: routeur,
              );
            },
          ),
        ),
      );
      void poser(Session s) => c.read(_sessionPosee.notifier).state = s;

      poser(gerant(retires));
      await tester.pumpAndSettle();
      for (final nom in entrees) {
        expect(find.text(nom), findsNothing, reason: '$nom visible à tort');
      }

      poser(gerant(rendus)); // la session relue après la descente du rôle
      await tester.pumpAndSettle();
      for (final nom in entrees) {
        expect(find.text(nom), findsOneWidget, reason: '$nom doit apparaître');
      }
      expect(c.read(sessionProvider)!.login, 'gerard', reason: 'même session');

      poser(gerant(retires));
      await tester.pumpAndSettle();
      for (final nom in entrees) {
        expect(find.text(nom), findsNothing, reason: '$nom doit disparaître');
      }
    });

    test('la descente du rôle modifié recopie M8/M9/M10/M13 sur le compte et '
        'la session OUVERTE les relit (roles_local → utilisateurs_local → '
        'session), sans reconnexion', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final base = AppDatabase.enMemoire();
      final c = ProviderContainer(
        overrides: [baseLocaleProvider.overrideWithValue(base)],
      );
      addTearDown(() async {
        c.dispose();
        await base.close();
      });
      await RolesDao(base).installerSocle();
      final role = (await RolesDao(base).parLibelle('gerant'))!;
      await RolesDao(base).inscrireDescendu(
        id: role.id,
        libelle: 'gerant',
        description: null,
        droits: retires,
      );
      await SessionRepositoryLocal(base).creerCompte(
        login: 'gerard',
        nom: 'GERARD',
        motDePasse: 'Secret-Gerard-9',
        role: 'gerant',
        droits: {..._matriceDuSeeder()['gerant']!, ...retires},
      );
      await c
          .read(sessionProvider.notifier)
          .connecter('gerard', 'Secret-Gerard-9');
      expect(
        c.read(droitsProvider).peutLire(ModuleTatacora.m10Comptabilite),
        isFalse,
      );
      expect(c.read(droitsProvider).peutLire(ModuleTatacora.m13Rh), isFalse);

      await RolesDao(base).inscrireDescendu(
        id: role.id,
        libelle: 'gerant',
        description: null,
        droits: rendus,
      );
      await c.read(sessionProvider.notifier).relireDroitsSiChange();

      final droits = c.read(droitsProvider);
      for (final m in [
        ModuleTatacora.m8Vehicules,
        ModuleTatacora.m9Tourisme,
        ModuleTatacora.m10Comptabilite,
        ModuleTatacora.m13Rh,
      ]) {
        expect(droits.peutEcrire(m), isTrue, reason: '$m');
      }
      expect(c.read(sessionProvider)!.login, 'gerard');
    });
  });
}

/// La session que le test pose à la main — l'état réel d'un poste, sans base ni réseau.
final _sessionPosee = StateProvider<Session?>((ref) => null);
