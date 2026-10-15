import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/achats/presentation/providers_achats.dart';
import 'package:tatacora_flutter/features/achats/presentation/widgets/vue_besoins.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

/// Les BESOINS de M7 (articles sous leur seuil) : le coût moyen pondéré d'un
/// article sans entrée valorisée est INCONNU, il s'exporte « — » et jamais
/// « 0.0000 » (D130). La liste exportée est construite par la vue ellemême
/// (`construireListe`), celle que le bouton d'export de la page appelle.
void main() {
  EtatStock etat() {
    MouvementCalcul mv(int ordre, String article, int q, {int? cout}) =>
        MouvementCalcul(
          id: 'm$ordre',
          articleId: article,
          pointId: 'magasin',
          type: TypeMouvement.entree,
          centiemes: q,
          ordre: ordre,
          date: DateTime(2026, 10, 8),
          coutDixMilliemes: cout,
        );
    // Les deux sont SOUS leur seuil (3,00 <= 5,00). Le riz a un coût, le sel non.
    return calculerEtat(
      articles: const [
        ArticleCalcul(
          id: 'riz',
          libelle: 'Riz',
          categorie: null,
          uniteMesure: 'sac',
          seuilCentiemes: 500,
          suivi: SuiviArticle.permanent,
        ),
        ArticleCalcul(
          id: 'sel',
          libelle: 'Sel',
          categorie: null,
          uniteMesure: 'sac',
          seuilCentiemes: 500,
          suivi: SuiviArticle.permanent,
        ),
      ],
      mouvements: [mv(1, 'riz', 300, cout: 12505000), mv(2, 'sel', 300)],
      maintenant: DateTime(2026, 10, 9),
      libellesPoints: const {},
      filtre: EtatStockFiltre.sousSeuil,
    );
  }

  testWidgets('l’export des besoins : CMP connu en nombre, inconnu en « — »', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 1400)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final e = etat();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [besoinsProvider.overrideWith((ref) async => StockRecu(e))],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: VueBesoins(terme: '')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final liste = tester
        .state<EtatVueBesoins>(find.byType(VueBesoins))
        .construireListe();
    expect(liste, isNotNull);
    expect(liste!.entetes.last, 'Coût moyen pondéré');

    final parArticle = {for (final l in liste.lignes) l[0]: l.last};
    expect(parArticle, {'Riz': '1250.5000', 'Sel': '—'});
  });
}
