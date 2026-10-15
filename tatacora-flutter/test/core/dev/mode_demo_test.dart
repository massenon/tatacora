import 'package:drift/drift.dart' show Value, Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/dev/donnees_demonstration.dart';
import 'package:tatacora_flutter/core/dev/donnees_exploitation_demonstration.dart';
import 'package:tatacora_flutter/core/dev/mode_demo.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/taux_paie.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';

/// L'amorçage du flavor **démo** — `SEEDER_TEST_FLUTTER.md` §4, PA-201.
///
/// ## Ce que ces cas protègent
///
/// **Qu'une démonstration s'ouvre sur des données.** Le flavor existait depuis
/// le Sprint 0 et n'amorçait rien : le poste affichait un catalogue vide, et
/// c'est exactement la situation qu'il était censé éviter.
///
/// **Qu'un poste DÉJÀ ENTAMÉ reçoive quand même le jeu.** Le cas est arrivé
/// sur le poste d'essai — un compte, un client, treize tables, rien d'autre —
/// et la première version l'écartait en entier, prenant ce client unique pour
/// la preuve d'un amorçage antérieur.
///
/// **Qu'il ne sème ni compte ni mot de passe.** La règle du dépôt est absolue,
/// et un jeu de démonstration est précisément l'endroit où l'on serait tenté
/// d'en poser un « pour aller plus vite ».
///
/// **Que les tables de stock restent vides** (PA-134) : le stock est calculé
/// par le serveur, et ce flavor n'en a aucun.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.enMemoire();
    // Comme `main_demo.dart` : le référentiel comptable est installé AVANT
    // l'amorçage, parce que les dépenses du jeu sont confrontées au plan.
    await db.customStatement('SELECT 1');
    await baseInstalleeSur(db, DateTime(2026, 10, 10));
  });
  tearDown(() => db.close());

  Future<int> compter(String table) async {
    final ligne = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return ligne.data['n'] as int;
  }

  group("L'amorçage écrit le jeu de démonstration", () {
    test(
      'les six référentiels arrivent, par leurs auteurs habituels',
      () async {
        final bilan = await amorcerModeDemo(db, modeDemo: true);

        // Les comptes viennent du jeu relevé sur le serveur : les figer ici en
        // dur ferait passer un jeu amputé pour un jeu complet.
        expect(await compter('clients_local'), clientsDemonstration.length);
        expect(
          await compter('cartes_boisson_local'),
          boissonsDemonstration.length,
        );
        expect(await compter('circuits_local'), circuitsDemonstration.length);
        expect(await compter('vehicules_local'), vehiculesDemonstration.length);
        expect(
          await compter('categories_hebergement_local'),
          parcDemonstration.categories.length,
        );
        expect(
          await compter('unites_hebergement_local'),
          parcDemonstration.unites.length,
        );
        expect(
          await compter('reservations_local'),
          reservationsDemonstration.length,
        );
        // Le jeu initial de la salle : 6 + 4 + 3.
        expect(await compter('tables_local'), 13);
        expect(bilan.estComplet, isTrue);
        expect(bilan.reservationsIgnorees, 0);
      },
    );

    test('les réservations RETROUVENT leur client et leur unité', () async {
      // Le cas qui mord si l'ordre d'écriture change : les deux colonnes sont
      // de vraies clés étrangères, et le parc doit précéder (PA-127).
      await amorcerModeDemo(db, modeDemo: true);

      final orphelines = await db.customSelect('''
        SELECT COUNT(*) AS n FROM reservations_local r
        LEFT JOIN clients_local c ON c.id = r.client_id
        LEFT JOIN unites_hebergement_local u ON u.id = r.unite_id
        WHERE c.id IS NULL OR u.id IS NULL
      ''').getSingle();

      expect(orphelines.data['n'], 0);
    });

    test('une boisson porte son lien de stock, jamais un stock figé', () async {
      // `stock_disponible` n'a pas de colonne (PA-129) ; le lien, lui, est
      // répliqué (PA-199) — sans lui la carte compterait tout comme non
      // rattaché, hors connexion.
      await amorcerModeDemo(db, modeDemo: true);

      final sansLien = await db
          .customSelect(
            "SELECT COUNT(*) AS n FROM cartes_boisson_local WHERE article_id = ''",
          )
          .getSingle();

      expect(sansLien.data['n'], 0);
    });
  });

  group('Un poste déjà entamé', () {
    test('reçoit le jeu MALGRÉ un client et des tables déjà là', () async {
      // Le poste d'essai du 12/09/2026, reproduit : une saisie isolée ne doit
      // pas faire écarter les six référentiels.
      await db
          .into(db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: 'cli-saisi-au-comptoir',
              nom: 'Saisi au comptoir',
              telephone: '90 00 00 00',
              typeClient: 'particulier',
              statutSync: const Value('en_attente_synchronisation'),
            ),
          );

      final bilan = await amorcerModeDemo(db, modeDemo: true);

      expect(bilan.catalogue, greaterThan(0));
      expect(
        await compter('cartes_boisson_local'),
        boissonsDemonstration.length,
      );
      expect(await compter('clients_local'), clientsDemonstration.length + 1);
      expect(
        await compter('reservations_local'),
        reservationsDemonstration.length,
      );
    });

    test('la saisie locale en attente n’est jamais écrasée', () async {
      await db
          .into(db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              // L'identifiant d'un client du JEU, porté par une saisie locale
              // en attente : `ClientDao.aligner` doit l'épargner.
              id: clientsDemonstration.first.id,
              nom: 'Corrigé sur le poste',
              telephone: '97 00 00 00',
              typeClient: 'particulier',
              statutSync: const Value('en_attente_synchronisation'),
            ),
          );

      await amorcerModeDemo(db, modeDemo: true);

      final garde = await db
          .customSelect(
            'SELECT nom FROM clients_local WHERE id = ?',
            variables: [Variable<String>(clientsDemonstration.first.id)],
          )
          .getSingle();

      expect(garde.data['nom'], 'Corrigé sur le poste');
    });

    test('un second amorçage ne duplique rien', () async {
      await amorcerModeDemo(db, modeDemo: true);
      await amorcerModeDemo(db, modeDemo: true);

      expect(await compter('clients_local'), clientsDemonstration.length);
      expect(
        await compter('cartes_boisson_local'),
        boissonsDemonstration.length,
      );
      expect(
        await compter('reservations_local'),
        reservationsDemonstration.length,
      );
      // La salle ne se re-sème pas : `toutes()` ne le fait que sur un
      // référentiel vide.
      expect(await compter('tables_local'), 13);
    });
  });

  group('Les quatre modules d’exploitation', () {
    test('les dépenses du jeu sont SANS pièce comptable, et ses comptes sont '
        'ceux du plan', () async {
      // Le mode démonstration n'a aucun utilisateur, donc aucun auteur à nommer
      // sur une pièce (RG-15) : ses dépenses sont celles d'un poste dont les
      // dépenses précèdent la comptabilité. Elles ne se disent JAMAIS
      // comptabilisées, et leurs comptes existent au plan (le rattrapage est
      // refusé par le CENTRE manquant — RG-12 —, pas par un compte inconnu).
      await amorcerModeDemo(db, modeDemo: true);

      expect(await compter('depenses_local'), depensesDemonstration.length);
      expect(await compter('ecritures_local'), 0);
      final liees = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM depenses_local '
            'WHERE ecriture_id IS NOT NULL',
          )
          .getSingle();
      expect(liees.data['n'], 0);

      final comptes = await db
          .customSelect(
            'SELECT DISTINCT l.compte_charge AS c FROM lignes_depense_local l '
            'LEFT JOIN plan_comptable_local p ON p.numero_compte = l.compte_charge '
            'WHERE p.id IS NULL',
          )
          .get();
      expect(comptes, isEmpty, reason: 'un compte du jeu est absent du plan');
    });

    test('guides, effectif, dépenses et modèles arrivent', () async {
      // Sans eux, les quatre écrans portés en « zéro réseau » s'ouvrent vides
      // sur un poste de démonstration — et aucun serveur ne viendra les
      // remplir. C'est la raison d'être de ce lot.
      final bilan = await amorcerModeDemo(db, modeDemo: true);

      expect(await compter('guides_local'), guidesDemonstration.length);
      expect(await compter('employes_local'), employesDemonstration.length);
      expect(await compter('depenses_local'), depensesDemonstration.length);
      expect(
        await compter('modeles_notification_local'),
        modelesDemonstration.length,
      );

      // Les deux référentiels de la paie, par leurs auteurs idempotents.
      expect(
        await compter('services_rh_local'),
        ReferentielPaie.services.length,
      );
      expect(
        await compter('taux_paie_local'),
        ReferentielPaie.confirmes.length,
      );

      // Aucun salarié écarté : les six services du référentiel couvrent les
      // quatre affectations du jeu.
      expect(bilan.employesIgnores, 0);
      expect(bilan.estComplet, isTrue);
    });

    test(
      'un second amorçage ne duplique NI dépense NI salarié NI modèle',
      () async {
        // ⚠ LE CAS QUI MORD. `creer`, `enregistrer` et `creerModele` frappent
        // leur propre identifiant ou refusent le doublon : sans la garde posée
        // table par table, un second démarrage doublerait l'effectif et les
        // dépenses, et lèverait sur les modèles.
        await amorcerModeDemo(db, modeDemo: true);
        await amorcerModeDemo(db, modeDemo: true);

        expect(await compter('employes_local'), employesDemonstration.length);
        expect(await compter('depenses_local'), depensesDemonstration.length);
        expect(
          await compter('modeles_notification_local'),
          modelesDemonstration.length,
        );
        // Les guides, eux, sont réécrits par upsert : le compte ne bouge pas
        // davantage, mais pour une autre raison — l'identifiant est fixe.
        expect(await compter('guides_local'), guidesDemonstration.length);
      },
    );

    test(
      'une dépense déjà saisie sur le poste écarte le jeu, et LUI SEUL',
      () async {
        // La garde porte sur le vide de CETTE table, jamais sur un drapeau
        // global : les six référentiels doivent arriver quand même.
        await db
            .into(db.depensesLocal)
            .insert(
              DepensesLocalCompanion.insert(
                id: 'dep-saisie-au-comptoir',
                dateTransaction: DateTime(2026, 9, 10),
                tresorerie: 'caisse',
                libelle: 'Saisie au comptoir',
              ),
            );

        final bilan = await amorcerModeDemo(db, modeDemo: true);

        expect(bilan.depenses, 0);
        expect(await compter('depenses_local'), 1);
        // Le reste du jeu est arrivé.
        expect(await compter('clients_local'), clientsDemonstration.length);
        expect(await compter('employes_local'), employesDemonstration.length);
      },
    );
  });

  group('Ce qu’il ne sème JAMAIS', () {
    test('aucun compte, donc aucun mot de passe connu', () async {
      await amorcerModeDemo(db, modeDemo: true);

      expect(await compter('utilisateurs_local'), 0);
    });

    test('les trois tables de stock restent vides (PA-134)', () async {
      await amorcerModeDemo(db, modeDemo: true);

      expect(await compter('articles_local'), 0);
      expect(await compter('points_stockage_local'), 0);
      expect(await compter('mouvements_stock_local'), 0);
    });
  });

  group('La garde de flavor', () {
    test('hors flavor démo, il REFUSE et n’écrit rien', () async {
      await expectLater(
        () => amorcerModeDemo(db, modeDemo: false),
        throwsA(isA<StateError>()),
      );

      expect(await compter('clients_local'), 0);
      expect(await compter('cartes_boisson_local'), 0);
    });
  });
}
