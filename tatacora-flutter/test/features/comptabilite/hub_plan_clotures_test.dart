import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/modales_hub_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/onglets_plan_clotures.dart';

import 'support/outils_comptabilite.dart';

/// Les affordances du hub Comptabilité que la vue offre et que le poste
/// n'avait pas (21/10/2026) : l'encadré « Comptabilité déséquilibrée. », le
/// plan comptable et « + Créer un compte », la liste des exercices et « Ouvrir
/// un exercice » — sur une VRAIE base en mémoire, écrites par le VRAI moteur.
///
/// Chaque cas qui écrit RELIT la base : un moteur bouché prouverait que
/// l'écran sait appeler une fonction, pas qu'un compte ou un exercice naît
/// (piège 5).
void main() {
  late AppDatabase db;
  late ComptabiliteDao dao;
  final annee = DateTime.now().year;

  setUp(() async {
    db = await baseInstallee(maintenant: DateTime.now());
    dao = ComptabiliteDao(db);
  });
  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester,
    String onglet, {
    String droit = 'C',
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': droit});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
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
          home: Scaffold(body: EcranComptabilite(ongletInitial: onglet)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> recevoir(String compte, {int debit = 0, int credit = 0}) =>
      EcrituresServeurDao(db).ajouterSiAbsente(
        id: 'e-$compte-$debit-$credit',
        annee: annee,
        codeJournal: 'VTE',
        numeroCompte: compte,
        libelleCompte: 'Compte $compte',
        classe: compte.substring(0, 1),
        dateEcriture: '$annee-06-15',
        libelle: 'Pièce',
        debitCentimes: debit,
        creditCentimes: credit,
      );

  Future<int> nombreDeComptes() => dao.nombreDeComptes();

  group('« Comptabilité déséquilibrée. » (#alerte-globale)', () {
    testWidgets('rien reçu, ou tout équilibré : aucun encadré', (tester) async {
      await monter(tester, 'journal');
      expect(find.byKey(const Key('compta-alerte-globale')), findsNothing);

      await recevoir('5711', debit: 100000);
      await recevoir('7061', credit: 100000);
      await monter(tester, 'journal');
      expect(find.byKey(const Key('compta-alerte-globale')), findsNothing);
    });

    testWidgets('un écart reçu allume l’encadré, aux deux phrases de la vue', (
      tester,
    ) async {
      await recevoir('5711', debit: 100000);
      await recevoir('7061', credit: 90000);
      await monter(tester, 'journal');

      final alerte = find.byKey(const Key('compta-alerte-globale'));
      expect(alerte, findsOneWidget);
      expect(
        find.descendant(
          of: alerte,
          matching: find.textContaining('Comptabilité déséquilibrée.'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: alerte,
          matching: find.textContaining(
            'Aucun état financier n\'est exploitable tant que l\'écart '
            'subsiste. Vérifiez la balance générale.',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('Plan comptable et « + Créer un compte »', () {
    testWidgets('un tableau par classe ; la recherche filtre', (tester) async {
      await monter(tester, 'plan');
      expect(find.byKey(const Key('compta-non-calcule-plan')), findsNothing);
      expect(find.byKey(const Key('compta-plan-classe-1')), findsOneWidget);
      expect(find.byKey(const Key('compta-plan-classe-6')), findsOneWidget);
      expect(find.text('Classe 6 — Charges'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('compta-plan-recherche')),
        '5711',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compta-plan-classe-5')), findsOneWidget);
      expect(find.byKey(const Key('compta-plan-classe-6')), findsNothing);

      await tester.enterText(
        find.byKey(const Key('compta-plan-recherche')),
        'zzzzzz-introuvable',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('compta-plan-aucun')), findsOneWidget);
    });

    testWidgets('« Créer un compte » écrit le compte au plan du poste', (
      tester,
    ) async {
      expect(await dao.compteParNumero('6999'), isNull);
      final avant = await nombreDeComptes();
      await monter(tester, 'plan');

      await tester.tap(find.byKey(const Key('compta-creer-compte')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-compte')), findsOneWidget);
      expect(
        find.text(TextesModalesHubComptabilite.champNatureAide),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('modale-compte-numero')),
        '6999',
      );
      await tester.enterText(
        find.byKey(const Key('modale-compte-intitule')),
        'Produits d’entretien',
      );
      await tester.tap(find.byKey(const Key('modale-compte-nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Charge').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-compte-creer')));
      await tester.pumpAndSettle();

      final cree = await dao.compteParNumero('6999');
      expect(cree, isNotNull, reason: 'le compte existe vraiment en base');
      expect(cree!.libelle, 'Produits d’entretien');
      expect(cree.nature, 'charge');
      expect(cree.classe, '6', reason: 'la classe se DÉRIVE du numéro');
      expect(await nombreDeComptes(), avant + 1);
      expect(find.byKey(const Key('modale-compte')), findsNothing);
      expect(find.text('Compte 6999 créé sur ce poste.'), findsOneWidget);
    });

    testWidgets('un refus du moteur est DIT dans la modale, rien n’est écrit', (
      tester,
    ) async {
      final avant = await nombreDeComptes();
      await monter(tester, 'plan');
      await tester.tap(find.byKey(const Key('compta-creer-compte')));
      await tester.pumpAndSettle();

      // Un numéro déjà au plan.
      await tester.enterText(
        find.byKey(const Key('modale-compte-numero')),
        '5711',
      );
      await tester.enterText(
        find.byKey(const Key('modale-compte-intitule')),
        'Doublon',
      );
      await tester.tap(find.byKey(const Key('modale-compte-nature')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Actif').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-compte-creer')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-compte-refus')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('modale-compte-refus')),
          matching: find.textContaining('5711'),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('modale-compte')), findsOneWidget);
      expect(await nombreDeComptes(), avant);

      // « Annuler » referme sans rien écrire, même une saisie en cours.
      await tester.enterText(
        find.byKey(const Key('modale-compte-numero')),
        '6998',
      );
      await tester.tap(find.byKey(const Key('modale-compte-annuler')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-compte')), findsNothing);
      expect(await dao.compteParNumero('6998'), isNull);
    });

    testWidgets('sans droit d’écriture, le bouton DIT le refus', (
      tester,
    ) async {
      await monter(tester, 'plan', droit: 'L');
      await tester.tap(find.byKey(const Key('compta-creer-compte')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-compte')), findsNothing);
      expect(find.text(TextesOngletsPlanClotures.sansDroit), findsOneWidget);
    });
  });

  group('Clôtures et « Ouvrir un exercice »', () {
    testWidgets('la liste des exercices, et l’année proposée est la suivante', (
      tester,
    ) async {
      await monter(tester, 'clotures');
      expect(find.text('Exercices comptables'), findsOneWidget);
      expect(find.text('$annee'), findsWidgets);
      expect(find.text('Ouvert'), findsOneWidget);
      expect(
        find.byKey(const Key('compta-cloture-non-portee')),
        findsOneWidget,
        reason: 'la clôture annuelle n’est pas portée, et l’onglet le DIT',
      );

      await tester.tap(find.byKey(const Key('compta-ouvrir-exercice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-exercice')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('modale-exercice-annee')))
            .controller!
            .text,
        '${annee + 1}',
      );
    });

    testWidgets(
      '« Ouvrir l’exercice » écrit l’exercice, de janvier à décembre',
      (tester) async {
        expect(await dao.exerciceDeLAnnee(annee + 1), isNull);
        await monter(tester, 'clotures');
        await tester.tap(find.byKey(const Key('compta-ouvrir-exercice')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('modale-exercice-ouvrir')));
        await tester.pumpAndSettle();

        final ouvert = await dao.exerciceDeLAnnee(annee + 1);
        expect(ouvert, isNotNull, reason: 'l’exercice existe vraiment en base');
        expect(ouvert!.dateDebut, '${annee + 1}-01-01');
        expect(ouvert.dateFin, '${annee + 1}-12-31');
        expect(ouvert.statut, StatutExercice.ouvert);
        expect(find.byKey(const Key('modale-exercice')), findsNothing);
        expect(
          find.text('Exercice ${annee + 1} ouvert sur ce poste.'),
          findsOneWidget,
        );
        // La liste le montre aussitôt.
        expect(find.text('${annee + 1}'), findsWidgets);
      },
    );

    testWidgets('une année déjà ouverte, ou hors plage, est refusée à la '
        'phrase du serveur', (tester) async {
      await monter(tester, 'clotures');
      await tester.tap(find.byKey(const Key('compta-ouvrir-exercice')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('modale-exercice-annee')),
        '$annee',
      );
      await tester.tap(find.byKey(const Key('modale-exercice-ouvrir')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('modale-exercice-refus')),
          matching: find.text('L\'exercice $annee existe déjà.'),
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('modale-exercice-annee')),
        '1999',
      );
      await tester.tap(find.byKey(const Key('modale-exercice-ouvrir')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('modale-exercice-refus')),
          matching: find.textContaining('entre 2000 et 2100'),
        ),
        findsOneWidget,
      );
      expect(await dao.exerciceDeLAnnee(1999), isNull);
      expect((await dao.exercices()).length, 1);
    });

    testWidgets('sans droit d’écriture, le bouton DIT le refus', (
      tester,
    ) async {
      await monter(tester, 'clotures', droit: 'L');
      await tester.tap(find.byKey(const Key('compta-ouvrir-exercice')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-exercice')), findsNothing);
      expect(find.text(TextesOngletsPlanClotures.sansDroit), findsOneWidget);
    });
  });
}
