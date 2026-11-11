/// Les PLANNINGS d'équipe et les CONGÉS (M13, EF-M13-02 et EF-M13-04) — v33,
/// 21/10/2026 (« ce que le web fait, le poste le fait »).
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
///
/// Deux tables, comme `plannings` et `conges` du serveur. Aucune clé
/// étrangère : l'employé et le service peuvent descendre dans une autre page du
/// flux (leçon du piège 11) ; c'est le DAO qui vérifie qu'ils existent avant
/// d'écrire une saisie.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `CongesPlanningsDao` (saisie), `AligneurDocuments` (descente) | écran « Congés & Plannings » |
library;

import 'package:drift/drift.dart';

/// Un créneau planifié : un employé, un service, un jour, deux heures.
///
/// Les heures sont du TEXTE `HH:MM` : ce n'est pas un instant, c'est une plage
/// dans la journée, et le serveur les compare comme telles (RG-13). Un créneau
/// se crée, il ne se modifie pas.
@DataClassName('PlanningLigne')
class PlanningsLocal extends Table {
  TextColumn get id => text()();

  TextColumn get employeId => text()();

  TextColumn get serviceId => text()();

  /// Le jour (minuit local).
  DateTimeColumn get date => dateTime()();

  /// `HH:MM`.
  TextColumn get heureDebut => text()();

  /// `HH:MM`, strictement après [heureDebut].
  TextColumn get heureFin => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Une demande de congé et sa décision.
///
/// La décision est la SEULE modification admise (`en_attente` → `valide` |
/// `refuse`) : une demande décidée ne se rouvre pas.
@DataClassName('CongeLigne')
class CongesLocal extends Table {
  TextColumn get id => text()();

  TextColumn get employeId => text()();

  /// `annuel` | `maladie` | `exceptionnel` | `maternite` — registre fermé du
  /// serveur (`Conge::TYPES`).
  TextColumn get type => text()();

  /// Premier jour (minuit local).
  DateTimeColumn get dateDebut => dateTime()();

  /// Dernier jour INCLUS, jamais avant [dateDebut].
  DateTimeColumn get dateFin => dateTime()();

  /// `en_attente` | `valide` | `refuse`.
  TextColumn get statutValidation =>
      text().withDefault(const Constant('en_attente'))();

  /// Le login de qui a décidé ; `null` tant que la demande attend, et pour une
  /// ligne descendue (le serveur ne livre pas le validateur) — l'écran rend « — ».
  TextColumn get validateur => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
