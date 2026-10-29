import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/database/auteur_ecriture.dart';
import 'package:tatacora_flutter/features/auth/data/code_secours_local.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/data/verificateur_hors_ligne.dart';
import 'package:tatacora_flutter/features/auth/domain/mot_de_passe_perdu.dart';
import 'package:tatacora_flutter/features/auth/domain/session_repository.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/journal_securite_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/comptes_utilisateurs.dart';
import 'package:tatacora_flutter/features/transverse/domain/journal_poste.dart';

/// MOT DE PASSE PERDU, SANS E-MAIL (PO, 29/10/2026, option A) — côté POSTE.
///
/// Les comptes du poste sont LOCAUX et distincts de ceux du web : rien ne se
/// synchronise, aucun dérivé de mot de passe ne part. Chaque règle est éprouvée
/// par le chemin que l'utilisateur emprunte — la vraie connexion
/// (`SessionRepositoryLocal`), le vrai DAO des comptes, le vrai code de secours —
/// jamais par une colonne relue seule : un compte dont le dérivé serait faux
/// aurait une ligne plausible et n'ouvrirait jamais.
///
/// Les règles jumelles du web (`MotDePassePerduTest`) : temporaire de 24 h,
/// changement forcé, refus de soi-même, code de secours à usage unique, cinq
/// essais puis quinze minutes, refus identique.
///
/// Les auteurs sont posés en SQL direct (dérivé factice) quand ils n'ont pas à se
/// connecter : 120 000 tours de PBKDF2 par compte allongeraient la suite pour rien.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptesUtilisateursDao dao;
  late SessionRepositoryLocal depot;
  late CodeSecoursLocal secours;
  late JournalSecuriteDao journal;
  var maintenant = DateTime(2026, 10, 29, 9);

  DateTime horloge() => maintenant;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    maintenant = DateTime(2026, 10, 29, 9);
    db = AppDatabase.enMemoire();
    dao = ComptesUtilisateursDao(db, horloge: horloge);
    depot = SessionRepositoryLocal(db, horloge: horloge);
    secours = CodeSecoursLocal(db, horloge: horloge);
    journal = JournalSecuriteDao(db, horloge: horloge);
    await RolesDao(db).installerSocle();
  });
  tearDown(() => db.close());

  /// Un compte posé en SQL direct, sans dérivé réel (il ne se connecte pas).
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

  Future<UtilisateurLocal> ligne(String login) => (db.select(
    db.utilisateursLocal,
  )..where((u) => u.login.equals(login))).getSingle();

  /// Un compte REEL (dérivé PBKDF2) — il se connecte.
  Future<String> reel(
    String login,
    String role, {
    String motDePasse = 'Ancien-Secret-9',
  }) async {
    await depot.creerCompte(
      login: login,
      nom: login.toUpperCase(),
      motDePasse: motDePasse,
      role: role,
      droits: const {'M1': 'C'},
    );
    return (await ligne(login)).id;
  }

  Future<String> messageRefus(Future<Object?> geste) async {
    try {
      await geste;
    } on RefusMotDePassePerdu catch (e) {
      return e.message;
    } on RefusComptes catch (e) {
      return e.message;
    } on EchecConnexion catch (e) {
      return e.message;
    }
    fail('aucun refus');
  }

  Future<List<EntreeSecurite>> entrees(String action) async => [
    for (final e in await journal.entrees())
      if (e.action == action) e,
  ];

  /// TOUT ce que le journal de sécurité contient, en une chaîne.
  Future<String> journalEntier() async => jsonEncode([
    for (final e in await journal.entrees())
      {
        'action': e.action,
        'auteur': e.auteurLogin,
        'poste': e.posteNom,
        'cibleId': e.cibleId,
        'cibleLogin': e.cibleLogin,
      },
  ]);

  // ======================================================== le générateur

  group('Les secrets générés', () {
    test('le mot de passe temporaire est fort (≥ 12), sans caractère ambigu, '
        'et ne se répète pas', () {
      final vus = <String>{};
      for (var i = 0; i < 300; i++) {
        final mdp = GenerateurDeSecret.motDePasseTemporaire();
        vus.add(mdp);
        expect(mdp.length, greaterThanOrEqualTo(12));
        expect(mdp, isNot(matches(RegExp('[0O1lI]'))));
        expect(mdp, matches(RegExp('[A-Z]')));
        expect(mdp, matches(RegExp('[a-z]')));
        expect(mdp, matches(RegExp('[0-9]')));
      }
      expect(vus.length, greaterThan(295));
    });

    test('le code de secours : 25 caractères en cinq groupes lisibles, sans '
        'ambiguïté ; la saisie se normalise', () {
      final code = GenerateurDeSecret.codeDeSecours();
      expect(code, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));
      expect(code.replaceAll('-', '').length, greaterThanOrEqualTo(20));
      expect(code, isNot(matches(RegExp('[0O1lI]'))));
      expect(
        GenerateurDeSecret.normaliserCode(' ${code.toLowerCase()} '),
        code.replaceAll('-', ''),
      );
    });

    test('le générateur emploie le hasard injecté (donc il est éprouvable) '
        'et Random.secure par défaut', () {
      expect(
        GenerateurDeSecret.motDePasseTemporaire(aleatoire: Random(1)),
        GenerateurDeSecret.motDePasseTemporaire(aleatoire: Random(1)),
      );
      expect(
        GenerateurDeSecret.motDePasseTemporaire(),
        isNot(GenerateurDeSecret.motDePasseTemporaire()),
      );
    });
  });

  // ============================================ réinitialisation par admin

  group('Réinitialisation par un administrateur', () {
    test('un administrateur ne peut PAS réinitialiser son propre compte : '
        'refus lisible, rien n’est écrit', () async {
      await poser('admin', 'administrateur');
      final avant = await ligne('admin');

      expect(
        await messageRefus(
          dao.reinitialiserParAdministrateur(
            auteurId: 'admin',
            compteId: 'admin',
          ),
        ),
        MessagesMotDePassePerdu.refusSoiMeme,
      );

      final apres = await ligne('admin');
      expect(apres.empreinte, avant.empreinte);
      expect(apres.changementObligatoire, isFalse);
      expect(await journal.entrees(), isEmpty);
    });

    test('un simple administrateur ne prend pas la main sur un super '
        'administrateur ; l’inverse est permis', () async {
      await poser('admin', 'administrateur');
      await poser('chef', 'super_admin');
      expect(
        await messageRefus(
          dao.reinitialiserParAdministrateur(
            auteurId: 'admin',
            compteId: 'chef',
          ),
        ),
        MessagesMotDePassePerdu.refusSuperAdmin,
      );
      expect((await ligne('chef')).changementObligatoire, isFalse);

      await dao.reinitialiserParAdministrateur(
        auteurId: 'chef',
        compteId: 'admin',
      );
      expect((await ligne('admin')).changementObligatoire, isTrue);
    });

    test('le journal dit QUI (compte connecté), QUEL compte, QUAND et depuis '
        'quelle machine — JAMAIS le mot de passe ni un dérivé', () async {
      await poser('admin', 'administrateur');
      await reel('marie', 'receptionniste');
      final marie = await ligne('marie');

      final fait = await dao.reinitialiserParAdministrateur(
        auteurId: 'admin',
        compteId: marie.id,
      );

      final e = (await entrees('reinitialisation_mot_de_passe')).single;
      expect(e.auteurLogin, 'admin', reason: 'qui');
      expect(e.cibleLogin, 'marie', reason: 'quel compte');
      expect(e.cibleId, marie.id);
      expect(e.creeLe, maintenant, reason: 'quand');
      expect(e.posteNom, nomDuPosteLocal(), reason: 'depuis quelle machine');

      final apres = await ligne('marie');
      final tout = await journalEntier();
      for (final secret in [
        fait.motDePasse,
        apres.empreinte,
        apres.sel,
        apres.selPrecedent!,
        apres.empreintePrecedente!,
      ]) {
        expect(tout, isNot(contains(secret)), reason: 'secret au journal');
      }
      // Et le journal d'audit du poste le rend sous son libellé.
      expect(
        entreeDepuisSecurite(
          action: e.action,
          creeLe: e.creeLe,
          auteurLogin: e.auteurLogin,
          posteNom: e.posteNom,
          cibleId: e.cibleId,
          cibleLogin: e.cibleLogin,
        )!.action.libelle,
        'Réinitialisation du mot de passe',
      );
    });

    test(
      'rien ne PART : le geste n’entre jamais dans la file d’envoi',
      () async {
        await poser('admin', 'administrateur');
        await reel('marie', 'receptionniste');
        await dao.reinitialiserParAdministrateur(
          auteurId: 'admin',
          compteId: (await ligne('marie')).id,
        );
        final n = await db
            .customSelect('SELECT COUNT(*) AS n FROM operations_sync_local')
            .getSingle();
        expect(n.data['n'], 0, reason: 'les comptes ne se synchronisent pas');
      },
    );

    test(
      'deux réinitialisations de suite gardent comme « ancien » le mot de '
      'passe que le titulaire avait CHOISI, pas le premier temporaire',
      () async {
        await poser('admin', 'administrateur');
        final id = await reel('marie', 'receptionniste');
        final choisi = await ligne('marie');

        await dao.reinitialiserParAdministrateur(
          auteurId: 'admin',
          compteId: id,
        );
        final deuxieme = await dao.reinitialiserParAdministrateur(
          auteurId: 'admin',
          compteId: id,
        );

        final l = await ligne('marie');
        expect(l.empreintePrecedente, choisi.empreinte);
        // Et le titulaire ne peut pas reprendre son ancien mot de passe.
        expect(
          await messageRefus(
            depot.definirNouveauMotDePasse(
              login: 'marie',
              nouveau: 'Ancien-Secret-9',
            ),
          ),
          MessagesMotDePassePerdu.identiqueAncien,
        );
        expect(deuxieme.motDePasse, isNotEmpty);
      },
    );
  });

  // ============================================= changement forcé & 24 h

  group('Changement obligatoire et expiration de 24 h', () {
    test('le temporaire ouvre une session « changement obligatoire » ; '
        'l’ancien mot de passe n’ouvre plus', () async {
      await poser('admin', 'administrateur');
      final id = await reel('marie', 'receptionniste');
      final fait = await dao.reinitialiserParAdministrateur(
        auteurId: 'admin',
        compteId: id,
      );

      final session = await depot.connecter('marie', fait.motDePasse);
      expect(session.changementObligatoire, isTrue);
      // La session restaurée au démarrage le porte aussi (la garde du routeur
      // relit le drapeau à chaque navigation).
      expect((await depot.sessionCourante())!.changementObligatoire, isTrue);
      expect(
        await messageRefus(depot.connecter('marie', 'Ancien-Secret-9')),
        SessionRepositoryLocal.refusIdentifiants,
      );
    });

    test(
      'le temporaire expire à 24 h pile : une seconde avant il ouvre, à '
      'l’échéance il n’ouvre plus — et la session restaurée est fermée',
      () async {
        await poser('admin', 'administrateur');
        final id = await reel('marie', 'receptionniste');
        final fait = await dao.reinitialiserParAdministrateur(
          auteurId: 'admin',
          compteId: id,
        );

        // L'ancrage EXTÉRIEUR (piège 12) : 24 heures, pas « l'échéance que le
        // code s'est donnée ».
        expect(fait.expireLe, maintenant.add(const Duration(hours: 24)));

        maintenant = fait.expireLe.subtract(const Duration(seconds: 1));
        await depot.connecter('marie', fait.motDePasse);
        expect(await depot.sessionCourante(), isNotNull);

        maintenant = fait.expireLe;
        expect(
          await messageRefus(depot.connecter('marie', fait.motDePasse)),
          MessagesMotDePassePerdu.expire,
        );
        expect(
          await depot.sessionCourante(),
          isNull,
          reason:
              'une session ouverte avec le temporaire se ferme à l’échéance',
        );
        expect(
          await messageRefus(
            depot.definirNouveauMotDePasse(
              login: 'marie',
              nouveau: 'Nouveau-Secret-7',
            ),
          ),
          MessagesMotDePassePerdu.expire,
        );

        // Il faut en regénérer un.
        final autre = await dao.reinitialiserParAdministrateur(
          auteurId: 'admin',
          compteId: id,
        );
        expect(autre.motDePasse, isNot(fait.motDePasse));
        expect(
          (await depot.connecter('marie', autre.motDePasse)).login,
          'marie',
        );
      },
    );

    test('le nouveau mot de passe doit être ≥ 8, ≠ du temporaire, ≠ de '
        'l’ancien ; refusé, rien ne change', () async {
      await poser('admin', 'administrateur');
      final id = await reel('marie', 'receptionniste');
      final fait = await dao.reinitialiserParAdministrateur(
        auteurId: 'admin',
        compteId: id,
      );
      final avant = await ligne('marie');

      expect(
        await messageRefus(
          depot.definirNouveauMotDePasse(login: 'marie', nouveau: 'court'),
        ),
        MessagesMotDePassePerdu.tropCourt,
      );
      expect(
        await messageRefus(
          depot.definirNouveauMotDePasse(
            login: 'marie',
            nouveau: fait.motDePasse,
          ),
        ),
        MessagesMotDePassePerdu.identiqueTemporaire,
      );
      expect(
        await messageRefus(
          depot.definirNouveauMotDePasse(
            login: 'marie',
            nouveau: 'Ancien-Secret-9',
          ),
        ),
        MessagesMotDePassePerdu.identiqueAncien,
      );
      final apres = await ligne('marie');
      expect(apres.empreinte, avant.empreinte);
      expect(apres.changementObligatoire, isTrue);
    });

    test('le choix d’un nouveau mot de passe lève le blocage, efface le '
        'temporaire et l’ancien dérivé ; seul le nouveau ouvre', () async {
      await poser('admin', 'administrateur');
      final id = await reel('marie', 'receptionniste');
      final fait = await dao.reinitialiserParAdministrateur(
        auteurId: 'admin',
        compteId: id,
      );

      await depot.definirNouveauMotDePasse(
        login: 'marie',
        nouveau: 'Nouveau-Secret-7',
      );

      final l = await ligne('marie');
      expect(l.changementObligatoire, isFalse);
      expect(l.mdpTemporaireExpireLe, isNull);
      expect(l.selPrecedent, isNull);
      expect(l.empreintePrecedente, isNull);
      expect(l.iterationsPrecedentes, isNull);
      expect(l.dateMotDePasse, maintenant);

      final session = await depot.connecter('marie', 'Nouveau-Secret-7');
      expect(session.changementObligatoire, isFalse);
      for (final vieux in [fait.motDePasse, 'Ancien-Secret-9']) {
        expect(
          await messageRefus(depot.connecter('marie', vieux)),
          SessionRepositoryLocal.refusIdentifiants,
        );
      }
    });

    test(
      'un compte sans changement exigé n’a rien à faire sur cet écran',
      () async {
        await reel('marie', 'receptionniste');
        expect(
          await messageRefus(
            depot.definirNouveauMotDePasse(
              login: 'marie',
              nouveau: 'Nouveau-Secret-7',
            ),
          ),
          SessionRepositoryLocal.refusIdentifiants,
        );
        expect(
          (await depot.connecter(
            'marie',
            'Ancien-Secret-9',
          )).changementObligatoire,
          isFalse,
        );
      },
    );
  });

  // ============================================================ code de secours

  group('Code de secours de l’administrateur', () {
    test(
      'le premier compte reçoit un code ; seul son DÉRIVÉ est stocké',
      () async {
        await reel('admin', 'administrateur');

        final code = await secours.poser(login: 'admin');

        expect(code, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));
        final l = await ligne('admin');
        expect(l.codeSecoursEmpreinte, isNotNull);
        expect(l.codeSecoursEmpreinte, isNot(contains(code)));
        expect(l.codeSecoursSel, isNot(contains(code)));
        expect(l.codeSecoursGenereLe, maintenant);
        // Le dérivé vérifie le code normalisé, et lui seul.
        final v = VerificateurHorsLigne(
          login: 'admin',
          sel: l.codeSecoursSel!,
          empreinte: l.codeSecoursEmpreinte!,
          iterations: l.codeSecoursIterations!,
          derniereConnexionEnLigne: maintenant,
        );
        expect(v.correspond(GenerateurDeSecret.normaliserCode(code)), isTrue);
        expect(v.correspond('AAAAAAAAAAAAAAAAAAAAAAAAA'), isFalse);
        // Le journal le trace, sans le code.
        expect(
          (await entrees('code_secours_genere')).single.cibleLogin,
          'admin',
        );
        expect(await journalEntier(), isNot(contains(code)));
      },
    );

    test('un compte non administrateur n’a pas de code de secours', () async {
      await reel('marie', 'receptionniste');
      expect(
        await messageRefus(secours.poser(login: 'marie')),
        MessagesMotDePassePerdu.refusCode,
      );
      expect((await ligne('marie')).codeSecoursEmpreinte, isNull);
    });

    test('« Mon profil » exige le mot de passe actuel, puis remplace le code '
        '(l’ancien ne sert plus)', () async {
      await reel('admin', 'administrateur');
      final premier = await secours.poser(login: 'admin');

      expect(
        await messageRefus(
          secours.genererPourSession(login: 'admin', motDePasse: 'faux-faux-1'),
        ),
        MessagesMotDePassePerdu.mdpIncorrect,
      );
      final second = await secours.genererPourSession(
        login: 'admin',
        motDePasse: 'Ancien-Secret-9',
      );
      expect(second, isNot(premier));

      expect(
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: premier,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        MessagesMotDePassePerdu.refusCode,
      );
      await secours.reinitialiser(
        login: 'admin',
        code: second,
        nouveau: 'Tout-Neuf-Mdp-4',
      );
    });

    test('un ancien administrateur (avant la v46, sans code) est refusé comme '
        'les autres : aucune porte dérobée', () async {
      await reel('admin', 'administrateur');
      expect(
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE',
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        MessagesMotDePassePerdu.refusCode,
      );
    });

    test('usage unique, rotation : le code réinitialise, est consommé, un '
        'NOUVEAU est remis ; l’ancien ne sert plus', () async {
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');

      final nouveauCode = await secours.reinitialiser(
        login: ' Admin ',
        code: code.toLowerCase(),
        nouveau: 'Tout-Neuf-Mdp-4',
      );

      expect(nouveauCode, isNot(code));
      expect(nouveauCode, matches(RegExp(r'^([A-Z2-9]{5}-){4}[A-Z2-9]{5}$')));
      // Le nouveau mot de passe ouvre, l'ancien non.
      expect(
        (await depot.connecter('admin', 'Tout-Neuf-Mdp-4')).login,
        'admin',
      );
      expect(
        await messageRefus(depot.connecter('admin', 'Ancien-Secret-9')),
        SessionRepositoryLocal.refusIdentifiants,
      );
      // L'ancien code est consommé ; le nouveau sert une fois, puis encore un autre.
      expect(
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: code,
            nouveau: 'Autre-Mdp-Sur-5',
          ),
        ),
        MessagesMotDePassePerdu.refusCode,
      );
      final encore = await secours.reinitialiser(
        login: 'admin',
        code: nouveauCode,
        nouveau: 'Autre-Mdp-Sur-5',
      );
      expect(encore, isNot(nouveauCode));
      expect(
        (await depot.connecter('admin', 'Autre-Mdp-Sur-5')).login,
        'admin',
      );
    });

    test('un temporaire en cours est levé par le code de secours', () async {
      await poser('chef', 'super_admin');
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');
      await dao.reinitialiserParAdministrateur(
        auteurId: 'chef',
        compteId: (await ligne('admin')).id,
      );
      expect((await ligne('admin')).changementObligatoire, isTrue);

      await secours.reinitialiser(
        login: 'admin',
        code: code,
        nouveau: 'Tout-Neuf-Mdp-4',
      );

      final l = await ligne('admin');
      expect(l.changementObligatoire, isFalse);
      expect(l.selPrecedent, isNull);
    });

    test('le refus est IDENTIQUE : compte inconnu, mauvais code, compte '
        'désactivé, non-administrateur muni d’un hash de code', () async {
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');
      await reel('marie', 'receptionniste');
      // Un non-administrateur qui porterait un hash de code (donnée forcée).
      final l = await ligne('admin');
      await (db.update(
        db.utilisateursLocal,
      )..where((u) => u.login.equals('marie'))).write(
        UtilisateursLocalCompanion(
          codeSecoursSel: Value(l.codeSecoursSel),
          codeSecoursEmpreinte: Value(l.codeSecoursEmpreinte),
          codeSecoursIterations: Value(l.codeSecoursIterations),
        ),
      );
      await reel('ancien', 'administrateur');
      final codeAncien = await secours.poser(login: 'ancien');
      await (db.update(db.utilisateursLocal)
            ..where((u) => u.login.equals('ancien')))
          .write(const UtilisateursLocalCompanion(actif: Value(false)));

      final messages = {
        await messageRefus(
          secours.reinitialiser(
            login: 'inconnu',
            code: code,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: 'AAAAA-BBBBB-CCCCC-DDDDD-EEEEE',
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        await messageRefus(
          secours.reinitialiser(
            login: 'marie',
            code: code,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        await messageRefus(
          secours.reinitialiser(
            login: 'ancien',
            code: codeAncien,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
      };
      expect(messages, {MessagesMotDePassePerdu.refusCode});
      expect(
        (await depot.connecter('admin', 'Ancien-Secret-9')).login,
        'admin',
        reason: 'aucun de ces refus n’a touché le compte administrateur',
      );
      expect(
        await messageRefus(depot.connecter('marie', 'Tout-Neuf-Mdp-4')),
        SessionRepositoryLocal.refusIdentifiants,
      );
    });

    test('cinq échecs bloquent le compte QUINZE minutes, même avec le bon '
        'code ; le blocage tombe ensuite', () async {
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');

      for (var i = 0; i < 5; i++) {
        expect(
          await messageRefus(
            secours.reinitialiser(
              login: 'admin',
              code: 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ',
              nouveau: 'Tout-Neuf-Mdp-4',
            ),
          ),
          MessagesMotDePassePerdu.refusCode,
        );
      }
      expect((await ligne('admin')).codeSecoursEchecs, 5);

      expect(
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: code,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        MessagesMotDePassePerdu.bloque(15),
      );
      expect(
        (await depot.connecter('admin', 'Ancien-Secret-9')).login,
        'admin',
        reason: 'le mot de passe n’a pas changé',
      );

      // Les tentatives BLOQUÉES sont tracées, mais ne prolongent pas le blocage.
      maintenant = maintenant.add(const Duration(minutes: 10));
      expect(
        await messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: code,
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        ),
        MessagesMotDePassePerdu.bloque(5),
      );
      expect(await entrees('code_secours_bloque'), hasLength(2));
      expect(await entrees('code_secours_refuse'), hasLength(5));

      maintenant = maintenant.add(const Duration(minutes: 5, seconds: 1));
      await secours.reinitialiser(
        login: 'admin',
        code: code,
        nouveau: 'Tout-Neuf-Mdp-4',
      );
      expect((await ligne('admin')).codeSecoursEchecs, 0);
    });

    test(
      'le blocage vaut aussi PAR POSTE : cinq refus sur cinq identifiants '
      'différents (dont des inconnus) bloquent un identifiant neuf',
      () async {
        await reel('admin', 'administrateur');
        final code = await secours.poser(login: 'admin');

        for (final inconnu in ['a', 'b', 'c', 'd', 'e']) {
          await messageRefus(
            secours.reinitialiser(
              login: inconnu,
              code: code,
              nouveau: 'Tout-Neuf-Mdp-4',
            ),
          );
        }

        expect(
          await messageRefus(
            secours.reinitialiser(
              login: 'admin',
              code: code,
              nouveau: 'Tout-Neuf-Mdp-4',
            ),
          ),
          MessagesMotDePassePerdu.bloque(15),
        );
      },
    );

    test(
      'des échecs étalés sur plus de quinze minutes ne bloquent personne',
      () async {
        await reel('admin', 'administrateur');
        final code = await secours.poser(login: 'admin');
        Future<void> echec() => messageRefus(
          secours.reinitialiser(
            login: 'admin',
            code: 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ',
            nouveau: 'Tout-Neuf-Mdp-4',
          ),
        );
        for (var i = 0; i < 4; i++) {
          await echec();
          maintenant = maintenant.add(const Duration(minutes: 16));
        }
        // Quatre échecs vieux de plus de quinze minutes ne comptent plus : un
        // cinquième ne bloque PAS, et le compteur repart de un.
        await echec();
        expect((await ligne('admin')).codeSecoursEchecs, 1);
        await secours.reinitialiser(
          login: 'admin',
          code: code,
          nouveau: 'Tout-Neuf-Mdp-4',
        );
      },
    );

    test('une saisie incomplète (mot de passe trop court) ne consomme aucun '
        'essai', () async {
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');
      for (var i = 0; i < 8; i++) {
        expect(
          await messageRefus(
            secours.reinitialiser(login: 'admin', code: code, nouveau: 'court'),
          ),
          MessagesMotDePassePerdu.tropCourt,
        );
      }
      expect((await ligne('admin')).codeSecoursEchecs, 0);
      expect(await entrees('code_secours_refuse'), isEmpty);
      await secours.reinitialiser(
        login: 'admin',
        code: code,
        nouveau: 'Tout-Neuf-Mdp-4',
      );
    });

    test('chaque tentative, réussie ou refusée, est au journal — sans le code '
        'ni le mot de passe', () async {
      await reel('admin', 'administrateur');
      final code = await secours.poser(login: 'admin');
      await messageRefus(
        secours.reinitialiser(
          login: 'admin',
          code: 'ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ-ZZZZZ',
          nouveau: 'Mdp-Refuse-Secret-3',
        ),
      );
      final nouveauCode = await secours.reinitialiser(
        login: 'admin',
        code: code,
        nouveau: 'Tout-Neuf-Mdp-4',
      );

      final refus = (await entrees('code_secours_refuse')).single;
      expect(refus.cibleLogin, 'admin');
      expect(refus.auteurLogin, isNull, reason: 'aucune session n’existait');
      final ok = (await entrees('code_secours_utilise')).single;
      expect(ok.cibleLogin, 'admin');
      expect(ok.creeLe, maintenant);

      final tout = await journalEntier();
      for (final secret in [
        code,
        GenerateurDeSecret.normaliserCode(code),
        nouveauCode,
        'Tout-Neuf-Mdp-4',
        'Mdp-Refuse-Secret-3',
      ]) {
        expect(tout, isNot(contains(secret)), reason: 'secret au journal');
      }
    });
  });

  // ======================================================== le journal d'audit

  group('Le Journal d’Audit du poste lit aussi le journal de sécurité', () {
    test('les cinq actions ont leur libellé, celui du serveur', () {
      const attendus = {
        'reinitialisation_mot_de_passe': 'Réinitialisation du mot de passe',
        'code_secours_genere': 'Code de secours généré',
        'code_secours_utilise': 'Réinitialisation par code de secours',
        'code_secours_refuse': 'Code de secours refusé',
        'code_secours_bloque': 'Code de secours bloqué',
      };
      for (final e in attendus.entries) {
        final a = ActionJournalPoste.depuisCode(e.key)!;
        expect(a.libelle, e.value);
        expect(a.estDeSecurite, isTrue);
      }
      expect(ActionJournalPoste.creation.estDeSecurite, isFalse);
    });
  });
}
