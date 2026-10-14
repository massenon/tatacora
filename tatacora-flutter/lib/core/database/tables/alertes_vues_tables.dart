/// L'état « vu » des alertes de la cloche — RÉPLIQUE LOCALE de la table
/// `alertes_vues` du serveur (14/10/2026, lot B du plan du PO). Schéma v22, UNE
/// table neuve, migration additive.
///
/// ## Pourquoi une table, et pourquoi elle ne porte QUE l'état « vu »
///
/// Les alertes de la cloche sont DÉRIVÉES à la lecture (`AlertesOuverture` au
/// serveur, `features/alertes/domain/alertes_ouverture.dart` ici) : une alerte
/// affichée est vraie au moment où elle s'affiche, et disparaît d'elle-même
/// avec sa cause. Seul l'état « vu » se stocke, parce qu'il n'est dérivable de
/// rien — c'est la règle du serveur, mot pour mot.
///
/// Les colonnes sont celles de `alertes_vues` (migration du serveur : `id`,
/// `utilisateur_id`, `cle_alerte` de 160 caractères, `date_vue`, unicité du
/// couple `(utilisateur_id, cle_alerte)`).
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `AlertesVuesDao` (`marquerVues`), SEUL auteur, appelé par la cloche (« Tout marquer comme lu », clic sur une ligne) | `AlertesVuesDao.clesVues`, pour la pastille dorée et le badge | personne : zéro réseau |
///
/// Aucune colonne de synchronisation : l'état « vu » est celui d'un compte sur
/// CE poste ; il ne part nulle part, et aucun écran ne l'annonce « en attente ».
library;

import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

/// Une alerte qu'un compte a vue.
class AlertesVuesLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// Le compte qui a vu l'alerte. Vraie clé étrangère (`restrictOnDelete` au
  /// serveur) : un compte désactivé n'est jamais supprimé.
  TextColumn get utilisateurId => text().references(UtilisateursLocal, #id)();

  /// La clé DÉRIVÉE de l'alerte (`stock:<article>:<point>`, `caisse:<session>`,
  /// `creance:<facture>`…), 160 caractères au plus comme au serveur.
  TextColumn get cleAlerte => text().withLength(max: 160)();

  DateTimeColumn get dateVue => dateTime()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {utilisateurId, cleAlerte},
  ];
}
