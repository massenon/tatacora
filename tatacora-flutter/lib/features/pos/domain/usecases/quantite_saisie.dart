/// Lecture d'une quantité saisie au clavier — **le piège déjà rencontré**.
///
/// ## L'incident, et sa forme exacte
///
/// Le prototype écrivait `Number(quantite) || 1`. En JavaScript, `0 || 1` vaut
/// `1` : une quantité **saisie à zéro** se facturait donc à **une unité**, sans
/// que rien ne le signale. Le défaut a été trouvé en éprouvant le moteur
/// (PA-78) et il est figé par une assertion de `t-panier.js`.
///
/// ## Pourquoi Dart ne le résout pas tout seul
///
/// `int.tryParse('')` rend `null`, et `int.tryParse('0')` rend `0`. Le langage
/// **distingue** donc les deux cas — mais seulement si le code les distingue à
/// son tour. Écrire `int.tryParse(texte) ?? 1` reproduirait exactement le
/// défaut d'origine dans une syntaxe différente : un champ vide vaudrait 1, un
/// zéro aussi.
///
/// Trois situations, trois réponses :
///
///  | Saisie | Interprétation | Réponse |
///  |---|---|---|
///  | champ vide, ou `null` | quantité **non précisée** | 1, la valeur d'usage |
///  | `0`, `-2` | quantité **précisée**, et invalide | refus explicite |
///  | `abc` | saisie **illisible** | refus explicite |
///
/// La deuxième ligne est celle qui compte : « absente » et « zéro » ne sont pas
/// la même chose, et la seule qui puisse se facturer à 1 est la première.
library;

/// Ce qu'une saisie de quantité vaut, une fois lue.
sealed class QuantiteSaisie {
  const QuantiteSaisie();

  /// Lit une saisie de champ texte.
  ///
  /// [texte] à `null` ou vide (espaces compris) signifie « non précisée ».
  factory QuantiteSaisie.depuisTexte(String? texte) {
    final net = texte?.trim() ?? '';
    if (net.isEmpty) return const QuantiteAbsente();

    final valeur = int.tryParse(net);
    if (valeur == null) {
      return QuantiteRefusee(
        saisie: net,
        motif: '« $net » n’est pas un nombre entier.',
      );
    }
    if (valeur <= 0) {
      // Le message dit ce qui a été lu : « la quantité doit être positive »
      // laisserait croire à un champ vide alors qu'un zéro a bien été frappé.
      return QuantiteRefusee(
        saisie: net,
        motif:
            'Quantité saisie à $valeur. Une quantité nulle ou négative ne se '
            'facture pas — retirez la ligne si l’article n’a pas été servi.',
      );
    }
    return QuantiteValide(valeur);
  }
}

/// Le champ est vide : la quantité vaut 1, la valeur d'usage au comptoir.
final class QuantiteAbsente extends QuantiteSaisie {
  const QuantiteAbsente();

  int get valeur => 1;
}

final class QuantiteValide extends QuantiteSaisie {
  const QuantiteValide(this.valeur);
  final int valeur;
}

/// Une quantité a bien été saisie, et elle n'est pas facturable.
final class QuantiteRefusee extends QuantiteSaisie {
  const QuantiteRefusee({required this.saisie, required this.motif});

  final String saisie;
  final String motif;
}
