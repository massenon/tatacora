import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/sejour_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_sejour.dart';

import 'retour_arriere_schema.dart';

/// Migration v21 -> v23 : DEUX tables neuves (`alertes_vues_local` en v22,
/// `sejours_local` en v23, lots B et C du 14/10/2026), éprouvée sur un FICHIER
/// RÉEL portant une réservation (piège 2), en sautant la v22.
///
/// Additive : aucune table existante n'est touchée, et AUCUNE ligne n'est
/// fabriquée — une migration ne sait pas quel client est réellement arrivé,
/// ni quelle alerte un compte a lue. La réservation d'avant reste « sans
/// séjour », et son arrivée se pointe au geste.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v23_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  Future<int> version(AppDatabase db) async {
    final r = await db.customSelect('PRAGMA user_version').getSingle();
    return r.data.values.first as int;
  }

  Future<Set<String>> tables(AppDatabase db) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    return {for (final l in r) l.data['name'] as String};
  }

  Future<int> compter(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  /// Ce que le poste portait AVANT, au format v21 : un parc d'une unité, un
  /// client et une réservation confirmée dont l'arrivée est le 14/10/2026.
  Future<void> semerAvant(AppDatabase db) async {
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT INTO unites_hebergement_local (id, categorie_id, numero, statut) '
      "VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01 00 00 00 01', 'particulier')",
    );
    final arrivee = DateTime.utc(2026, 10, 14).millisecondsSinceEpoch ~/ 1000;
    final depart = DateTime.utc(2026, 10, 16).millisecondsSinceEpoch ~/ 1000;
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte, mode_paiement) '
      "VALUES ('res-1', 'LOC-A', 'cli-1', 'u-1', ?, ?, 'confirmee', 28000, "
      "5000, 'especes')",
      [arrivee, depart],
    );
  }

  test('la fixture ramène le fichier à la forme v21 : les deux tables '
      'manquent', () async {
    final db = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(db, 21);
    expect(await version(db), 21);
    final noms = await tables(db);
    expect(noms.intersection(tablesAjouteesEnV22), isEmpty);
    expect(noms.intersection(tablesAjouteesEnV23), isEmpty);
    await db.close();
  });

  test('v21 -> v23 : les deux tables APPARAISSENT, rien d’autre ne bouge, '
      'la réservation est INTACTE et aucune ligne n’est fabriquée', () async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, 21);
    await semerAvant(avant);
    final tablesAvant = await tables(avant);
    await avant.close();

    final apres = AppDatabase.surFichier(fichier);
    expect(await version(apres), apres.schemaVersion);
    expect(apres.schemaVersion, greaterThanOrEqualTo(23));
    expect(await tables(apres), {
      ...tablesAvant,
      ...tablesAjouteesEnV22,
      ...tablesAjouteesEnV23,
      ...tablesAjouteesEnV24,
      ...tablesAjouteesEnV25,
      ...tablesAjouteesEnV26,
    });

    final r = await apres
        .customSelect(
          'SELECT reference, statut, acompte, unite_id FROM reservations_local',
        )
        .getSingle();
    expect(
      (r.data['reference'], r.data['statut'], r.data['acompte']),
      ('LOC-A', 'confirmee', 5000),
    );
    expect(await compter(apres, 'sejours_local'), 0);
    expect(await compter(apres, 'alertes_vues_local'), 0);
    final u = await apres
        .customSelect('SELECT statut FROM unites_hebergement_local')
        .getSingle();
    expect(u.data['statut'], 'libre');
    await apres.close();
  });

  test('le poste migré est UTILISABLE : la réservation d’avant se pointe '
      'au geste (check-in), une seule fois', () async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, 21);
    await semerAvant(avant);
    await avant.close();

    final db = AppDatabase.surFichier(fichier);
    final dao = SejourDao(db, maintenant: () => DateTime(2026, 10, 14, 9));
    await dao.checkin('res-1');
    expect(await dao.reservationsAuSejourOuvert(), {'res-1'});
    expect(
      (await db
              .customSelect('SELECT statut FROM reservations_local')
              .getSingle())
          .data['statut'],
      'en_cours',
    );
    await expectLater(dao.checkin('res-1'), throwsA(isA<RefusSejour>()));
    await db.close();
  });
}
