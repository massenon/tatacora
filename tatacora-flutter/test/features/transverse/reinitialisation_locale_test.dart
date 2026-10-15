import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';
import 'package:tatacora_flutter/features/transverse/data/reinitialisation_locale.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// « Réinitialiser comme neuf » sur la base locale (D429, 14/10/2026) : ce qui
/// est gardé reste PLEIN, ce qui est vidé est VIDE, les triggers RG-11 sont
/// recréés, et chaque verrou refuse sans rien écrire.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
  });
  tearDown(() => db.close());

  Future<int> compter(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM "$table"').getSingle())
              .data['n']
          as int;

  Future<int> declencheurs() async =>
      (await db
                  .customSelect(
                    "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'trigger' "
                    "AND name LIKE 'rg11_%'",
                  )
                  .getSingle())
              .data['n']
          as int;

  Future<void> ouvrirBascule() => ParametresDao(
    db,
  ).ecrire({OptionsSysteme.cleReinitialisationSeeders: '1'}, auteurId: null);

  Future<void> piece() async {
    final restaurant = (await ComptabiliteDao(
      db,
    ).centreParLibelle('Restaurant'))!.id;
    await moteurSur(db).passerEtValider(
      DemandePiece(
        journal: 'VTE',
        date: '2031-03-04',
        libelle: 'Vente comptoir',
        lignes: [
          LigneDemandee(compte: '5711', debitCentimes: 10000),
          LigneDemandee(
            compte: '7061',
            creditCentimes: 10000,
            centreId: restaurant,
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
  }

  /// Un jeu d'exploitation : une pièce VALIDÉE (protégée par RG-11), un
  /// client, une chambre occupée, les rôles du socle.
  Future<void> semer() async {
    await piece();
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01 00 00 00 01', 'particulier')",
    );
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT INTO unites_hebergement_local (id, categorie_id, numero, statut) '
      "VALUES ('u-1', 'cat-1', 'BNG-01', 'occupee')",
    );
    await RolesDao(db).installerSocle();
  }

  test('administrateur, bascule ouverte : les tables vidées sont VIDES, les '
      'gardées PLEINES, les triggers RG-11 recréés et actifs', () async {
    await semer();
    await ouvrirBascule();
    expect(await compter('ecritures_local'), greaterThan(0));
    expect(await declencheurs(), 4);

    final moteur = ReinitialisationLocale(db);
    final effacables = await moteur.tablesEffacables();
    expect(effacables, containsAll(['ecritures_local', 'clients_local']));
    expect(effacables, isNot(contains('roles_local')));

    final bilan = await moteur.executer(role: 'administrateur');
    expect(bilan.tablesVidees, effacables.length);
    expect(bilan.lignesSupprimees, greaterThan(0));

    for (final t in effacables) {
      expect(await compter(t), 0, reason: t);
    }
    for (final t in [
      'utilisateurs_local',
      'roles_local',
      'parametres_systeme_local',
      'plan_comptable_local',
      'journaux_local',
      'exercices_local',
      'centres_cout_local',
      'categories_hebergement_local',
      'unites_hebergement_local',
    ]) {
      expect(await compter(t), greaterThan(0), reason: t);
    }
    final u = await db
        .customSelect('SELECT statut FROM unites_hebergement_local')
        .getSingle();
    expect(u.data['statut'], 'libre');

    // Les quatre gardes sont de RETOUR : une pièce validée passée après la
    // remise à neuf ne se supprime toujours pas.
    expect(await declencheurs(), 4);
    await piece();
    expect(await compter('ecritures_local'), greaterThan(0));
    await expectLater(
      db.customStatement('DELETE FROM ecritures_local'),
      throwsA(anything),
    );
  });

  test(
    'refus : bascule fermée, rôle hors administration — RIEN écrit',
    () async {
      await semer();
      final moteur = ReinitialisationLocale(db);
      final avant = await compter('ecritures_local');

      await expectLater(
        moteur.executer(role: 'administrateur'),
        throwsA(
          isA<ReinitialisationRefusee>().having(
            (e) => e.message,
            'message',
            RefusReinitialisation.bascule,
          ),
        ),
      );
      await ouvrirBascule();
      for (final role in ['gerant', 'barman', null]) {
        await expectLater(
          moteur.executer(role: role),
          throwsA(
            isA<ReinitialisationRefusee>().having(
              (e) => e.message,
              'message',
              RefusReinitialisation.role,
            ),
          ),
          reason: '$role',
        );
      }
      expect(await compter('ecritures_local'), avant);
      expect(await compter('clients_local'), 1);
      expect(await declencheurs(), 4);
      expect(ReinitialisationLocale.estPermisA('super_admin'), isTrue);
    },
  );

  testWidgets('sans le mot « VIDER », « Vider définitivement » ne vide rien', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await semer();
      await ouvrirBascule();
    });
    tester.view
      ..physicalSize = const Size(1600, 2400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final droits = GardeAcces.depuisJson(const {'PARAM': 'C', 'ROLES': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(droits),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'admin',
              nom: 'Admin',
              role: 'administrateur',
              droits: droits,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranImportExport()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ie-onglet-seeders')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    final bouton = find.byKey(const Key('ie-seeders-bouton'));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ie-seeders-modale')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ie-seeders-saisie')), 'VIDE');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ie-seeders-confirmer')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('ie-seeders-modale')), findsOneWidget);
    final clients = await tester.runAsync(() => compter('clients_local'));
    expect(clients, 1);
  });
}
