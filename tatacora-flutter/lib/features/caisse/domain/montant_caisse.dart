/// Le montant saisi à la caisse — lu comme le SERVEUR le lit.
///
/// Le composant `PosComptant` valide `['required', 'numeric', 'min:0']`, stocke
/// la chaîne telle quelle dans une colonne `DECIMAL(15,2)` (MySQL ARRONDIT à la
/// seconde décimale), puis calcule l'écart avec `bcsub(…, 2)` (qui TRONQUE et
/// REFUSE ce qui n'est pas un nombre « bien formé »). Chaque étape a sa règle,
/// et elles ne coïncident pas — ce fichier les porte une par une, dans des
/// fonctions pures sur des ENTIERS (jamais un flottant), et chacune est
/// confrontée au vrai composant (`tool/caisse/rejouer_caisse.php`).
///
/// @see `PosComptant::ouvrirCaisse`, `PosComptant::cloturerCaisse`
library;

import '../../../core/format/formats.dart';

/// La plus grande valeur d'un `DECIMAL(15,2)`, en centimes : 9 999 999 999 999,99.
const int centimesMaxDecimal15x2 = 999999999999999;

/// `is_numeric` de PHP 8 : espaces de tête et de queue permis, signe optionnel,
/// partie entière et/ou décimale, exposant optionnel. Pas d'hexadécimal, pas de
/// séparateur de milliers, pas de virgule.
final RegExp _numerique = RegExp(
  r'^[ \t\n\r\v\f]*([+-]?)(\d+(?:\.\d*)?|\.\d+)(?:[eE]([+-]?\d+))?[ \t\n\r\v\f]*$',
);

/// Ce que `bcsub` accepte : signe optionnel, chiffres, un point, chiffres — rien
/// d'autre (ni espace, ni exposant). Mesuré par PHP 8.3 : `"5."`, `".5"`, `"+5"`
/// passent ; `" 5"`, `"5e1"`, `"--5"` lèvent `ValueError`.
final RegExp _bcBienForme = RegExp(r'^[+-]?\d*(?:\.\d*)?$');

/// Un nombre décimal EXACT : `mantisse × 10^-echelle`.
final class DecimalSaisi {
  const DecimalSaisi._(this._mantisse, this._echelle, this._brut);

  final BigInt _mantisse;

  /// Le nombre de décimales de [_mantisse] (peut être négatif : « 1e3 »).
  final int _echelle;

  final String _brut;

  /// Lit [brut] comme `is_numeric`. `null` si ce n'est pas un nombre.
  static DecimalSaisi? lire(String brut) {
    final m = _numerique.firstMatch(brut);
    if (m == null) return null;
    final signe = m.group(1) == '-' ? BigInt.from(-1) : BigInt.one;
    final corps = m.group(2)!;
    final point = corps.indexOf('.');
    final entiers = point < 0 ? corps : corps.substring(0, point);
    final fraction = point < 0 ? '' : corps.substring(point + 1);
    final chiffres = '$entiers$fraction';
    final exposant = int.tryParse(m.group(3) ?? '0');
    // Un exposant démesuré ne représente aucune somme d'argent : on le range
    // dans le même sac que le serveur (hors plage, ou zéro), sans bâtir un
    // entier de plusieurs milliers de chiffres.
    if (exposant == null || exposant.abs() > 400) {
      return DecimalSaisi._(
        BigInt.parse(chiffres.isEmpty ? '0' : chiffres) == BigInt.zero
            ? BigInt.zero
            : signe * BigInt.one,
        exposant == null || exposant > 0 ? -400 : 400,
        brut,
      );
    }
    return DecimalSaisi._(
      signe * BigInt.parse(chiffres.isEmpty ? '0' : chiffres),
      fraction.length - exposant,
      brut,
    );
  }

  /// Strictement négatif — `-0` ne l'est pas (`-0 >= 0` au serveur).
  bool get estNegatif => _mantisse < BigInt.zero;

  /// `gt:0` : la valeur EXACTE est strictement positive (`0`, `-0`, `0.000` et
  /// tout négatif sont refusés ; `0.004` passe — il est > 0 avant d'être
  /// tronqué par `bccomp` au service).
  bool get estStrictementPositif => _mantisse > BigInt.zero;

