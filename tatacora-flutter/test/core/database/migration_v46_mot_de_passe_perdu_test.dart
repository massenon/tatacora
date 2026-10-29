import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/auth/data/code_secours_local.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';

/// Migration -> v46 (29/10/2026 : MOT DE PASSE PERDU SANS E-MAIL) : ONZE colonnes
/// ADDITIVES sur `utilisateurs_local` et UNE table locale neuve,
/// `journal_securite_local`, éprouvées sur un FICHIER RÉEL portant des comptes
/// (piège 2) — y compris en sautant des versions.
///
/// Additive, et rien n'est fabriqué : un compte d'avant la v46 garde son mot de
/// passe, n'a pas de changement exigé, pas de code de secours, aucun échec compté.
/// Puis la preuve qui compte : sur le fichier MIGRÉ, le compte se connecte avec
/// son ancien mot de passe, un administrateur le réinitialise, et un code de
/// secours se pose et se consomme.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dossier;
  late File fichier;

  // Les ONZE colonnes que la v46 ajoute à `utilisateurs_local` : nom -> NOT NULL.
  const colonnesV46 = <String, bool>{
    'changement_obligatoire': true,
    'mdp_temporaire_expire_le': false,
    'sel_precedent': false,
    'empreinte_precedente': false,
    'iterations_precedentes': false,
    'code_secours_sel': false,
    'code_secours_empreinte': false,
    'code_secours_iterations': false,
    'code_secours_genere_le': false,
    'code_secours_echecs': true,
    'code_secours_dernier_echec_le': false,
  };

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    dossier = await Directory.systemTemp.createTemp('tatacora_v46_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Map<String, bool>> colonnes(AppDatabase db, String table) async => {
    for (final c in await db.customSelect('PRAGMA table_info($table)').get())
      c.data['name'] as String: c.data['notnull'] == 1,
  };

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  /// Une base de la forme v45 : la courante, MOINS ce que la v46 ajoute (les onze
  /// colonnes des comptes et la table du journal), avec un VRAI administrateur
  /// (dérivé PBKDF2) et une employée. [cible] : la version posée.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await SessionRepositoryLocal(avant).creerCompte(
      login: 'n.kora',
      nom: 'KORA Noël',
      motDePasse: 'Ancien-Secret-9',
      role: 'administrateur',
      droits: const {'M1': 'C', 'ROLES': 'C'},
    );
    await SessionRepositoryLocal(avant).creerCompte(
      login: 'marie',
      nom: 'HOUNSOU Marie',
      motDePasse: 'Marie-Secret-5',
      role: 'receptionniste',
      droits: const {'M1': 'C'},
    );
    await avant.customStatement('DROP TABLE journal_securite_local');
    for (final nom in colonnesV46.keys) {
      await avant.customStatement(
        'ALTER TABLE utilisateurs_local DROP COLUMN $nom',
      );
    }
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    final cols = await colonnes(avant, 'utilisateurs_local');
    for (final nom in colonnesV46.keys) {
      expect(cols.keys, isNot(contains(nom)), reason: 'retiré : $nom');
    }
    await avant.customStatement('PRAGMA user_version = $cible');
    await avant.close();
  }

  for (final depart in const [45, 40]) {
    test('v$depart -> v46 : onze colonnes et une table, les comptes sont '
        'INTACTS, rien n’est fabriqué, et ça SERT de bout en bout', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(46));

      // Les colonnes, avec leur contrainte.
      final cols = await colonnes(apres, 'utilisateurs_local');
      for (final e in colonnesV46.entries) {
        expect(cols.keys, contains(e.key));
        expect(cols[e.key], e.value, reason: '${e.key} : NOT NULL ?');
      }
      // La table du journal existe, vide.
      final journal = await colonnes(apres, 'journal_securite_local');
      expect(
        journal.keys,
        containsAll(['id', 'action', 'auteur_login', 'poste_nom', 'cible_id']),
      );
      expect(
        (await apres
                .customSelect(
                  'SELECT COUNT(*) AS n FROM journal_securite_local',
                )
                .getSingle())
            .data['n'],
        0,
      );

      // Rien n'est fabriqué : ni changement exigé, ni code, ni échec.
      final u = await apres
          .customSelect(
            'SELECT login, nom, role, changement_obligatoire AS c, '
            'mdp_temporaire_expire_le AS e, sel_precedent AS p, '
            'code_secours_empreinte AS s, code_secours_echecs AS n '
            "FROM utilisateurs_local WHERE login = 'n.kora'",
          )
          .getSingle();
      expect(u.data['nom'], 'KORA Noël');
      expect(u.data['role'], 'administrateur');
      expect(u.data['c'], 0);
      expect(u.data['e'], isNull);
      expect(u.data['p'], isNull);
      expect(u.data['s'], isNull, reason: 'aucun code de secours fabriqué');
      expect(u.data['n'], 0);

      // Le curseur de descente n'est PAS touché par cette migration.
      final etat = {
        for (final l
            in await apres
                .customSelect(
                  'SELECT cle, valeur FROM etat_synchronisation_local',
                )
                .get())
          l.data['cle'] as String: l.data['valeur'] as String,
      };
      if (depart == 45) expect(etat['descente.curseur'], 'abc');
      expect(etat['serveur.generation'], 'g1');

      // La preuve qui compte : le compte MIGRÉ se connecte avec son ancien mot
      // de passe, un administrateur le réinitialise, un code de secours se pose.
      final depot = SessionRepositoryLocal(apres);
      final session = await depot.connecter('n.kora', 'Ancien-Secret-9');
      expect(session.changementObligatoire, isFalse);

      final marie = await apres
          .customSelect(
            "SELECT id FROM utilisateurs_local WHERE login = 'marie'",
          )
          .getSingle();
      final fait = await ComptesUtilisateursDao(apres)
          .reinitialiserParAdministrateur(
            auteurId: session.utilisateurId,
            compteId: marie.data['id'] as String,
          );
      expect(
        (await depot.connecter('marie', fait.motDePasse)).changementObligatoire,
        isTrue,
      );

      final code = await CodeSecoursLocal(apres).poser(login: 'n.kora');
      await CodeSecoursLocal(
        apres,
      ).reinitialiser(login: 'n.kora', code: code, nouveau: 'Tout-Neuf-Mdp-4');
      expect(
        (await depot.connecter('n.kora', 'Tout-Neuf-Mdp-4')).login,
        'n.kora',
      );

      // Le tout survit à la réouverture.
      await apres.close();
      final relue = AppDatabase.surFichier(fichier);
      expect(await version(relue), relue.schemaVersion);
      final trace = await relue
          .customSelect(
            'SELECT action FROM journal_securite_local ORDER BY cree_le',
          )
          .get();
      expect(
        trace.map((l) => l.data['action']),
        containsAll([
          'reinitialisation_mot_de_passe',
          'code_secours_genere',
          'code_secours_utilise',
        ]),
      );
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v46 '
      'mais marqué v45 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await SessionRepositoryLocal(base).creerCompte(
      login: 'n.kora',
      nom: 'KORA Noël',
      motDePasse: 'Ancien-Secret-9',
      role: 'administrateur',
      droits: const {'M1': 'C'},
    );
    final code = await CodeSecoursLocal(base).poser(login: 'n.kora');
    await base.customStatement('PRAGMA user_version = 45');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    // Le code posé AVANT le rejeu est intact : il sert toujours.
    await CodeSecoursLocal(
      apres,
    ).reinitialiser(login: 'n.kora', code: code, nouveau: 'Tout-Neuf-Mdp-4');
    await apres.close();
  });

  test(
    'un poste neuf (onCreate) porte lui aussi les onze colonnes et la table',
    () async {
      final base = AppDatabase.surFichier(fichier);
      final cols = await colonnes(base, 'utilisateurs_local');
      expect(cols.keys, containsAll(colonnesV46.keys));
      expect(
        (await colonnes(base, 'journal_securite_local')).keys,
        contains('cree_le'),
      );
      await base.close();
    },
  );
}
