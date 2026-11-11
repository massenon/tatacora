/// Les tables et colonnes que la PWA écrit et que le poste n'écrivait pas —
/// v35, 21/10/2026 (« tout doit être au complet » : immobilisations,
/// relances, inventaires, archivage, composition provisoire, remise du panier).
///
/// Quatre tables neuves, sans clé étrangère (leçon du piège 11 : l'élément cité
/// peut descendre dans une autre page du flux ; le DAO vérifie l'existence).
/// Les montants sont des CENTIMES entiers (le serveur : `DECIMAL(15,2)`), les
/// quantités d'inventaire des CENTIÈMES entiers (`DECIMAL(10,2)`).
///
/// | Table | Qui l'écrit | Qui la lit |
/// |---|---|---|
/// | `immobilisations_local` | `ImmobilisationsDao` (saisie), `AligneurDocuments` (descente) | onglet Immobilisations du hub comptable |
/// | `relances_clients_local` | `RelancesClientsDao` (saisie), `AligneurDocuments` (descente) | registre des créances |
/// | `inventaires_local`, `lignes_inventaire_local` | `InventairesDao` (clôture), `AligneurDocuments` (descente) | écran Inventaire physique |
library;

import 'package:drift/drift.dart';

/// Une immobilisation : un bien, sa valeur d'origine, sa durée d'amortissement.
@DataClassName('ImmobilisationLigne')
class ImmobilisationsLocal extends Table {
  TextColumn get id => text()();

  /// Unique au serveur (RG de `ImmobilisationService`).
  TextColumn get code => text()();

  TextColumn get libelle => text()();

  /// Numéro de compte d'immobilisation (231, 244…), facultatif.
  TextColumn get compteImmobilisation => text().nullable()();

  IntColumn get valeurOrigineCentimes => integer()();

  /// `AAAA-MM-JJ`.
  TextColumn get dateMiseService => text()();

  /// 1 à 60 ; `null` pour une ligne descendue qui n'en porte pas.
  IntColumn get dureeAnnees => integer().nullable()();

  /// Le login de qui a saisi ; `null` pour une ligne descendue.
  TextColumn get creePar => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Une relance d'un client débiteur : un fait daté, jamais modifié.
@DataClassName('RelanceClientLigne')
class RelancesClientsLocal extends Table {
  TextColumn get id => text()();

  TextColumn get clientId => text()();

  /// `AAAA-MM-JJ`.
  TextColumn get dateRelance => text()();

  /// `telephone` | `whatsapp` | `email` | `courrier` | `visite`.
  TextColumn get canal => text()();

  IntColumn get montantReclameCentimes => integer()();

  /// `AAAA-MM-JJ` de la promesse de paiement, facultative.
  TextColumn get promesse => text().nullable()();

  TextColumn get commentaire => text().nullable()();

  TextColumn get creePar => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// L'en-tête d'un inventaire physique clôturé (un point, un jour).
@DataClassName('InventaireLigne')
class InventairesLocal extends Table {
  TextColumn get id => text()();

  TextColumn get pointId => text()();

  /// `AAAA-MM-JJ`.
  TextColumn get dateInventaire => text()();

  TextColumn get utilisateurId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Une ligne comptée : le théorique, le constaté et l'écart, en CENTIÈMES.
@DataClassName('LigneInventaireLigne')
class LignesInventaireLocal extends Table {
  TextColumn get id => text()();

  TextColumn get inventaireId => text()();

  TextColumn get articleId => text()();

  IntColumn get quantiteTheoriqueCentiemes => integer()();

  IntColumn get quantiteConstateeCentiemes => integer()();

  IntColumn get ecartCentiemes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Un canal de réservation (Direct, Téléphone, Booking…) : le registre que la
/// PWA gère (ajout, renommage, désactivation) et que la fiche de réservation
/// propose.
@DataClassName('CanalReservationLigne')
class CanauxReservationLocal extends Table {
  TextColumn get id => text()();

  TextColumn get nom => text()();

  BoolColumn get actif => boolean().withDefault(const Constant(true))();

  IntColumn get ordre => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
