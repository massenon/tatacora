// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
/// Le parc de véhicules.
library;

import '../regles_vehicules.dart';

/// Les sept catégories de l'enum `vehicules.categorie`.
///
/// ## Le code STOCKÉ et le libellé AFFICHÉ sont deux choses
///
/// `code` est la valeur en base (`voiture`), `libelle` ce que l'écran montre
/// (« Berline »). Les confondre est ce qui faisait sortir « velo » en valeur
/// d'enum brute sur la PWA (corrigé le 02/09/2026) : les libellés viennent de
/// `tatacora-api/lang/fr/vehicules.php` (`pwa.categorie_*`), au mot.
///
/// ⚠ « voiture » se dit **« Berline »** — l'arbitrage du seeder, pris dans ce
/// sens-là. Le libellé n'est jamais dérivé du code par une mise en majuscule.
///
/// ## Sept valeurs, alors que l'ancien maître n'en connaissait que cinq
///
/// `scooter` et `velo` sont au schéma et absents de son jeu de démonstration.
/// Le PHPDoc du serveur le dit : « Ne pas la restreindre aux 5 valeurs du
/// prototype ». Un registre fermé auquel il manquerait deux valeurs rangerait
/// un vrai véhicule dans « inconnu ».
enum CategorieVehicule {
  voiture('voiture', 'Berline'),
  quatreQuatre('4x4', '4x4'),
  pickup('pickup', 'Pick-up'),
  moto('moto', 'Moto'),
  scooter('scooter', 'Scooter'),
  velo('velo', 'Vélo'),
  bus('bus', 'Bus');

  const CategorieVehicule(this.code, this.libelle);

  /// La valeur STOCKÉE dans `vehicules_local.categorie`.
  final String code;

  /// Le libellé d'AFFICHAGE — `vehicules.pwa.categorie_*`.
  final String libelle;

  static CategorieVehicule? depuisCode(String? code) {
    for (final c in CategorieVehicule.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Les quatre valeurs de l'enum `vehicules.statut`.
enum StatutVehicule {
  disponible('disponible', 'Disponible'),
  loue('loue', 'Loué'),
  entretien('entretien', 'Entretien'),
  horsService('hors_service', 'Hors service');

  const StatutVehicule(this.code, this.libelle);

  final String code;
  final String libelle;

  /// Un véhicule **immobilisé** : il n'est proposé nulle part. `loue` n'en est
  /// pas — il est engagé, pas immobilisé, et il redeviendra libre à la fin de
  /// son contrat.
  bool get estImmobilise =>
      this == StatutVehicule.entretien || this == StatutVehicule.horsService;

  static StatutVehicule? depuisCode(String? code) {
    for (final s in StatutVehicule.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Un véhicule du parc, tel que `vehicules_local` le porte.
///
/// ## Le maître affiche un NOM ; le schéma n'en a pas
///
/// La table porte `immatriculation`, `categorie`, `tarif_jour` et `statut` —
/// **aucune colonne de nom**. L'écran affiche donc l'immatriculation, seul
/// identifiant qui existe, et le dit.
///
/// ## Année, places et transmission : portés depuis la v41 (27/10/2026)
///
/// `annee`, `transmission` et `capacite` sont des colonnes NULLABLES de
/// `vehicules_local` (décision D1/D2 du PO : le poste fait comme le web). Un
/// véhicule d'avant la v41 les a à `null` et l'écran rend « — » : la migration
/// n'en fabrique aucun.
final class Vehicule {
  const Vehicule({
    required this.id,
    required this.immatriculation,
    required this.categorie,
    required this.categorieBrute,
    required this.annee,
    required this.transmission,
    required this.capacite,
    required this.tarifJour,
    required this.statut,
    required this.statutBrut,
    required this.exigePermis,
  });

  final String id;
  final String immatriculation;
  final CategorieVehicule? categorie;
  final String? categorieBrute;

  /// L'année (`vehicules_local.annee`, v41). `null` : véhicule d'avant, ou
  /// jamais saisie — « — » s'affiche, jamais « 0 ».
  final int? annee;

  /// La transmission (v41), texte libre. `null` : « — ».
  final String? transmission;

  /// Le nombre de places (v41). `null` : « — » s'affiche, jamais « 0 ».
  final int? capacite;

  /// Montant décimal en chaîne (« 25000.00 »), converti une seule fois au DAO.
  final String tarifJour;

  final StatutVehicule? statut;
  final String? statutBrut;

  /// RG-09 — dérivé de [exigePermisPour], **l'unique auteur local**.
  ///
  /// ⚠ Il ne vient plus du serveur : il n'y a plus de serveur. La liste des
  /// catégories dispensées vit dans `domain/regles_vehicules.dart`, qui cite
  /// `Vehicule::CATEGORIES_SANS_PERMIS` comme la seule décision (PA-50) et
  /// qu'un test relit contre le fichier PHP. Le recalculer ici en donnerait une
  /// seconde version.
  final bool exigePermis;

  /// Le véhicule est-il proposable ? `disponible` et `loue` — un véhicule loué
  /// aujourd'hui reste louable demain, ce que le statut seul ne dit pas.
  bool get estLouable => statutsLouables.contains(statutBrut);

  String? get categorieLibelle => categorie?.libelle ?? categorieBrute;
  String? get statutLibelle => statut?.libelle ?? statutBrut;
}

/// La disponibilité d'UN véhicule sur UNE période.
///
/// ## Deux booléens, jamais un seul
///
/// « Un véhicule au calendrier libre mais en entretien n'est pas louable pour
/// autant. » Les fondre en un seul « disponible » ferait proposer à la location
/// un véhicule au garage.
final class DisponibiliteVehicule {
  const DisponibiliteVehicule({
    required this.vehiculeId,
    required this.calendrierLibre,
    required this.statutLouable,
  });

  final String vehiculeId;

  /// Aucun contrat ne chevauche la période. **Confort d'affichage** : entre
  /// cette lecture et l'écriture, le parc a pu changer. Seule la création du
  /// contrat protège réellement (RG-08).
  final bool calendrierLibre;

  final bool statutLouable;

  /// Ce que la vue appelle « Disponible » : les deux à la fois.
  bool get disponible => calendrierLibre && statutLouable;
}
