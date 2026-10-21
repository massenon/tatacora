import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';
import '../../features/facturation/support/outils_encaissement.dart';
import '../../features/pos/support/outils_ventes.dart';
import 'retour_arriere_schema.dart';

/// Migration v18 -> v19 : HUIT colonnes ajoutées à `reservations_local`
/// (l'annulation avec commission et remboursement, lot 6), éprouvées sur un
/// FICHIER RÉEL portant des données (piège 2), y compris en sautant des versions.
///
/// `onCreate` tourne à chaque test en mémoire, `onUpgrade` jamais. Ces cas
/// partent d'un fichier ramené à l'ancienne version, y sèment des données AU
/// FORMAT DE CETTE VERSION, le ferment, puis le rouvrent : c'est la réouverture
/// qui emprunte `onUpgrade`.
///
/// ## La migration NE FABRIQUE RIEN
///
/// Une réservation déjà annulée n'avait ni taux, ni commission, ni
/// remboursement : lui en prêter un affirmerait une commission que personne n'a
/// retenue, sur le compte d'un client. Un panier déjà clôturé n'a pas de pièce
/// comptable, et la migration n'en passe aucune rétroactivement — elle ne sait
/// pas quelle vente a été encaissée en quel mode, ni à quelle date comptable.
/// Les deux restent donc ce qu'ils étaient, et le test le constate.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_v19_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // Verrou Windows après fermeture : sans conséquence sur l'assertion.
    }
  });

  const colonnesDeLaV19 = [
    'taux_annulation_centiemes',
    'montant_total_annulation_centimes',
    'montant_commission_annulation_centimes',
    'montant_rembourse_annulation_centimes',
    'mode_saisie_remboursement',
    'date_annulation',
    'utilisateur_annulation_id',
    'ecriture_remboursement_id',
  ];

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

  Future<List<String>> colonnes(AppDatabase db, String table) async {
    final r = await db.customSelect('PRAGMA table_info($table)').get();
    return [for (final c in r) c.data['name'] as String];
  }

  /// Ce que le poste portait AVANT : un auteur, une session ouverte, un panier au
  /// comptant clôturé en espèces SANS pièce, un client, et deux réservations —
  /// une active avec un acompte, une déjà ANNULÉE avec son motif — au format v18.
  Future<void> semerAvant(AppDatabase db) async {
    await semerAuteur(db);
    await db.customStatement(
      'INSERT INTO sessions_caisse_local (id, point_vente, '
      'utilisateur_ouverture_id, date_ouverture, montant_fond_centimes) '
      "VALUES ('sess-v18', 'bar', ?, 1787000000, 1000000)",
      [auteurEssai],
    );
    await db.customStatement(
      'INSERT INTO paniers_local (id, type_vente, point_vente, statut, '
      'mode_paiement, montant_cloture, cloture_le, session_encaissement_id) '
      "VALUES ('p-v18', 'comptant', 'Réception', 'cloture', 'especes', 4000, "
      "1787000100, 'sess-v18')",
    );
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
    // Active : 2 nuits à 28 000 F, acompte 5 000 F en espèces.
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte, mode_paiement) '
      "VALUES ('res-active', 'LOC-A', 'cli-1', 'u-1', 1790000000, 1790172800, "
      "'confirmee', 28000, 5000, 'especes')",
    );
    // Déjà annulée par l'ANCIENNE version : un statut et un motif, rien d'autre.
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte, '
      'motif_annulation) VALUES '
      "('res-annulee', 'LOC-B', 'cli-1', 'u-1', 1795000000, 1795172800, "
      "'annulee', 28000, 2000, 'Désistement du client')",
    );
  }

  group('v18 -> v19 — la mise à jour d’un poste qui avait des réservations', () {
    test('la fixture ramène bien le fichier à la forme v18 : les huit '
        'colonnes manquent, aucune table ne manque', () async {
      final db = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(db, 18);

      expect(await version(db), 18);
      final noms = await colonnes(db, 'reservations_local');
      for (final c in colonnesDeLaV19) {
        expect(noms, isNot(contains(c)), reason: '$c devrait manquer');
      }
      // La v19 n'ajoute AUCUNE table : celles de la v18 sont toutes là.
      expect(await tables(db), contains('paiements_facture_local'));
      await db.close();
    });

    test('à la réouverture : les huit colonnes sont AJOUTÉES (nullables), '
        'aucune table n’apparaît, les données d’avant sont INTACTES et RIEN '
        'n’est fabriqué', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 18);
      await semerAvant(avant);
      final tablesAvant = await tables(avant);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(19));

      // La v19 n'ajoute aucune table et n'en perd aucune : le fichier est
      // rouvert au schéma COURANT, donc la v20 (règlement fournisseur) y ajoute
      // sa seule table — c'est la SEULE différence.
      expect((await tables(apres)).difference(tablesAvant), {
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
      });
      expect(tablesAvant.difference(await tables(apres)), isEmpty);

      final noms = await colonnes(apres, 'reservations_local');
      for (final c in colonnesDeLaV19) {
        expect(noms.where((n) => n == c), hasLength(1), reason: c);
      }

      // La réservation déjà annulée GARDE son motif, et n'a AUCUN taux ni
      // montant : la migration ne lui prête pas une commission.
      final annulee = await apres
          .customSelect(
            'SELECT motif_annulation, ${colonnesDeLaV19.join(', ')} '
            "FROM reservations_local WHERE id = 'res-annulee'",
          )
          .getSingle();
      expect(annulee.data['motif_annulation'], 'Désistement du client');
      for (final c in colonnesDeLaV19) {
        expect(annulee.data[c], isNull, reason: '$c ne doit pas être inventé');
      }

      // L'active a toujours son acompte et son mode, et aucune annulation.
      final active = await apres
          .customSelect(
            'SELECT acompte, mode_paiement, statut, taux_annulation_centiemes '
            "FROM reservations_local WHERE id = 'res-active'",
          )
          .getSingle();
      expect(active.data['acompte'], 5000);
      expect(active.data['mode_paiement'], 'especes');
      expect(active.data['statut'], 'confirmee');
      expect(active.data['taux_annulation_centiemes'], isNull);

      // Le panier clôturé d'avant est LÀ, sa session aussi, et AUCUNE pièce n'a
      // été passée rétroactivement.
      expect(await compterLignes(apres, 'paniers_local'), 1);
      expect(await compterLignes(apres, 'sessions_caisse_local'), 1);
      expect(await compterLignes(apres, 'ecritures_local'), 0);
      expect(await compterLignes(apres, 'reservations_local'), 2);
      await apres.close();
    });

    test('le poste migré est UTILISABLE : annuler la réservation d’AVANT '
        'rembourse et passe sa pièce ; celle déjà annulée est refusée ; une '
        'vente passe sa pièce, celle d’avant n’en a pas', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 18);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      await baseInstalleeSur(db, jourDeVente);
      final dao = ReservationDao(
        db,
        maintenant: () => jourDeVente,
        moteur: () async => moteurSur(db, maintenant: () => jourDeVente),
      );

      // 1. L'active (acompte 5 000 F espèces) s'annule : 50 % de 56 000 F de
      // commission, 100 % de l'acompte rendu, pièce Dr 4191 / Cr 5711.
      final annulee = await dao.annulerAvecConditions(
        'res-active',
        tauxSaisi: '50',
        modeRemboursement: 'pourcentage',
        valeurRemboursement: '100',
        auteurId: auteurEssai,
      );
      expect(annulee.statut, StatutReservation.annulee);
      final a = annulee.annulation!;
      expect(a.totalCentimes, 5600000);
      expect(a.commissionCentimes, 2800000);
      expect(a.rembourseCentimes, 500000);
      expect(a.ecritureRemboursementId, isNotNull);
      // La réservation désigne la ligne DÉBIT (4191), pas la ligne de caisse.
      final designee = await db
          .customSelect(
            'SELECT e.debit_centimes AS d, c.numero_compte AS n FROM ecritures_local e '
            'JOIN plan_comptable_local c ON c.id = e.compte_id WHERE e.id = ?',
            variables: [Variable.withString(a.ecritureRemboursementId!)],
          )
          .getSingle();
      expect(designee.data['n'], '4191');
      expect(designee.data['d'], 500000);
      expect(await compterLignes(db, 'ecritures_local'), 2);

      // 2. Celle que l'ancienne version avait annulée ne se réannule pas, et
      // n'écrit rien de plus.
      await expectLater(
        dao.annulerAvecConditions(
          'res-annulee',
          tauxSaisi: '50',
          modeRemboursement: 'montant',
          valeurRemboursement: '0',
          auteurId: auteurEssai,
        ),
        throwsA(
          isA<Object>().having(
            (e) => '$e',
            'message',
            contains(MessagesAnnulation.dejaAnnulee),
          ),
        ),
      );
      expect(await compterLignes(db, 'ecritures_local'), 2);

      // 3. Une vente clôturée APRÈS la mise à jour passe sa pièce VTE ; le panier
      // d'avant, lui, n'en a toujours pas.
      await semerBoisson(db);
      final vente = await vendreAuComptant(db, quantite: 2);
      expect(vente.sessionEncaissementId, 'sess-v18');
      expect(await compterLignes(db, 'ecritures_local'), 4);
      await db.close();
    });

    test('un fichier déjà à la forme v19 mais marqué v18 ne plante pas et ne '
        'perd rien (l’ajout de chaque colonne est conditionnel)', () async {
      // L'état d'un poste qui a reçu un fichier de test, ou qui a sauté une
      // livraison puis restauré une sauvegarde : les colonnes existent déjà
      // (piège 3 : « duplicate column name »).
      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      await db.customStatement(
        'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
        "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
      );
      await db.customStatement(
        'INSERT INTO unites_hebergement_local (id, categorie_id, numero, '
        "statut) VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
      );
      await db.customStatement(
        'INSERT INTO clients_local (id, nom, telephone, type_client) VALUES '
        "('cli-1', 'KORA', '+229 01', 'particulier')",
      );
      await db.customStatement(
        'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
        'date_arrivee, date_depart, statut, tarif_nuit, '
        'taux_annulation_centiemes, utilisateur_annulation_id) VALUES '
        "('r', 'LOC', 'cli-1', 'u-1', 1790000000, 1790172800, 'annulee', "
        '28000, 5000, ?)',
        [auteurEssai],
      );
      await db.customStatement('PRAGMA user_version = 18');
      await db.close();

      final rouvert = AppDatabase.surFichier(fichier);
      expect(await version(rouvert), rouvert.schemaVersion);
      final r = await rouvert
          .customSelect(
            'SELECT taux_annulation_centiemes, utilisateur_annulation_id '
            "FROM reservations_local WHERE id = 'r'",
          )
          .getSingle();
      expect(r.data['taux_annulation_centiemes'], 5000);
      expect(r.data['utilisateur_annulation_id'], auteurEssai);
      await rouvert.close();
    });

    test('les clés étrangères des deux colonnes tiennent sur le fichier '
        'migré', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 18);
      await semerAvant(avant);
      await avant.close();

      final db = AppDatabase.surFichier(fichier);
      // Un auteur d'annulation qui n'existe pas est refusé…
      await expectLater(
        db.customStatement(
          "UPDATE reservations_local SET utilisateur_annulation_id = 'fantome' "
          "WHERE id = 'res-active'",
        ),
        throwsA(isA<Exception>()),
      );
      // …une pièce de remboursement qui n'existe pas aussi.
      await expectLater(
        db.customStatement(
          "UPDATE reservations_local SET ecriture_remboursement_id = 'fantome' "
          "WHERE id = 'res-active'",
        ),
        throwsA(isA<Exception>()),
      );
      await db.close();
    });
  });

  group('v10 -> v19 — le poste qui a sauté neuf livraisons', () {
    test('la chaîne s’exécute sur un fichier v10 portant des dépenses, et '
        'l’annulation est possible après', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 10);
      await semerAuteur(avant);
      const jour = 1787000000;
      await avant.customStatement(
        'INSERT INTO depenses_local (id, date_transaction, tresorerie, '
        'libelle, saisie_le) VALUES (?, ?, ?, ?, ?)',
        ['dep-1', jour, 'caisse', 'Marché du matin', jour],
      );
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(await compterLignes(apres, 'depenses_local'), 1);
      final noms = await colonnes(apres, 'reservations_local');
      for (final c in colonnesDeLaV19) {
        expect(noms.where((n) => n == c), hasLength(1), reason: c);
      }

      // Le poste sert : référentiel, parc, réservation, annulation.
      await baseInstalleeSur(apres, jourDeVente);
      await apres.customStatement(
        'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
        "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
      );
      await apres.customStatement(
        'INSERT INTO unites_hebergement_local (id, categorie_id, numero, '
        "statut) VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
      );
      await apres.customStatement(
        'INSERT INTO clients_local (id, nom, telephone, type_client) VALUES '
        "('cli-1', 'KORA', '+229 01', 'particulier')",
      );
      await apres.customStatement(
        'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
        'date_arrivee, date_depart, statut, tarif_nuit) VALUES '
        "('r', 'LOC', 'cli-1', 'u-1', 1790000000, 1790172800, 'confirmee', "
        '28000)',
      );
      final dao = ReservationDao(apres, maintenant: () => jourDeVente);
      final r = await dao.annulerAvecConditions(
        'r',
        tauxSaisi: '10',
        modeRemboursement: 'montant',
        valeurRemboursement: '0',
        auteurId: auteurEssai,
      );
      expect(r.annulation!.commissionCentimes, 560000);
      await apres.close();
    });
  });

  group('v2 -> v19 — la chaîne ENTIÈRE', () {
    test('un fichier v2 (la première livraison du poste) arrive à la v19 avec '
        'les huit colonnes, une seule fois chacune', () async {
      final avant = AppDatabase.surFichier(fichier);
      await ramenerSchemaA(avant, 2);
      await avant.close();

      final apres = AppDatabase.surFichier(fichier);
      expect(await version(apres), apres.schemaVersion);
      expect(apres.schemaVersion, greaterThanOrEqualTo(19));
      final noms = await colonnes(apres, 'reservations_local');
      for (final c in colonnesDeLaV19) {
        expect(noms.where((n) => n == c), hasLength(1), reason: c);
      }
      await apres.close();
    });
  });

  test('une pièce refusée emporte l’annulation entière, statut compris — '
      'sur le fichier migré', () async {
    final avant = AppDatabase.surFichier(fichier);
    await ramenerSchemaA(avant, 18);
    await semerAvant(avant);
    await avant.close();

    final db = AppDatabase.surFichier(fichier);
    // Le référentiel n'est PAS installé : le journal CAI est inconnu, la pièce du
    // remboursement est refusée.
    final dao = ReservationDao(
      db,
      maintenant: () => jourDeVente,
      moteur: () async => moteurSur(db, maintenant: () => jourDeVente),
    );
    await expectLater(
      dao.annulerAvecConditions(
        'res-active',
        tauxSaisi: '50',
        modeRemboursement: 'pourcentage',
        valeurRemboursement: '100',
        auteurId: auteurEssai,
      ),
      throwsA(isA<RefusComptable>()),
    );
    final r = await db
        .customSelect(
          'SELECT statut, taux_annulation_centiemes FROM reservations_local '
          "WHERE id = 'res-active'",
        )
        .getSingle();
    expect(r.data['statut'], 'confirmee', reason: 'le statut est revenu');
    expect(r.data['taux_annulation_centiemes'], isNull);
    expect(await compterLignes(db, 'ecritures_local'), 0);
    await db.close();
  });
}
