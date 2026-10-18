import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import 'support/faux_transport.dart';

/// Audit de couverture (18/10/2026) : le parc M8 et les contrats des autres
/// postes descendent. Une plaque déjà au parc est le même véhicule ; un
/// contrat d'ailleurs occupe le véhicule ici aussi (RG-08 du poste).
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(
          FauxTransport(
            (r) => r.methode == 'GET'
                ? FauxCatalogue(elements).repondre(r)
                : reponseLot(r),
          ),
        )
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test('plaque connue = même véhicule ; nouveau véhicule inscrit ; le contrat '
      'd’un autre poste occupe la période', () async {
    final local = await VehiculeDao(b.db).enregistrerVehicule(
      immatriculation: 'BJ-1',
      categorie: CategorieVehicule.voiture,
      tarifJour: 20000,
    );
    // Ce poste a envoyé sa création ; le serveur l'a fusionnée.
    await b.db.customStatement(
      "UPDATE operations_sync_local SET statut = 'synchronise'",
    );

    final bilan = await descendre([
      element('clients', 'cl-1', {
        'nom': 'Sabi',
        'telephone': '96000003',
        'type_client': 'particulier',
      }),
      element('vehicules', 'srv-bj1', {
        'immatriculation': 'BJ-1',
        'categorie': 'voiture',
        'annee': 2020,
        'transmission': null,
        'capacite': 5,
        'tarif_jour': '22000.00',
        'statut': 'disponible',
      }),
      element('vehicules', 'srv-bj2', {
        'immatriculation': 'BJ-2',
        'categorie': 'moto',
        'annee': 2021,
        'transmission': null,
        'capacite': 2,
        'tarif_jour': '8000.00',
        'statut': 'entretien',
      }),
      {
        ...element('contrats_location', 'ctr-1', {
          'vehicule_id': 'srv-bj1',
          'client_id': 'cl-1',
          'guide_id': null,
          'date_debut': '2026-10-20',
          'date_fin': '2026-10-23',
          'numero': 'LOC-2026-00001',
          'statut': 'actif',
          'montant': '66000.00',
        }),
        'poste_origine': 'POSTE-B',
      },
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final dao = VehiculeDao(b.db);
    final ligne = await (b.db.select(
      b.db.vehiculesLocal,
    )..where((v) => v.id.equals(local.id))).getSingle();
    expect(ligne.tarifJour, 22000, reason: 'le tarif du serveur suit');
    expect((await dao.vehicule('srv-bj2'))!.statut, StatutVehicule.entretien);
    final dispo = await dao.disponibilite(
      vehiculeId: local.id,
      debut: DateTime(2026, 10, 21),
      fin: DateTime(2026, 10, 22),
    );
    expect(dispo.calendrierLibre, isFalse, reason: 'occupé par POSTE-B');
    expect(
      (await b.db.select(b.db.vehiculesLocal).get()).length,
      2,
      reason: 'aucun doublon de la plaque BJ-1',
    );
  });
}
