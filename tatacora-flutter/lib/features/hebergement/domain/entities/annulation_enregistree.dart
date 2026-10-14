/// Ce que l'annulation d'une réservation a FIXÉ — la copie, sur la réservation,
/// du calcul de `AnnulationReservationService` : le taux, le montant global sur
/// lequel la commission a été retenue, la commission, le remboursement, qui a
/// annulé et quand.
///
/// ## Figé, jamais recalculé
///
/// Le total d'une réservation peut bouger (une ligne ajoutée avant l'annulation,
/// un changement de grille) ; la commission, elle, a été retenue sur CE total, à
/// CE taux. Les relire depuis la fiche montrerait un autre chiffre le jour où la
/// fiche changerait. Tout est donc stocké (`reservations_local`, v19).
///
/// ## Une annulation d'AVANT la v19 n'en a pas
///
/// `Reservation.annulation` est alors `null`, et l'onglet « Annulations » la
/// montre avec des tirets : lui prêter un taux affirmerait une commission que
/// personne n'a retenue.
library;

final class AnnulationEnregistree {
  const AnnulationEnregistree({
    required this.tauxCentiemes,
    required this.totalCentimes,
    required this.commissionCentimes,
    required this.rembourseCentimes,
    required this.modeSaisie,
    required this.date,
    this.auteurId,
    this.auteurLogin,
    this.ecritureRemboursementId,
  });

  /// Le taux en centièmes de pour cent (`50.00 %` -> 5000).
  final int tauxCentiemes;

  /// Le montant GLOBAL de la réservation, en centimes, AVANT déduction de
  /// l'acompte.
  final int totalCentimes;

  final int commissionCentimes;
  final int rembourseCentimes;

  /// `pourcentage` ou `montant`. Écrite, lue par aucun écran (comme au serveur).
  final String modeSaisie;

  final DateTime date;

  /// Qui a annulé (RG-15) et son identifiant de connexion, pour la colonne
  /// « Par ».
  final String? auteurId;
  final String? auteurLogin;

  /// La ligne DÉBIT (4191) de la pièce du remboursement, ou `null` quand aucun
  /// argent n'est sorti de la caisse.
  final String? ecritureRemboursementId;

  bool get aRembourse => rembourseCentimes > 0;

  /// Le taux tel que la vue l'imprime : `rtrim(rtrim(number_format($t, 2),
  /// '0'), '.').' %'` — « 50 % », « 12.5 % », « 12.55 % ».
  String get tauxAffiche {
    final entier = tauxCentiemes ~/ 100;
    final reste = (tauxCentiemes % 100).toString().padLeft(2, '0');
    final decimales = reste.replaceFirst(RegExp(r'0+$'), '');
    return decimales.isEmpty ? '$entier %' : '$entier.$decimales %';
  }
}
