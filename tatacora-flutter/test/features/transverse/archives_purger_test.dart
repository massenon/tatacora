@Timeout(Duration(minutes: 3))
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/transverse/data/archives_poste.dart';
import 'package:tatacora_flutter/features/transverse/domain/registre_archives.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_import_export.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_archives.dart';
import 'package:tatacora_flutter/features/vehicules/data/vehicule_dao.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../synchronisation/support/scenario_file.dart' show fileAuProtocole;
import 'support/outils_import.dart';

/// A5 « Purger » (28/10/2026) : la purge DÉFINITIVE d'une unité d'hébergement ou
/// d'un véhicule archivé, contre le VRAI composant `ImportExport` / le vrai
/// `RegistreArchivesService` du serveur (`tool/transverse/rejouer_purge.php`),
/// puis son enfilement dans la file d'envoi et l'écran.
///
/// Base d'essai privée : `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  late AppDatabase db;
  late ParcDao parc;
  late VehiculeDao vehicules;
  late ArchivesPoste archives;
  final ids = <String, String>{};

  final aujourdhui = DateTime.now();
  final jourZero = DateTime(aujourdhui.year, aujourdhui.month, aujourdhui.day);
  DateTime jour(int decalage) =>
      DateTime(jourZero.year, jourZero.month, jourZero.day + decalage);

  /// Le monde, décrit UNE fois : les mêmes éléments au serveur (décalages en
  /// jours) et sur le poste.
  final monde = <String, Object?>{
    'unites': [
      {'numero': 'U-OK', 'archivee': true},
      {'numero': 'U-LIBRE', 'archivee': false},
      {'numero': 'U-ADM', 'archivee': true},
      {
        'numero': 'U-ENG',
        'archivee': true,
        'reservations': [
          {'debut': 3, 'fin': 6, 'statut': 'confirmee'},
        ],
      },
      {
        'numero': 'U-PASSEE',
        'archivee': true,
        'reservations': [
          {'debut': -10, 'fin': -7, 'statut': 'terminee'},
        ],
      },
      {
        'numero': 'U-ANNULEE',
        'archivee': true,
        'reservations': [
          {'debut': 3, 'fin': 6, 'statut': 'annulee'},
        ],
      },
      {
        'numero': 'U-DEPART-AUJ',
        'archivee': true,
        'reservations': [
          {'debut': -2, 'fin': 0, 'statut': 'confirmee'},
        ],
      },
    ],
    'vehicules': [
      {'immatriculation': 'V-OK', 'archive': true},
      {'immatriculation': 'V-LIBRE', 'archive': false},
      {'immatriculation': 'V-SUP', 'archive': true},
      {
        'immatriculation': 'V-ENG',
        'archive': true,
        'contrats': [
          {'debut': 0, 'fin': 2, 'numero': 'LOC-1'},
        ],
      },
      {
        'immatriculation': 'V-FIN-AUJ',
        'archive': true,
        'contrats': [
          {'debut': -3, 'fin': 0, 'numero': 'LOC-2'},
        ],
      },
      {
        'immatriculation': 'V-PASSE',
        'archive': true,
        'contrats': [
          {'debut': -10, 'fin': -5, 'numero': 'LOC-3'},
        ],
      },
      {
        'immatriculation': 'V-ANNULE',
        'archive': true,
        'contrats': [
          {'debut': 2, 'fin': 4, 'numero': 'LOC-4', 'annule': true},
        ],
      },
      {'immatriculation': 'V-ENTRETIEN', 'archive': true, 'entretiens': 1},
      {
        'immatriculation': 'V-QUATRE',
        'archive': true,
        'contrats': [
          {'debut': 30, 'fin': 32, 'numero': 'LOC-D'},
          {'debut': 1, 'fin': 3, 'numero': 'LOC-A'},
          {'debut': 20, 'fin': 22, 'numero': 'LOC-C'},
          {'debut': 10, 'fin': 12, 'numero': 'LOC-B'},
        ],
      },
    ],
  };

  Future<void> semerPoste() async {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
    final categorie = await parc.creerCategorie(
      libelle: 'Standard',
      capaciteMax: 2,
      tarifBase: 10000,
    );
    var n = 0;
    for (final u in monde['unites']! as List) {
      final unite = u as Map<String, Object?>;
      final numero = unite['numero']! as String;
      final id = await parc.creerUnite(
        numero: numero,
        categorieId: categorie.id,
      );
      ids[numero] = id;
      for (final r in (unite['reservations'] ?? const []) as List) {
        final resa = r as Map<String, Object?>;
        await db
            .into(db.reservationsLocal)
            .insert(
              ReservationsLocalCompanion.insert(
                id: 'res-${n++}',
                reference: 'RES-$n',
                clientId: 'cli-1',
                uniteId: id,
                dateArrivee: jour(resa['debut']! as int),
                dateDepart: jour(resa['fin']! as int),
                statut: resa['statut']! as String,
                tarifNuit: 10000,
              ),
            );
      }
      if (unite['archivee']! as bool) {
        // Posé en base, comme le serveur le donne : `ParcDao.archiver` refuserait
        // une unité engagée.
        await db.customStatement(
          "UPDATE unites_hebergement_local SET statut = 'hors_service' "
          "WHERE id = '$id'",
        );
      }
    }
    for (final v in monde['vehicules']! as List) {
      final vehicule = v as Map<String, Object?>;
      final plaque = vehicule['immatriculation']! as String;
      final cree = await vehicules.enregistrerVehicule(
        immatriculation: plaque,
        categorie: CategorieVehicule.values.first,
        tarifJour: 20000,
      );
      ids[plaque] = cree.id;
      for (final c in (vehicule['contrats'] ?? const []) as List) {
        final contrat = c as Map<String, Object?>;
        await db
            .into(db.contratsLocationLocal)
            .insert(
              ContratsLocationLocalCompanion.insert(
                id: 'ctr-${n++}',
                vehiculeId: cree.id,
                clientId: 'cli-1',
                dateDebut: jour(contrat['debut']! as int),
                dateFin: jour(contrat['fin']! as int),
                numero: Value(contrat['numero']! as String),
                statut: Value(
                  (contrat['annule'] ?? false) as bool ? 'annule' : null,
                ),
              ),
            );
      }
      for (var i = 0; i < ((vehicule['entretiens'] ?? 0) as int); i++) {
        await db
            .into(db.entretiensVehiculeLocal)
            .insert(
              EntretiensVehiculeLocalCompanion.insert(
                id: 'ent-${n++}',
                vehiculeId: cree.id,
                type: 'entretien',
                date: jour(-30),
                cout: 15000,
              ),
            );
      }
      if (vehicule['archive']! as bool) {
        // L'archivage du poste refuse un véhicule engagé : le statut est posé
        // en base (le monde du serveur est archivé par construction).
        await db.customStatement(
          "UPDATE vehicules_local SET statut = 'hors_service' WHERE id = '${cree.id}'",
        );
      }
    }
    // Les créations / archivages du monde ne sont pas l'objet : la file repart vide.
    await db.customStatement('DELETE FROM operations_sync_local');
  }

  setUp(() async {
    db = await baseImport();
    db.auteurEcriture = () => (login: 'root', poste: 'P1');
    parc = ParcDao(db);
    vehicules = VehiculeDao(db);
    archives = ArchivesPoste(db, parc: parc, vehicules: vehicules);
    ids.clear();
    await semerPoste();
  });

  tearDown(() => db.close());

  Future<bool> existe(String ref) async {
    final id = ids[ref]!;
    final u = await (db.select(
      db.unitesHebergementLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    final v = await (db.select(
      db.vehiculesLocal,
    )..where((x) => x.id.equals(id))).getSingleOrNull();
    return u != null || v != null;
  }

  TypeArchive typeDe(String ref) => ref.startsWith('U-')
      ? TypeArchive.uniteHebergement
      : TypeArchive.vehicule;

  /// Le verdict du poste pour [ref] : `null` = purgé, sinon la phrase du refus.
  Future<String?> purgerAuPoste(String ref) async {
    try {
      await archives.purger(typeDe(ref), ids[ref]!);
      return null;
    } on RefusArchive catch (refus) {
      return refus.message;
    }
  }

  Future<List<OperationSync>> file() => OperationsSyncDao(db).operations();

  group('Contre le VRAI serveur', () {
    late List<Map<String, dynamic>> serveur;
    // U-ADM et V-SUP ne servent qu'au clic (composant) : le service ne les touche pas.
    final refs = [
      for (final u in monde['unites']! as List)
        if ((u as Map<String, Object?>)['numero'] != 'U-ADM')
          u['numero']! as String,
      for (final v in monde['vehicules']! as List)
        if ((v as Map<String, Object?>)['immatriculation'] != 'V-SUP')
          v['immatriculation']! as String,
    ];

    setUpAll(() async {
      final ops = <Map<String, Object?>>[
        for (final r in refs)
          {
            'op': 'service',
            'type': r.startsWith('U-') ? 'unite_hebergement' : 'vehicule',
            'ref': r,
          },
        // Le clic, par le composant : le super_admin purge, l'administrateur non.
        {
          'op': 'composant',
          'type': 'unite_hebergement',
          'ref': 'U-ADM',
          'role': 'administrateur',
        },
        {
          'op': 'composant',
          'type': 'vehicule',
          'ref': 'V-SUP',
          'role': 'super_admin',
        },
        {'op': 'service', 'type': 'vehicule', 'ref': 'ZZZ'},
        {'op': 'libelles'},
      ];
      final r = await executerPhp(
        'rejouer_purge.php',
        dossier: 'transverse',
        entree: {'monde': monde, 'ops': ops},
      );
      serveur = [
        for (final e in r['resultats'] as List) e as Map<String, dynamic>,
      ];
    });

    test('le scénario est assez large pour que la comparaison compte', () {
      final verdicts = [
        for (var i = 0; i < refs.length; i++) serveur[i]['erreur'],
      ];
      expect(verdicts.where((v) => v == null), hasLength(2));
      expect(verdicts.where((v) => v != null), hasLength(refs.length - 2));
      expect(
        verdicts.whereType<String>().toSet().length,
        greaterThanOrEqualTo(4),
        reason: 'non archivé, engagé (unité), engagé (véhicule), cité',
      );
    });

    test('chaque élément : le MÊME verdict, la MÊME phrase', () async {
      final ecarts = <String>[];
      for (var i = 0; i < refs.length; i++) {
        final srv = serveur[i]['erreur'] as String?;
        final poste = await purgerAuPoste(refs[i]);
        if (srv != poste) {
          ecarts.add('${refs[i]}\n  serveur : $srv\n  poste   : $poste');
        }
        expect(
          await existe(refs[i]),
          serveur[i]['existe_apres'],
          reason: '${refs[i]} : existe après',
        );
      }
      expect(ecarts, isEmpty, reason: ecarts.join('\n'));
    });

    test('les trois premiers contrats engagés, dans l’ordre des départs, et '
        '« … » au-delà', () {
      final i = refs.indexOf('V-QUATRE');
      final phrase = serveur[i]['erreur']! as String;
      expect(phrase, contains('Élément engagé dans 4 opération(s)'));
      expect(
        phrase.indexOf('LOC-A'),
        lessThan(phrase.indexOf('LOC-B')),
        reason: 'ordre des départs',
      );
      expect(phrase, isNot(contains('LOC-D')));
      expect(phrase, contains(' …. Il ne peut pas être archivé'));
    });

    test('purger : seul le super administrateur ; l’administrateur est refusé '
        'et rien n’est effacé', () {
      final iAdmin = refs.length;
      expect(serveur[iAdmin]['refus'], isNotNull);
      expect(serveur[iAdmin]['existe_apres'], true);
      final iSuper = refs.length + 1;
      expect(serveur[iSuper]['erreur'], isNull);
      expect(serveur[iSuper]['existe_apres'], false);
    });

    test('un élément inconnu : le serveur lève, le poste refuse en '
        'français', () async {
      expect(serveur[refs.length + 2]['erreur'], contains('No query results'));
      await expectLater(
        archives.purger(TypeArchive.vehicule, 'zzz'),
        throwsA(
          isA<RefusArchive>().having(
            (e) => e.message,
            'message',
            MessagesArchives.elementIntrouvable,
          ),
        ),
      );
      await expectLater(
        archives.purger(TypeArchive.uniteHebergement, 'zzz'),
        throwsA(isA<RefusArchive>()),
      );
    });

    test('le REGISTRE FERMÉ est celui du serveur : les gestionnaires qui '
        'acceptent une suppression sont exactement ceux du poste', () {
      final dossier = Directory(
        '../tatacora-api/app/Shared/Sync/Gestionnaires',
      );
      final serveurAccepte = <String>{};
      for (final f in dossier.listSync().whereType<File>()) {
        final php = f.readAsStringSync();
        if (!RegExp(
          r'function accepteSuppression\(\): bool\s*\{\s*return true;',
        ).hasMatch(php)) {
          continue;
        }
        final table = RegExp(
          r"function table\(\): string\s*\{\s*return '([a-z_]+)';",
        ).firstMatch(php)!.group(1)!;
        serveurAccepte.add(table);
      }
      expect(serveurAccepte, {
        for (final t in TableSynchronisee.values)
          if (t.accepteSuppression) t.nomServeur,
      });
      expect(serveurAccepte, {'unites_hebergement', 'vehicules'});
    });

    test('les mots de la purge sont ceux du serveur', () {
      final mots = (serveur.last['mots'] as Map).cast<String, String>();
      expect(TextesImportExport.actionPurger, mots['action_purger']);
      expect(TextesImportExport.purgeTitre, mots['purge_titre']);
      expect(TextesImportExport.purgeMessage, mots['purge_message']);
      expect(TextesImportExport.purgeDetail, mots['purge_detail']);
      expect(TextesImportExport.purgeConfirmer, mots['purge_confirmer']);
      expect(MessagesArchives.purgee(':element'), mots['archive_purgee']);
    });
  });

  group('La file du poste, poussée au VRAI moteur de synchronisation', () {
    /// Un véhicule créé, archivé puis purgé PAR LES ÉCRIVAINS du poste : sa file
    /// (création, archivage, suppression) est celle qu'enverrait le moteur.
    Future<(String, List<Map<String, Object?>>)> viePuisPurge() async {
      await db.customStatement('DELETE FROM operations_sync_local');
      final v = await vehicules.enregistrerVehicule(
        immatriculation: 'ZZ-999',
        categorie: CategorieVehicule.values.first,
        tarifJour: 20000,
      );
      await vehicules.archiverVehicule(v.id);
      await vehicules.purger(v.id);
      return (v.id, await fileAuProtocole(db));
    }

    Future<Map<String, dynamic>> pousser(
      List<Map<String, Object?>> operations,
      String role,
    ) => executerPhp(
      'valider_charge.php',
      dossier: 'sync',
      entree: {
        'aujourdhui': '2026-10-28',
        'poste_id': 'poste-essai-a5',
        'role': role,
        'operations': operations,
      },
    );

    test('le super_admin : création, archivage et PURGE sont acceptés, le '
        'véhicule n’existe plus au serveur', () async {
      final (id, operations) = await viePuisPurge();
      expect(operations.map((o) => o['type']), [
        'creation',
        'modification',
        'suppression',
      ]);
      final sortie = await pousser(operations, 'super_admin');
      expect(sortie['enveloppe'], isEmpty);
      expect(
        [for (final r in sortie['resultats'] as List) (r as Map)['statut']],
        ['synchronise', 'synchronise', 'synchronise'],
      );
      // PHP rend `[]` quand aucun état n'est relu : le véhicule a disparu.
      final etats = sortie['etats'];
      expect(
        etats is Map && etats.containsKey('vehicules:$id'),
        isFalse,
        reason: 'purgé au serveur',
      );
    });

    test('l’administrateur : la purge est REFUSÉE avec la phrase du serveur, '
        'le véhicule reste archivé au serveur', () async {
      final (id, operations) = await viePuisPurge();
      final sortie = await pousser(operations, 'administrateur');
      final refus = (sortie['resultats'] as List).last as Map<String, dynamic>;
      expect(refus['statut'], 'rejete');
      expect(refus['code_motif'], 'droit_manquant');
      expect(
        refus['motif'],
        'Purge refusée : seul le super administrateur purge définitivement un '
        'élément, et il lui faut le droit d\'écrire dans ce module.',
      );
      expect(
        ((sortie['etats'] as Map)['vehicules:$id'] as Map)['statut'],
        'hors_service',
      );
    });

    test('une table hors registre fermé : le serveur refuse la suppression '
        '(le poste, lui, ne l’enfile même pas)', () async {
      final sortie = await pousser([
        {
          'uuid_operation': '6f1c1f0e-5d3a-4c63-9a52-0a1b2c3d4e5f',
          'table': 'clients',
          'type': 'suppression',
          'entite_id': '7a1c1f0e-5d3a-4c63-9a52-0a1b2c3d4e5f',
          'payload': {'libelle': 'x'},
          'horodatage_client': '2026-10-28T08:00:00Z',
        },
      ], 'super_admin');
      final r = (sortie['resultats'] as List).single as Map<String, dynamic>;
      expect(
        (r['statut'], r['code_motif']),
        ('rejete', 'suppression_non_synchronisable'),
      );
    });
  });

  group('La file d’envoi', () {
    test('une purge enfile UNE suppression (libellé), dans la transaction du '
        'geste', () async {
      expect(await purgerAuPoste('U-OK'), isNull);
      expect(await purgerAuPoste('V-OK'), isNull);
      final f = await file();
      expect(
        [for (final o in f) (o.table, o.type, o.entiteId, o.payload, o.statut)],
        [
          (
            TableSynchronisee.unitesHebergement,
            TypeOperationSync.suppression,
            ids['U-OK'],
            '{"libelle":"U-OK"}',
            StatutOperationSync.enAttente,
          ),
          (
            TableSynchronisee.vehicules,
            TypeOperationSync.suppression,
            ids['V-OK'],
            '{"libelle":"V-OK"}',
            StatutOperationSync.enAttente,
          ),
        ],
      );
      expect(f.first.auteurLogin, 'root');
    });

    test('un refus n’enfile RIEN et n’efface rien', () async {
      for (final ref in ['U-LIBRE', 'U-ENG', 'U-PASSEE', 'V-ENG', 'V-PASSE']) {
        expect(await purgerAuPoste(ref), isNotNull, reason: ref);
        expect(await existe(ref), isTrue, reason: ref);
      }
      expect(await file(), isEmpty);
    });

    test('ATOMICITÉ : une file en panne défait la suppression, une '
        'suppression en panne ne laisse aucune ligne de file', () async {
      for (final (ref, table) in [
        ('U-OK', 'unites_hebergement_local'),
        ('V-OK', 'vehicules_local'),
      ]) {
        await db.customStatement(
          'CREATE TEMP TRIGGER panne_file BEFORE INSERT ON operations_sync_local '
          "BEGIN SELECT RAISE(ABORT, 'panne de la file'); END",
        );
        await expectLater(
          archives.purger(typeDe(ref), ids[ref]!),
          throwsA(anything),
        );
        await db.customStatement('DROP TRIGGER panne_file');
        expect(await existe(ref), isTrue, reason: '$ref : file en panne');

        await db.customStatement(
          'CREATE TEMP TRIGGER panne_metier BEFORE DELETE ON $table '
          "BEGIN SELECT RAISE(ABORT, 'panne de l''écriture'); END",
        );
        await expectLater(
          archives.purger(typeDe(ref), ids[ref]!),
          throwsA(anything),
        );
        await db.customStatement('DROP TRIGGER panne_metier');
        expect(await existe(ref), isTrue);
        expect(await file(), isEmpty, reason: '$ref : écriture en panne');

        expect(
          await purgerAuPoste(ref),
          isNull,
          reason: 'sans panne, ça passe',
        );
        expect(await file(), hasLength(1));
        await db.customStatement('DELETE FROM operations_sync_local');
      }
    });

    test('le registre : une purge retire la ligne des archivées, et la '
        'suppression de la file ne fabrique aucune « restauration »', () async {
      expect(
        (await archives.registre()).archivees.map((e) => e.libelle),
        contains('U-OK'),
      );
      await purgerAuPoste('U-OK');
      final r = await archives.registre();
      expect(r.archivees.map((e) => e.libelle), isNot(contains('U-OK')));
      expect(r.restaurees, isEmpty);
    });

    test('REGISTRE FERMÉ : la file refuse une suppression ailleurs que sur ces '
        'deux tables, ou sans libellé', () async {
      final f = OperationsSyncDao(db);
      Future<void> enfiler(TableSynchronisee t, Map<String, Object?> p) =>
          db.transaction(
            () => f.enfiler(
              table: t,
              entiteId: 'x',
              type: TypeOperationSync.suppression,
              payload: p,
            ),
          );
      for (final t in TableSynchronisee.values) {
        if (t.accepteSuppression) continue;
        await expectLater(
          enfiler(t, {'libelle': 'x'}),
          throwsArgumentError,
          reason: t.nomServeur,
        );
      }
      await expectLater(
        enfiler(TableSynchronisee.vehicules, {}),
        throwsArgumentError,
      );
      expect(
        {
          for (final t in TableSynchronisee.values)
            if (t.accepteSuppression) t.nomServeur,
        },
        {'unites_hebergement', 'vehicules'},
      );
    });
  });

  group('Le droit, relu au geste', () {
    Future<Object?> purgerEn(String role, Map<String, String> droits) async {
      final c = ProviderContainer(
        overrides: surchargesImport(db, droits: droits, role: role),
      );
      addTearDown(c.dispose);
      try {
        await c.read(purgerArchiveProvider)(
          TypeArchive.uniteHebergement,
          ids['U-OK']!,
        );
        return null;
      } on RefusArchive catch (refus) {
        return refus.message;
      }
    }

    test('l’administrateur ne purge pas, même avec le droit d’écrire '
        '(exigerSuperAdmin d’abord)', () async {
      expect(
        await purgerEn('administrateur', droitsImportComplets),
        MessagesArchives.superAdminRequis,
      );
      expect(await existe('U-OK'), isTrue);
      expect(await file(), isEmpty);
    });

    test('« Super Admin » (casse de la session) purge ; sans l’écriture sur '
        'Paramètres, non', () async {
      expect(
        await purgerEn('super_admin', const {'PARAM': 'L'}),
        MessagesArchives.droitManquant,
      );
      expect(await existe('U-OK'), isTrue);
      expect(await purgerEn('Super Admin', droitsImportComplets), isNull);
      expect(await existe('U-OK'), isFalse);
    });
  });

  group('L’écran', () {
    Future<void> monter(
      WidgetTester tester, {
      String role = 'super_admin',
      Map<String, String> droits = droitsImportComplets,
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 2600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: surchargesImport(db, droits: droits, role: role),
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranImportExport()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ie-onglet-restaurer')));
      await tester.pumpAndSettle();
    }

    Key purger(String ref) => Key('ie-archive-purger-${ids[ref]}');

    testWidgets('le super_admin voit une corbeille sur chaque ligne à '
        'restaurer, avec l’infobulle de la vue', (tester) async {
      await tester.runAsync(() async {});
      await monter(tester);
      for (final ref in ['U-OK', 'V-OK', 'U-ENG']) {
        expect(find.byKey(purger(ref)), findsOneWidget, reason: ref);
      }
      expect(
        find.byTooltip('Purger définitivement (administrateur)'),
        findsWidgets,
      );
    });

    testWidgets('l’administrateur NE voit PAS le bouton de purge (PO '
        '03/09/2026) mais garde « Restaurer »', (tester) async {
      await monter(tester, role: 'administrateur');
      expect(find.byKey(purger('U-OK')), findsNothing);
      expect(
        find.byKey(Key('ie-archive-restaurer-${ids['U-OK']}')),
        findsOneWidget,
      );
    });

    testWidgets('« Purger » ouvre la confirmation forte, « Annuler » ne '
        'touche à rien', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(purger('U-OK')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ie-modale-purge')), findsOneWidget);
      expect(find.text('Purger définitivement'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-purge-element'))).data,
        'U-OK',
      );
      expect(
        find.text('Cet élément sera effacé sans retour possible.'),
        findsOneWidget,
      );
      expect(
        find.text(
          "Contrairement à l'archivage, la purge ne laisse aucune trace restaurable.",
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ie-purge-annuler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('ie-modale-purge')), findsNothing);
      expect(await existe('U-OK'), isTrue);
      expect(await file(), isEmpty);
    });

    testWidgets('« Purger » confirmé : toast, ligne retirée, élément effacé, '
        'suppression enfilée', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(purger('U-OK')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ie-purge-confirmer')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ie-modale-purge')), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const Key('ie-archive-purgee')),
                matching: find.byType(Text),
              ),
            )
            .data,
        'U-OK purgé définitivement.',
      );
      expect(find.byKey(purger('U-OK')), findsNothing);
      expect(await existe('U-OK'), isFalse);
      expect((await file()).single.type, TypeOperationSync.suppression);
    });

    testWidgets('un refus MOTIVÉ s’affiche DANS la modale, qui reste '
        'ouverte', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(purger('U-ENG')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ie-purge-confirmer')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('ie-modale-purge')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-purge-refus'))).data,
        startsWith('Élément engagé dans 1 opération(s) : réservation du'),
      );
      expect(await existe('U-ENG'), isTrue);
      expect(await file(), isEmpty);
    });

    testWidgets('sans le droit d’écrire sur Paramètres, la purge est refusée '
        'au geste (le serveur répond 403)', (tester) async {
      await monter(tester, droits: const {'PARAM': 'L'});
      await tester.tap(find.byKey(purger('U-OK')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ie-purge-confirmer')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('ie-purge-refus'))).data,
        MessagesArchives.droitManquant,
      );
      expect(await existe('U-OK'), isTrue);
    });

    testWidgets('une ligne « déjà restaurée » n’offre pas la purge', (
      tester,
    ) async {
      // Un cycle complet par les écrivains (l'archivage du monde est posé en base,
      // sans opération : « restaurée » exige un archivage connu).
      await archives.restaurer(TypeArchive.vehicule, ids['V-OK']!);
      await vehicules.archiverVehicule(ids['V-OK']!);
      await archives.restaurer(TypeArchive.vehicule, ids['V-OK']!);
      await monter(tester);
      await tester.tap(find.byKey(const Key('ie-filtre-archives')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Déjà restaurées').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('ie-archive-badge-${ids['V-OK']}')),
        findsOneWidget,
      );
      expect(find.byKey(purger('V-OK')), findsNothing);
    });
  });
}
