import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
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
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/journal_securite_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/domain/journal_poste.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/presentation/widgets/modales_comptes.dart';

/// SUPPRIMER UN COMPTE UTILISATEUR, au poste (03/11/2026, décision du PO) : le
/// geste, l'autorité, la file d'envoi, la descente et l'écran. Sur une base réelle
/// en mémoire ; les phrases de refus sont RELUES de `lang/fr/pwa.php` du serveur.
///
/// Les tests de MUTATION de la règle d'autorité sont ici : un non super_admin ne
/// supprime pas, un administrateur n'est pas supprimable, on ne se supprime pas
/// soi-même.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptesUtilisateursDao dao;
  final jour = DateTime(2026, 11, 3, 9);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.enMemoire();
    dao = ComptesUtilisateursDao(db, horloge: () => jour);
    await RolesDao(db).installerSocle();
  });
  tearDown(() => db.close());

  Future<void> poser(String id, String role, {bool actif = true}) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: 'Nom $id',
          role: role,
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
          actif: Value(actif),
        ),
      );

  Future<UtilisateurLocal> ligne(String id) => (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(id))).getSingle();

  Future<String> refus(Future<Object?> geste) async {
    try {
      await geste;
    } on RefusComptes catch (e) {
      return e.message;
    }
    fail('aucun refus');
  }

  /// Les phrases du SERVEUR : `lang/fr/pwa.php`, groupe `comptes`.
  String phraseDuServeur(String cle) {
    final source = File('../tatacora-api/lang/fr/pwa.php').readAsStringSync();
    final debut = source.indexOf("'comptes' => [");
    final fin = source.indexOf("'changement_mdp' => [");
    final bloc = source.substring(debut, fin);
    final m = RegExp(
      "'$cle' => ((?:'(?:[^'\\\\]|\\\\.)*'(?:\\s*\\.\\s*)?\\s*)+),",
      dotAll: true,
    ).firstMatch(bloc);
    expect(m, isNotNull, reason: cle);
    return RegExp("'((?:[^'\\\\]|\\\\.)*)'")
        .allMatches(m!.group(1)!)
        .map((x) => x.group(1)!.replaceAll("\\'", "'"))
        .join();
  }

  group('le geste', () {
    test('un super administrateur supprime un compte non administrateur : '
        'LOGIQUE, désactivé, hors liste, tracé, et la charge de file ne porte '
        'que le login', () async {
      await poser('sa', 'super_admin');
      await poser('barman1', 'barman');
      await poser('gerant1', 'gerant');

      await dao.supprimerCompte(auteurId: 'sa', compteId: 'barman1');

      final u = await ligne('barman1');
      expect(u.supprimeLe, jour, reason: 'la ligne RESTE, datée');
      expect(u.actif, isFalse);
      expect(
        (await dao.comptes()).map((c) => c.identifiant),
        unorderedEquals(['sa', 'gerant1']),
        reason: 'disparu des listes',
      );

      // La trace : qui, quel login, quand — jamais un secret.
      final trace = (await JournalSecuriteDao(db).entrees()).single;
      expect(trace.action, ActionJournalPoste.compteSupprime.code);
      expect((trace.auteurLogin, trace.cibleLogin), ('sa', 'barman1'));
      expect(trace.cibleId, 'barman1');

      // La file : une `suppression` de la table des comptes, par le LOGIN.
      final file = await OperationsSyncDao(db).operations();
      expect(file, hasLength(1));
      expect(file.single.type, TypeOperationSync.suppression);
      expect(file.single.table, TableSynchronisee.utilisateurs);
      final charge = jsonDecode(file.single.payload) as Map<String, Object?>;
      expect(charge, {'login': 'barman1', 'supprime_par': 'sa'});
      expect(jsonEncode(charge), isNot(contains('empreinte')));
      expect(jsonEncode(charge), isNot(contains('sel')));
    });

    test(
      'un compte supprimé ne se connecte plus (le vrai dépôt de session)',
      () async {
        await poser('sa', 'super_admin');
        final depot = SessionRepositoryLocal(db, horloge: () => jour);
        final id = await dao.creerCompte(
          auteurId: 'sa',
          nom: 'Barman',
          identifiant: 'b.kora',
          role: 'barman',
          motDePasse: 'motdepasse1',
          confirmation: 'motdepasse1',
        );
        // Preuve que la connexion marche AVANT (sinon le refus serait vide).
        expect(
          (await depot.connecter('b.kora', 'motdepasse1')).login,
          'b.kora',
        );

        await dao.supprimerCompte(auteurId: 'sa', compteId: id);

        await expectLater(
          depot.connecter('b.kora', 'motdepasse1'),
          throwsA(isA<EchecConnexion>()),
        );
        expect(
          await depot.verifierMotDePasse('b.kora', 'motdepasse1'),
          isFalse,
        );
        // L'identifiant n'est PAS réutilisable.
        expect(
          (await refus(
            dao.creerCompte(
              auteurId: 'sa',
              nom: 'Autre',
              identifiant: 'b.kora',
              role: 'barman',
              motDePasse: 'motdepasse2',
              confirmation: 'motdepasse2',
            ),
          )),
          MessagesComptes.identifiantPris('b.kora'),
        );
        // Et aucun autre geste ne le retrouve (désactiver, réactiver, réinitialiser).
        expect(
          await refus(
            dao.definirActif(auteurId: 'sa', compteId: id, actif: true),
          ),
          MessagesComptes.compteIntrouvable,
        );
        expect(
          await refus(
            dao.reinitialiserParAdministrateur(auteurId: 'sa', compteId: id),
          ),
          MessagesComptes.compteIntrouvable,
        );
      },
    );

    test('MUTATION — un non super administrateur ne supprime pas', () async {
      await poser('cible', 'barman');
      for (final role in ['administrateur', 'gerant', 'barman', 'comptable']) {
        await poser('auteur-$role', role);
        expect(
          await refus(
            dao.supprimerCompte(auteurId: 'auteur-$role', compteId: 'cible'),
          ),
          role == 'administrateur'
              ? MessagesComptes.refusSuppressionDroit
              : MessagesComptes.refusSuppressionDroit,
          reason: role,
        );
      }
      expect((await ligne('cible')).supprimeLe, isNull);
      expect(await OperationsSyncDao(db).operations(), isEmpty);
      expect(await JournalSecuriteDao(db).entrees(), isEmpty);
    });

    test(
      'MUTATION — un administrateur ou un super administrateur n’est pas '
      'supprimable ; on ne se supprime pas soi-même ; compte inconnu',
      () async {
        await poser('sa', 'super_admin');
        await poser('sa2', 'super_admin');
        await poser('adm', 'administrateur');
        for (final cible in ['sa2', 'adm']) {
          expect(
            await refus(dao.supprimerCompte(auteurId: 'sa', compteId: cible)),
            MessagesComptes.refusSuppressionAdministrateur,
            reason: cible,
          );
          expect((await ligne(cible)).supprimeLe, isNull);
        }
        expect(
          await refus(dao.supprimerCompte(auteurId: 'sa', compteId: 'sa')),
          MessagesComptes.refusSuppressionSoiMeme,
        );
        expect(
          await refus(dao.supprimerCompte(auteurId: 'sa', compteId: 'zzz')),
          MessagesComptes.compteIntrouvable,
        );
        expect(await OperationsSyncDao(db).operations(), isEmpty);
      },
    );

    test('un auteur désactivé ou supprimé ne supprime rien', () async {
      await poser('sa', 'super_admin', actif: false);
      await poser('cible', 'barman');
      expect(
        await refus(dao.supprimerCompte(auteurId: 'sa', compteId: 'cible')),
        MessagesComptes.refusDroit,
      );
    });

    test('les phrases sont celles du SERVEUR (relues de lang/fr/pwa.php)', () {
      expect(
        MessagesComptes.refusSuppressionDroit,
        phraseDuServeur('refus_suppression_droit'),
      );
      expect(
        MessagesComptes.refusSuppressionSoiMeme,
        phraseDuServeur('refus_suppression_soi_meme'),
      );
      expect(
        MessagesComptes.refusSuppressionAdministrateur,
        phraseDuServeur('refus_suppression_administrateur'),
      );
      expect(
        TextesModalesComptes.supprimerTitre('LOGIN'),
        phraseDuServeur('supprimer_titre').replaceAll(':login', 'LOGIN'),
      );
      expect(
        TextesModalesComptes.supprimerTexte,
        phraseDuServeur('supprimer_texte'),
      );
      expect(
        TextesModalesComptes.supprimerConfirmer,
        phraseDuServeur('supprimer_confirmer'),
      );
      expect(TextesComptes.supprimer, phraseDuServeur('supprimer'));
      expect(
        MessagesComptes.auteurSupprime('LOGIN'),
        phraseDuServeur('auteur_supprime').replaceAll(':login', 'LOGIN'),
      );
      expect(
        MessagesComptes.compteSupprime('LOGIN'),
        phraseDuServeur('supprime_succes').replaceAll(':login', 'LOGIN'),
      );
    });

    test('le serveur ET le poste écrivent la règle d’autorité de la même '
        'façon : seul super_admin supprime, seuls les non-administrateurs '
        'sont supprimables', () {
      expect(peutSupprimerDesComptes('super_admin'), isTrue);
      expect(peutSupprimerDesComptes('Super Admin'), isTrue);
      expect(peutSupprimerDesComptes('administrateur'), isFalse);
      expect(peutSupprimerDesComptes('gerant'), isFalse);
      expect(peutSupprimerDesComptes(null), isFalse);
      expect(compteSupprimable('barman'), isTrue);
      expect(compteSupprimable('gerant'), isTrue);
      expect(compteSupprimable('administrateur'), isFalse);
      expect(compteSupprimable('super_admin'), isFalse);
      // La règle serveur, relue du PHP : un seul super administrateur supprime.
      final user = File(
        '../tatacora-api/app/Models/User.php',
      ).readAsStringSync();
      expect(user, contains('function peutSupprimerDesComptes'));
      expect(user, contains('\$this->estSuperAdmin()'));
      expect(user, contains('! \$this->estAdministrateur()'));
    });

    test('un SEUL écrivain enfile la suppression d’un compte : le DAO des '
        'comptes (balayage de lib/, plancher non vide)', () {
      final ecrivains = <String>[];
      var balayes = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        balayes++;
        final code = f.readAsStringSync();
        if (code.contains('.enfiler(') &&
            code.contains('TableSynchronisee.utilisateurs')) {
          ecrivains.add(f.path.replaceAll('\\\\', '/'));
        }
      }
      expect(balayes, greaterThan(200), reason: 'balayage non vide');
      expect(ecrivains.toSet(), {
        'lib/features/transverse/data/comptes_utilisateurs_dao.dart',
      });
    });
  });

  group('la descente : un compte supprimé au serveur', () {
    Future<IssueAlignement> descendre({
      String login = 'barman1',
      Object? quand = '2026-11-03 08:00:00',
      Map<String, Object?>? donnees,
    }) => db.transaction(
      () =>
          AligneurCatalogue(
            db,
            DescenteCatalogueDao(db),
            auteur: () async => null,
            maintenant: () => jour,
          ).aligner(
            ElementCatalogue(
              table: TableDescendue.utilisateurs,
              id: 'id-serveur-sans-rapport',
              actif: false,
              modifieLe: '2026-11-03 08:00:00',
              donnees: donnees ?? {'login': login, 'supprime_le': quand},
            ),
          ),
    );

    test('le compte local de même LOGIN est marqué supprimé et désactivé — '
        'sans rien enfiler, sans toucher au mot de passe', () async {
      await poser('barman1', 'barman');
      final avant = await ligne('barman1');

      expect(await descendre(), isA<Aligne>());

      final apres = await ligne('barman1');
      expect(apres.supprimeLe, DateTime.utc(2026, 11, 3, 8).toLocal());
      expect(apres.actif, isFalse);
      // Rien d'autre n'a bougé.
      expect(
        (apres.sel, apres.empreinte, apres.iterations, apres.role, apres.nom),
        (avant.sel, avant.empreinte, avant.iterations, avant.role, avant.nom),
      );
      expect(await OperationsSyncDao(db).operations(), isEmpty);
      final trace = (await JournalSecuriteDao(db).entrees()).single;
      expect(trace.action, ActionJournalPoste.compteSupprime.code);
      expect(trace.cibleLogin, 'barman1');
      expect(trace.auteurLogin, isNull, reason: 'la décision vient du serveur');
      expect((await dao.comptes()), isEmpty);
    });

    test('jamais de création : un login inconnu de ce poste ne crée rien, et '
        'le rejeu est un no-op', () async {
      await poser('autre', 'barman');
      expect(await descendre(login: 'inconnu'), isA<Aligne>());
      expect(
        (await db.select(db.utilisateursLocal).get()).map((u) => u.login),
        ['autre'],
      );

      await poser('barman1', 'barman');
      await descendre();
      final premiere = (await ligne('barman1')).supprimeLe;
      await descendre(quand: '2027-01-01 00:00:00');
      expect(
        (await ligne('barman1')).supprimeLe,
        premiere,
        reason: 'idempotent',
      );
      expect(await JournalSecuriteDao(db).entrees(), hasLength(1));
    });

    test(
      'un homonyme ADMINISTRATEUR local n’est jamais supprimé : refus lisible',
      () async {
        await poser('adm', 'administrateur');
        final issue = await descendre(login: 'adm');
        expect(issue, isA<RefuseParLePoste>());
        expect((issue as RefuseParLePoste).motif, contains('désactive'));
        expect((await ligne('adm')).supprimeLe, isNull);
        expect((await ligne('adm')).actif, isTrue);
      },
    );

    test(
      'une date illisible ou un login absent sont refusés, rien n’est écrit',
      () async {
        await poser('barman1', 'barman');
        expect(await descendre(quand: 'pas une date'), isA<RefuseParLePoste>());
        expect(
          await descendre(donnees: {'supprime_le': '2026-11-03 08:00:00'}),
          isA<RefuseParLePoste>(),
        );
        expect((await ligne('barman1')).supprimeLe, isNull);
      },
    );

    test(
      'l’élément du flux ne porte QUE login et supprime_le (parse du JSON)',
      () {
        final e = ElementCatalogue.depuisJson({
          'table': 'utilisateurs',
          'id': 'u-1',
          'actif': false,
          'modifie_le': '2026-11-03 08:00:00',
          'donnees': {'login': 'barman1', 'supprime_le': '2026-11-03 08:00:00'},
        });
        expect(e?.table, TableDescendue.utilisateurs);
        expect(e?.donnees.keys, ['login', 'supprime_le']);
      },
    );
  });

  group('l’écran', () {
    Future<void> monter(
      WidgetTester tester, {
      required String id,
      required String role,
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
                utilisateurId: id,
                login: id,
                nom: 'Nom $id',
                role: role,
                droits: GardeAcces.depuisJson(socleRbacCdcf['administrateur']!),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranComptesUtilisateurs()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('« Supprimer » : seulement pour un super administrateur, sur '
        'un compte non administrateur, jamais sur sa ligne', (tester) async {
      await poser('sa', 'super_admin');
      await poser('adm', 'administrateur');
      await poser('barman1', 'barman');
      await monter(tester, id: 'sa', role: 'super_admin');

      expect(
        find.byKey(const Key('comptes-supprimer-barman1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('comptes-supprimer-adm')), findsNothing);
      expect(find.byKey(const Key('comptes-supprimer-sa')), findsNothing);
      // À côté de « Désactiver ».
      expect(find.byKey(const Key('comptes-basculer-barman1')), findsOneWidget);
    });

    testWidgets(
      'MUTATION — un administrateur ne voit aucun bouton « Supprimer »',
      (tester) async {
        await poser('adm', 'administrateur');
        await poser('barman1', 'barman');
        await monter(tester, id: 'adm', role: 'administrateur');

        expect(
          find.byKey(const Key('comptes-basculer-barman1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('comptes-supprimer-barman1')),
          findsNothing,
        );
      },
    );

    testWidgets('la confirmation dit la phrase du PO, puis le compte disparaît '
        'de la liste', (tester) async {
      await poser('sa', 'super_admin');
      await poser('barman1', 'barman');
      await monter(tester, id: 'sa', role: 'super_admin');

      await tester.tap(find.byKey(const Key('comptes-supprimer-barman1')));
      await tester.pumpAndSettle();
      expect(find.text('Supprimer le compte « barman1 » ?'), findsOneWidget);
      expect(
        find.text(
          "Il ne pourra plus se connecter. Ce qu'il a saisi garde son nom.",
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('comptes-supprimer-confirmer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('comptes-nom-barman1')), findsNothing);
      expect(find.byKey(const Key('comptes-succes')), findsOneWidget);
      expect((await ligne('barman1')).supprimeLe, isNotNull);
    });

    testWidgets('annuler ne supprime rien', (tester) async {
      await poser('sa', 'super_admin');
      await poser('barman1', 'barman');
      await monter(tester, id: 'sa', role: 'super_admin');

      await tester.tap(find.byKey(const Key('comptes-supprimer-barman1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comptes-modale-annuler')));
      await tester.pumpAndSettle();
      expect((await ligne('barman1')).supprimeLe, isNull);
      expect(find.byKey(const Key('comptes-nom-barman1')), findsOneWidget);
    });
  });
}
