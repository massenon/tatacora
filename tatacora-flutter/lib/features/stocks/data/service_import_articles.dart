/// Le moteur d'import d'articles du poste, PARTAGÉ par ses deux portes
/// d'entrée (demande du PO du 14/10/2026) :
///
///  * la modale « Importer des articles » de l'écran Stocks — lot ligne par
///    ligne, ligne fautive NOMMÉE et lot conservé (règle de l'écran M6) ;
///  * l'onglet « Importer les données » de l'écran Import & Export — aucun
///    import partiel, une transaction unique (règle de cet écran-là).
///
/// Les deux lisent une ligne par `lireLigneArticle` (domaine) et l'écrivent
/// par [enregistrerArticleImporte] : `StocksApi.enregistrerArticle`, ses
/// refus et sa transaction (article ET entrée d'ouverture). Ce sont les règles
/// de DEUX écrans distincts du serveur, pas une divergence à réconcilier.
library;

import '../domain/entities/mouvement_stock.dart';
import '../domain/import_articles.dart';
import 'stocks_api.dart';

/// Le refus d'une ligne quand l'écriture n'a pas pu avoir lieu sur ce poste.
const String articleNonEcrit = "L'article n'a pas pu être écrit sur ce poste.";

/// Écrit UNE ligne d'import par `StocksApi.enregistrerArticle` et traduit son
/// issue en [ResultatImportLigne].
Future<ResultatImportLigne> enregistrerArticleImporte(
  StocksApi api,
  SaisieArticle saisie,
) async {
  final r = await api.enregistrerArticle(saisie);
  return switch (r) {
    ArticleEnregistre() => const LigneImportee(),
    ArticleRefuse(:final motif) => LigneRefusee(motif),
    ArticleInjoignable() => const LigneRefusee(articleNonEcrit),
  };
}
