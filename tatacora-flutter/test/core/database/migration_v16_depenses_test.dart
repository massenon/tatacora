import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';
import '../../features/depenses/support/outils_depenses.dart';
import 'retour_arriere_schema.dart';

/// Migration v15 -> v16 : DEUX colonnes ajoutées à `depenses_local`
/// (`ecriture_id`, `ecriture_refus`) — éprouvée sur un FICHIER RÉEL portant des
/// dépenses (piège 2), y compris en sautant des versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des dépenses AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Les colonnes sont AJOUTÉES, jamais la table recréée : les dépenses saisies
/// avant la mise à jour sont la seule copie qui existe. Et la migration NE
/// FABRIQUE AUCUNE PIÈCE : ces dépenses restent « sans pièce comptable » jusqu'au
/// geste explicite de rattrapage.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v16_');
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

  Future<int> compte(AppDatabase db, String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<List<String>> colonnes(AppDatabase db, String table) async {
    final r = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final c in r) c.data['name'] as String];
  }

  Future<int> nombreDeTables(AppDatabase db) async =>
      (await db
                  .customSelect(
                    "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
                    "AND name NOT LIKE 'sqlite_%'",
                  )
                  .getSingle())
              .data['n']
          as int;

  /// Ce que le poste portait AVANT : un auteur, et DEUX dépenses au format v15 —
  /// une à trois lignes (un compte de l'ancien registre à six chiffres) et une
  /// à une ligne (un compte du plan).
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    const jour = 1787000000; // un instant de septembre 2026
    await db.customStatement(
      'INSERT INTO depenses_local (id, date_transaction, tresorerie, libelle, '
      'saisie_le) VALUES (?, ?, ?, ?, ?)',
      ['dep-1', jour, 'caisse', 'Marché du matin', jour],
    );
    for (final (id, compte, montant) in [
      ('l-1', '601100', 15000),
      ('l-2', '601100', 8500),
      ('l-3', '605100', 3500),
    ]) {
      await db.customStatement(
        'INSERT INTO lignes_depense_local (id, depense_id, libelle, '
        'compte_charge, nature, famille, montant, ajoutee_le) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        [id, 'dep-1', 'Achat $id', compte, 'Tomate', 'Marché', montant, jour],
      );
    }
    await db.customStatement(
      'INSERT INTO depenses_local (id, date_transaction, tresorerie, libelle, '
      'saisie_le) VALUES (?, ?, ?, ?, ?)',
      ['dep-2', jour + 86400, 'banque', 'Électricité', jour + 86400],
    );
    await db.customStatement(
      'INSERT INTO lignes_depense_local (id, depense_id, libelle, '
      'compte_charge, nature, famille, montant, ajoutee_le) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'l-4',
        'dep-2',
        'Recharge',
        '6052',
        'Électricité / eau',
        'Services',
        45000,
        jour,
      ],
    );
  }

  group('v15 -> v16 — la mise à jour d’un poste qui avait des dépenses', () {
    test('la fixture ramène bien le fichier à la forme v15 : deux colonnes en '
        'moins', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 15);

      expect(await version(db), 15);
      expect(await colonnes(db, 'depenses_local'), [
        'id',
        'date_transaction',
        'tresorerie',
        'libelle',
        'saisie_le',
      ]);
      await db.close();
    });

    test('à la réouverture : colonnes ajoutées, dépenses INTACTES, AUCUNE '
        'pièce fabriquée', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 15);
      await semerAvant(avant);
      final tablesAvant = await nombreDeTables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(16));

      expect(await colonnes(apres, 'depenses_local'), [
        'id',
        'date_transaction',
        'tresorerie',
        'libelle',
        'saisie_le',
        'ecriture_id',
        'ecriture_refus',
        // Puis, a la reouverture, les six colonnes du recu de la v42
        // (27/10/2026) : la liste est celle de la forme COURANTE.
        'recu_nom',
        'recu_sha256',
        'recu_taille',
        'recu_type',
        'recu_statut',
        'recu_cause',
      ]);
      // La v16 n'ajoute aucune table et n'en recrée aucune.
      // La v17 (sessions de caisse) et la v18 (encaissement de facture)
      // s'ajoutent à la réouverture : UNE table de plus chacune, pas une
      // recréée.
      expect(
        await nombreDeTables(apres),
        tablesAvant +
            tablesAjouteesEnV17.length +
            tablesAjouteesEnV18.length +
            tablesAjouteesEnV20.length +
            tablesAjouteesEnV22.length +
            tablesAjouteesEnV23.length +
            tablesAjouteesEnV24.length +
            tablesAjouteesEnV25.length +
            tablesAjouteesEnV26.length +
            tablesAjouteesEnV27.length +
            tablesAjouteesEnV28.length +
            tablesAjouteesEnV29.length +
            tablesAjouteesEnV31.length +
            tablesAjouteesEnV32.length +
            tablesAjouteesEnV33.length +
            tablesAjouteesEnV34.length +
            tablesAjouteesEnV35.length +
            tablesAjouteesEnV37.length +
            tablesAjouteesEnV38.length +
            tablesAjouteesEnV39.length +
            tablesAjouteesEnV40.length +
            tablesAjouteesEnV44.length,
      );

      // La donnée antérieure est la seule copie qui existe : elle survit.
      expect(await compte(apres, 'depenses_local'), 2);
      expect(await compte(apres, 'lignes_depense_local'), 4);

      // Et la migration n'invente AUCUNE pièce : ni écriture, ni lien.
      expect(await compte(apres, 'ecritures_local'), 0);
      final liens = await apres
          .customSelect(
            'SELECT COUNT(*) AS n FROM depenses_local '
            'WHERE ecriture_id IS NOT NULL OR ecriture_refus IS NOT NULL',
          )
          .getSingle();
      expect(liens.data['n'], 0);

      final dao = depenseDaoSur(apres);
      final lues = await dao.depenses();
      expect(lues.map((d) => d.montantTotal).toList()..sort(), [27000, 45000]);
      expect(lues.every((d) => !d.estComptabilisee), isTrue);
      expect(lues.every((d) => d.numeroPiece == null), isTrue);
      await apres.close();
    });

    test('le poste migré est UTILISABLE : installation, nouvelle dépense avec '
        'sa pièce, rattrapage d’une ancienne', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 15);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      // Le référentiel s'installe au démarrage, comme en production.
      await baseInstalleeSur(db, jourDeReference);
      final dao = depenseDaoSur(db);

      // Une dépense neuve : sa pièce est dans la même transaction.
      final neuve = await dao.enregistrer(
        dateTransaction: DateTime(2026, 10, 1),
        tresorerie: TresorerieDepense.caisse,
        libelle: 'Gaz',
        lignes: const [
          SaisieLigneDepense(
            libelle: 'Bouteille',
            compteCharge: '6052',
            nature: NatureDepense.electriciteEau,
            montant: 7000,
          ),
        ],
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Structure'),
      );
      expect(neuve.numeroPiece, 'CAI-2026-00001');

      // Une ancienne au compte du PLAN : son rattrapage aboutit, avec le centre
      // EXPLICITE que l'opérateur choisit (10/10/2026) — aucun défaut posé.
      final rattrapee = await dao.comptabiliser(
        'dep-2',
        auteurId: auteurDepense,
        centreId: await centreDe(db, 'Structure'),
      );
      expect(rattrapee.estComptabilisee, isTrue);
      expect(rattrapee.numeroPiece, 'BQ-2026-00001');

      // Une ancienne à l'ancien compte à six chiffres : refusée, raison
      // consignée, RIEN d'écrit.
      final avantRefus = await compte(db, 'ecritures_local');
      await expectLater(
        dao.comptabiliser(
          'dep-1',
          auteurId: auteurDepense,
          centreId: await centreDe(db, 'Structure'),
        ),
        throwsA(anything),
      );
      expect(await compte(db, 'ecritures_local'), avantRefus);
      final refusee = (await dao.parId('dep-1'))!;
      expect(refusee.estComptabilisee, isFalse);
      expect(refusee.ecritureRefus, contains('601100'));

      // RG-11 tient sur le fichier migré : une pièce validée ne se modifie pas.
      await expectLater(
        db.customStatement(
          'UPDATE ecritures_local SET libelle = ? WHERE id = ?',
          ['trafiqué', rattrapee.ecritureId],
        ),
        throwsA(anything),
      );
      // La clé étrangère tient aussi : une dépense ne désigne pas une écriture
      // qui n'existe pas.
      await expectLater(
        db.customStatement(
          "UPDATE depenses_local SET ecriture_id = 'n-existe-pas' "
          "WHERE id = 'dep-1'",
        ),
        throwsA(anything),
      );
      await db.close();
    });

    test('un fichier déjà à la forme v16 mais marqué v15 ne plante pas, et ne '
        'perd rien', () async {
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await db.customStatement(
        'INSERT INTO depenses_local (id, date_transaction, tresorerie, '
        "libelle) VALUES ('dep-x', 1787000000, 'caisse', 'Déjà là')",
      );
      // Les colonnes existent déjà (définition courante) ; seul le marqueur de
      // version recule — l'état d'un poste qui a sauté une livraison puis a
      // reçu un fichier de test.
      await db.customStatement('PRAGMA user_version = 15');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      expect(await compte(rouvert, 'depenses_local'), 1);
      expect(
        (await colonnes(
          rouvert,
          'depenses_local',
        )).where((c) => c.startsWith('ecriture')),
        ['ecriture_id', 'ecriture_refus'],
        reason: 'ni doublon, ni colonne manquante',
      );
      await rouvert.close();
    });
  });

  group('v10 -> v16 — le poste qui a sauté six livraisons', () {
    test(
      'la chaîne s’exécute sur un fichier v10 portant des dépenses',
      () async {
        final avant = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(avant, 10);
        await semerAvant(avant);
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);
        expect(await compte(apres, 'depenses_local'), 2);
        expect(await compte(apres, 'lignes_depense_local'), 4);
        expect(
          await colonnes(apres, 'depenses_local'),
          containsAll(['ecriture_id', 'ecriture_refus']),
        );
        // Le moteur comptable de la v15 est là aussi, VIDE.
        expect(await compte(apres, 'ecritures_local'), 0);
        final tables = await apres
            .customSelect(
              "SELECT COUNT(*) AS n FROM sqlite_master WHERE type = 'table' "
              "AND name IN ('ecritures_local','exercices_local')",
            )
            .getSingle();
        expect(tables.data['n'], 2);

        // Et il s'ouvre : l'installation au démarrage met le poste en état.
        await baseInstalleeSur(apres, jourDeReference);
        expect(
          (await ComptabiliteDao(apres).exerciceDeLAnnee(2026)),
          isNotNull,
        );
        await apres.close();
      },
    );
  });
}
