import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';

import 'support/faux_transport.dart';

/// L'ANNULATION d'un contrat de location à la descente — 26/10/2026 (v38).
///
/// Le statut ne va que vers l'avant : un contrat annulé (ici ou au serveur) ne
/// redevient jamais actif par une descente, et une annulation locale encore en
/// file n'est pas écrasée par la version « actif » du serveur.
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

  List<Map<String, Object?>> socle() => [
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
  ];

  Map<String, Object?> contrat(String statut) => {
    ...element('contrats_location', 'ctr-1', {
      'vehicule_id': 'srv-bj1',
      'client_id': 'cl-1',
      'guide_id': null,
      'date_debut': '2026-10-20',
      'date_fin': '2026-10-23',
      'numero': 'LOC-2026-00001',
      'statut': statut,
      'montant': '66000.00',
    }),
    'poste_origine': 'POSTE-B',
  };

  Future<String?> statutLocal() async {
    final lignes = await b.db.select(b.db.contratsLocationLocal).get();
    expect(lignes, hasLength(1));
    return lignes.single.statut;
  }

  Future<int> operationsDeContrat() async =>
      (await b.db.select(b.db.operationsSyncLocal).get())
          .where((o) => o.tableServeur == 'contrats_location')
          .length;

  test('un contrat descendu ANNULÉ est inséré annulé', () async {
    final bilan = await descendre([...socle(), contrat('annule')]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));
    expect(await statutLocal(), 'annule');
  });

  test('un contrat actif devient annulé quand le serveur l\'annule', () async {
    await descendre([...socle(), contrat('actif')]);
    expect(await statutLocal(), isNot('annule'));

    await descendre([...socle(), contrat('annule')]);
    expect(await statutLocal(), 'annule');
  });

  test('jamais de retour à actif par la descente', () async {
    await descendre([...socle(), contrat('annule')]);
    await descendre([...socle(), contrat('actif')]);
    expect(await statutLocal(), 'annule');
  });

  test('l\'annulation locale d\'un contrat connu du serveur s\'enfile ; la '
      'version « actif » du serveur ne l\'écrase pas', () async {
    await descendre([...socle(), contrat('actif')]);
    final id = (await b.db.select(b.db.contratsLocationLocal).get()).single.id;

    await VehiculeDao(b.db).annulerContrat(id);
    expect(await statutLocal(), 'annule');
    expect(await operationsDeContrat(), 1);

    await descendre([...socle(), contrat('actif')]);
    expect(await statutLocal(), 'annule');
    expect(
      await operationsDeContrat(),
      1,
      reason: 'l\'aligneur n\'enfile rien',
    );
  });
}
