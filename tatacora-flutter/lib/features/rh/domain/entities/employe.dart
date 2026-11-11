/// Le dossier du personnel — entités de domaine.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
library;

import '../refus_rh.dart';

/// Le service (département) d'affectation.
final class ServiceRh {
  const ServiceRh({required this.id, required this.libelle});

  final String id;
  final String libelle;
}

/// Les quatre types de contrat — **registre fermé du maître**.
///
/// Un cinquième type ajouté demain ne doit pas obtenir un comportement par
/// omission : le DAO refuse à l'écriture tout code hors de ce registre.
enum TypeContrat {
  cdi('CDI'),
  cdd('CDD'),
  stage('Stage'),
  journalier('Journalier');

  const TypeContrat(this.code);

  final String code;

  /// `null` pour « non renseigné » — le contrat est facultatif au schéma.
  ///
  /// Lève sur un code **présent mais inconnu** : la fiche a été écrite par un
  /// chemin qui a contourné la garde du DAO, et le taire afficherait un contrat
  /// vide sur un dossier qui en porte un.
  static TypeContrat? depuisCode(String? code) {
    if (code == null || code.isEmpty) return null;
    for (final type in TypeContrat.values) {
      if (type.code == code) return type;
    }
    throw ContratInconnu(code);
  }
}

/// Les quatre statuts au schéma.
///
/// ⚠ Le maître rend ces codes **tels quels** dans sa liste déroulante
/// (`{{ $statut }}`), et l'écran fait de même : les habiller de libellés
/// donnerait deux vocabulaires pour un même dossier, celui de la fiche et celui
/// du filtre.
enum StatutEmploye {
  actif('actif'),
  conge('conge'),
  suspendu('suspendu'),
  parti('parti');

  const StatutEmploye(this.code);

  final String code;

  static StatutEmploye depuisCode(String code) {
    for (final statut in StatutEmploye.values) {
      if (statut.code == code) return statut;
    }
    throw StatutEmployeInconnu(code);
  }

  /// En poste = payable. Un salarié en congé garde son bulletin ; un salarié
  /// suspendu ou parti n'entre pas dans la génération du mois.
  bool get estEnPoste => this == actif || this == conge;
}

/// Un salarié.
final class Employe {
  const Employe({
    required this.id,
    required this.matricule,
    required this.nom,
    required this.prenom,
    required this.poste,
    required this.serviceId,
    required this.serviceLibelle,
    required this.dateEmbauche,
    required this.salaireBase,
    required this.statut,
    this.dateFinContrat,
    this.numeroCnss,
    this.typeContrat,
    this.email,
  });

  final String id;
  final String matricule;
  final String nom;
  final String prenom;

  /// L'e-mail FACULTATIF (v45), déjà normalisé ; `null` : non renseigné.
  final String? email;
  final String poste;
  final String serviceId;

  /// Le libellé joint. `null` si le service a disparu du référentiel — l'écran
  /// rend alors un tiret plutôt qu'une chaîne vide.
  final String? serviceLibelle;

  final DateTime dateEmbauche;
  final DateTime? dateFinContrat;
  final String? numeroCnss;
  final TypeContrat? typeContrat;

  /// En francs CFA. **Le seul montant saisi du module.**
  final int salaireBase;

  final StatutEmploye statut;

  /// Nom puis prénoms, dans l'ordre du maître.
  ///
  /// Une seule implémentation : l'écran, le bulletin imprimé et l'export
  /// doivent nommer le salarié de la même façon, sinon un rapprochement manuel
  /// entre deux documents devient impossible.
  String nomComplet() => '$nom $prenom'.trim();

  /// ⚠ Sans numéro CNSS, le bulletin se **calcule** mais le salarié ne peut pas
  /// figurer à la déclaration.
  ///
  /// Le prédicat vit ici pour qu'il n'y ait qu'une définition de « absent »
  /// dans l'écran, l'export et le document imprimé.
  bool get sansNumeroCnss => numeroCnss == null || numeroCnss!.trim().isEmpty;

  bool get estEnPoste => statut.estEnPoste;
}
