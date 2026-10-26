import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/crm/data/relances_clients_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/registre_clients.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/relance.dart';
import 'package:tatacora_flutter/features/crm/domain/messages_relance.dart';
import 'package:tatacora_flutter/features/crm/domain/regles_relance.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../facturation/support/outils_encaissement.dart';

/// Les RELANCES d'un client (EF-M3-03) : la règle « à relancer », la validation
/// du montant, et l'écrivain unique `RelancesClientsDao` (écriture locale +
/// file d'envoi dans UNE transaction). Les phrases, elles, sont confrontées au
/// serveur par `messages_relance_test.dart`.
void main() {
  late AppDatabase db;
  final aujourdhui = jourEncaissement; // 12/10/2026 10:00

  setUp(() async => db = await baseEncaissement());
  tearDown(() => db.close());

  RelancesClientsDao dao() =>
      RelancesClientsDao(db, maintenant: () => aujourdhui);

  Future<List<OperationSync>> file() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.relancesClients);

  Map<String, Object?> charge(OperationSync o) =>
      jsonDecode(o.payload) as Map<String, Object?>;

  /* ================================================================== */
  group('« Clients à relancer » (JOURS_AVANT_RELANCE = 30)', () {
    Client client(String id) => Client(
      id: id,
      nom: 'NOM-$id',
      telephone: '97',
      type: TypeClientReferentiel.particulier,
    );

    LigneClient debiteur(String id, {int solde = 500000, DateTime? depuis}) =>
        LigneClient(
          client: client(id),
          soldeCentimes: solde,
          nbPieces: 1,
          plusAncienne: depuis ?? DateTime(2026, 9, 12),
        );

    Relance relance(String clientId, DateTime jour) => Relance(
      id: 'r-$clientId-${jour.toIso8601String()}',
      clientId: clientId,
      clientNom: 'x',
      dateRelance: jour,
      canal: 'telephone',
      montantReclameCentimes: 1,
    );

    test('la constante est celle du serveur', () {
      final source = File(
        '../tatacora-api/app/Pwa/Livewire/Crm/ClientsCreances.php',
      ).readAsStringSync();
      final m = RegExp(r'JOURS_AVANT_RELANCE\s*=\s*(\d+)').firstMatch(source);
      expect(m, isNotNull, reason: 'constante introuvable : garde vide');
      expect(joursAvantRelance, int.parse(m!.group(1)!));
    });

    test('un débiteur jamais relancé est à relancer, avec son ancienneté', () {
      final liste = clientsARelancer(
        registre: [debiteur('a')],
        relances: const [],
        maintenant: aujourdhui,
      );
      expect(liste, hasLength(1));
      expect(liste.single.derniereRelance, isNull);
      expect(liste.single.soldeCentimes, 500000);
      expect(liste.single.ancienneteMaxJours, 30); // 12/09 -> 12/10
    });

    test('la borne : 30 jours EXACTEMENT = relancé récemment (écarté), '
        '31 jours = à relancer', () {
      final liste = clientsARelancer(
        registre: [debiteur('a'), debiteur('b')],
        relances: [
          relance('a', DateTime(2026, 9, 12)), // il y a 30 jours
          relance('b', DateTime(2026, 9, 11)), // il y a 31 jours
        ],
        maintenant: aujourdhui,
      );
      expect(liste.map((c) => c.clientId), ['b']);
      expect(liste.single.derniereRelance, DateTime(2026, 9, 11));
    });

    test('c’est la DERNIÈRE relance qui compte, pas la première', () {
      final liste = clientsARelancer(
        registre: [debiteur('a')],
        relances: [
          relance('a', DateTime(2026, 7, 1)),
          relance('a', DateTime(2026, 10, 1)),
          relance('a', DateTime(2026, 8, 1)),
        ],
        maintenant: aujourdhui,
      );
      expect(liste, isEmpty);
    });

    test('un client sans dette n’est jamais à relancer', () {
      final liste = clientsARelancer(
        registre: [debiteur('a', solde: 0)],
        relances: const [],
        maintenant: aujourdhui,
      );
      expect(liste, isEmpty);
    });

    test('l’ordre est celui du registre (plus gros débiteurs d’abord)', () {
      final liste = clientsARelancer(
        registre: [debiteur('gros', solde: 900000), debiteur('petit')],
        relances: const [],
        maintenant: aujourdhui,
      );
      expect(liste.map((c) => c.clientId), ['gros', 'petit']);
    });
  });

  /* ================================================================== */
  group('Le montant saisi (required | numeric | min:0)', () {
    test('chaque règle sort avec SA phrase, dans l’ordre de Laravel', () {
      expect(lireMontantRelance('').refus, MessagesRelance.montantObligatoire);
      expect(
        lireMontantRelance('  ').refus,
        MessagesRelance.montantObligatoire,
      );
      expect(
        lireMontantRelance(null).refus,
        MessagesRelance.montantObligatoire,
      );
      expect(lireMontantRelance('abc').refus, MessagesRelance.montantIllisible);
      expect(lireMontantRelance('-5').refus, MessagesRelance.montantNegatif);
      // `min:0` se juge sur la valeur EXACTE : -0.004 est négatif.
      expect(
        lireMontantRelance('-0.004').refus,
        MessagesRelance.montantNegatif,
      );
    });

    test('zéro est admis (« positif ou nul »), et la troncature est celle de '
        'bcadd', () {
      expect(lireMontantRelance('0').centimes, 0);
      expect(lireMontantRelance('15000').centimes, 1500000);
      expect(lireMontantRelance('15000.00').centimes, 1500000);
      expect(lireMontantRelance('12.999').centimes, 1299);
      expect(lireMontantRelance('0').refus, isNull);
    });
  });

  /* ================================================================== */
  group('RelancesClientsDao.enregistrer', () {
    test('écrit le fait ET l’enfile, dans une seule transaction', () async {
      final c = await creerClient(db);
      final r = await dao().enregistrer(
        clientId: c.id,
        canal: 'whatsapp',
        montantReclameCentimes: 1500000,
        promesse: DateTime(2026, 10, 30),
        commentaire: '  Rappelle vendredi ',
        auteurLogin: 'amina',
      );

      final ligne = await db.select(db.relancesClientsLocal).getSingle();
      expect(ligne.id, r.id);
      expect(ligne.clientId, c.id);
      expect(ligne.dateRelance, '2026-10-12');
      expect(ligne.canal, 'whatsapp');
      expect(ligne.montantReclameCentimes, 1500000);
      expect(ligne.promesse, '2026-10-30');
      expect(ligne.commentaire, 'Rappelle vendredi');
      expect(ligne.creePar, 'amina');

      final ops = await file();
      expect(ops, hasLength(1));
      expect(ops.single.type, TypeOperationSync.creation);
      expect(ops.single.entiteId, r.id);
      expect(charge(ops.single), {
        'client_id': c.id,
        'date_relance': '2026-10-12',
        'canal': 'whatsapp',
        // Une chaîne décimale EXACTE, jamais un double.
        'montant_reclame': '15000.00',
        'promesse': '2026-10-30',
        'commentaire': 'Rappelle vendredi',
      });
    });

    test('promesse et commentaire absents partent null ; un commentaire vide '
        'est absent', () async {
      final c = await creerClient(db);
      await dao().enregistrer(
        clientId: c.id,
        canal: 'visite',
        montantReclameCentimes: 0,
        commentaire: '   ',
      );
      final p = charge((await file()).single);
      expect(p['promesse'], isNull);
      expect(p['commentaire'], isNull);
      expect(p['montant_reclame'], '0.00');
    });

    test('un canal hors registre est refusé, avec la phrase du serveur, et '
        'RIEN n’est écrit ni enfilé', () async {
      final c = await creerClient(db);
      await expectLater(
        dao().enregistrer(
          clientId: c.id,
          canal: 'pigeon',
          montantReclameCentimes: 100,
        ),
        throwsA(
          isA<RefusRelance>().having(
            (e) => e.message,
            'message',
            MessagesRelance.canalInconnu('pigeon'),
          ),
        ),
      );
      expect(await db.select(db.relancesClientsLocal).get(), isEmpty);
      expect(await file(), isEmpty);
    });

    test('un client inconnu et un montant négatif sont refusés, dans l’ordre '
        'du service', () async {
      await expectLater(
        dao().enregistrer(
          clientId: 'fantome',
          canal: 'telephone',
          montantReclameCentimes: -1,
        ),
        throwsA(
          isA<RefusRelance>().having(
            (e) => e.message,
            'message',
            MessagesRelance.clientInconnu,
          ),
        ),
      );
      final c = await creerClient(db);
      await expectLater(
        dao().enregistrer(
          clientId: c.id,
          canal: 'telephone',
          montantReclameCentimes: -1,
        ),
        throwsA(
          isA<RefusRelance>().having(
            (e) => e.message,
            'message',
            MessagesRelance.montantInvalide,
          ),
        ),
      );
      expect(await db.select(db.relancesClientsLocal).get(), isEmpty);
    });

    test(
      'un client d’AVANT la synchronisation part AVANT sa relance (seq)',
      () async {
        // Écrit par l'ancien code : `local`, aucune création dans la file.
        await db
            .into(db.clientsLocal)
            .insert(
              ClientsLocalCompanion.insert(
                id: 'ancien',
                nom: 'ANCIEN',
                telephone: '96',
                typeClient: 'particulier',
                statutSync: const Value('local'),
              ),
            );
        await dao().enregistrer(
          clientId: 'ancien',
          canal: 'telephone',
          montantReclameCentimes: 100,
        );
        final toutes = await OperationsSyncDao(db).operations();
        expect(
          toutes.map((o) => '${o.type.code} ${o.table.nomServeur}').toList(),
          ['creation clients', 'creation relances_clients'],
        );
      },
    );

    test('un client DESCENDU du serveur n’est pas renvoyé', () async {
      await db
          .into(db.clientsLocal)
          .insert(
            ClientsLocalCompanion.insert(
              id: 'serveur',
              nom: 'SERVEUR',
              telephone: '96',
              typeClient: 'particulier',
              statutSync: const Value('synchronise'),
            ),
          );
      await dao().enregistrer(
        clientId: 'serveur',
        canal: 'telephone',
        montantReclameCentimes: 100,
      );
      final toutes = await OperationsSyncDao(db).operations();
      expect(toutes.map((o) => o.table.nomServeur), ['relances_clients']);
    });
  });

  /* ================================================================== */
  group('Lectures', () {
    test('historique : les plus récentes d’abord, avec le nom du client ; '
        'deClient filtre', () async {
      final a = await creerClient(db, nom: 'ALPHA');
      final b = await creerClient(db, nom: 'BETA', telephone: '2');
      final ancien = RelancesClientsDao(
        db,
        maintenant: () => DateTime(2026, 9, 1),
      );
      await ancien.enregistrer(
        clientId: a.id,
        canal: 'email',
        montantReclameCentimes: 100,
      );
      await dao().enregistrer(
        clientId: b.id,
        canal: 'courrier',
        montantReclameCentimes: 200,
      );

      final h = await dao().historique();
      expect(h.map((r) => r.clientNom), ['BETA', 'ALPHA']);
      expect(h.first.dateRelance, DateTime(2026, 10, 12));
      expect((await dao().deClient(a.id)).single.canal, 'email');
      expect(await dao().toutes(), hasLength(2));
    });

    test(
      'canaux : le registre fermé est celui du serveur, libellés compris',
      () {
        final source = File(
          '../tatacora-api/app/Domain/Crm/Models/RelanceClient.php',
        ).readAsStringSync();
        final bloc = RegExp(r'CANAUX\s*=\s*\[([^\]]*)\]').firstMatch(source);
        expect(bloc, isNotNull, reason: 'RelanceClient::CANAUX introuvable');
        final serveur = RegExp(
          "'([^']+)'",
        ).allMatches(bloc!.group(1)!).map((m) => m.group(1)!).toList();
        expect(serveur, hasLength(5), reason: 'plancher : extraction non vide');
        expect(CanalRelance.values.map((c) => c.code).toList(), serveur);
        // Un canal inconnu se lit comme le téléphone (le `default` de la vue).
        expect(CanalRelance.libelleDe('inconnu'), 'Appel téléphonique');
      },
    );
  });
}
