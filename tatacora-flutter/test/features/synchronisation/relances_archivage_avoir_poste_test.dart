import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/crm/data/archivage_clients.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/data/relances_clients_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/faux_transport.dart';

/// 21/10/2026, « tout au complet » : les RELANCES, l'ARCHIVAGE des clients et
/// l'AVOIR PARTIEL, dans les deux sens de la synchronisation.
///
///  * montée : la file reçoit le payload du contrat (relevé du serveur par
///    `charges_relances_archivage_avoir_contre_serveur_test.dart`) ;
///  * descente : une relance, un client archivé ou restauré, un avoir partiel
///    d'un autre poste s'écrivent SANS rien renvoyer ;
///  * régularisation : le numéro `AV-` du serveur se pose sur l'avoir partiel
///    de CE poste, reconnu par son identifiant.
void main() {
  late BancSync b;

  setUp(() async {
    b = await BancSync.creer();
    await b.semerAuteur();
  });
  tearDown(() => b.fermer());

  Future<Map<String, Object?>?> ligne(String table, String id) async =>
      (await b.db
              .customSelect(
                'SELECT * FROM $table WHERE id = ?',
                variables: [Variable.withString(id)],
              )
              .getSingleOrNull())
          ?.data;

  FauxTransport transportDe(FauxCatalogue cat) => FauxTransport(
    (r) => r.methode == 'GET' ? cat.repondre(r) : reponseLot(r),
  );

  Future<BilanDescente> descendre(List<Map<String, Object?>> elements) async {
    await DescenteCatalogueDao(b.db).effacerCurseur();
    return b
        .descente(transportDe(FauxCatalogue(elements)))
        .descendre((await b.lecteur.appairage())!, surRefus: (_) async {});
  }

  Map<String, Object?> client(String id, {bool actif = true}) =>
      element('clients', id, {
        'nom': 'Sabi',
        'prenom': 'Awa',
        'telephone': '96000003',
        'email': null,
        'type_client': 'particulier',
      }, actif: actif);

  Map<String, Object?> relance(
    String id, {
    String clientId = 'cl-1',
    Map<String, Object?> surcharge = const {},
  }) => element('relances_clients', id, {
    'client_id': clientId,
    'date_relance': '2026-10-20',
    'canal': 'whatsapp',
    'montant_reclame': '15000.00',
    'promesse': '2026-10-30',
    'commentaire': 'Rappelle vendredi',
    ...surcharge,
  });

  /* ================================================================== */
  group('Descente des relances', () {
    test('une relance d’un autre poste s’écrit, montant en CENTIMES, sans '
        'auteur, et RIEN n’est renvoyé', () async {
      final bilan = await descendre([client('cl-1'), relance('r-1')]);
      expect((bilan.appliques, bilan.refuses), (2, 0));

      final r = (await ligne('relances_clients_local', 'r-1'))!;
      expect(r['client_id'], 'cl-1');
      expect(r['date_relance'], '2026-10-20');
      expect(r['canal'], 'whatsapp');
      expect(r['montant_reclame_centimes'], 1500000);
      expect(r['promesse'], '2026-10-30');
      expect(r['commentaire'], 'Rappelle vendredi');
      expect(r['cree_par'], isNull, reason: 'le login ne descend pas');
      // Jamais de renvoi : une relance descendue n'enfile rien.
      expect(
        await b.dao.operations(table: TableSynchronisee.relancesClients),
        isEmpty,
      );
    });

    test('la relance avant son client : elle ATTEND, puis s’écrit dans la même '
        'descente', () async {
      final bilan = await descendre([relance('r-1'), client('cl-1')]);
      expect((bilan.appliques, bilan.refuses), (2, 0));
      expect(await ligne('relances_clients_local', 'r-1'), isNotNull);
    });

    test('une relance déjà détenue n’est pas réécrite (un fait ne change '
        'pas)', () async {
      await descendre([client('cl-1'), relance('r-1')]);
      await descendre([
        client('cl-1'),
        relance(
          'r-1',
          surcharge: {'montant_reclame': '1.00', 'canal': 'visite'},
        ),
      ]);
      final r = (await ligne('relances_clients_local', 'r-1'))!;
      expect(r['montant_reclame_centimes'], 1500000);
      expect(r['canal'], 'whatsapp');
    });

    test('canal inconnu, fraction de centime, montant négatif, date illisible '
        ': REFUSÉS et comptés, jamais avalés', () async {
      final bilan = await descendre([
        client('cl-1'),
        relance('r-canal', surcharge: {'canal': 'pigeon'}),
        relance('r-fraction', surcharge: {'montant_reclame': '10.005'}),
        relance('r-negatif', surcharge: {'montant_reclame': '-1.00'}),
        relance('r-date', surcharge: {'date_relance': 'hier'}),
        relance('r-ok', surcharge: {'promesse': null, 'commentaire': null}),
      ]);
      expect((bilan.appliques, bilan.refuses), (2, 4));
      expect(await ligne('relances_clients_local', 'r-ok'), isNotNull);
      for (final id in ['r-canal', 'r-fraction', 'r-negatif', 'r-date']) {
        expect(await ligne('relances_clients_local', id), isNull, reason: id);
      }
    });
  });

  /* ================================================================== */
  group('Descente de l’archivage d’un client', () {
    test('archivé au serveur = archivé ici ; restauré = restauré', () async {
      await descendre([client('cl-1', actif: false)]);
      expect((await ligne('clients_local', 'cl-1'))!['actif'], 0);
      expect(
        (await ClientDao(b.db).parId('cl-1'))!.actif,
        isFalse,
        reason: 'l’entité le lit',
      );
      await descendre([client('cl-1')]);
      expect((await ligne('clients_local', 'cl-1'))!['actif'], 1);
    });

    test('un archivage fait ICI et pas encore parti est CONSERVÉ face à la '
        'version du serveur', () async {
      await descendre([client('cl-1')]);
      // Un client que le serveur connaît (écrit par la descente) : archivé ici.
      await ArchivageClients(
        b.db,
        creances: () async => const [],
      ).archiverUn('cl-1');
      final bilan = await descendre([client('cl-1')]);
      expect(bilan.conservesLocalement, 1);
      expect((await ligne('clients_local', 'cl-1'))!['actif'], 0);
    });

    test('un client descendu n’est pas renvoyé à l’archivage : une seule '
        'opération, {actif:false}', () async {
      await descendre([client('cl-1')]);
      await ArchivageClients(
        b.db,
        creances: () async => const [],
      ).archiverUn('cl-1');
      final ops = await b.dao.operations(table: TableSynchronisee.clients);
      expect(ops, hasLength(1));
      expect(jsonDecode(ops.single.payload), {'actif': false});
    });
  });

  /* ================================================================== */
  group('Montée : la file reçoit le contrat du serveur', () {
    test(
      'relance et archivage de bout en bout dans la file, dans l’ordre',
      () async {
        final c = await ClientDao(b.db).creer(
          nom: 'KORA',
          telephone: '97',
          type: TypeClientReferentiel.particulier,
        );
        await RelancesClientsDao(
          b.db,
          maintenant: () => b.maintenant,
        ).enregistrer(
          clientId: c.id,
          canal: 'visite',
          montantReclameCentimes: 250050,
          auteurLogin: 'amina',
        );
        await ArchivageClients(
          b.db,
          creances: () async => const [],
        ).archiverUn(c.id);

        final ops = await b.dao.operations();
        expect(
          ops.map((o) => '${o.type.code} ${o.table.nomServeur}').toList(),
          [
            'creation clients',
            'creation relances_clients',
            'modification clients',
          ],
        );
        expect(jsonDecode(ops[1].payload), {
          'client_id': c.id,
          'date_relance': '2026-10-15',
          'canal': 'visite',
          'montant_reclame': '2500.50',
          'promesse': null,
          'commentaire': null,
        });
      },
    );

    test(
      'une relance ne se MODIFIE pas : la file la refuse à l’enfilement',
      () async {
        final c = await ClientDao(b.db).creer(
          nom: 'KORA',
          telephone: '97',
          type: TypeClientReferentiel.particulier,
        );
        await expectLater(
          b.db.transaction(
            () => b.dao.enfiler(
              table: TableSynchronisee.relancesClients,
              entiteId: c.id,
              type: TypeOperationSync.modification,
              payload: const {'montant_reclame': '1.00'},
            ),
          ),
          throwsA(anything),
        );
      },
    );
  });

  /* ================================================================== */
  group('Avoir partiel : la régularisation du numéro', () {
    Future<(PieceFacturation, PieceFacturation)> factureEtAvoir() async {
      final dao = FactureDao(b.db, maintenant: () => b.maintenant);
      final f = await dao.emettre(
        const BrouillonFacture(
          origine: OrigineFacture.factureDirecte,
          clientNom: 'KORA',
          lignes: [
            LigneBrouillon(
              module: ModuleFacturable.m5Bar,
              libelle: 'Prestation',
              prixUnitaire: 10000,
              quantite: 1,
            ),
          ],
        ),
      );
      final avoir = await dao.emettreAvoirPartiel(f.id, 3000, 'Geste');
      return (f, avoir);
    }

    test('le payload part avec avoir_id ; le numéro rendu se pose sur CET '
        'avoir, la facture reste émise', () async {
      final (f, avoir) = await factureEtAvoir();
      final ops = await b.dao.operations(table: TableSynchronisee.factures);
      final partiel = ops.last;
      expect(partiel.type, TypeOperationSync.modification);
      expect(jsonDecode(partiel.payload), {
        'montant': 3000,
        'motif': 'Geste',
        'avoir_id': avoir.id,
      });

      final t = FauxTransport((r) {
        if (r.methode == 'GET') return FauxCatalogue(const []).repondre(r);
        return reponseLot(
          r,
          particulier: (o) => {
            'uuid_operation': o['uuid_operation'],
            'statut': 'synchronise',
            'entite_id': o['entite_id'],
            'numero': 'F-2026-00001',
            if ((o['payload'] as Map).containsKey('avoir_id')) ...{
              'numero_avoir': 'AV-2026-00001',
              'avoir_id': (o['payload'] as Map)['avoir_id'],
            },
          },
        );
      });
      await b.manager(t).synchroniserMaintenant();

      final facture = await FactureDao(b.db).parId(f.id);
      expect(facture!.numero, 'F-2026-00001');
      expect(facture.statut, StatutPiece.emise, reason: 'RG-03 : inchangée');
      final localAvoir = await FactureDao(b.db).parId(avoir.id);
      expect(localAvoir!.numero, 'AV-2026-00001');
      expect(localAvoir.avoirDe, 'F-2026-00001');
      expect(
        (await ligne(
          'pieces_facturation_local',
          avoir.id,
        ))!['statut_transmission'],
        'transmise',
      );
    });

    test(
      'un SECOND avoir partiel reçoit SON numéro, pas celui du premier',
      () async {
        final (f, premier) = await factureEtAvoir();
        final second = await FactureDao(
          b.db,
          maintenant: () => b.maintenant,
        ).emettreAvoirPartiel(f.id, 1000, 'Autre geste');
        var rang = 0;
        final t = FauxTransport((r) {
          if (r.methode == 'GET') return FauxCatalogue(const []).repondre(r);
          return reponseLot(
            r,
            particulier: (o) {
              final p = o['payload'] as Map;
              if (!p.containsKey('avoir_id')) return null;
              rang++;
              return {
                'uuid_operation': o['uuid_operation'],
                'statut': 'synchronise',
                'entite_id': o['entite_id'],
                'numero': 'F-2026-00001',
                'numero_avoir': 'AV-2026-0000$rang',
                'avoir_id': p['avoir_id'],
              };
            },
          );
        });
        await b.manager(t).synchroniserMaintenant();

        expect(
          (await FactureDao(b.db).parId(premier.id))!.numero,
          'AV-2026-00001',
        );
        expect(
          (await FactureDao(b.db).parId(second.id))!.numero,
          'AV-2026-00002',
        );
      },
    );

    test('à la descente, l’avoir de CE poste reçoit son numéro par son '
        'identifiant (réponse d’envoi perdue)', () async {
      final (f, avoir) = await factureEtAvoir();
      await FactureDao(b.db).regulariserNumeros(f.id, numero: 'F-2026-00001');
      await descendre([
        element('avoirs', avoir.id, {
          'facture_id': f.id,
          'numero': 'AV-2026-00007',
          'motif': 'Geste',
          'montant': '3000.00',
          'date_emission': '2026-10-15',
        }),
      ]);
      expect((await FactureDao(b.db).parId(avoir.id))!.numero, 'AV-2026-00007');
      // Pas de doublon : une seule pièce-avoir.
      final avoirs = (await FactureDao(b.db).pieces()).where((p) => p.estAvoir);
      expect(avoirs, hasLength(1));
    });

    test('l’avoir PARTIEL d’un autre poste est inscrit, la facture reste '
        'émise', () async {
      final dao = FactureDao(b.db, maintenant: () => b.maintenant);
      final f = await dao.emettre(
        const BrouillonFacture(
          origine: OrigineFacture.factureDirecte,
          clientNom: 'KORA',
          lignes: [
            LigneBrouillon(
              module: ModuleFacturable.m5Bar,
              libelle: 'Prestation',
              prixUnitaire: 10000,
              quantite: 1,
            ),
          ],
        ),
      );
      await dao.regulariserNumeros(f.id, numero: 'F-2026-00001');
      await descendre([
        element('avoirs', 'av-autre', {
          'facture_id': f.id,
          'numero': 'AV-2026-00009',
          'motif': 'Geste du poste B',
          'montant': '4000.00',
          'date_emission': '2026-10-15',
        }),
      ]);
      expect((await dao.parId(f.id))!.statut, StatutPiece.emise);
      final a = (await dao.parId('av-autre'))!;
      expect(a.montantTotal, -4000);
      expect(a.avoirDe, 'F-2026-00001');
    });
  });
}
