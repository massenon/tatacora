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

  /// v41 (27/10/2026) — LES TROIS CHAMPS DE LA FICHE VÉHICULE que le web saisit
  /// (`Locations::enregistrerVehicule` : Année, Places, Transmission), comme
  /// `vehicules.annee` / `.capacite` / `.transmission` du serveur. NULLABLES : un
  /// véhicule d'avant la v41 n'en a pas, et la migration n'en fabrique aucun
  /// (l'écran affiche « — », jamais une valeur plausible).
  ///
  /// | Qui l'écrit | Qui la lit | Qui la descend |
  /// |---|---|---|
  /// | `VehiculeDao.enregistrerVehicule` (seul écrivain de saisie, il enfile) | le parc, le planning, l'état « Véhicules » | `AligneurDocuments._vehicule` (n'enfile jamais) |
  IntColumn get annee => integer().nullable()();

  /// v41 — les « Places » (`capacite` du serveur), 1 à 99. Voir [annee].
  IntColumn get capacite => integer().nullable()();

  /// v41 — la transmission, texte libre (255 au plus), vidable. Voir [annee].
  TextColumn get transmission => text().nullable()();

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

  /// v38 (26/10/2026) — LE STATUT du contrat, comme `contrats_location.statut`
  /// du serveur : `actif` ou `annule`. NULLABLE : un contrat d'avant la v38 n'a
  /// pas de statut, et `null` se lit « actif » (le seul état qu'il pouvait
  /// avoir — aucun geste ne l'annulait). Aucune valeur n'est fabriquée par la
  /// migration.
  ///
  /// | Qui l'écrit | Qui la lit | Qui la descend |
  /// |---|---|---|
  /// | `VehiculeDao.annulerContrat` (seul écrivain de saisie) ; l'aligneur de documents applique l'annulation DU SERVEUR (`annulationDescendue`) | le planning, la disponibilité (RG-08), les indicateurs, l'archivage d'un client | `AligneurDocuments._contratLocation` (vers l'avant seulement : `annule` ne redevient jamais `actif`) |
  TextColumn get statut => text().nullable()();

  /// v41 (27/10/2026) — LE N° `LOC-` du contrat (`contrats_location.numero`).
  /// NULLABLE, et le poste n'en INVENTE aucun : la séquence est celle du serveur,
  /// qui le rend à l'accusé du `POST /sync` (`VehiculeDao.regulariserNumero`) ou à
  /// la descente. Un contrat d'avant, ou pas encore envoyé : « — ».
  ///
  /// | Qui l'écrit | Qui la lit | Qui la descend |
  /// |---|---|---|
  /// | `SyncManager` (accusé) par `VehiculeDao.regulariserNumero` ; l'aligneur | la liste des contrats, l'état « Locations » | `AligneurDocuments._contratLocation` (n'enfile jamais) |
  TextColumn get numero => text().nullable()();

  /// v41 — la REMISE accordée à la signature, en francs entiers
  /// (`Locations::enregistrerContrat`, « Remise (FCFA) »). NULLABLE : le serveur
  /// ne la garde pas (il n'en range que le montant net), donc un contrat descendu
  /// d'un autre poste ou du web n'en a pas — « — », jamais déduite par
  /// soustraction avec un tarif qui a pu changer.
  IntColumn get remise => integer().nullable()();

  /// v41 — l'ACOMPTE reçu, en francs entiers (« Acompte reçu (FCFA) »). NULLABLE :
  /// « — » pour un contrat d'avant. Écrit par `VehiculeDao.creerContrat`, descendu.
  IntColumn get acompte => integer().nullable()();

  /// v41 — LE MONTANT NET, FIGÉ À LA SIGNATURE (tarif du jour × jours − remise), en
  /// francs entiers : `contrats_location.montant` du serveur. Avant la v41, le
  /// montant était RECALCULÉ au tarif courant du véhicule — un changement de grille
  /// réécrivait un contrat déjà signé. NULLABLE : un contrat d'avant n'a pas de
  /// montant figé et la migration n'en déduit AUCUN (« — », pas le tarif courant).
  /// Le « reste dû » en est la différence avec l'acompte : jamais une colonne.
  IntColumn get montant => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
