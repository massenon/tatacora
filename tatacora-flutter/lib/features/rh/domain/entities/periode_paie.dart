/// La période de paie — `AAAA-MM`.
///
/// Vue Blade maîtresse (PA-183) : pwa/rh/paie.blade.php
library;

/// Un mois de paie.
///
/// ## L'échéance du VPS se CALCULE, elle ne se saisit pas
///
/// Une date d'échéance recopiée à la main vieillit d'un mois à chaque période,
/// et personne ne s'en aperçoit : c'est la famille de défauts PA-59/60/61
/// appliquée à une date.
final class PeriodePaie {
  const PeriodePaie._(this.annee, this.mois);

  /// Lit « 2026-09 ». Rend `null` sur toute autre forme — la période vient
  /// d'un champ, donc de l'extérieur, et une période illisible ne doit pas
  /// atteindre les services au milieu d'un rendu.
  static PeriodePaie? depuisTexte(String? brut) {
    if (brut == null) return null;
    if (!RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(brut)) return null;

    return PeriodePaie._(
      int.parse(brut.substring(0, 4)),
      int.parse(brut.substring(5, 7)),
    );
  }

  factory PeriodePaie.deLaDate(DateTime date) =>
      PeriodePaie._(date.year, date.month);

  final int annee;
  final int mois;

  /// Les mois en toutes lettres. Écrits ici plutôt que tirés d'`intl` : le
  /// dépôt formate déjà ses dates à la main (`core/format/formats.dart`), et
  /// une seconde voie de formatage finirait par rendre « September ».
  static const List<String> _mois = [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ];

  /// `2026-09`.
  String get code => '$annee-${mois.toString().padLeft(2, '0')}';

  /// « septembre 2026 » — l'`isoFormat('MMMM YYYY')` du composant.
  String get libelleLong => '${_mois[mois - 1]} $annee';

  /// Le 10 du mois **suivant** : déclaration et paiement du VPS.
  DateTime get echeanceVps =>
      mois == 12 ? DateTime(annee + 1, 1, 10) : DateTime(annee, mois + 1, 10);

  @override
  bool operator ==(Object other) =>
      other is PeriodePaie && other.annee == annee && other.mois == mois;

  @override
  int get hashCode => Object.hash(annee, mois);

  @override
  String toString() => code;
}
