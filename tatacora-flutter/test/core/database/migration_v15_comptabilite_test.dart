import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';
import 'retour_arriere_schema.dart';

/// Migration v14 -> v15 : SIX tables de la comptabilité (moteur local) —
/// éprouvée sur un FICHIER RÉEL portant des données (piège 2).
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des lignes AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// Les six tables sont NEUVES : la migration ne doit rien toucher d'existant
/// (le stock, le client, l'utilisateur, le menu saisis avant la mise à jour sont
/// la seule copie qui existe) ni rien semer — le référentiel s'installe au
/// démarrage, par `installerReferentielComptable`. Les QUATRE TRIGGERS de RG-11
/// ne sont pas des tables : `createTable` ne les crée pas, et c'est ici qu'on
/// vérifie qu'ils existent bien sur un fichier MIGRÉ, pas seulement sur un
/// fichier neuf.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v15_');
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

  Future<bool> tableExiste(AppDatabase db, String table) async {
    final r = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          variables: [Variable<String>(table)],
        )
        .get();
    return r.isNotEmpty;
  }

  Future<List<String>> declencheurs(AppDatabase db) async => [
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'trigger' "
              "AND name LIKE 'rg11_%' ORDER BY name",
            )
            .get())
      r.data['name'] as String,
  ];

  Future<Set<String>> toutesLesTables(AppDatabase db) async => {
    for (final r
        in await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get())
      r.data['name'] as String,
  };

  /// Ce que le poste portait AVANT : un utilisateur, un client, la tolérance
  /// saisie en Paramètres, un menu du restaurant (v14), une entrée de stock
  /// VALORISÉE (10 kg de poulet à 2 500 F).
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
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
        .into(db.parametresSystemeLocal)
        .insert(
          ParametresSystemeLocalCompanion.insert(
            cle: 'tolerance_reception_pct',
            valeur: '5',
            modifieLe: DateTime(2026, 10, 2),
          ),
        );
    await db
        .into(db.menusLocal)
        .insert(
          MenusLocalCompanion.insert(
            id: 'm-1',
            libelle: 'Carte du jour',
            type: 'local',
            creeLe: DateTime(2026, 10, 3),
            creePar: auteurEssai,
          ),
        );

    final stocks = StocksDao(db);
    await stocks.creerPoint(
      libelle: 'Cuisine',
      type: TypePoint.cuisine,
      id: 'p-cui',
    );
    await stocks.creerArticle(
      id: 'a-poulet',
      libelle: 'Poulet',
      categorie: 'Viandes',
      uniteMesure: 'kg',
      seuilCentiemes: 500,
      suivi: SuiviArticle.permanent,
      pointStockageId: 'p-cui',
      auteurId: auteurEssai,
    );
    await stocks.ajouterMouvement(
      articleId: 'a-poulet',
      pointId: 'p-cui',
      type: TypeMouvement.entree,
      centiemes: 1000,
      motif: 'Reprise',
      auteurId: auteurEssai,
      coutDixMilliemes: 25000000,
    );
  }

  group('v14 -> v15 — la mise à jour d’un poste qui travaillait déjà', () {
    test(
      'la fixture ramène bien le fichier à la forme v14 : SIX tables en moins',
      () async {
        final db = AppDatabase.surFichier(fichier);
        await ramenerSchemaA(db, 14);

        expect(await version(db), 14);
        for (final t in tablesAjouteesEnV15) {
          expect(
            await tableExiste(db, t),
            isFalse,
            reason: '$t devrait manquer',
          );
        }
        expect(await declencheurs(db), isEmpty);
        // Les tables du restaurant de la v14, elles, sont intactes.
        expect(await tableExiste(db, 'plats_local'), isTrue);
        await db.close();
      },
    );

    test(
      'à la réouverture : six tables créées, VIDES, données antérieures intactes, version 15',
      () async {
        // Semée par les DAO d'aujourd'hui sur une forme ANCIENNE, qui n'a pas
        // la file d'envoi (v26) : les écrivains n'y enfilent donc rien.
        final avant = AppDatabase.surFichier(
          fichier,
          fileSynchronisation: false,
        );
        await ramenerSchemaA(avant, 14);
        await semerAvant(avant);
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        // Le fichier est rouvert au schéma COURANT : la v16 (pièce des
        // dépenses) suit la v15 (cette migration).
        expect(await version(apres), apres.schemaVersion);
        expect(apres.schemaVersion, greaterThanOrEqualTo(15));

        for (final t in tablesAjouteesEnV15) {
          expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
          // Rien n'est semé ni déduit : le référentiel est installé au démarrage.
          expect(await compte(apres, t), 0, reason: '$t devrait être vide');
        }

        // La donnée antérieure est la seule copie qui existe : elle survit.
        expect(await compte(apres, 'utilisateurs_local'), 1);
        expect(await compte(apres, 'clients_local'), 1);
        expect(await compte(apres, 'parametres_systeme_local'), 1);
        expect(await compte(apres, 'menus_local'), 1);
        expect(await compte(apres, 'points_stockage_local'), 1);
        expect(await compte(apres, 'articles_local'), 1);
        expect(await compte(apres, 'mouvements_stock_local'), 1);

        final poulet = (await StocksDao(apres).etat()).lignes.single;
        expect(poulet.stock, '10.00');
        expect(poulet.coutMoyenPondere, '2500.0000');
        await apres.close();
      },
    );

    test('les colonnes des six tables sont figées, table par table', () async {
      final avant = AppDatabase.surFichier(fichier, fileSynchronisation: false);
      await ramenerSchemaA(avant, 14);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await colonnes(apres, 'centres_cout_local'), [
        'id',
        'libelle',
        'type',
      ]);
      expect(await colonnes(apres, 'journaux_local'), [
        'id',
        'code',
        'libelle',
      ]);
      expect(await colonnes(apres, 'plan_comptable_local'), [
        'id',
        'numero_compte',
        'libelle',
        'classe',
        'nature',
        'centre_cout_defaut_id',
      ]);
      expect(await colonnes(apres, 'exercices_local'), [
        'id',
        'annee',
        'date_debut',
        'date_fin',
        'statut',
        'date_cloture',
        'utilisateur_cloture_id',
      ]);
      expect(await colonnes(apres, 'ecritures_local'), [
        'id',
        'exercice_id',
        'journal_id',
        'compte_id',
        'centre_id',
        'date_ecriture',
        'libelle',
        'debit_centimes',
        'credit_centimes',
        'statut',
        'ecriture_contrepassee_id',
        'numero_piece',
        'cree_le',
        'cree_par',
        'modifie_le',
        'modifie_par',
      ]);
      expect(await colonnes(apres, 'sequences_piece_local'), [
        'journal_id',
        'annee',
        'dernier_rang',
      ]);

      // Ni un solde, ni un total de pièce, ni un montant à virgule, ni une note
      // que personne n'écrit, ni un `statut_sync` n'est une colonne (piège 9).
      for (final t in tablesAjouteesEnV15) {
        final cols = await colonnes(apres, t);
        for (final interdit in [
          'solde',
          'total',
          'total_debit',
          'total_credit',
          'debit',
          'credit',
          'resultat_reporte',
          'evenements_posterieurs',
          'statut_sync',
          'equilibre',
        ]) {
          expect(cols, isNot(contains(interdit)), reason: '$t.$interdit');
        }
      }
      await apres.close();
    });

    test(
      'les QUATRE triggers de RG-11 existent sur le fichier MIGRÉ',
      () async {
        final avant = AppDatabase.surFichier(
          fichier,
          fileSynchronisation: false,
        );
        await ramenerSchemaA(avant, 14);
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        expect(await declencheurs(apres), [
          'rg11_brouillon_exercice_clos_maj',
          'rg11_ecriture_jamais_supprimee',
          'rg11_ecriture_validee_immuable',
          'rg11_exercice_clos_ajout',
        ]);
        await apres.close();
      },
    );

    test(
      'le poste migré est UTILISABLE : installation, pièce validée, RG-11 qui tient, compteur qui survit',
      () async {
        final avant = AppDatabase.surFichier(
          fichier,
          fileSynchronisation: false,
        );
        await ramenerSchemaA(avant, 14);
        await semerAvant(avant);
        await avant.close();

        // --- Première session : le démarrage installe, un module passe une pièce.
        final s1 = AppDatabase.surFichier(fichier);
        final bilan = await installerReferentielComptable(
          s1,
          contenuPlan: lirePlanEmbarque(),
          maintenant: DateTime(2026, 10, 10),
        );
        expect(bilan.comptesCrees, 1332);
        expect(bilan.exerciceSeme, 2026);

        final dao1 = ComptabiliteDao(s1);
        final moteur1 = MoteurComptable(
          dao1,
          maintenant: () => DateTime(2026, 10, 10, 9),
        );
        final restaurant = (await dao1.centreParLibelle('Restaurant'))!.id;
        DemandePiece vente(String libelle) => DemandePiece(
          journal: 'VTE',
          date: '2026-10-10',
          libelle: libelle,
          lignes: [
            const LigneDemandee(compte: '5711', debitCentimes: 450000),
            LigneDemandee(
              compte: '7061',
              creditCentimes: 450000,
              centreId: restaurant,
            ),
          ],
        );
        final piece = await moteur1.passerEtValider(
          vente('Poulet DG'),
          auteurId: auteurEssai,
        );
        expect(piece.first.numeroPiece, 'VTE-2026-00001');

        // RG-11 tient sur le fichier migré : on ne modifie pas une validée.
        try {
          await s1.customStatement(
            "UPDATE ecritures_local SET libelle = 'x' WHERE id = '${piece[0].id}'",
          );
          fail('Le trigger devait refuser.');
        } catch (e) {
          final r = ComptabiliteDao.traduireRefusBase(e);
          expect(r?.motif, MotifRefus.ecritureImmuable);
        }
        await s1.close();

        // --- Seconde session, après FERMETURE : tout est là, le compteur aussi.
        final s2 = AppDatabase.surFichier(fichier);
        expect(await version(s2), s2.schemaVersion);
        expect(await compte(s2, 'ecritures_local'), 2);
        expect(await compte(s2, 'plan_comptable_local'), 1332);
        final dao2 = ComptabiliteDao(s2);
        final relue = await dao2.lignesDeLaPiece('VTE-2026-00001');
        expect(relue, hasLength(2));
        expect(relue.map((l) => l.debitCentimes + l.creditCentimes).toList(), [
          450000,
          450000,
        ]);

        // Une seconde installation ne change rien…
        final bilan2 = await installerReferentielComptable(
          s2,
          contenuPlan: lirePlanEmbarque(),
          maintenant: DateTime(2026, 10, 11),
        );
        expect(bilan2.aRienChange, isTrue);

        // … et la pièce suivante porte le numéro 2 : le compteur a survécu.
        final moteur2 = MoteurComptable(
          dao2,
          maintenant: () => DateTime(2026, 10, 10, 11),
        );
        final suivante = await moteur2.passer(
          vente('Capitaine braisé'),
          auteurId: auteurEssai,
        );
        expect(suivante.first.numeroPiece, 'VTE-2026-00002');

        // Les données d'avant la mise à jour sont toujours là, et utilisables.
        expect(await compte(s2, 'menus_local'), 1);
        expect((await StocksDao(s2).etat()).lignes.single.stock, '10.00');
        await s2.close();
      },
    );
  });

  group('v9 -> v15 — le poste qui a sauté six livraisons', () {
    test(
      'la chaîne v10 à v15 s’exécute sur un fichier v9 portant des données',
      () async {
        final avant = AppDatabase.surFichier(
          fichier,
          fileSynchronisation: false,
        );
        await ramenerSchemaA(avant, 9);
        expect(await version(avant), 9);
        await avant
            .into(avant.clientsLocal)
            .insert(
              ClientsLocalCompanion.insert(
                id: 'cli-9',
                nom: 'MAMA',
                telephone: '+229 01 00 00 00 09',
                typeClient: 'particulier',
              ),
            );
        await avant.close();

        final apres = AppDatabase.surFichier(fichier);
        expect(await version(apres), apres.schemaVersion);
        for (final t in tablesAjouteesEnV15) {
          expect(await tableExiste(apres, t), isTrue, reason: '$t manque');
          expect(await compte(apres, t), 0, reason: t);
        }
        expect((await declencheurs(apres)), hasLength(4));
        // Les versions intermédiaires ont eu lieu aussi.
        expect(await tableExiste(apres, 'plats_local'), isTrue);
        expect(await tableExiste(apres, 'fournisseurs_local'), isTrue);
        expect(await compte(apres, 'clients_local'), 1);
        await apres.close();
      },
    );
  });

  group('Une migration doit pouvoir se REJOUER (piège 3)', () {
    test(
      'un fichier déjà à la forme v15 mais marqué v14 ne plante pas, et ne perd rien',
      () async {
        // `createAll` à la définition COURANTE, des lignes semées, puis
        // `user_version` ramené à 14 sans rien retirer : c'est l'état où un
        // `CREATE TABLE` ou un `CREATE TRIGGER` inconditionnel échouerait sur
        // « already exists ».
        final neuf = AppDatabase.surFichier(fichier);
        await neuf.customStatement('SELECT 1');
        await semerAuteur(neuf);
        await installerReferentielComptable(
          neuf,
          contenuPlan: lirePlanEmbarque(),
          maintenant: DateTime(2026, 10, 10),
        );
        await neuf.customStatement('PRAGMA user_version = 14');
        await neuf.close();

        final rouvert = AppDatabase.surFichier(fichier);
        expect(await version(rouvert), rouvert.schemaVersion);
        // Les lignes existantes n'ont pas été recréées.
        expect(await compte(rouvert, 'plan_comptable_local'), 1332);
        expect(await compte(rouvert, 'journaux_local'), 5);
        expect(await declencheurs(rouvert), hasLength(4));
        await rouvert.close();
      },
    );
  });

  group('Le retour arrière est SYMÉTRIQUE (tables neuves)', () {
    test(
      'ramener à la v14 retire exactement les six tables (plus celle de la v17), pas une de plus',
      () async {
        final db = AppDatabase.surFichier(fichier);
        await db.customStatement('SELECT 1');
        final avant = await toutesLesTables(db);
        await ramenerSchemaA(db, 14);
        final apres = await toutesLesTables(db);

        // Depuis la v17, la fixture défait AUSSI la table des sessions de caisse
        // en passant : elle fait partie de ce qui disparaît avec les six.
        expect(avant.difference(apres), {
          ...tablesAjouteesEnV15,
          ...tablesAjouteesEnV17,
          ...tablesAjouteesEnV18,
          ...tablesAjouteesEnV20,
          ...tablesAjouteesEnV22,
          ...tablesAjouteesEnV23,
          ...tablesAjouteesEnV24,
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
        expect(apres.difference(avant), isEmpty);
        // Les triggers disparaissent avec leur table.
        expect(await declencheurs(db), isEmpty);
        await db.close();
      },
    );
  });
}
