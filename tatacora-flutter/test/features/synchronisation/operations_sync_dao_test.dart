import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

/// `OperationsSyncDao` — le SEUL auteur de la file d'envoi (lot F1).
///
/// L'enfilement dans la transaction de l'écriture métier, le contenu figé, et
/// les aides du moteur d'envoi (F2) : réclamer un lot dans l'ordre, libérer
/// les baux d'un processus tué, consigner les résultats, bloquer ce qui suit
/// un rejet.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late DateTime maintenant;
  late OperationsSyncDao dao;

  setUp(() async {
    db = AppDatabase.enMemoire();
    maintenant = DateTime(2026, 10, 15, 9);
    dao = OperationsSyncDao(db, maintenant: () => maintenant);
  });

  tearDown(() => db.close());

  Future<int> compte() async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM operations_sync_local')
        .getSingle();
    return r.data['n'] as int;
  }

  Future<String?> enfiler(
    String entite, {
    TableSynchronisee table = TableSynchronisee.articles,
    TypeOperationSync type = TypeOperationSync.creation,
    Map<String, Object?> payload = const {'libelle': 'x'},
  }) => db.transaction(
    () => dao.enfiler(
      table: table,
      entiteId: entite,
      type: type,
      payload: payload,
    ),
  );

  group('enfiler', () {
    test('HORS transaction : refusé, rien n’est écrit', () async {
      await expectLater(
        dao.enfiler(
          table: TableSynchronisee.articles,
          entiteId: 'a-1',
          type: TypeOperationSync.creation,
          payload: const {'libelle': 'Riz'},
        ),
        throwsA(isA<StateError>()),
      );
      expect(await compte(), 0);
    });

    test('DANS une transaction : la ligne porte le document figé, au nom de '
        'table du serveur, horodatée en UTC', () async {
      final saisie = DateTime.utc(2026, 10, 14, 21, 30);
      final uuid = await db.transaction(
        () => dao.enfiler(
          table: TableSynchronisee.sessionsCaisse,
          entiteId: 's-1',
          type: TypeOperationSync.creation,
          payload: const {'point_vente': 'bar', 'montant_fond_centimes': 5},
          horodatage: saisie,
          dateMetier: '2026-10-14',
        ),
      );
      final o = (await dao.operations()).single;
      expect(o.uuidOperation, uuid);
      expect(o.table, TableSynchronisee.sessionsCaisse);
      final brute = await db
          .customSelect('SELECT table_serveur FROM operations_sync_local')
          .getSingle();
      expect(brute.data['table_serveur'], 'sessions_caisse');
      expect(o.entiteId, 's-1');
      expect(o.type, TypeOperationSync.creation);
      expect(jsonDecode(o.payload), {
        'point_vente': 'bar',
        'montant_fond_centimes': 5,
      });
      expect(o.horodatageClient, '2026-10-14T21:30:00.000Z');
      expect(o.dateMetier, '2026-10-14');
      expect(o.statut, StatutOperationSync.enAttente);
      expect(o.tentatives, 0);
      expect(o.creeLe, maintenant);
    });

    test('seq est global et croissant ; uuid_operation distinct de '
        'l’identifiant métier', () async {
      final a = await enfiler('e-1');
      final b = await enfiler('e-1', type: TypeOperationSync.modification);
      final c = await enfiler('e-2', table: TableSynchronisee.clients);
      final ops = await dao.operations();
      expect(ops.map((o) => o.uuidOperation), [a, b, c]);
      expect(ops[0].seq < ops[1].seq && ops[1].seq < ops[2].seq, isTrue);
      expect(ops.map((o) => o.uuidOperation).toSet(), hasLength(3));
      expect(ops.every((o) => o.uuidOperation != o.entiteId), isTrue);
    });

    test('une modification sur une table que le serveur ne modifie pas est '
        'REFUSÉE (ventes, dépenses, réservations, achats)', () async {
      for (final t in TableSynchronisee.values.where(
        (t) => !t.accepteModification,
      )) {
        await expectLater(
          enfiler('x', table: t, type: TypeOperationSync.modification),
          throwsA(isA<ArgumentError>()),
          reason: t.nomServeur,
        );
      }
      expect(await compte(), 0);
    });

    test('une modification SANS champ changé n’est pas enfilée ; une '
        'création vide est refusée', () async {
      expect(
        await enfiler(
          'a-1',
          type: TypeOperationSync.modification,
          payload: const {},
        ),
        isNull,
      );
      await expectLater(
        enfiler('a-1', payload: const {}),
        throwsA(isA<ArgumentError>()),
      );
      expect(await compte(), 0);
    });

    test('base de DÉMONSTRATION : rien n’est enfilé', () async {
      final demo = AppDatabase.enMemoire(fileSynchronisation: false);
      final rendu = await demo.transaction(
        () => OperationsSyncDao(demo).enfiler(
          table: TableSynchronisee.articles,
          entiteId: 'a-1',
          type: TypeOperationSync.creation,
          payload: const {'libelle': 'Riz'},
        ),
      );
      expect(rendu, isNull);
      expect(await OperationsSyncDao(demo).operations(), isEmpty);
      await demo.close();
    });

    test('la transaction de l’écrivain défait l’enfilement, et '
        'inversement', () async {
      // L'écriture métier échoue APRÈS l'enfilement : rien ne reste.
      await expectLater(
        db.transaction(() async {
          await dao.enfiler(
            table: TableSynchronisee.pointsStockage,
            entiteId: 'p-1',
            type: TypeOperationSync.creation,
            payload: const {'libelle': 'Bar'},
          );
          throw StateError('panne de l’écriture métier');
        }),
        throwsStateError,
      );
      expect(await compte(), 0);

      // L'enfilement échoue : l'écriture métier est défaite.
      await db.customStatement(
        'CREATE TEMP TRIGGER panne_file BEFORE INSERT ON operations_sync_local '
        "BEGIN SELECT RAISE(ABORT, 'panne de la file'); END",
      );
      await expectLater(
        db.transaction(() async {
          await db.customStatement(
            "INSERT INTO points_stockage_local (id, libelle) VALUES ('p-1', 'Bar')",
          );
          await dao.enfiler(
            table: TableSynchronisee.pointsStockage,
            entiteId: 'p-1',
            type: TypeOperationSync.creation,
            payload: const {'libelle': 'Bar'},
          );
        }),
        throwsA(anything),
      );
      final points = await db
          .customSelect('SELECT COUNT(*) AS n FROM points_stockage_local')
          .getSingle();
      expect(points.data['n'], 0);
    });
  });

  group('le moteur d’envoi (F2) : réclamer, libérer, marquer', () {
    test('réclamer : les plus anciennes, dans l’ordre de seq, sous un lot et '
        'un bail ; tentatives comptées', () async {
      for (var i = 1; i <= 4; i++) {
        await enfiler('e-$i');
      }
      final lot = await dao.reclamerLot(
        taille: 3,
        bail: const Duration(minutes: 2),
        lotId: 'lot-1',
      );
      expect(lot.map((o) => o.entiteId), ['e-1', 'e-2', 'e-3']);
      expect(lot.every((o) => o.statut == StatutOperationSync.enCours), isTrue);
      expect(lot.every((o) => o.lotId == 'lot-1'), isTrue);
      expect(
        lot.every(
          (o) => o.verrouJusqua == maintenant.add(const Duration(minutes: 2)),
        ),
        isTrue,
      );
      expect(lot.every((o) => o.tentatives == 1), isTrue);
      // Le suivant ne reprend pas ce qui est en cours.
      expect((await dao.reclamerLot(lotId: 'lot-2')).single.entiteId, 'e-4');
      expect(await dao.reclamerLot(), isEmpty);
    });

    test('un repli NON ÉCHU arrête la réclamation : un document ne double '
        'jamais ce qu’il cite', () async {
      final article = await enfiler('a-1');
      await enfiler('cmd-1', table: TableSynchronisee.commandesAchat);
      await dao.marquerEchecTransitoire(
        article!,
        erreur: 'réseau',
        delai: const Duration(minutes: 5),
      );
      expect(await dao.reclamerLot(), isEmpty);
      maintenant = maintenant.add(const Duration(minutes: 6));
      expect((await dao.reclamerLot()).map((o) => o.entiteId), [
        'a-1',
        'cmd-1',
      ]);
    });

    test('marquer un échec transitoire : la ligne revient en attente, avec '
        'son erreur et son code', () async {
      final u = await enfiler('a-1');
      await dao.reclamerLot();
      await dao.marquerEchecTransitoire(
        u!,
        erreur: 'Délai dépassé',
        codeHttp: 503,
        delai: const Duration(seconds: 30),
      );
      final o = (await dao.operations()).single;
      expect(o.statut, StatutOperationSync.enAttente);
      expect((o.derniereErreur, o.codeHttp), ('Délai dépassé', 503));
      expect(o.prochaineTentative, maintenant.add(const Duration(seconds: 30)));
      expect((o.lotId, o.verrouJusqua), (null, null));
      expect(o.tentatives, 1);
    });

    test('libérer au démarrage : seuls les baux ÉCHUS redeviennent en '
        'attente', () async {
      await enfiler('e-1');
      await dao.reclamerLot(bail: const Duration(minutes: 2));
      expect(await dao.libererBauxExpires(), 0);
      maintenant = maintenant.add(const Duration(minutes: 3));
      expect(await dao.libererBauxExpires(), 1);
      final o = (await dao.operations()).single;
      expect(o.statut, StatutOperationSync.enAttente);
      expect((o.lotId, o.verrouJusqua), (null, null));
    });

    test(
      'résultat « synchronise » avec fusion : id serveur retenu, résultat '
      'gardé tel quel ; la clôture sans session serveur est un succès',
      () async {
        final a = await enfiler('a-1');
        final s = await enfiler('s-1', table: TableSynchronisee.sessionsCaisse);
        await dao.reclamerLot();
        await dao.marquerResultat(
          a!,
          codeHttp: 200,
          resultat: {
            'uuid_operation': a,
            'statut': 'synchronise',
            'entite_id': 'srv-9',
            'fusionne_avec': 'srv-9',
          },
        );
        await dao.marquerResultat(
          s!,
          resultat: {
            'uuid_operation': s,
            'statut': 'cloture_sans_session_serveur',
            'entite_id': 's-1',
          },
        );
        final ops = await dao.operations();
        expect(ops[0].statut, StatutOperationSync.synchronise);
        expect(ops[0].idServeur, 'srv-9');
        expect(ops[0].codeHttp, 200);
        expect(ops[0].synchroniseLe, maintenant);
        expect(
          (jsonDecode(ops[0].resultatJson!) as Map)['fusionne_avec'],
          'srv-9',
        );
        expect(ops[1].statut, StatutOperationSync.synchronise);
        await expectLater(
          dao.marquerResultat(a, resultat: {'statut': 'inconnu'}),
          throwsArgumentError,
        );
      },
    );

    test('un REJET bloque les opérations suivantes du MÊME élément, et elles '
        'seules ; elles ne sont plus jamais réclamées', () async {
      final creation = await enfiler('a-1');
      await enfiler('a-2');
      await dao.reclamerLot(taille: 2);
      await enfiler('a-1', type: TypeOperationSync.modification);
      await enfiler('a-2', type: TypeOperationSync.modification);
      await dao.marquerResultat(
        creation!,
        resultat: {
          'statut': 'rejete',
          'entite_id': 'a-1',
          'motif': 'Le libellé est obligatoire.',
        },
      );
      final ops = await dao.operations();
      expect(ops.map((o) => (o.entiteId, o.statut)), [
        ('a-1', StatutOperationSync.rejete),
        ('a-2', StatutOperationSync.enCours),
        ('a-1', StatutOperationSync.bloque),
        ('a-2', StatutOperationSync.enAttente),
      ]);
      expect(ops[0].derniereErreur, 'Le libellé est obligatoire.');
      expect(ops[2].derniereErreur, contains(creation));
      expect(ops[0].synchroniseLe, isNull);

      // a-2 a une opération en cours : sa suivante attend son tour.
      expect(await dao.reclamerLot(), isEmpty);
      final comptes = await dao.compteParStatut();
      expect(comptes[StatutOperationSync.bloque], 1);
      expect(comptes[StatutOperationSync.conflit], 0);
    });

    test('ouverture puis clôture d’une même caisse partent dans le MÊME lot '
        '(le serveur l’admet), dans l’ordre', () async {
      await enfiler('s-1', table: TableSynchronisee.sessionsCaisse);
      await enfiler('v-1', table: TableSynchronisee.ventes);
      await enfiler(
        's-1',
        table: TableSynchronisee.sessionsCaisse,
        type: TypeOperationSync.modification,
      );
      final lot = await dao.reclamerLot();
      expect(lot.map((o) => '${o.type.code} ${o.table.nomServeur}'), [
        'creation sessions_caisse',
        'creation ventes',
        'modification sessions_caisse',
      ]);
    });
  });

  group('le registre des tables est celui du SERVEUR (relu, pas recopié)', () {
    final racine = Directory('../tatacora-api/app/Shared/Sync');

    test('mêmes tables, même ordre que TABLES_SYNCHRONISABLES', () {
      final registre = File(
        '${racine.path}/Services/RegistreSynchronisation.php',
      ).readAsStringSync();
      final bloc = registre.substring(
        registre.indexOf('TABLES_SYNCHRONISABLES = ['),
        registre.indexOf('];', registre.indexOf('TABLES_SYNCHRONISABLES = [')),
      );
      final tables = [
        for (final m in RegExp(
          r"'([a-z_]+)' => Gestionnaire\w+::class",
        ).allMatches(bloc))
          m.group(1)!,
      ];
      expect(tables, hasLength(greaterThanOrEqualTo(16)));
      expect(TableSynchronisee.values.map((t) => t.nomServeur), tables);
    });

    test('accepteModification relu de chaque gestionnaire', () {
      for (final t in TableSynchronisee.values) {
        final registre = File(
          '${racine.path}/Services/RegistreSynchronisation.php',
        ).readAsStringSync();
        final classe = RegExp(
          "'${t.nomServeur}' => (Gestionnaire\\w+)::class",
        ).firstMatch(registre)!.group(1)!;
        final source = File(
          '${racine.path}/Gestionnaires/$classe.php',
        ).readAsStringSync();
        final accepte =
            source.contains('extends GestionnaireReferentielAbstrait') ||
            RegExp(
              r'function accepteModification\(\): bool\s*\{\s*return true;',
            ).hasMatch(source);
        expect(t.accepteModification, accepte, reason: t.nomServeur);
      }
    });

    test('aucune table d’écritures comptables au registre du poste (D246)', () {
      expect(
        TableSynchronisee.values.where(
          (t) => t.nomServeur.contains('ecriture'),
        ),
        isEmpty,
      );
    });
  });
}
