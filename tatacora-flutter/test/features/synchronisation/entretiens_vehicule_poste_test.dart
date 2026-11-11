import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

import 'support/faux_transport.dart';

/// Les entretiens et carburations des véhicules, côté poste — 21/10/2026
/// (« Immobiliser » de la PWA). Un fait daté qui PART (création, jamais
/// modifié) sans toucher au statut du véhicule, et ceux des autres postes qui
/// DESCENDENT sans rien renvoyer.
void main() {
  late BancSync b;
  late VehiculeDao dao;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    dao = VehiculeDao(b.db);
  });
  tearDown(() => b.fermer());

  Future<List<(String, TypeOperationSync, Map<String, Object?>)>> file(
    TableSynchronisee t,
  ) async => [
    for (final o in await b.dao.operations(table: t))
      (o.entiteId, o.type, jsonDecode(o.payload) as Map<String, Object?>),
  ];

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test('« Immobiliser » écrit un fait daté, le statut reste, et il PART après '
      'le véhicule', () async {
    final v = await dao.enregistrerVehicule(
      immatriculation: 'BJ-1',
      categorie: CategorieVehicule.voiture,
      tarifJour: 25000,
    );
    final e = await dao.enregistrerEntretien(
      vehiculeId: v.id,
      type: TypeEntretien.carburation,
      date: DateTime(2026, 10, 20, 14, 30),
      coutFrancs: 8000,
      auteur: 'gerant',
    );

    expect(e.date, '2026-10-20');
    expect((await dao.entretiens()).single.auteur, 'gerant');
    expect((await dao.entretiens()).single.immatriculation, 'BJ-1');
    // Le statut n'a pas bougé : statut ≠ disponibilité (comme la PWA).
    expect((await dao.vehicule(v.id))?.statut, StatutVehicule.disponible);

    final envois = await file(TableSynchronisee.entretiensVehicule);
    expect(envois, hasLength(1));
    expect(envois.single.$2, TypeOperationSync.creation);
    expect(envois.single.$3, {
      'vehicule_id': v.id,
      'type': 'carburation',
      'date': '2026-10-20',
      'cout': 8000,
    });
    // Le véhicule est en file AVANT son entretien.
    final tout = await b.dao.operations();
    final iVehicule = tout.indexWhere(
      (o) => o.table == TableSynchronisee.vehicules,
    );
    final iEntretien = tout.indexWhere(
      (o) => o.table == TableSynchronisee.entretiensVehicule,
    );
    expect(iVehicule, lessThan(iEntretien));
  });

  test(
    'un coût négatif et un véhicule inconnu sont refusés SANS écrire',
    () async {
      final v = await dao.enregistrerVehicule(
        immatriculation: 'BJ-2',
        categorie: CategorieVehicule.voiture,
        tarifJour: 1000,
      );
      await expectLater(
        dao.enregistrerEntretien(
          vehiculeId: v.id,
          type: TypeEntretien.entretien,
          date: DateTime(2026, 10, 20),
          coutFrancs: -1,
        ),
        throwsA(isA<RefusVehicule>()),
      );
      await expectLater(
        dao.enregistrerEntretien(
          vehiculeId: 'fantome',
          type: TypeEntretien.entretien,
          date: DateTime(2026, 10, 20),
          coutFrancs: 1,
        ),
        throwsA(isA<RefusVehicule>()),
      );
      expect(await dao.entretiens(), isEmpty);
      expect(await file(TableSynchronisee.entretiensVehicule), isEmpty);
    },
  );

  Map<String, Object?> vehiculeServeur(String id) => element('vehicules', id, {
    'immatriculation': 'BJ-$id',
    'categorie': 'voiture',
    'annee': 2020,
    'transmission': null,
    'capacite': null,
    'tarif_jour': '25000.00',
    'statut': 'disponible',
  });

  Map<String, Object?> entretienServeur(
    String id,
    String vehicule, {
    String cout = '15000.00',
  }) => element('entretiens_vehicule', id, {
    'vehicule_id': vehicule,
    'type': 'entretien',
    'date': '2026-10-19',
    'cout': cout,
    'chauffeur_id': null,
  });

  test('l’entretien d’un autre poste descend, sans rien renvoyer', () async {
    final bilan = await descendre([
      vehiculeServeur('srv-v1'),
      entretienServeur('srv-e1', 'srv-v1'),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final e = (await dao.entretiens()).single;
    expect(
      [e.date, e.coutFrancs, e.type],
      ['2026-10-19', 15000, TypeEntretien.entretien],
    );
    expect(e.auteur, isNull);
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });

  test('un véhicule pas encore reçu fait attendre l’entretien ; une fraction '
      'de franc est refusée', () async {
    var bilan = await descendre([entretienServeur('srv-e1', 'srv-absent')]);
    expect(bilan.refuses, 0);
    expect(await dao.entretiens(), isEmpty);

    bilan = await descendre([
      vehiculeServeur('srv-v1'),
      entretienServeur('srv-e2', 'srv-v1', cout: '15000.50'),
    ]);
    expect(bilan.refuses, 1);
    expect(await dao.entretiens(), isEmpty);
  });
}
