import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/documents_autres_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../synchronisation/support/faux_transport.dart';

/// LE BADGE DIT LA VÉRITÉ DE LA FILE (09/11/2026).
///
/// Constat du PO sur deux postes réels : chaque poste voyait SA réservation « En
/// attente d'envoi » alors que l'autre l'avait reçue. Cause : rien, en production,
/// ne posait `synchronise` à l'accusé (seul un test appelait `majStatutSync`), et
/// une modification (service, prix, acompte) ne partait jamais mais remettait la
/// ligne « en attente » à vie.
///
/// Règle prouvée ici, cas par cas : « En attente d'envoi » SEULEMENT tant qu'une
/// opération de CETTE ligne est réellement en file ; « Synchronisée » après
/// l'accusé ; « Refusée » (motif du serveur, et « À traiter ») au rejet.
void main() {
  late BancSync b;
  late ReservationDao dao;

  setUp(() async {
    b = await BancSync.creer();
    dao = ReservationDao(b.db);
    await b.db
        .into(b.db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-1',
            libelle: 'Studio',
            capaciteMax: 2,
            tarifBase: 37500,
          ),
        );
    await b.db
        .into(b.db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-1',
            categorieId: 'cat-1',
            numero: 'S-01',
            statut: 'libre',
          ),
        );
    await b.db
        .into(b.db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'ISSA',
            telephone: '97000001',
            typeClient: 'particulier',
          ),
        );
  });
  tearDown(() => b.fermer());

  LigneService chambre() => const LigneService(
    id: 'l-h',
    service: ServiceReservation.hebergement,
    itemId: 'u-1',
    libelle: 'Studio (S-01)',
    prixUnitaire: 37500,
    quantite: 2,
  );
  LigneService tourisme() => const LigneService(
    id: 'l-t',
    service: ServiceReservation.tourisme,
    itemId: 'circ-1',
    libelle: 'Tanougou',
    prixUnitaire: 5000,
    quantite: 1,
  );

  Reservation fiche({
    int acompte = 0,
    List<LigneService>? lignes,
    StatutSynchronisation sync = StatutSynchronisation.local,
  }) => Reservation(
    id: 'res-1',
    reference: 'LOC-1',
    clientId: 'cli-1',
    clientNom: 'ISSA',
    uniteId: 'u-1',
    periode: PeriodeSejour(
      arrivee: DateTime.utc(2026, 11, 9),
      depart: DateTime.utc(2026, 11, 11),
    ),
    tarifNuit: 37500,
    statut: StatutReservation.enAttente,
    statutSynchronisation: sync,
    creeeLe: DateTime.utc(2026, 11, 9),
    acompte: acompte,
    lignes: lignes ?? [chambre()],
  );

  Future<StatutSynchronisation> badge() async =>
      (await dao.parId('res-1'))!.statutSynchronisation;

  Future<List<OperationSync>> ops() => b.dao.operations(entiteId: 'res-1');

  Future<void> accuser(String uuid, String statut, {String? motif}) =>
      b.dao.marquerResultat(
        uuid,
        resultat: {
          'uuid_operation': uuid,
          'statut': statut,
          'entite_id': 'res-1',
          'motif': ?motif,
        },
        codeHttp: 200,
      );

  Future<void> creer() => dao.creer(fiche(), auteurId: 'inutile');

  test('l’ACCUSÉ pose « Synchronisée » ; tant que l’opération attend, '
      '« En attente d’envoi »', () async {
    await creer();
    expect(await badge(), StatutSynchronisation.local);
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.local, reason: 'en file');

    await accuser((await ops()).single.uuidOperation, 'synchronise');
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.synchronise);
  });

  test('une opération EN COURS d’envoi se dit « Envoi en cours »', () async {
    await creer();
    await b.dao.reclamerLot();
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.enAttente);
  });

  test('une MODIFICATION (service, acompte) est réellement mise en file : '
      'en attente tant qu’elle n’est pas acquittée, puis synchronisée, et elle '
      'porte les champs CHANGÉS seulement', () async {
    await creer();
    await accuser((await ops()).single.uuidOperation, 'synchronise');
    await dao.reconcilierStatutSync('res-1');

    await dao.enregistrer(
      fiche(acompte: 45000, lignes: [chambre(), tourisme()]),
    );
    expect(await badge(), StatutSynchronisation.local);
    final modif = (await ops()).last;
    expect(modif.type, TypeOperationSync.modification);
    final charge = jsonDecode(modif.payload) as Map<String, Object?>;
    expect(charge.keys.toSet(), {'acompte', 'lignes'});
    expect(charge['acompte'], '45000.00');
    expect((charge['lignes']! as List).single, {
      'service': 'tourisme',
      'source_id': 'circ-1',
      'libelle': 'Tanougou',
      'quantite': '1.00',
      'prix_unitaire': '5000.00',
    });

    await accuser(modif.uuidOperation, 'synchronise');
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.synchronise);
  });

  test('la CRÉATION porte ses services (jamais laissés au poste)', () async {
    await dao.creer(
      fiche(lignes: [chambre(), tourisme()]),
      auteurId: 'inutile',
    );
    final charge =
        jsonDecode((await ops()).single.payload) as Map<String, Object?>;
    expect(
      (charge['lignes']! as List).cast<Map<String, Object?>>().map(
        (l) => l['service'],
      ),
      ['tourisme'],
      reason: 'l’hébergement vit sur unite_id et tarif_nuit, pas en ligne',
    );
  });

  test(
    'une « modification » qui ne change rien de ce que le serveur connaît '
    'NE remet PAS la ligne en attente (aucune opération ne partirait)',
    () async {
      await creer();
      await accuser((await ops()).single.uuidOperation, 'synchronise');
      await dao.reconcilierStatutSync('res-1');

      await dao.enregistrer(fiche());
      expect(await badge(), StatutSynchronisation.synchronise);
      expect(await ops(), hasLength(1));
    },
  );

  test('un REFUS est lisible : « Refusée », son motif, et « À traiter » ; '
      'renvoyé, la ligne repasse en attente puis se synchronise', () async {
    await creer();
    final uuid = (await ops()).single.uuidOperation;
    await accuser(
      uuid,
      'rejete',
      motif: 'Cette chambre est déjà réservée sur cette période.',
    );
    await dao.reconcilierStatutSync('res-1');

    final r = (await dao.parId('res-1'))!;
    expect(r.statutSynchronisation, StatutSynchronisation.rejete);
    expect(r.motifRejet, 'Cette chambre est déjà réservée sur cette période.');
    expect(
      [for (final t in await b.dao.aTraiter()) t.operation.entiteId],
      ['res-1'],
    );

    await b.dao.renvoyer(uuid);
    await dao.reconcilierStatutSync('res-1');
    expect(
      await badge(),
      StatutSynchronisation.local,
      reason: 'le renvoi est en file : l’ancien refus est remplacé',
    );

    final renvoi = (await ops()).last;
    await accuser(renvoi.uuidOperation, 'synchronise');
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.synchronise);
  });

  test('une annulation REFUSÉE avant le 09/11/2026 par « ce document a été '
      'saisi sur un autre poste » est RENVOYÉE d’elle-même, une seule fois : '
      'plus rien ne bloque, personne n’a à cliquer « Relancer »', () async {
    await creer();
    await accuser((await ops()).single.uuidOperation, 'synchronise');
    await b.db.transaction(
      () => b.dao.enfiler(
        table: TableSynchronisee.reservations,
        entiteId: 'res-1',
        type: TypeOperationSync.modification,
        payload: {
          'statut': 'annulee',
          'taux': '50.00',
          'mode_remboursement': 'montant',
          'valeur_remboursement': '0.00',
        },
      ),
    );
    final ancienne = (await ops()).last;
    await accuser(
      ancienne.uuidOperation,
      'rejete',
      motif: DocumentsAutresPostes.refus,
    );
    await dao.reconcilierStatutSync('res-1');
    expect(await badge(), StatutSynchronisation.rejete);

    await dao.reconcilierTout();

    final apres = await ops();
    expect(
      apres,
      hasLength(3),
      reason: 'création, ancienne annulation, renvoi',
    );
    final renvoi = apres.last;
    expect(renvoi.statut, StatutOperationSync.enAttente);
    expect(jsonDecode(renvoi.payload)['statut'], 'annulee');
    expect(
      (await b.dao.remplacees()).keys,
      contains(ancienne.uuidOperation),
      reason: 'l’ancien refus reste à l’historique, marqué remplacé',
    );
    expect(
      await badge(),
      StatutSynchronisation.local,
      reason: 'le renvoi est en file : en attente d’envoi, plus « Refusée »',
    );

    // Une seconde passe ne renvoie PAS une seconde fois.
    await dao.reconcilierTout();
    expect(await ops(), hasLength(3));

    // Le refus d'une AUTRE cause n'est jamais renvoyé tout seul.
    await accuser(renvoi.uuidOperation, 'rejete', motif: 'Autre refus.');
    await dao.reconcilierTout();
    expect(await ops(), hasLength(3));
  });

  test(
    'une ligne SANS aucune opération n’est pas déclarée « Synchronisée »',
    () async {
      await dao.enregistrer(fiche());
      await dao.reconcilierStatutSync('res-1');
      expect(await badge(), StatutSynchronisation.local);
    },
  );

  group('rattrapage des lignes modifiées par l’ancienne version', () {
    Future<void> poserCreationAcceptee({required bool avecLignes}) async {
      await b.db.transaction(
        () => b.dao.enfiler(
          table: TableSynchronisee.reservations,
          entiteId: 'res-1',
          type: TypeOperationSync.creation,
          payload: {
            'client_id': 'cli-1',
            'unite_id': 'u-1',
            'date_arrivee': '2026-11-09',
            'date_depart': '2026-11-11',
            'statut': 'en_attente',
            'acompte': '40000.00',
            'tarif_nuit': '37500.00',
            'remise_type': 'aucune',
            'remise_valeur': '0.00',
            'mode_paiement': null,
            'canal': null,
            'lignes': ?(avecLignes ? const <Object?>[] : null),
          },
        ),
      );
      await accuser((await ops()).single.uuidOperation, 'synchronise');
    }

    test('un service ajouté AVANT la correction (créée ici, acceptée, jamais '
        'modifiée au serveur) part : la différence seulement', () async {
      await poserCreationAcceptee(avecLignes: false);
      await dao.enregistrer(
        fiche(acompte: 40000, lignes: [chambre(), tourisme()]),
      );
      // L'état laissé par l'ancienne version : modifié, « local », rien en file.
      await b.db.customStatement(
        "UPDATE reservations_local SET statut_sync = 'local' WHERE id = 'res-1'",
      );
      await b.db.customStatement(
        "DELETE FROM operations_sync_local WHERE type = 'modification'",
      );

      await dao.reconcilierTout();

      final modif = (await ops()).last;
      expect(modif.type, TypeOperationSync.modification);
      final charge = jsonDecode(modif.payload) as Map<String, Object?>;
      expect(charge.keys.toSet(), {'lignes'});
      expect(await badge(), StatutSynchronisation.local);
    });

    test('une ligne identique à ce que le serveur a reçu est simplement '
        '« Synchronisée » (le cas de la réservation créée puis jamais '
        'marquée)', () async {
      await poserCreationAcceptee(avecLignes: true);
      await b.db.customStatement(
        "UPDATE reservations_local SET statut_sync = 'local' WHERE id = 'res-1'",
      );
      // La fiche locale = la création acceptée.
      await dao.enregistrer(fiche(acompte: 40000));
      await b.db.customStatement(
        "UPDATE reservations_local SET statut_sync = 'local' WHERE id = 'res-1'",
      );

      await dao.reconcilierTout();

      expect(await ops(), hasLength(1), reason: 'aucune opération inutile');
      expect(await badge(), StatutSynchronisation.synchronise);
    });

    test('une ligne descendue, « local », sans opération : toute la fiche '
        'part ; une ligne jamais descendue ni envoyée est laissée', () async {
      await dao.enregistrer(fiche(acompte: 40000));
      await b.db.customStatement(
        "UPDATE reservations_local SET statut_sync = 'local' WHERE id = 'res-1'",
      );
      await dao.reconcilierTout();
      expect(await ops(), isEmpty, reason: 'ni envoyée ni reçue : rien');
      expect(await badge(), StatutSynchronisation.local);

      await b.db.customStatement(
        'INSERT INTO origines_documents_local '
        "(table_serveur, entite_id, recu_le) VALUES ('reservations', 'res-1', 0)",
      );
      await dao.reconcilierTout();
      final modif = (await ops()).single;
      expect(
        (jsonDecode(modif.payload) as Map).keys.toSet(),
        containsAll(['unite_id', 'tarif_nuit', 'acompte', 'lignes']),
      );
    });
  });
}
