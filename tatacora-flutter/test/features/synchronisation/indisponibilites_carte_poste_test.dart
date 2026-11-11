import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/bar/domain/motif_indisponibilite.dart';
import 'package:tatacora_flutter/features/pos/data/indisponibilites_carte_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// Les retraits de la carte du jour, côté poste — 21/10/2026 (« ce que le web
/// fait, le poste le fait »). Le retrait et la remise PARTENT (le serveur
/// fusionne), ceux des autres postes DESCENDENT, et ce qui descend ne remonte
/// pas.
void main() {
  late BancSync b;
  late IndisponibilitesCarteDao dao;
  final instant = DateTime(2026, 10, 21, 9, 30);

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
    dao = IndisponibilitesCarteDao(b.db, horloge: () => instant);
  });
  tearDown(() => b.fermer());

  Future<List<(TypeOperationSync, Map<String, Object?>)>> file() async => [
    for (final o in await b.dao.operations())
      if (o.table == TableSynchronisee.indisponibilitesCarte)
        (o.type, jsonDecode(o.payload) as Map<String, Object?>),
  ];

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(FauxTransport((r) => FauxCatalogue(elements).repondre(r)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  Map<String, Object?> boisson(String id) => element('cartes_boisson', id, {
    'libelle': 'Béninoise $id',
    'categorie': 'locale',
    'prix_vente': '500.00',
    'article_id': null,
  });

  Map<String, Object?> retrait(
    String id, {
    String? boisson,
    String? retour,
    String motif = 'rupture',
  }) => element('indisponibilites_carte', id, {
    'boisson_id': boisson,
    'plat_id': null,
    'motif': motif,
    'commentaire': 'Plus de glace',
    'date_indisponibilite': '2026-10-21 08:00:00',
    'date_retour_disponibilite': retour,
  });

  test('retirer puis remettre : la création part avec le geste, la remise '
      'en est la seule modification', () async {
    final id = await dao.retirer(
      boissonId: 'b-1',
      motif: MotifIndisponibilite.rupture,
      commentaire: ' Plus de glace ',
    );
    expect(id, isNotNull);
    expect(await dao.remettre(boissonId: 'b-1'), isTrue);

    final f = await file();
    expect(f.map((e) => e.$1), [
      TypeOperationSync.creation,
      TypeOperationSync.modification,
    ]);
    expect(f[0].$2, {
      'boisson_id': 'b-1',
      'motif': 'rupture',
      'commentaire': 'Plus de glace',
      'date_indisponibilite': '2026-10-21 09:30:00',
    });
    expect(f[1].$2, {'date_retour_disponibilite': '2026-10-21 09:30:00'});
    expect(await dao.boissonsRetirees(), isEmpty);
  });

  test('un article déjà retiré ne double rien et n’envoie rien ; remettre '
      'sans retrait non plus', () async {
    await dao.retirer(boissonId: 'b-1', motif: MotifIndisponibilite.saison);
    expect(
      await dao.retirer(boissonId: 'b-1', motif: MotifIndisponibilite.retire),
      isNull,
    );
    expect(await file(), hasLength(1));
    expect(await dao.remettre(boissonId: 'b-2'), isFalse);
    expect(await file(), hasLength(1));
  });

  test('un retrait porte sur une boisson OU un plat, jamais les deux', () {
    expect(
      () => dao.retirer(
        boissonId: 'b-1',
        platId: 'p-1',
        motif: MotifIndisponibilite.rupture,
      ),
      throwsArgumentError,
    );
    expect(
      () => dao.retirer(motif: MotifIndisponibilite.rupture),
      throwsArgumentError,
    );
  });

  test('un plat se retire et se remet comme une boisson', () async {
    await dao.retirer(platId: 'p-1', motif: MotifIndisponibilite.rupture);
    expect((await dao.platsRetires()).keys, ['p-1']);
    expect((await file()).single.$2, contains('plat_id'));
    expect(await dao.remettre(platId: 'p-1'), isTrue);
    expect(await dao.platsRetires(), isEmpty);
  });

  test('le retrait d’un autre poste descend, sans rien renvoyer', () async {
    final bilan = await descendre([
      boisson('srv-b1'),
      retrait('srv-i1', boisson: 'srv-b1'),
    ]);
    expect(bilan.refuses, 0, reason: bilan.motifsRefus.join(' ; '));

    final retirees = await dao.boissonsRetirees();
    expect(retirees.keys, ['srv-b1']);
    expect(retirees['srv-b1']?.libelle, 'Rupture du jour');
    expect(retirees['srv-b1']?.commentaire, 'Plus de glace');
    expect(await b.total(), 0, reason: 'ce qui descend ne remonte pas');
  });

  test('la remise faite ailleurs ferme le retrait ici', () async {
    await descendre([boisson('srv-b1'), retrait('srv-i1', boisson: 'srv-b1')]);
    expect(await dao.boissonsRetirees(), isNotEmpty);

    await descendre([
      retrait('srv-i1', boisson: 'srv-b1', retour: '2026-10-21 12:00:00'),
    ]);
    expect(await dao.boissonsRetirees(), isEmpty);
  });

  test('une boisson pas encore reçue fait attendre le retrait, jamais le '
      'refuser', () async {
    final bilan = await descendre([retrait('srv-i1', boisson: 'srv-absente')]);
    expect(bilan.refuses, 0);
    expect(await dao.boissonsRetirees(), isEmpty);
  });

  test('un retrait local déjà parti est remplacé par celui du serveur, un '
      'retrait local encore en file est CONSERVÉ', () async {
    await descendre([boisson('srv-b1')]);

    // Encore en file : l'envoi fera fusionner, aucun doublon avant.
    await dao.retirer(boissonId: 'srv-b1', motif: MotifIndisponibilite.saison);
    await descendre([retrait('srv-i1', boisson: 'srv-b1')]);
    expect((await dao.boissonsRetirees())['srv-b1']?.motif, 'saison');
    expect(
      (await b.db.select(b.db.indisponibilitesCarteLocal).get()).length,
      1,
    );
  });
}
