import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/data/tableau_de_bord_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/impression/etat_pilotage.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/ecran_pilotage_consolide.dart';

/// L'ÉTAT IMPRIMÉ du pilotage dit, lui aussi, ce que sa « Valeur du stock »
/// ne comprend pas (D119, D130) : le document circule sans l'écran, et une
/// somme minorée qui ne le dit pas se lit comme exacte. Depuis le 12/10/2026
/// la valeur est la carte « Valeur du stock », lue de la BANDE comme à l'écran
/// (plus une ligne lue en M6), et la mention part en ligne RÉSERVE.
///
/// L'état est composé par `composerEtatPilotage`, celui que le bouton
/// d'export appelle — pas par une copie de sa logique.
void main() {
  EtatStock etatAvecSansCout() {
    // Riz : 10,00 à 1 250,50 F (valorisé). Sel : 4,00 sans aucun coût.
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
          seuilCentiemes: 100,
          suivi: SuiviArticle.permanent,
        ),
      ],
      mouvements: [mv(1, 'riz', 1000, cout: 12505000), mv(2, 'sel', 400)],
      maintenant: DateTime(2026, 10, 9, 14),
      libellesPoints: const {},
    );
  }

  /// La bande telle que `TableauDeBordLocal` la calcule sur cet état de stock
  /// — l'indicateur `valeur_stock` et sa mention viennent du VRAI calcul, pas
  /// d'un indicateur écrit à la main dans le test.
  Future<TableauDeBord> bande(EtatStock e) async {
    final r = await TableauDeBordLocal(
      unites: () async => const [],
      reservations: () async => const [],
      employes: () async => const [],
      stock: () async => StockRecu(e),
      pieces: () async => const [],
      creances: () async => const [],
      paiements: () async => const [],
      sessions: () async => const [],
      peutLire: () => true,
      maintenant: () => DateTime(2026, 10, 9, 14),
    ).consulter(SelectionPeriode.parDefaut);
    return (r as TableauDeBordRecu).tableau;
  }

  Future<EtatPilotage> composer(WidgetTester tester, EtatStock e) async {
    final tableau = await tester.runAsync(() => bande(e));
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockPilotageProvider.overrideWith((r) async => StockRecu(e)),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              // Chargé et gardé vivant : un `autoDispose` non écouté n'a pas
              // de valeur à lire.
              r.watch(stockPilotageProvider);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    return composerEtatPilotage(ref, tableau: tableau);
  }

  testWidgets('avec des articles sans coût : le montant (carte « Valeur du '
      'stock », lue de la bande) ET ce qu’il ne comprend pas (réserve)', (
    tester,
  ) async {
    final e = etatAvecSansCout();
    expect(e.kpis.valeurStock, '12505');
    expect(e.kpis.sansValorisation, 1);

    final etat = await composer(tester, e);
    expect(etat.kpis['Valeur du stock'], '12 505 FCFA');
    expect(
      etat.lignes,
      contains(
        equals(['RÉSERVE', 'Valeur du stock hors 1 article(s) sans coût', '']),
      ),
    );
    expect(
      etat.lignes.where((l) => l[1] == 'Valeur au coût moyen pondéré'),
      isEmpty,
    );
  });

  testWidgets('registre vide : « 0 FCFA » sans réserve, c’est vrai', (
    tester,
  ) async {
    final e = calculerEtat(
      articles: const [],
      mouvements: const [],
      maintenant: DateTime(2026, 10, 9),
      libellesPoints: const {},
    );

    final etat = await composer(tester, e);
    expect(etat.kpis['Valeur du stock'], '0 FCFA');
    expect(
      etat.lignes.where((l) => l[1].startsWith('Valeur du stock')),
      isEmpty,
    );
  });

  testWidgets('sans bande (droit M11 refusé) : « — », jamais un zéro, et '
      'aucune réserve sur une valeur qui n’est pas imprimée', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockPilotageProvider.overrideWith(
            (r) async => StockRecu(etatAvecSansCout()),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final etat = composerEtatPilotage(ref);
    expect(etat.kpis['Valeur du stock'], '—');
    expect(
      etat.lignes.where((l) => l[1].startsWith('Valeur du stock')),
      isEmpty,
    );
  });

  // Contrôle du lot 1, A-1 (12/10/2026) : PDF exporté pendant le calcul de la
  // bande ou après son échec — les trois cartes lues de la bande sortaient à
  // « — » SANS une ligne pour dire pourquoi.
  testWidgets('sans bande : les trois « — » de la bande sont DITS par une '
      'réserve « non consultés à l’édition »', (tester) async {
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stockPilotageProvider.overrideWith(
            (r) async => StockRecu(etatAvecSansCout()),
          ),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, r, _) {
              ref = r;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final etat = composerEtatPilotage(ref);
    expect(etat.kpis['Chiffre d\'affaires encaissé'], '—');
    expect(etat.kpis['Trésorerie (caisse)'], '—');
    expect(etat.kpis['Valeur du stock'], '—');
    expect(
      etat.lignes,
      contains(
        equals([
          'RÉSERVE',
          "Chiffre d'affaires encaissé, Trésorerie (caisse) et Valeur du "
              "stock non consultés à l'édition : indicateurs de la bande non "
              'reçus (calcul en cours, en échec ou non autorisé)',
          '—',
        ]),
      ),
    );
  });

  testWidgets('bande reçue, « Valeur du stock » non établie : une réserve '
      'pour CET indicateur, avec la raison de la bande, et aucune autre', (
    tester,
  ) async {
    final tableau = await tester.runAsync(
      () async =>
          ((await TableauDeBordLocal(
                    unites: () async => const [],
                    reservations: () async => const [],
                    employes: () async => const [],
                    stock: () async => const StockInjoignable(),
                    pieces: () async => const [],
                    creances: () async => const [],
                    paiements: () async => const [],
                    sessions: () async => const [],
                    peutLire: () => true,
                    maintenant: () => DateTime(2026, 10, 9, 14),
                  ).consulter(SelectionPeriode.parDefaut))
                  as TableauDeBordRecu)
              .tableau,
    );
    final indicateur = tableau!.parCle(cleValeurStock)!;
    expect(indicateur.estDisponible, isFalse, reason: 'cas non vide');

    final reserves = reservesBandeNonConsultee(tableau);
    expect(reserves, hasLength(1));
    expect(reserves.single[0], 'RÉSERVE');
    expect(
      reserves.single[1],
      startsWith("Valeur du stock non consulté à l'édition"),
    );
    // La raison de la bande part avec la réserve : le lecteur du papier n'a
    // pas l'infobulle de la carte.
    expect(indicateur.raisonAbsence, isNotNull, reason: 'cas non vide');
    expect(reserves.single[1], endsWith(' : ${indicateur.raisonAbsence}'));
    expect(reserves.single[2], '—');
  });

  test('bande reçue et établie : AUCUNE réserve de bande', () async {
    final tableau =
        ((await TableauDeBordLocal(
                  unites: () async => const [],
                  reservations: () async => const [],
                  employes: () async => const [],
                  stock: () async => StockRecu(etatAvecSansCout()),
                  pieces: () async => const [],
                  creances: () async => const [],
                  paiements: () async => const [],
                  sessions: () async => const [],
                  peutLire: () => true,
                  maintenant: () => DateTime(2026, 10, 9, 14),
                ).consulter(SelectionPeriode.parDefaut))
                as TableauDeBordRecu)
            .tableau;
    for (final cle in const [
      cleChiffreAffairesEncaisse,
      cleTresorerieCaisse,
      cleValeurStock,
    ]) {
      expect(valeurPilotageDeLaBande(tableau, cle), isNotNull, reason: cle);
    }
    expect(reservesBandeNonConsultee(tableau), isEmpty);
  });
}
