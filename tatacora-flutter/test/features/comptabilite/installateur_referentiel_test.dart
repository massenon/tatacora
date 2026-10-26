@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/comptes_syscohada.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/plan_comptable_fichier.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// L'installation du référentiel : le plan du PO entre en base par UNE fonction,
/// idempotente, et le résultat est identique à celui du vrai
/// `ComptabiliteReferentielSeeder` (PHP exécuté, MySQL, rollback).
void main() {
  late AppDatabase db;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = AppDatabase.enMemoire();
    await db.customStatement('SELECT 1');
  });

  tearDown(() => db.close());

  Future<int> compte(String table) async {
    final r = await db
        .customSelect('SELECT COUNT(*) AS n FROM $table')
        .getSingle();
    return r.data['n'] as int;
  }

  test(
    'la migration crée les tables VIDES : rien n’est semé avant l’installation',
    () async {
      for (final t in [
        'plan_comptable_local',
        'journaux_local',
        'centres_cout_local',
        'exercices_local',
        'ecritures_local',
        'sequences_piece_local',
      ]) {
        expect(await compte(t), 0, reason: t);
      }
    },
  );

  test(
    'première installation : 7 centres, 7 journaux, 1 332 comptes, l’exercice de l’année',
    () async {
      final bilan = await baseInstalleeSur(db, DateTime(2026, 10, 10));

      expect(bilan.centresCrees, 7);
      expect(bilan.journauxCrees, 7);
      expect(bilan.comptesCrees, 1332);
      expect(bilan.comptesAlignes, 0);
      expect(bilan.exerciceSeme, 2026);
      expect(bilan.aRienChange, isFalse);

      expect(await compte('centres_cout_local'), 7);
      expect(await compte('journaux_local'), 7);
      expect(await compte('plan_comptable_local'), 1332);
      expect(await compte('exercices_local'), 1);

      final e = (await ComptabiliteDao(db).exerciceDeLAnnee(2026))!;
      expect(e.dateDebut, '2026-01-01');
      expect(e.dateFin, '2026-12-31');
      expect(e.statut.valeur, 'ouvert');
      expect(
        await compte('ecritures_local'),
        0,
        reason: 'aucune écriture semée',
      );
    },
  );

  test(
    'IDEMPOTENTE : une seconde exécution ne change rien, ni lignes ni identifiants',
    () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      final avant = await db
          .customSelect('SELECT id FROM plan_comptable_local ORDER BY id')
          .get();

      final bilan = await baseInstalleeSur(db, DateTime(2026, 10, 11));
      expect(bilan.aRienChange, isTrue);
      expect(await compte('plan_comptable_local'), 1332);
      expect(await compte('centres_cout_local'), 7);
      expect(await compte('journaux_local'), 7);
      expect(await compte('exercices_local'), 1);

      final apres = await db
          .customSelect('SELECT id FROM plan_comptable_local ORDER BY id')
          .get();
      expect(
        apres.map((r) => r.data['id']).toList(),
        avant.map((r) => r.data['id']).toList(),
      );
    },
  );

  test(
    'le plan installé est CELUI DU FICHIER : numéro, libellé, classe, dans le même ordre',
    () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      final lignes = await db
          .customSelect(
            'SELECT numero_compte, libelle, classe FROM plan_comptable_local '
            'ORDER BY numero_compte',
          )
          .get();
      final attendu = lirePlanComptable(lirePlanEmbarque())
        ..sort((a, b) => a.numero.compareTo(b.numero));
      expect(lignes, hasLength(attendu.length));
      for (var i = 0; i < attendu.length; i++) {
        expect(lignes[i].data['numero_compte'], attendu[i].numero);
        expect(lignes[i].data['libelle'], attendu[i].libelle);
        expect(lignes[i].data['classe'], attendu[i].numero.substring(0, 1));
      }
    },
  );

  test(
    'nature et centre par défaut : 6 = charge, 7 = produit, le reste NULL ; 11 centres',
    () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      Future<List<String?>> natures(String classe) async => [
        for (final r
            in await db
                .customSelect(
                  'SELECT DISTINCT nature FROM plan_comptable_local WHERE classe = ?',
                  variables: [Variable<String>(classe)],
                )
                .get())
          r.data['nature'] as String?,
      ];
      expect(await natures('6'), ['charge']);
      expect(await natures('7'), ['produit']);
      for (final c in ['1', '2', '3', '4', '5', '8', '9']) {
        expect(await natures(c), [null], reason: 'classe $c');
      }

      final dao = ComptabiliteDao(db);
      final centres = {for (final c in await dao.centres()) c.id: c.libelle};
      var avecCentre = 0;
      for (final e in ComptesSyscohada.centreParDefaut.entries) {
        final compte = (await dao.compteParNumero(e.key))!;
        expect(centres[compte.centreCoutDefautId], e.value, reason: e.key);
        avecCentre++;
      }
      expect(avecCentre, 11);
      // Et AUCUN autre compte n'a de centre par défaut.
      final r = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM plan_comptable_local '
            'WHERE centre_cout_defaut_id IS NOT NULL',
          )
          .getSingle();
      expect(r.data['n'], 11);
    },
  );

  test(
    'un compte ALTÉRÉ est réaligné sur le fichier ; une nature déjà posée est gardée',
    () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      await db.customStatement(
        "UPDATE plan_comptable_local SET libelle = 'FALSIFIÉ', classe = '9' "
        "WHERE numero_compte = '6011'",
      );
      await db.customStatement(
        "UPDATE plan_comptable_local SET nature = 'actif' "
        "WHERE numero_compte = '4111'",
      );
      await db.customStatement(
        "UPDATE plan_comptable_local SET nature = 'passif' "
        "WHERE numero_compte = '6012'",
      );

      final bilan = await baseInstalleeSur(db, DateTime(2026, 10, 11));
      expect(bilan.comptesAlignes, 1, reason: 'seul 6011 diffère du fichier');
      final dao = ComptabiliteDao(db);
      final c = (await dao.compteParNumero('6011'))!;
      expect(
        c.libelle,
        lirePlanComptable(
          lirePlanEmbarque(),
        ).firstWhere((l) => l.numero == '6011').libelle,
      );
      expect(c.classe, '6');
      // La nature posée par ailleurs n'est JAMAIS écrasée.
      expect((await dao.compteParNumero('4111'))!.nature, 'actif');
      expect((await dao.compteParNumero('6012'))!.nature, 'passif');
    },
  );

  test(
    'ne supprime JAMAIS un compte : un compte créé à la main survit',
    () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      await db.customStatement(
        'INSERT INTO plan_comptable_local (id, numero_compte, libelle, classe) '
        "VALUES ('x', '6999', 'Compte de l''exploitant', '6')",
      );
      await baseInstalleeSur(db, DateTime(2026, 10, 11));
      expect(await compte('plan_comptable_local'), 1333);
      expect(await ComptabiliteDao(db).compteParNumero('6999'), isNotNull);
    },
  );

  test('un fichier invalide ne laisse RIEN derrière lui', () async {
    try {
      await installerReferentielComptable(
        db,
        contenuPlan: 'Code;Libellé\r\n1;Bon\r\n0099;Mauvais\r\n',
        maintenant: DateTime(2026, 10, 10),
      );
      fail('Le fichier devait être refusé.');
    } on RefusComptable catch (e) {
      expect(e.motif, MotifRefus.planFichierInvalide);
    }
    for (final t in [
      'plan_comptable_local',
      'journaux_local',
      'centres_cout_local',
      'exercices_local',
    ]) {
      expect(await compte(t), 0, reason: t);
    }
  });

  group('L’exercice de l’année COURANTE s’ouvre à chaque démarrage', () {
    test(
      'un poste sans exercice reçoit celui de l’année de l’installation',
      () async {
        final bilan = await baseInstalleeSur(db, DateTime(2027, 1, 1));
        expect(bilan.exerciceSeme, 2027);
        expect(await compte('exercices_local'), 1);
      },
    );

    test(
      'le même jour, une seconde installation n’ouvre RIEN (idempotent)',
      () async {
        await baseInstalleeSur(db, DateTime(2026, 10, 10));
        final bilan = await baseInstalleeSur(db, DateTime(2026, 12, 31));
        expect(bilan.exerciceSeme, isNull);
        expect(await compte('exercices_local'), 1);
      },
    );

    test('31/12 -> 01/01 : le démarrage du premier janvier ouvre 2027, 2026 '
        'reste intact', () async {
      // Décision du lead (D197, option (b)) : sans cela, le poste cesserait de
      // comptabiliser le 01/01/2027. ÉCART ASSUMÉ avec le serveur, qui n'ouvre
      // jamais un exercice tout seul.
      await baseInstalleeSur(db, DateTime(2026, 12, 31));
      final dao = ComptabiliteDao(db);
      expect(await dao.exerciceDeLAnnee(2027), isNull);

      final bilan = await baseInstalleeSur(db, DateTime(2027, 1, 1));
      expect(bilan.exerciceSeme, 2027);
      expect(bilan.aRienChange, isFalse);

      final e2026 = (await dao.exerciceDeLAnnee(2026))!;
      final e2027 = (await dao.exerciceDeLAnnee(2027))!;
      expect(e2026.statut, StatutExercice.ouvert);
      expect(e2027.statut, StatutExercice.ouvert);
      expect(e2027.dateDebut, '2027-01-01');
      expect(e2027.dateFin, '2027-12-31');
      expect(await compte('exercices_local'), 2);

      // Et il est idempotent : un troisième démarrage ne change plus rien.
      final encore = await baseInstalleeSur(db, DateTime(2027, 1, 2));
      expect(encore.exerciceSeme, isNull);
      expect(encore.aRienChange, isTrue);
      expect(await compte('exercices_local'), 2);
    });

    test(
      'un exercice CLÔTURÉ de l’année n’est ni rouvert ni dupliqué',
      () async {
        await baseInstalleeSur(db, DateTime(2026, 10, 10));
        await db.customStatement(
          "UPDATE exercices_local SET statut = 'cloture' WHERE annee = 2026",
        );
        final bilan = await baseInstalleeSur(db, DateTime(2026, 11, 1));
        expect(bilan.exerciceSeme, isNull);
        expect(await compte('exercices_local'), 1);
        expect(
          (await ComptabiliteDao(db).exerciceDeLAnnee(2026))!.statut,
          StatutExercice.cloture,
        );
      },
    );

    test('les années passées ne sont jamais comblées', () async {
      await baseInstalleeSur(db, DateTime(2026, 10, 10));
      await baseInstalleeSur(db, DateTime(2029, 3, 1));
      final annees = [
        for (final e in await ComptabiliteDao(db).exercices()) e.annee,
      ];
      // Ouvrir 2027 et 2028 sur un poste éteint serait un choix comptable.
      expect(annees, [2026, 2029]);
    });
  });

  group('Confrontation au VRAI seeder du serveur (PHP, MySQL, rollback)', () {
    test(
      'le plan installé ici = le plan que le seeder écrit : 1 332 lignes, 5 champs',
      () async {
        await baseInstalleeSur(db, DateTime(2031, 6, 15));
        final r = await executerPhp(
          'rejouer_scenario.php',
          entree: {
            'aujourdhui': '2031-06-15',
            'ops': [
              {'op': 'dump_plan'},
              {'op': 'dump_exercices'},
            ],
          },
        );
        final resultats = r['resultats'] as List<dynamic>;
        final serveur = ((resultats[0] as Map)['plan'] as List<dynamic>)
            .map((l) => (l as List<dynamic>).cast<String?>())
            .toList();
        expect(serveur, hasLength(1332));

        final dao = ComptabiliteDao(db);
        final centres = {for (final c in await dao.centres()) c.id: c.libelle};
        final locaux = await db
            .customSelect(
              'SELECT numero_compte, libelle, classe, nature, '
              'centre_cout_defaut_id FROM plan_comptable_local '
              'ORDER BY numero_compte',
            )
            .get();
        expect(locaux, hasLength(1332));
        for (var i = 0; i < serveur.length; i++) {
          final l = locaux[i].data;
          expect(
            [
              l['numero_compte'],
              l['libelle'],
              l['classe'],
              l['nature'],
              l['centre_cout_defaut_id'] == null
                  ? null
                  : centres[l['centre_cout_defaut_id']],
            ],
            serveur[i],
            reason: 'ligne $i du plan',
          );
        }

        // L'exercice de l'année : le même, semé de la même façon.
        expect((resultats[1] as Map)['exercices'], [
          [2031, 'ouvert'],
        ]);
        final locaux2 = await dao.exercices();
        expect(
          [
            for (final e in locaux2) [e.annee, e.statut.valeur],
          ],
          [
            [2031, 'ouvert'],
          ],
        );
      },
    );
  });
}
