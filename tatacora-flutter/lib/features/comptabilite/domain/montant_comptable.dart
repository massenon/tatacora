/// Le montant comptable du poste : des CENTIMES entiers.
///
/// Le serveur écrit `DECIMAL(15,2)` et calcule en `bcmath` (chaînes à deux
/// décimales). Ici, l'unité de calcul est le centime ENTIER : une addition
/// d'entiers est exacte, un flottant ne l'est pas (`0.1 + 0.2`). La conversion
/// avec la chaîne du serveur est EXPLICITE et se fait aux deux bornes
/// seulement — à l'entrée d'une saisie, à la sortie d'un message ou d'un état.
///
/// ## Ce que `bcadd($v, '0', 2)` fait, reproduit à l'identique
///
/// * il TRONQUE au-delà de la deuxième décimale, il n'arrondit pas :
///   `10.999` devient `10.99` ;
/// * il refuse une chaîne qui n'est pas un nombre (`ValueError` au serveur,
///   `FormatException` ici — le moteur la traduit en refus) ; il n'ôte AUCUN
///   espace (« 12.5 » entouré d'espaces est refusé) et lit la chaîne vide
///   comme zéro.
///
/// @see RG-11 — la précision des pièces validées ne bouge plus jamais.
library;

final RegExp _nombre = RegExp(r'^([+-]?)(\d+)(?:\.(\d*))?$|^([+-]?)\.(\d+)$');

/// Convertit une chaîne décimale en centimes, en TRONQUANT.
///
/// `"12500.00"` -> `1250000`, `"100.999"` -> `10099`, `"-3.5"` -> `-350`.
/// Lève [FormatException] sur toute chaîne qui n'est pas un nombre décimal.
int centimesDepuisChaine(String valeur) {
  // `bcadd('', '0', 2)` rend `0.00` : une chaîne vide est un zéro, pas un refus
  // (un champ de saisie laissé vide). Constaté par PHP, repris tel quel.
  if (valeur.isEmpty) return 0;
  final m = _nombre.firstMatch(valeur);
  if (m == null) {
    throw FormatException('Montant illisible : « $valeur ».', valeur);
  }
  final signe = (m.group(1) ?? m.group(4)) == '-' ? -1 : 1;
  final entiers = m.group(2) ?? '0';
  final decimales = (m.group(3) ?? m.group(5) ?? '');
  final deux = decimales.padRight(2, '0').substring(0, 2);
  final centimes = int.parse(entiers) * 100 + int.parse(deux);
  return signe * centimes;
}

/// La chaîne à DEUX décimales, comme `bcadd(.., '0', 2)` : `1250000` ->
/// `"12500.00"`, `-50` -> `"-0.50"`, `0` -> `"0.00"`.
String chaineDepuisCentimes(int centimes) {
  final negatif = centimes < 0;
  final absolu = centimes.abs();
  final entiers = absolu ~/ 100;
  final reste = (absolu % 100).toString().padLeft(2, '0');
  return '${negatif ? '-' : ''}$entiers.$reste';
}
