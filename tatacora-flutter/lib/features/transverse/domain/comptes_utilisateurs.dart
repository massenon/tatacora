/// Les COMPTES UTILISATEURS du poste — Lot J2, directive du Product Owner du
/// 14/10/2026 : un administrateur crée les comptes de ses employés, les
/// désactive ou les réactive, et réinitialise leur mot de passe. Jamais de
/// suppression (RG-15 : un compte désactivé reste en base, ses saisies gardent
/// leur auteur).
///
/// ## Un AJOUT du poste, sans modèle dans la vue
///
/// La PWA n'a aucun écran de gestion des comptes (relu le 14/10/2026 : ni
/// composant sous `app/Pwa`, ni vue, ni route `pwa.*` ; les comptes y naissent
/// par l'opérateur). Les mots ci-dessous sont donc ceux du poste ; ils
/// reprennent ceux de « Rôles & Permissions » et de « Mon profil » partout où
/// ces écrans en ont (libellé des rôles, règle des 8 caractères).
library;

import '../../../core/rbac/regle_archivage.dart';

/// Un compte tel que l'écran le liste — JAMAIS le sel ni l'empreinte.
final class CompteUtilisateur {
  const CompteUtilisateur({
    required this.id,
    required this.identifiant,
    required this.nom,
    required this.role,
    required this.actif,
    required this.dateCreation,
    required this.dateMotDePasse,
  });

  final String id;

  /// `utilisateurs_local.login`, en minuscules.
  final String identifiant;
  final String nom;

  /// Le CODE du rôle (`administrateur`, `barman`…), affiché par `libelleRole`.
  final String role;
  final bool actif;
  final DateTime dateCreation;
  final DateTime dateMotDePasse;

  /// L'un des deux rôles d'administration (`User::ROLES_ADMINISTRATION`).
  bool get estAdministration =>
      rolesAdministration.contains(roleNormalise(role));
}

/// L'auteur d'un geste peut-il administrer les comptes ? Les deux rôles
/// d'administration, et eux seuls — identifiés par leur CODE
/// (`utilisateurs_local.role`), jamais par leur libellé affiché.
bool peutAdministrerComptes(String? role) =>
    rolesAdministration.contains(roleNormalise(role));

/// Les règles de saisie, écrites une fois — l'écran les affiche, le DAO les
/// rejoue au geste.
abstract final class ReglesComptes {
  /// La règle de `SessionRepositoryLocal.creerCompte` et `changerMotDePasse`.
  static const int longueurMinMotDePasse = 8;

  static const int longueurMinIdentifiant = 3;
  static const int longueurMaxIdentifiant = 50;
  static const int longueurMaxNom = 150;

  /// Minuscules, chiffres, point, tiret et souligné — commence par une lettre
  /// ou un chiffre (`n.nabogou`, `barman2`). L'identifiant est normalisé en
  /// minuscules AVANT ce contrôle, comme à la connexion.
  static final RegExp formatIdentifiant = RegExp(r'^[a-z0-9][a-z0-9._-]*$');

  /// L'identifiant tel qu'il sera stocké et comparé à la connexion.
  static String normaliserIdentifiant(String saisie) =>
      saisie.trim().toLowerCase();
}

/// Les messages de l'écran et des refus.
abstract final class MessagesComptes {
  static const String refusDroit = "Ce geste est réservé à l'Administrateur.";
  static const String nomObligatoire = 'Le nom complet est obligatoire.';
  static const String nomTropLong =
      'Le nom complet ne peut pas dépasser 150 caractères.';
  static const String identifiantObligatoire = "L'identifiant est obligatoire.";
  static const String identifiantLongueur =
      "L'identifiant doit compter de 3 à 50 caractères.";
  static const String identifiantFormat =
      "L'identifiant ne peut contenir que des lettres minuscules sans accent, "
      'des chiffres, le point, le tiret et le souligné.';
  static String identifiantPris(String identifiant) =>
      "L'identifiant « $identifiant » est déjà utilisé sur ce poste.";
  static const String roleObligatoire = 'Choisissez un rôle.';
  static const String roleInconnu = "Ce rôle n'existe pas sur ce poste.";
  static const String motDePasseCourt =
      'Le mot de passe doit compter au moins 8 caractères.';
  static const String confirmationDifferente =
      'Les deux saisies ne correspondent pas.';
  static const String motDePasseIdentique =
      "Le nouveau mot de passe est identique à l'ancien.";
  static const String compteIntrouvable = 'Ce compte est introuvable.';
  static const String desactiverSoiMeme =
      'Vous ne pouvez pas désactiver votre propre compte.';
  static const String dernierAdministrateur =
      'Ce compte est le dernier administrateur actif du poste : le désactiver '
      "fermerait l'administration à tout le monde.";

  static String compteCree(String identifiant) =>
      'Compte « $identifiant » créé.';
  static String compteDesactive(String identifiant) =>
      'Compte « $identifiant » désactivé.';
  static String compteReactive(String identifiant) =>
      'Compte « $identifiant » réactivé.';
  static String motDePasseReinitialise(String identifiant) =>
      'Mot de passe de « $identifiant » réinitialisé.';
}

/// Un refus d'un geste sur les comptes — par CHAMP, pour que la modale
/// l'affiche sous le champ fautif (`droit` / `compte` : en tête de modale).
final class RefusComptes implements Exception {
  const RefusComptes(this.erreurs);

  RefusComptes.message(String champ, String message)
    : erreurs = {champ: message};

  final Map<String, String> erreurs;

  String get message => erreurs.values.first;

  @override
  String toString() => message;
}
