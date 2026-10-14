import 'entities/parametre.dart';

/// Ce que la consultation des paramètres peut rendre.
///
/// Il n'y a PLUS d'issue « injoignable » : la source est locale (09/10/2026),
/// il n'y a aucun serveur à joindre. Garder la branche aurait laissé un écran
/// dire « hors connexion » d'une base qui est sur le disque, et renvoyé
/// l'exploitant vérifier un routeur sans rapport (PA-59/60/61).
sealed class ResultatParametres {
  const ResultatParametres();
}

final class ParametresRecus extends ResultatParametres {
  const ParametresRecus(this.parametres);
  final Parametres parametres;
}

/// La lecture est refusée : droit absent ou base illisible. Le [motif] est
/// affiché tel quel.
final class ParametresRefuses extends ResultatParametres {
  const ParametresRefuses({required this.motif});
  final String motif;
}

/// Ce qu'un enregistrement peut rendre.
sealed class ResultatEcriture {
  const ResultatEcriture();
}

final class EcritureAcceptee extends ResultatEcriture {
  const EcritureAcceptee({required this.message, required this.modifiees});
  final String message;
  final List<String> modifiees;
}

/// L'enregistrement est refusé, et RIEN n'est écrit.
///
/// Deux formes de refus coexistent et l'écran a besoin des deux : une erreur
/// de forme est rattachée à son champ ([parCle]), la garde de cohérence rend un
/// message global ([motif]). Les fondre en une chaîne perdrait le champ fautif.
final class EcritureRefusee extends ResultatEcriture {
  const EcritureRefusee({required this.motif, this.parCle = const {}});
  final String motif;
  final Map<String, String> parCle;
}
