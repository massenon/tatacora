// Vue Blade maîtresse (PA-183) : pwa/hebergement/reservations.blade.php
/// M1 Hebergement — offline-first complet.
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';
import 'comptabilite_tables.dart';
import 'utilisateurs_table.dart';

class CategoriesHebergementLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();
  IntColumn get capaciteMax => integer()();
  RealColumn get tarifBase => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class UnitesHebergementLocal extends Table {
  TextColumn get id => text()();
  TextColumn get categorieId =>
      text().references(CategoriesHebergementLocal, #id)();
  TextColumn get numero => text()();
  TextColumn get statut =>
      text()(); // 'libre' | 'occupee' | 'reservee' | 'nettoyage' | 'hors_service'

  @override
  Set<Column> get primaryKey => {id};
}

/// Réservations d'hébergement.
///
/// ## Quatre colonnes ajoutées au schéma documenté (v2, 18/08/2026)
///
/// Le schéma d'origine ne permettait pas de tenir les garanties du domaine.
/// Les ajouts sont consignés au registre PA et reportés dans
/// `FULL_MIGRATIONS_DATABASE_FLUTTER.md`.
///
///  - **`tarifNuit`** — sans lui, le montant se recalcule depuis le tarif
///    *courant* de l'unité. Un changement de grille tarifaire réécrirait alors
///    silencieusement le montant d'une réservation déjà prise, et le client
///    recevrait une facture différente du devis. Le tarif se fige à la
///    réservation.
///  - **`motifRejet`** — ⚠ colonne SANS ÉCRIVAIN depuis le 14/09/2026. Elle
///    existait parce qu'une réservation refusée par le serveur devait être
///    *conservée avec le message du serveur* : `SyncQueue` portait bien un
///    motif, mais par **opération**, et l'entrée de file était purgée quand la
///    réservation, elle, restait. Zéro réseau : plus de serveur, donc plus de
///    refus distant, donc plus rien n'écrit ce motif. Elle est conservée — la
///    retirer serait une migration destructrice de plus pour une colonne qui
///    ne gêne personne — mais **aucun écran ne doit l'afficher comme un fait** :
///    elle est vide sur toute ligne, et le restera.
///  - **`reference`** — ce qu'on annonce au client. Provisoire tant que le
///    serveur n'a pas attribué sa numérotation continue.
///  - **`motifAnnulation`** — sans lui, désistement client, erreur de saisie et
///    rejet serveur se ressemblent exactement dans l'historique.
///
/// ## `statutSync` naît à `local`, pas à `synchronise`
///
/// C'est le changement le plus important, et il tient en un mot. Une
/// réservation créée sur ce poste n'a **jamais** touché le serveur : la
/// déclarer synchronisée par défaut est un mensonge que rien ne viendrait
/// corriger si la file échouait. `local` est la seule valeur honnête à la
/// création.
class ReservationsLocal extends Table {
  TextColumn get id =>
      text()(); // UUID client — jamais d'auto-incrément (offline-first)
  TextColumn get reference => text()();
  TextColumn get clientId => text().references(ClientsLocal, #id)();
  TextColumn get uniteId => text().references(UnitesHebergementLocal, #id)();
  DateTimeColumn get dateArrivee => dateTime()();
  DateTimeColumn get dateDepart => dateTime()();
  TextColumn get statut =>
      text()(); // 'confirmee' | 'en_cours' | 'terminee' | 'annulee'

  /// Tarif figé au moment de la réservation, en francs CFA (entier : le XOF
  /// n'a pas de sous-unité en circulation).
  IntColumn get tarifNuit => integer()();

  RealColumn get acompte => real().withDefault(const Constant(0))();

  /// La fiche du maître — quatre attributs que `reservations.html` demande et
  /// que ce schéma ignorait, si bien que le formulaire les aurait recueillis
  /// pour rien : une saisie qui disparaît est pire que le champ absent.
  ///
  /// Tous **nullables** : les réservations antérieures au schéma v7 n'en
  /// portent pas, et leur attribuer une valeur par défaut affirmerait un canal
  /// ou un mode de paiement que personne n'a choisi — l'analyse par canal
  /// deviendrait fausse sans que rien ne le signale.
  TextColumn get typeClient => text().nullable()();

  /// Le **code** du canal (`can-booking`…), pas son libellé : le libellé
  /// change, le code sert à comparer d'une version à l'autre.
  TextColumn get canal => text().nullable()();

  TextColumn get modePaiement => text().nullable()();

  /// `aucune` | `pourcentage` | `montant`.
  TextColumn get remiseType => text().nullable()();

  /// La valeur SAISIE — pourcentage ou francs selon [remiseType].
  ///
  /// Le **montant** de la remise, lui, ne se stocke pas : il se calcule, et le
  /// stocker créerait deux vérités qui divergeraient au premier changement de
  /// tarif.
  RealColumn get remiseValeur => real().nullable()();

  TextColumn get statutSync => text().withDefault(const Constant('local'))();
  // 'local' | 'en_attente' | 'synchronise' | 'rejete'

  /// Message du serveur en cas de refus — affiché tel quel au réceptionniste.
  TextColumn get motifRejet => text().nullable()();

  TextColumn get motifAnnulation => text().nullable()();

  // ======================================================================
  // v19 (12/10/2026) — l'ANNULATION avec commission et remboursement
  // (EF-M1-06). Huit colonnes AJOUTÉES, toutes NULLABLES : une réservation
  // jamais annulée n'en porte aucune, et une annulation d'AVANT la v19 non plus
  // (elle n'avait ni taux ni montant — en inventer un serait un chiffre
  // plausible et faux sur la commission d'un client).
  //
  // Ce sont les colonnes de `reservations` du serveur (`2026_09_03_220000`) ;
  // l'écart de représentation est unique et nommé : les montants sont des
  // CENTIMES ENTIERS (le serveur écrit `DECIMAL(15,2)`) et le taux des
  // CENTIÈMES de pour cent (`DECIMAL(5,2)`), jamais un flottant.
  //
  // | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
  // |---|---|---|---|
  // | les huit | `ReservationDao.annulerAvecConditions`, SEUL auteur, dans la même transaction que la pièce | l'onglet « Annulations » (total, taux, commission, remboursé, date, auteur) ; `ecriture_remboursement_id` et `mode_saisie_remboursement` : AUCUN écran, comme au serveur | personne : zéro réseau |
  //
  // Aucune contrainte `CHECK` : `ALTER TABLE ADD COLUMN` n'en porte pas de
  // croisée, et une base créée à neuf différerait d'une base migrée. Les bornes
  // (taux 0..100, remboursement <= acompte) sont tenues par le DAO.
  // ======================================================================

  /// Le taux appliqué, en CENTIÈMES de pour cent (`50.00 %` -> 5000).
  IntColumn get tauxAnnulationCentiemes => integer().nullable()();

  /// Le montant GLOBAL sur lequel la commission a été calculée (sous-total moins
  /// remise, AVANT l'acompte), en centimes. Figé : il ne se recalcule pas.
  IntColumn get montantTotalAnnulationCentimes => integer().nullable()();

  IntColumn get montantCommissionAnnulationCentimes => integer().nullable()();

  IntColumn get montantRembourseAnnulationCentimes => integer().nullable()();

  /// `pourcentage` | `montant` — la façon dont l'opérateur a saisi le
  /// remboursement. Écrite, lue par aucun écran (comme au serveur).
  TextColumn get modeSaisieRemboursement => text().nullable()();

  DateTimeColumn get dateAnnulation => dateTime().nullable()();

  /// Qui a annulé (RG-15). Vraie clé étrangère ; un compte désactivé n'est
  /// jamais supprimé.
  TextColumn get utilisateurAnnulationId =>
      text().nullable().references(UtilisateursLocal, #id)();

  /// La ligne DÉBIT (4191) de la pièce du remboursement, ou `NULL` quand aucun
  /// argent n'est sorti de la caisse. Écrite, lue par aucun écran.
  TextColumn get ecritureRemboursementId =>
      text().nullable().references(EcrituresLocal, #id)();

  DateTimeColumn get dateCreationLocale =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Les LIGNES DE SERVICE d'une réservation (schéma v8).
///
/// ## Pourquoi cette table existe
///
/// Le maître compose une réservation de plusieurs services — hébergement,
/// restauration, bar, tourisme, véhicule — chacun avec ses propres lignes
/// (`prototype_v2/pages/reservations.html` l.144, et
/// `reservations-services.js`). Le schéma s'arrêtait à `reservations.unite_id`
/// et `tarif_nuit` : une seule chambre, aucun autre service. Le sous-total du
/// récapitulatif valait donc `tarif × nuits` — juste pour un séjour sec, faux
/// dès qu'un circuit entre dans la même fiche, et sans que rien ne le signale.
///
/// ## Le libellé et le prix sont COPIÉS, pas référencés
///
/// Une ligne porte son libellé et son prix unitaire, figés à l'ajout. Les
/// relire au catalogue ferait varier le montant d'une réservation déjà prise
/// au premier changement de grille — c'est le raisonnement de `tarifNuit`
/// (PA-55) et des lignes de panier (PA-98), et il vaut ici pour la même
/// raison : le catalogue dit ce qu'on vend aujourd'hui, la ligne dit ce qui a
/// été vendu.
///
/// [itemId] reste néanmoins écrit : sans lui, impossible de rouvrir la fiche
/// avec la bonne entrée présélectionnée, ni de savoir quelle chambre est
/// engagée.
///
/// ## Aucune clé étrangère vers les catalogues, et c'est mesuré
///
/// Les cinq services visent cinq tables différentes, dont une — `plats` (M4) —
/// n'est pas répliquée sur le poste. Une clé étrangère par service imposerait
/// cinq colonnes nullables et une contrainte `CHECK` que SQLite ne saurait pas
/// porter vers MySQL à l'identique ; c'est le point Q1 du panier, tranché de la
/// même façon : un **registre fermé** (`service`) plus une vérification réelle
/// d'existence au moment de l'ajout, là où le catalogue est répliqué.
class LignesReservationLocal extends Table {
  TextColumn get id => text()();

  TextColumn get reservationId => text().references(ReservationsLocal, #id)();

  /// La `cle` du registre fermé `ServiceReservation` — jamais le nom affiché.
  TextColumn get service => text()();

  /// Le code de l'entrée retenue au catalogue du service.
  TextColumn get itemId => text()();

  /// FIGÉ à l'ajout — voir l'en-tête.
  TextColumn get libelle => text()();

  /// FIGÉ à l'ajout, en francs CFA.
  IntColumn get prixUnitaire => integer()();

  /// Nuits, participants, jours ou unités selon le service.
  IntColumn get quantite => integer()();

  /// L'ordre de saisie. Sans lui, la fiche rouverte réordonne ses lignes au
  /// gré du moteur de base, et le réceptionniste ne retrouve pas ce qu'il a
  /// tapé.
  IntColumn get ordre => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
