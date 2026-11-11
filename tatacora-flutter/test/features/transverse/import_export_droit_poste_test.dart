import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart'
    show cheminConfigurationPosteProvider;
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_roles_permissions.dart';

import 'support/outils_import.dart';

/// 11/11/2026 (PO) : le CRUD d'« Import & Export » est piloté par le droit `IMPORT_EXPORT`
/// (modifiable à l'écran Rôles & Permissions), pas par `Paramètres` ni par un nom de rôle :
/// `C` (gérant, comptable) agit ; `L` (barman) voit la page en lecture seule ; un droit passé de
/// `C` à `L` change la page à la descente du rôle, sans reconnexion.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() async => db = await baseImport());
  tearDown(() async => db.close());

  Session session(String role, Map<String, String> droits) => Session(
    utilisateurId: 'u-$role',
    login: role,
    nom: role,
    role: role,
    droits: GardeAcces.depuisJson(droits),
  );

  // Les droits SOCLE du poste (réplique de la matrice du seeder), jamais une carte écrite ici.
  Map<String, String> socle(String role) => socleRbacCdcf[role]!;

  Future<ProviderContainer> monter(WidgetTester tester, Session debut) async {
    tester.view
      ..physicalSize = const Size(1600, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final posee = StateProvider<Session?>((ref) => debut);
    late ProviderContainer c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => '/inexistant/poste.json',
          ),
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild((ref, n) => ref.watch(posee)),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            c = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.clair,
              home: const Scaffold(body: EcranImportExport()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    _posee = posee;
    return c;
  }

  for (final role in const ['gerant', 'comptable']) {
    testWidgets('$role (IMPORT_EXPORT = C au socle) : import, sauvegardes et '
        'restauration sont offerts', (tester) async {
      expect(socle(role)['IMPORT_EXPORT'], 'C');
      await monter(tester, session(role, socle(role)));
      expect(find.byKey(const Key('ie-onglet-importer')), findsOneWidget);
      expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsOneWidget);
      expect(find.byKey(const Key('ie-onglet-restaurer')), findsOneWidget);
      expect(find.byKey(const Key('ie-modele')), findsOneWidget);
    });
  }

  // 11/11/2026 (PO) : les utilisateurs SYSTÈME ont TOUJOURS l'accès complet, même sans RBAC. La
  // session est bâtie par le dépôt local (le chemin réel : ligne `utilisateurs_local`), pas à la main.
  for (final role in const ['administrateur', 'super_admin']) {
    for (final ligne in const ['absente', '-', 'L']) {
      testWidgets('$role, ligne IMPORT_EXPORT $ligne : trois onglets et '
          'tous les gestes', (tester) async {
        FlutterSecureStorage.setMockInitialValues({});
        final droits = {...socle(role)};
        if (ligne == 'absente') {
          droits.remove('IMPORT_EXPORT');
        } else {
          droits['IMPORT_EXPORT'] = ligne;
        }
        final depot = SessionRepositoryLocal(db);
        final Session connectee = (await tester.runAsync(() async {
          await depot.creerCompte(
            login: 'sys-$role',
            nom: 'Système',
            motDePasse: 'motdepasse123',
            role: role,
            droits: droits,
          );
          return depot.connecter('sys-$role', 'motdepasse123');
        }))!;
        expect(
          connectee.droits.peutEcrire(ModuleTatacora.importExport),
          isTrue,
        );
        await monter(tester, connectee);
        expect(find.byKey(const Key('ie-onglet-importer')), findsOneWidget);
        expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsOneWidget);
        expect(find.byKey(const Key('ie-onglet-restaurer')), findsOneWidget);
        expect(find.byKey(const Key('ie-modele')), findsOneWidget);
      });
    }
  }

  testWidgets('le gérant dont la ligne est à L reste en lecture seule (le '
      'droit implicite ne le concerne pas)', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final depot = SessionRepositoryLocal(db);
    final Session connectee = (await tester.runAsync(() async {
      await depot.creerCompte(
        login: 'g1',
        nom: 'Gérant',
        motDePasse: 'motdepasse123',
        role: 'gerant',
        droits: {...socle('gerant'), 'IMPORT_EXPORT': 'L'},
      );
      return depot.connecter('g1', 'motdepasse123');
    }))!;
    await monter(tester, connectee);
    expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsNothing);
    expect(find.byKey(const Key('ie-modele')), findsNothing);
  });

  mainRolesEnLecture();

  testWidgets('barman (IMPORT_EXPORT = L au socle) : la page est en lecture '
      'seule, sans onglet de sauvegarde ni geste d\'import', (tester) async {
    expect(socle('barman')['IMPORT_EXPORT'], 'L');
    await monter(tester, session('barman', socle('barman')));
    expect(find.byKey(const Key('ie-onglet-importer')), findsOneWidget);
    expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsNothing);
    expect(find.byKey(const Key('ie-onglet-restaurer')), findsNothing);
    expect(find.byKey(const Key('ie-modele')), findsNothing);
  });

  testWidgets('le droit du gérant passe de C à L (descente du rôle) : la page '
      'devient lecture seule SANS reconnexion, puis revient', (tester) async {
    final c = await monter(tester, session('gerant', socle('gerant')));
    expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsOneWidget);

    c.read(_posee.notifier).state = session('gerant', {
      ...socle('gerant'),
      'IMPORT_EXPORT': 'L',
    });
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsNothing);
    expect(find.byKey(const Key('ie-modele')), findsNothing);

    c.read(_posee.notifier).state = session('gerant', socle('gerant'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ie-onglet-sauvegardes')), findsOneWidget);
  });
}

late StateProvider<Session?> _posee;

/// « Rôles & Permissions » s'ouvre au gérant et au comptable en LECTURE SEULE (ROLES = L au
/// socle) : aucune erreur, aucun bouton de création ni de rétablissement du socle.
void mainRolesEnLecture() {
  for (final role in const ['gerant', 'comptable']) {
    testWidgets('$role : Rôles & Permissions en lecture seule (ROLES = L)', (
      tester,
    ) async {
      expect(socleRbacCdcf[role]!['ROLES'], 'L');
      final base = AppDatabase.enMemoire();
      addTearDown(base.close);
      final droits = GardeAcces.depuisJson(socleRbacCdcf[role]!);
      tester.view
        ..physicalSize = const Size(1600, 2400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(base),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-$role',
                login: role,
                nom: role,
                role: role,
                droits: droits,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranRolesPermissions()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('roles-nouveau')), findsNothing);
      expect(find.byKey(const Key('roles-retablir-socle')), findsNothing);
    });
  }
}
