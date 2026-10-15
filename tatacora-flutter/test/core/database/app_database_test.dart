import 'package:sqlite3/common.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:uuid/uuid.dart';

/// Base locale Drift — livrable 3 du Sprint 0.
///
/// La spécification demande « un test simple d'insertion/lecture ». On y ajoute
/// les deux contrôles qui, eux, cassent en production si on ne les fait pas :
/// l'UUID généré côté client, et l'activation effective des clés étrangères.
void main() {
  late AppDatabase base;

  setUp(() => base = AppDatabase.enMemoire());
  tearDown(() => base.close());

  test('les 57 tables du périmètre offline sont créées', () async {
    // `allTables` reflète ce que Drift a réellement généré, pas ce qu'on
    // croit avoir déclaré.
    //
    // 20 au schéma v2 ; **22 depuis la v3** — `paniers_local` et
    // `lignes_panier_local` (D2, portage de la proposition de modèle non
    // ratifiée, voir `tables/panier_tables.dart`) ; **25 depuis la v4** —
    // `pieces_facturation_local`, `lignes_piece_facturation_local` et
    // `sequences_facture_local` (D3, registre de facturation, voir
    // `tables/registre_facturation_tables.dart`) ; **26 depuis la v5** —
    // `utilisateurs_local`, le référentiel des comptes de ce poste
    // (authentification locale, PA-103) ; **27 depuis la v6** —
    // `tables_local`, le référentiel des tables de salle porté de
    // `tables-engine.js` pour le panneau Salle du point de vente (PA-108) ;
    // **28 depuis la v8** — `lignes_reservation_local`, les lignes de service
    // d'une réservation, sans lesquelles le maître ne pouvait pas être porté :
    // il compose une réservation de cinq services combinables quand ce schéma
    // n'en connaissait qu'un (voir `tables/hebergement_tables.dart`).
    //
    // Le compte est écrit en dur DÉLIBÉRÉMENT : c'est ce qui oblige à rouvrir
    // ce test le jour où une table entre au périmètre offline, et donc à se
    // demander si elle y a sa place — la taille de la base locale conditionne
    // la durée de la fenêtre hors ligne.
    // 28 → 34 le 14/09/2026 : deux tables de synchronisation RETIRÉES
    // (`sync_queue`, `sync_conflict_local` — décision « zéro réseau ») et huit
    // AJOUTÉES pour les quatre modules d'exploitation portés en local pur
    // (dépenses ×2, notifications ×2, personnel & paie ×4).
    //
    // Ce nombre est figé **exprès** : il oblige à rouvrir ce test le jour où
    // une table entre au périmètre offline, donc à se demander si elle y a sa
    // place. La taille de la base conditionne la fenêtre hors ligne.
    //
    // 34 → 35 le 09/10/2026 : `parametres_systeme_local` (v11), la source
    // locale de l'écran Paramètres. Une seule table, sans `statutSync` ni file ;
    // les taux de charges sociales n'y sont PAS dupliqués (ils ont leur auteur,
    // `taux_paie_local`).
    //
    // 35 → 35 le 09/10/2026 (v12, M6 Stocks local) : AUCUNE table ajoutée. Les
    // trois tables de stock existent depuis la v1, vides et sans auteur
    // (PA-134) ; la v12 leur AJOUTE sept colonnes. Ce nombre ne bouge donc pas,
    // et c'est voulu : le périmètre offline n'a pas grandi, ses tables ont reçu
    // un auteur. Les colonnes sont figées par `migration_v12_stocks_test.dart`
    // (liste exacte, table par table) — un compte de tables seul ne verrait
    // pas une colonne ajoutée « pendant qu'on y est ».
    //
    // 35 → 40 le 09/10/2026 (v13, M7 Achats local) : CINQ tables neuves —
    // `fournisseurs_local`, `commandes_achat_local`,
    // `lignes_commande_achat_local`, `bons_reception_local` et
    // `lignes_bon_reception_local` (voir `tables/achats_tables.dart`). M7 entre
    // au périmètre local PAR DÉCISION DU PRODUIT (la source de données de M7 est
    // locale) ; chaque table a un seul auteur (`AchatsDao`) et personne ne la
    // descend. Les cinq noms sont assertés ci-dessous : un compte seul ne verrait
    // pas une table remplacée par une autre.
    //
    // 40 → 44 le 09/10/2026 (v14, M4 Restaurant local) : QUATRE tables neuves —
    // `menus_local`, `recettes_local`, `ingredients_recette_local` et
    // `plats_local` (voir `tables/restaurant_tables.dart`). M4 entre au
    // périmètre local PAR DÉCISION DU PRODUIT ; chaque table a un seul auteur
    // (`RestaurantDao`) et personne ne la descend. Les quatre noms sont assertés
    // ci-dessous, comme ceux de la v13.
    //
    // 44 → 50 le 10/10/2026 (v15, M10 Comptabilité, moteur LOCAL réplique du
    // serveur) : SIX tables neuves — `centres_cout_local`, `journaux_local`,
    // `plan_comptable_local`, `exercices_local`, `ecritures_local` et
    // `sequences_piece_local` (voir `tables/comptabilite_tables.dart`). M10
    // entre au périmètre local PAR DÉCISION DU PO (08/10 et 10/10/2026) ; chaque
    // table a un seul auteur (`MoteurComptable`, `installerReferentielComptable`)
    // et personne ne la descend. Les six noms sont assertés ci-dessous.
    //
    // 50 → 50 le 10/10/2026 (v16, M10 Dépenses, pièce comptable) : AUCUNE table
    // neuve — deux colonnes AJOUTÉES à `depenses_local` (`ecriture_id`,
    // `ecriture_refus`, voir `tables/depenses_tables.dart`). Le nombre ne bouge
    // pas, et c'est ici qu'on le DIT : une colonne ajoutée ne rouvre pas ce
    // compte, elle rouvre `migration_v16_depenses_test.dart`.
    //
    // 50 → 51 le 12/10/2026 (v17, sessions de caisse, réplique du serveur) : UNE
    // table neuve, `sessions_caisse_local` (voir `tables/caisse_tables.dart`). Seul
    // auteur : `SessionsCaisseDao`, personne ne la descend. Son nom est asserté
    // ci-dessous : un compte seul ne verrait pas une table remplacée par une autre.
    //
    // 51 → 52 le 12/10/2026 (v18, encaissement de facture, réplique du serveur) :
    // UNE table neuve, `paiements_facture_local` (voir
    // `tables/paiements_facture_tables.dart`), plus UNE colonne ajoutée à
    // `paniers_local` (`session_encaissement_id`, le `ventes.session_id` du
    // serveur). Seul auteur de la table : `PaiementsFactureDao`. L'ancienne
    // `paiements_local` (Sprint 0, REAL, sans session) reste sans écrivain : les
    // DEUX tables sont assertées ci-dessous, pour qu'un renommage ne passe pas
    // pour un ajout.
    //
    // 52 → 53 le 12/10/2026 (v20, règlement fournisseur, réplique du serveur) :
    // UNE table neuve, `reglements_fournisseur_local` (voir
    // `tables/reglements_fournisseur_tables.dart`), aucune colonne ajoutée.
    // Seul auteur : `ReglementsFournisseurDao`.
    //
    // 53 → 55 le 14/10/2026 : `alertes_vues_local` (v22, l'état « vu » des
    // alertes de la cloche, lot B ; seul auteur : le dépôt des alertes) et
    // `sejours_local` (v23, check-in / check-out, lot C, D408 ; seul auteur :
    // `SejourDao`). Les deux noms sont assertés ci-dessous.
    //
    // 55 → 56 le 14/10/2026 : `roles_local` (v24, Rôles & Permissions, D438 ;
    // seul auteur : `RolesDao`). Son nom est asserté ci-dessous.
    //
    // 56 → 57 le 14/10/2026 : `messages_editeur_local` (v25, boîte d'envoi de
    // « Contactez l'éditeur » ; seul auteur : `MessagesEditeurDao`). Son nom
    // est asserté ci-dessous.
    expect(base.allTables.length, 57);
    expect(base.schemaVersion, 25);
    expect(
      base.allTables.map((t) => t.actualTableName).toSet().containsAll({
        'messages_editeur_local',
        'roles_local',
        'alertes_vues_local',
        'sejours_local',
        'reglements_fournisseur_local',
        'sessions_caisse_local',
        'paiements_facture_local',
        'paiements_local',
      }),
      isTrue,
    );
    expect(
      base.allTables
          .firstWhere((t) => t.actualTableName == 'paniers_local')
          .$columns
          .map((c) => c.name),
      contains('session_encaissement_id'),
    );
    expect(
      base.allTables
          .firstWhere((t) => t.actualTableName == 'depenses_local')
          .$columns
          .map((c) => c.name),
      containsAll(['ecriture_id', 'ecriture_refus']),
    );
    expect(
      base.allTables.map((t) => t.actualTableName).toSet().containsAll({
        'menus_local',
        'recettes_local',
        'ingredients_recette_local',
        'plats_local',
      }),
      isTrue,
    );
    expect(
      base.allTables.map((t) => t.actualTableName).toSet().containsAll({
        'centres_cout_local',
        'journaux_local',
        'plan_comptable_local',
        'exercices_local',
        'ecritures_local',
        'sequences_piece_local',
      }),
      isTrue,
    );
    expect(
      base.allTables.map((t) => t.actualTableName).toSet().containsAll({
        'fournisseurs_local',
        'commandes_achat_local',
        'lignes_commande_achat_local',
        'bons_reception_local',
        'lignes_bon_reception_local',
      }),
      isTrue,
    );
  });

  test('insertion puis relecture d’un client', () async {
    const id = 'cli-test-0001';

    await base
        .into(base.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: id,
            nom: 'KORA',
            telephone: '01 90 12 34 56',
            typeClient: 'particulier',
          ),
        );

    final relu = await (base.select(
      base.clientsLocal,
    )..where((c) => c.id.equals(id))).getSingle();

    expect(relu.nom, 'KORA');
    expect(relu.telephone, '01 90 12 34 56');
    // Valeur par défaut : un enregistrement créé localement sans passer par la
    // file de synchronisation est considéré comme déjà synchronisé.
    expect(relu.statutSync, 'synchronise');
    expect(relu.solde, 0);
  });

  test('l’UUID vient du client, jamais d’un auto-incrément', () async {
    // C'est ce qui garantit l'idempotence si le réseau coupe en pleine
    // requête : le serveur reçoit deux fois la même opération et n'en
    // applique qu'une.
    const uuid = Uuid();
    final id = uuid.v4();

    await base
        .into(base.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: id,
            nom: 'DOSSOU',
            telephone: '01 91 22 33 44',
            typeClient: 'particulier',
          ),
        );

    final relu = await (base.select(
      base.clientsLocal,
    )..where((c) => c.id.equals(id))).getSingle();

    expect(relu.id, id);
    expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
  });

  test('un identifiant en double est refusé', () async {
    const id = 'cli-doublon';
    Future<void> inserer() => base
        .into(base.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: id,
            nom: 'ADJOVI',
            telephone: '01 92 00 00 00',
            typeClient: 'particulier',
          ),
        );

    await inserer();
    // Sans cette garantie, un rejeu de la file de synchronisation créerait un
    // doublon silencieux au lieu d'échouer visiblement.
    await expectLater(inserer(), throwsA(isA<SqliteException>()));
  });

  // ⚠ UN CAS A ÉTÉ RETIRÉ ICI le 14/09/2026, et son absence est délibérée.
  //
  // « la file de synchronisation accepte une opération en attente » vérifiait
  // qu'une entrée de `sync_queue` s'écrivait avec le statut `en_attente` et
  // sans motif de rejet. La décision « zéro réseau » du Product Owner a
  // supprimé la table (v10) : ce cas n'a plus de sujet, et aucune autre table
  // ne porte ce qu'il garantissait — il n'y a donc rien à réécrire, seulement
  // à constater.
  //
  // Écrit plutôt que tu : un test qui disparaît sans un mot se lit comme un
  // oubli, et quelqu'un finit par le remettre.
}
