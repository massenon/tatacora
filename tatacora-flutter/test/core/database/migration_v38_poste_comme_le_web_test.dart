import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/historique_prix_carte_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/changement_prix_carte.dart';

import 'retour_arriere_schema.dart';

/// Migration v37 -> v38 (« le poste fait ce que le web fait », 26/10/2026) :
/// UNE table neuve (`historique_prix_carte_local`) et SIX colonnes nullables
/// (`contrats_location_local.statut`, `operations_sync_local.auteur_login` /
/// `.poste_nom`, `paniers_local.numero_vente` / `.auteur_login`), éprouvées sur
/// un FICHIER RÉEL portant des données (piège 2), y compris par un poste qui a
/// sauté des livraisons.
///
/// Additive, et rien n'est déduit : un contrat d'avant n'a pas de statut, une
/// opération d'avant n'a ni auteur ni poste, un panier d'avant n'a ni numéro ni
/// auteur — « — » à l'écran, jamais une valeur plausible fabriquée. Le curseur
/// de descente est oublié, pour que l'historique et les statuts déjà au serveur
/// redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v38_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<Set<String>> tables(AppDatabase db) async => {
    for (final l
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
      l.data['name'] as String,
  };

  Future<Set<String>> colonnes(AppDatabase db, String table) async => {
    for (final c in await db.customSelect('PRAGMA table_info($table)').get())
      c.data['name'] as String,
  };

  Future<int> compte(AppDatabase db, String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  Future<int> version(AppDatabase db) async =>
      (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .first
          as int;

  /// Les six colonnes que la v38 ajoute, par table.
  const ajouts = {
    'contrats_location_local': {'statut'},
    'operations_sync_local': {'auteur_login', 'poste_nom'},
    'paniers_local': {'numero_vente', 'auteur_login'},
  };

  /// Prépare un fichier à la forme [cible] et y sème ce qu'un poste portait.
  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    for (final t in tablesAjouteesEnV38) {
      expect(tablesAvant, isNot(contains(t)), reason: 'imiter une v$cible');
    }
    for (final e in ajouts.entries) {
      if (!tablesAvant.contains(e.key)) continue;
      for (final c in e.value) {
        expect(
          await colonnes(avant, e.key),
          isNot(contains(c)),
          reason: '${e.key}.$c absente d’une v$cible',
        );
      }
    }
    expect(await version(avant), cible);

    await avant.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
    );
    await avant.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) '
      "VALUES ('c-1', 'KORA', '+229 01 00 00 00 01', 'particulier')",
    );
    await avant.customStatement(
      'INSERT INTO contrats_location_local (id, vehicule_id, client_id, '
      'date_debut, date_fin) VALUES '
      "('ct-1', 'v-1', 'c-1', 1788000000, 1788172800)",
    );
    if (cible >= 3) {
      await avant.customStatement(
        "INSERT INTO paniers_local (id, type_vente) VALUES ('p-1', 'comptant')",
      );
    }
    if (cible >= 26) {
      await avant.customStatement(
        'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
        'entite_id, type, payload, horodatage_client, cree_le) VALUES '
        "('u-1', 'clients', 'c-1', 'creation', '{}', "
        "'2026-10-20T08:00:00Z', 1788000000)",
      );
    }
    if (cible >= 27) {
      await avant.customStatement(
        'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
        "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
      );
    }
    await avant.close();
    return tablesAvant;
  }

  for (final depart in const [37, 36, 30, 26, 10]) {
    test('v$depart -> courante : la table apparaît VIDE, les six colonnes sont '
        'NULL pour l’existant, tout est INTACT, et ça sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(38));
      expect(
        await tables(apres),
        containsAll([...tablesAvant, ...tablesAjouteesEnV38]),
      );
      expect(await compte(apres, 'historique_prix_carte_local'), 0);

      // Les six colonnes existent.
      for (final e in ajouts.entries) {
        expect(await colonnes(apres, e.key), containsAll(e.value));
      }

      // L'existant est INTACT et rien n'est fabriqué.
      expect(await compte(apres, 'vehicules_local'), 1);
      expect(await compte(apres, 'contrats_location_local'), 1);
      final contrat = await apres
          .customSelect(
            "SELECT statut FROM contrats_location_local WHERE id = 'ct-1'",
          )
          .getSingle();
      expect(contrat.data['statut'], isNull, reason: 'aucun statut déduit');
      if (depart >= 3) {
        final panier = await apres
            .customSelect(
              'SELECT numero_vente, auteur_login FROM paniers_local '
              "WHERE id = 'p-1'",
            )
            .getSingle();
        expect(panier.data['numero_vente'], isNull);
        expect(panier.data['auteur_login'], isNull);
      }
      if (depart >= 26) {
        expect(await compte(apres, 'operations_sync_local'), 1);
        final op = await apres
            .customSelect(
              'SELECT auteur_login, poste_nom FROM operations_sync_local',
            )
            .getSingle();
        expect(op.data['auteur_login'], isNull);
        expect(op.data['poste_nom'], isNull);
      }
      if (depart >= 27) {
        // Le curseur est OUBLIÉ (l'historique et les statuts redescendent) ; le
        // reste de l'état — la génération des données du serveur — est intact.
        final etat = {
          for (final l
              in await apres
                  .customSelect(
                    'SELECT cle, valeur FROM etat_synchronisation_local',
                  )
                  .get())
            l.data['cle'] as String: l.data['valeur'] as String,
        };
        expect(etat.containsKey('descente.curseur'), isFalse);
        expect(etat['serveur.generation'], 'g1');
      }

      // La table neuve SERT : la DAO y écrit, et ses contraintes tiennent.
      final dao = HistoriquePrixCarteDao(apres);
      await apres.transaction(
        () => dao.tracer(
          source: SourceCarte.boisson,
          sourceId: 'b-1',
          changements: changementsDePrix(prixAvant: 1000, prixApres: 1200),
        ),
      );
      expect(await compte(apres, 'historique_prix_carte_local'), 1);
      await expectLater(
        apres.customStatement(
          'INSERT INTO historique_prix_carte_local (id, source, source_id, '
          "champ, cree_le) VALUES ('x', 'inconnue', 'b-1', 'prix_vente', 0)",
        ),
        throwsA(anything),
        reason: 'source : registre fermé',
      );
      await expectLater(
        apres.customStatement(
          'INSERT INTO historique_prix_carte_local (id, source, source_id, '
          "champ, cree_le) VALUES ('y', 'plat', 'p-1', 'prix_achat', 0)",
        ),
        throwsA(anything),
        reason: 'champ : registre fermé',
      );
      await apres.close();

      // Et la donnée écrite survit à la réouverture.
      final relue = AppDatabase.surFichier(fichier);
      expect(await compte(relue, 'historique_prix_carte_local'), 1);
      final trace = await relue
          .customSelect(
            'SELECT source, champ, ancien_prix, nouveau_prix, par, '
            'recu_du_serveur FROM historique_prix_carte_local',
          )
          .getSingle();
      expect(trace.data['source'], 'carte_boisson');
      expect(trace.data['champ'], 'prix_vente');
      expect(trace.data['ancien_prix'], '1000.00');
      expect(trace.data['nouveau_prix'], '1200.00');
      expect(trace.data['recu_du_serveur'], 0);
      await relue.close();
    });
  }

  test('une migration se REJOUE (piège 3) : un fichier déjà à la forme v38 '
      'mais marqué v37 ne plante pas et ne perd rien', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO vehicules_local (id, categorie, immatriculation, '
      "tarif_jour, statut) VALUES ('v-1', 'voiture', 'BJ-1', 25000, 'disponible')",
    );
    await base.customStatement('PRAGMA user_version = 37');
    await base.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(await compte(apres, 'vehicules_local'), 1);
    for (final e in ajouts.entries) {
      expect(await colonnes(apres, e.key), containsAll(e.value));
    }
    await apres.close();
  });
}
