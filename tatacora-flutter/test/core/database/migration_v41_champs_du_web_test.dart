import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import 'retour_arriere_schema.dart';

/// Migration v40 -> v41 (« les champs du web que le poste ne portait pas »,
/// 27/10/2026, décisions D1 et D2 du PO) : AUCUNE table neuve et DIX colonnes
/// NULLABLES — `vehicules_local` (annee, capacite, transmission),
/// `contrats_location_local` (numero, remise, acompte, montant),
/// `plats_local` (categorie), `guides_local` (certification, tarif_jour) —,
/// éprouvées sur un FICHIER RÉEL portant des données (piège 2), y compris par un
/// poste qui a sauté des livraisons.
///
/// Additive, et RIEN n'est déduit : un contrat d'avant n'a ni montant, ni acompte,
/// ni N° (le montant n'est PAS recalculé au tarif courant), un véhicule d'avant n'a
/// ni année ni places, un plat d'avant n'a pas de catégorie (le type de son menu
/// n'en est pas une), un guide d'avant n'a ni certification ni tarif. Le curseur de
/// descente est oublié : le catalogue redescend avec ces champs.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v41_');
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

  /// Les dix colonnes que la v41 ajoute, par table.
  const ajouts = {
    'vehicules_local': {'annee', 'capacite', 'transmission'},
    'contrats_location_local': {'numero', 'remise', 'acompte', 'montant'},
    'plats_local': {'categorie'},
    'guides_local': {'certification', 'tarif_jour'},
  };

  /// Prépare un fichier à la forme [cible] et y sème ce qu'un poste portait.
  Future<Set<String>> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, cible);
    final tablesAvant = await tables(avant);
    for (final e in ajouts.entries) {
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
      "('ct-1', 'v-1', 'c-1', 1788000000, 1788259200)",
    );
    await avant.customStatement(
      'INSERT INTO guides_local (id, nom, zone_competence) '
      "VALUES ('g-1', 'Moussa', 'Atacora')",
    );
    if (cible >= 5) {
      await avant.customStatement(
        'INSERT INTO utilisateurs_local (id, login, nom, role, droits_json, '
        'sel, empreinte, iterations, date_creation, date_mot_de_passe) VALUES '
        "('u-1', 'admin', 'Admin', 'administrateur', '{}', 's', 'e', 1, 0, 0)",
      );
    }
    if (cible >= 14) {
      await avant.customStatement(
        'INSERT INTO menus_local (id, libelle, type, cree_le, cree_par) '
        "VALUES ('m-1', 'Carte', 'local', 0, 'u-1')",
      );
      await avant.customStatement(
        'INSERT INTO recettes_local (id, libelle, cree_le, cree_par) '
        "VALUES ('r-1', 'Riz', 0, 'u-1')",
      );
      await avant.customStatement(
        'INSERT INTO plats_local (id, menu_id, recette_id, libelle, '
        'prix_vente, cree_le, cree_par) VALUES '
        "('p-1', 'm-1', 'r-1', 'Riz sauce', 2500, 0, 'u-1')",
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

  for (final depart in const [40, 38, 36, 30, 26, 14]) {
    test('v$depart -> courante : AUCUNE table neuve, les dix colonnes sont NULL '
        'pour l’existant, tout est INTACT, et ça sert', () async {
      final tablesAvant = await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(41));
      // Le compte de tables ne bouge pas à cause de la v41 : aucune table n'y naît
      // (les tables des versions ultérieures, s'il y en a, ne sont pas de ce test).
      expect(await tables(apres), containsAll(tablesAvant));

      // Les dix colonnes existent.
      for (final e in ajouts.entries) {
        expect(await colonnes(apres, e.key), containsAll(e.value));
      }

      // L'existant est INTACT et rien n'est fabriqué.
      expect(await compte(apres, 'vehicules_local'), 1);
      expect(await compte(apres, 'contrats_location_local'), 1);
      expect(await compte(apres, 'guides_local'), 1);
      final v = await apres
          .customSelect(
            'SELECT annee, capacite, transmission, tarif_jour '
            "FROM vehicules_local WHERE id = 'v-1'",
          )
          .getSingle();
      expect(
        [v.data['annee'], v.data['capacite'], v.data['transmission']],
        [null, null, null],
      );
      expect(v.data['tarif_jour'], 25000);
      final c = await apres
          .customSelect(
            'SELECT numero, remise, acompte, montant FROM '
            "contrats_location_local WHERE id = 'ct-1'",
          )
          .getSingle();
      expect(
        [
          c.data['numero'],
          c.data['remise'],
          c.data['acompte'],
          c.data['montant'],
        ],
        [null, null, null, null],
        reason: 'aucun montant déduit du tarif courant, aucun N° inventé',
      );
      final g = await apres
          .customSelect(
            'SELECT certification, tarif_jour FROM guides_local '
            "WHERE id = 'g-1'",
          )
          .getSingle();
      expect([g.data['certification'], g.data['tarif_jour']], [null, null]);
      if (depart >= 14) {
        expect(await compte(apres, 'plats_local'), 1);
        final p = await apres
            .customSelect(
              "SELECT categorie, prix_vente FROM plats_local WHERE id = 'p-1'",
            )
            .getSingle();
        expect(
          p.data['categorie'],
          isNull,
          reason: 'le menu n’est pas une catégorie',
        );
        expect(p.data['prix_vente'], 2500);
      }
      if (depart >= 27) {
        // Le curseur est OUBLIÉ (le catalogue redescend avec ses nouveaux champs) ;
        // le reste de l'état — la génération des données du serveur — est intact.
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

      // Les colonnes SERVENT : le DAO y écrit, l'entité les relit, et le contrat
      // d'avant reste « — » (montant nul, jamais le tarif courant).
      final dao = VehiculeDao(apres);
      final neuf = await dao.enregistrerVehicule(
        immatriculation: 'BJ-2',
        categorie: CategorieVehicule.quatreQuatre,
        tarifJour: 30000,
        annee: 2022,
        capacite: 7,
        transmission: 'Automatique',
      );
      expect((await dao.vehicule(neuf.id))!.capacite, 7);
      final ancien = (await dao.contrats()).single;
      expect(ancien.id, 'ct-1');
      expect(ancien.montant, isNull);
      expect(ancien.resteDu, isNull);
      expect((await dao.vehicule('v-1'))!.annee, isNull);

      await apres.customStatement(
        'INSERT INTO clients_local (id, nom, telephone, type_client) '
        "VALUES ('c-2', 'SABI', '+229 01 00 00 00 02', 'particulier')",
      );
      final signe = await dao.creerContrat(
        SaisieContrat(
          vehiculeId: neuf.id,
          clientId: 'c-2',
          debut: DateTime(2026, 11, 1),
          fin: DateTime(2026, 11, 4),
          pieceIdentite: 'CNI',
          permisConduire: 'P',
          remiseFrancs: 5000,
          acompteFrancs: 20000,
        ),
      );
      expect(
        [signe.montant, signe.acompte, signe.resteDu],
        ['85000.00', '20000.00', '65000.00'],
      );
      await apres.close();

      // Et la donnée écrite survit à la réouverture.
      final relue = AppDatabase.surFichier(fichier);
      final ligne = await relue
          .customSelect(
            'SELECT montant, remise, acompte, numero FROM '
            "contrats_location_local WHERE id = '${signe.id}'",
          )
          .getSingle();
      expect(
        [
          ligne.data['montant'],
          ligne.data['remise'],
          ligne.data['acompte'],
          ligne.data['numero'],
        ],
        [85000, 5000, 20000, null],
      );
      expect(signe.statut, statutContratActif);
      await relue.close();
    });
  }

  test(
    'une migration se REJOUE (piège 3) : un fichier déjà à la forme v41 mais '
    'marqué v40 ne plante pas et ne perd rien',
    () async {
      final base = AppDatabase.surFichier(fichier);
      await base.customStatement('SELECT 1');
      await base.customStatement(
        'INSERT INTO vehicules_local (id, categorie, immatriculation, '
        'tarif_jour, statut, annee, capacite) VALUES '
        "('v-1', 'voiture', 'BJ-1', 25000, 'disponible', 2021, 5)",
      );
      await base.customStatement('PRAGMA user_version = 40');
      await base.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await compte(apres, 'vehicules_local'), 1);
      final v = await apres
          .customSelect('SELECT annee, capacite FROM vehicules_local')
          .getSingle();
      expect([v.data['annee'], v.data['capacite']], [2021, 5]);
      for (final e in ajouts.entries) {
        expect(await colonnes(apres, e.key), containsAll(e.value));
      }
      await apres.close();
    },
  );

  test('le retour arrière de la v41 retire EXACTEMENT les dix colonnes '
      '(fixture symétrique)', () async {
    final base = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(base, 40);
    for (final e in ajouts.entries) {
      final presentes = await colonnes(base, e.key);
      for (final c in e.value) {
        expect(presentes, isNot(contains(c)));
      }
    }
    await base.close();
  });
}
