/// L'OCCUPATION des tables de salle par les AUTRES postes (et la PWA) — lot
/// F6, décision du Product Owner du 18/10/2026 (« il faut le créer » :
/// l'arbitrage des tables entre postes).
///
/// Une ligne par panier DE TABLE descendu du serveur qui n'est pas un panier
/// de CE poste. Ouvert, il occupe la table ici aussi : le plan de salle la
/// montre prise, et `PanierDao.ouvrir` refuse d'y ouvrir une addition. Les
/// paniers de ce poste restent dans `paniers_local` — l'occupation LOCALE se
/// déduit d'eux, jamais d'un drapeau (même règle que `TablesLocal`).
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `AligneurCatalogue` (descente), SEUL auteur | `TablesPosDao.salle`, `PanierDao.ouvrir` |
library;

import 'package:drift/drift.dart';

@DataClassName('OccupationTableLigne')
class OccupationsTablesLocal extends Table {
  /// L'identifiant du panier au serveur.
  TextColumn get panierId => text()();

  /// La table LOCALE (après correspondance), sans clé étrangère : une table
  /// du serveur pas encore reçue ne doit pas emporter la page de descente.
  TextColumn get tableId => text()();

  TextColumn get pointVente => text()();

  /// Le poste qui a ouvert l'addition, ou `null` (la PWA).
  TextColumn get posteOrigine => text().nullable()();

  /// Ouvert : la table est prise ailleurs.
  BoolColumn get ouvert => boolean()();

  DateTimeColumn get recuLe => dateTime()();

  @override
  Set<Column> get primaryKey => {panierId};
}
