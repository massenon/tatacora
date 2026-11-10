import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/bar/presentation/providers_bar.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';

/// 10/11/2026 — le PO : la Carte du bar affiche « non consulté » pour le STOCK VENDABLE alors que
/// la synchronisation est faite (articles et mouvements sont sur le poste). Le stock vendable se
/// calcule ICI, des mouvements répliqués, comme `StockDeCarteService` : solde de l'article lié AU
/// POINT « bar » × unités vendables par unité de stock. Chiffres calculés À LA MAIN.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ProviderContainer conteneur;

  Future<void> article(String id, String libelle, {double seuil = 2}) => db
      .into(db.articlesLocal)
      .insert(
        ArticlesLocalCompanion.insert(
          id: id,
          libelle: libelle,
          categorie: 'Boissons',
          uniteMesure: 'casier',
          seuilAlerte: seuil,
        ),
      );

  Future<void> entree(String id, String articleId, double quantite) => db
      .into(db.mouvementsStockLocal)
      .insert(
        MouvementsStockLocalCompanion.insert(
          id: id,
          articleId: articleId,
          pointId: 'bar',
          typeMouvement: 'entree',
          quantite: quantite,
          motif: 'essai',
          dateMouvement: DateTime(2026, 11, 1),
        ),
      );

  setUp(() async {
    db = AppDatabase.enMemoire();
    conteneur = ProviderContainer(
      overrides: [baseLocaleProvider.overrideWithValue(db)],
    );
    await db
        .into(db.pointsStockageLocal)
        .insert(
          PointsStockageLocalCompanion.insert(
            id: 'bar',
            libelle: 'Bar',
            type: const Value('bar'),
          ),
        );
    await article('a-bière', 'Casier Béninoise');
    await article('a-vide', 'Casier Flag');
  });

  tearDown(() async {
    conteneur.dispose();
    await db.close();
  });

  Future<void> boisson(String libelle, String articleId) async {
    final r = await BoissonsApi(CatalogueDao(db)).enregistrer(
      SaisieBoisson(
        libelle: libelle,
        categorie: CategorieBoisson.locale,
        prixVente: '500',
        articleId: articleId,
        unitesVendablesParUniteStock: '24',
      ),
    );
    expect(r, isA<BarRecu<Boisson>>());
  }

  test('2 casiers de 24 au bar = 48 bouteilles vendables ; un casier à 0 est '
      'en RUPTURE ; rien n’est « non consulté »', () async {
    await boisson('Béninoise 33 cl', 'a-bière');
    await boisson('Flag 33 cl', 'a-vide');
    await entree('m1', 'a-bière', 2);

    final carte = await conteneur.read(carteLocaleProvider.future);
    final biere = carte.firstWhere((l) => l.libelle == 'Béninoise 33 cl');
    final flag = carte.firstWhere((l) => l.libelle == 'Flag 33 cl');

    expect(biere.stock, 48.0); // 2 × 24
    expect(biere.enRupture, isFalse);
    expect(biere.stockNonConsulte, isFalse);
    expect(flag.stock, 0.0);
    expect(flag.enRupture, isTrue);
    expect(flag.sousSeuil, isTrue);
    expect(flag.stockNonConsulte, isFalse);
  });

  test(
    'un solde AU-DESSUS du seuil n’est pas sous seuil ; ≤ seuil l’est',
    () async {
      await boisson('Béninoise 33 cl', 'a-bière');
      await entree('m1', 'a-bière', 2); // seuil 2 : 2 ≤ 2
      var l = (await conteneur.read(carteLocaleProvider.future)).single;
      expect(l.sousSeuil, isTrue);
      expect(l.enRupture, isFalse);

      conteneur.invalidate(carteLocaleProvider);
      await entree('m2', 'a-bière', 1); // 3 > 2
      l = (await conteneur.read(carteLocaleProvider.future)).single;
      expect(l.sousSeuil, isFalse);
      expect(l.stock, 72.0); // 3 × 24
    },
  );

  test(
    'une boisson SANS lien reste sans stock (jamais un 0 inventé)',
    () async {
      final r = await BoissonsApi(CatalogueDao(db)).enregistrer(
        const SaisieBoisson(
          libelle: 'Jus maison',
          categorie: CategorieBoisson.maison,
          prixVente: '300',
        ),
      );
      expect(r, isA<BarRecu<Boisson>>());
      final l = (await conteneur.read(carteLocaleProvider.future)).single;
      expect(l.stock, isNull);
      expect(l.enRupture, isFalse);
    },
  );
}
