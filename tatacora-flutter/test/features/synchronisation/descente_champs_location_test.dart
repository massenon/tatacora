import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import 'support/faux_transport.dart';

/// Lot L3 (27/10/2026) : ce que le poste PORTE désormais DESCEND aussi — année,
/// places et transmission d'un véhicule ; N° `LOC-`, montant net et acompte d'un
/// contrat ; catégorie d'un plat ; certification et tarif d'un guide. La descente
/// range ces champs et n'enfile JAMAIS rien (balayage de la file), ne réécrit pas
/// le montant FIGÉ d'un contrat signé ici, et ne fabrique pas de valeur (année `0`
/// du serveur = inconnue).
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

  Map<String, Object?> client() => element('clients', 'cl-1', {
    'nom': 'Sabi',
    'telephone': '96000003',
    'type_client': 'particulier',
  });

  Map<String, Object?> vehicule(String id, String plaque, Object? annee) =>
      element('vehicules', id, {
        'immatriculation': plaque,
        'categorie': 'voiture',
        'annee': annee,
        'transmission': 'Automatique',
        'capacite': 5,
        'tarif_jour': '25000.00',
        'statut': 'disponible',
      });

  Map<String, Object?> contrat(String id, Map<String, Object?> plus) =>
      element('contrats_location', id, {
        'vehicule_id': 'srv-v1',
        'client_id': 'cl-1',
        'guide_id': null,
        'date_debut': '2026-11-01',
        'date_fin': '2026-11-04',
        'numero': 'LOC-2026-00001',
        'statut': 'actif',
        'montant': '70000.00',
        'acompte': '20000.00',
        ...plus,
      });

  test('véhicule : année, places et transmission descendent ; une année `0` du '
      'serveur se range inconnue, jamais 0', () async {
    final enFile = await b.total();
    final bilan = await descendre([
      vehicule('srv-v1', 'BJ-1', '2021'),
      vehicule('srv-v2', 'BJ-2', 0),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final dao = VehiculeDao(b.db);
    final v1 = (await dao.vehicule('srv-v1'))!;
    expect([v1.annee, v1.capacite, v1.transmission], [2021, 5, 'Automatique']);
    expect(
      (await dao.vehicule('srv-v2'))!.annee,
      isNull,
      reason:
          'le serveur range 0 un véhicule venu d’un poste d’avant : inconnu',
    );
    expect(await b.total(), enFile, reason: 'une descente n’enfile rien');
  });

  test('contrat d’un autre poste : N°, montant net et acompte descendent '
      '(reste dû = différence)', () async {
    final enFile = await b.total();
    final bilan = await descendre([
      client(),
      vehicule('srv-v1', 'BJ-1', 2021),
      contrat('ctr-1', {}),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final c = (await VehiculeDao(b.db).contrats()).single;
    expect(
      [c.numero, c.montant, c.acompte, c.resteDu],
      ['LOC-2026-00001', '70000.00', '20000.00', '50000.00'],
    );
    expect(c.remise, isNull, reason: 'le serveur ne garde pas la remise');
    expect(await b.total(), enFile, reason: 'une descente n’enfile rien');
  });

  test(
    'le montant FIGÉ du poste n’est jamais réécrit par la descente ; le N° '
    'du serveur se pose ; un contrat d’AVANT reçoit les chiffres du serveur',
    () async {
      final dao = VehiculeDao(b.db);
      final v = await dao.enregistrerVehicule(
        immatriculation: 'BJ-1',
        categorie: CategorieVehicule.voiture,
        tarifJour: 25000,
      );
      await b.db
          .into(b.db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: 'cl-loc',
              nom: 'KORA',
              telephone: '97000001',
              typeClient: 'particulier',
            ),
          );
      final signe = await dao.creerContrat(
        SaisieContrat(
          vehiculeId: v.id,
          clientId: 'cl-loc',
          debut: DateTime(2026, 11, 1),
          fin: DateTime(2026, 11, 4),
          pieceIdentite: 'CNI',
          permisConduire: 'P',
          remiseFrancs: 5000,
          acompteFrancs: 20000,
        ),
      );
      final ancien = await dao.creerContrat(
        SaisieContrat(
          vehiculeId: v.id,
          clientId: 'cl-loc',
          debut: DateTime(2026, 12, 1),
          fin: DateTime(2026, 12, 3),
          pieceIdentite: 'CNI',
          permisConduire: 'P',
        ),
      );
      // Un contrat d'avant la v41 : ni montant, ni acompte, ni remise.
      await b.db.customStatement(
        'UPDATE contrats_location_local SET montant = NULL, acompte = NULL, '
        "remise = NULL WHERE id = '${ancien.id}'",
      );
      // Les créations sont parties (accusées) : seul l'aligneur parle ensuite.
      await b.db.customStatement(
        "UPDATE operations_sync_local SET statut = 'synchronise'",
      );

      final bilan = await descendre([
        vehicule(v.id, 'BJ-1', 2021),
        element('clients', 'cl-loc', {
          'nom': 'KORA',
          'telephone': '97000001',
          'type_client': 'particulier',
        }),
        // Le serveur a recalculé au tarif de SA réception : 75 000 (sans remise).
        contrat(signe.id, {
          'vehicule_id': v.id,
          'client_id': 'cl-loc',
          'numero': 'LOC-2026-00007',
          'montant': '75000.00',
          'acompte': '1000.00',
        }),
        contrat(ancien.id, {
          'vehicule_id': v.id,
          'client_id': 'cl-loc',
          'date_debut': '2026-12-01',
          'date_fin': '2026-12-03',
          'numero': 'LOC-2026-00008',
          'montant': '50000.00',
          'acompte': '0.00',
        }),
      ]);
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

      final lignes = {
        for (final l in await b.db.select(b.db.contratsLocationLocal).get())
          l.id: l,
      };
      final s = lignes[signe.id]!;
      expect(s.numero, 'LOC-2026-00007', reason: 'le N° est celui du serveur');
      expect(s.montant, 70000, reason: 'le montant FIGÉ n’est pas réécrit');
      expect(s.acompte, 20000);
      expect(s.remise, 5000);
      final a = lignes[ancien.id]!;
      expect(a.numero, 'LOC-2026-00008');
      expect(
        [a.montant, a.acompte, a.remise],
        [50000, 0, null],
        reason:
            'les chiffres du SERVEUR comblent un contrat d’avant ; la remise, '
            'que le serveur ne garde pas, reste inconnue',
      );
    },
  );

  test('un contrat annulé au serveur le reste ici, et les champs ne reculent '
      'pas', () async {
    await descendre([
      client(),
      vehicule('srv-v1', 'BJ-1', 2021),
      contrat('ctr-1', {'statut': 'annule'}),
    ]);
    final c = (await VehiculeDao(b.db).contrats()).single;
    expect(
      [c.statut, c.numero, c.montant],
      [statutContratAnnule, 'LOC-2026-00001', '70000.00'],
    );
  });

  test(
    'plat : la catégorie descend ; guide : certification et tarif descendent '
    '(un tarif à fraction de franc se range inconnu, le guide reste utilisable)',
    () async {
      final enFile = await b.total();
      final bilan = await descendre([
        element('menus', 'menu-a', {
          'libelle': 'Carte',
          'type': 'local',
          'date_debut': null,
          'date_fin': null,
        }),
        element('recettes', 'rec-a', {
          'libelle': 'Sandwich',
          'composition_provisoire': false,
          'lignes': <Object?>[],
        }),
        element('plats', 'plat-a', {
          'libelle': 'Sandwich poulet',
          'menu_id': 'menu-a',
          'recette_id': 'rec-a',
          'article_id': null,
          'unites_vendables_par_unite_stock': null,
          'prix_vente': '1500.00',
          'categorie': 'sandwicherie',
          'prix_provisoire': false,
          'prix_corrige_main': false,
        }),
        element('plats', 'plat-b', {
          'libelle': 'Plat sans catégorie',
          'menu_id': 'menu-a',
          'recette_id': 'rec-a',
          'article_id': null,
          'unites_vendables_par_unite_stock': null,
          'prix_vente': '500.00',
          'categorie': null,
          'prix_provisoire': false,
          'prix_corrige_main': false,
        }),
        element('guides', 'g-1', {
          'nom': 'Moussa',
          'certification': 'Guide diplômé',
          'zone_competence': 'Atacora',
          'tarif_jour': '15000.00',
        }),
        element('guides', 'g-2', {
          'nom': 'Awa',
          'certification': null,
          'zone_competence': null,
          'tarif_jour': '15000.50',
        }),
      ]);
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

      final plats = {
        for (final p in await b.db.select(b.db.platsLocal).get()) p.id: p,
      };
      expect(plats['plat-a']!.categorie, 'sandwicherie');
      expect(plats['plat-b']!.categorie, isNull);

      final guides = {
        for (final g in await b.db.select(b.db.guidesLocal).get()) g.id: g,
      };
      expect(
        [guides['g-1']!.certification, guides['g-1']!.tarifJour],
        ['Guide diplômé', 15000],
      );
      expect(
        [guides['g-2']!.certification, guides['g-2']!.tarifJour],
        [null, null],
      );
      expect(await b.total(), enFile, reason: 'une descente n’enfile rien');
    },
  );
}
