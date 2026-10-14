/// Les refus du check-in et du check-out — `lang/fr/sejour.php` du serveur, au
/// mot (apostrophe droite, comme le fichier de langue).
///
/// Le serveur les lève depuis `SejourService` (`RuntimeException`) et le
/// composant de l'accueil les affiche sous la modale (`addError`) : ici, ils
/// sont portés par [RefusSejour] et affichés de même.
library;

abstract final class MessagesSejour {
  /// `sejour.reservation_annulee`.
  static const String reservationAnnulee =
      "Cette réservation est annulée : aucun client n'est attendu. "
      'Rétablissez une réservation valide avant de faire une arrivée.';

  /// `sejour.deja_arrive` — `:date` au format `d/m/Y H:i`.
  static String dejaArrive(String date) =>
      "L'arrivée a déjà été enregistrée le $date. "
      'La ressaisir créerait un second séjour pour un seul client.';

  /// `sejour.deja_parti` — `:date` au format `d/m/Y H:i`, VIDE quand le
  /// composant ne trouve aucun séjour ouvert (`Accueil::confirmerCheckout`
  /// passe `['date' => '']` : la phrase finit alors sur « le . »).
  static String dejaParti(String date) =>
      'Le départ a déjà été enregistré le $date.';

  /// `sejour.unite_hors_service`.
  static String uniteHorsService(String unite) =>
      "L'unité $unite est hors service : son état ne se change pas par une "
      "arrivée ou un départ. Levez la maintenance d'abord.";

  /// Réservation introuvable — `Reservation::findOrFail` lève au serveur une
  /// `ModelNotFoundException` (page 404, aucun message de langue). Écart
  /// nommé : ce poste le dit plutôt que de lever sans un mot.
  static const String reservationIntrouvable =
      "Cette réservation n'existe pas sur ce poste.";
}

/// Un check-in ou un check-out REFUSÉ : rien n'a été écrit.
class RefusSejour implements Exception {
  const RefusSejour(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `d/m/Y H:i` — le format que le serveur écrit dans `deja_arrive` et
/// `deja_parti`.
String dateHeureCommeServeur(DateTime d) {
  String deux(int n) => n.toString().padLeft(2, '0');
  return '${deux(d.day)}/${deux(d.month)}/${d.year} '
      '${deux(d.hour)}:${deux(d.minute)}';
}
