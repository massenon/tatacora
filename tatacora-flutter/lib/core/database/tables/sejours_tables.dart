/// Les séjours — RÉPLIQUE LOCALE de la table `sejours` du serveur (14/10/2026,
/// lot C du plan du PO, décision du Lead D408 : « le serveur fait foi »).
/// Schéma v23, UNE table neuve, migration additive.
///
/// ## Pourquoi une table, et pourquoi celle du serveur
///
/// Le check-in et le check-out du serveur (`SejourService`) écrivent
/// `sejours.date_checkin_reel` / `date_checkout_reel` : c'est la seule source
/// qui réponde à « quelqu'un dort-il dans cette unité cette nuit ? »
/// (`Sejour::estEnCours()`). Sans elle, le poste ne pouvait ni faire d'arrivée,
/// ni dériver l'alerte « arrivée du jour sans check-in » (D403).
///
/// Les colonnes sont celles de la migration du serveur
/// (`create_hebergement.php` l.59-66) : `id`, `reservation_id` (clé étrangère,
/// `restrictOnDelete`), `date_checkin_reel`, `date_checkout_reel`,
/// `occupants` (JSON), plus les deux horodatages de `timestamps()`.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `SejourDao` (`checkin`, `checkout`), SEUL auteur, appelé par l'accueil (« Check-in », « Check-out », « Effectuer Check-in ») | `SejourDao.reservationsAuSejourOuvert` (bouton Check-in / Check-out de l'accueil), `SejourDao.arriveesSansCheckIn` (cloche) | personne : zéro réseau |
/// | `occupants` | `SejourDao.checkin` écrit `[]` (le serveur écrit le tableau vide : « aucun occupant relevé » ≠ « jamais renseigné ») | personne : aucun écran du serveur ne la saisit depuis l'accueil | personne |
///
/// Aucune colonne de synchronisation : un séjour enregistré ici reste ici, et
/// aucun écran ne l'annonce « en attente ».
library;

import 'package:drift/drift.dart';

import 'hebergement_tables.dart';

/// Une occurrence effective de séjour : arrivée et départ RÉELS.
class SejoursLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// La réservation que ce séjour réalise. Vraie clé étrangère : une
  /// réservation n'est jamais supprimée (RG-02 : on annule).
  TextColumn get reservationId => text().references(ReservationsLocal, #id)();

  DateTimeColumn get dateCheckinReel => dateTime().nullable()();

  DateTimeColumn get dateCheckoutReel => dateTime().nullable()();

  /// Les pièces d'identité des occupants (EF-M1-04), en JSON — `[]` au
  /// check-in, comme le serveur.
  TextColumn get occupants => text().nullable()();

  /// `created_at` / `updated_at` du serveur.
  DateTimeColumn get dateCreation => dateTime()();

  DateTimeColumn get dateModification => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
