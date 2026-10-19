@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/installateur_referentiel.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/plan_comptable_fichier.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// Le plan comptable du PO, embarqué : la COPIE du fichier du serveur, lue par
/// UNE fonction, confrontée à la vraie fonction PHP.
///
/// Le fichier de référence n'est pas un chemin supposé : c'est
/// `ComptabiliteReferentielSeeder::FICHIER_PLAN`, que le script PHP rend.
void main() {
  const fichierServeur =
      '../tatacora-api/database/data/plan-comptable-syscohada-revise.csv';

  group('L’asset est la copie OCTET POUR OCTET du fichier du serveur', () {
    test('mêmes octets, fichier non vide (1 333 lignes : en-tête + 1 332)', () {
      final embarque = File(cheminAssetPlanComptable).readAsBytesSync();
      final serveur = File(fichierServeur).readAsBytesSync();

      // Non vide : une égalité de deux fichiers absents ne prouverait rien.
      expect(embarque.length, greaterThan(50000));
      expect(embarque, serveur);

      final lignes = String.fromCharCodes(
        embarque,
      ).split('\n').where((l) => l.isNotEmpty).length;
      expect(lignes, 1333);
    });

    test(
      'le chemin que le script PHP désigne EST celui qu’on a comparé',
      () async {
        final r = await executerPhp('exporter_referentiel.php');
        // Le seeder dit `data/...` relatif à `database/` : on retrouve le fichier
        // comparé ci-dessus, pas un autre.
        expect(
          fichierServeur.endsWith(r['fichier_plan'] as String),
          isTrue,
          reason: 'le serveur lit ${r['fichier_plan']}',
        );
      },
    );

    test(
      'pubspec.yaml déclare l’asset (sinon rootBundle ne le trouverait pas)',
      () {
        final pubspec = File('pubspec.yaml').readAsStringSync();
        expect(pubspec, contains('- $cheminAssetPlanComptable'));
      },
    );
  });

  group(
    'lirePlanComptable lit le même plan que la vraie fonction du serveur',
    () {
      test('1 332 comptes, couple par couple, dans l’ordre', () async {
        final locaux = lirePlanComptable(lirePlanEmbarque());
        expect(locaux, hasLength(1332));

        final r = await executerPhp('exporter_referentiel.php');
        final serveur = [
          for (final c in r['plan'] as List<dynamic>)
            LigneDuPlan((c as List<dynamic>)[0] as String, c[1] as String),
        ];
        expect(serveur, hasLength(1332));
        expect(locaux, serveur);
      });

      test(
        'le libellé entre guillemets qui contient un « ; » est lu en entier',
        () {
          final comptes = lirePlanComptable(lirePlanEmbarque());
          final c = comptes.firstWhere((c) => c.numero == '5024');
          expect(
            c.libelle,
            'Actions démembrées (certificats d\'investissement ; droits de vote)',
          );
        },
      );

      test('numéros de 1 à 4 chiffres, uniques, sans zéro initial', () {
        final comptes = lirePlanComptable(lirePlanEmbarque());
        expect(comptes.map((c) => c.numero).toSet(), hasLength(1332));
        for (final c in comptes) {
          expect(c.numero, matches(RegExp(r'^[1-9][0-9]{0,3}$')));
        }
      });

      test('les 18 comptes que le code mouvemente existent au plan', () {
        final numeros = lirePlanComptable(
          lirePlanEmbarque(),
        ).map((c) => c.numero).toSet();
        for (final n in const [
          '4111', '4011', '4191', '4431', '4432', '4452', '5711', '5211', //
          '552', '7061', '7011', '6011', '6052', '6051', '6223', '6281',
          '131', '139',
        ]) {
          expect(numeros, contains(n));
        }
      });
    },
  );

  group(
    'Un fichier invalide est refusé avec la phrase et la LIGNE du serveur',
    () {
      String attendu(int ligne) => MessagesComptables.dire(
        'comptabilite.plan_fichier_ligne_invalide',
        {'ligne': '$ligne'},
      );

      void refuse(String contenu, int ligne) {
        try {
          lirePlanComptable(contenu);
          fail('Le fichier devait être refusé à la ligne $ligne.');
        } on RefusComptable catch (e) {
          expect(e.motif, MotifRefus.planFichierInvalide);
          expect(e.message, attendu(ligne));
        }
      }

      test(
        'numéro à zéro initial, libellé vide, champ en trop ou en moins',
        () {
          const entete = 'Code;Libellé\r\n';
          refuse('${entete}0123;Compte\r\n', 2);
          refuse('${entete}1;Bon\r\n2;\r\n', 3);
          refuse('${entete}1;Bon\r\n2;A;B\r\n', 3);
          refuse('${entete}1;Bon\r\n2\r\n', 3);
          refuse('${entete}1;Bon\r\n\r\n2;Deux\r\n', 3);
          refuse('${entete}ABC;Compte\r\n', 2);
        },
      );

      test('le fichier réel dont on vide un libellé est refusé à SA ligne', () {
        // Le plan réel, dont on vide le libellé de la 500e ligne : le refus porte
        // le numéro de cette ligne (l'en-tête est la ligne 1).
        final lignes = lirePlanEmbarque().split('\r\n');
        lignes[499] = '${lignes[499].split(';').first};';
        refuse(lignes.join('\r\n'), 500);
      });

      test('un en-tête seul donne zéro compte, sans refus', () {
        expect(lirePlanComptable('Code;Libellé\r\n'), isEmpty);
      });
    },
  );
}
