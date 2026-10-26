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
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/providers_comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/onglets_etats_financiers.dart';

import 'support/outils_comptabilite.dart';

/// Compte de résultat et bilan SUR LE POSTE (21/10/2026) : lus des écritures
/// validées reçues du serveur, avec la colonne N-1, les bandeaux de la vue et
/// l'encadré de provenance. Le calcul lui-même est confronté au serveur dans
/// `etats_financiers_contre_serveur_test.dart`.
void main() {
  late AppDatabase db;
  final annee = DateTime.now().year;

  setUp(() async => db = await baseInstallee(maintenant: DateTime.now()));
  tearDown(() => db.close());

  String fcfa(int centimes) =>
      formaterMontantDecimal('${centimes ~/ 100}.00', suffixe: 'FCFA')!;

  Future<void> recevoir(
    int a,
    String journal,
    String compte, {
    int debit = 0,
    int credit = 0,
    String? classe,
  }) => EcrituresServeurDao(db).ajouterSiAbsente(
    id: 'e-$a-$journal-$compte-$debit-$credit',
    annee: a,
    codeJournal: journal,
    numeroCompte: compte,
    libelleCompte: 'Compte $compte',
    classe: classe ?? compte.substring(0, 1),
    dateEcriture: '$a-06-15',
    libelle: 'Pièce',
    debitCentimes: debit,
    creditCentimes: credit,
  );

  String texteDe(WidgetTester tester, String cle) =>
      tester.widget<Text>(find.byKey(Key(cle))).data!;

  Future<void> monter(WidgetTester tester, String onglet) async {
    tester.view
      ..physicalSize = const Size(1800, 3200)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final garde = GardeAcces.depuisJson(const {'M10': 'C'});
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

  testWidgets('rien reçu : le compte de résultat est à zéro, avant impôt, et '
      'le DIT', (tester) async {
    await monter(tester, 'resultat');

    expect(
      find.byKey(const Key('compta-non-calcule-resultat')),
      findsNothing,
      reason: 'l’onglet n’est plus « non calculé »',
    );
    expect(find.text(TextesEtatsFinanciers.titreResultat), findsOneWidget);
    expect(
      find.byKey(const Key('compta-resultat-avant-impot')),
      findsOneWidget,
    );
    expect(find.text(TextesEtatsFinanciers.libelleAvantImpot), findsOneWidget);
    expect(find.textContaining('Aucune écriture du serveur'), findsNothing);
  });

  testWidgets('les écritures reçues donnent le résultat, la colonne N-1 et '
      'la provenance', (tester) async {
    final dao = ComptabiliteDao(db);
    await dao.alignerExerciceDescendu(
      annee: annee - 1,
      dateDebut: '${annee - 1}-01-01',
      dateFin: '${annee - 1}-12-31',
      statut: StatutExercice.cloture,
      dateCloture: DateTime(annee, 1, 20),
    );
    await recevoir(annee, 'VTE', '5711', debit: 250000);
    await recevoir(annee, 'VTE', '7061', credit: 250000);
    await recevoir(annee, 'ACH', '6011', debit: 100000);
    await recevoir(annee, 'ACH', '4011', credit: 100000);
    await recevoir(annee - 1, 'VTE', '5711', debit: 70000);
    await recevoir(annee - 1, 'VTE', '7061', credit: 70000);
    await monter(tester, 'resultat');

    // 2 500 − 1 000 = 1 500 au net ; 700 l'an dernier.
    expect(texteDe(tester, 'compta-resultat-net'), fcfa(150000));
    expect(
      find.text(
        TextesEtatsFinanciers.colonnePrecedente(annee - 1).toUpperCase(),
      ),
      findsOneWidget,
    );
    expect(find.text(fcfa(70000)), findsWidgets, reason: 'colonne N-1');
    expect(
      find.textContaining('écriture(s)'),
      findsNothing,
      reason: 'aucun encadré de provenance à l’écran',
    );
  });

  testWidgets('un bilan équilibré ne crie pas ; un bilan sans contrepartie '
      'dit son écart', (tester) async {
    await recevoir(annee, 'OD', '5711', debit: 500000);
    await recevoir(annee, 'OD', '101', credit: 500000);
    await monter(tester, 'bilan');

    expect(find.byKey(const Key('compta-bilan-desequilibre')), findsNothing);
    expect(texteDe(tester, 'compta-bilan-total-actif'), fcfa(500000));
    expect(texteDe(tester, 'compta-bilan-total-passif'), fcfa(500000));
    expect(find.text(TextesEtatsFinanciers.totalActif), findsOneWidget);
    expect(find.text(TextesEtatsFinanciers.totalPassif), findsOneWidget);
  });

  testWidgets('une écriture reçue seule rend le bilan déséquilibré, et le '
      'dit avec son écart', (tester) async {
    await recevoir(annee, 'OD', '5711', debit: 300000);
    await monter(tester, 'bilan');

    expect(find.byKey(const Key('compta-bilan-desequilibre')), findsOneWidget);
    expect(
      find.textContaining(
        TextesEtatsFinanciers.ecartBilan(fcfa(300000)),
        findRichText: true,
      ),
      findsOneWidget,
    );
  });

  testWidgets('un compte hors nomenclature est listé, jamais avalé', (
    tester,
  ) async {
    await recevoir(annee, 'OD', '4431', credit: 100000);
    await recevoir(annee, 'OD', '5711', debit: 100000);
    await monter(tester, 'bilan');

    expect(find.byKey(const Key('compta-bilan-hors-rubrique')), findsOneWidget);
    expect(find.textContaining('4431'), findsWidgets);
    expect(find.text(TextesEtatsFinanciers.horsRubriqueTitre), findsOneWidget);
  });
}
