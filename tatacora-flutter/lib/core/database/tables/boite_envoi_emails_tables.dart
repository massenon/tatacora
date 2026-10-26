/// La BOÎTE D'ENVOI des e-mails du poste — schéma v39, UNE table neuve,
/// migration additive. Décision du Product Owner du 26/10/2026 : « l'envoi
/// réel d'e-mails DOIT ÊTRE IMPLÉMENTÉ EN POSTE ET WEB ».
///
/// ## Ce qu'elle porte, et ce qu'elle ne porte pas
///
/// Les e-mails que le poste ÉCRIT mais n'envoie pas lui-même au moment du
/// geste : aujourd'hui les notifications M12 de canal e-mail (source
/// `notification`). « Contactez l'éditeur » a SA boîte (v25,
/// `messages_editeur_local`, schéma plus ancien, déjà éprouvée) ; elle n'est
/// pas migrée ici : ses messages portent type, module, étapes et capture que
/// cette table n'a pas.
///
/// ## Écrit D'ABORD, envoyé ENSUITE
///
/// La ligne naît `en_attente`, hors ligne ou non. Un réseau absent, un relais
/// SMTP injoignable ou un mot de passe non saisi ne perdent rien : le message
/// attend, avec sa raison, et repart à la relance suivante (repli
/// exponentiel, `PolitiqueRelanceEmail`) ou à « Renvoyer ». `envoye` n'est
/// écrit QUE quand le relais SMTP a accepté le message — jamais parce qu'une
/// configuration existe (PA-59/60/61).
///
/// ## Jamais deux e-mails pour une même chose
///
/// `cle_idempotence` est UNIQUE au schéma : `notification:<id du message>`.
/// Deux détections, deux clics, une relance qui croise le geste : une seule
/// ligne, donc un seul courriel.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `BoiteEnvoiEmailsDao`, SEUL auteur : `mettreEnFile` (la composition d'un e-mail de notification), `marquerEnvoye` / `marquerTentativeEchouee` / `marquerNonTente` (`ServiceBoiteEnvoiEmails`), `remettreEnFile` (« Renvoyer ») | `parSource` (la file de M12 : tentatives, cause), `enAttente` (la relance), `etatFile` | personne : le courriel part par SMTP, la ligne reste ici |
///
/// ## Ce qu'elle ne porte JAMAIS
///
/// Aucun mot de passe SMTP : il est relu à l'envoi dans `poste.json`
/// (`configuration_poste.dart`). `derniere_erreur` est expurgée du secret
/// avant écriture. Aucune ligne n'est jamais supprimée.
///
/// Gardée par « Réinitialiser comme neuf », comme `messages_editeur_local`.
library;

import 'package:drift/drift.dart';

/// Un e-mail à envoyer (ou envoyé) par ce poste.
@DataClassName('EnvoiEmailLocal')
class BoiteEnvoiEmailsLocal extends Table {
  /// UUID posé **côté client**, à l'écriture — jamais à l'envoi.
  TextColumn get id => text()();

  /// L'idempotence, posée au SCHÉMA : `notification:<id du message>`.
  TextColumn get cleIdempotence => text().unique()();

  /// L'origine : `notification` (M12).
  TextColumn get source => text()();

  /// L'identifiant de l'objet d'origine (le message de notification).
  TextColumn get sourceId => text().nullable()();

  /// L'adresse RÉELLE du destinataire — jamais un nom d'affichage.
  TextColumn get adresse => text()();

  /// Le nom affiché du destinataire.
  TextColumn get destinataireNom => text().nullable()();

  TextColumn get objet => text()();

  TextColumn get corps => text()();

  DateTimeColumn get creeLe => dateTime()();

  /// `en_attente`, `envoye`, `echec` (relances automatiques épuisées) ou
  /// `annule` (le message d'origine a été transmis à la main ou abandonné
  /// avant l'envoi).
  TextColumn get statut => text().withDefault(const Constant('en_attente'))();

  /// Les tentatives RÉELLES (une connexion au relais SMTP a été essayée). Un
  /// envoi impossible faute de configuration ne compte pas.
  IntColumn get tentatives => integer().withDefault(const Constant(0))();

  /// La raison du dernier échec, en clair, SANS secret.
  TextColumn get derniereErreur => text().nullable()();

  /// L'ancre du délai de relance.
  DateTimeColumn get derniereTentative => dateTime().nullable()();

  /// Le moment où le relais SMTP a ACCEPTÉ le message.
  DateTimeColumn get envoyeLe => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
