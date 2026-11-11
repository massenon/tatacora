import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/rh/data/conges_plannings_dao.dart';
import 'package:tatacora_flutter/features/rh/data/employe_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/conge_planning.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// Plannings et congés, côté poste — 21/10/2026 (« ce que le web fait, le
/// poste le fait »). RG-13 et RG-14 rejouées aux mots du serveur, chaque geste
/// qui PART, et les créneaux / demandes des autres postes qui DESCENDENT sans
/// rien renvoyer.
void main() {
  late BancSync b;
  late EmployeDao rh;
  late CongesPlanningsDao dao;
  late String cuisine;
  late String hebergement;

  // « Aujourd'hui » du poste : figé, car le préavis se compte depuis lui.
  final aujourdhui = DateTime(2026, 10, 21, 9);

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    rh = EmployeDao(b.db);
    await rh.installerServices();
    final services = await b.db.select(b.db.servicesRhLocal).get();
    cuisine = services.firstWhere((s) => s.libelle == 'Restauration').id;
    hebergement = services.firstWhere((s) => s.libelle == 'Hébergement').id;
    dao = CongesPlanningsDao(b.db, maintenant: () => aujourdhui);
  });
  tearDown(() => b.fermer());

  Future<String> embaucher(
    String nom, {
    String? service,
    bool archive = false,
  }) async {
    final e = await rh.creer(
      nom: nom,
      prenom: 'Test',
      poste: 'Cuisinier',
      serviceId: service ?? cuisine,
      dateEmbauche: DateTime(2023, 2, 1),
      salaireBase: 150000,
    );
    if (archive) await rh.archiver(e.id);
    return e.id;
  }

  Future<void> parametrer({String? preavis, String? couverture}) async {
    Future<void> poser(String cle, String valeur) => b.db
        .into(b.db.parametresSystemeLocal)
        .insert(
          ParametresSystemeLocalCompanion.insert(
            cle: cle,
            valeur: valeur,
            modifieLe: aujourdhui,
          ),
        );
    if (preavis != null) {
      await poser(CongesPlanningsDao.cleDelaiPreavis, preavis);
    }
    if (couverture != null) {
      await poser(CongesPlanningsDao.cleCouverture, couverture);
    }
  }

  Future<List<(String, TypeOperationSync, Map<String, Object?>)>> file(
    TableSynchronisee t,
  ) async => [
    for (final o in await b.dao.operations(table: t))
      (o.entiteId, o.type, jsonDecode(o.payload) as Map<String, Object?>),
  ];

  Future<CreneauPlanning> planifier(
    String employe,
    String debut,
    String fin, {
    DateTime? jour,
  }) => dao.planifier(
    employeId: employe,
    serviceId: cuisine,
    date: jour ?? DateTime(2026, 10, 22),
    heureDebut: debut,
    heureFin: fin,
  );

  Matcher refus(String message) => throwsA(
    isA<RefusCongesPlannings>().having((r) => r.message, 'message', message),
  );

  group('RG-13 — planifier', () {
    test(
      'un créneau s’écrit et PART (heures HH:MM, jour AAAA-MM-JJ)',
      () async {
        final e = await embaucher('ADJIBI');
        final c = await planifier(e, '8:00', '12:00');

        expect(
          [c.date, c.heureDebut, c.heureFin],
          ['2026-10-22', '08:00', '12:00'],
        );
        expect(c.employeNom, 'ADJIBI Test');
        expect(c.serviceLibelle, 'Restauration');
        expect(
          (await dao.creneaux(jour: DateTime(2026, 10, 22))).map((x) => x.id),
          [c.id],
        );
        expect(await dao.creneaux(jour: DateTime(2026, 10, 23)), isEmpty);

        final envois = await file(TableSynchronisee.plannings);
        expect(envois, hasLength(1));
        expect(envois.single.$2, TypeOperationSync.creation);
        expect(envois.single.$3, {
          'employe_id': e,
          'service_id': cuisine,
          'service_libelle': 'Restauration',
          'date': '2026-10-22',
          'heure_debut': '08:00',
          'heure_fin': '12:00',
        });
      },
    );

    test('un chevauchement est refusé SANS rien écrire ; une borne commune '
        'et un autre jour passent', () async {
      final e = await embaucher('ADJIBI');
      await planifier(e, '08:00', '12:00');

      await expectLater(
        planifier(e, '11:00', '14:00'),
        refus(MessagesCongesPlannings.chevauchement),
      );
      await expectLater(
        planifier(e, '07:00', '09:00'),
        refus(MessagesCongesPlannings.chevauchement),
      );
      await expectLater(
        planifier(e, '09:00', '10:00'),
        refus(MessagesCongesPlannings.chevauchement),
        reason: 'inclus dans un créneau existant',
      );
      // Adjacent : 12:00 est la borne de l’un ET le début de l’autre.
      await planifier(e, '12:00', '16:00');
      // Autre jour : les mêmes heures ne se recouvrent pas.
      await planifier(e, '08:00', '12:00', jour: DateTime(2026, 10, 23));

      expect(await file(TableSynchronisee.plannings), hasLength(3));
    });

    test('un autre employé peut prendre le même créneau', () async {
      final a = await embaucher('ADJIBI');
      final z = await embaucher('ZINSOU');
      await planifier(a, '08:00', '12:00');
      await planifier(z, '08:00', '12:00');
      expect(await dao.creneaux(jour: DateTime(2026, 10, 22)), hasLength(2));
    });

    test('un employé en congé VALIDÉ ce jour-là (bornes incluses) n’est pas '
        'planifiable ; un congé refusé ou en attente ne bloque pas', () async {
      final e = await embaucher('ADJIBI');
      await parametrer(preavis: '0', couverture: '0');
      final c = await dao.demander(
        employeId: e,
        type: TypeConge.annuel,
        dateDebut: DateTime(2026, 10, 22),
        dateFin: DateTime(2026, 10, 24),
      );
      // En attente : ne bloque pas.
      await planifier(e, '08:00', '09:00');

      await dao.valider(c.id, validateur: 'gerant');
      await expectLater(
        planifier(e, '10:00', '11:00'),
        refus(MessagesCongesPlannings.enConge('2026-10-22')),
      );
      await expectLater(
        planifier(e, '10:00', '11:00', jour: DateTime(2026, 10, 24)),
        refus(MessagesCongesPlannings.enConge('2026-10-24')),
        reason: 'dernier jour inclus',
      );
      await planifier(e, '10:00', '11:00', jour: DateTime(2026, 10, 25));
    });

    test('un employé parti, des heures illisibles et une fin avant le début '
        'sont refusés', () async {
      final parti = await embaucher('PARTI', archive: true);
      final e = await embaucher('ADJIBI');
      await expectLater(
        planifier(parti, '08:00', '09:00'),
        refus(MessagesCongesPlannings.horsEffectif('parti')),
      );
      await expectLater(
        planifier(e, '25:00', '26:00'),
        refus(MessagesCongesPlannings.heureIllisible),
      );
      await expectLater(
        planifier(e, '10:00', '10:00'),
        refus(MessagesCongesPlannings.heureFinAvantDebut),
      );
      await expectLater(
        dao.planifier(
          employeId: null,
          serviceId: cuisine,
          date: DateTime(2026, 10, 22),
          heureDebut: '08:00',
          heureFin: '09:00',
        ),
        refus(MessagesCongesPlannings.employeRequis),
      );
      expect(await file(TableSynchronisee.plannings), isEmpty);
    });
  });

  group('RG-14 — congés', () {
    test('DEMANDER est toujours accepté (même hors délai, sans paramètre) et '
        'PART', () async {
      final e = await embaucher('ADJIBI');
      final c = await dao.demander(
        employeId: e,
        type: TypeConge.maladie,
        dateDebut: DateTime(2026, 10, 21),
        dateFin: DateTime(2026, 10, 23),
      );
      expect(c.statut, StatutConge.enAttente);
      expect(c.jours, 3);

      final envois = await file(TableSynchronisee.conges);
      expect(envois.single.$2, TypeOperationSync.creation);
      expect(envois.single.$3, {
        'employe_id': e,
        'type': 'maladie',
        'date_debut': '2026-10-21',
        'date_fin': '2026-10-23',
      });
    });

    test('une fin avant le début et un employé parti sont refusés', () async {
      final e = await embaucher('ADJIBI');
      final parti = await embaucher('PARTI', archive: true);
      await expectLater(
        dao.demander(
          employeId: e,
          type: TypeConge.annuel,
          dateDebut: DateTime(2026, 10, 25),
          dateFin: DateTime(2026, 10, 24),
        ),
        refus(MessagesCongesPlannings.finAvantDebut),
      );
      await expectLater(
        dao.demander(
          employeId: parti,
          type: TypeConge.annuel,
          dateDebut: DateTime(2026, 10, 25),
          dateFin: DateTime(2026, 10, 26),
        ),
        refus(MessagesCongesPlannings.horsEffectif('parti')),
      );
      expect(await file(TableSynchronisee.conges), isEmpty);
    });

    Future<String> demande(
      String employe, {
      DateTime? debut,
      DateTime? fin,
    }) async => (await dao.demander(
      employeId: employe,
      type: TypeConge.annuel,
      dateDebut: debut ?? DateTime(2026, 11, 2),
      dateFin: fin ?? DateTime(2026, 11, 4),
    )).id;

    test('VALIDER sans paramètre REFUSE : jamais une valeur devinée', () async {
      final e = await embaucher('ADJIBI');
      final id = await demande(e);

      await expectLater(
        dao.valider(id, validateur: 'gerant'),
        refus(
          MessagesCongesPlannings.parametreAbsent('delai_preavis_conge_jours'),
        ),
      );
      await parametrer(preavis: '7');
      await expectLater(
        dao.valider(id, validateur: 'gerant'),
        refus(
          MessagesCongesPlannings.parametreAbsent(
            'couverture_minimale_par_service',
          ),
        ),
      );
      expect((await dao.conges()).single.statut, StatutConge.enAttente);
      expect(await file(TableSynchronisee.conges), hasLength(1));
    });

    test('le préavis se compte en jours depuis aujourd’hui', () async {
      final e = await embaucher('ADJIBI');
      await parametrer(preavis: '15', couverture: '0');
      // Du 02/11 : 12 jours depuis le 21/10.
      final id = await demande(e);
      await expectLater(
        dao.valider(id, validateur: 'gerant'),
        refus(
          MessagesCongesPlannings.preavisInsuffisant(reel: 12, exige: '15'),
        ),
      );

      // Une demande dans le PASSÉ : le réel est ramené à zéro.
      final passe = await demande(
        e,
        debut: DateTime(2026, 10, 1),
        fin: DateTime(2026, 10, 2),
      );
      await expectLater(
        dao.valider(passe, validateur: 'gerant'),
        refus(MessagesCongesPlannings.preavisInsuffisant(reel: 0, exige: '15')),
      );

      // Exactement le préavis : accepté (borne incluse).
      final pile = await demande(
        e,
        debut: DateTime(2026, 11, 5),
        fin: DateTime(2026, 11, 6),
      );
      await dao.valider(pile, validateur: 'gerant');
      expect(
        (await dao.conges()).firstWhere((c) => c.id == pile).statut,
        StatutConge.valide,
      );
    });

    test('la couverture compte l’effectif ACTIF du service, absents validés '
        'déduits', () async {
      final a = await embaucher('ADJIBI');
      final z = await embaucher('ZINSOU');
      final k = await embaucher('KOUASSI');
      await embaucher('AUTRE_SERVICE', service: hebergement);
      await embaucher('PARTI', archive: true);
      await parametrer(preavis: '0', couverture: '2');

      // 3 actifs en cuisine, minimum 2 : un seul congé tient.
      final c1 = await demande(a);
      await dao.valider(c1, validateur: 'gerant');

      // Le second chevauche : restants = 3 - (1 + 1) = 1 < 2.
      final c2 = await demande(
        z,
        debut: DateTime(2026, 11, 4),
        fin: DateTime(2026, 11, 6),
      );
      await expectLater(
        dao.valider(c2, validateur: 'gerant'),
        refus(
          MessagesCongesPlannings.couvertureInsuffisante(
            restants: 1,
            minimum: '2',
          ),
        ),
      );

      // Sur d’autres jours, la couverture tient de nouveau.
      final c3 = await demande(
        k,
        debut: DateTime(2026, 11, 10),
        fin: DateTime(2026, 11, 11),
      );
      await dao.valider(c3, validateur: 'gerant');
    });

    test('VALIDER pose le validateur et PART en modification ; REFUSER garde '
        'la demande ; une décision ne se rejoue pas', () async {
      final a = await embaucher('ADJIBI');
      final z = await embaucher('ZINSOU');
      await parametrer(preavis: '0', couverture: '0');
      final v = await demande(a);
      final r = await demande(z);

      await dao.valider(v, validateur: 'rodrigue');
      await dao.refuser(r, validateur: 'rodrigue');

      final conges = await dao.conges();
      expect(conges, hasLength(2), reason: 'un refus ne supprime rien');
      final cv = conges.firstWhere((c) => c.id == v);
      expect([cv.statut, cv.validateur], [StatutConge.valide, 'rodrigue']);
      expect(conges.firstWhere((c) => c.id == r).statut, StatutConge.refuse);

      await expectLater(
        dao.valider(v, validateur: 'rodrigue'),
        refus(MessagesCongesPlannings.dejaTraite),
      );
      await expectLater(
        dao.refuser(r, validateur: 'rodrigue'),
        refus(MessagesCongesPlannings.dejaTraite),
      );

      final decisions = (await file(
        TableSynchronisee.conges,
      )).where((o) => o.$2 == TypeOperationSync.modification).toList();
      expect(decisions.map((o) => '${o.$1} ${jsonEncode(o.$3)}'), [
        '$v {"statut_validation":"valide"}',
        '$r {"statut_validation":"refuse"}',
      ]);
    });

    test('filtre par statut et décompte des absents du jour', () async {
      final a = await embaucher('ADJIBI');
      await parametrer(preavis: '0', couverture: '0');
      final id = await demande(
        a,
        debut: DateTime(2026, 10, 21),
        fin: DateTime(2026, 10, 22),
      );
      expect(await dao.enCongeLe(DateTime(2026, 10, 21)), 0);
      await dao.valider(id, validateur: 'gerant');
      expect(await dao.enCongeLe(DateTime(2026, 10, 21)), 1);
      expect(await dao.enCongeLe(DateTime(2026, 10, 22)), 1);
      expect(await dao.enCongeLe(DateTime(2026, 10, 23)), 0);

      expect(await dao.conges(statut: StatutConge.enAttente), isEmpty);
      expect(await dao.conges(statut: StatutConge.valide), hasLength(1));
    });
  });

  group('descente', () {
    Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
      await DescenteCatalogueDao(b.db).effacerCurseur();
      return b
          .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
          .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
    }

    Map<String, Object?> service() =>
        element('services', 'srv-s1', {'libelle': 'Cuisine'});

    Map<String, Object?> employe() => element('employes', 'srv-e1', {
      'matricule': 'EMP-2026-00001',
      'nom': 'LAWANI',
      'prenom': 'Sali',
      'poste': 'Chef',
      'service_id': 'srv-s1',
      'date_embauche': '2024-01-01',
      'numero_cnss': null,
      'type_contrat': 'CDI',
      'date_fin_contrat': null,
      'salaire_base': '200000.00',
      'statut': 'actif',
    });

    Map<String, Object?> planning({String fin = '16:00:00'}) =>
        element('plannings', 'srv-p1', {
          'employe_id': 'srv-e1',
          'service_id': 'srv-s1',
          'date': '2026-10-22',
          'heure_debut': '08:00:00',
          'heure_fin': fin,
        });

    Map<String, Object?> conge(String statut) => element('conges', 'srv-c1', {
      'employe_id': 'srv-e1',
      'type': 'annuel',
      'date_debut': '2026-11-02',
      'date_fin': '2026-11-04',
      'statut_validation': statut,
    });

    test('un créneau et une demande d’un autre poste descendent, sans rien '
        'renvoyer', () async {
      final bilan = await descendre([
        planning(),
        conge('en_attente'),
        employe(),
        service(),
      ]);
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

      final creneaux = await dao.creneaux(jour: DateTime(2026, 10, 22));
      expect(creneaux, hasLength(1));
      expect(
        [creneaux.single.heureDebut, creneaux.single.heureFin],
        ['08:00', '16:00'],
        reason: 'HH:MM:SS du serveur ramené à HH:MM',
      );
      expect(creneaux.single.employeNom, 'LAWANI Sali');
      final c = (await dao.conges()).single;
      expect(
        [c.statut, c.jours, c.validateur],
        [StatutConge.enAttente, 3, isNull],
      );
      expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
    });

    test(
      'la décision du serveur descend vers l’avant, jamais en arrière',
      () async {
        await descendre([service(), employe(), conge('en_attente')]);
        expect((await dao.conges()).single.statut, StatutConge.enAttente);

        await descendre([conge('valide')]);
        expect((await dao.conges()).single.statut, StatutConge.valide);

        await descendre([conge('en_attente')]);
        expect(
          (await dao.conges()).single.statut,
          StatutConge.valide,
          reason: 'une demande décidée ne se rouvre pas',
        );
        await descendre([conge('refuse')]);
        expect((await dao.conges()).single.statut, StatutConge.valide);
      },
    );

    test('un employé pas encore reçu fait attendre ; un créneau incohérent '
        'est refusé', () async {
      var bilan = await descendre([planning(), conge('en_attente')]);
      expect(bilan.refuses, 0);
      expect(await dao.conges(), isEmpty);
      expect(await dao.creneaux(jour: DateTime(2026, 10, 22)), isEmpty);

      bilan = await descendre([
        service(),
        employe(),
        planning(fin: '07:00:00'),
      ]);
      expect(bilan.refuses, 1);
      expect(await dao.creneaux(jour: DateTime(2026, 10, 22)), isEmpty);
    });

    test(
      'une décision locale encore en file est CONSERVÉE face au serveur',
      () async {
        await descendre([service(), employe(), conge('en_attente')]);
        await parametrer(preavis: '0', couverture: '0');
        await dao.valider('srv-c1', validateur: 'gerant');

        await descendre([conge('refuse')]);
        expect(
          (await dao.conges()).single.statut,
          StatutConge.valide,
          reason: 'la modification locale attend encore de partir',
        );
      },
    );
  });
}
