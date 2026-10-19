import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';

import 'retour_arriere_schema.dart';

/// Migration v10 -> v11 : `parametres_systeme_local`, la source locale de
/// l'écran Paramètres — éprouvée sur un FICHIER RÉEL portant des données.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais (piège 2 du
/// guide). Ces cas partent d'un fichier ramené à l'ancienne version, y sèment
/// des lignes au format de cette version, le ferment, puis le rouvrent : c'est
/// la réouverture qui emprunte `onUpgrade`, le chemin de la mise à jour.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v11_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  /// Sème, au format de la version visée, de quoi prouver que rien n'est perdu :
  /// un client, un taux de paie, un compte.
  Future<void> semer(AppDatabase db) async {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    await db
        .into(db.tauxPaieLocal)
        .insert(
          TauxPaieLocalCompanion.insert(
            cle: 'taux_cnss_salarie',
            valeur: '3.6',
            description: const Value('posé avant la mise à jour'),
          ),
        );
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'admin',
            nom: 'Admin',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
  }

  Future<bool> tableExiste(AppDatabase db, String nom) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable.withString(nom)],
        )
        .get();
    return r.isNotEmpty;
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

  group('v10 -> v11 — la mise à jour d’un poste qui travaillait déjà', () {
    test('la fixture ramène bien le fichier à une v10 SANS la table', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 10);

      expect(await tableExiste(db, 'parametres_systeme_local'), isFalse);
      expect(await version(db), 10);
      await db.close();
    });

    test('à la réouverture : table créée, VIDE, données antérieures intactes, '
        'version 11', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 10);
      await semer(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      // Ouvre le fichier : `onUpgrade` s'exécute ici.
      expect(await tableExiste(apres, 'parametres_systeme_local'), isTrue);
      // La v12 (colonnes de stock) vient APRÈS la v11 que ce test éprouve : la
      // version finale est la courante, pas 11.
      expect(await version(apres), apres.schemaVersion);

      // AUCUNE ligne semée : un taux « d'usine » posé par une migration serait
      // plausible, donc invisible (PA-53, PA-19).
      expect(await compte(apres, 'parametres_systeme_local'), 0);

      // Ce qui existait est là.
      expect(await compte(apres, 'clients_local'), 1);
      final taux = await apres.select(apres.tauxPaieLocal).getSingle();
      expect(taux.cle, 'taux_cnss_salarie');
      expect(taux.valeur, '3.6');
      expect(taux.description, 'posé avant la mise à jour');
      expect(await compte(apres, 'utilisateurs_local'), 1);
      await apres.close();
    });

    test('la table migrée est UTILISABLE : écriture, relecture après '
        'fermeture, clé étrangère de l’auteur active', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 10);
      await semer(avant);
      await avant.close();

      final ouverte = AppDatabase.surFichier(fichier);
      final dao = ParametresDao(
        ouverte,
        maintenant: () => DateTime(2026, 10, 9),
      );
      expect(
        await dao.ecrire({'entreprise_ifu': '3202612345678'}, auteurId: 'u-1'),
        ['entreprise_ifu'],
      );
      // Un auteur inexistant est refusé : la clé étrangère est une VRAIE
      // clé étrangère, sur le fichier réel aussi.
      await expectLater(
        dao.ecrire({'entreprise_rccm': 'RB/1'}, auteurId: 'fantome'),
        throwsA(anything),
      );
      await ouverte.close();

      final relue = AppDatabase.surFichier(fichier);
      expect(await ParametresDao(relue).lireTout(), {
        'entreprise_ifu': '3202612345678',
      });
      await relue.close();
    });

    test('les colonnes sont celles de la définition : clé primaire, valeur '
        'obligatoire, auteur nullable', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 10);
      await db.close();

      final apres = AppDatabase.surFichier(fichier);
      final info = await apres
          .customSelect('PRAGMA table_info(parametres_systeme_local)')
          .get();
      final colonnes = {
        for (final c in info)
          c.data['name'] as String: (
            notnull: c.data['notnull'] as int,
            pk: c.data['pk'] as int,
          ),
      };
      expect(colonnes.keys, ['cle', 'valeur', 'modifie_le', 'modifie_par']);
      expect(colonnes['cle']!.pk, 1);
      expect(colonnes['valeur']!.notnull, 1);
      expect(colonnes['modifie_le']!.notnull, 1);
      expect(colonnes['modifie_par']!.notnull, 0);
      await apres.close();
    });
  });

  group('v9 -> v11 — le poste qui a sauté une livraison', () {
    test('la chaîne v10 puis v11 s’exécute sur un fichier v9 portant des '
        'données', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 9);
      // En v9, `sync_queue` existe encore (vide : la fixture la recrée).
      expect(await tableExiste(avant, 'sync_queue'), isTrue);
      expect(await version(avant), 9);
      await semerV9(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await tableExiste(apres, 'parametres_systeme_local'), isTrue);
      expect(await compte(apres, 'parametres_systeme_local'), 0);
      // La v10 a bien eu lieu aussi (file retirée), la v11 ne l'a pas défaite.
      expect(await tableExiste(apres, 'sync_queue'), isFalse);
      expect(await tableExiste(apres, 'taux_paie_local'), isTrue);
      expect(await compte(apres, 'clients_local'), 1);
      await apres.close();
    });
  });
}

/// En v9, `taux_paie_local` n'existe pas encore (créée par la v10) : on ne sème
/// que ce qui existait.
Future<void> semerV9(AppDatabase db) async {
  await db
      .into(db.clientsLocal)
      .insert(
        ClientsLocalCompanion.insert(
          id: 'cli-1',
          nom: 'KORA',
          telephone: '+229 01 00 00 00 01',
          typeClient: 'particulier',
        ),
      );
}
