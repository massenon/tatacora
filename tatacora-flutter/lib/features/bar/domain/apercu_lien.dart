/// L'aperçu de « Lier au stock » — ce que chaque vente retirera du stock, et
/// ce que le stock actuel représente en unités vendables.
///
/// Transcription de `EcranDeCarte::apercuDuLien()` et `unitesVendables()`
/// (PWA), qui calculent en `bcmul`/`bcdiv` : **aucun flottant**. En `double`,
/// 0,29 × 100 vaut 28,999…, que la troncature rend 28 — une bouteille de
/// moins, affichée sur l'écran où l'on décide d'une commande. Les nombres
/// sont donc lus en entiers mis à l'échelle du dix-millième, la précision de
/// la colonne (`decimal:4`).
///
/// Ces valeurs sont AFFICHÉES, jamais soumises : le serveur recalcule tout à
/// la vente (règle projet — une valeur calculable est en lecture seule).
///
/// @see RG-05 Sortie de stock automatique
library;

/// L'échelle de la colonne `unites_vendables_par_unite_stock`.
const int _echelle = 4;
final BigInt _unite = BigInt.from(10).pow(_echelle);

/// Un nombre décimal lu en dix-millièmes, ou `null` s'il n'est pas lisible.
///
/// Les chiffres au-delà du quatrième décimal sont TRONQUÉS, comme `bcmath`
/// sous l'échelle 4. La virgule est acceptée : c'est celle qu'on tape au
/// Bénin.
BigInt? lireDecimal(String brut) {
  final texte = brut.trim().replaceAll(',', '.');
  final forme = RegExp(r'^(-?)(\d*)(?:\.(\d*))?$').firstMatch(texte);
  if (forme == null) return null;

  final entiere = forme.group(2) ?? '';
  final decimale = forme.group(3) ?? '';
  if (entiere.isEmpty && decimale.isEmpty) return null;

  final fraction =
      (decimale.length > _echelle ? decimale.substring(0, _echelle) : decimale)
          .padRight(_echelle, '0');
  final valeur = BigInt.parse('${entiere.isEmpty ? '0' : entiere}$fraction');
  return forme.group(1) == '-' ? -valeur : valeur;
}

/// Un nombre en dix-millièmes, rendu sans zéros de fin — « 24 », « 0.0417 ».
///
/// La PWA écrit `rtrim(rtrim($x, '0'), '.')` sur la sortie de `bcdiv` : le
/// POINT décimal est celui de la vue, et il est gardé (ce qui se voit suit la
/// vue, PA-182).
String ecrireDecimal(BigInt valeur) {
  final negatif = valeur.isNegative;
  final absolu = valeur.abs();
  final entiere = absolu ~/ _unite;
  var fraction = (absolu % _unite).toString().padLeft(_echelle, '0');
  fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
  final corps = fraction.isEmpty ? '$entiere' : '$entiere.$fraction';
  return negatif ? '-$corps' : corps;
}

/// Ce que chaque vente retirera du stock : `1 / conditionnement`, au
/// dix-millième, tronqué — `bcdiv('1', $conversion, 4)`.
///
/// `null` quand le conditionnement n'est pas exploitable (vide, illisible,
/// nul ou négatif) : la PWA ne montre alors AUCUN aperçu, et un aperçu bâti
/// sur 1 laisserait croire qu'un champ vide vaut « une pour une ».
BigInt? decrementParVente(String conditionnement) {
  final c = lireDecimal(conditionnement);
  if (c == null || c <= BigInt.zero) return null;
  // (1 × 10⁴) × 10⁴ / (c × 10⁴) = 10⁴ / c, en dix-millièmes.
  return (_unite * _unite) ~/ c;
}

/// Le stock exprimé en unités VENDABLES — `bcmul($solde, $conversion, 0)` :
/// « il reste 47 bouteilles », pas « 1,96 casier ». Tronqué vers zéro.
///
/// `null` si l'un des deux n'est pas lisible, ou si le conditionnement n'est
/// pas strictement positif.
BigInt? unitesVendables({
  required String solde,
  required String conditionnement,
}) {
  final s = lireDecimal(solde);
  final c = lireDecimal(conditionnement);
  if (s == null || c == null || c <= BigInt.zero) return null;
  // (s × 10⁴)(c × 10⁴) / 10⁸ — `~/` tronque vers zéro, comme bcmath.
  return (s * c) ~/ (_unite * _unite);
}

/// Le conditionnement d'un lien, en clair — « 24 par casier » se lit bien,
/// « 1/24 de casier » se lit mal. Transcription de
/// `StockDeCarteService::conversionLisible()` (`carte_pwa.commun.
/// conversion_par_unite` / `conversion_par_vente`), en dix-millièmes comme le
/// reste de ce fichier : aucun flottant.
///
/// `null` quand [conversion] n'est pas un nombre strictement positif : une
/// phrase bâtie sur un conditionnement illisible serait un conditionnement
/// inventé.
String? conversionLisible(String conversion, String unite) {
  final c = lireDecimal(conversion);
  if (c == null || c <= BigInt.zero) return null;
  if (c > _unite) return '${ecrireDecimal(c)} par $unite';
  if (c == _unite) return '1 $unite par vente';
  // Moins d'une unité vendable par unité de stock : une vente en consomme
  // plusieurs — le maître rend alors `1 / quantité`.
  return '${ecrireDecimal(decrementParVente(conversion)!)} $unite par vente';
}
