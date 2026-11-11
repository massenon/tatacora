@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/comptes_utilisateurs_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/journal_securite_dao.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/champs_profil.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// « Mon profil » sous droit (03/11/2026) : le droit est appliqué par le DAO, jamais
/// seulement masqué ; normalisation, bornes, journal « Profil modifié », valeurs par
/// défaut (nom et téléphone : tous les rôles ; intitulé : administration), rôle neuf.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptesUtilisateursDao dao;

  Future<void> poser(String id, String role) async {
    final roles = await RolesDao(db).roles();
    final droits = roles.firstWhere((r) => r.libelle == role);
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: id,
            login: id,
            nom: id.toUpperCase(),
            role: role,
            droitsJson: _json(droits.niveaux),
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
  }

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = ComptesUtilisateursDao(db, horloge: () => DateTime(2026, 11, 3, 9));
    await RolesDao(db).installerSocle();
    await poser('admin', 'administrateur');
    await poser('barman', 'barman');
  });
  tearDown(() => db.close());

  test('valeurs par défaut : nom et téléphone pour tous, intitulé pour '
      "l'administration", () async {
    for (final r in await RolesDao(db).roles()) {
      expect(r.droitProfil('PROFIL_NOM'), isTrue, reason: r.libelle);
      expect(r.droitProfil('PROFIL_TELEPHONE'), isTrue, reason: r.libelle);
      expect(
        r.droitProfil('PROFIL_INTITULE'),
        rolesAdministrationProfil.contains(r.libelle),
        reason: r.libelle,
      );
      expect(r.conforme, isTrue, reason: r.libelle);
    }
    final p = await dao.profil('barman');
    expect(p.peutModifier(ChampProfil.intitule), isFalse);
    expect(
      (await dao.profil('admin')).peutModifier(ChampProfil.intitule),
      isTrue,
    );
  });

  test('un administrateur renseigne ses champs, normalisés, et le journal '
      'garde ancien → nouveau', () async {
    final faits = await dao.enregistrerProfil(
      utilisateurId: 'admin',
      nomComplet: '  Awa   Kossou ',
      telephone: ' +229  97 00-11 ',
      intitule: ' Directrice  des opérations ',
      email: null,
    );
    expect(faits, ['nom_complet', 'telephone', 'intitule_poste']);
    final p = await dao.profil('admin');
    expect(p.nomComplet, 'Awa Kossou');
    expect(p.telephone, '+229 97 00-11');
    expect(p.intitule, 'Directrice des opérations');

    final trace = (await JournalSecuriteDao(db).entrees()).single;
    expect(trace.action, 'profil_modifie');
    expect(trace.auteurLogin, 'admin');
    expect(trace.cibleLogin, contains('« ADMIN » → « Awa Kossou »'));
    expect(trace.cibleLogin, contains('Téléphone : — →'));

    // Rien de changé : rien d'écrit, pas de seconde trace.
    expect(
      await dao.enregistrerProfil(
        utilisateurId: 'admin',
        nomComplet: 'Awa Kossou',
        telephone: '+229 97 00-11',
        intitule: 'Directrice des opérations',
        email: null,
      ),
      isEmpty,
    );
    expect(await JournalSecuriteDao(db).entrees(), hasLength(1));

    // Vider est permis ; le nom effacé retombe sur le login.
    await dao.enregistrerProfil(
      utilisateurId: 'admin',
      nomComplet: '',
      telephone: '',
      intitule: '',
      email: null,
    );
    final vide = await dao.profil('admin');
    expect(vide.nomComplet, 'admin');
    expect(vide.telephone, isNull);
    expect(vide.intitule, isNull);
  });

  test(
    'une action forgée sans le droit est refusée et n\'écrit RIEN',
    () async {
      // Le barman n'a pas l'intitulé : il le forge, avec un nom permis.
      await expectLater(
        dao.enregistrerProfil(
          utilisateurId: 'barman',
          nomComplet: 'Nouveau nom',
          telephone: null,
          intitule: 'Directeur général',
          email: 'x@y.com',
        ),
        throwsA(
          isA<RefusProfil>().having((r) => r.erreurs.keys, 'champs', ['droit']),
        ),
      );
      final c = await (db.select(
        db.utilisateursLocal,
      )..where((u) => u.id.equals('barman'))).getSingle();
      expect(c.nom, 'BARMAN');
      expect(c.intituleDePoste, isNull);
      expect(c.email, isNull);
      expect(await JournalSecuriteDao(db).entrees(), isEmpty);

      // Retirer le droit au nom (dans la matrice du compte) le refuse aussi.
      await (db.update(
        db.utilisateursLocal,
      )..where((u) => u.id.equals('barman'))).write(
        const UtilisateursLocalCompanion(
          droitsJson: Value('{"PROFIL_NOM":"-"}'),
        ),
      );
      await expectLater(
        dao.enregistrerProfil(
          utilisateurId: 'barman',
          nomComplet: 'Forgé',
          telephone: null,
          intitule: null,
          email: null,
        ),
        throwsA(isA<RefusProfil>()),
      );
      // Un droit absent ou `L` refuse (jamais par omission).
      await (db.update(
        db.utilisateursLocal,
      )..where((u) => u.id.equals('barman'))).write(
        const UtilisateursLocalCompanion(
          droitsJson: Value('{"PROFIL_NOM":"L"}'),
        ),
      );
      expect((await dao.profil('barman')).droits, isEmpty);
    },
  );

  test('bornes et format', () async {
    Future<RefusProfil> refus({
      String? nom,
      String? tel,
      String? intitule,
    }) async {
      try {
        await dao.enregistrerProfil(
          utilisateurId: 'admin',
          nomComplet: nom ?? 'ADMIN',
          telephone: tel,
          intitule: intitule,
          email: null,
        );
      } on RefusProfil catch (r) {
        return r;
      }
      fail('aurait dû être refusé');
    }

    expect((await refus(nom: 'a' * 121)).erreurs.keys, ['nom_complet']);
    expect((await refus(nom: 'Awa\u0007K')).erreurs.keys, ['nom_complet']);
    expect((await refus(tel: '97 AB')).erreurs.keys, ['telephone']);
    expect((await refus(tel: '1' * 31)).erreurs.keys, ['telephone']);
    expect((await refus(intitule: 'b' * 121)).erreurs.keys, ['intitule_poste']);
    // 120 et 30 passent.
    await dao.enregistrerProfil(
      utilisateurId: 'admin',
      nomComplet: 'a' * 120,
      telephone: '1' * 30,
      intitule: 'b' * 120,
      email: null,
    );
  });

  test(
    'un rôle créé à l\'écran reçoit nom et téléphone, pas l\'intitulé, et le '
    'profil reste LOCAL (rien enfilé pour le compte)',
    () async {
      final id = await RolesDao(db).creerRole(
        auteur: GardeAcces.depuisJson({'ROLES': 'C'}),
        libelle: 'role_libre',
      );
      final r = (await RolesDao(db).roles()).firstWhere((x) => x.id == id);
      expect(r.droitProfil('PROFIL_NOM'), isTrue);
      expect(r.droitProfil('PROFIL_TELEPHONE'), isTrue);
      expect(r.droitProfil('PROFIL_INTITULE'), isFalse);
      expect(r.niveaux['M1'], '-');

      final avant = await db.select(db.operationsSyncLocal).get();
      await dao.enregistrerProfil(
        utilisateurId: 'admin',
        nomComplet: 'Autre',
        telephone: null,
        intitule: null,
        email: null,
      );
      final apres = await db.select(db.operationsSyncLocal).get();
      expect(apres.length, avant.length);
      expect(
        apres.where(
          (o) =>
              o.tableServeur == TableSynchronisee.utilisateurs.nomServeur &&
              o.type == 'creation',
        ),
        isEmpty,
      );
    },
  );

  test(
    "« Modifier les droits » règle les droits de profil d'un rôle",
    () async {
      final bar = (await RolesDao(
        db,
      ).roles()).firstWhere((r) => r.libelle == 'barman');
      await RolesDao(db).definirDroits(
        auteur: GardeAcces.depuisJson({'ROLES': 'C'}),
        roleId: bar.id,
        niveaux: {
          for (final m in libellesModulesMatrice.keys) m: bar.droits.niveau(m),
        },
        droitsProfil: {'PROFIL_INTITULE': true, 'PROFIL_NOM': false},
      );
      final p = await dao.profil('barman');
      expect(p.peutModifier(ChampProfil.intitule), isTrue);
      expect(p.peutModifier(ChampProfil.nomComplet), isFalse);
      expect(p.peutModifier(ChampProfil.telephone), isTrue);
    },
  );
}

String _json(Map<String, String> m) =>
    '{${m.entries.map((e) => '"${e.key}":"${e.value}"').join(',')}}';
