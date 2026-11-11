/// Plannings d'équipe et congés (M13, EF-M13-02 / EF-M13-04) — entités du poste.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/conges-plannings.blade.php
///
/// Registres FERMÉS, relus du serveur (`Conge::TYPES`, `Conge::STATUT_*`) : un
/// cas ajouté demain ne doit pas obtenir un comportement par omission.
library;

import '../refus_rh.dart';

/// La nature d'un congé — `Conge::TYPES` du serveur, dans son ordre.
enum TypeConge {
  annuel('annuel', 'Congé annuel'),
  maladie('maladie', 'Maladie'),
  exceptionnel('exceptionnel', 'Congé exceptionnel'),
  maternite('maternite', 'Maternité');

  const TypeConge(this.code, this.libelle);

  final String code;

  /// `type_*` de `lang/fr/rh_conges_pwa.php`.
  final String libelle;

  static TypeConge? depuisCode(String? code) {
    for (final t in TypeConge.values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

/// La décision portée par une demande.
enum StatutConge {
  enAttente('en_attente', 'En attente'),
  valide('valide', 'Validé'),
  refuse('refuse', 'Refusé');

  const StatutConge(this.code, this.libelle);

  final String code;

  /// `statut_*` de `lang/fr/rh_conges_pwa.php`.
  final String libelle;

  static StatutConge? depuisCode(String? code) {
    for (final s in StatutConge.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

/// Un créneau planifié. Les jours sont des `AAAA-MM-JJ`, les heures des `HH:MM`.
final class CreneauPlanning {
  const CreneauPlanning({
    required this.id,
    required this.employeId,
    required this.employeNom,
    required this.serviceId,
    required this.serviceLibelle,
    required this.date,
    required this.heureDebut,
    required this.heureFin,
  });

  final String id;
  final String employeId;
  final String employeNom;
  final String serviceId;
  final String serviceLibelle;
  final String date;
  final String heureDebut;
  final String heureFin;
}

/// Une demande de congé et sa décision.
final class DemandeConge {
  const DemandeConge({
    required this.id,
    required this.employeId,
    required this.employeNom,
    required this.type,
    required this.dateDebut,
    required this.dateFin,
    required this.jours,
    required this.statut,
    this.validateur,
  });

  final String id;
  final String employeId;
  final String employeNom;
  final TypeConge type;
  final String dateDebut;
  final String dateFin;

  /// Bornes incluses, comme `Conge::nombreJours()`.
  final int jours;
  final StatutConge statut;

  /// Le login de qui a décidé ; `null` = « — » (en attente, ou ligne descendue).
  final String? validateur;
}

/// Les trois bandeaux de tête de l'écran.
final class IndicateursCongesPlannings {
  const IndicateursCongesPlannings({
    required this.creneauxDuJour,
    required this.enAttente,
    required this.enCongeAujourdhui,
  });

  final int creneauxDuJour;
  final int enAttente;
  final int enCongeAujourdhui;
}

/// Un employé proposé aux formulaires (en poste : `actif` ou `conge`).
final class EmployePlanifiable {
  const EmployePlanifiable({required this.id, required this.nomComplet});

  final String id;
  final String nomComplet;
}

/* ====================================================================== */
/* Messages et refus                                                       */
/* ====================================================================== */

/// Les phrases de refus, **reprises au mot de `tatacora-api/lang/fr/rh.php`**
/// (apostrophe DROITE comprise). Un test les relit par PHP : elles ne
/// peuvent pas s'écarter du serveur sans le faire rougir.
abstract final class MessagesCongesPlannings {
  static const String chevauchement =
      'Cet employé est déjà planifié sur un créneau qui recouvre celui-ci.';

  static String horsEffectif(String statut) =>
      "Cet employé n'est pas en poste ($statut) : il ne peut pas être planifié.";

  static String enConge(String date) =>
      'Cet employé est en congé validé le $date.';

  static const String dejaTraite =
      'Cette demande a déjà été validée ou refusée.';

  static String preavisInsuffisant({
    required int reel,
    required String exige,
  }) => 'Préavis insuffisant : $reel jour(s) au lieu des $exige exigés.';

  static String couvertureInsuffisante({
    required int restants,
    required String minimum,
  }) =>
      'Couverture de service compromise : $restants employé(s) resteraient '
      'en poste pour un minimum de $minimum.';

  static String parametreAbsent(String cle) =>
      "Le paramètre « $cle » n'est pas configuré. "
      "Aucune validation de congé n'est possible tant qu'un Administrateur ne "
      "l'a pas renseigné.";

  /// Les contrôles de forme que le serveur fait par ses règles de validation :
  /// le poste les dit avant d'écrire, pour ne rien enfiler qui serait rejeté.
  static const String employeRequis = 'Choisissez un employé.';
  static const String serviceRequis = 'Choisissez un service.';
  static const String dateIllisible = 'La date est illisible.';
  static const String heureIllisible = "L'heure est illisible (HH:MM).";
  static const String heureFinAvantDebut =
      "L'heure de fin doit être après l'heure de début.";
  static const String finAvantDebut =
      'La date de fin ne peut pas précéder la date de début.';
  static const String employeInconnu = 'Cet employé est introuvable.';
  static const String serviceInconnu = 'Ce service est introuvable.';
  static const String demandeInconnue = 'Cette demande est introuvable.';
  static const String typeInconnu = 'La nature du congé est inconnue.';
}

/// Un refus du module planning/congés — la phrase est celle du serveur.
final class RefusCongesPlannings extends RefusRh {
  const RefusCongesPlannings(this.message);

  @override
  final String message;
}
