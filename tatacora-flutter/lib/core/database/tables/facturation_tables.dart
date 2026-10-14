/// M2 Facturation — offline-first complet.
///
/// Categorie **financiere** au sens de `LARAVEL_SYNC_FLUTTER.md` §4.2 :
/// aucun conflit ne s'y resout automatiquement (RG-17).
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';

class FacturesLocal extends Table {
  TextColumn get id => text()();
  TextColumn get numeroMecef =>
      text().nullable()(); // null tant que non synchronisée+certifiée
  TextColumn get clientId => text().references(ClientsLocal, #id)();
  DateTimeColumn get dateEmission => dateTime()();
  RealColumn get montantHt => real()();
  RealColumn get montantTva => real()();
  RealColumn get montantTtc => real()();
  TextColumn get statut =>
      text()(); // 'brouillon' | 'en_attente_certification' | 'certifiee' | 'echec_certification'
  TextColumn get statutSync =>
      text().withDefault(const Constant('synchronise'))();

  @override
  Set<Column> get primaryKey => {id};
}

class LignesFactureLocal extends Table {
  TextColumn get id => text()();
  TextColumn get factureId => text().references(FacturesLocal, #id)();
  TextColumn get sourceModule => text()();
  TextColumn get sourceId => text()();
  TextColumn get libelle => text()();
  RealColumn get quantite => real()();
  RealColumn get prixUnitaire => real()();
  RealColumn get montant => real()();

  @override
  Set<Column> get primaryKey => {id};
}

class PaiementsLocal extends Table {
  TextColumn get id => text()();
  TextColumn get factureId => text().references(FacturesLocal, #id)();
  TextColumn get modePaiement => text()();
  RealColumn get montant => real()();
  DateTimeColumn get datePaiement => dateTime()();
  TextColumn get statutSync =>
      text().withDefault(const Constant('synchronise'))();

  @override
  Set<Column> get primaryKey => {id};
}
