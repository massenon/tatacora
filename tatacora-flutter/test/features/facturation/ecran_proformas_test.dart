import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/facturation/data/proforma_dao.dart';
import 'package:tatacora_flutter/features/facturation/domain/reglages_documents.dart';
import 'package:tatacora_flutter/features/facturation/domain/textes_proforma.dart';
import 'package:tatacora_flutter/features/facturation/presentation/ecran_proformas.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_facturation.dart';
import 'package:tatacora_flutter/features/facturation/presentation/providers_proformas.dart';

/// L'écran « Proformas » du poste (PO, 07/11/2026) : hors ligne, droits M2, mêmes libellés que le web,
/// aucun débordement de 320 à 1600 px.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late List<String> imprimees;
  late ProformaDao dao;

  setUp(() {
    db = AppDatabase.enMemoire();
    dao = ProformaDao(db);
    imprimees = [];
  });
  tearDown(() => db.close());

  Future<void> monter(
    WidgetTester tester, {
    double largeur = 1600,
    String niveau = 'C',
    String flux = '',
    ReglagesDocuments reglages = ReglagesDocuments.parDefaut,
  }) async {
    tester.view
      ..physicalSize = Size(largeur, 1000)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(
            GardeAcces.depuisJson({'M2': niveau}),
          ),
          imprimerProformaProvider.overrideWithValue(
            (id) async => imprimees.add(id),
          ),
          reglagesDocumentsProvider.overrideWith((ref) async => reglages),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: Scaffold(body: EcranProformas(flux: flux)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> saisir(WidgetTester t, String cle, String texte) async {
    await t.enterText(find.byKey(Key(cle)), texte);
    await t.pump();
  }

  Future<void> toucher(WidgetTester t, String cle) async {
    await t.ensureVisible(find.byKey(Key(cle)));
    await t.tap(find.byKey(Key(cle)));
    await t.pumpAndSettle();
  }

  const lignes = [(designation: 'Salle', quantite: 2, prixUnitaire: 50000)];

  testWidgets(
    'hors ligne : saisie libre, émission avec numéro PROVISOIRE, puis conversion confirmée',
    (tester) async {
      await monter(tester);
      expect(find.byKey(const Key('proformas-vide')), findsOneWidget);

      await toucher(tester, 'proformas-nouvelle');
      await saisir(tester, 'proforma-client', 'SARL KORA');
      await saisir(tester, 'proforma-objet', 'Atelier');
      await saisir(tester, 'proforma-ligne-0-designation', 'Salle');
      await saisir(tester, 'proforma-ligne-0-quantite', '2');
      await saisir(tester, 'proforma-ligne-0-prix', '50000');
      await toucher(tester, 'proforma-enregistrer-emettre');

      final p = (await dao.liste()).single;
      expect(p.numero, startsWith('PROV-FP-'));
      expect(p.total, 100000);
      expect(find.text(p.numero!), findsOneWidget);
      expect(find.text(TextesProforma.statut['emise']!), findsOneWidget);
      expect(find.byKey(const Key('proforma-message')), findsOneWidget);

      await toucher(tester, 'proforma-convertir-${p.id}');
      expect(
        find.text(TextesProforma.ui['conversion_message']!),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('proforma-conversion-expiree')),
        findsNothing,
      );
      await toucher(tester, 'proforma-conversion-confirmer');

      expect((await dao.parId(p.id))!.statut, 'convertie');
      // Convertie : immuable — plus de Modifier / Convertir / Annuler.
      expect(find.byKey(Key('proforma-modifier-${p.id}')), findsNothing);
      expect(find.byKey(Key('proforma-convertir-${p.id}')), findsNothing);
      expect(find.byKey(Key('proforma-annuler-${p.id}')), findsNothing);
    },
  );

  testWidgets('une ligne invalide est refusée avec la phrase du serveur', (
    tester,
  ) async {
    await monter(tester);
    await toucher(tester, 'proformas-nouvelle');
    await saisir(tester, 'proforma-client', 'SARL KORA');
    await toucher(tester, 'proforma-enregistrer');
    expect(find.text(RefusProforma.ligneInvalide), findsOneWidget);
    expect(await dao.liste(), isEmpty);
  });

  testWidgets('l\'annulation exige un motif et garde le numéro', (
    tester,
  ) async {
    final p = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
    await monter(tester);
    await toucher(tester, 'proforma-annuler-${p.id}');
    await toucher(tester, 'proforma-annulation-confirmer');
    expect((await dao.parId(p.id))!.statut, 'emise');

    await saisir(tester, 'proforma-motif', 'Client désisté');
    await toucher(tester, 'proforma-annulation-confirmer');
    final a = (await dao.parId(p.id))!;
    expect(a.statut, 'annulee');
    expect(a.numero, p.numero);
    expect(find.text(TextesProforma.statut['annulee']!), findsWidgets);
  });

  testWidgets(
    'une proforma EXPIRÉE se dit, et se convertit avec confirmation',
    (tester) async {
      final p = await dao.creer(
        clientNom: 'A',
        lignes: lignes,
        emettre: true,
        reglages: ReglagesDocuments.depuis({
          ClesReglagesDocuments.validiteAffichee: 'true',
          ClesReglagesDocuments.validiteJours: '1',
        }),
      );
      await (db.update(
        db.proformasLocal,
      )..where((t) => t.id.equals(p.id))).write(
        ProformasLocalCompanion(valideJusquAu: Value(DateTime(2020, 1, 1))),
      );
      await monter(tester);

      expect(find.text(TextesProforma.statut['expiree']!), findsOneWidget);
      await toucher(tester, 'proforma-convertir-${p.id}');
      expect(
        find.byKey(const Key('proforma-conversion-expiree')),
        findsOneWidget,
      );
      await toucher(tester, 'proforma-conversion-confirmer');
      expect((await dao.parId(p.id))!.statut, 'convertie');
    },
  );

  testWidgets('le filtre par statut et la recherche', (tester) async {
    final a = await dao.creer(
      clientNom: 'ALPHA',
      lignes: lignes,
      emettre: true,
    );
    final b = await dao.creer(clientNom: 'BRAVO', lignes: lignes);
    await monter(tester);
    expect(find.byKey(Key('proforma-${a.id}')), findsOneWidget);
    expect(find.byKey(Key('proforma-${b.id}')), findsOneWidget);

    await saisir(tester, 'proformas-recherche', 'bravo');
    expect(find.byKey(Key('proforma-${a.id}')), findsNothing);
    expect(find.byKey(Key('proforma-${b.id}')), findsOneWidget);
    await saisir(tester, 'proformas-recherche', '');

    await tester.tap(find.byKey(const Key('proformas-filtre-statut')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TextesProforma.statut['emise']!).last);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('proforma-${a.id}')), findsOneWidget);
    expect(find.byKey(Key('proforma-${b.id}')), findsNothing);
  });

  testWidgets(
    'en lecture seule (M2 = L) : on voit et on imprime, on n\'écrit rien',
    (tester) async {
      final p = await dao.creer(clientNom: 'A', lignes: lignes, emettre: true);
      await monter(tester, niveau: 'L');

      expect(find.byKey(const Key('proformas-nouvelle')), findsNothing);
      expect(find.byKey(Key('proforma-modifier-${p.id}')), findsNothing);
      expect(find.byKey(Key('proforma-convertir-${p.id}')), findsNothing);
      expect(find.byKey(Key('proforma-annuler-${p.id}')), findsNothing);
      await toucher(tester, 'proforma-pdf-${p.id}');
      expect(imprimees, [p.id]);
    },
  );

  testWidgets('un événement ouvre la proforma VIDE, prête à remplir', (
    tester,
  ) async {
    await monter(tester, flux: 'evenement');
    expect(find.byKey(const Key('proforma-client')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(TextesProforma.ui['form_titre_creation']!),
      ),
      findsOneWidget,
    );
  });

  testWidgets('une arrivée sans droit d\'écriture n\'ouvre aucune saisie', (
    tester,
  ) async {
    await monter(tester, flux: 'evenement', niveau: 'L');
    expect(find.byKey(const Key('proforma-client')), findsNothing);
  });

  for (final largeur in [320.0, 600.0, 1600.0]) {
    testWidgets('aucun débordement à ${largeur.toInt()} px (liste et saisie)', (
      tester,
    ) async {
      final p = await dao.creer(
        clientNom: 'SOCIÉTÉ DE TRANSPORT ET DE TOURISME DU GRAND NORD',
        objet: 'Séjour de groupe avec restauration et excursions guidées',
        lignes: lignes,
        emettre: true,
      );
      await monter(tester, largeur: largeur);
      expect(tester.takeException(), isNull);
      expect(find.byKey(Key('proforma-${p.id}')), findsOneWidget);

      await toucher(tester, 'proformas-nouvelle');
      expect(tester.takeException(), isNull);
      await toucher(tester, 'proforma-ajouter-ligne');
      expect(tester.takeException(), isNull);
    });
  }
}
