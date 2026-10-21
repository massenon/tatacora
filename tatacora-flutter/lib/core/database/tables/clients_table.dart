/// Clients — cache de lecture + creation offline (EF-M3-01).
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

class ClientsLocal extends Table {
  TextColumn get id =>
      text()(); // UUID généré côté client à la création (RG-18, §15 de 03_DATABASE_ENGINEERING.md)
  TextColumn get nom => text()();
  TextColumn get prenom => text().nullable()();
  TextColumn get telephone => text()();
  TextColumn get email => text().nullable()();
  TextColumn get typeClient =>
      text()(); // 'particulier' | 'groupe' | 'agence' | 'structure'
  RealColumn get solde => real().withDefault(const Constant(0))();
  TextColumn get statutSync =>
      text().withDefault(const Constant('synchronise'))();
  // 'synchronise' | 'en_attente_synchronisation' | 'conflit_en_attente' — affiché à
  // l'utilisateur comme badge de statut (04_UIUX_DESIGN_SYSTEM.md §3, StatusBadge)

  @override
  Set<Column> get primaryKey => {id};

  /// v35 (21/10/2026) : `false` = archivé ; `null` ou `true` = actif (nullable
  /// à dessein, comme `articles_local.actif`).
  BoolColumn get actif =>
      boolean().nullable().withDefault(const Constant(true))();
}
