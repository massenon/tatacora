import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/immobilisations_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/immobilisations.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/faux_transport.dart';

/// Les immobilisations (M10), côté poste — 21/10/2026. La création PART (une
/// `creation`, jamais de modification, le code du serveur remplace le
/// provisoire) ; celles des autres postes DESCENDENT sans rien renvoyer.
void main() {
  late BancSync b;
  late ImmobilisationsDao dao;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    await baseInstalleeSur(b.db, DateTime(2026, 10, 15));
    dao = ImmobilisationsDao(b.db, auteur: 'gerant');
  });
  tearDown(() => b.fermer());

  Future<List<(String, TypeOperationSync, Map<String, Object?>)>>
  file() async => [
    for (final o in await b.dao.operations(
      table: TableSynchronisee.immobilisations,
    ))
      (o.entiteId, o.type, jsonDecode(o.payload) as Map<String, Object?>),
  ];

  Future<Immobilisation> creer({
    String libelle = 'Toyota Land Cruiser Prado',
    int? valeur = 1200000000,
    int? duree = 5,
    String date = '2026-03-20',
    String? compte = '231',
  }) => dao.creer(
    libelle: libelle,
    valeurOrigineCentimes: valeur,
    dureeAnnees: duree,
    dateMiseService: date,
    compteImmobilisation: compte,
  );

  test('la création écrit la ligne ET la file dans la même transaction, au '
      'contrat du serveur', () async {
    final i = await creer();

    expect(i.code, 'IMMO-2026-00001');
    expect(
      [
        i.libelle,
        i.valeurOrigineCentimes,
        i.dureeAnnees,
        i.compteImmobilisation,
      ],
      ['Toyota Land Cruiser Prado', 1200000000, 5, '231'],
    );
    final ligne = await (b.db.select(b.db.immobilisationsLocal)).getSingle();
    expect(ligne.creePar, 'gerant');

    final envois = await file();
    expect(envois, hasLength(1));
    expect(envois.single.$1, i.id);
    expect(envois.single.$2, TypeOperationSync.creation);
    expect(envois.single.$3, {
      'libelle': 'Toyota Land Cruiser Prado',
      'compte_immobilisation': '231',
      'valeur_origine': 1200000000,
      'date_mise_service': '2026-03-20',
      'duree_annees': 5,
    });
  });

  test('le code suit la séquence de l’ANNÉE de mise en service', () async {
    expect((await creer(date: '2026-01-02')).code, 'IMMO-2026-00001');
    expect((await creer(date: '2026-12-31')).code, 'IMMO-2026-00002');
    expect((await creer(date: '2027-01-01')).code, 'IMMO-2027-00001');
    expect((await creer(date: '2026-06-06')).code, 'IMMO-2026-00003');
  });

  test('un refus n’écrit RIEN : ni ligne, ni opération', () async {
    for (final f in <Future<Immobilisation> Function()>[
      () => creer(libelle: '  '),
      () => creer(valeur: 0),
      () => creer(valeur: null),
      () => creer(duree: null),
      () => creer(duree: 0),
      () => creer(date: '2026-02-31'),
      () => creer(date: ''),
      () => creer(compte: '9999'),
    ]) {
      await expectLater(f(), throwsA(isA<RefusImmobilisation>()));
    }
    expect(await dao.toutes(), isEmpty);
    expect(await file(), isEmpty);
  });

  test(
    'un compte absent est admis (facultatif), un compte connu aussi',
    () async {
      final i = await creer(compte: null);
      expect(i.compteImmobilisation, isNull);
      expect((await file()).single.$3['compte_immobilisation'], isNull);
    },
  );

  test('le code du serveur remplace le provisoire à l’accusé', () async {
    final i = await creer();
    final t = FauxTransport(
      (r) => reponseLot(
        r,
        particulier: (o) => o['entite_id'] == i.id
            ? {
                'uuid_operation': o['uuid_operation'],
                'statut': 'synchronise',
                'entite_id': i.id,
                'code': 'IMMO-2026-00017',
              }
            : null,
      ),
    );
    await b.manager(t).synchroniserMaintenant();
    expect((await dao.toutes()).single.code, 'IMMO-2026-00017');
  });

  Map<String, Object?> serveur(
    String id, {
    String code = 'IMMO-2026-00009',
    String valeur = '500000.00',
    Object? duree = '4',
    String date = '2026-08-01',
  }) => element('immobilisations', id, {
    'code': code,
    'libelle': 'Groupe électrogène',
    'compte_immobilisation': '231',
    'valeur_origine': valeur,
    'date_mise_service': date,
    'duree_annees': duree,
  });

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  test(
    'l’immobilisation d’un autre poste descend, sans rien renvoyer',
    () async {
      final bilan = await descendre([serveur('srv-i1')]);
      expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

      final i = (await dao.toutes()).single;
      expect(
        [i.code, i.valeurOrigineCentimes, i.dureeAnnees, i.dateMiseService],
        ['IMMO-2026-00009', 50000000, 4, '2026-08-01'],
      );
      expect(i.compteImmobilisation, '231');
      expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
      // Le plan est calculé, jamais descendu : 4 ans, mise en service en août.
      expect(planAmortissement(i).lignes.first.prorata, '5/12');
    },
  );

  test('une ligne détenue n’est pas réécrite, sauf son code (celui du serveur '
      'fait foi)', () async {
    final i = await creer();
    // La réponse de l'envoi s'est perdue : la descente rend le code.
    await b.dao.marquerResultat(
      (await b.dao.operations()).single.uuidOperation,
      resultat: const {'statut': 'synchronise'},
      codeHttp: 200,
    );
    final bilan = await descendre([
      serveur(i.id, code: 'IMMO-2026-00021', valeur: '1.00', duree: 1),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final apres = (await dao.toutes()).single;
    expect(apres.code, 'IMMO-2026-00021');
    expect(apres.valeurOrigineCentimes, 1200000000);
    expect(apres.dureeAnnees, 5);
  });

  test('fraction de centime, durée absente, date illisible : refusées, '
      'comptées', () async {
    final bilan = await descendre([
      serveur('srv-a', valeur: '500000.005'),
      serveur('srv-b', duree: null),
      serveur('srv-c', duree: '0'),
      serveur('srv-d', date: 'hier'),
      serveur('srv-e', valeur: '0.00'),
    ]);
    expect(bilan.refuses, 5);
    expect(await dao.toutes(), isEmpty);
  });

  test('une durée du serveur en entier JSON est lue aussi', () async {
    final bilan = await descendre([serveur('srv-f', duree: 6)]);
    expect(bilan.refuses, 0);
    expect((await dao.toutes()).single.dureeAnnees, 6);
  });
}
