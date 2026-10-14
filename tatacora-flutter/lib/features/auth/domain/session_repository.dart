import 'session.dart';

/// Contrat de session — la couche presentation ne connait que lui.
///
/// L'implementation reelle (`SessionRepositoryImpl`) et le double de test
/// (`SessionRepositoryFake`) le satisfont indifferemment, ce qui permet de
/// developper les ecrans avant que le backend soit joignable.
abstract interface class SessionRepository {
  /// Retourne la session, ou leve `EchecConnexion` si les identifiants sont
  /// refuses.
  Future<Session> connecter(String identifiant, String motDePasse);

  Future<void> deconnecter();

  /// Session restauree au demarrage, `null` si aucun jeton valide n'est stocke.
  Future<Session?> sessionCourante();
}

/// Echec d'authentification, distinct d'une panne reseau.
///
/// Les confondre produirait le pire message possible : « identifiants
/// incorrects » alors que le serveur est simplement injoignable, ce qui pousse
/// l'utilisateur a ressaisir son mot de passe indefiniment.
final class EchecConnexion implements Exception {
  const EchecConnexion(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Le serveur est injoignable — l'utilisateur n'y peut rien.
final class ReseauIndisponible implements Exception {
  const ReseauIndisponible();
  @override
  String toString() => 'Serveur injoignable';
}
