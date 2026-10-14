/// Période d'un séjour, en bornes **semi-ouvertes** `[arrivée, départ)`.
///
/// ## Pourquoi un objet dédié pour deux dates
///
/// La convention de bornes est la source d'erreur la plus coûteuse du module :
/// un départ le 12 et une arrivée le 12 **ne se chevauchent pas**, la chambre
/// est libérée le matin et relouée le soir. Se tromper de sens refuse des
/// réservations parfaitement valides — et ce refus est signalé par les clients,
/// jamais par un test.
///
/// La règle est donc écrite **une fois**, ici. Aucun autre fichier ne
/// soustrait deux dates : ni l'écran, ni le dépôt, ni le calcul de montant.
///
/// ## Le calcul des nuits ne passe pas par une différence de millisecondes
///
/// `fin.difference(debut).inDays` donne 1 au lieu de 2 dès qu'un changement
/// d'heure d'été traverse le séjour, et le Bénin n'est pas le seul fuseau où
/// l'application tournera. Les deux dates sont ramenées à minuit UTC avant
/// soustraction : seule la partie calendaire compte pour une nuitée.
final class PeriodeSejour {
  PeriodeSejour({required DateTime arrivee, required DateTime depart})
    : arrivee = _jour(arrivee),
      depart = _jour(depart) {
    if (!this.depart.isAfter(this.arrivee)) {
      throw ArgumentError.value(
        depart,
        'depart',
        'La date de départ doit être postérieure à la date d’arrivée '
            '(séjour de zéro nuit impossible).',
      );
    }
  }

  final DateTime arrivee;
  final DateTime depart;

  /// Minuit UTC du jour concerné — neutralise l'heure et le fuseau.
  static DateTime _jour(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Nombre de nuits facturables. Arrivée le 10, départ le 12 → 2.
  int get nuits => depart.difference(arrivee).inDays;

  /// Vrai si les deux périodes se recouvrent sur au moins une nuit.
  ///
  /// C'est la formulation locale de RG-01. Le serveur reste seul juge : lui
  /// seul voit les réservations des autres postes, et il pose un verrou
  /// pessimiste que le client ne peut pas simuler.
  bool chevauche(PeriodeSejour autre) =>
      arrivee.isBefore(autre.depart) && autre.arrivee.isBefore(depart);

  /// Vrai si le jour donné est occupé par ce séjour (départ exclu).
  bool contient(DateTime jour) {
    final j = _jour(jour);
    return !j.isBefore(arrivee) && j.isBefore(depart);
  }

  @override
  bool operator ==(Object other) =>
      other is PeriodeSejour &&
      other.arrivee == arrivee &&
      other.depart == depart;

  @override
  int get hashCode => Object.hash(arrivee, depart);

  @override
  String toString() => 'PeriodeSejour($arrivee → $depart, $nuits nuit(s))';
}
