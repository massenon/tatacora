import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/correspondance_comptes.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_correspondance_comptes.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';
import 'package:tatacora_flutter/features/synchronisation/data/aligneur_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/data/descente_catalogue_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/descente_catalogue.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/outils_comptabilite.dart';

/// La CORRESPONDANCE DES COMPTES sur le poste (26/10/2026, décision du PO :
/// « on peut impérativement modifier les comptes sur poste et le web »).
///
/// Le poste lit la correspondance AU MOMENT de passer la pièce, l'écran
/// l'écrit par le seul `EnregistrerParametres`, la file d'envoi (que le Journal
/// d'Audit du poste relit) en garde la trace, et la descente du serveur la
/// pose sans rien renvoyer. Chaque cas relit la BASE : un écran qui
/// appellerait une fonction sans que rien ne soit écrit ne passerait pas.
///
/// La parité avec le serveur — mêmes pièces, mêmes refus, mêmes phrases — est
/// prouvée contre le VRAI PHP par les tests `*_contre_serveur_test.dart`
/// (ventes, règlements, encaissements, acomptes, dépenses, validation).
void main() {
  late AppDatabase db;
  late ComptabiliteDao dao;
  late MoteurComptable moteur;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    dao = ComptabiliteDao(db);
    moteur = moteurSur(db);
  });
  tearDown(() => db.close());

  EnregistrerParametres cas() => EnregistrerParametres(
    ParametresDepotLocal(db),
    verifierCompte: dao.verifierCompteDuRole,
  );

  Future<ResultatEcriture> ecrire(
    Map<String, Object?> valeurs, {
    bool droit = true,
  }) => cas().executer(valeurs, peutEcrire: droit, auteurId: auteurEssai);

  Future<List<OperationSync>> file() => OperationsSyncDao(
    db,
  ).operations(table: TableSynchronisee.parametresSysteme);

  /// Les comptes de la pièce, ligne par ligne (compte, débit, crédit).
  Future<List<(String, int, int)>> lignes(
    List<EcritureComptable> piece,
  ) async => [
    for (final e in piece)
      (
        (await dao.compteParId(e.compteId))!.numero,
        e.debitCentimes,
        e.creditCentimes,
      ),
  ];

  const centreStructure = 'Structure';

  Future<String> centre(String libelle) async =>
      (await dao.centreParLibelle(libelle))!.id;

  DemandePiece vente() => DemandePiece(
    journal: 'VTE',
    date: '2031-06-15',
    libelle: 'Vente de test',
    lignes: [
      const LigneDemandee(role: 'CAISSE', debitCentimes: 100000),
      const LigneDemandee(role: 'PRODUIT_LOCATIONS', creditCentimes: 100000),
    ],
  );

  group('Le moteur lit la correspondance AU MOMENT de passer la pièce', () {
    test('sans rien de choisi : le défaut de chaque rôle', () async {
      for (final r in RolesCorrespondance.roles) {
        expect(await dao.compteDuRole(r.code), r.defaut, reason: r.code);
      }
    });

    test('un compte choisi vaut pour la pièce FUTURE ; la pièce passée '
        'n’est JAMAIS réécrite (RG-11)', () async {
      final centreVehicules = await centre('Véhicules');
      DemandePiece piece() => DemandePiece(
        journal: 'VTE',
        date: '2031-06-15',
        libelle: 'Vente de test',
        lignes: [
          const LigneDemandee(role: 'CAISSE', debitCentimes: 100000),
          LigneDemandee(
            role: 'PRODUIT_LOCATIONS',
            creditCentimes: 100000,
            centreId: centreVehicules,
          ),
        ],
      );

      final avant = await moteur.passerEtValider(
        piece(),
        auteurId: auteurEssai,
      );
      expect(await lignes(avant), [('5711', 100000, 0), ('7073', 0, 100000)]);

      final r = await ecrire({
        'compte_produit_locations': '7078',
        'compte_caisse': '5712',
      });
      expect(r, isA<EcritureAcceptee>());

      final apres = await moteur.passerEtValider(
        piece(),
        auteurId: auteurEssai,
      );
      expect(await lignes(apres), [('5712', 100000, 0), ('7078', 0, 100000)]);

      // La pièce d'avant, relue de la base : intacte.
      final relue = [for (final e in avant) (await dao.ecriture(e.id))!];
      expect(await lignes(relue), [('5711', 100000, 0), ('7073', 0, 100000)]);
    });

    test(
      'vider le paramètre rétablit le défaut ; une valeur blanche aussi',
      () async {
        await ecrire({'compte_caisse': '5712'});
        expect(await dao.compteDuRole('CAISSE'), '5712');

        await ecrire({'compte_caisse': null});
        expect(await dao.compteDuRole('CAISSE'), '5711');

        // Une ligne blanche (descente d'un serveur qui a vidé la clé) = défaut.
        await ParametresDao(db).inscrireDescendue('compte_caisse', '   ');
        expect(await dao.compteDuRole('CAISSE'), '5711');
      },
    );

    test('un compte sans centre par défaut au plan ne bloque pas la pièce : '
        'le centre est celui du compte par défaut du rôle', () async {
      // 4112 « Clients-Groupe », 5712 « en devises » : AUCUN centre par défaut.
      expect((await dao.compteParNumero('4112'))!.centreCoutDefautId, isNull);
      await ecrire({'compte_clients': '4112', 'compte_caisse': '5712'});

      final piece = await moteur.passerEtValider(
        DemandePiece(
          journal: 'VTE',
          date: '2031-06-15',
          libelle: 'Note de chambre',
          lignes: [
            const LigneDemandee(role: 'CLIENTS', debitCentimes: 5000),
            const LigneDemandee(role: 'CAISSE', creditCentimes: 5000),
          ],
        ),
        auteurId: auteurEssai,
      );

      // 4111 porte « Structure » par défaut, 5711 « Hébergement ».
      final centres = {
        for (final e in piece)
          (await dao.compteParId(e.compteId))!.numero: e.centreId,
      };
      expect(centres['4112'], await centre(centreStructure));
      expect(centres['5712'], await centre('Hébergement'));
    });

    test('une ligne SANS rôle garde son numéro : un compte de charge saisi '
        'n’est jamais détourné', () async {
      await ecrire({'compte_caisse': '5712'});
      final piece = await moteur.passerEtValider(
        DemandePiece(
          journal: 'CAI',
          date: '2031-06-15',
          libelle: 'Charge',
          lignes: [
            LigneDemandee(
              compte: '6011',
              debitCentimes: 9000,
              centreId: await centre('Restaurant'),
            ),
            const LigneDemandee(role: 'CAISSE', creditCentimes: 9000),
          ],
        ),
        auteurId: auteurEssai,
      );
      expect(await lignes(piece), [('6011', 9000, 0), ('5712', 0, 9000)]);
    });

    test('un compte CHOISI que le plan refuse (posé hors validation) refuse '
        'la pièce, avec la phrase du serveur, rien n’est écrit', () async {
      for (final (numero, phrase) in [
        ('7999', 'Compte comptable inconnu : 7999'),
        ('70', 'Le compte 70 est une division du plan comptable'),
      ]) {
        await ParametresDao(
          db,
        ).ecrire({'compte_produit_locations': numero}, auteurId: null);
        await expectLater(
          moteur.passerEtValider(vente(), auteurId: auteurEssai),
          throwsA(
            isA<RefusComptable>().having(
              (e) => e.message,
              'message',
              contains(phrase),
            ),
          ),
        );
      }
      expect((await dao.toutesLesEcritures()), isEmpty);
    });

    test('un rôle hors registre LÈVE : jamais un compte deviné', () async {
      expect(() => dao.compteDuRole('INVENTE'), throwsArgumentError);
    });
  });

  group('L’écriture : un paramètre, validé, audité, synchronisé', () {
    test('un changement valide s’écrit, part au serveur en UN enregistrement '
        '(la trace du Journal d’Audit du poste) et se lit à nouveau', () async {
      final r = await ecrire({'compte_produit_locations': '7078'});

      expect(r, isA<EcritureAcceptee>());
      expect((r as EcritureAcceptee).modifiees, ['compte_produit_locations']);
      expect(await dao.compteDuRole('PRODUIT_LOCATIONS'), '7078');

      final ops = await file();
      expect(ops, hasLength(1));
      expect(ops.single.type, TypeOperationSync.creation);
      expect(jsonDecode(ops.single.payload), {
        'valeurs': {'compte_produit_locations': '7078'},
      });
    });

    test('quatre refus, les phrases du serveur : RIEN n’est écrit, RIEN ne '
        'part', () async {
      final cas = <(String, String, String)>[
        (
          'compte_produit_locations',
          '70739',
          'Numéro de compte invalide : « 70739 »',
        ),
        (
          'compte_produit_locations',
          '7999',
          'Le compte 7999 n’existe pas au plan comptable.',
        ),
        (
          'compte_produit_locations',
          '6011',
          'Le compte 6011 ne convient pas au rôle « Produits de la location '
              'de véhicules » : le numéro attendu est de la classe 7.',
        ),
        (
          'compte_tva_facturee_biens',
          '4452',
          'le numéro attendu commence par 443.',
        ),
        (
          'compte_caisse',
          '57',
          'Le compte 57 est une division du plan comptable',
        ),
      ];
      for (final (cle, numero, phrase) in cas) {
        final r = await ecrire({cle: numero});
        expect(r, isA<EcritureRefusee>(), reason: '$cle <- $numero');
        expect(
          (r as EcritureRefusee).parCle[cle],
          contains(phrase),
          reason: '$cle <- $numero',
        );
      }
      expect(await ParametresDao(db).lireTout(), isEmpty);
      expect(await file(), isEmpty);
    });

    test('un lot refusé n’écrit AUCUNE de ses clés', () async {
      final r = await ecrire({
        'compte_caisse': '5712',
        'compte_banque': '6011',
      });
      expect(r, isA<EcritureRefusee>());
      expect(await dao.compteDuRole('CAISSE'), '5711');
      expect(await file(), isEmpty);
    });

    test('vider rétablit le défaut et le DIT au serveur (null) ; rien de '
        'modifié : rien ne part', () async {
      await ecrire({'compte_caisse': '5712'});
      final vide = await ecrire({'compte_caisse': null});
      expect((vide as EcritureAcceptee).modifiees, ['compte_caisse']);
      expect(await dao.compteDuRole('CAISSE'), '5711');
      expect(jsonDecode((await file()).last.payload), {
        'valeurs': {'compte_caisse': null},
      });

      final rien = await ecrire({'compte_caisse': null});
      expect((rien as EcritureAcceptee).modifiees, isEmpty);
      expect(rien.message, messageAucunChangement);
      expect(await file(), hasLength(2));
    });

    test('le droit : sans écriture M10 rien n’est écrit', () async {
      final r = await ecrire({'compte_caisse': '5712'}, droit: false);
      expect(r, isA<EcritureRefusee>());
      expect(await dao.compteDuRole('CAISSE'), '5711');
    });

    test('sans verificateur du plan, une clé de la correspondance est REFUSÉE '
        '(fermé par défaut)', () async {
      final r = await EnregistrerParametres(ParametresDepotLocal(db)).executer(
        {'compte_caisse': '5712'},
        peutEcrire: true,
        auteurId: auteurEssai,
      );
      expect(
        (r as EcritureRefusee).parCle['compte_caisse'],
        refusVerificateurComptesAbsent,
      );
      expect(await dao.compteDuRole('CAISSE'), '5711');
    });

    test(
      'le registre est fermé : « compte_inconnu » n’est pas un rôle',
      () async {
        final r = await ecrire({'compte_inconnu': '7078'});
        expect(r, isA<EcritureRefusee>());
        expect(await ParametresDao(db).lireTout(), isEmpty);
      },
    );
  });

  group('La descente : dernier écrit gagnant, clé par clé', () {
    Future<IssueAlignement> descendre(String cle, String? valeur) =>
        db.transaction(
          () =>
              AligneurCatalogue(
                db,
                DescenteCatalogueDao(db),
                auteur: () async => null,
              ).aligner(
                ElementCatalogue(
                  table: TableDescendue.parametresSysteme,
                  id: 's-$cle',
                  actif: true,
                  modifieLe: '2026-10-26 10:00:00',
                  donnees: {'cle': cle, 'valeur': valeur},
                ),
              ),
        );

    test('un compte posé par le serveur (ou un autre poste) est lu par le '
        'moteur, sans rien renvoyer ; vidé au serveur : le défaut', () async {
      expect(
        await descendre('compte_produit_locations', '7078'),
        isA<Aligne>(),
      );
      expect(await dao.compteDuRole('PRODUIT_LOCATIONS'), '7078');
      expect(await file(), isEmpty);

      await descendre('compte_produit_locations', '');
      expect(await dao.compteDuRole('PRODUIT_LOCATIONS'), '7073');
      expect(await ParametresDao(db).lireTout(), isEmpty);
      expect(await file(), isEmpty);
    });

    test('une saisie locale qui attend de partir est conservée', () async {
      await ecrire({'compte_caisse': '5712'});
      expect(
        await descendre('compte_caisse', '552'),
        isA<ConserveLocalement>(),
      );
      expect(await dao.compteDuRole('CAISSE'), '5712');
    });
  });

  group('L’écran « Correspondance des comptes »', () {
    Future<void> monter(WidgetTester tester, {String droit = 'C'}) async {
      tester.view
        ..physicalSize = const Size(1800, 3600)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final garde = GardeAcces.depuisJson({'M10': droit});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            sansFichierDePoste(),
            moteurComptableProvider.overrideWith((ref) async => moteur),
            droitsProvider.overrideWithValue(garde),
            sessionProvider.overrideWithBuild(
              (ref, notifier) => Session(
                utilisateurId: auteurEssai,
                login: 'compta-$auteurEssai',
                nom: 'Comptable',
                role: 'comptable',
                droits: garde,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranCorrespondanceComptes()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder cle(String k) => find.byKey(Key(k));

    testWidgets('quinze rôles en cinq groupes, le compte actuel, son '
        'intitulé au plan, l’état « Défaut » et l’avertissement RG-11', (
      tester,
    ) async {
      await monter(tester);

      expect(find.text('Correspondance des comptes'), findsOneWidget);
      expect(
        find.text(MessagesCorrespondance.dire('avertissement')),
        findsOneWidget,
      );
      for (final g in RolesCorrespondance.groupes) {
        expect(cle('correspondance-groupe-$g'), findsOneWidget, reason: g);
      }
      for (final r in RolesCorrespondance.roles) {
        expect(cle('correspondance-actuel-${r.code}'), findsOneWidget);
        expect(cle('correspondance-modifier-${r.code}'), findsOneWidget);
      }
      final locations = tester.widget<Text>(
        cle('correspondance-actuel-PRODUIT_LOCATIONS'),
      );
      final texte = locations.textSpan!.toPlainText();
      expect(texte, contains('7073'));
      expect(texte, contains('Locations'));
      expect(texte, contains('Défaut'));
      expect(
        find.text(MessagesCorrespondance.dire('lecture_seule')),
        findsNothing,
      );
    });

    testWidgets('trois rôles que le serveur seul lit le DISENT', (
      tester,
    ) async {
      await monter(tester);
      final serveurSeul = [
        for (final r in RolesCorrespondance.roles)
          if (find
              .byKey(Key('correspondance-serveur-seul-${r.code}'))
              .evaluate()
              .isNotEmpty)
            r.code,
      ];
      expect(serveurSeul, [
        'TVA_RECUPERABLE_ACHATS',
        'RESULTAT_BENEFICE',
        'RESULTAT_PERTE',
      ]);
    });

    testWidgets('modifier : le refus du plan s’affiche tel quel et RIEN '
        'n’est écrit ; un compte valide s’écrit, le moteur le lit, la file '
        'part', (tester) async {
      await monter(tester);

      await tester.ensureVisible(
        cle('correspondance-modifier-PRODUIT_LOCATIONS'),
      );
      await tester.tap(cle('correspondance-modifier-PRODUIT_LOCATIONS'));
      await tester.pumpAndSettle();
      expect(cle('modale-correspondance'), findsOneWidget);
      // Le champ porte le compte actuel ; le rappel dit ce que le rôle attend.
      expect(
        tester
            .widget<TextField>(cle('modale-correspondance-numero'))
            .controller!
            .text,
        '7073',
      );
      expect(find.text('Numéro attendu : est de la classe 7.'), findsOneWidget);
      expect(find.text('Compte par défaut : 7073.'), findsOneWidget);

      // Un compte de charge pour un rôle de produit : refusé, la phrase du serveur.
      await tester.enterText(cle('modale-correspondance-numero'), '6011');
      await tester.tap(cle('modale-correspondance-enregistrer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(cle('modale-correspondance-refus')).data,
        contains('ne convient pas au rôle'),
      );
      expect(await ParametresDao(db).lireTout(), isEmpty);
      expect(await file(), isEmpty);

      // Un compte absent du plan.
      await tester.enterText(cle('modale-correspondance-numero'), '7999');
      await tester.tap(cle('modale-correspondance-enregistrer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(cle('modale-correspondance-refus')).data,
        contains('n’existe pas au plan comptable'),
      );

      // Un compte valide.
      await tester.enterText(cle('modale-correspondance-numero'), '7078');
      await tester.tap(cle('modale-correspondance-enregistrer'));
      await tester.pumpAndSettle();
      expect(cle('modale-correspondance'), findsNothing);
      expect(
        find.text(
          'Correspondance enregistrée : les pièces futures utiliseront le '
          'compte 7078.',
        ),
        findsOneWidget,
      );
      expect(await dao.compteDuRole('PRODUIT_LOCATIONS'), '7078');
      expect(await file(), hasLength(1));

      final texte = tester
          .widget<Text>(cle('correspondance-actuel-PRODUIT_LOCATIONS'))
          .textSpan!
          .toPlainText();
      expect(texte, contains('7078'));
      expect(texte, contains('Autres produits accessoires'));
      expect(texte, contains('Modifié'));
    });

    testWidgets('« Rétablir le défaut » vide le paramètre', (tester) async {
      await ecrire({'compte_produit_locations': '7078'});
      await monter(tester);

      await tester.ensureVisible(
        cle('correspondance-modifier-PRODUIT_LOCATIONS'),
      );
      await tester.tap(cle('correspondance-modifier-PRODUIT_LOCATIONS'));
      await tester.pumpAndSettle();
      await tester.tap(cle('modale-correspondance-retablir'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Défaut rétabli : les pièces futures utiliseront le compte 7073.',
        ),
        findsOneWidget,
      );
      expect(await dao.compteDuRole('PRODUIT_LOCATIONS'), '7073');
      expect(await ParametresDao(db).lireTout(), isEmpty);
    });

    testWidgets('un champ vide n’enregistre rien : le défaut a son bouton', (
      tester,
    ) async {
      await monter(tester);
      await tester.ensureVisible(cle('correspondance-modifier-CAISSE'));
      await tester.tap(cle('correspondance-modifier-CAISSE'));
      await tester.pumpAndSettle();
      await tester.enterText(cle('modale-correspondance-numero'), '');
      await tester.tap(cle('modale-correspondance-enregistrer'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(cle('modale-correspondance-refus')).data,
        MessagesCorrespondance.dire('champ_compte_requis'),
      );
      expect(await file(), isEmpty);
    });

    testWidgets('en LECTURE (M10 = L) : on voit, on ne modifie pas', (
      tester,
    ) async {
      await monter(tester, droit: 'L');
      expect(
        find.text(MessagesCorrespondance.dire('lecture_seule')),
        findsOneWidget,
      );
      expect(cle('correspondance-actuel-CAISSE'), findsOneWidget);
      expect(cle('correspondance-modifier-CAISSE'), findsNothing);
    });

    testWidgets('sans droit M10, l’écran est refusé', (tester) async {
      await monter(tester, droit: '-');
      expect(cle('correspondance-actuel-CAISSE'), findsNothing);
    });

    testWidgets('le lien de l’onglet Plan du hub ouvre l’écran', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1800, 3200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final garde = GardeAcces.depuisJson({'M10': 'C'});
      final routeur = GoRouter(
        initialLocation: '/comptabilite',
        routes: [
          GoRoute(
            path: '/comptabilite',
            builder: (_, e) =>
                const Scaffold(body: EcranComptabilite(ongletInitial: 'plan')),
            routes: [
              GoRoute(
                path: 'correspondance-comptes',
                builder: (_, e) =>
                    const Scaffold(body: EcranCorrespondanceComptes()),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            sansFichierDePoste(),
            moteurComptableProvider.overrideWith((ref) async => moteur),
            droitsProvider.overrideWithValue(garde),
            sessionProvider.overrideWithBuild(
              (ref, notifier) => Session(
                utilisateurId: auteurEssai,
                login: 'compta-$auteurEssai',
                nom: 'Comptable',
                role: 'comptable',
                droits: garde,
              ),
            ),
          ],
          child: MaterialApp.router(
            theme: AppTheme.clair,
            routerConfig: routeur,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(cle('compta-correspondance-comptes'));
      await tester.pumpAndSettle();
      expect(cle('correspondance-actuel-CAISSE'), findsOneWidget);
    });
  });

  group('L’écran Paramètres ne montre PAS la correspondance', () {
    testWidgets('aucune des quinze clés n’est rendue sous aucun onglet', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1600, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final garde = GardeAcces.depuisJson({'PARAM': 'C'});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            droitsProvider.overrideWithValue(garde),
            sessionProvider.overrideWithBuild(
              (ref, notifier) => Session(
                utilisateurId: auteurEssai,
                login: 'compta-$auteurEssai',
                nom: 'Admin',
                role: 'administrateur',
                droits: garde,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranParametres()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final onglet in const [
        'identite',
        'communication',
        'email',
        'activation',
      ]) {
        final cible = find.byKey(Key('param-onglet-$onglet'));
        if (cible.evaluate().isNotEmpty) {
          await tester.tap(cible);
          await tester.pumpAndSettle();
        }
        for (final r in RolesCorrespondance.roles) {
          expect(
            find.byKey(Key('param-ligne-${r.cle}')),
            findsNothing,
            reason: '${r.cle} sous « $onglet »',
          );
        }
      }
      expect(find.textContaining('Compte — '), findsNothing);
    });
  });
}
