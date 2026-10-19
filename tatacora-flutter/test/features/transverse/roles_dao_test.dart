@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/transverse/data/roles_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// `RolesDao` (D438–D441, 14/10/2026) : le socle relu sur le VRAI seeder du
/// serveur, les gestes, leurs refus, et la recopie des droits sur les comptes.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late RolesDao dao;

  final admin = GardeAcces(const {'ROLES': 'C'});
  final lecteur = GardeAcces(const {'ROLES': 'L'});

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = RolesDao(db, horloge: () => DateTime(2026, 10, 14, 9));
  });
  tearDown(() => db.close());

  Future<void> compte(String id, String role) => db
      .into(db.utilisateursLocal)
      .insert(
        UtilisateursLocalCompanion.insert(
          id: id,
          login: id,
          nom: id,
          role: role,
          droitsJson: '{}',
          sel: 's',
          empreinte: 'e',
          iterations: 1,
          dateCreation: DateTime(2026, 10, 1),
          dateMotDePasse: DateTime(2026, 10, 1),
        ),
      );

  Future<RoleDuPoste> role(String libelle) async =>
      (await dao.roles()).singleWhere((r) => r.libelle == libelle);

  Future<Map<String, dynamic>> droitsDuCompte(String id) async {
    final u = await (db.select(
      db.utilisateursLocal,
    )..where((u) => u.id.equals(id))).getSingle();
    return jsonDecode(u.droitsJson) as Map<String, dynamic>;
  }

  test('le socle recopié est EXACTEMENT RolePermissionSeeder::MATRICE, relue '
      'par PHP', () async {
    final r = await Process.run('php', [
      '-r',
      "require 'vendor/autoload.php'; "
          'echo json_encode(\\Database\\Seeders\\RolePermissionSeeder::MATRICE);',
    ], workingDirectory: '../tatacora-api');
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final serveur = (jsonDecode(r.stdout as String) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, Map<String, String>.from(v as Map)));
    expect(serveur, isNotEmpty);
    expect(socleRbacCdcf, serveur);
  });

  test('installerSocle : douze rôles, idempotent, un rôle présent JAMAIS '
      'réécrit', () async {
    expect(await dao.installerSocle(), socleRbacCdcf.length);
    expect(await dao.installerSocle(), 0);
    final roles = await dao.roles();
    expect(roles.map((r) => r.libelle).toSet(), socleRbacCdcf.keys.toSet());
    for (final r in roles) {
      expect(r.niveaux, socleRbacCdcf[r.libelle], reason: r.libelle);
    }
    expect(matriceConformeAuSocle(roles), isTrue);

    // Un rôle du socle amendé n'est pas rétabli par une nouvelle lecture.
    final barman = await role('barman');
    await dao.definirDroits(
      auteur: admin,
      roleId: barman.id,
      niveaux: {ModuleTatacora.m5Bar: NiveauAcces.lecture},
    );
    expect(await dao.installerSocle(), 0);
    expect((await role('barman')).niveaux['M5'], 'L');
    expect((await role('barman')).conforme, isFalse);
  });

  test('création : rôle FERMÉ partout ; refus droit, vide, trop long, '
      'doublon sans casse ni accent', () async {
    await dao.installerSocle();
    final id = await dao.creerRole(
      auteur: admin,
      libelle: '  Serveur  ',
      description: 'Salle',
    );
    final cree = (await dao.roles()).singleWhere((r) => r.id == id);
    expect(cree.libelle, 'Serveur');
    expect(cree.niveaux.values.toSet(), {'-'});
    expect(cree.niveaux.keys.toSet(), codesModulesSocle.toSet());
    expect(cree.conforme, isNull);

    Future<Map<String, String>> refus(Future<Object?> geste) async {
      try {
        await geste;
      } on RefusRoles catch (e) {
        return e.erreurs;
      }
      fail('aucun refus');
    }

    expect(await refus(dao.creerRole(auteur: lecteur, libelle: 'X')), {
      'droit': MessagesRoles.refusDroit,
    });
    expect(await refus(dao.creerRole(auteur: admin, libelle: '   ')), {
      'libelle': MessagesRoles.libelleObligatoire,
    });
    expect(
      await refus(
        dao.creerRole(
          auteur: admin,
          libelle: 'a' * 101,
          description: 'd' * 256,
        ),
      ),
      {
        'libelle': MessagesRoles.libelleTropLong,
        'description': MessagesRoles.descriptionTropLongue,
      },
    );
    expect(await refus(dao.creerRole(auteur: admin, libelle: 'SÉRVEUR')), {
      'libelle': MessagesRoles.roleDejaExistant('SÉRVEUR'),
    });
    expect((await dao.roles()).length, socleRbacCdcf.length + 1);
  });

  test('droits : recopiés sur les comptes du rôle ; verrou administrateur / '
      'ROLES ; refus sans droit, RIEN écrit', () async {
    await dao.installerSocle();
    await compte('b1', 'barman');
    await compte('b2', 'barman');
    await compte('r1', 'receptionniste');
    expect((await role('barman')).comptes, 2);
    expect(await dao.totalComptes(), 3);

    final barman = await role('barman');
    await dao.definirDroits(
      auteur: admin,
      roleId: barman.id,
      niveaux: {
        ModuleTatacora.m5Bar: NiveauAcces.complet,
        ModuleTatacora.m4Restaurant: NiveauAcces.lecture,
      },
    );
    final attendu = (await role('barman')).niveaux;
    expect(attendu['M4'], 'L');
    expect(attendu['M6'], '-');
    // ANNULATIONS (hors écran) garde son niveau.
    expect(attendu['ANNULATIONS'], socleRbacCdcf['barman']!['ANNULATIONS']);
    expect(await droitsDuCompte('b1'), attendu);
    expect(await droitsDuCompte('b2'), attendu);
    expect(await droitsDuCompte('r1'), isEmpty);

    final administrateur = await role('administrateur');
    await expectLater(
      dao.definirDroits(
        auteur: admin,
        roleId: administrateur.id,
        niveaux: {ModuleTatacora.roles: NiveauAcces.lecture},
      ),
      throwsA(
        isA<RefusRoles>().having(
          (e) => e.message,
          'message',
          MessagesRoles.verrouillageAdministrateur,
        ),
      ),
    );
    expect((await role('administrateur')).conforme, isTrue);

    await expectLater(
      dao.definirDroits(auteur: lecteur, roleId: barman.id, niveaux: const {}),
      throwsA(isA<RefusRoles>()),
    );
    expect((await role('barman')).niveaux, attendu);
  });

  test('rétablir le socle : les rôles du socle et LEURS comptes réalignés, '
      'un rôle créé intact', () async {
    await dao.installerSocle();
    await compte('b1', 'barman');
    final barman = await role('barman');
    await dao.definirDroits(
      auteur: admin,
      roleId: barman.id,
      niveaux: {ModuleTatacora.m1Hebergement: NiveauAcces.complet},
    );
    final idCree = await dao.creerRole(auteur: admin, libelle: 'Serveur');
    await dao.definirDroits(
      auteur: admin,
      roleId: idCree,
      niveaux: {ModuleTatacora.m5Bar: NiveauAcces.complet},
    );

    await expectLater(
      dao.retablirSocle(auteur: lecteur),
      throwsA(isA<RefusRoles>()),
    );
    expect(await dao.retablirSocle(auteur: admin), socleRbacCdcf.length);

    final roles = await dao.roles();
    expect(matriceConformeAuSocle(roles), isTrue);
    expect((await role('barman')).niveaux, socleRbacCdcf['barman']);
    expect(await droitsDuCompte('b1'), socleRbacCdcf['barman']);
    expect(roles.singleWhere((r) => r.id == idCree).niveaux['M5'], 'C');
  });
}
