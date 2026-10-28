import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';

import 'support/outils_comptabilite.dart';

/// Qui écrit, qui appelle (pièges 1, 9 et 11).
///
/// * L'installation du référentiel a un APPELANT : `main.dart`. Un commentaire
///   qui décrit un déclencheur n'est pas un déclencheur — ce test relit le
///   source d'où part l'appel, et fait tourner la chaîne réelle (fournisseur,
///   asset embarqué par `rootBundle`, base, moteur).
/// * Chaque table a ses auteurs, et aucun autre : le balayage de `lib/` le dit.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('L’installation du référentiel a un appelant', () {
    test('main.dart lit referentielComptableProvider au démarrage', () {
      final main = File('lib/main.dart').readAsStringSync();
      expect(main, contains('ref.read(referentielComptableProvider)'));
      expect(main, contains('providers_comptabilite.dart'));
    });

    test(
      'la chaîne réelle : asset -> installation -> moteur -> une pièce',
      () async {
        final db = AppDatabase.enMemoire();
        addTearDown(db.close);
        await db.customStatement('SELECT 1');
        await semerAuteur(db);
        final conteneur = ProviderContainer(
          overrides: [baseLocaleProvider.overrideWithValue(db)],
        );
        addTearDown(conteneur.dispose);

        // On demande LE MOTEUR, sans avoir lu le référentiel : c'est lui qui
        // doit l'attendre. Un moteur servi sur un plan vide répondrait « compte
        // inconnu » à toute pièce. L'asset est lu par `rootBundle` :
        // pubspec.yaml le déclare, ou ceci échoue.
        final moteur = await conteneur.read(moteurComptableProvider.future);
        final dao = conteneur.read(comptabiliteDaoProvider);
        expect(await dao.nombreDeComptes(), 1332);

        // Le bilan mémorisé est celui de CETTE installation (la première).
        final bilan = await conteneur.read(referentielComptableProvider.future);
        expect(bilan.comptesCrees, 1332);
        expect(bilan.centresCrees, 7);
        expect(bilan.journauxCrees, 7);
        expect(bilan.exerciceSeme, DateTime.now().year);

        final restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
        final aujourdhui = formaterDateIso(DateTime.now());
        final piece = await moteur.passerEtValider(
          DemandePiece(
            journal: 'VTE',
            date: aujourdhui,
            libelle: 'Vente du jour',
            lignes: [
              const LigneDemandee(compte: '5711', debitCentimes: 10000),
              LigneDemandee(
                compte: '7061',
                creditCentimes: 10000,
                centreId: restaurant,
              ),
            ],
          ),
          auteurId: auteurEssai,
        );
        expect(piece.first.numeroPiece, 'VTE-${DateTime.now().year}-00001');
        expect(piece.every((l) => l.estValidee), isTrue);
      },
    );

    test('le flavor demo installe le référentiel explicitement, AVANT '
        'l’amorçage', () {
      // Les dépenses du jeu de démonstration sont confrontées au plan avant
      // d'être écrites : installer après l'amorçage les ferait refuser.
      final demo = File('lib/main_demo.dart').readAsStringSync();
      final installation = demo.indexOf('installerReferentielComptable(');
      expect(installation, isNonNegative);
      expect(installation, lessThan(demo.indexOf('amorcerModeDemo(base)')));
      expect(installation, lessThan(demo.indexOf('runApp(')));
    });

    test('le moteur n’est jamais servi avant l’installation', () {
      final src = File(
        'lib/features/comptabilite/presentation/providers_comptabilite.dart',
      ).readAsStringSync();
      final moteur = src.substring(src.indexOf('moteurComptableProvider ='));
      expect(
        moteur.indexOf('await ref.watch(referentielComptableProvider.future)'),
        allOf(
          isNonNegative,
          lessThan(moteur.indexOf('return MoteurComptable(')),
        ),
      );
    });
  });

  group('Chaque table a ses auteurs, et aucun autre (balayage de lib/)', () {
    final fichiers = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
        .map(
          (f) => (
            f.path.replaceAll(r'\', '/'),
            // Le CODE seulement : une phrase de commentaire qui nomme une
            // table n'est pas un accès à cette table.
            f
                .readAsLinesSync()
                .where((l) => !l.trimLeft().startsWith('//'))
                .join('\n'),
          ),
        )
        .toList();

    Set<String> qui(Pattern motif) => {
      for (final (chemin, source) in fichiers)
        if (source.contains(motif)) chemin.split('/').last,
    };

    test('plancher : le balayage a lu l’application entière', () {
      expect(fichiers.length, greaterThan(300));
    });

    test('ecritures_local : le DAO comptable, et lui seul', () {
      // Accès Drift typé.
      expect(qui('.ecrituresLocal'), {'comptabilite_dao.dart'});
      // SQL brut : les quatre triggers de RG-11, et personne d'autre.
      // Lot A1/A3 (28/10/2026) : le DAO LIT par SQL brut (pièces saisies non
      // reprises, anciennes pièces) ; il n'y écrit jamais en SQL brut.
      expect(qui('ecritures_local'), {
        'declencheurs_comptables.dart',
        'comptabilite_dao.dart',
      });
      expect(
        RegExp(
          r'(INSERT\s+INTO|UPDATE|DELETE\s+FROM)\s+ecritures_local',
        ).hasMatch(
          File(
            'lib/features/comptabilite/data/comptabilite_dao.dart',
          ).readAsStringSync(),
        ),
        isFalse,
      );
    });

    test('l’écriture d’une ligne ne s’appelle que par le moteur', () {
      expect(qui('insererEcriture('), {
        'comptabilite_dao.dart',
        'moteur_comptable.dart',
      });
      expect(qui('marquerValidee('), {
        'comptabilite_dao.dart',
        'moteur_comptable.dart',
      });
      expect(qui('allouerRang('), {
        'comptabilite_dao.dart',
        'moteur_comptable.dart',
      });
    });

    test('la séquence : le DAO comptable seul', () {
      expect(qui('.sequencesPieceLocal'), {'comptabilite_dao.dart'});
    });

    test('plan, journaux, centres, exercices : le DAO et l’installateur', () {
      for (final t in [
        '.planComptableLocal',
        '.journauxLocal',
        '.centresCoutLocal',
        '.exercicesLocal',
      ]) {
        expect(
          qui(t).difference({
            'comptabilite_dao.dart',
            'installateur_referentiel.dart',
            // Lot F2b (15/10/2026) : la descente du catalogue RECONNAÎT les
            // centres du serveur et n'en crée un que s'il manque — le seul
            // de ces quatre référentiels qu'elle touche.
            if (t == '.centresCoutLocal') 'aligneur_catalogue.dart',
          }),
          isEmpty,
          reason: t,
        );
        expect(qui(t), isNotEmpty, reason: t);
      }
    });

    test('les DÉPENSES, les ENCAISSEMENTS DE FACTURE, les VENTES du comptoir, '
        'les RÉSERVATIONS (acompte, remboursement) et les RÈGLEMENTS FOURNISSEUR sont les cinq modules qui '
        'appellent le moteur', () {
      // Le premier mouvement d'argent branché (lot 3 de M10), puis
      // l'encaissement de facture (lot 5, 12/10/2026). Chaque module qui s'y
      // ajoutera rouvrira ce test, et donc la question : sa pièce est-elle dans
      // la même transaction que son argent ? Pour les deux premiers, un test
      // dédié le prouve sur le code (`ecrivains_paiements_facture_test.dart`) et
      // sur le comportement (rien n'est écrit quand la pièce est refusée).
      final appelants = qui(
        'MoteurComptable',
      ).difference({'moteur_comptable.dart', 'providers_comptabilite.dart'});
      // Lot 7 (12/10/2026) : le règlement fournisseur (`reglements_fournisseur_dao.dart`,
      // Dr 4011 / Cr trésorerie) rejoint la liste, pièce dans la même transaction.
      // Lot 6 (12/10/2026) : la clôture d'un panier (`panier_dao.dart`) et
      // l'acompte / le remboursement d'une réservation (`reservation_dao.dart`)
      // rejoignent la liste. Chacun est gardé par `pieces_des_mouvements_test.dart`
      // (un seul écrivain du statut, moteur branché en production) et par un test
      // d'atomicité (pièce refusée = rien d'écrit).
      expect(appelants, {
        'depense_dao.dart',
        'paiements_facture_dao.dart',
        'panier_dao.dart',
        'reglements_fournisseur_dao.dart',
        'reservation_dao.dart',
        // Lot F6 (18/10/2026) : la descente TRANSMET le moteur aux DAO de la
        // vente et de l'encaissement, pour la seule contre-passation de la
        // pièce d'un document de CE poste que le serveur a annulé
        // (`annulations_serveur_test.dart`). Elle ne passe aucune pièce
        // elle-même : le miroir (`aligneur_documents.dart`) ne nomme pas le
        // moteur (cas ci-dessous).
        'descente_catalogue.dart',
        'aligneur_catalogue.dart',
        // 26/10/2026 : la CLÔTURE ANNUELLE (`ClotureExerciceLocale`) demande
        // ses deux pièces (CL, AN) et la contre-passation de la réouverture au
        // moteur — ce n'est pas un mouvement d'argent : le résultat et les
        // soldes de bilan sont déjà dans des pièces validées. Elle n'écrit
        // aucune ligne elle-même (`ecrivains_cloture_test.dart`).
        'cloture_exercice_locale.dart',
      });
      expect(qui('moteurComptableProvider'), {
        // Lot A3 : le geste « Envoyer mes anciennes pièces saisies ».
        'envoi_anciennes_pieces.dart',
        'providers_achats.dart',
        'providers_comptabilite.dart',
        'providers_depenses.dart',
        'providers_paiements.dart',
        'providers_pos.dart',
        'providers_hebergement.dart',
        // Lot F6 : la descente reçoit le moteur de production (voir plus haut).
        'providers_synchronisation.dart',
        // Lot J1 (1/4, 14/10/2026) : la modale « Passer une écriture » du hub
        // Comptabilité — l'écriture MANUELLE, comme la modale de la vue
        // (`comptabilite/hub.blade.php` l.292). Ce n'est pas un mouvement
        // d'argent : la pièce EST toute l'écriture, et elle passe par
        // `MoteurComptable.passer` / `passerEtValider`, seul écrivain de
        // `ecritures_local` (aucun accès direct : voir les cas ci-dessus).
        'modale_ecriture.dart',
        // 21/10/2026 : « Créer un compte » et « Ouvrir un exercice » du hub
        // (`MoteurComptable.creerCompte` / `ouvrirExercice`) — des gestes de
        // référentiel, aucun mouvement d'argent, aucune écriture (`hub_plan_clotures_test.dart`).
        'modales_hub_comptabilite.dart',
        // 26/10/2026 : les gestes de la clôture annuelle (onglet « Clôtures »).
        'providers_cloture.dart',
      });
    });

    test(
      'l’écriture d’une dépense SANS pièce n’a qu’un appelant : la démo',
      () {
        expect(qui('enregistrerHistoriqueSansPiece('), {
          'depense_dao.dart',
          'mode_demo.dart',
        });
      },
    );

    test('depenses_local (dont ecriture_id) : le DAO des dépenses l’écrit, '
        'et lui seul', () {
      // Piège 9 : une colonne que personne n'écrit n'est jamais affichée — et
      // une colonne que n'importe qui écrit n'est pas une preuve. `ecriture_id`
      // ne naît que dans la transaction de la pièce.
      //
      // Lot F4 (17/10/2026) : second auteur DÉCLARÉ, le miroir du serveur — la
      // dépense d'un autre poste descend SANS pièce (Q1 du PO) ; il n'écrit
      // jamais `ecriture_id` (cas ci-dessous), et le rattrapage la refuse.
      expect(qui('DepensesLocalCompanion'), {
        'depense_dao.dart',
        'aligneur_documents.dart',
      });
      expect(qui('LignesDepenseLocalCompanion'), {
        'depense_dao.dart',
        'aligneur_documents.dart',
      });
      expect(qui('.depensesLocal'), {
        'depense_dao.dart',
        'aligneur_documents.dart',
      });
    });

    test('le miroir du serveur n’écrit jamais `ecriture_id` ni une pièce', () {
      final code = File(
        'lib/features/synchronisation/data/aligneur_documents.dart',
      ).readAsStringSync();
      expect(code, isNot(contains('ecritureId:')));
      expect(code, isNot(contains('MoteurComptable')));
      expect(code, isNot(contains('passerEtValider')));
    });

    test('aucun client réseau dans le module (zéro réseau)', () {
      for (final (chemin, source) in fichiers) {
        if (!chemin.contains('lib/features/comptabilite/')) continue;
        for (final interdit in [
          'package:dio',
          'package:http',
          'HttpClient',
          '/api/',
        ]) {
          expect(
            source,
            isNot(contains(interdit)),
            reason: '$chemin $interdit',
          );
        }
      }
    });
  });
}
