/// Les entités du moteur comptable — des faits du domaine, jamais une ligne
/// Drift ni un DTO d'API (un `Repository` n'expose pas un modèle Drift).
///
/// Les dates sont des chaînes `AAAA-MM-JJ`, comme au serveur (`whereDate`) :
/// une date comptable n'a pas d'heure, et un fuseau ne doit pas la décaler d'un
/// jour. Les montants sont des CENTIMES entiers (`montant_comptable.dart`).
library;

import '../montant_comptable.dart';

/// `brouillon` -> `validee` : `validee` est le point de non-retour de RG-11.
enum StatutEcriture {
  brouillon('brouillon'),
  validee('validee');

  const StatutEcriture(this.valeur);

  /// La valeur stockée, celle de l'`enum` du serveur.
  final String valeur;

  static StatutEcriture depuis(String valeur) =>
      StatutEcriture.values.firstWhere(
        (s) => s.valeur == valeur,
        orElse: () =>
            throw StateError("Statut d'écriture inconnu : « $valeur »."),
      );
}

/// Registre fermé du serveur : `ouvert`, `en_cloture`, `cloture`.
enum StatutExercice {
  ouvert('ouvert'),
  enCloture('en_cloture'),
  cloture('cloture');

  const StatutExercice(this.valeur);

  final String valeur;

  static StatutExercice depuis(String valeur) =>
      StatutExercice.values.firstWhere(
        (s) => s.valeur == valeur,
        orElse: () =>
            throw StateError("Statut d'exercice inconnu : « $valeur »."),
      );
}

final class CompteDuPlan {
  const CompteDuPlan({
    required this.id,
    required this.numero,
    required this.libelle,
    required this.classe,
    required this.nature,
    required this.centreCoutDefautId,
  });

  final String id;
  final String numero;
  final String libelle;

  /// Le premier chiffre du numéro.
  final String classe;
  final String? nature;
  final String? centreCoutDefautId;
}

final class JournalComptable {
  const JournalComptable({
    required this.id,
    required this.code,
    required this.libelle,
  });

  final String id;
  final String code;
  final String libelle;
}

final class CentreDeCout {
  const CentreDeCout({required this.id, required this.libelle, this.type});

  final String id;
  final String libelle;
  final String? type;
}

final class ExerciceComptable {
  const ExerciceComptable({
    required this.id,
    required this.annee,
    required this.dateDebut,
    required this.dateFin,
    required this.statut,
    this.dateCloture,
    this.utilisateurClotureId,
  });

  final String id;
  final int annee;
  final String dateDebut;
  final String dateFin;
  final StatutExercice statut;
  final DateTime? dateCloture;
  final String? utilisateurClotureId;
}

/// UNE ligne d'écriture. Une pièce est l'ensemble des lignes qui partagent un
/// [numeroPiece] (PA-52 : le serveur n'a pas d'autre identifiant de pièce).
final class EcritureComptable {
  const EcritureComptable({
    required this.id,
    required this.exerciceId,
    required this.journalId,
    required this.compteId,
    required this.centreId,
    required this.dateEcriture,
    required this.libelle,
    required this.debitCentimes,
    required this.creditCentimes,
    required this.statut,
    required this.ecritureContrepasseeId,
    required this.numeroPiece,
    required this.creeLe,
    required this.creePar,
    required this.modifieLe,
    required this.modifiePar,
  });

  final String id;
  final String exerciceId;
  final String journalId;
  final String compteId;
  final String centreId;
  final String dateEcriture;
  final String libelle;
  final int debitCentimes;
  final int creditCentimes;
  final StatutEcriture statut;

  /// La ligne d'ORIGINE que celle-ci inverse, `null` sinon.
  final String? ecritureContrepasseeId;
  final String? numeroPiece;
  final DateTime creeLe;
  final String creePar;
  final DateTime? modifieLe;
  final String? modifiePar;

  /// `"12500.00"` — la forme du serveur, pour les messages et les états.
  String get debit => chaineDepuisCentimes(debitCentimes);
  String get credit => chaineDepuisCentimes(creditCentimes);

  bool get estValidee => statut == StatutEcriture.validee;
}
