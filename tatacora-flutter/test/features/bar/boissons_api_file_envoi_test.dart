import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/bar/data/boissons_api.dart';
import 'package:tatacora_flutter/features/bar/domain/entities/boisson.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// D (21/10/2026) — « Modifier la boisson » ENFILE-t-il une opération ?
///
/// L'agent d'avant l'affirmait sans l'avoir vérifié (piège 1 : un commentaire
/// qui décrit un déclencheur n'est pas un déclencheur). Ces cas passent par
/// `BoissonsApi` — le chemin de l'écran Carte du bar —, jamais par
/// `CatalogueDao.enregistrerBoisson` directement, et lisent la FILE.
///
/// Mutation éprouvée : remplacer `enregistrerBoisson` par `_ecrireBoisson` dans
/// `CatalogueDao` (ne plus enfiler) fait rougir chaque cas ci-dessous.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late BoissonsApi api;
  late OperationsSyncDao file;

  setUp(() {
    db = AppDatabase.enMemoire();
    api = BoissonsApi(CatalogueDao(db));
    file = OperationsSyncDao(db);
  });

  tearDown(() => db.close());

  Future<List<OperationSync>> boissons() async => [
    for (final o in await file.operations())
      if (o.table == TableSynchronisee.cartesBoisson) o,
  ];

  Future<Boisson> creer() async {
    final r = await api.enregistrer(
      const SaisieBoisson(
        libelle: 'Béninoise 33 cl',
        categorie: CategorieBoisson.locale,
        prixVente: '500',
        articleId: '',
      ),
    );
    return (r as BarRecu<Boisson>).donnees;
  }

  test('« Modifier la boisson » (libellé, catégorie) enfile UNE modification '
      'aux seuls champs changés', () async {
    final b = await creer();
    expect((await boissons()).single.type, TypeOperationSync.creation);

    final r = await api.modifier(
      b.id,
      libelle: 'Béninoise 65 cl',
      categorie: CategorieBoisson.importee,
    );
    expect(r, isA<BarRecu<Boisson>>());

    final ops = await boissons();
    expect(ops, hasLength(2));
    expect(ops.last.type, TypeOperationSync.modification);
    expect(ops.last.entiteId, b.id);
    expect(jsonDecode(ops.last.payload), {
      'libelle': 'Béninoise 65 cl',
      'categorie': 'importee',
    });
    expect(ops.last.statut, StatutOperationSync.enAttente);
  });

  test('« Modifier le prix » enfile le seul prix', () async {
    final b = await creer();
    await api.modifierPrix(b.id, '650');
    final ops = await boissons();
    expect(ops, hasLength(2));
    expect(jsonDecode(ops.last.payload), {'prix_vente': 650});
  });

  test('une modification qui ne change rien n’enfile rien, un refus non '
      'plus', () async {
    final b = await creer();
    await api.modifier(
      b.id,
      libelle: 'Béninoise 33 cl',
      categorie: CategorieBoisson.locale,
    );
    expect(await boissons(), hasLength(1));

    final refus = await api.modifier(
      b.id,
      libelle: '   ',
      categorie: CategorieBoisson.locale,
    );
    expect(refus, isA<BarRefuse<Boisson>>());
    expect(await boissons(), hasLength(1));
  });

  test('la ligne locale ET la file sont écrites ensemble : l’écriture '
      'métier est relue par une instance neuve', () async {
    final b = await creer();
    await api.modifier(
      b.id,
      libelle: 'Castel',
      categorie: CategorieBoisson.locale,
    );
    final relu = await CatalogueDao(db).boissonDuCatalogue(b.id);
    expect(relu!.libelle, 'Castel');
    expect(
      (await boissons()).last.entiteId,
      b.id,
      reason: 'la file désigne la boisson modifiée',
    );
  });
}
