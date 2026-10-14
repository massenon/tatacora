import '../entities/disponibilite.dart';
import '../entities/periode_sejour.dart';
import '../repositories/reservation_repository.dart';

/// Consulte la disponibilité du parc sur une période.
///
/// Le cas d'usage n'ajoute pas de règle métier à celles du dépôt : il fixe
/// l'**ordre de présentation**, qui est une décision métier et non un détail
/// d'affichage. Les unités libres d'abord, les moins chères en tête — c'est ce
/// que le réceptionniste propose en premier quand un client hésite.
final class ConsulterDisponibilites {
  const ConsulterDisponibilites(this._depot);

  final ReservationRepository _depot;

  Future<List<Disponibilite>> call(
    PeriodeSejour periode, {
    String? exclureReservationId,
  }) async {
    final resultats = await _depot.consulterDisponibilites(
      periode,
      exclureReservationId: exclureReservationId,
    );

    resultats.sort((a, b) {
      if (a.disponible != b.disponible) return a.disponible ? -1 : 1;
      final parTarif = a.unite.tarifBase.compareTo(b.unite.tarifBase);
      if (parTarif != 0) return parTarif;
      // Départage stable : sans lui, deux unités au même tarif changent
      // d'ordre à chaque rafraîchissement et la liste « bouge » sous le doigt.
      return a.unite.numero.compareTo(b.unite.numero);
    });

    return resultats;
  }
}
