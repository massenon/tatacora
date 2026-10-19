import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable, driftRuntimeOptions;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session_repository.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';

/// `ComptesUtilisateursDao` (Lot J2, 14/10/2026) : un administrateur crée,
/// désactive, réactive et réinitialise — et la preuve de chaque geste est la
/// CONNEXION par le vrai `SessionRepositoryLocal`, pas une colonne relue. Un
/// compte dont le dérivé serait faux (mot de passe en clair, hachage sauté)
/// aurait une ligne parfaitement plausible et n'ouvrirait jamais.
///
/// Les auteurs des gestes sont posés en SQL direct (dérivé factice) : ils
/// n'ont pas à se connecter, et 120 000 tours de PBKDF2 par auteur
/// allongeraient la suite pour rien. Les comptes qui se connectent passent
/// par le DAO.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptesUtilisateursDao dao;
  late SessionRepositoryLocal depot;

  final jour = DateTime(2026, 10, 14, 9);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.enMemoire();
    dao = ComptesUtilisateursDao(db, horloge: () => jour);
    depot = SessionRepositoryLocal(db);
    await RolesDao(db).installerSocle();
  });
  tearDown(() => db.close());

  /// Un auteur (ou un compte) posé en SQL direct, sans dérivé réel.
  Future<void> poser(String id, String role, {bool actif = true}) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: id.toUpperCase(),
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

  Future<int> lignes() async =>
      (await db
                  .customSelect('SELECT COUNT(*) AS n FROM utilisateurs_local')
                  .getSingle())
              .data['n']
          as int;

  Future<UtilisateurLocal> ligne(String id) => (db.select(
    db.utilisateursLocal,
  )..where((u) => u.id.equals(id))).getSingle();

  Future<Map<String, String>> refus(Future<Object?> geste) async {
    try {
      await geste;
    } on RefusComptes catch (e) {
      return e.erreurs;
    }
    fail('aucun refus');
  }

  Future<String> creer({
    String auteur = 'admin',
    String nom = 'KORA Jean',
    String identifiant = 'j.kora',
    String? role = 'barman',
    String motDePasse = 'comptoir2026',
    String? confirmation,
  }) => dao.creerCompte(
    auteurId: auteur,
    nom: nom,
    identifiant: identifiant,
    role: role,
    motDePasse: motDePasse,
    confirmation: confirmation ?? motDePasse,
  );

  Future<bool> seConnecte(String login, String motDePasse) async {
    try {
      await depot.connecter(login, motDePasse);
      return true;
    } on EchecConnexion catch (e) {
      // Le refus reste le message UNIQUE de la connexion (PA-103).
      expect(e.message, SessionRepositoryLocal.refusIdentifiants);
      return false;
    }
  }

  group('Création', () {
    test('le compte créé SE CONNECTE par SessionRepositoryLocal ; un mauvais '
        'mot de passe est refusé ; il porte les droits de son rôle', () async {
      await poser('admin', 'administrateur');
      final id = await creer(identifiant: '  J.Kora ');

      final u = await ligne(id);
      expect(u.login, 'j.kora', reason: 'identifiant normalisé en minuscules');
      expect(u.role, 'barman');
      expect(u.actif, isTrue);
      expect(u.dateCreation, jour);

      // Droits RECOPIÉS du rôle, à l'identique.
      final role = await (db.select(
        db.rolesLocal,
      )..where((r) => r.libelle.equals('barman'))).getSingle();
      expect(jsonDecode(u.droitsJson), jsonDecode(role.droitsJson));
      expect(jsonDecode(u.droitsJson), isNotEmpty);

      // La preuve : la connexion réelle.
      final session = await depot.connecter('J.KORA', 'comptoir2026');
      expect(session.utilisateurId, id);
      expect(session.role, 'barman');
      final niveaux = (jsonDecode(role.droitsJson) as Map)
          .cast<String, String>();
      expect(
        session.droits.peutLire(ModuleTatacora.m5Bar),
        niveaux['M5'] != '-',
      );
      expect(niveaux['M5'], isNot('-'), reason: 'un barman lit le bar');
      expect(await seConnecte('j.kora', 'comptoir2027'), isFalse);
    });

    test('le mot de passe n’est écrit NULLE PART dans la ligne', () async {
      await poser('admin', 'administrateur');
      final id = await creer(motDePasse: 'secretGite99');
      final brut = await db
          .customSelect(
            'SELECT * FROM utilisateurs_local WHERE id = ?',
            variables: [Variable.withString(id)],
          )
          .getSingle();
      for (final e in brut.data.entries) {
        expect(
          '${e.value}'.contains('secretGite99'),
          isFalse,
          reason: 'colonne ${e.key}',
        );
      }
      final u = await ligne(id);
      expect(u.iterations, greaterThanOrEqualTo(100000));
      expect(u.sel, isNot(isEmpty));
    });

    test(
      'identifiant DÉJÀ PRIS (sans casse) : refusé, une seule ligne',
      () async {
        await poser('admin', 'administrateur');
        await creer(identifiant: 'barman1');
        final avant = await lignes();
        expect(await refus(creer(identifiant: ' BARMAN1 ', nom: 'Autre')), {
          'identifiant': MessagesComptes.identifiantPris('barman1'),
        });
        expect(await lignes(), avant);
      },
    );

    test('identifiant : vide, < 3, > 50, caractères hors [a-z0-9._-] — '
        'refusés ; 3 et 50 caractères acceptés', () async {
      await poser('admin', 'administrateur');
      Future<String?> erreur(String identifiant) async =>
          (await refus(creer(identifiant: identifiant)))['identifiant'];

      expect(await erreur('   '), MessagesComptes.identifiantObligatoire);
      expect(await erreur('ab'), MessagesComptes.identifiantLongueur);
      expect(await erreur('a' * 51), MessagesComptes.identifiantLongueur);
      for (final mauvais in [
        'jean kora',
        'josé',
        '.kora',
        'kora@gite',
        '_x1',
      ]) {
        expect(
          await erreur(mauvais),
          MessagesComptes.identifiantFormat,
          reason: mauvais,
        );
      }
      expect(await lignes(), 1, reason: 'aucun refus n’écrit');

      await creer(identifiant: 'abc');
      final long = await creer(identifiant: 'a${'b' * 49}');
      expect((await ligne(long)).login, hasLength(50));
    });

    test('mot de passe < 8, confirmation différente, nom et rôle manquants : '
        'toutes les erreurs à la fois', () async {
      await poser('admin', 'administrateur');
      expect(
        await refus(
          creer(nom: ' ', role: null, motDePasse: 'court', confirmation: 'x'),
        ),
        {
          'nom': MessagesComptes.nomObligatoire,
          'role': MessagesComptes.roleObligatoire,
          'motDePasse': MessagesComptes.motDePasseCourt,
          'confirmation': MessagesComptes.confirmationDifferente,
        },
      );
      expect(await refus(creer(role: 'inexistant')), {
        'role': MessagesComptes.roleInconnu,
      });
      expect(await lignes(), 1);
    });

    test('auteur NON administrateur, ou administrateur DÉSACTIVÉ, ou '
        'inconnu : refusé, rien écrit', () async {
      await poser('gerant1', 'gerant');
      await poser('admin-off', 'administrateur', actif: false);
      for (final auteur in ['gerant1', 'admin-off', 'personne']) {
        expect(await refus(creer(auteur: auteur)), {
          'droit': MessagesComptes.refusDroit,
        }, reason: auteur);
      }
      expect(await lignes(), 2);
    });

    test('super_admin administre aussi (par son CODE)', () async {
      await poser('sa', 'super_admin');
      final id = await creer(
        auteur: 'sa',
        identifiant: 'recep1',
        role: 'receptionniste',
      );
      expect((await ligne(id)).role, 'receptionniste');
    });
  });

  group('Désactivation / réactivation', () {
    test('un compte désactivé NE SE CONNECTE PLUS ; réactivé, il se '
        'reconnecte ; la ligne reste en base', () async {
      await poser('admin', 'administrateur');
      final id = await creer();
      final avant = await lignes();

      await dao.definirActif(auteurId: 'admin', compteId: id, actif: false);
      expect((await ligne(id)).actif, isFalse);
      expect(await seConnecte('j.kora', 'comptoir2026'), isFalse);
      expect(await lignes(), avant, reason: 'jamais supprimé (RG-15)');
      expect(
        (await dao.comptes()).singleWhere((c) => c.id == id).actif,
        isFalse,
      );

      await dao.definirActif(auteurId: 'admin', compteId: id, actif: true);
      expect(await seConnecte('j.kora', 'comptoir2026'), isTrue);
      expect(await lignes(), avant);
    });

    test('un administrateur ne se désactive PAS lui-même (même s’il en reste '
        'un autre)', () async {
      await poser('admin', 'administrateur');
      await poser('admin2', 'administrateur');
      expect(
        await refus(
          dao.definirActif(auteurId: 'admin', compteId: 'admin', actif: false),
        ),
        {'compte': MessagesComptes.desactiverSoiMeme},
      );
      expect((await ligne('admin')).actif, isTrue);
    });

    test(
      'le DERNIER administrateur actif ne se désactive pas — et un '
      'administrateur peut en désactiver un autre tant qu’il en reste un',
      () async {
        await poser('admin', 'administrateur');
        await poser('sa', 'super_admin');
        // Seul administrateur actif du poste à l'issue : il reste « admin ».
        await dao.definirActif(auteurId: 'admin', compteId: 'sa', actif: false);
        expect((await ligne('sa')).actif, isFalse);

        // « admin » est désormais le dernier : sa désactivation est refusée,
        // quelle que soit la garde qui la refuse. ⚠ Éprouvé par mutation le
        // 15/10/2026 : la garde « dernier administrateur » SEULE est
        // inatteignable par l'API — l'auteur, relu actif et administrateur,
        // est toujours un « autre » administrateur actif, sauf quand il se
        // vise lui-même, cas que la garde « soi-même » refuse d'abord.
        // Retirer les DEUX gardes fait rougir ce cas ; la seconde seule, rien.
        final r = await refus(
          dao.definirActif(auteurId: 'admin', compteId: 'admin', actif: false),
        );
        expect(r.keys, ['compte']);
        expect(
          r['compte'],
          anyOf(
            MessagesComptes.desactiverSoiMeme,
            MessagesComptes.dernierAdministrateur,
          ),
        );
        expect((await ligne('admin')).actif, isTrue);
        // Il reste au moins un administrateur actif : le poste n'est jamais
        // fermé à l'administration.
        final actifs = (await dao.comptes()).where(
          (c) => c.actif && c.estAdministration,
        );
        expect(actifs, isNotEmpty);
      },
    );

    test('refus de droit sur la désactivation et un compte inconnu', () async {
      await poser('admin', 'administrateur');
      await poser('barman1', 'barman');
      expect(
        await refus(
          dao.definirActif(
            auteurId: 'barman1',
            compteId: 'admin',
            actif: false,
          ),
        ),
        {'droit': MessagesComptes.refusDroit},
      );
      expect(
        await refus(
          dao.definirActif(auteurId: 'admin', compteId: 'zzz', actif: false),
        ),
        {'compte': MessagesComptes.compteIntrouvable},
      );
      expect((await ligne('admin')).actif, isTrue);
    });
  });

  group('Réinitialisation du mot de passe', () {
    test('l’administrateur pose le nouveau : il ouvre, l’ancien n’ouvre plus ; '
        'identique à l’actuel : refusé', () async {
      await poser('admin', 'administrateur');
      final id = await creer();

      expect(
        await refus(
          dao.reinitialiserMotDePasse(
            auteurId: 'admin',
            compteId: id,
            nouveau: 'comptoir2026',
            confirmation: 'comptoir2026',
          ),
        ),
        {'motDePasse': MessagesComptes.motDePasseIdentique},
      );
      expect(
        await refus(
          dao.reinitialiserMotDePasse(
            auteurId: 'admin',
            compteId: id,
            nouveau: 'court',
            confirmation: 'autre',
          ),
        ),
        {
          'motDePasse': MessagesComptes.motDePasseCourt,
          'confirmation': MessagesComptes.confirmationDifferente,
        },
      );
      expect(await seConnecte('j.kora', 'comptoir2026'), isTrue);

      await dao.reinitialiserMotDePasse(
        auteurId: 'admin',
        compteId: id,
        nouveau: 'nouveauSecret1',
        confirmation: 'nouveauSecret1',
      );
      expect(await seConnecte('j.kora', 'nouveauSecret1'), isTrue);
      expect(await seConnecte('j.kora', 'comptoir2026'), isFalse);
    });

    test('auteur sans droit : refusé, le mot de passe ne change pas', () async {
      await poser('admin', 'administrateur');
      await poser('recep', 'receptionniste');
      final id = await creer();
      final avant = (await ligne(id)).empreinte;
      expect(
        await refus(
          dao.reinitialiserMotDePasse(
            auteurId: 'recep',
            compteId: id,
            nouveau: 'piratage123',
            confirmation: 'piratage123',
          ),
        ),
        {'droit': MessagesComptes.refusDroit},
      );
      expect((await ligne(id)).empreinte, avant);
    });
  });

  group('Lecture et traçabilité', () {
    test('la liste rend TOUS les comptes (désactivés compris), triés par '
        'nom, sans sel ni empreinte', () async {
      await poser('zed', 'barman');
      await poser('admin', 'administrateur');
      await poser('bob', 'cuisine', actif: false);
      final comptes = await dao.comptes();
      expect(comptes.map((c) => c.identifiant), ['admin', 'bob', 'zed']);
      expect(comptes.singleWhere((c) => c.identifiant == 'bob').actif, isFalse);

      // La requête de la liste ne SÉLECTIONNE pas les colonnes secrètes : la
      // méthode est relue dans le source (une entité sans champ ne suffit
      // pas — une colonne lue puis jetée resterait en mémoire).
      final source = File(
        'lib/features/transverse/data/comptes_utilisateurs_dao.dart',
      ).readAsStringSync();
      final debut = source.indexOf('Future<List<CompteUtilisateur>> comptes()');
      final fin = source.indexOf('Future<String> creerCompte(');
      expect(debut, greaterThan(0));
      expect(fin, greaterThan(debut));
      final methode = source.substring(debut, fin);
      expect(methode, contains('t.login'), reason: 'extraction non vide');
      expect(methode, isNot(contains('t.sel')));
      expect(methode, isNot(contains('t.empreinte')));
      expect(methode, isNot(contains('select(_base.utilisateursLocal')));
    });

    test('aucun geste ne SUPPRIME : le DAO n’a aucun delete', () {
      final source = File(
        'lib/features/transverse/data/comptes_utilisateurs_dao.dart',
      ).readAsStringSync();
      expect(source, contains('_base.update('), reason: 'source relu');
      expect(source, isNot(contains('.delete(')));
      expect(source, isNot(contains('DELETE')));
    });
  });
}
