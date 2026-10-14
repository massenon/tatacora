/// M8 Vehicules — offline-first complet.
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';

class VehiculesLocal extends Table {
  TextColumn get id => text()();
  TextColumn get categorie => text()();
  TextColumn get immatriculation => text()();
  RealColumn get tarifJour => real()();
  TextColumn get statut => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class ContratsLocationLocal extends Table {
  TextColumn get id => text()();
  TextColumn get vehiculeId => text().references(VehiculesLocal, #id)();
  TextColumn get clientId => text().references(ClientsLocal, #id)();
  TextColumn get guideId => text().nullable()(); // package optionnel EF-M8-04
  DateTimeColumn get dateDebut => dateTime()();
  DateTimeColumn get dateFin => dateTime()();
  TextColumn get cheminPieceIdentiteLocal =>
      text().nullable()(); // chemin fichier local avant upload
  TextColumn get cheminPermisConduireLocal => text().nullable()();
  TextColumn get statutUploadPieces =>
      text().withDefault(const Constant('en_attente'))();
  // 'en_attente' | 'televerse' — suivi distinct du statutSync des données textuelles
  // (LARAVEL_SYNC_FLUTTER.md §7 — fichiers joints envoyés séparément, jamais en base64
  // dans le lot JSON principal)
  TextColumn get statutSync =>
      text().withDefault(const Constant('synchronise'))();

  @override
  Set<Column> get primaryKey => {id};
}
