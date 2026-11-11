import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/format/formats.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

import 'support/outils_comptabilite.dart';

/// Lots A1, A2, A3 (28/10/2026) : le poste compte ses pièces saisies à la main
/// que le serveur n'a pas reprises, même quand le miroir est la source ; une
/// pièce refusée reste comptée et le dit ; les anciennes pièces ne partent que
/// par le geste explicite.
void main() {
  late AppDatabase db;
  late Directory dossier;
  late ComptabiliteDao dao;
  late MoteurComptable moteur;
  late String restaurant;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dossier = await Directory.systemTemp.createTemp('tatacora-manuelles-');
    dao = ComptabiliteDao(db);
    moteur = moteurSur(db, maintenant: DateTime.now);
    restaurant = (await dao.centreParLibelle('Restaurant'))!.id;
  });
  tearDown(() async {
    await db.close();
    await dossier.delete(recursive: true);
  });

  DemandePiece demande(String journal, int centimes) => DemandePiece(
    journal: journal,
    date: '$annee-03-04',
    libelle: 'Régularisation',
    lignes: [
      LigneDemandee(compte: '5711', debitCentimes: centimes),
      LigneDemandee(
        compte: '7061',
        creditCentimes: centimes,
        centreId: restaurant,
      ),
    ],
  );

  Future<List<EcritureComptable>> saisie(int centimes) => moteur.saisirPiece(
    demande('OD', centimes),
    auteurId: auteurEssai,
    valider: true,
  );

  /// Le serveur a envoyé SA pièce de 9 000 F (VTE) — et, si [origine], celle du
  /// poste redescendue avec son identifiant d'origine.
  Future<void> recevoir({String? origine, int centimes = 0}) async {
    final miroir = EcrituresServeurDao(db);
    Future<void> ligne(
      String id,
      String compte, {
      int d = 0,
      int c = 0,
      String journal = 'VTE',
      String? orig,
    }) => miroir.ajouterSiAbsente(
      id: id,
      annee: annee,
      codeJournal: journal,
      numeroCompte: compte,
      libelleCompte: 'Compte $compte',
      classe: compte.substring(0, 1),
      dateEcriture: '$annee-06-15',
      libelle: 'Pièce du serveur',
      debitCentimes: d,
      creditCentimes: c,
      pieceOrigineId: orig,
    );
    await ligne('s1', '5711', d: 900000);
    await ligne('s2', '7061', c: 900000);
    if (origine != null) {
      await ligne('s3', '5711', d: centimes, journal: 'OD', orig: origine);
      await ligne('s4', '7061', c: centimes, journal: 'OD', orig: origine);
    }
  }

  Future<void> monter(
    WidgetTester tester, {
    String role = 'comptable',
    String onglet = 'resultat',
  }) async {
    final fichier = File('${dossier.path}/poste.json');
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(const {'M10': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          cheminConfigurationPosteProvider.overrideWithValue(
            () async => fichier.path,
          ),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
          droitsProvider.overrideWithValue(garde),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'u-$auteurEssai',
              nom: 'Utilisateur',
              role: role,
              droits: garde,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: EcranComptabilite(ongletInitial: onglet)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String fcfa(int centimes) =>
      formaterMontantDecimal('${centimes ~/ 100}.00', suffixe: 'FCFA')!;
  String net(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('compta-resultat-net'))).data!;

  group('A1 — miroir + pièces manuelles non reprises', () {
    testWidgets('le résultat ajoute la pièce manuelle au miroir, et le dit', (
      tester,
    ) async {
      await saisie(300000);
      await recevoir();
      await monter(tester);

      expect(net(tester), fcfa(900000 + 300000));
      expect(
        find.byKey(const Key('compta-etats-pieces-manuelles')),
        findsOneWidget,
      );
    });

    testWidgets('redescendue, la pièce est reconnue : JAMAIS deux fois', (
      tester,
    ) async {
      await saisie(300000);
      final origine = (await db.select(db.piecesSaisieLocal).get()).single.id;
      await recevoir(origine: origine, centimes: 300000);
      await monter(tester);

      expect(net(tester), fcfa(900000 + 300000), reason: 'une seule fois');
      expect(
        find.byKey(const Key('compta-etats-pieces-manuelles')),
        findsNothing,
      );
    });

    test(
      'un brouillon, une pièce de module et une clôture ne s’ajoutent pas',
      () async {
        await moteur.saisirPiece(
          demande('OD', 1000),
          auteurId: auteurEssai,
          valider: false,
        );
        await moteur.passerEtValider(
          demande('VTE', 2000),
          auteurId: auteurEssai,
        );
        expect(await dao.ecrituresPiecesManuellesNonReprises(), isEmpty);
        expect(await dao.nombrePiecesManuellesCompteesEnAttente(), 0);
        expect(await dao.chargesPiecesManuellesNonReprises(), isEmpty);
      },
    );
  });

  group('A2 — pièce refusée', () {
    testWidgets('reste comptée, et le bandeau dit le motif', (tester) async {
      await saisie(300000);
      await recevoir();
      final op = (await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.piecesSaisie)).single;
      await db.customStatement(
        "UPDATE operations_sync_local SET statut = 'rejete', "
        "derniere_erreur = 'Le compte 7061 est introuvable.' "
        "WHERE uuid_operation = '${op.uuidOperation}'",
      );
      await monter(tester);

      expect(net(tester), fcfa(1200000));
      final texte = tester
          .widget<Text>(find.byKey(const Key('compta-etats-piece-refusee-0')))
          .data!;
      expect(texte, contains('Le compte 7061 est introuvable.'));
      expect(texte, contains('validée, immuable et COMPTÉE'));
      expect(texte, contains('À traiter'));
    });
  });

  group('A3 — anciennes pièces', () {
    /// Une pièce d'avant la v44 : écrite par le moteur, sans marque.
    Future<void> ancienne(String journal, int centimes) => moteur
        .passerEtValider(demande(journal, centimes), auteurId: auteurEssai);

    test(
      'proposées : journaux de saisie seulement, jamais VTE/CAI/BQ/CL/AN',
      () async {
        await ancienne('OD', 100000);
        await ancienne('ACH', 50000);
        await ancienne('VTE', 70000);
        await ancienne('CAI', 70000);
        await ancienne('BQ', 70000);
        final pieces = await dao.anciennesPiecesSaisies();
        expect(pieces.map((p) => p.journal).toSet(), {'OD', 'ACH'});
        expect(pieces, hasLength(2));
        expect(await OperationsSyncDao(db).operations(), isEmpty);
      },
    );

    test(
      'une pièce contre-passée ou déséquilibrée n’est PAS proposée (doute)',
      () async {
        final p = await moteur.passerEtValider(
          demande('OD', 100000),
          auteurId: auteurEssai,
        );
        await moteur.contrepasserPiece(p, auteurId: auteurEssai);
        expect(await dao.anciennesPiecesSaisies(), isEmpty);
      },
    );

    test(
      'une pièce d’un exercice CLÔTURÉ n’est pas proposée (le serveur la refuserait)',
      () async {
        await ancienne('OD', 100000);
        await exerciceClos(db, annee);
        expect(await dao.anciennesPiecesSaisies(), isEmpty);
      },
    );

    test('le geste marque, enfile, et ne renvoie rien deux fois', () async {
      await ancienne('OD', 100000);
      expect(await moteur.envoyerAnciennesPieces(auteurId: auteurEssai), 1);
      final marques = await db.select(db.piecesSaisieLocal).get();
      expect(marques, hasLength(1));
      final file = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.piecesSaisie);
      expect(file, hasLength(1));
      expect(file.single.entiteId, marques.single.id);
      expect(await moteur.envoyerAnciennesPieces(auteurId: auteurEssai), 0);
      // Marquée et non reprise : toujours comptée.
      expect(await dao.nombrePiecesManuellesCompteesEnAttente(), 1);
    });

    testWidgets('non faite, la pièce reste comptée au poste en mode miroir', (
      tester,
    ) async {
      await ancienne('OD', 300000);
      await recevoir();
      await monter(tester);
      expect(net(tester), fcfa(1200000));
    });

    testWidgets(
      'le bouton est réservé, confirme avec nombre et total, puis envoie',
      (tester) async {
        await ancienne('OD', 300000);
        await monter(tester, role: 'barman', onglet: 'saisie');
        expect(
          find.byKey(const Key('compta-anciennes-pieces-bouton')),
          findsNothing,
        );
      },
    );

    testWidgets('administration : confirmation puis envoi', (tester) async {
      await ancienne('OD', 300000);
      await monter(tester, onglet: 'saisie');
      await tester.ensureVisible(
        find.byKey(const Key('compta-anciennes-pieces-bouton')),
      );
      await tester.tap(find.byKey(const Key('compta-anciennes-pieces-bouton')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('compta-anciennes-pieces-confirmation')),
          matching: find.textContaining(fcfa(300000)),
        ),
        findsOneWidget,
        reason: 'la confirmation dit le total',
      );
      expect(await db.select(db.piecesSaisieLocal).get(), isEmpty);
      await tester.tap(
        find.byKey(const Key('compta-anciennes-pieces-confirmer')),
      );
      await tester.pumpAndSettle();
      expect(await db.select(db.piecesSaisieLocal).get(), hasLength(1));
    });
  });
}
