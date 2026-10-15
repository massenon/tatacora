// Lance PHP (un script FACTICE, sans base) : délai de fichier des tests PHP.
@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/outils_comptabilite.dart';

/// R1 (12/10/2026) : un `setUpAll` PHP échouait sur une `QueryException` que le
/// motif de nouvel essai ne reconnaissait pas. Deux gardes, chacune éprouvée
/// par mutation :
///
///  1. la CAUSE est retirée — un verrou de fichier sérialise les scripts qui
///     touchent à `tatacora_test` ;
///  2. le motif de nouvel essai, qui reste le filet, reconnaît les phrases de
///     contention sur l'un ou l'autre flux, et REFUSE de rejouer une
///     `QueryException` qui n'en est pas une.
/// Un fichier de verrou à ces essais : ils n'attendent pas la file des vrais
/// scripts PHP, qui peut dépasser le délai d'un test pendant la suite complète.
const _verrouEssai = 'tatacora_verrou_essai';

void main() {
  group('Le motif de nouvel essai (contention MySQL)', () {
    test('reconnaît la contention, sur la sortie standard ou d’erreur', () {
      const enveloppe =
          'PHP Fatal error: Uncaught Illuminate\\Database\\QueryException: '
          'SQLSTATE[40001]: Serialization failure: 1213 Deadlock found when '
          'trying to get lock; try restarting transaction (Connection: mysql, '
          'SQL: insert into `roles` ...)';
      expect(estContentionMysql(enveloppe, ''), isTrue);
      expect(estContentionMysql('', enveloppe), isTrue);

      // Les phrases qui n'étaient PAS reconnues avant R1 : le délai d'attente
      // vu sur la sortie d'erreur, l'état SQL seul, l'invite MySQL seule.
      expect(
        estContentionMysql(
          '',
          'SQLSTATE[HY000]: General error: 1205 Lock wait timeout exceeded',
        ),
        isTrue,
      );
      // Chaque marque ISOLÉE : une phrase qui en porte plusieurs ne prouve pas
      // que chacune est reconnue (mutation : retirer 1205 laissait vert).
      expect(
        estContentionMysql('', 'SQLSTATE[HY000]: General error: 1205'),
        isTrue,
      );
      expect(
        estContentionMysql('', 'SQLSTATE[HY000]: General error: 1213'),
        isTrue,
      );
      expect(estContentionMysql('Serialization failure', ''), isTrue);
      expect(estContentionMysql('SQLSTATE[40001]', ''), isTrue);
      expect(estContentionMysql('', 'try restarting transaction'), isTrue);
      expect(estContentionMysql('', 'DeadlockException'), isTrue);
    });

    test('REFUSE de rejouer une QueryException qui n’est pas de la '
        'contention : une requête fausse échoue tout de suite', () {
      expect(
        estContentionMysql(
          '',
          'Illuminate\\Database\\QueryException: SQLSTATE[42S22]: Column not '
              "found: 1054 Unknown column 'x' in 'field list'",
        ),
        isFalse,
      );
      expect(
        estContentionMysql(
          'SQLSTATE[23000]: Integrity constraint violation: 1062 Duplicate '
              'entry',
          '',
        ),
        isFalse,
      );
      expect(estContentionMysql('', ''), isFalse);
    });
  });

  group('Le verrou de la base de test', () {
    test('deux accès simultanés ne se chevauchent JAMAIS', () async {
      // Le verrou est celui du système de fichiers : sous Windows (le poste
      // cible), il est PAR DESCRIPTEUR, donc deux accès d'un même processus
      // s'excluent aussi — c'est ce qui rend ce cas possible sans lancer un
      // second exécutable.
      var enCours = 0;
      var maxSimultanes = 0;
      final journal = <String>[];

      Future<void> acces(String nom) =>
          sousVerrouBaseDeTest(nom: _verrouEssai, () async {
            enCours++;
            if (enCours > maxSimultanes) maxSimultanes = enCours;
            journal.add('entre $nom');
            await Future<void>.delayed(const Duration(milliseconds: 150));
            journal.add('sort $nom');
            enCours--;
          });

      await Future.wait([acces('A'), acces('B'), acces('C')]);

      expect(journal, hasLength(6), reason: 'les trois accès ont eu lieu');
      expect(
        maxSimultanes,
        1,
        reason: 'jamais deux scripts à la fois sur la base : $journal',
      );
    });

    test('le verrou est relâché même quand le travail échoue', () async {
      await expectLater(
        sousVerrouBaseDeTest<void>(
          () async => throw StateError('boum'),
          nom: _verrouEssai,
        ),
        throwsStateError,
      );
      // Si le verrou était resté pris, cet accès attendrait indéfiniment.
      final ok = await sousVerrouBaseDeTest(
        () async => 'repris',
        nom: _verrouEssai,
      ).timeout(const Duration(seconds: 10));
      expect(ok, 'repris');
    });
  });

  // R-B (recontrôle du lot 7, D283) : les deux gardes ci-dessus éprouvent
  // `estContentionMysql` et `sousVerrouBaseDeTest` SÉPARÉMENT. Rien ne prouvait
  // que `executerPhp` les emprunte (piège 5). Ces essais font passer un vrai
  // processus PHP — un script factice qui compte ses exécutions — par
  // `executerPhp` lui-même. Mutations éprouvées : retirer l'appel au verrou
  // dans `executerPhp` rougit le premier cas ; rejouer TOUT échec rougit le
  // deuxième ; ne plus rejouer la contention rougit le troisième.
  group('executerPhp, sur un script FACTICE', () {
    const racine = 'test/features/comptabilite/support';
    const dossier = 'php_factice';
    const script = 'script_factice.php';
    // Un verrou à ces essais : ils n'attendent pas la file des vrais scripts.
    const verrou = 'tatacora_verrou_essai_executer_php';

    late Directory dir;
    late File compteur;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('executer_php_');
      compteur = File('${dir.path}${Platform.pathSeparator}compteur');
    });
    tearDown(() => dir.deleteSync(recursive: true));

    int executions() =>
        compteur.existsSync() ? int.parse(compteur.readAsStringSync()) : 0;

    Future<Map<String, dynamic>> lancer(String mode, {int echecs = 0}) =>
        executerPhp(
          script,
          racine: racine,
          dossier: dossier,
          nomVerrou: verrou,
          entree: {'compteur': compteur.path, 'mode': mode, 'echecs': echecs},
        );

    test('(1) il PREND le verrou : tant qu’un autre le tient, le script ne '
        'part pas', () async {
      final tenu = Completer<void>();
      final relache = Completer<void>();
      final detenteur = sousVerrouBaseDeTest(nom: verrou, () async {
        tenu.complete();
        await relache.future;
      });
      await tenu.future;

      final appel = lancer('succes');
      // Largement plus que le démarrage de PHP : sans verrou, le script a
      // compté son exécution bien avant.
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        executions(),
        0,
        reason: 'le script est parti pendant que le verrou était tenu',
      );

      relache.complete();
      await detenteur;
      final resultat = await appel;
      expect(resultat['execution'], 1);
      expect(executions(), 1);
    });

    test('(2) un échec NON contentionnel n’est PAS rejoué : une seule '
        'exécution, puis l’échec', () async {
      await expectLater(lancer('echec_requete'), throwsA(isA<TestFailure>()));
      expect(executions(), 1);
    });

    test('(3) un échec contentionnel EST rejoué, jusqu’au succès', () async {
      final resultat = await lancer('contention', echecs: 2);
      expect(resultat['execution'], 3);
      expect(executions(), 3);
    });

    test('(3 bis) la contention qui ne cesse pas échoue après quatre '
        'tentatives, pas davantage', () async {
      await expectLater(
        lancer('contention', echecs: 99),
        throwsA(isA<TestFailure>()),
      );
      expect(executions(), 4);
    });
  });
}
