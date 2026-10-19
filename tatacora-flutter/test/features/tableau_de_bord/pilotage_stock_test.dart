import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_tableau_de_bord.dart';

import '../../support/coquille_montee.dart';

/// La « Valeur du stock » de M11 ne MINORE plus sans le dire (D119).
///
/// Un article qui a du stock mais aucune entrée valorisée compte pour zéro
/// franc dans la somme : la somme est minorée, et un chiffre minoré qui ne le
/// dit pas se lit comme exact. Quand `sansValorisation > 0`, la valeur est
/// accompagnée de la mention « N article(s) sans coût » ; sur un registre
/// vide (ou entièrement valorisé), « 0 FCFA » reste vrai et n'a aucune mention.
void main() {
  EtatStock etat({required String valeur, required int sans, int refs = 3}) =>
      EtatStock(
        kpis: KpisStock(
          references: refs,
          sousSeuil: 1,
          rupture: 0,
          valeurStock: valeur,
          mouvements30Jours: 4,
          permanents: refs,
          journaliers: 0,
          sansValorisation: sans,
        ),
        lignes: const [],
        arreteAu: '09/10/2026 14:03',
      );

  group('Les deux phrases, en fonctions pures', () {
    test(
      'avec des articles sans coût : le montant ET ce qu’il ne comprend pas',
      () {
        final k = etat(valeur: '12505', sans: 2).kpis;
        expect(mentionStockSansCout(k), '2 article(s) sans coût');
        expect(
          valeurStockPilotage(k),
          '12 505 FCFA (hors 2 article(s) sans coût)',
        );
      },
    );

    test('registre vide ou entièrement valorisé : aucune mention', () {
      final vide = etat(valeur: '0', sans: 0, refs: 0).kpis;
      expect(mentionStockSansCout(vide), '');
      expect(valeurStockPilotage(vide), '0 FCFA');
      expect(
        valeurStockPilotage(etat(valeur: '12505', sans: 0).kpis),
        '12 505 FCFA',
      );
    });
  });

  /// Sur la CHAÎNE RÉELLE (piège 5) : `StocksDao` -> `stocksApiProvider` ->
  /// `TableauDeBordLocal` (la bande) -> la carte KPI du pilotage, et
  /// `stockPilotageProvider` -> la carte « Stocks » par module. Aucun
  /// fournisseur de données n'est surchargé.
  ///
  /// Depuis le 12/10/2026, la carte KPI lit l'indicateur `valeur_stock` de la
  /// BANDE (accueil.blade.php l.928-933) : libellé et note de la vue, la
  /// mention « hors N article(s) sans coût » en plus (D119). Le décompte
  /// « N référence(s) · N sous seuil » qu'elle portait n'est pas dans la vue.
  group('Rendu de la carte « Valeur du stock » du pilotage', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.enMemoire());
    tearDown(() => db.close());

    const noteVue =
        "Au coût moyen pondéré, à l'instant — jamais au prix de vente";

    Future<void> monter(WidgetTester tester) async {
      await monterCoquille(
        tester,
        role: 'administrateur',
        droits: {
          for (final m in ['M1', 'M6', 'M10', 'M11']) m: 'C',
        },
        routeActive: '/tableau-de-bord',
        enfant: const EcranTableauDeBord(),
        surcharges: [baseLocaleProvider.overrideWithValue(db)],
      );
      await tester.tap(find.text('Pilotage consolidé'));
      await tester.pumpAndSettle();
    }

    List<String> textes(WidgetTester tester, Key cle) => tester
        .widgetList<Text>(
          find.descendant(of: find.byKey(cle), matching: find.byType(Text)),
        )
        .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
        .toList();

    testWidgets('des articles sans coût : la mention est DANS la carte (après '
        'la note de la vue) et dans la ligne du module', (tester) async {
      // L'auteur des mouvements est une vraie clé étrangère (RG-15).
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-essai',
              login: 'essai',
              nom: 'Essai',
              role: 'magasinier',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
      final stocks = StocksDao(db);
      final point = await stocks.creerPoint(libelle: 'Magasin');
      Future<void> article(String id, int centiemes, int? cout) =>
          stocks.creerArticle(
            id: id,
            libelle: id,
            categorie: null,
            uniteMesure: 'sac',
            seuilCentiemes: 100,
            suivi: SuiviArticle.permanent,
            pointStockageId: point.id,
            auteurId: 'u-essai',
            ouverture: (centiemes: centiemes, coutDixMilliemes: cout),
          );
      // 10 sacs à 1 250,50 F, puis deux articles SANS coût.
      await article('riz', 1000, 12505000);
      await article('sel', 400, null);
      await article('mil', 300, null);

      await monter(tester);

      expect(textes(tester, const Key('pilotage-kpi-stock')), [
        'VALEUR DU STOCK',
        '12 505 FCFA',
        '$noteVue · hors 2 article(s) sans coût',
      ]);

      final module = textes(tester, const Key('pilotage-module-m6'));
      expect(module, contains('12 505 FCFA (hors 2 article(s) sans coût)'));
    });

    testWidgets('registre vide : « 0 FCFA » et la note de la vue AU MOT, sans '
        'mention — c’est vrai', (tester) async {
      await monter(tester);

      expect(textes(tester, const Key('pilotage-kpi-stock')), [
        'VALEUR DU STOCK',
        '0 FCFA',
        noteVue,
      ]);

      final module = textes(tester, const Key('pilotage-module-m6'));
      expect(module, contains('0 FCFA'));
      expect(module.where((t) => t.contains('sans coût')), isEmpty);
    });
  });
}
