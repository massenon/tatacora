import 'package:drift/drift.dart';

/// Le référentiel des utilisateurs, **sur le poste**.
///
/// ## Pourquoi cette table existe
///
/// Décision du Product Owner, 21/08/2026 : **l'authentification ne passe pas
/// par Laravel.** Le comptoir du Gîte doit ouvrir que le lien vers Cotonou
/// soit debout ou non, et pas seulement « après une première connexion en
/// ligne » — ce qui restait une dépendance déguisée.
///
/// La synchronisation porte sur les **modules métier** — ventes, POS, stocks,
/// rapports —, jamais sur la connexion. C'est la distinction qui structure
/// tout ce fichier : le **référentiel** des utilisateurs est une donnée comme
/// une autre, qui pourra se synchroniser un jour ; l'**authentification**, elle,
/// est locale et le reste.
///
/// ## Ce qui n'est PAS stocké : le mot de passe
///
/// Ni en clair, ni chiffré — un chiffrement suppose une clé, et une clé posée
/// sur le même disque que le secret qu'elle protège n'en protège aucun.
///
/// [sel], [empreinte] et [iterations] portent un dérivé **PBKDF2-HMAC-SHA256**
/// (`features/auth/data/verificateur_hors_ligne.dart`). Il permet de
/// **vérifier** un mot de passe, jamais de le retrouver.
///
/// ## Les droits sont une donnée, pas un calcul
///
/// [droitsJson] porte la matrice **16 modules × niveau** (`C` / `L` / `-`)
/// telle qu'elle a été accordée. Le client ne la recalcule jamais : il n'a
/// aucune autorité sur le RBAC (RG-16, premier des trois niveaux). Une
/// omission n'y vaut pas un droit — un module absent de la matrice est traité
/// comme `-`, jamais comme « non renseigné donc permis ».
@DataClassName('UtilisateurLocal')
class UtilisateursLocal extends Table {
  /// UUID v4 fourni par le client, comme partout ailleurs dans ce schéma.
  TextColumn get id => text()();

  /// L'identifiant de connexion, en minuscules.
  ///
  /// Normalisé à l'écriture : « N.Nabogou » et « n.nabogou » désignent la même
  /// personne, et deux lignes pour un seul employé donneraient deux jeux de
  /// droits qui divergeraient.
  TextColumn get login => text().unique()();

  TextColumn get nom => text()();

  /// Le rôle, tel que la matrice RBAC le nomme — `administrateur`,
  /// `receptionniste`, `barman`…
  TextColumn get role => text()();

  /// La matrice des droits, sérialisée. Voir la note de classe.
  TextColumn get droitsJson => text()();

  TextColumn get sel => text()();
  TextColumn get empreinte => text()();
  IntColumn get iterations => integer()();

  /// Un compte désactivé **reste** en base.
  ///
  /// Le supprimer effacerait l'imputabilité de tout ce qu'il a saisi (RG-15) :
  /// une vente encaissée par un employé parti doit continuer de porter son
  /// nom. C'est la même règle que l'archivage plutôt que la suppression, et
  /// c'est pourquoi aucune méthode de suppression n'est exposée.
  BoolColumn get actif => boolean().withDefault(const Constant(true))();

  DateTimeColumn get dateCreation => dateTime()();

  /// Dernière modification du mot de passe — pour qu'un changement soit
  /// traçable sans révéler quoi que ce soit du secret lui-même.
  DateTimeColumn get dateMotDePasse => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
