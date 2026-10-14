/// Une ligne de `reservations_tour_local`, enrichie de ses libellés.
///
/// Les noms du circuit, du client et du guide sont résolus par le DAO :
/// l'écran ne doit jamais afficher un UUID, qui ne dit rien au comptoir.
library;

/// Le statut d'une réservation — **registre fermé**, celui du serveur.
///
/// `ReservationTour::STATUTS_INACTIFS = ['annulee']` : seule l'annulation
/// libère la place au départ. Une valeur inconnue ne reçoit pas de
/// comportement par omission — elle est refusée à la lecture.
enum StatutReservationTour {
  reservee('reservee', 'Réservée'),
  enCours('en_cours', 'En cours'),
  terminee('terminee', 'Terminée'),
  annulee('annulee', 'Annulée');

  const StatutReservationTour(this.cle, this.libelle);

  /// La valeur stockée, celle du serveur.
  final String cle;

  /// Le libellé du maître (`lang/fr/tourisme.php`, `pwa.etat_*`).
  final String libelle;

  /// `null` sur une valeur inconnue : le DAO décide alors d'écarter la ligne
  /// plutôt que de lui prêter un statut. Un `default => reservee` ferait
  /// compter une réservation cassée comme une place vendue.
  static StatutReservationTour? depuisCle(String cle) {
    for (final s in StatutReservationTour.values) {
      if (s.cle == cle) return s;
    }
    return null;
  }

  /// Une réservation annulée ne consomme plus de place (RG-13, cumul).
  bool get estAnnulee => this == StatutReservationTour.annulee;

  /// Une prestation clôturée ne s'annule plus et ne change plus de guide.
  bool get estTerminee => this == StatutReservationTour.terminee;
}

final class ReservationTour {
  const ReservationTour({
    required this.id,
    required this.circuitId,
    required this.circuitNom,
    required this.prixUnitaire,
    required this.capaciteCircuit,
    required this.clientId,
    required this.clientNom,
    required this.guideId,
    required this.guideNom,
    required this.dateCircuit,
    required this.nbParticipants,
    required this.statut,
    this.clientTelephone,
    this.dureeCircuit,
  });

  final String id;

  final String circuitId;
  final String circuitNom;

  /// Le prix du circuit **au moment de la lecture**, en francs entiers.
  ///
  /// ⚠ Ce n'est PAS un prix figé à la réservation : `reservations_tour` n'a
  /// aucune colonne de prix, ni au serveur ni ici. Une prestation dont le
  /// tarif change au catalogue voit donc son montant changer rétroactivement.
  /// Le maître calcule de la même façon (`ReservationTour::montant()` lit
  /// `$this->circuit->prix`) ; l'écart avec la règle « prix figé à l'ajout »
  /// du panier est une lacune de SCHÉMA, nommée et non contournée.
  final int prixUnitaire;

  final int capaciteCircuit;
  final String? dureeCircuit;

  final String clientId;
  final String clientNom;
  final String? clientTelephone;

  /// Jamais `null` — la colonne est NOT NULL (PA-51).
  final String guideId;
  final String guideNom;

  /// Le jour du départ, **normalisé à minuit** par le DAO : un départ est le
  /// couple (circuit, date), et une heure de saisie en ferait deux.
  final DateTime dateCircuit;

  final int nbParticipants;
  final StatutReservationTour statut;

  /// Montant de la prestation — **CALCULÉ, jamais stocké ni saisi**
  /// (`ReservationTour::montant()`). Règle du dépôt : toute valeur calculable
  /// s'affiche en lecture seule.
  int get montant => prixUnitaire * nbParticipants;

  bool get estAnnulee => statut.estAnnulee;
}
