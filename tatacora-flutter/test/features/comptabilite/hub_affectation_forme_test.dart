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
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_cloture.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../../support/selecteur_essai.dart';
import 'support/outils_comptabilite.dart';

/// La carte « Affectation du résultat » SELON LA FORME JURIDIQUE (09/11/2026), menée au
/// clic sur une VRAIE base en mémoire :
///
///  - ENTREPRISE INDIVIDUELLE (aucune forme descendue : le défaut du Gîte) : « Date de la
///    décision de l'exploitant », ni dividendes ni réserve légale (aucun champ), le reste
///    au compte de l'exploitant, la pièce part avec `compte_exploitant` ;
///  - SOCIÉTÉ : « Date d'approbation des comptes », dividendes et réserve légale, la
///    réserve légale obligatoire refusée sous son minimum, l'alerte de l'article 664
///    lisible sur la carte (non bloquante), la contre-passation refusée quand un
///    dividende est réglé.
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
    archives = await Directory.systemTemp.createTemp('hub_affectation_forme_');
    selecteur = SelecteurEssai();
  });
  tearDown(() async {
    await db.close();
    if (archives.existsSync()) await archives.delete(recursive: true);
  });

  Future<void> piece(
    String journal,
    String debit,
    String credit,
    int montant,
    String centre, {
    String libelle = 'Pièce',
    String? mois,
  }) async {
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    await moteurSur(db, maintenant: DateTime.now).passerEtValider(
      DemandePiece(
        journal: journal,
        date: '$annee-${mois ?? '03'}-10',
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
  }

  /// Un bénéfice de 70 000 (vente 100 000, charge 30 000) ou une perte de [perte].
  Future<void> exploiter({int? perte}) async {
    if (perte == null) {
      await piece('CAI', '5711', '7011', 10000000, 'Bar');
      await piece('CAI', '6011', '5711', 3000000, 'Restaurant');
    } else {
      await piece('CAI', '5711', '7011', 1000000, 'Bar');
      await piece('CAI', '6011', '5711', 1000000 + perte, 'Restaurant');
    }
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

  Future<void> cloturer() async {
    final id = await idExercice();
    await serviceDirect().demarrer(id, auteurId: auteurEssai);
    await serviceDirect().cloturer(id, auteurId: auteurEssai);
  }

  Future<void> monter(WidgetTester tester, {DateTime? aujourdhui}) async {
    tester.view
      ..physicalSize = const Size(1800, 4200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson({'M10': 'C'});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          sansFichierDePoste(),
          moteurComptableProvider.overrideWith(
            (ref) async => moteurSur(db, maintenant: DateTime.now),
          ),
          droitsProvider.overrideWithValue(garde),
          if (aujourdhui != null)
            affectationResultatLocaleProvider.overrideWith(
              (ref) async => AffectationResultatLocale(
                db,
                moteurSur(db, maintenant: () => aujourdhui),
                maintenant: () => aujourdhui,
              ),
            ),
          sessionProvider.overrideWithBuild(
            (ref, notifier) => Session(
              utilisateurId: auteurEssai,
              login: 'compta-$auteurEssai',
              nom: 'Comptable',
              role: 'comptable',
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

  String erreur(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('compta-affectation-erreur')))
      .data!;

  group('entreprise individuelle (le défaut du Gîte)', () {
    testWidgets('« Date de la décision de l’exploitant », ni dividendes ni '
        'réserve légale, le reste au compte de l’exploitant', (tester) async {
      await piece('OD', '5711', '1011', 50000000, 'Structure');
      await exploiter();
      await cloturer();
      await monter(tester);

      expect(texte('Date de la décision de l’exploitant'), findsOneWidget);
      expect(texte('Date d’approbation des comptes'), findsNothing);
      expect(
        texte('Forme juridique : Entreprise individuelle'),
        findsOneWidget,
      );
      expect(
        texte('ni réserve légale, ni dividendes, ni assemblée'),
        findsOneWidget,
      );
      for (final p in const ['dividendes', 'reserve_legale']) {
        expect(
          find.byKey(Key('compta-affectation-$p')),
          findsNothing,
          reason: 'le champ « $p » n’est pas offert',
        );
      }
      for (final p in const [
        'compte_exploitant',
        'autres_reserves',
        'report_a_nouveau',
      ]) {
        expect(find.byKey(Key('compta-affectation-$p')), findsOneWidget);
      }
      expect(texte('Compte de l\'exploitant'), findsOneWidget);
      expect(
        find.byKey(const Key('compta-affectation-reserve-note')),
        findsNothing,
        reason: 'aucune réserve légale, même avec un capital',
      );
      expect(champ(tester, 'compta-affectation-compte_exploitant'), '70000.00');

      // Le reste va au compte de l'exploitant : 5 000 aux réserves, 10 000 au report.
      await saisir(tester, 'compta-affectation-autres_reserves', '5000');
      expect(champ(tester, 'compta-affectation-compte_exploitant'), '65000.00');
      await saisir(tester, 'compta-affectation-report_a_nouveau', '10000');
      expect(champ(tester, 'compta-affectation-compte_exploitant'), '55000.00');
      expect(texte('La ventilation égale le résultat.'), findsOneWidget);
    });

    testWidgets('le geste passe la pièce 131 / 1041 / 121 / 1181 et l’enfile '
        'avec le compte de l’exploitant', (tester) async {
      await exploiter();
      await cloturer();
      await monter(tester);
      await saisir(tester, 'compta-affectation-autres_reserves', '5000');
      await saisir(tester, 'compta-affectation-report_a_nouveau', '10000');
      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');

      final suivant = (await dao.exerciceDeLAnnee(annee + 1))!;
      final lignes = [
        for (final e in await dao.toutesLesEcritures())
          if (e.exerciceId == suivant.id &&
              e.libelle == "Affectation du résultat de l'exercice $annee")
            e,
      ];
      final parCompte = {
        for (final l in lignes)
          (await dao.compteParId(l.compteId))!.numero: (
            l.debitCentimes,
            l.creditCentimes,
          ),
      };
      expect(parCompte, {
        '131': (7000000, 0),
        '1041': (0, 5500000),
        '121': (0, 1000000),
        '1181': (0, 500000),
      });
      final pieces = await OperationsSyncDao(
        db,
      ).operations(table: TableSynchronisee.piecesSaisie);
      final charge = jsonDecode(pieces.single.payload) as Map<String, dynamic>;
      expect(
        ((charge['affectation'] as Map)['ventilation']
            as Map)['compte_exploitant'],
        5500000,
      );
      expect(
        find.byKey(const Key('compta-affectation-passee-texte')),
        findsOneWidget,
      );
      expect(texte('Compte de l\'exploitant : '), findsOneWidget);
    });

    testWidgets('une perte : compte de l’exploitant par défaut, jamais de '
        'dividende ni de réserve légale', (tester) async {
      await exploiter(perte: 3000000);
      await cloturer();
      await monter(tester);

      expect(texte('Imputation de la perte'), findsOneWidget);
      expect(
        find.byKey(const Key('compta-affectation-dividendes')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('compta-affectation-reserve_legale')),
        findsNothing,
      );
      expect(champ(tester, 'compta-affectation-compte_exploitant'), '30000.00');
      expect(find.byKey(const Key('compta-affectation-alerte')), findsNothing);
    });
  });

  group('société (SARL)', () {
    setUp(() => poserFormeJuridique(db, 'sarl'));

    testWidgets('« Date d’approbation des comptes », dividendes et réserve '
        'légale offerts, la réserve légale obligatoire refusée sous son '
        'minimum', (tester) async {
      await piece('OD', '5711', '1011', 50000000, 'Structure');
      await exploiter();
      await cloturer();
      await monter(tester);

      expect(texte('Date d’approbation des comptes'), findsOneWidget);
      expect(texte('Date de la décision de l’exploitant'), findsNothing);
      expect(texte('Forme juridique : SARL'), findsOneWidget);
      expect(
        find.byKey(const Key('compta-affectation-dividendes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('compta-affectation-reserve_legale')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('compta-affectation-compte_exploitant')),
        findsNothing,
      );
      expect(
        texte('Réserve légale obligatoire : au moins 10 %'),
        findsOneWidget,
      );
      // 10 % de 70 000 : proposé.
      expect(champ(tester, 'compta-affectation-reserve_legale'), '7000.00');

      await saisir(tester, 'compta-affectation-reserve_legale', '6999.99');
      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');
      expect(
        erreur(tester),
        contains(
          'La réserve légale est obligatoire : elle doit recevoir au moins 7000.00',
        ),
      );
      expect((await affectationDirecte().active(await idExercice())), isNull);
    });

    testWidgets('l’alerte de l’article 664 est LISIBLE sur la carte, sans '
        'bloquer l’affectation', (tester) async {
      await piece('OD', '5711', '1011', 10000000, 'Structure');
      await exploiter(perte: 7000000);
      await cloturer();
      await monter(tester);

      // Capitaux propres : 100 000 − 70 000 = 30 000 < 50 000.
      expect(
        find.byKey(const Key('compta-affectation-alerte')),
        findsOneWidget,
      );
      expect(texte('ALERTE : après cette perte'), findsOneWidget);
      expect(texte('art. 664'), findsOneWidget);
      await taper(tester, 'compta-affectation-passer');
      await taper(tester, 'compta-affectation-confirmer');
      expect(
        (await affectationDirecte().active(await idExercice())),
        isNotNull,
        reason: 'une alerte ne bloque pas',
      );
    });

    testWidgets('la contre-passation est refusée tant qu’un dividende est '
        'réglé : « annulez d’abord le règlement »', (tester) async {
      await exploiter();
      await cloturer();
      await affectationDirecte().affecter(
        await idExercice(),
        ventilation: {'dividendes': 2000000, 'report_a_nouveau': 5000000},
        date: '${annee + 1}-04-30',
        auteurId: auteurEssai,
      );
      // Un règlement partiel de 8 000 (D 465 / C caisse), dans N.
      final centres = {for (final c in await dao.centres()) c.libelle: c.id};
      await moteurSur(db, maintenant: DateTime.now).passerEtValider(
        DemandePiece(
          journal: 'OD',
          date: '${annee + 1}-05-02',
          libelle: 'Règlement partiel du dividende',
          lignes: [
            LigneDemandee(
              compte: '465',
              debitCentimes: 800000,
              centreId: centres['Structure'],
            ),
            LigneDemandee(compte: '5711', creditCentimes: 800000),
          ],
        ),
        auteurId: auteurEssai,
      );
      await monter(tester, aujourdhui: DateTime(annee + 1, 6, 15, 10));

      await saisir(
        tester,
        'compta-affectation-motif',
        'Ventilation à revoir en assemblée',
      );
      await taper(tester, 'compta-affectation-contrepasser');
      expect(
        erreur(tester),
        contains(
          'un dividende est déjà réglé en tout ou partie (8000.00 réglé sur 20000.00). Annulez d\'abord le règlement',
        ),
      );
      expect(
        (await affectationDirecte().active(await idExercice())),
        isNotNull,
      );
    });
  });
}
