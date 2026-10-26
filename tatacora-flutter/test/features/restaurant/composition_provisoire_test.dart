import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_api.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// La COMPOSITION PROVISOIRE d'une fiche (21/10/2026, v35) : posée par le
/// serveur (ses fiches semées, qui descendent avec la marque), lue par la carte
/// du restaurant, le point de vente et les compteurs, et LEVÉE quand la
/// composition est réenregistrée — ici comme au serveur
/// (`CompositionRecetteService::remplacerComposition`).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late RestaurantDao dao;
  late RestaurantApi api;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-1',
            login: 'chef',
            nom: 'Aïcha',
            role: 'cuisinier',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    final stocks = StocksDao(db);
    await stocks.creerArticle(
      id: 'riz',
      libelle: 'Riz',
      categorie: null,
      uniteMesure: 'kg',
      seuilCentiemes: 0,
      suivi: SuiviArticle.permanent,
      pointStockageId: null,
      auteurId: 'u-1',
    );
    dao = RestaurantDao(db, stocks: stocks);
    api = RestaurantApi(
      dao: dao,
      peutLire: () => true,
      peutEcrire: () => true,
      auteurId: () => 'u-1',
    );
  });
  tearDown(() => db.close());

  Future<IssueAlignement> descendre(String id, {required bool provisoire}) =>
      db.transaction(
        () =>
            AligneurCatalogue(
              db,
              DescenteCatalogueDao(db),
              auteur: () async => 'u-1',
            ).aligner(
              ElementCatalogue(
                table: TableDescendue.recettes,
                id: id,
                actif: true,
                modifieLe: '2026-10-21 10:00:00',
                donnees: {
                  'libelle': 'Riz sauce',
                  'composition_provisoire': provisoire,
                  'lignes': [
                    {'article_id': 'riz', 'quantite_unitaire': '0.250'},
                  ],
                },
              ),
            ),
      );

  Future<bool?> marque(String id) async => (await (db.select(
    db.recettesLocal,
  )..where((r) => r.id.equals(id))).getSingle()).compositionProvisoire;

  test('la marque DESCEND avec la fiche, et se lit : fiche, compteur, '
      'catalogue du point de vente', () async {
    expect(await descendre('r-1', provisoire: true), isA<Aligne>());
    expect(await marque('r-1'), isTrue);

    final fiches = await dao.fiches();
    expect(fiches.single.compositionProvisoire, isTrue);
    final compteurs =
        (await api.compteursFiches()) as RestaurantRecu<CompteursFiches>;
    expect(compteurs.donnees.provisoires, 1);
    expect(compteurs.donnees.total, 1);

    // Un plat qui s'en sert porte la marque « P » au comptoir.
    await db
        .into(db.menusLocal)
        .insert(
          MenusLocalCompanion.insert(
            id: 'm-1',
            libelle: 'Carte',
            type: 'local',
            creeLe: DateTime(2026, 10, 1),
            creePar: 'u-1',
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
            creeLe: DateTime(2026, 10, 1),
            creePar: 'u-1',
          ),
        );
    final rayons = await CatalogueDao(db).rayons();
    final plat = rayons
        .firstWhere((r) => r.module == ModuleVendable.m4Restaurant)
        .articles
        .single;
    expect(plat.compositionProvisoire, isTrue);
    expect(plat.sansLienStock, isFalse);

    // Le serveur l'a levée : elle redescend à faux.
    await descendre('r-1', provisoire: false);
    expect(await marque('r-1'), isFalse);
    expect(
      (await CatalogueDao(db).rayons())
          .firstWhere((r) => r.module == ModuleVendable.m4Restaurant)
          .articles
          .single
          .compositionProvisoire,
      isFalse,
    );
  });

  test('LEVER la marque : réenregistrer la composition la fait tomber, et la '
      'modification part avec `lignes` même inchangées', () async {
    await descendre('r-1', provisoire: true);
    await db.customStatement(
      "UPDATE operations_sync_local SET statut = 'synchronise'",
    );

    await dao.enregistrerRecette(
      const SaisieFiche(
        id: 'r-1',
        libelle: 'Riz sauce',
        lignes: [LigneSaisieComposition(articleId: 'riz', quantite: '0,25')],
      ),
      auteurId: 'u-1',
    );

    expect(await marque('r-1'), isFalse);
    final ops = await OperationsSyncDao(
      db,
    ).operations(table: TableSynchronisee.recettes);
    expect(ops, hasLength(1));
    expect(ops.single.type, TypeOperationSync.modification);
    final charge = jsonDecode(ops.single.payload) as Map<String, dynamic>;
    expect(charge['lignes'], [
      {'article_id': 'riz', 'quantite_unitaire': '0.250'},
    ]);
    final compteurs =
        (await api.compteursFiches()) as RestaurantRecu<CompteursFiches>;
    expect(compteurs.donnees.provisoires, 0);
  });

  test(
    'une fiche NON provisoire ré-enregistrée à l’identique n’enfile rien',
    () async {
      await descendre('r-1', provisoire: false);
      await dao.enregistrerRecette(
        const SaisieFiche(
          id: 'r-1',
          libelle: 'Riz sauce',
          lignes: [LigneSaisieComposition(articleId: 'riz', quantite: '0,25')],
        ),
        auteurId: 'u-1',
      );
      expect(
        await OperationsSyncDao(
          db,
        ).operations(table: TableSynchronisee.recettes),
        isEmpty,
      );
    },
  );
}
