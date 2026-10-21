/// Les ENTRETIENS et CARBURATIONS des véhicules (M8, EF-M8-05) — v32,
/// 21/10/2026 (« ce que le web fait, le poste le fait »).
///
/// Une ligne par fait daté, comme `entretiens_vehicule` du serveur : le type
/// (`entretien` | `carburation`), le jour, le coût en francs entiers et, si on
/// l'a, le chauffeur. Une ligne ne se modifie jamais. Le statut du véhicule
/// n'en dépend pas (la PWA ne le touche pas non plus : statut ≠ disponibilité).
///
/// Aucune clé étrangère : le véhicule et le chauffeur peuvent descendre dans une
/// autre page du flux (leçon du piège 11).
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `VehiculeDao.enregistrerEntretien` (saisie), `AligneurCatalogue` (descente) | onglet « Immobilisations » |
library;

import 'package:drift/drift.dart';

@DataClassName('EntretienVehiculeLigne')
class EntretiensVehiculeLocal extends Table {
  TextColumn get id => text()();

  TextColumn get vehiculeId => text()();

  /// `entretien` | `carburation` — registre fermé du serveur.
  TextColumn get type => text()();

  /// Le jour (minuit local).
  DateTimeColumn get date => dateTime()();

  /// Francs entiers (`cout` du serveur est un décimal à deux chiffres : une
  /// fraction de franc est REFUSÉE à la descente).
  IntColumn get cout => integer()();

  TextColumn get chauffeurId => text().nullable()();

  /// Le login de qui a saisi, pour « Enregistré par » ; `null` pour une ligne
  /// descendue (le serveur ne livre pas l'auteur) — l'écran rend « — ».
  TextColumn get auteur => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
