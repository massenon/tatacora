import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/rupture_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/stock_en_attente.dart';

/// La rupture que le comptoir DIT avant d'encaisser (`stocks.rupture`) : ce
/// qu'elle estime, et ce qu'elle refuse d'inventer.
void main() {
  const boissons = {'b-1': (articleId: 'a-1', facteur: '24')};

  test('48 bouteilles sortent 2,00 casiers : 1,00 disponible, rupture dite '
      'aux mots du serveur', () {
    final r = constaterRupture(
      lignes: [(boissonId: 'b-1', quantite: 48)],
      boissons: boissons,
      stockCentiemes: const {'a-1': 100},
      enAttente: StockEnAttente.vide,
    );
    expect(r, isNotNull);
    expect(
      r!.message,
      'Stock insuffisant : 1.00 disponible, 2.00 demandé. Une validation '
      'explicite est requise pour forcer la sortie.',
    );
  });

  test('assez de stock : aucune rupture', () {
    expect(
      constaterRupture(
        lignes: [(boissonId: 'b-1', quantite: 24)],
        boissons: boissons,
        stockCentiemes: const {'a-1': 100},
        enAttente: StockEnAttente.vide,
      ),
      isNull,
    );
  });

  test('les ventes déjà en file et les lignes précédentes du panier '
      'comptent', () {
    // 1,00 en stock, 0,50 déjà en file : 24 bouteilles (1,00) dépassent.
    expect(
      constaterRupture(
        lignes: [(boissonId: 'b-1', quantite: 24)],
        boissons: boissons,
        stockCentiemes: const {'a-1': 100},
        enAttente: const StockEnAttente(
          parArticle: {'a-1': 50},
          nonConvertibles: 0,
        ),
      )?.disponibleCentiemes,
      50,
    );
    // Deux lignes de 12 bouteilles (0,50 chacune) : la seconde voit la première.
    expect(
      constaterRupture(
        lignes: [
          (boissonId: 'b-1', quantite: 12),
          (boissonId: 'b-1', quantite: 18),
        ],
        boissons: boissons,
        stockCentiemes: const {'a-1': 100},
        enAttente: StockEnAttente.vide,
      ),
      isNotNull,
    );
  });

  test('sans facteur reçu, sans article ou sans stock lu : JAMAIS un 1 '
      'inventé, aucune rupture estimée', () {
    for (final b in [
      const {'b-1': (articleId: 'a-1', facteur: null)},
      const {'b-1': (articleId: '', facteur: '24')},
    ]) {
      expect(
        constaterRupture(
          lignes: [(boissonId: 'b-1', quantite: 999)],
          boissons: b,
          stockCentiemes: const {'a-1': 0},
          enAttente: StockEnAttente.vide,
        ),
        isNull,
      );
    }
    expect(
      constaterRupture(
        lignes: [(boissonId: 'b-1', quantite: 999)],
        boissons: boissons,
        stockCentiemes: const {},
        enAttente: StockEnAttente.vide,
      ),
      isNull,
    );
  });
}
