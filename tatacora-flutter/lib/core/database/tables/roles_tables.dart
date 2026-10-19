/// Le référentiel des RÔLES du poste — réplique locale de la table `roles` du
/// serveur et de la matrice qu'elle porte (`permission_role`), 14/10/2026,
/// demande du Product Owner (« Rôles & Permissions » complet). Schéma v24, UNE
/// table neuve, migration additive.
///
/// ## Pourquoi une table
///
/// Au serveur, un compte porte un RÔLE, et ses droits se lisent du rôle
/// (`User::niveauSurModule()` → `Role::niveauSurModule()`). Sur ce poste, chaque
/// compte porte SES droits (`utilisateurs_local.droitsJson`, PA-103). Pour
/// créer un rôle, modifier ses droits ou rétablir le socle du CdCF comme le
/// fait `RolePermissionService`, il faut le référentiel rôle → droits ; les
/// droits d'un rôle sont ensuite RECOPIÉS sur les comptes qui le portent, ce
/// qui rend au poste l'effet immédiat du serveur.
///
/// ## Une colonne JSON, pas une table de liaison
///
/// Le serveur dérive le niveau du NOMBRE d'actions attachées (1 = L, plusieurs
/// = C, aucune = -) et `RolePermissionService` synchronise toujours l'ensemble
/// des actions d'un niveau : le seul état atteignable par l'écran est donc
/// « un niveau C/L/- par module ». Le poste le stocke tel quel, sous la forme
/// que lit déjà `GardeAcces.depuisJson` — une seconde représentation serait une
/// seconde formule.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | toutes | `RolesDao`, SEUL auteur : `installerSocle` (les rôles du socle ABSENTS, jamais réécrits — `RolePermissionSeeder::completerRolesNouveaux`), `creerRole`, `definirDroits`, `retablirSocle`, et `inscrireDescendu` (la descente, lot 10e) | `RolesDao.roles` (écran Rôles & Permissions) | le flux `roles` du serveur (lot 10e, 18/10/2026) : la matrice du serveur, par l'aligneur du catalogue, appariée au rôle local par son LIBELLÉ |
///
/// Aucune colonne de synchronisation : depuis le lot 10e, `creerRole`,
/// `definirDroits` et `retablirSocle` enfilent leur geste (`roles`, libellé
/// et matrice entière) dans la transaction de l'écriture. Les COMPTES ne
/// partent jamais (PA-103).
library;

import 'package:drift/drift.dart';

/// Un rôle du poste et sa matrice.
@DataClassName('RoleLocal')
class RolesLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// `roles.libelle` du serveur — le CODE du rôle (`administrateur`,
  /// `barman`…), celui que porte `utilisateurs_local.role`. Pas d'unicité au
  /// schéma, comme au serveur : c'est `RolesDao.creerRole` qui refuse un
  /// doublon (`role_deja_existant`).
  TextColumn get libelle => text()();

  /// `roles.description`, facultative.
  TextColumn get description => text().nullable()();

  /// La matrice du rôle, sérialisée : code de module → `C` / `L` / `-`. Un
  /// module absent vaut `-` (`GardeAcces`), jamais un droit par omission.
  TextColumn get droitsJson => text()();

  DateTimeColumn get dateCreation => dateTime()();
  DateTimeColumn get dateModification => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
