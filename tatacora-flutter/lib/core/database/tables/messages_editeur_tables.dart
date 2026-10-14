/// La BOÎTE D'ENVOI de « Contactez l'éditeur » — réplique locale de la table
/// `messages_editeur` du serveur (migration `2026_09_04_100000`), schéma v25,
/// UNE table neuve, migration additive. Directive du Product Owner du
/// 14/10/2026 (Lot J2, partie 2) : le poste ENVOIE réellement le message à
/// l'éditeur, par SMTP.
///
/// ## Pourquoi une table, et pourquoi AVANT l'envoi
///
/// Le poste du Gîte perd sa connexion. Le message s'écrit d'abord ici
/// (`en_attente`), PUIS l'envoi est tenté : une coupure, un serveur SMTP
/// injoignable ou un mot de passe absent ne perdent donc rien — le message
/// attend et repart à la relance suivante. C'est la règle du serveur
/// (`MessageEditeurService::enregistrer` écrit, puis tente) : « le geste de
/// l'utilisateur a une valeur même non transmis ».
///
/// ## Trois statuts, pas deux
///
/// Le serveur n'en a que deux (`a_transmettre` / `transmis`). Le poste en
/// ajoute un : `echec`, posé quand les relances AUTOMATIQUES sont épuisées
/// (`PolitiqueRelanceEditeur.tentativesMax`). Le message n'est PAS supprimé —
/// aucune ligne de cette table ne l'est jamais — et « Renvoyer maintenant »
/// le remet en file. `envoye` n'est écrit QUE quand le serveur SMTP a accepté
/// le message, jamais parce qu'une configuration existe en apparence
/// (PA-59/60/61).
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `MessagesEditeurDao`, SEUL auteur : `enregistrer` (le geste de l'écran), `marquerEnvoye` / `marquerTentativeEchouee` / `marquerNonTente` (`ServiceMessagesEditeur`), `remettreEnFile` (« Renvoyer maintenant ») | `MessagesEditeurDao.envoisDuCompte` (« Vos envois »), `etatFile` (« Messages en attente d'envoi »), `aEnvoyer` (la relance) | personne : la table ne remonte à aucun serveur — le MESSAGE part par courriel, la ligne reste ici |
///
/// ## Ce qu'elle ne porte JAMAIS
///
/// Aucun mot de passe SMTP : il est relu à l'envoi dans
/// `%APPDATA%\TATACORA\poste.json` et n'est écrit nulle part
/// (`configuration_poste.dart`). `derniere_erreur` est expurgée du secret
/// avant écriture.
///
/// Gardée par « Réinitialiser comme neuf », comme `messages_editeur` au
/// serveur (`ReinitialisationDonneesTestService::TABLES_PRESERVEES`).
library;

import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

/// Un message (ou un signalement de bug) adressé à l'éditeur.
@DataClassName('MessageEditeurLocal')
class MessagesEditeurLocal extends Table {
  /// UUID posé **côté client**, à la saisie — jamais à l'envoi.
  TextColumn get id => text()();

  /// `message` ou `bug` — `messages_editeur.type` du serveur.
  TextColumn get type => text()();

  /// Le sujet : l'objet saisi (message) ou « Bug — `module` » (bug), comme
  /// `messages_editeur.objet`.
  TextColumn get sujet => text()();

  /// Le module concerné d'un signalement de bug (registre fermé de la vue),
  /// nul pour un message.
  TextColumn get moduleConcerne => text().nullable()();

  TextColumn get corps => text()();

  /// « Étapes pour reproduire » d'un signalement, facultatives.
  TextColumn get etapes => text().nullable()();

  /// L'auteur RÉEL — le compte de la session, jamais une valeur saisie
  /// (`utilisateur_creation_id` du serveur). Nul seulement sans session.
  TextColumn get auteurId =>
      text().nullable().references(UtilisateursLocal, #id)();

  /// L'identifiant de connexion de l'auteur, FIGÉ à la saisie : il figure
  /// dans le courriel (« Auteur : … ») comme `auteur->login` au serveur.
  TextColumn get auteurLogin => text().nullable()();

  /// Le nom du poste (`Platform.localHostname`) à la saisie.
  TextColumn get poste => text().nullable()();

  DateTimeColumn get creeLe => dateTime()();

  /// `en_attente`, `envoye` ou `echec` — voir l'en-tête.
  TextColumn get statut => text().withDefault(const Constant('en_attente'))();

  /// Les tentatives RÉELLES (une connexion au serveur SMTP a été essayée).
  /// Un envoi impossible faute de configuration ne compte pas.
  IntColumn get tentatives => integer().withDefault(const Constant(0))();

  /// La raison du dernier échec, en clair, sans secret.
  TextColumn get derniereErreur => text().nullable()();

  /// Le moment de la dernière tentative — l'ancre du délai de relance.
  DateTimeColumn get derniereTentative => dateTime().nullable()();

  /// Le moment où le serveur SMTP a ACCEPTÉ le message.
  DateTimeColumn get envoyeLe => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
