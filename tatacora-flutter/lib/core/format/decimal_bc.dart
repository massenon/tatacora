/// Un décimal à la manière de `bcmath` — pour répliquer, au centime près, un
/// calcul que le serveur fait en chaînes.
///
/// ## Pourquoi pas un `double`, ni un `int` de centimes partout
///
/// `bcmath` tronque (jamais n'arrondit) à l'échelle demandée, et le serveur
/// enchaîne parfois deux opérations à des échelles différentes
/// (`bcdiv(bcmul($a, $b, 4), '100', 2)`). Reproduire la troncature AU MÊME
/// ENDROIT est ce qui donne le même centime ; un flottant donnerait parfois un
/// centime de moins, sur une pièce immuable. La valeur est un entier [unites] et
/// une [echelle] (nombre de décimales) : `12.50` = 1250 à l'échelle 2.
///
/// Ce n'est PAS une bibliothèque décimale générale : seulement ce que la
/// réplique d'un calcul serveur exige, et chaque opération dit quelle fonction
/// `bcmath` elle copie.
library;

final class DecimalBc implements Comparable<DecimalBc> {
  const DecimalBc(this.unites, this.echelle);

  /// Entier à l'échelle [echelle] : la valeur est `unites / 10^echelle`.
  final BigInt unites;
  final int echelle;

  static final RegExp _simple = RegExp(r'^-?\d+(\.\d+)?$');

  /// `null` sur toute entrée qui n'est pas « [-]chiffres[.chiffres] » — jamais
  /// zéro : une saisie illisible n'est pas une saisie nulle. (Le serveur lève
  /// ici une `ValueError` de `bcmath`.)
  static DecimalBc? lire(String texte) {
    if (!_simple.hasMatch(texte)) return null;
    final negatif = texte.startsWith('-');
    final corps = negatif ? texte.substring(1) : texte;
    final point = corps.indexOf('.');
    final decimales = point < 0 ? 0 : corps.length - point - 1;
    final brut = BigInt.parse(corps.replaceAll('.', ''));
    return DecimalBc(negatif ? -brut : brut, decimales);
  }

  /// Un entier de [centimes] : à l'échelle 2.
  factory DecimalBc.centimes(int centimes) =>
      DecimalBc(BigInt.from(centimes), 2);

  static BigInt _dix(int p) => BigInt.from(10).pow(p);

  /// Même valeur, exprimée à l'échelle [e] — PAR TRONCATURE vers zéro quand on
  /// réduit (`bcadd($x, '0', $e)`), exacte quand on agrandit.
  DecimalBc versEchelle(int e) {
    if (e == echelle) return this;
    if (e > echelle) return DecimalBc(unites * _dix(e - echelle), e);
    // `~/` tronque vers zéro, comme bcmath.
    return DecimalBc(unites ~/ _dix(echelle - e), e);
  }

  /// `bcmul($a, $b, $e)` : le produit exact, tronqué à l'échelle [e].
  DecimalBc fois(DecimalBc autre, int e) =>
      DecimalBc(unites * autre.unites, echelle + autre.echelle).versEchelle(e);

  /// `bcdiv($a, $b, $e)` : le quotient, tronqué à l'échelle [e].
  DecimalBc divise(DecimalBc autre, int e) {
    // (u1/10^e1) / (u2/10^e2) à l'échelle e  =>  u1 * 10^(e + e2 - e1) / u2.
    final decalage = e + autre.echelle - echelle;
    final numerateur = decalage >= 0
        ? unites * _dix(decalage)
        : unites ~/ _dix(-decalage);
    return DecimalBc(numerateur ~/ autre.unites, e);
  }

  /// `bcsub($a, $b, $e)` : la différence, tronquée à l'échelle [e].
  DecimalBc moins(DecimalBc autre, int e) {
    final commune = echelle > autre.echelle ? echelle : autre.echelle;
    final a = versEchelle(commune).unites;
    final b = autre.versEchelle(commune).unites;
    return DecimalBc(a - b, commune).versEchelle(e);
  }

  /// `bccomp($a, $b, $e)` : comparaison APRÈS troncature des deux à l'échelle
  /// [e] — `bccomp('-0.001', '0', 2)` vaut 0.
  int compare(DecimalBc autre, int e) =>
      versEchelle(e).unites.compareTo(autre.versEchelle(e).unites);

  @override
  int compareTo(DecimalBc autre) {
    final commune = echelle > autre.echelle ? echelle : autre.echelle;
    return versEchelle(
      commune,
    ).unites.compareTo(autre.versEchelle(commune).unites);
  }

  bool get estNegatif => unites.isNegative;

  /// Le texte à l'échelle de la valeur, comme `bcmath` le rend (`"12.50"`,
  /// `"0.00"`).
  @override
  String toString() {
    if (echelle == 0) return unites.toString();
    final negatif = unites.isNegative;
    var chiffres = unites.abs().toString().padLeft(echelle + 1, '0');
    final entier = chiffres.substring(0, chiffres.length - echelle);
    final decimales = chiffres.substring(chiffres.length - echelle);
    chiffres = '$entier.$decimales';
    return negatif ? '-$chiffres' : chiffres;
  }
}
