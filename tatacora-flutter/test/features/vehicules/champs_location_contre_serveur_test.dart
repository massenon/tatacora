@Timeout(Duration(minutes: 3))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/restaurant/data/restaurant_dao.dart';
import 'package:tatacora_flutter/features/restaurant/domain/calcul_restaurant.dart';
import 'package:tatacora_flutter/features/restaurant/domain/entities/plat.dart';
import 'package:tatacora_flutter/features/restaurant/domain/messages_restaurant.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/tourisme/data/tourisme_dao.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';
import 'package:tatacora_flutter/features/vehicules/domain/regles_vehicules.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/scenario_file.dart';

/// Les CHAMPS DU WEB que le poste porte depuis la v41 (lot L3, 27/10/2026),
/// CONFRONTÉS AU SERVEUR en l'exécutant (piège 12) :
/// `tool/vehicules/rejouer_champs_location.php` pousse des documents hors bornes
/// au vrai `SynchronisationService` (gestionnaires véhicules, contrats, plats) et
/// rend les PHRASES du refus ; le poste doit dire les mêmes mots, aux mêmes
/// bornes, dans le même ordre, et son montant FIGÉ doit être celui que le serveur
/// range. Les dix catégories d'un plat (clés ET libellés) sont relues de
/// `CarteRestaurant::CATEGORIES`, jamais recopiées.
///
/// Un second volet pousse la FILE du poste (véhicule complet, contrat avec remise
/// et acompte, plat catégorisé, guide certifié) au vrai moteur : ce que le serveur
/// a rangé doit être ce que le poste a saisi.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Map<String, dynamic> serveur;
  late Map<String, dynamic> refus;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_champs_location.php',
      dossier: 'vehicules',
    );
    refus = serveur['refus'] as Map<String, dynamic>;
  });

  late AppDatabase db;
  late VehiculeDao dao;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = VehiculeDao(db);
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '97000001',
            typeClient: 'particulier',
          ),
        );
  });
  tearDown(() => db.close());

  Future<Vehicule> parc({int tarif = 25000}) => dao.enregistrerVehicule(
    immatriculation: 'BJ-L3',
    categorie: CategorieVehicule.voiture,
    tarifJour: tarif,
  );

  Future<ContratLocation> louer(
    Vehicule v, {
    int remise = 0,
    int acompte = 0,
    String debut = '2026-11-01',
    String fin = '2026-11-04',
  }) => dao.creerContrat(
    SaisieContrat(
      vehiculeId: v.id,
      clientId: 'cli-1',
      debut: DateTime.parse(debut),
      fin: DateTime.parse(fin),
      pieceIdentite: 'CNI-1',
      permisConduire: 'P-1',
      remiseFrancs: remise,
      acompteFrancs: acompte,
    ),
  );

  Matcher refusDe(String phrase) =>
      throwsA(isA<RefusVehicule>().having((e) => e.message, 'message', phrase));

  test('le script a rendu toute l’histoire (l’extraction n’est pas vide)', () {
    expect(refus.length, greaterThanOrEqualTo(17));
    expect(refus.values.whereType<String>().length, refus.length);
    expect(serveur['categories'], hasLength(10));
    expect((serveur['categories_libelles'] as Map).length, 10);
    expect(serveur['vehicule_ok'], isNotNull);
    expect(serveur['contrat_ok'], isNotNull);
  });

  group(
    'Véhicule : année, places, transmission — mêmes bornes, mêmes mots',
    () {
      test(
        'l’an prochain est la borne haute de l’année, comme `date(Y) + 1`',
        () {
          expect(anneeMaximaleVehicule(), serveur['annee_max']);
        },
      );

      test('année : trop ancienne, trop récente, illisible, vide', () async {
        final v = await parc();
        Future<void> modifier(int? annee) => dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'BJ-L3',
          categorie: CategorieVehicule.voiture,
          tarifJour: 25000,
          annee: annee,
        );

        await expectLater(
          modifier(1949),
          refusDe(refus['modif_annee_trop_ancienne']),
        );
        await expectLater(
          modifier((serveur['annee_max'] as int) + 1),
          refusDe(refus['modif_annee_trop_recente']),
        );
        expect(refusAnnee('abc'), refus['modif_annee_texte']);
        expect(refusAnnee(''), refus['modif_annee_nulle']);
        expect(refusAnnee('1949'), refus['creation_annee_trop_ancienne']);
        // Les bornes elles-mêmes passent (comme au serveur).
        await modifier(1950);
        await modifier(serveur['annee_max'] as int);
        expect((await dao.vehicule(v.id))!.annee, serveur['annee_max']);
      });

      test('places : zéro, cent, illisible, vide', () async {
        final v = await parc();
        Future<void> modifier(int? places) => dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'BJ-L3',
          categorie: CategorieVehicule.voiture,
          tarifJour: 25000,
          capacite: places,
        );

        await expectLater(modifier(0), refusDe(refus['modif_places_zero']));
        await expectLater(modifier(100), refusDe(refus['modif_places_cent']));
        expect(refusPlaces('abc'), refus['modif_places_texte']);
        expect(refusPlaces(''), refus['modif_places_nulles']);
        await modifier(1);
        await modifier(99);
        expect((await dao.vehicule(v.id))!.capacite, 99);
      });

      test('transmission : 255 caractères au plus, vidable', () async {
        expect(
          refusTransmission('x' * 256),
          refus['modif_transmission_longue'],
        );
        expect(refusTransmission('x' * 255), isNull);
        final v = await parc();
        await dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'BJ-L3',
          categorie: CategorieVehicule.voiture,
          tarifJour: 25000,
          transmission: 'Manuelle',
        );
        expect((await dao.vehicule(v.id))!.transmission, 'Manuelle');
        await dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'BJ-L3',
          categorie: CategorieVehicule.voiture,
          tarifJour: 25000,
          transmission: '',
        );
        expect((await dao.vehicule(v.id))!.transmission, isNull);
      });

      test(
        'une saisie qui ne les cite pas LAISSE les trois champs tels quels',
        () async {
          final v = await dao.enregistrerVehicule(
            immatriculation: 'BJ-L3',
            categorie: CategorieVehicule.voiture,
            tarifJour: 25000,
            annee: 2021,
            capacite: 5,
            transmission: 'Manuelle',
          );
          await dao.enregistrerVehicule(
            id: v.id,
            immatriculation: 'BJ-L3',
            categorie: CategorieVehicule.voiture,
            tarifJour: 26000,
          );
          final relu = (await dao.vehicule(v.id))!;
          expect(
            [relu.annee, relu.capacite, relu.transmission],
            [2021, 5, 'Manuelle'],
          );
        },
      );
    },
  );

  group('Contrat : remise, acompte, montant FIGÉ — comme le serveur', () {
    test(
      'remise > brut, acompte > net, négatifs : les phrases du serveur',
      () async {
        final v = await parc();
        await expectLater(
          louer(v, remise: 75001),
          refusDe(refus['remise_superieure_au_brut']),
        );
        await expectLater(
          louer(v, remise: 5000, acompte: 70001),
          refusDe(refus['acompte_superieur_au_net']),
        );
        await expectLater(
          louer(v, remise: -1),
          refusDe(refus['remise_negative']),
        );
        await expectLater(
          louer(v, acompte: -1),
          refusDe(refus['acompte_negatif']),
        );
        // Rien n'est écrit sur un refus, et le véhicule n'est pas passé « loué ».
        expect(await db.select(db.contratsLocationLocal).get(), isEmpty);
        expect((await dao.vehicule(v.id))!.statut, StatutVehicule.disponible);
      },
    );

    test('3 jours x 25 000, remise 5 000, acompte 20 000 : le montant net, '
        'l’acompte et le reste dû sont ceux que le serveur range', () async {
      final v = await parc();
      final c = await louer(v, remise: 5000, acompte: 20000);
      final s = serveur['contrat_ok'] as Map<String, dynamic>;

      expect(c.montant, s['montant']);
      expect(c.acompte, s['acompte']);
      expect(c.resteDu, s['reste_a_payer']);
      expect(c.remise, '5000.00');
      // Le N° vient du serveur : jamais inventé ici.
      expect(c.numero, isNull);
      expect(s['numero_accuse'], startsWith('LOC-'));

      final ligne = (await db.select(db.contratsLocationLocal).get()).single;
      expect(
        [ligne.montant, ligne.remise, ligne.acompte, ligne.numero],
        [70000, 5000, 20000, null],
      );
    });

    test(
      'remise = brut (contrat gratuit) et acompte = net : les bornes passent, '
      'comme au serveur',
      () async {
        final v = await parc();
        final c = await louer(v, remise: 75000);
        final s = serveur['contrat_gratuit'] as Map<String, dynamic>;
        expect([c.montant, c.resteDu], [s['montant'], s['reste_a_payer']]);

        final d = await louer(
          v,
          acompte: 75000,
          debut: '2026-12-01',
          fin: '2026-12-04',
        );
        expect([d.montant, d.resteDu], ['75000.00', '0.00']);
      },
    );

    test(
      'le montant est FIGÉ : le tarif change, le contrat signé non',
      () async {
        final v = await parc();
        await louer(v, remise: 5000);
        await dao.enregistrerVehicule(
          id: v.id,
          immatriculation: 'BJ-L3',
          categorie: CategorieVehicule.voiture,
          tarifJour: 40000,
        );
        expect((await dao.contrats()).single.montant, '70000.00');
      },
    );

    test('le N° `LOC-` posé à l’accusé n’est écrit qu’une fois', () async {
      final v = await parc();
      final c = await louer(v);
      await dao.regulariserNumero(c.id, 'LOC-2026-00001');
      await dao.regulariserNumero(c.id, 'LOC-2026-00002');
      expect((await dao.contrats()).single.numero, 'LOC-2026-00001');
    });
  });

  group('Plat : la catégorie, les dix valeurs du web', () {
    test('le registre du poste est celui de la vue : clés ET libellés', () {
      expect(
        CategorieCarte.values.map((c) => c.code).toList(),
        serveur['categories'],
      );
      final libelles = serveur['categories_libelles'] as Map<String, dynamic>;
      for (final c in CategorieCarte.values) {
        expect(c.libelle, libelles[c.code]);
      }
    });

    test('hors registre, vide : les phrases du serveur', () {
      SaisiePlat saisie(String? categorie) => SaisiePlat(
        libelle: 'Riz',
        menuId: 'm',
        recetteId: 'r',
        prixVente: '1000',
        categorie: categorie,
      );
      expect(
        verifierPlat(saisie('Plats')).erreurs['categorie'],
        refus['categorie_inconnue'],
      );
      expect(
        verifierPlat(saisie('inconnue')).erreurs['categorie'],
        refus['categorie_modif_inconnue'],
      );
      expect(
        verifierPlat(saisie('')).erreurs['categorie'],
        refus['categorie_modif_nulle'],
      );
      expect(
        MessagesRestaurant.categorieDuPlatInvalide,
        refus['categorie_inconnue'],
      );
      expect(
        MessagesRestaurant.categorieDuPlatObligatoire,
        refus['categorie_modif_nulle'],
      );
      for (final c in CategorieCarte.values) {
        expect(verifierPlat(saisie(c.code)).erreurs, isEmpty);
      }
      expect(verifierPlat(saisie(null)).erreurs, isEmpty);
    });
  });

  test('la FILE du poste, poussée au vrai moteur : le serveur range ce que le '
      'poste a saisi (véhicule complet, contrat remisé, plat catégorisé, guide '
      'certifié)', () async {
    final h = DateTime(2026, 10, 27, 10);
    await semerAuteur(db);

    // Le client du contrat existe au serveur avant lui (sa création part d'abord).
    const client = '5f0e3a52-47d8-4f56-a7a3-2f7d9a5e11a1';
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: client,
            nom: 'SABI',
            telephone: '97000009',
            typeClient: 'particulier',
          ),
        );
    await db.transaction(
      () => OperationsSyncDao(db).enfiler(
        table: TableSynchronisee.clients,
        entiteId: client,
        type: TypeOperationSync.creation,
        payload: {
          'nom': 'SABI',
          'telephone': '97000009',
          'type_client': 'particulier',
        },
      ),
    );

    final v = await dao.enregistrerVehicule(
      immatriculation: 'BJ-F-L3',
      categorie: CategorieVehicule.quatreQuatre,
      tarifJour: 25000,
      annee: 2021,
      capacite: 7,
      transmission: 'Automatique',
    );
    final c = await dao.creerContrat(
      SaisieContrat(
        vehiculeId: v.id,
        clientId: client,
        debut: DateTime(2026, 11, 1),
        fin: DateTime(2026, 11, 4),
        pieceIdentite: 'CNI-1',
        permisConduire: 'P-1',
        remiseFrancs: 5000,
        acompteFrancs: 20000,
      ),
    );
    // Une retouche : elle part en MODIFICATION, avec ses seuls champs changés.
    await dao.enregistrerVehicule(
      id: v.id,
      immatriculation: 'BJ-F-L3',
      categorie: CategorieVehicule.quatreQuatre,
      tarifJour: 25000,
      annee: 2022,
      transmission: '',
    );

    final resto = RestaurantDao(
      db,
      stocks: StocksDao(db, maintenant: () => h),
      maintenant: () => h,
    );
    final menu = (await resto.enregistrerMenu(
      const SaisieMenu(libelle: 'Carte L3', type: 'local'),
      auteurId: auteurEssai,
    )).id;
    final fiche = (await resto.enregistrerRecette(
      const SaisieFiche(libelle: 'Fiche L3', lignes: []),
      auteurId: auteurEssai,
    )).id;
    final plat = (await resto.enregistrerPlat(
      SaisiePlat(
        libelle: 'Sandwich L3',
        menuId: menu,
        recetteId: fiche,
        prixVente: '1500',
        categorie: CategorieCarte.sandwicherie.code,
      ),
      modification: false,
      auteurId: auteurEssai,
    )).id;

    final guide = (await TourismeDao(db).enregistrerGuide(
      nom: 'Moussa L3',
      zoneCompetence: 'Atacora',
      certification: 'Guide diplômé',
      tarifJourFrancs: 15000,
    )).id;

    final operations = await fileAuProtocole(db);
    final sortie = await executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-27',
        'poste_id': 'poste-essai-l3',
        'operations': operations,
      },
    );
    expect(sortie['enveloppe'], isEmpty);
    final resultats = [
      for (final r in sortie['resultats'] as List) r as Map<String, dynamic>,
    ];
    for (var i = 0; i < resultats.length; i++) {
      expect(
        resultats[i]['statut'],
        'synchronise',
        reason:
            '${operations[i]['type']} ${operations[i]['table']} : '
            '${resultats[i]['motif']}',
      );
    }
    final etats = sortie['etats'] as Map<String, dynamic>;

    final veh = etats['vehicules:${v.id}'] as Map<String, dynamic>;
    // Créé avec 2021 / 7 / Automatique, puis retouché : 2022, transmission vidée.
    expect(
      [
        int.parse('${veh['annee']}'),
        int.parse('${veh['capacite']}'),
        veh['transmission'],
      ],
      [2022, 7, isNull],
    );

    final contrat = etats['contrats_location:${c.id}'] as Map<String, dynamic>;
    expect(
      [contrat['montant'], contrat['acompte'], contrat['reste_a_payer']],
      ['70000.00', '20000.00', '50000.00'],
    );
    // Le N° `LOC-` rendu à l'accusé est celui que le poste posera.
    final accuse =
        resultats[operations.indexWhere((o) => o['entite_id'] == c.id)];
    expect(accuse['numero'], startsWith('LOC-'));
    expect(contrat['numero'], accuse['numero']);

    expect((etats['plats:$plat'] as Map)['categorie'], 'sandwicherie');

    final g = etats['guides:$guide'] as Map<String, dynamic>;
    expect(
      [g['certification'], g['tarif_jour']],
      ['Guide diplômé', '15000.00'],
    );
    expect(
      sortie['anomalies'],
      isEmpty,
      reason: 'année, tarif du guide donnés : rien à signaler',
    );
  });
}
