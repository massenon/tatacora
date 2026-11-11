import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectations_recues_dao.dart';

import 'retour_arriere_schema.dart';

/// Migration -> v53 (09/11/2026 : AFFECTATIONS DU RÉSULTAT REÇUES du serveur) : UNE table
/// NEUVE, `affectations_resultat_local`, aucune colonne ajoutée à une table existante,
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2), y compris en sautant des
/// versions (le poste qui a raté des livraisons).
///
/// Additive, et rien n'est déduit : aucune affectation n'est fabriquée (la table
/// APPARAÎT vide : les affectations viennent du serveur, par la descente), aucune ligne
/// d'avant ne disparaît, une pièce d'avant n'est jamais prise pour une affectation. Le
/// curseur de descente est oublié : les affectations déjà passées au serveur
/// redescendent.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v53_');
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

  Future<bool> tableExiste(AppDatabase db, String nom) async =>
      (await db
              .customSelect(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = '$nom'",
              )
              .get())
          .isNotEmpty;

  /// Une base de la forme [cible] : la courante, ramenée en arrière par le fichier
  /// central des retours arrière, avec des données d'avant (un exercice, une pièce
  /// libellée comme une affectation, un client) et un curseur de descente.
  Future<void> preparer(int cible) async {
    final avant = AppDatabase.surFichier(fichier);
    await avant.customStatement('SELECT 1');
    await ramenerSchemaA(avant, cible);
    expect(await tableExiste(avant, 'affectations_resultat_local'), isFalse);
    await avant.customStatement(
      'INSERT INTO exercices_local (id, annee, date_debut, date_fin, statut) '
      "VALUES ('x-2030', 2030, '2030-01-01', '2030-12-31', 'cloture')",
    );
    await avant.customStatement(
      'INSERT INTO clients_local (id, nom, telephone, type_client) VALUES '
      "('c-1', 'Sabi', '96000003', 'groupe')",
    );
    await avant.customStatement(
      'INSERT INTO etat_synchronisation_local (cle, valeur, modifie_le) '
      "VALUES ('descente.curseur', 'abc', 0), ('serveur.generation', 'g1', 0)",
    );
    await avant.close();
  }

  for (final depart in const [52, 51, 44, 40]) {
    test('v$depart -> v53 : une table NEUVE et VIDE, aucune affectation '
        'fabriquée, aucune ligne perdue, et ça sert', () async {
      await preparer(depart);

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(53));
      expect(await tableExiste(apres, 'affectations_resultat_local'), isTrue);

      final c = await colonnes(apres, 'affectations_resultat_local');
      expect(
        c.keys,
        containsAll([
          'id',
          'annee',
          'resultat_centimes',
          'date_approbation',
          'reserve_legale_centimes',
          'autres_reserves_centimes',
          'dividendes_centimes',
          'report_crediteur_centimes',
          'report_debiteur_centimes',
          'numero_piece',
          'piece_origine_id',
          'auteur_login',
          'affectee_le',
          'contrepassee_le',
        ]),
      );
      expect(
        c['piece_origine_id'],
        isFalse,
        reason: 'NULLABLE : une affectation du web n\'a pas de pièce de poste',
      );
      expect(
        c['contrepassee_le'],
        isFalse,
        reason: 'NULLABLE : active tant que vide',
      );
      expect(c['auteur_login'], isFalse);

      // Rien n'est fabriqué ; les données d'avant sont intactes.
      expect(
        (await apres
                .customSelect(
                  'SELECT COUNT(*) AS n FROM affectations_resultat_local',
                )
                .getSingle())
            .data['n'],
        0,
      );
      expect(
        (await apres
                .customSelect(
                  "SELECT statut FROM exercices_local WHERE id = 'x-2030'",
                )
                .getSingle())
            .data['statut'],
        'cloture',
      );
      expect(
        (await apres
                .customSelect("SELECT nom FROM clients_local WHERE id = 'c-1'")
                .getSingle())
            .data['nom'],
        'Sabi',
      );
      final etat = {
        for (final l
            in await apres
                .customSelect(
                  'SELECT cle, valeur FROM etat_synchronisation_local',
                )
                .get())
          l.data['cle'] as String: l.data['valeur'] as String,
      };
      expect(
        etat.containsKey('descente.curseur'),
        isFalse,
        reason: 'le curseur est OUBLIÉ : les affectations redescendent',
      );
      expect(etat['serveur.generation'], 'g1');

      // La table SERT, par son seul écrivain, et survit à la réouverture.
      await AffectationsRecuesDao(apres).inscrire(
        AffectationRecueDuServeur(
          id: 'aff-1',
          annee: 2030,
          resultatCentimes: 7000000,
          dateApprobation: '2031-04-30',
          reserveLegaleCentimes: 700000,
          autresReservesCentimes: 0,
          dividendesCentimes: 0,
          reportCrediteurCentimes: 6300000,
          reportDebiteurCentimes: 0,
          numeroPiece: 'OD-2031-00001',
          pieceOrigineId: null,
          auteurLogin: 'comptable',
          affecteeLe: DateTime(2031, 5, 2, 14, 30),
          contrepasseeLe: null,
        ),
      );
      await apres.close();

      final rouvert = AppDatabase.surFichier(fichier);
      final lues = await AffectationsRecuesDao(rouvert).deLAnnee(2030);
      expect(lues.single.numeroPiece, 'OD-2031-00001');
      expect(lues.single.reportCrediteurCentimes, 6300000);
      expect(lues.single.contrepassee, isFalse);
      expect(await version(rouvert), rouvert.schemaVersion);
      await rouvert.close();
    });
  }

  test('un fichier de la forme v53 marqué v52 se rejoue sans « already exists » '
      'et ne perd pas une affectation déjà reçue', () async {
    final base = AppDatabase.surFichier(fichier);
    await base.customStatement('SELECT 1');
    await base.customStatement(
      'INSERT INTO affectations_resultat_local (id, annee, resultat_centimes, '
      'date_approbation, numero_piece, affectee_le) VALUES '
      "('aff-9', 2030, 100, '2031-04-30', 'OD-2031-00009', 0)",
    );
    await base.customStatement('PRAGMA user_version = 52');
    await base.close();

    final rejoue = AppDatabase.surFichier(fichier);
    expect(await tableExiste(rejoue, 'affectations_resultat_local'), isTrue);
    expect(
      (await rejoue
              .customSelect(
                'SELECT COUNT(*) AS n FROM affectations_resultat_local',
              )
              .getSingle())
          .data['n'],
      1,
      reason: 'la migration conditionnelle ne recrée pas, ne vide pas',
    );
    expect(await version(rejoue), rejoue.schemaVersion);
    await rejoue.close();
  });
}
