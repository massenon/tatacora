/// Le bulletin de paie — entité de domaine.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
library;

import 'employe.dart';

/// Les trois statuts d'un bulletin.
///
/// Aucun `supprime` : un bulletin faux **s'annule** avec un motif et reste au
/// dossier du salarié. Il sort du livre de paie et des déclarations, il ne
/// disparaît pas (RG-15).
enum StatutBulletin {
  brouillon('brouillon'),
  validee('validee'),
  annulee('annulee');

  const StatutBulletin(this.code);

  final String code;

  static StatutBulletin depuisCode(String code) {
    for (final statut in StatutBulletin.values) {
      if (statut.code == code) return statut;
    }
    // Un code inconnu ne devient pas « brouillon » par omission : un bulletin
    // dont on ignore l'état ne doit pas rejoindre le livre de paie.
    throw ArgumentError.value(code, 'code', 'Statut de bulletin hors registre');
  }
}

/// Un bulletin établi, **tous montants figés**.
final class BulletinPaie {
  const BulletinPaie({
    required this.id,
    required this.numero,
    required this.employe,
    required this.periode,
    required this.salaireBase,
    required this.totalPrimes,
    required this.totalRetenues,
    required this.cnssSalarie,
    required this.its,
    required this.chargesPatronalesConfirmees,
    required this.netAPayer,
    required this.statut,
    required this.etabliLe,
    this.motifAnnulation,
  });

  final String id;

  /// `BUL-AAAA-NNNNN`.
  final String numero;

  final Employe employe;

  /// `AAAA-MM`.
  final String periode;

  final int salaireBase;

  /// Toujours zéro dans ce dépôt : aucune table de primes n'est alimentée. Le
  /// « + Ajouter un élément » du maître n'est donc pas rendu, et le refus est
  /// nommé à l'écran plutôt que laissé en bouton inerte.
  final int totalPrimes;

  final int totalRetenues;
  final int cnssSalarie;
  final int its;

  /// 19,4 % du brut — CNSS pension, prestations familiales et VPS. **Jamais un
  /// total** : les risques professionnels n'y sont pas, et aucune colonne ne
  /// les accueille (PA-53).
  final int chargesPatronalesConfirmees;

  final int netAPayer;
  final StatutBulletin statut;
  final String? motifAnnulation;
  final DateTime etabliLe;

  /// Le brut soumis à cotisations.
  ///
  /// CALCULÉ, jamais stocké : deux colonnes qui doivent s'additionner pour en
  /// donner une troisième finissent par ne plus s'additionner.
  int get brut => salaireBase + totalPrimes;

  /// Brut moins la cotisation salariale. Appliquer le barème au brut
  /// surtaxerait chaque bulletin.
  int get revenuImposable => brut - cnssSalarie;

  /// Les retenues qui ne sont ni la CNSS ni l'ITS — avances, oppositions.
  ///
  /// Elle se **déduit** du total plutôt que de vivre à côté : un total qui ne
  /// serait pas la somme de ses parts est le défaut le plus difficile à voir
  /// sur un bulletin.
  int get autresRetenues => totalRetenues - (cnssSalarie + its);

  bool get estAnnule => statut == StatutBulletin.annulee;
}