  /// `min:0` : la valeur EXACTE est positive ou nulle (`-0.001` est refusé,
  /// alors qu'il s'arrondirait à zéro).
  bool get respecteMinZero => !estNegatif;

  /// Le texte lu par `bcsub` serait-il refusé (`ValueError`, HTTP 500 au
  /// serveur) ? Vrai pour « 1e3 », « 1 000 » entouré d'espaces, « --5 ».
  bool get estBienFormePourBc => _bcBienForme.hasMatch(_brut);

  /// Les CENTIMES que MySQL stockerait dans un `DECIMAL(15,2)` : arrondi à
  /// l'écart maximal de la demi-unité, ÉLOIGNÉ de zéro (`0.005` -> `0.01`).
  /// `null` si la valeur sort de la plage de la colonne — le serveur lève alors
  /// une `QueryException` (« Out of range value ») et n'écrit rien.
  int? get centimesArrondis {
    // value × 100 = mantisse × 10^(2 - echelle)
    final decalage = 2 - _echelle;
    BigInt centimes;
    if (decalage >= 0) {
      if (decalage > 40) return _mantisse == BigInt.zero ? 0 : null;
      centimes = _mantisse * BigInt.from(10).pow(decalage);
    } else {
      final diviseur = decalage < -40 ? null : BigInt.from(10).pow(-decalage);
      if (diviseur == null) return 0;
      final absolu = _mantisse.abs();
      var q = absolu ~/ diviseur;
      if ((absolu % diviseur) * BigInt.two >= diviseur) q += BigInt.one;
      centimes = _mantisse.isNegative ? -q : q;
    }
    if (centimes.abs() > BigInt.from(centimesMaxDecimal15x2)) return null;
    return centimes.toInt();
  }

  /// `bcsub(constate, théorique, 2)` en CENTIMES : la différence EXACTE, puis
  /// TRONQUÉE vers zéro à la deuxième décimale (`0.999 - 1.00` -> `0.00`).
  ///
  /// Ce n'est PAS `centimesArrondis - théorique` : le serveur calcule l'écart
  /// sur la saisie brute, mais stocke la saisie ARRONDIE. Les deux divergent
  /// d'un centime sur une saisie à trois décimales — signalé, jamais corrigé.
  int ecartTronque(int theoriqueCentimes) {
    if (_echelle <= 2) {
      final centimes = _mantisse * BigInt.from(10).pow(2 - _echelle);
      return (centimes - BigInt.from(theoriqueCentimes)).toInt();
    }
    final facteur = BigInt.from(10).pow(_echelle);
    final difference =
        _mantisse * BigInt.from(100) - BigInt.from(theoriqueCentimes) * facteur;
    // `~/` sur BigInt TRONQUE vers zéro, comme `bcsub` à l'échelle 2.
    return (difference ~/ facteur).toInt();
  }
}

/// `MontantFcfa::format` : arrondi à l'unité (`bcadd(x, ±0.5, 0)`, soit la
/// demi-unité ÉLOIGNÉE de zéro), signe conservé, `-0` ramené à `0`, groupes de
/// trois chiffres, « FCFA ».
///
/// Écart assumé et nommé : le serveur sépare les groupes par l'insécable
/// U+00A0, le client Flutter par l'espace ordinaire de [formaterFcfa] — la
/// seule forme que tous ses écrans emploient. Le test de confrontation
/// normalise les deux avant de comparer.
String formaterCentimesEnFcfa(int centimes) {
  final absolu = centimes.abs();
  var unites = absolu ~/ 100;
  if (absolu % 100 >= 50) unites++;
  // `-0` ramené à `0` (` === '-0'` du serveur) : un entier n'a pas de zéro
  // négatif, `-1 * 0` vaut déjà `0` — la garde du serveur est donc portée par la
  // représentation, pas par une condition (une condition ici serait du code
  // mort que aucune mutation ne pourrait tuer).
  return formaterFcfa((centimes < 0 ? -1 : 1) * unites);
}
