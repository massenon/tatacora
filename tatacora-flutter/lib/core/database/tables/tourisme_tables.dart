/// M9 Tourisme — offline-first complet.
///
/// Le guide en circuit de plusieurs jours est le cas d'usage qui impose
/// une fenetre offline longue et interdit toute purge locale agressive.
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';

class CircuitsLocal extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  TextColumn get theme => text()();
  TextColumn get zone => text()();
  RealColumn get prix => real()();
  IntColumn get capaciteMax => integer()();

  /// `circuits.duree` — un `varchar` **LIBRE** au serveur (PA-51) : « 3 heures »,
  /// « 2 jours », « la journée ». Ajoutée en v10 (14/09/2026).
  ///
  /// **Nullable, et c'est le point** : les circuits déjà semés n'en portent
  /// aucune, et leur en inventer une — « 1 jour » par défaut — ferait dire à
  /// l'écran une durée que personne n'a saisie. Tant qu'elle est nulle, la
  /// colonne « Durée » et l'indicateur « Durée indéterminée » le DISENT.
  ///
  /// ⚠ Un texte libre ne se compare pas : un circuit de plusieurs jours ne
  /// bloque que son jour de départ, et le contrôle de capacité (RG-13) reste
  /// borné à la journée. Ne pas en déduire une plage.
  TextColumn get duree => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class GuidesLocal extends Table {
  TextColumn get id => text()();
  TextColumn get nom => text()();
  TextColumn get zoneCompetence => text().nullable()();

  /// v41 (27/10/2026) — la CERTIFICATION (`guides.certification`), texte libre.
  /// NULLABLE : un guide d'avant la v41 n'en a pas (les valeurs saisies PARTAIENT
  /// au serveur sans être rangées ici) ; la migration n'en fabrique aucune.
  ///
  /// | Qui l'écrit | Qui la lit | Qui la descend |
  /// |---|---|---|
  /// | `TourismeDao.enregistrerGuide` (il enfile) | la fiche du guide | `AligneurDocuments._guide` (n'enfile jamais) |
  TextColumn get certification => text().nullable()();

  /// v41 — le TARIF JOURNALIER en francs entiers (`guides.tarif_jour`). NULLABLE :
  /// « — » pour un guide d'avant ; jamais 0 par défaut (un tarif nul se lirait
  /// « gratuit »). Voir [certification].
  IntColumn get tarifJour => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReservationsTourLocal extends Table {
  TextColumn get id => text()();
  TextColumn get circuitId => text().references(CircuitsLocal, #id)();
  TextColumn get clientId => text().references(ClientsLocal, #id)();
  TextColumn get guideId => text().references(GuidesLocal, #id)();
  DateTimeColumn get dateCircuit => dateTime()();
  IntColumn get nbParticipants => integer()();
  TextColumn get statut => text()();
  TextColumn get statutSync =>
      text().withDefault(const Constant('en_attente_synchronisation'))();

  @override
  Set<Column> get primaryKey => {id};
}
