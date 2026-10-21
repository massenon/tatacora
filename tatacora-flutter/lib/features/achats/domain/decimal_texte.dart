/// Arithmétique décimale **sur des chaînes**, à deux décimales exactement.
///
/// ## Pourquoi pas `double`
///
/// M7 manipule des quantités et des montants qui viennent du serveur en
/// `DECIMAL(15,2)` sérialisé. Les convertir en `double` pour les soustraire
/// puis les réafficher les réarrondirait, et l'écran dirait un autre chiffre
/// que le bon de commande remis au Gérant — c'est la règle du projet depuis
/// PA-55, et c'est aussi pourquoi le serveur, lui, ne calcule qu'avec `bcsub`
/// et `bccomp`.
///
/// Ce fichier est donc le pendant Dart de `bcsub`/`bccomp`/`bcmul` : il
/// travaille en **centièmes entiers**, jamais en flottant. `0.1 + 0.2` vaut
/// exactement `0.30` ici, et `Math.ceil(4.999999999)` ne peut pas survenir.
///
/// ## Ce qu'il ne fait pas
///
/// Il ne **divise** pas. Aucun écran de M7 n'a besoin d'une division, et une
/// division décimale exige de trancher un mode d'arrondi — décision qui ne se
/// prend pas au détour d'un utilitaire.
///
/// `null` est rendu sur toute entrée illisible, **jamais zéro** : un champ
/// absent du serveur n'est pas un champ qui vaut zéro, et les confondre
/// afficherait « manque 0 » sur un article dont on ignore le stock.
library;

/// Deux décimales : la précision du schéma (`decimal:0,2` côté serveur).
const int _echelle = 100;

final RegExp _forme = RegExp(r'^-?\d+(\.\d{1,2})?$');

/// Le nombre [brut] en centièmes entiers, ou `null` s'il n'a pas la forme
/// attendue.
///
/// Accepte la virgule décimale : au Gîte on tape « 12,5 ». La refuser
/// localement serait refuser une écriture correcte en français.
int? enCentiemes(String brut) {
  final texte = brut.trim().replaceAll(',', '.');
  if (!_forme.hasMatch(texte)) return null;

  final negatif = texte.startsWith('-');
  final absolu = negatif ? texte.substring(1) : texte;
  final point = absolu.indexOf('.');

  final entiere = point < 0 ? absolu : absolu.substring(0, point);
  final decimale = point < 0 ? '' : absolu.substring(point + 1);

  final unites = int.tryParse(entiere);
  if (unites == null) return null;

  // `padRight` et non `padLeft` : « 12.5 » vaut 12,50 — cinquante centièmes,
  // pas cinq. L'inverse diviserait la quantité par dix, en silence.
  final centiemes = int.tryParse(decimale.padRight(2, '0'));
  if (centiemes == null) return null;

  final total = unites * _echelle + centiemes;
  return negatif ? -total : total;
}

/// La forme d'affichage d'un nombre de centièmes : toujours deux décimales.
///
/// Toujours deux, y compris sur un entier : c'est la forme que le serveur
/// renvoie (`'4.00'`), et deux écritures d'un même chiffre sur le même écran
/// font douter de celui qu'on lit.
String depuisCentiemes(int centiemes) {
  final negatif = centiemes < 0;
  final absolu = negatif ? -centiemes : centiemes;
  final unites = absolu ~/ _echelle;
  final reste = absolu % _echelle;

  return '${negatif ? '-' : ''}$unites.${reste.toString().padLeft(2, '0')}';
}

/// Le coût [brut] (« 833.3333 ») arrondi au centième SUPÉRIEUR OU ÉGAL à la
/// demi-unité (demi vers le haut), ou `null` s'il est illisible ou s'arrondit à
/// zéro. Calculé sur les chiffres de la chaîne, jamais par un `double`.
///
/// Sert au prix unitaire PRÉ-REMPLI d'un bon de commande : le serveur y pose
/// le coût moyen pondéré tel quel, et la ligne de commande ne porte que deux
/// décimales.
String? arrondirAuCentieme(String brut) {
  final texte = brut.trim();
  final m = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(texte);
  if (m == null) return null;

  final unites = int.tryParse(m.group(1)!);
  if (unites == null) return null;
  final decimales = (m.group(2) ?? '').padRight(3, '0');
  var centiemes = unites * _echelle + int.parse(decimales.substring(0, 2));
  if (int.parse(decimales[2]) >= 5) centiemes += 1;

  return centiemes <= 0 ? null : depuisCentiemes(centiemes);
}

/// `a - b`, ou `null` si l'un des deux est illisible.
String? soustraire(String a, String b) {
  final ca = enCentiemes(a);
  final cb = enCentiemes(b);
  if (ca == null || cb == null) return null;

  return depuisCentiemes(ca - cb);
}

/// `a + b`, ou `null` si l'un des deux est illisible.
String? additionner(String a, String b) {
  final ca = enCentiemes(a);
  final cb = enCentiemes(b);
  if (ca == null || cb == null) return null;

  return depuisCentiemes(ca + cb);
}

/// `a * b`, ou `null` si l'un des deux est illisible.
///
/// Le produit est ramené à deux décimales par **troncature**, comme
/// `bcmul($a, $b, 2)` côté serveur. Arrondir au plus proche ici ferait diverger
/// le montant affiché de celui que `LigneCommandeAchat::montant()` calcule, sur
/// la ligne d'un bon de commande.
String? multiplier(String a, String b) {
  final ca = enCentiemes(a);
  final cb = enCentiemes(b);
  if (ca == null || cb == null) return null;

  // Produit en dix-millièmes, ramené aux centièmes.
  final produit = ca * cb;
  final negatif = produit < 0;
  final absolu = (negatif ? -produit : produit) ~/ _echelle;

  return depuisCentiemes(negatif ? -absolu : absolu);
}

/// `-1`, `0` ou `1` — le `bccomp` du serveur. `null` si l'un est illisible.
int? comparer(String a, String b) {
  final ca = enCentiemes(a);
  final cb = enCentiemes(b);
  if (ca == null || cb == null) return null;

  return ca.compareTo(cb);
}

/// Vrai si [brut] est lisible et strictement positif.
bool estStrictementPositif(String brut) {
  final c = enCentiemes(brut);
  return c != null && c > 0;
}

/// La quantité à commander suggérée par le maître —
/// `m7-approvisionnement.html` l.219.
///
/// `Math.max(1, Math.ceil(seuil * 2 - stock))`. Le maître écrit lui-même la
/// raison du double (l.216-218) : *« remonter au double du seuil, pas au seuil
/// pile — recommander à l'exact ferait repasser sous alerte à la première
/// sortie »*.
///
/// Rendue en **unités entières**, jamais en centièmes : on ne commande pas un
/// demi-sac de riz, et l'arrondi au supérieur est celui du maître.
///
/// `null` quand l'un des deux chiffres est illisible — l'écran laisse alors le
/// champ vide plutôt que d'y poser un « 1 » qui passerait pour une mesure.
String? quantiteSuggeree({required String seuilAlerte, required String stock}) {
  final seuil = enCentiemes(seuilAlerte);
  final courant = enCentiemes(stock);
  if (seuil == null || courant == null) return null;

  final manque = seuil * 2 - courant;
  // Plafond entier : `(n + 99) ~/ 100` sur un positif. Sur un négatif ou nul,
  // le plancher de 1 s'applique de toute façon.
  final unites = manque <= 0 ? 0 : (manque + _echelle - 1) ~/ _echelle;

  return (unites < 1 ? 1 : unites).toString();
}
