import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/transverse/data/messages_editeur_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/messages_editeur.dart';

import 'retour_arriere_schema.dart';

/// Migration v24 -> v25 : UNE table neuve (`messages_editeur_local`, boîte
/// d'envoi de « Contactez l'éditeur », Lot J2 du 14/10/2026), éprouvée sur un
/// FICHIER RÉEL portant des données (piège 2), y compris par un poste qui a
/// sauté des livraisons (depuis la v21 et depuis la v10).
///
/// Additive : aucune table existante n'est touchée, et AUCUNE ligne n'est
/// semée — avant la v25, le poste n'enregistrait aucun envoi.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v25_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> tables(AppDatabase db) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return {for (final l in r) l.data['name'] as String};
  }

  Future<int> compte(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<int> version(AppDatabase db) async {
    final r = await db.customSelect('PRAGMA user_version').getSingle();
    return r.data.values.first as int;
  }

  /// Sème, au format d'une version ancienne (v10 et après), de quoi prouver
  /// que rien n'est perdu : un compte et un client.
  Future<void> semer(AppDatabase db) async {
    await db.customStatement(
      'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, sel, '
      'empreinte, iterations, actif, date_creation, date_mot_de_passe) '
      "VALUES ('u-1', 'admin', 'Admin', 'administrateur', '{\"PARAM\":\"C\"}', "
      "'s', 'e', 1, 1, 0, 0)",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', '+229 01 00 00 00 01', 'particulier')",
    );
  }

  /// Ramène le fichier à [cible], y sème le jeu d'avant, puis le ferme.
  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    expect(
      tablesAvant,
      isNot(contains('messages_editeur_local')),
      reason: 'la fixture doit imiter une v$cible, qui n’a pas la boîte',
    );
    expect(await version(avant), cible);
    await semer(avant);
    await avant.close();
    return tablesAvant;
  }

  /// Les données d'avant, relues sur le fichier migré.
  Future<void> exigerDonneesIntactes(AppDatabase db) async {
    final u = await db
        .customSelect('SELECT login, role, droits_json FROM utilisateurs_local')
        .getSingle();
    expect(
      (u.data['login'], u.data['role'], u.data['droits_json']),
      ('admin', 'administrateur', '{"PARAM":"C"}'),
    );
    final c = await db
        .customSelect('SELECT nom, telephone FROM clients_local')
        .getSingle();
    expect(
      (c.data['nom'], c.data['telephone']),
      ('KORA', '+229 01 00 00 00 01'),
    );
  }

  const SaisieMessageEditeur saisie = (
    type: TypeMessageEditeur.bug,
    sujet: 'Bug — Point de vente',
    moduleConcerne: 'Point de vente',
    corps: 'Le ticket ne sort pas.',
    etapes: '1. Encaisser\n2. Imprimer',
  );

  test('v24 -> v25 : la table APPARAÎT vide, les données d’avant sont '
      'INTACTES, user_version = courante', () async {
    final tablesAvant = await preparer(24);

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(apres.schemaVersion, greaterThanOrEqualTo(25));
    expect(await tables(apres), {
      ...tablesAvant,
      ...tablesAjouteesEnV25,
      ...tablesAjouteesEnV26,
      ...tablesAjouteesEnV27,
      ...tablesAjouteesEnV28,
      ...tablesAjouteesEnV29,
      ...tablesAjouteesEnV31,
      ...tablesAjouteesEnV32,
      ...tablesAjouteesEnV33,
      ...tablesAjouteesEnV34,
      ...tablesAjouteesEnV35,
      ...tablesAjouteesEnV37,
      ...tablesAjouteesEnV38,
    });
    expect(
      await compte(apres, 'messages_editeur_local'),
      0,
      reason: 'la migration ne fabrique aucun envoi',
    );
    await exigerDonneesIntactes(apres);
    await apres.close();
  });

  test('les colonnes sont EXACTEMENT celles de la définition : nom, '
      'nullabilité, défauts, clé primaire', () async {
    await preparer(24);

    final apres = AppDatabase.surFichier(fichier);
    final info = await apres
        .customSelect('PRAGMA table_info(messages_editeur_local)')
        .get();
    final colonnes = {
      for (final l in info)
        l.data['name'] as String: (
          notnull: l.data['notnull'] as int,
          defaut: l.data['dflt_value'] as String?,
          pk: l.data['pk'] as int,
        ),
    };
    expect(colonnes.keys.toList(), [
      'id',
      'type',
      'sujet',
      'module_concerne',
      'corps',
      'etapes',
      'auteur_id',
      'auteur_login',
      'poste',
      'cree_le',
      'statut',
      'tentatives',
      'derniere_erreur',
      'derniere_tentative',
      'envoye_le',
    ]);
    expect(colonnes['id']!.pk, 1);
    for (final obligatoire in [
      'id',
      'type',
      'sujet',
      'corps',
      'cree_le',
      'statut',
      'tentatives',
    ]) {
      expect(colonnes[obligatoire]!.notnull, 1, reason: obligatoire);
    }
    for (final facultative in [
      'module_concerne',
      'etapes',
      'auteur_id',
      'auteur_login',
      'poste',
      'derniere_erreur',
      'derniere_tentative',
      'envoye_le',
    ]) {
      expect(colonnes[facultative]!.notnull, 0, reason: facultative);
    }
    expect(colonnes['statut']!.defaut, "'en_attente'");
    expect(colonnes['tentatives']!.defaut, '0');

    // La seule clé étrangère : l'auteur, vers `utilisateurs_local`.
    final cles = await apres
        .customSelect('PRAGMA foreign_key_list(messages_editeur_local)')
        .get();
    expect(
      [for (final l in cles) (l.data['from'], l.data['table'], l.data['to'])],
      [('auteur_id', 'utilisateurs_local', 'id')],
    );
    await apres.close();
  });

  test(
    'contraintes tenues sur le fichier migré : auteur fantôme refusé, '
    'statut par défaut « en_attente », aucun mot de passe en colonne',
    () async {
      await preparer(24);

      final apres = AppDatabase.surFichier(fichier);
      await expectLater(
        apres.customStatement(
          'INSERT INTO messages_editeur_local (id, type, sujet, corps, '
          "auteur_id, cree_le) VALUES ('m-x', 'message', 's', 'c', "
          "'fantome', 0)",
        ),
        throwsA(anything),
        reason: 'la clé étrangère est ACTIVE sur le fichier réel',
      );
      expect(await compte(apres, 'messages_editeur_local'), 0);

      await apres.customStatement(
        'INSERT INTO messages_editeur_local (id, type, sujet, corps, '
        "auteur_id, cree_le) VALUES ('m-1', 'message', 's', 'c', 'u-1', 0)",
      );
      final l = await apres
          .customSelect(
            "SELECT statut, tentatives FROM messages_editeur_local WHERE id = 'm-1'",
          )
          .getSingle();
      expect((l.data['statut'], l.data['tentatives']), ('en_attente', 0));
      expect(StatutMessageEditeur.values.map((s) => s.code), [
        'en_attente',
        'envoye',
        'echec',
      ], reason: 'les trois statuts que le DAO écrit, ni plus ni moins');

      final info = await apres
          .customSelect('PRAGMA table_info(messages_editeur_local)')
          .get();
      for (final r in info) {
        expect(
          r.data['name'] as String,
          isNot(matches(RegExp('mot_de_passe|password|secret'))),
        );
      }
      await apres.close();
    },
  );

  test('la table migrée est UTILISABLE : le DAO écrit, marque envoyé, et '
      'relit après fermeture', () async {
    await preparer(24);

    final ouverte = AppDatabase.surFichier(fichier);
    final dao = MessagesEditeurDao(ouverte);
    final ecrit = await dao.enregistrer(
      saisie,
      auteurId: 'u-1',
      auteurLogin: 'admin',
      poste: 'COMPTOIR-1',
      maintenant: DateTime(2026, 10, 14, 9, 30),
    );
    expect(ecrit.statut, StatutMessageEditeur.enAttente);
    expect((await dao.enAttente()).single.id, ecrit.id);
    await dao.marquerEnvoye(
      ecrit.id,
      maintenant: DateTime(2026, 10, 14, 9, 31),
    );
    await ouverte.close();

    final relue = AppDatabase.surFichier(fichier);
    final m = (await MessagesEditeurDao(relue).parId(ecrit.id))!;
    expect(m.type, TypeMessageEditeur.bug);
    expect(m.sujet, 'Bug — Point de vente');
    expect(m.moduleConcerne, 'Point de vente');
    expect(m.corps, 'Le ticket ne sort pas.');
    expect(m.etapes, '1. Encaisser\n2. Imprimer');
    expect(m.auteurLogin, 'admin');
    expect(m.poste, 'COMPTOIR-1');
    expect(m.creeLe, DateTime(2026, 10, 14, 9, 30));
    expect(m.statut, StatutMessageEditeur.envoye);
    expect(m.envoyeLe, DateTime(2026, 10, 14, 9, 31));
    expect(await MessagesEditeurDao(relue).enAttente(), isEmpty);
    await exigerDonneesIntactes(relue);
    await relue.close();
  });

  group('versions SAUTÉES : le poste qui a raté des livraisons', () {
    for (final depart in const [21, 10]) {
      test('v$depart -> courante : la boîte apparaît vide, rien n’est perdu, '
          'et elle sert', () async {
        final tablesAvant = await preparer(depart);

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);
        final tablesApres = await tables(apres);
        expect(tablesApres, containsAll(tablesAvant));
        expect(tablesApres, containsAll(tablesAjouteesEnV25));
        expect(await compte(apres, 'messages_editeur_local'), 0);
        await exigerDonneesIntactes(apres);

        final ecrit = await MessagesEditeurDao(apres).enregistrer(
          saisie,
          auteurId: 'u-1',
          auteurLogin: 'admin',
          poste: null,
          maintenant: DateTime(2026, 10, 14),
        );
        expect(
          (await MessagesEditeurDao(apres).parId(ecrit.id))!.corps,
          'Le ticket ne sort pas.',
        );
        await apres.close();
      });
    }
  });
}
