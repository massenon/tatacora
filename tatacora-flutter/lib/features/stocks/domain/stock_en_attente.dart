/// Le stock QUE LES VENTES EN FILE VONT SORTIR (RG-05, 21/10/2026).
///
/// Le serveur sort le stock d'une vente quand il la REÇOIT ; ces sorties
/// redescendent ensuite à tous les postes, celui qui a vendu compris, et le
/// stock du poste est recalculé des mouvements. Entre la vente et cette
/// descente — hors ligne, par exemple — le stock affiché est trop haut.
///
/// Ce fichier calcule ce que les ventes encore en file sortiront, pour le DIRE
/// à côté du stock (« −X en attente d'envoi »). Rien n'est ÉCRIT : un
/// mouvement local serait compté deux fois à la synchronisation (le sien, puis
/// celui du serveur). La mention disparaît d'elle-même quand la vente part.
///
/// Même calcul que `CarteBoisson::stockConsommePour` puis
/// `MouvementStockService::arrondirQuantite` : la quantité vendue divisée par
/// les unités vendables par unité de stock, au dix-millième (troncature), puis
/// arrondie au centième (demi vers le haut). Des entiers, aucun `double`.
library;

const int _echelleFacteur = 10000;

/// Le facteur texte (`24.0000`) en dix-millièmes, `null` s'il est absent,
/// illisible ou nul — une boisson sans facteur n'est PAS estimée (jamais un 1
/// inventé).
int? facteurEnDixMilliemes(String? texte) {
  if (texte == null) return null;
  final m = RegExp(r'^(\d+)(?:\.(\d{1,4}))?\d*$').firstMatch(texte.trim());
  if (m == null) return null;
  final entiere = int.parse(m.group(1)!);
  final decimale = (m.group(2) ?? '').padRight(4, '0');
  final valeur = entiere * _echelleFacteur + int.parse(decimale);
  return valeur > 0 ? valeur : null;
}

/// La quantité de STOCK, en CENTIÈMES, que [quantiteVendue] unités vendues
/// sortent, pour un facteur en dix-millièmes ([facteur]).
int stockSortiEnCentiemes({required int quantiteVendue, required int facteur}) {
  // vendue / unités, au dix-millième, tronqué : vendue * 1e4 * 1e4 / facteur.
  final q4 = (quantiteVendue * _echelleFacteur * _echelleFacteur) ~/ facteur;
  // Arrondi au centième, demi vers le haut.
  return (q4 + 50) ~/ 100;
}

/// Ce que les ventes en file sortiront, par article de stock, plus le nombre
/// de lignes qu'on n'a pas pu convertir (facteur absent).
final class StockEnAttente {
  const StockEnAttente({
    required this.parArticle,
    required this.nonConvertibles,
  });

  /// L'identifiant LOCAL de l'article -> centièmes à sortir.
  final Map<String, int> parArticle;

  /// Lignes de boisson dont le facteur n'est pas encore reçu : non estimées.
  final int nonConvertibles;

  static const vide = StockEnAttente(parArticle: {}, nonConvertibles: 0);

  int pour(String articleId) => parArticle[articleId] ?? 0;
}

/// Agrège les lignes [ventes] (boisson locale, quantité vendue) en file.
///
/// [boissons] : identifiant local de la boisson -> (article local, facteur
/// texte). Une boisson sans lien de stock (article vide) ne sort rien.
StockEnAttente agregerStockEnAttente({
  required Iterable<({String boissonId, int quantite})> ventes,
  required Map<String, ({String articleId, String? facteur})> boissons,
}) {
  final parArticle = <String, int>{};
  var nonConvertibles = 0;
  for (final v in ventes) {
    final b = boissons[v.boissonId];
    if (b == null || b.articleId.isEmpty || v.quantite <= 0) continue;
    final facteur = facteurEnDixMilliemes(b.facteur);
    if (facteur == null) {
      nonConvertibles++;
      continue;
    }
    final sortie = stockSortiEnCentiemes(
      quantiteVendue: v.quantite,
      facteur: facteur,
    );
    parArticle[b.articleId] = (parArticle[b.articleId] ?? 0) + sortie;
  }
  return StockEnAttente(
    parArticle: parArticle,
    nonConvertibles: nonConvertibles,
  );
}

/// Les mots affichés — ajout propre au poste (la vue n'a pas de file d'envoi).
abstract final class TextesStockEnAttente {
  /// « −2,50 en attente d'envoi ».
  static String sortie(int centiemes) {
    final entier = centiemes ~/ 100;
    final dec = (centiemes % 100).toString().padLeft(2, '0');
    return "−$entier,$dec en attente d'envoi";
  }
}
