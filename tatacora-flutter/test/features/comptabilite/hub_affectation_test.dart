import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/core/impression/entete_parametree.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/affectation_resultat_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_cloture.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../../support/selecteur_essai.dart';
import 'support/outils_comptabilite.dart';

/// La carte « Affectation du résultat de l'exercice N-1 » de l'onglet
/// « Clôtures » (09/11/2026), menée AU CLIC sur une VRAIE base en mémoire,
/// écrite par le VRAI moteur : le résultat (lecture seule), la proposition, le
/// contrôle EN DIRECT du total, la confirmation, la pièce OD enfilée comme une
/// pièce saisie à la main, l'état « Affectation passée… », la contre-passation
/// (motif), les refus aux phrases du serveur, le droit du comptable. Chaque
/// geste RELIT la base : un bouton qui n'écrirait rien rougit (piège 5).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ComptabiliteDao dao;
  late Directory archives;
  late SelecteurEssai selecteur;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dao = ComptabiliteDao(db);
    archives = await Directory.systemTemp.createTemp('hub_affectation_');
    selecteur = SelecteurEssai();
  });
  tearDown(() async {
    await db.close();
    if (archives.existsSync()) await archives.delete(recursive: true);
  });

  /// Vente 100 000, charge 30 000 : bénéfice 70 000 (ou, avec [perte], une
  /// charge de 130 000 : perte de 30 000).
  Future<void> exploiter({bool perte = false}) async {
    final moteur = moteurSur(db, maintenant: DateTime.now);
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    Future<void> piece(
      String libelle,
      String debit,
      String credit,
      int montant,
      String centre,
    ) => moteur.passerEtValider(
      DemandePiece(
        journal: 'CAI',
        date: '$annee-03-10',
        libelle: libelle,
        lignes: [
          LigneDemandee(
            compte: debit,
            debitCentimes: montant,
            centreId: centres[centre],
          ),
          LigneDemandee(
            compte: credit,
            creditCentimes: montant,
            centreId: centres[centre],
          ),
        ],
      ),
      auteurId: auteurEssai,
    );
    await piece('Ventes bar', '5711', '7011', 10000000, 'Bar');
    await piece(
      'Marché',
      '6011',
      '5711',
      perte ? 13000000 : 3000000,
      'Restaurant',
    );
  }

  ClotureExerciceLocale serviceDirect() => ClotureExerciceLocale(
    db,
    moteurSur(db, maintenant: DateTime.now),
    maintenant: DateTime.now,
  );

  AffectationResultatLocale affectationDirecte() => AffectationResultatLocale(
    db,
    moteurSur(db, maintenant: DateTime.now),
    maintenant: DateTime.now,
  );

  Future<String> idExercice() async => (await dao.exerciceDeLAnnee(annee))!.id;

  /// L'exercice de [annee] clôturé (démarrer, puis clôturer).
  Future<void> cloturer() async {
    final id = await idExercice();
    await serviceDirect().demarrer(id, auteurId: auteurEssai);
    await serviceDirect().cloturer(id, auteurId: auteurEssai);
  }

  Future<void> monter(
    WidgetTester tester, {
    String role = 'comptable',
    String droit = 'C',
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 4200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': droit});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sansFichierDePoste(),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
          droitsProvider.overrideWithValue(garde),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'compta-$auteurEssai',
              nom: 'Comptable',
              role: role,
              droits: garde,
            ),
          ),
          dossierArchivesProvider.overrideWithValue(() async => archives),
          lireEnteteEtablissementProvider.overrideWithValue(
            () async => const EnteteEtablissement(),
          ),
          ...selecteur.surcharges,
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(
            body: EcranComptabilite(ongletInitial: 'clotures'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final choisi = (await dao.exerciceDeLAnnee(annee))!;
    if (choisi.statut != StatutExercice.ouvert) {
      ProviderScope.containerOf(
        tester.element(find.byType(EcranComptabilite)),
      ).read(exerciceChoisiProvider.notifier).choisir(choisi.id);
      await tester.pumpAndSettle();
    }
  }

  Finder texte(String t) => find.textContaining(t);

  Future<void> taper(WidgetTester tester, String cle) async {
    final bouton = find.byKey(Key(cle));
    await tester.ensureVisible(bouton);
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester tester, String cle, String valeur) async {
    final champ = find.byKey(Key(cle));
    await tester.ensureVisible(champ);
    await tester.enterText(champ, valeur);
    await tester.pumpAndSettle();
  }

  String champ(WidgetTester tester, String cle) =>
      tester.widget<TextField>(find.byKey(Key(cle))).controller!.text;

  Future<List<EcritureComptable>> pieceAffectation() async {
    final suivant = (await dao.exerciceDeLAnnee(annee + 1))!;
    return [
      for (final e in await dao.toutesLesEcritures())
        if (e.exerciceId == suivant.id &&
            e.libelle == "Affectation du résultat de l'exercice $annee")
          e,
    ];
  }

  group('La carte « Affectation du résultat de l’exercice N-1 »', () {
    testWidgets('absente tant que l’exercice n’est pas clôturé', (
      tester,
    ) async {
      await exploiter();
      await monter(tester);
      expect(find.byKey(const Key('compta-affectation')), findsNothing);
    });

    testWidgets('clôturé : le résultat en lecture seule, la date, la '
        'ventilation amorcée, le total qui égale le résultat', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester);

      expect(find.byKey(const Key('compta-affectation')), findsOneWidget);
      expect(
        texte('Affectation du résultat de l’exercice $annee'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('compta-affectation-resultat')),
          matching: find.text('70 000 FCFA'),
        ),
        findsOneWidget,
      );
      expect(texte('Bénéfice, compte 131'), findsOneWidget);
      // Pas de capital au plan : aucune réserve légale proposée, et on le dit.
      expect(
        find.byKey(const Key('compta-affectation-reserve-note')),
        findsOneWidget,
      );
      expect(
        texte(
          'Le capital n’est pas déterminable (aucun solde créditeur au compte 101)',
        ),
        findsOneWidget,
      );
      expect(champ(tester, 'compta-affectation-reserve_legale'), '0.00');
      expect(champ(tester, 'compta-affectation-report_a_nouveau'), '70000.00');
      expect(champ(tester, 'compta-affectation-date'), '${annee + 1}-01-01');
      expect(texte('La ventilation égale le résultat.'), findsOneWidget);
      // Rien n'est écrit tant qu'on n'a pas confirmé.
      expect(await pieceAffectation(), isEmpty);
    });

    testWidgets('le contrôle EN DIRECT : le report à nouveau reçoit le reste, '
        'un total qui ne tombe pas juste le dit', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester);

      await saisir(tester, 'compta-affectation-dividendes', '10000');
      expect(champ(tester, 'compta-affectation-report_a_nouveau'), '60000.00');
      expect(texte('La ventilation égale le résultat.'), findsOneWidget);

      await saisir(tester, 'compta-affectation-report_a_nouveau', '1000');
      expect(
        texte('La ventilation diffère du résultat de 59 000 FCFA.'),
        findsOneWidget,
      );
      expect(texte('La ventilation égale le résultat.'), findsNothing);
    });

    testWidgets('« Passer l’affectation » demande confirmation, passe la pièce '
        'OD, l’ENFILE comme une pièce saisie et dit « Affectation passée… »', (
      tester,
    ) async {
      await exploiter();
      await cloturer();
      await monter(tester);
      await saisir(tester, 'compta-affectation-date', '${annee + 1}-04-30');
      await saisir(tester, 'compta-affectation-dividendes', '10000');

      await taper(tester, 'compta-affectation-passer');
      // La confirmation : le montant et la date, rien d'écrit encore.
      expect(
        find.byKey(const Key('compta-affectation-confirmation')),
        findsOneWidget,
      );
      expect(
        texte(
          'Une pièce de 70 000 FCFA sera passée au journal OD le ${annee + 1}-04-30',
        ),
        findsOneWidget,
      );
      expect(await pieceAffectation(), isEmpty);
      await taper(tester, 'compta-affectation-annuler');
      expect(await pieceAffectation(), isEmpty, reason: 'annuler n’écrit rien');

      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');

      final lignes = await pieceAffectation();
      expect(lignes, hasLength(3));
      expect({for (final l in lignes) l.dateEcriture}, {'${annee + 1}-04-30'});
      expect(lignes.every((l) => l.estValidee), isTrue);
      final numeros = {for (final l in lignes) l.numeroPiece};
      expect(numeros, {'OD-${annee + 1}-00001'});
      final parCompte = <String, (int, int)>{};
      for (final l in lignes) {
        parCompte[(await dao.compteParId(l.compteId))!.numero] = (
          l.debitCentimes,
          l.creditCentimes,
        );
      }
      expect(parCompte, {
        '131': (7000000, 0),
        '121': (0, 6000000),
        '465': (0, 1000000),
      });

      // La file d'envoi : UNE pièce saisie, validée, avec son bloc affectation.
      final pieces = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.piecesSaisie);
      expect(pieces, hasLength(1));
      final charge = jsonDecode(pieces.single.payload) as Map<String, dynamic>;
      expect(charge['journal'], 'OD');
      expect(charge['statut'], 'validee');
      expect(charge['affectation'], {
        'annee': annee,
        'ventilation': {
          'reserve_legale': 0,
          'autres_reserves': 0,
          'dividendes': 1000000,
          'report_a_nouveau': 6000000,
          'imputation_report_crediteur': 0,
        },
      });

      // L'état : « Affectation passée le … par … (pièce n° …) ».
      expect(
        find.byKey(const Key('compta-affectation-passee-texte')),
        findsOneWidget,
      );
      expect(
        texte('par compta-$auteurEssai (pièce n° OD-${annee + 1}-00001).'),
        findsOneWidget,
      );
      expect(texte('Dividendes : 10 000 FCFA'), findsOneWidget);
      expect(find.byKey(const Key('compta-affectation-passer')), findsNothing);
      expect(
        find.byKey(const Key('compta-affectation-contrepasser')),
        findsOneWidget,
      );
    });

    testWidgets('une somme fausse est refusée à la phrase du serveur, rien '
        'n’est écrit ni enfilé', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester);
      await saisir(tester, 'compta-affectation-report_a_nouveau', '69999');

      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');

      final erreur = find.byKey(const Key('compta-affectation-erreur'));
      expect(erreur, findsOneWidget);
      expect(
        tester.widget<Text>(erreur).data,
        "La ventilation totalise 69999.00 alors que le résultat à affecter "
        "est de 70000.00 (écart 1.00) : elle doit l'égaler exactement.",
      );
      expect(await pieceAffectation(), isEmpty);
      expect(
        await OperationsSyncDao(
          db,
        ).operations(table: TableSynchronisee.piecesSaisie),
        isEmpty,
      );
    });

    testWidgets('la double affectation est refusée', (tester) async {
      await exploiter();
      await cloturer();
      await affectationDirecte().affecter(
        await idExercice(),
        ventilation: {'report_a_nouveau': 7000000},
        date: '${annee + 1}-04-30',
        auteurId: auteurEssai,
      );
      await monter(tester);
      // La carte montre l'affectation passée : plus de bouton « Passer ».
      expect(find.byKey(const Key('compta-affectation-passer')), findsNothing);
      await expectLater(
        affectationDirecte().affecter(
          await idExercice(),
          ventilation: {'report_a_nouveau': 7000000},
          date: '${annee + 1}-05-02',
          auteurId: auteurEssai,
        ),
        throwsA(
          isA<RefusComptable>().having(
            (e) => e.message,
            'message',
            contains('est déjà affecté (pièce OD-${annee + 1}-00001)'),
          ),
        ),
      );
      expect(await pieceAffectation(), hasLength(2));
    });

    testWidgets('« Contre-passer l’affectation » : motif obligatoire, pièce '
        'inversée, demande enfilée, l’affectation peut être refaite', (
      tester,
    ) async {
      await exploiter();
      await cloturer();
      await affectationDirecte().affecter(
        await idExercice(),
        ventilation: {'reserve_legale': 700000, 'report_a_nouveau': 6300000},
        date: '${annee + 1}-04-30',
        auteurId: auteurEssai,
      );
      await monter(tester);

      await saisir(tester, 'compta-affectation-motif', 'court');
      await taper(tester, 'compta-affectation-contrepasser');
      expect(
        tester
            .widget<Text>(find.byKey(const Key('compta-affectation-erreur')))
            .data,
        contains(
          'Le motif de la contre-passation est obligatoire (10 caractères au moins)',
        ),
      );
      expect(await pieceAffectation(), hasLength(3));

      await saisir(
        tester,
        'compta-affectation-motif',
        'Ventilation à revoir en assemblée',
      );
      await taper(tester, 'compta-affectation-contrepasser');

      // Les lignes d'origine sont intactes ; trois inverses les compensent.
      final toutes = await dao.toutesLesEcritures();
      final inverses = [
        for (final e in toutes)
          if (e.ecritureContrepasseeId != null &&
              e.libelle.startsWith("Contre-passation de l'affectation"))
            e,
      ];
      expect(inverses, hasLength(3));
      expect(
        inverses.first.libelle,
        "Contre-passation de l'affectation du résultat $annee — Ventilation à revoir en assemblée",
      );
      expect(
        find.byKey(const Key('compta-affectation-passer')),
        findsOneWidget,
      );
      final demandes = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.demandesClotureExercice);
      final annulation = [
        for (final o in demandes)
          if ((jsonDecode(o.payload) as Map)['action'] == 'annuler_affectation')
            jsonDecode(o.payload) as Map<String, dynamic>,
      ];
      expect(annulation, hasLength(1));
      expect(annulation.single['annee'], annee);
      expect(annulation.single['motif'], 'Ventilation à revoir en assemblée');

      // Refaite : une nouvelle pièce, de nouvelles lignes.
      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');
      expect(
        (await pieceAffectation()).where(
          (l) => l.ecritureContrepasseeId == null,
        ),
        hasLength(5),
      );
    });

    testWidgets('une perte : compte 139, imputation de la perte, pas de '
        'dividende', (tester) async {
      await exploiter(perte: true);
      await cloturer();
      await monter(tester);

      expect(texte('Perte, compte 139'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('compta-affectation-resultat')),
          matching: find.text('-30 000 FCFA'),
        ),
        findsOneWidget,
      );
      expect(texte('Imputation de la perte'), findsOneWidget);
      expect(
        find.byKey(const Key('compta-affectation-dividendes')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('compta-affectation-reserve_legale')),
        findsNothing,
      );
      expect(champ(tester, 'compta-affectation-report_a_nouveau'), '30000.00');
      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');
      final comptes = {
        for (final l in await pieceAffectation())
          (await dao.compteParId(l.compteId))!.numero: (
            l.debitCentimes,
            l.creditCentimes,
          ),
      };
      expect(comptes, {'139': (0, 3000000), '1291': (3000000, 0)});
    });

    testWidgets('seul le comptable affecte : tout autre profil lit la phrase, '
        'sans bouton', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester, role: 'administrateur');

      expect(find.byKey(const Key('compta-affectation')), findsOneWidget);
      expect(find.byKey(const Key('compta-affectation-passer')), findsNothing);
      expect(
        find.byKey(const Key('compta-affectation-reservee')),
        findsOneWidget,
      );
      expect(
        texte(
          'Seul le comptable peut passer ou contre-passer l’affectation du résultat.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('le comptable SANS droit d’écriture M10 : le geste DIT le '
        'refus, rien n’est écrit', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester, droit: 'L');

      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');
      expect(
        find.byKey(const Key('compta-affectation-sans-droit')),
        findsOneWidget,
      );
      expect(await pieceAffectation(), isEmpty);
    });

    testWidgets('la carte se lit aussi depuis N, l’exercice qui porte la '
        'pièce', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester);
      ProviderScope.containerOf(tester.element(find.byType(EcranComptabilite)))
          .read(exerciceChoisiProvider.notifier)
          .choisir((await dao.exerciceDeLAnnee(annee + 1))!.id);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compta-affectation')), findsOneWidget);
      expect(
        texte('Affectation du résultat de l’exercice $annee'),
        findsOneWidget,
      );
    });
  });
}
