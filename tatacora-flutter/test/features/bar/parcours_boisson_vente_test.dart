import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/bar/presentation/ecran_carte_bar.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/providers_hebergement.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/presentation/ecran_pos_comptant.dart';
import 'package:tatacora_flutter/features/pos/presentation/providers_pos.dart';
import 'package:tatacora_flutter/features/stocks/presentation/ecran_stocks.dart';
import 'package:tatacora_flutter/features/ventes/presentation/ecran_historique_ventes.dart';

import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import '../pos/support/outils_ventes.dart';

/// Le PARCOURS que le PO ne parvenait pas à faire (26/10/2026), de bout en
/// bout et sur la base locale réelle, écran par écran :
///
///  1. **Carte du bar** — « Nouvelle boisson » avec son article de stock et son
///     facteur (un casier de 24) ;
///  2. **Point de vente du comptoir** — la vendre, plus une boisson SANS lien et
///     un plat SANS fiche, puis encaisser ;
///  3. **Historique des ventes** — la vente y est, avec la mention « stock ✕ »
///     (une ligne n'a rien décrémenté) ;
///  4. **Stocks** — « −X en attente d'envoi » sous l'article de la boisson.
///
/// Les écrans se SUCCÈDENT sous un même `ProviderScope`, comme les pages du
/// routeur sous le scope racine de l'application : un fournisseur qui garderait
/// l'état d'avant la vente (le défaut corrigé le 26/10/2026 sur le journal) se
/// verrait ici, pas dans un test qui monte l'historique après coup sur une base
/// déjà garnie.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  final ecran = ValueNotifier<Widget>(const SizedBox.shrink());

  // La vente a lieu le 26/10/2026 à 10 h : l'horloge du DAO est fixée.
  final jour = DateTime(2026, 10, 26, 10);

  setUp(() async {
    db = AppDatabase.enMemoire();
    await avecComptabilite(db, maintenant: jour);
    await ouvrirLaCaisseDuComptoir(db);

    await db
        .into(db.articlesLocal)
        .insert(
          ArticlesLocalCompanion.insert(
            id: 'art-casier',
            libelle: 'Casier Béninoise',
            categorie: 'Boissons',
            uniteMesure: 'casier',
            seuilAlerte: 2,
          ),
        );
    // Une boisson SANS lien et un plat SANS fiche : la vente de chacun ne
    // sortirait aucun stock (`stock_non_impacte`).
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-libre',
            articleId: '',
            libelle: 'Jus maison',
            categorie: 'maison',
            prixVente: 300,
          ),
        );
    await db
        .into(db.menusLocal)
        .insert(
          MenusLocalCompanion.insert(
            id: 'm-1',
            libelle: 'Carte',
            type: 'local',
            creeLe: jour,
            creePar: caissierDeVente,
          ),
        );
    await db
        .into(db.recettesLocal)
        .insert(
          RecettesLocalCompanion.insert(
            id: 'r-1',
            libelle: 'Fiche vide',
            creeLe: jour,
            creePar: caissierDeVente,
          ),
        );
    await db
        .into(db.platsLocal)
        .insert(
          PlatsLocalCompanion.insert(
            id: 'p-1',
            menuId: 'm-1',
            recetteId: 'r-1',
            libelle: 'Riz sauce',
            prixVente: 2500,
            creeLe: jour,
            creePar: caissierDeVente,
          ),
        );
  });

  tearDown(() => db.close());

  Future<void> monter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(2400, 1600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const droits = {'M5': 'C', 'M4': 'C', 'M6': 'C', 'M1': 'C'};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: caissierDeVente,
              login: 'caissier',
              nom: 'Caissier',
              role: 'gerant',
              droits: GardeAcces.depuisJson(droits),
            ),
          ),
          droitsProvider.overrideWithValue(GardeAcces.depuisJson(droits)),
          // Le DAO branché sur le moteur comptable de la base d'essai, à
          // l'horloge fixée : la clôture passe sa pièce comme en production.
          depotPanierProvider.overrideWithValue(
            PanierRepositoryLocal(panierDaoSur(db, horloge: jour)),
          ),
          depotReservationProvider.overrideWithValue(
            ReservationRepositoryLocal(ReservationDao(db)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(
            body: ValueListenableBuilder<Widget>(
              valueListenable: ecran,
              builder: (_, e, _) => e,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> aller(WidgetTester tester, Widget e) async {
    ecran.value = e;
    await tester.pumpAndSettle();
  }

  testWidgets('créer une boisson liée au stock, la vendre au comptoir, la voir '
      'à l’historique, lire « −X en attente d’envoi »', (tester) async {
    await monter(tester);

    // L'historique est ouvert D'ABORD, vide : c'est le cas du gérant qui
    // regarde son journal avant de servir (et qui laisserait un journal figé).
    await aller(tester, const EcranHistoriqueVentes());
    expect(find.byKey(const Key('ventes-kpi-nombre')), findsOneWidget);
    expect(find.textContaining('Aucune vente'), findsWidgets);

    // 1. La carte du bar.
    await aller(tester, const EcranCarteBar());
    await tester.tap(find.byKey(const Key('carte-nouvelle-boisson')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nouvelle-boisson-libelle')),
      'Béninoise 33 cl',
    );
    await tester.enterText(
      find.byKey(const Key('nouvelle-boisson-prix')),
      '500',
    );
    await tester.tap(find.byKey(const Key('nouvelle-boisson-article-liste')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Casier Béninoise').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('nouvelle-boisson-conversion')),
      '24',
    );
    await tester.tap(find.byKey(const Key('nouvelle-boisson-confirmer')));
    await tester.pumpAndSettle();
    final creee = await (db.select(
      db.cartesBoissonLocal,
    )..where((b) => b.libelle.equals('Béninoise 33 cl'))).getSingle();
    expect([creee.articleId, creee.unitesVendables], ['art-casier', '24']);

    // Le toast « est à la carte du bar » couvre le coin du comptoir : il
    // s'éteint de lui-même, comme à l'usage.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // 2. Le point de vente : la boisson liée ×6, la boisson libre, le plat.
    await aller(tester, const EcranPosComptant());
    await tester.tap(find.byKey(const Key('pos-comptant-ouvrir')));
    await tester.pumpAndSettle();
    for (var i = 0; i < 6; i++) {
      await tester.tap(find.byKey(Key('pos-article-M5:${creee.id}')));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byKey(const Key('pos-article-M5:bsn-libre')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-famille')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-rayon-M4')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-article-M4:p-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-cloturer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('modale-vente-encaissee')), findsOneWidget);
    await tester.tap(find.byKey(const Key('vente-encaissee-fermer')));
    await tester.pumpAndSettle();

    // 3. L'historique : la vente y est, au bon montant, avec « stock ✕ ».
    await aller(tester, const EcranHistoriqueVentes());
    const montant = 6 * 500 + 300 + 2500;
    final panier = await db.select(db.paniersLocal).getSingle();
    expect(panier.statut, 'cloture');
    final rangee = find.byKey(Key('vente-ligne-${panier.id}'));
    expect(rangee, findsOneWidget);
    // Le montant est dans LA LIGNE de la vente, pas ailleurs sur la page.
    expect(
      find.descendant(
        of: rangee,
        matching: find.textContaining(formaterFcfa(montant)),
      ),
      findsWidgets,
    );
    expect(find.byKey(const Key('vente-badge-stock')), findsOneWidget);

    // 4. Les stocks : ce que la file sortira, sous l'article de la boisson.
    await aller(tester, const EcranStocks());
    // 6 bouteilles / 24 par casier = 0,25 casier.
    expect(
      find.byKey(const Key('stocks-en-attente-art-casier')),
      findsOneWidget,
    );
    expect(find.text("−0,25 en attente d'envoi"), findsOneWidget);
  });
}
