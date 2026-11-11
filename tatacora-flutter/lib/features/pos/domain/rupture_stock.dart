// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
/// La RUPTURE que la vente constaterait, dite AVANT d'encaisser (RG-06).
///
/// ## Ce que fait le serveur, et ce que le poste en rejoue
///
/// `VenteService::deduireStock` sort, pour chaque ligne du bar, `quantité ÷
/// unités vendables par unité de stock` du stock du point « bar ». Quand le
/// stock disponible est INFÉRIEUR à la sortie, `MouvementStockService::sortie`
/// lève `RuptureStockException` — « Stock insuffisant : 12.00 disponible, 24.00
/// demandé. Une validation explicite est requise pour forcer la sortie. » — et
/// `PosComptant` ouvre la modale « Stock insuffisant » : l'opérateur habilité
/// choisit « Vendre quand même », le panier restant intact entre-temps.
///
/// Ce poste n'écrit AUCUNE sortie de stock (RG-05, D240) : le serveur sort le
/// stock à la RÉCEPTION de la vente, et ses sorties redescendent. La rupture est
/// donc ESTIMÉE ici avec ce que le poste sait : le stock au point « bar » de ses
/// mouvements, moins ce que les ventes encore en file sortiront
/// (`StockEnAttente`), moins ce que les lignes précédentes de CE panier
/// sortent déjà.
///
/// ## Ce qui n'est pas estimé, et le dit
///
///  - une boisson sans article de stock, ou sans facteur de conditionnement
///    reçu : aucune sortie n'est calculable (jamais un 1 inventé) ;
///  - un article journalier : son stock n'est pas tenu ;
///  - les plats (M4) : leur déduction passe par la cuisine, que ce poste ne tient
///    pas ;
///  - **si aucun point de stockage de type « bar » n'existe** : aucune estimation
///    n'est produite (le serveur, lui, refuserait : « Aucun point de stockage de
///    type « bar » n'est défini »).
///
/// La question n'est jamais un blocage : « Vendre quand même » est toujours
/// offert, parce que le serveur FORCE de toute façon une vente déjà faite et la
/// signale (`vente_en_rupture`) — la rejeter ferait disparaître l'argent des
/// livres.
library;

import '../../stocks/domain/stock_en_attente.dart';

/// La première ligne dont la sortie dépasse le stock disponible.
final class RuptureConstatee {
  const RuptureConstatee({
    required this.articleId,
    required this.disponibleCentiemes,
    required this.demandeCentiemes,
  });

  /// L'article de stock en rupture (identifiant local).
  final String articleId;

  /// Le stock restant au point « bar », en centièmes — négatif si les ventes en
  /// attente l'ont déjà dépassé.
  final int disponibleCentiemes;

  /// La sortie que la ligne demande, en centièmes.
  final int demandeCentiemes;

  /// `12.00` — la forme du serveur (`bcmath` à deux décimales).
  static String _decimal(int centiemes) {
    final negatif = centiemes < 0;
    final a = centiemes.abs();
    return '${negatif ? '-' : ''}${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
  }

  /// `stocks.rupture`, au mot.
  String get message =>
      'Stock insuffisant : ${_decimal(disponibleCentiemes)} disponible, '
      '${_decimal(demandeCentiemes)} demandé. Une validation explicite est '
      'requise pour forcer la sortie.';
}

/// Constate la rupture d'un panier au comptant.
///
/// [lignes] : les lignes du BAR, dans l'ordre du panier (boisson locale,
/// quantité vendue). [boissons] : identifiant local de la boisson → (article
/// local, facteur texte). [stockCentiemes] : article local → stock au point
/// « bar », en centièmes ; un article absent de la table n'est PAS estimé.
/// [enAttente] : ce que les ventes en file sortiront.
RuptureConstatee? constaterRupture({
  required Iterable<({String boissonId, int quantite})> lignes,
  required Map<String, ({String articleId, String? facteur})> boissons,
  required Map<String, int> stockCentiemes,
  required StockEnAttente enAttente,
}) {
  // Ce que les lignes précédentes de CE panier ont déjà demandé, par article :
  // le serveur sort ligne après ligne, la seconde voit le stock de la première.
  final dejaDemande = <String, int>{};

  for (final l in lignes) {
    final b = boissons[l.boissonId];
    if (b == null || b.articleId.isEmpty || l.quantite <= 0) continue;
    final facteur = facteurEnDixMilliemes(b.facteur);
    if (facteur == null) continue;
    final stock = stockCentiemes[b.articleId];
    if (stock == null) continue;

    final demande = stockSortiEnCentiemes(
      quantiteVendue: l.quantite,
      facteur: facteur,
    );
    final disponible =
        stock - enAttente.pour(b.articleId) - (dejaDemande[b.articleId] ?? 0);
    if (disponible < demande) {
      return RuptureConstatee(
        articleId: b.articleId,
        disponibleCentiemes: disponible,
        demandeCentiemes: demande,
      );
    }
    dejaDemande[b.articleId] = (dejaDemande[b.articleId] ?? 0) + demande;
  }
  return null;
}
