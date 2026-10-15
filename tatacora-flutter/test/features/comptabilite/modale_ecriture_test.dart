import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/shared_widgets/bouton_standard.dart';

import 'support/outils_comptabilite.dart';

/// La modale « Passer une écriture » (PO, 14/10/2026), ouverte par
/// « + Nouvelle écriture » du hub comptable — sur une VRAIE base en mémoire,
/// référentiel installé par la vraie fonction, écrite par le VRAI moteur.
///
/// ## Ces cas relisent `ecritures_local`
///
/// Un dépôt bouché prouverait que la modale sait appeler une fonction ; il ne
/// prouverait pas qu'un clic sur « Enregistrer en brouillon » écrit une pièce
/// en BROUILLON, ni qu'un refus du moteur ne laisse rien derrière lui
/// (piège 5).
///
/// ## L'horloge est la VRAIE
///
/// La modale date la pièce d'aujourd'hui (`DateTime.now()`) : l'exercice
/// installé est donc celui de l'année courante, et le moteur lit la même
/// horloge — sans quoi tout essai tomberait sur « aucun exercice ».
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
    WidgetTester tester, {
    Map<String, String> droits = const {'M10': 'C'},
  }) async {
    tester.view
      ..physicalSize = const Size(1800, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(droits);

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
          home: const Scaffold(body: EcranComptabilite()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final modale = find.byKey(const Key('modale-ecriture'));
  final brouillon = find.byKey(const Key('modale-ecriture-brouillon'));
  final valider = find.byKey(const Key('modale-ecriture-valider'));
  final annuler = find.byKey(const Key('modale-ecriture-annuler'));
  final refus = find.byKey(const Key('modale-ecriture-refus'));
  final toast = find.byKey(const Key('compta-ecriture-enregistree'));

  Future<void> ouvrir(WidgetTester tester) async {
    final bouton = find.byKey(const Key('compta-nouvelle-ecriture'));
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  bool actif(WidgetTester tester, Finder bouton) =>
      tester.widget<BoutonStandard>(bouton).onPressed != null;

  Future<void> journal(WidgetTester tester, String code) async {
    await tester.tap(find.byKey(const Key('modale-ecriture-journal')));
    await tester.pumpAndSettle();
    final libelle = (await dao.journalParCode(code))!.libelle;
    await tester.tap(find.text('$code — $libelle').last);
    await tester.pumpAndSettle();
  }

  /// Choisit le compte [numero] sur la ligne [ligne], par la liste proposée
  /// à la frappe (le libellé est relu du plan installé).
  Future<void> compte(WidgetTester tester, int ligne, String numero) async {
    final c = (await dao.compteParNumero(numero))!;
    await tester.enterText(
      find.byKey(Key('modale-ecriture-compte-$ligne')),
      numero,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('${c.numero} — ${c.libelle}').last);
    await tester.pumpAndSettle();
  }

  Future<void> montant(
    WidgetTester tester,
    int ligne,
    String sens,
    String francs,
  ) async {
    await tester.enterText(
      find.byKey(Key('modale-ecriture-$sens-$ligne')),
      francs,
    );
    await tester.pumpAndSettle();
  }

  /// Une pièce OD valide : Dr 5711 / Cr 5211, 10 000 F. Les deux comptes
  /// portent un centre par défaut (Hébergement, Structure) : le moteur
  /// l'accepte sans centre explicite.
  Future<void> remplirPieceValide(WidgetTester tester) async {
    await journal(tester, 'OD');
    await tester.enterText(
      find.byKey(const Key('modale-ecriture-libelle')),
      'Versement caisse en banque',
    );
    await compte(tester, 0, '5711');
    await montant(tester, 0, 'debit', '10000');
    await compte(tester, 1, '5211');
    await montant(tester, 1, 'credit', '10000');
  }

  Future<void> cliquer(WidgetTester tester, Finder bouton) async {
    await tester.ensureVisible(bouton);
    await tester.pumpAndSettle();
    await tester.tap(bouton);
    await tester.pumpAndSettle();
  }

  testWidgets('« + Nouvelle écriture » ouvre la modale, titrée « Passer une '
      'écriture », avec ses trois actions', (tester) async {
    await monter(tester);
    expect(modale, findsNothing);
    expect(find.text('+ ${TextesComptabilite.saisieBouton}'), findsOneWidget);

    await ouvrir(tester);
    expect(modale, findsOneWidget);
    expect(
      find.descendant(of: modale, matching: find.text('Passer une écriture')),
      findsOneWidget,
    );
    for (final (bouton, libelle) in [
      (annuler, 'Annuler'),
      (brouillon, 'Enregistrer en brouillon'),
      (valider, 'Enregistrer et valider'),
    ]) {
      expect(
        find.descendant(of: modale, matching: bouton),
        findsOneWidget,
        reason: libelle,
      );
      expect(tester.widget<BoutonStandard>(bouton).libelle, libelle);
    }
    expect(actif(tester, annuler), isTrue);
  });

  testWidgets('enregistrement grisé : moins de deux lignes, pièce '
      'déséquilibrée, total nul — actif seulement équilibrée et non nulle', (
    tester,
  ) async {
    await monter(tester);
    await ouvrir(tester);
    await journal(tester, 'OD');

    // Aucune ligne renseignée.
    expect(actif(tester, brouillon), isFalse);
    expect(actif(tester, valider), isFalse);

    // UNE ligne renseignée (débit seul).
    await compte(tester, 0, '5711');
    await montant(tester, 0, 'debit', '10000');
    expect(actif(tester, brouillon), isFalse);
    expect(actif(tester, valider), isFalse);

    // Deux lignes, DÉSÉQUILIBRÉES : l'écart se lit.
    await compte(tester, 1, '5211');
    await montant(tester, 1, 'credit', '9000');
    expect(actif(tester, brouillon), isFalse);
    expect(actif(tester, valider), isFalse);
    final ecart = find.byKey(const Key('modale-ecriture-ecart'));
    expect(
      find.descendant(of: ecart, matching: find.textContaining('Écart : ')),
      findsOneWidget,
    );

    // Deux lignes, comptes choisis, montants NULS : équilibrée, mais vide.
    await montant(tester, 0, 'debit', '');
    await montant(tester, 1, 'credit', '');
    expect(actif(tester, brouillon), isFalse);
    expect(actif(tester, valider), isFalse);

    // Équilibrée et non nulle : les deux s'activent.
    await montant(tester, 0, 'debit', '10000');
    await montant(tester, 1, 'credit', '10000');
    expect(actif(tester, brouillon), isTrue);
    expect(actif(tester, valider), isTrue);
    expect(
      find.descendant(of: ecart, matching: find.text('Pièce équilibrée.')),
      findsOneWidget,
    );
    expect(await dao.toutesLesEcritures(), isEmpty, reason: 'rien écrit');
  });

  testWidgets('« Enregistrer en brouillon » écrit une pièce BROUILLON, le '
      'dit, et le journal du hub la montre', (tester) async {
    await monter(tester);
    await ouvrir(tester);
    await remplirPieceValide(tester);
    await cliquer(tester, brouillon);

    expect(modale, findsNothing);
    expect(toast, findsOneWidget);
    expect(
      tester.widget<Text>(toast).data,
      'Écriture enregistrée sur ce poste.',
    );

    final ecrites = await dao.toutesLesEcritures();
    expect(ecrites, hasLength(2));
    expect(ecrites.every((e) => e.statut == StatutEcriture.brouillon), isTrue);
    expect({for (final e in ecrites) e.numeroPiece}, {'OD-$annee-00001'});
    expect(
      {for (final e in ecrites) e.dateEcriture},
      {formaterDateIso(DateTime.now())},
    );
    expect(
      {for (final e in ecrites) (e.debitCentimes, e.creditCentimes)},
      {(1000000, 0), (0, 1000000)},
    );
    expect(ecrites.every((e) => e.creePar == auteurEssai), isTrue);

    // Le journal du hub relit la base : les deux lignes, en Brouillon.
    await cliquer(tester, find.byKey(const Key('compta-onglet-journal')));
    expect(
      tester.widget<Text>(find.byKey(const Key('compta-journal-lignes'))).data,
      TextesComptabilite.lignes(2),
    );
    expect(find.text('OD-$annee-00001'), findsNWidgets(2));
    expect(find.text(TextesComptabilite.brouillon), findsNWidgets(2));
  });

  testWidgets('« Enregistrer et valider » écrit une pièce VALIDÉE, et le '
      'dit', (tester) async {
    await monter(tester);
    await ouvrir(tester);
    await remplirPieceValide(tester);
    await cliquer(tester, valider);

    expect(modale, findsNothing);
    expect(
      tester.widget<Text>(toast).data,
      'Écriture enregistrée sur ce poste et validée.',
    );
    final ecrites = await dao.toutesLesEcritures();
    expect(ecrites, hasLength(2));
    expect(ecrites.every((e) => e.statut == StatutEcriture.validee), isTrue);
    expect({for (final e in ecrites) e.numeroPiece}, {'OD-$annee-00001'});

    await cliquer(tester, find.byKey(const Key('compta-onglet-journal')));
    expect(find.text(TextesComptabilite.validee), findsNWidgets(2));
  });

  testWidgets('« Annuler » ferme la modale sans RIEN écrire', (tester) async {
    await monter(tester);
    await ouvrir(tester);
    await remplirPieceValide(tester);
    await cliquer(tester, annuler);

    expect(modale, findsNothing);
    expect(toast, findsNothing);
    expect(await dao.toutesLesEcritures(), isEmpty);
  });

  testWidgets('un refus du MOTEUR (centre absent, RG-12) est dit DANS la '
      'modale, à sa phrase ; rien n’est écrit, aucun toast', (tester) async {
    await monter(tester);
    await ouvrir(tester);
    await journal(tester, 'OD');
    await tester.enterText(
      find.byKey(const Key('modale-ecriture-libelle')),
      'Achat de légumes',
    );
    // 6011 ne porte AUCUN centre par défaut, et la ligne laisse « — ».
    await compte(tester, 0, '6011');
    await montant(tester, 0, 'debit', '5000');
    await compte(tester, 1, '5711');
    await montant(tester, 1, 'credit', '5000');
    expect(actif(tester, valider), isTrue);
    await cliquer(tester, valider);

    expect(modale, findsOneWidget, reason: 'la saisie reste à corriger');
    expect(refus, findsOneWidget);
    expect(
      find.descendant(
        of: refus,
        matching: find.text(
          MessagesComptables.dire('depenses.centre_absent', {'numero': '6011'}),
        ),
      ),
      findsOneWidget,
    );
    expect(toast, findsNothing);
    expect(await dao.toutesLesEcritures(), isEmpty);
    final sequences = await db
        .customSelect('SELECT COUNT(*) AS n FROM sequences_piece_local')
        .getSingle();
    expect(sequences.data['n'], 0, reason: 'aucun numéro consommé');
  });

  testWidgets('un refus du MOTEUR (exercice clos entre-temps) est dit dans la '
      'modale ; rien n’est écrit', (tester) async {
    await monter(tester);
    await ouvrir(tester);
    await remplirPieceValide(tester);
    // L'exercice est clos APRÈS l'ouverture de la modale : seul le moteur
    // peut le voir.
    await db.customStatement(
      "UPDATE exercices_local SET statut = 'cloture' WHERE annee = $annee",
    );
    await cliquer(tester, brouillon);

    expect(modale, findsOneWidget);
    expect(
      find.descendant(
        of: refus,
        matching: find.text(
          MessagesComptables.dire('depenses.exercice_clos', {
            'annee': '$annee',
            'statut': 'cloture',
          }),
        ),
      ),
      findsOneWidget,
    );
    expect(toast, findsNothing);
    expect(await dao.toutesLesEcritures(), isEmpty);
  });

  testWidgets('sans le droit d’écriture M10 (lecture seule) : la modale ne '
      's’ouvre pas, le refus est dit, rien n’est écrit', (tester) async {
    await monter(tester, droits: const {'M10': 'L'});
    await ouvrir(tester);

    expect(modale, findsNothing);
    final dit = find.byKey(const Key('compta-saisie-sans-droit'));
    expect(dit, findsOneWidget);
    expect(tester.widget<Text>(dit).data, TextesComptabilite.saisieSansDroit);
    expect(await dao.toutesLesEcritures(), isEmpty);
  });
}
