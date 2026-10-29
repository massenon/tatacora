import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/transverse/data/journal_securite_dao.dart';
import 'package:tatacora_flutter/features/transverse/domain/journal_poste.dart';
import 'package:tatacora_flutter/features/transverse/presentation/ecran_journal_audit.dart';
import 'package:tatacora_flutter/features/transverse/presentation/providers_transverses.dart';

/// Le Journal d'Audit du poste : la file d'envoi lue comme la vue lit
/// `journal_audit` — filtre, plafond de 200 lignes, décompte et troncature.
void main() {
  final base = DateTime(2026, 10, 21, 8);

  List<EntreeJournalPoste> entrees(int n) => [
    for (var i = 0; i < n; i++)
      EntreeJournalPoste(
        action: i.isEven
            ? ActionJournalPoste.creation
            : ActionJournalPoste.modification,
        table: i % 3 == 0 ? 'clients' : 'reservations',
        entiteId: 'id-$i',
        dateHeure: base.add(Duration(minutes: i)),
      ),
  ];

  Future<void> monter(
    WidgetTester tester,
    List<EntreeJournalPoste> liste,
  ) async {
    tester.view
      ..physicalSize = const Size(1600, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          droitsProvider.overrideWithValue(const GardeAcces({'M14': 'L'})),
          journalDuPosteProvider.overrideWith((ref) async => liste),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranJournalAudit()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('le filtre garde les plus récentes d\'abord et plafonne à 200', () {
    final vue = filtrerJournalPoste(entrees(250));
    expect(vue.total, 250);
    expect(vue.entrees, hasLength(plafondJournalAudit));
    expect(vue.entrees.first.entiteId, 'id-249');
    final filtre = filtrerJournalPoste(
      entrees(10),
      action: ActionJournalPoste.creation,
    );
    expect(filtre.total, 5);
    final libre = filtrerJournalPoste(entrees(10), recherche: 'client');
    expect(libre.total, 4, reason: 'libellé français de la table');
  });

  testWidgets('le journal de SÉCURITÉ du poste est lu avec la file : qui, quel '
      'compte, quelle action — jamais un secret (29/10/2026)', (tester) async {
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await JournalSecuriteDao(db, horloge: () => base).tracer(
      action: ActionJournalPoste.reinitialisationMotDePasse,
      auteurLogin: 'n.kora',
      cibleId: 'u-1',
      cibleLogin: 'marie',
    );
    await JournalSecuriteDao(db, horloge: () => base).tracer(
      action: ActionJournalPoste.codeSecoursRefuse,
      cibleLogin: 'inconnu',
    );
    tester.view
      ..physicalSize = const Size(1600, 2600)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          baseLocaleProvider.overrideWithValue(db),
          droitsProvider.overrideWithValue(const GardeAcces({'M14': 'L'})),
        ],
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(body: EcranJournalAudit()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Réinitialisation du mot de passe'), findsWidgets);
    expect(find.text('Code de secours refusé'), findsWidgets);
    expect(find.text('Compte utilisateur : marie'), findsOneWidget);
    expect(find.text('Compte utilisateur : inconnu'), findsOneWidget);
    expect(find.text('n.kora'), findsOneWidget, reason: 'l’utilisateur');
    expect(
      find.text('2 entrée(s) au registre pour ce filtre.'),
      findsOneWidget,
    );
    // Libère l'écran (et les flux de la base) avant la fin du cas.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('un journal vide dit la phrase de la vue, sans zéro inventé', (
    tester,
  ) async {
    await monter(tester, const []);
    expect(
      find.text('Aucune entrée ne correspond à votre recherche.'),
      findsOneWidget,
    );
    expect(
      find.text('0 entrée(s) au registre pour ce filtre.'),
      findsOneWidget,
    );
  });

  testWidgets('le décompte réel s\'affiche sous le tableau', (tester) async {
    await monter(tester, entrees(3));
    expect(
      find.text('3 entrée(s) au registre pour ce filtre.'),
      findsOneWidget,
    );
    expect(find.text('Création'), findsWidgets);
    expect(find.text('Client : id-0'), findsOneWidget);
    expect(find.byKey(const Key('journal-source-poste')), findsOneWidget);
  });

  testWidgets('au-delà du plafond, la troncature se voit', (tester) async {
    await monter(tester, entrees(250));
    expect(
      find.text(
        "Seules les 200 entrées les plus récentes sont affichées sur 250. Affinez la recherche ou le filtre d'action pour atteindre les autres.",
      ),
      findsOneWidget,
    );
  });

  testWidgets('la recherche réduit le décompte', (tester) async {
    await monter(tester, entrees(10));
    await tester.enterText(find.byKey(const Key('journal-recherche')), 'id-7');
    await tester.pumpAndSettle();
    expect(
      find.text('1 entrée(s) au registre pour ce filtre.'),
      findsOneWidget,
    );
  });

  testWidgets('l’UTILISATEUR et le POSTE s’affichent quand ils sont connus, '
      '« — » sinon (jamais un compte inventé)', (tester) async {
    await monter(tester, [
      EntreeJournalPoste(
        action: ActionJournalPoste.creation,
        table: 'clients',
        entiteId: 'id-1',
        dateHeure: base,
        utilisateur: 'awa.caisse',
        poste: 'CAISSE-1',
      ),
      EntreeJournalPoste(
        action: ActionJournalPoste.modification,
        table: 'clients',
        entiteId: 'id-2',
        dateHeure: base.add(const Duration(minutes: 1)),
      ),
    ]);

    expect(find.text('awa.caisse'), findsOneWidget);
    expect(find.text('CAISSE-1'), findsOneWidget);
    // L'entrée sans auteur : « — » dans les deux colonnes (et nulle part ailleurs
    // un nom fabriqué). Les colonnes « Détail » n'emploient pas ce tiret.
    expect(find.text('—'), findsNWidgets(2));
  });

  test('la recherche porte aussi sur l’utilisateur, comme la vue', () {
    final liste = [
      EntreeJournalPoste(
        action: ActionJournalPoste.creation,
        table: 'clients',
        entiteId: 'a',
        dateHeure: base,
        utilisateur: 'awa.caisse',
      ),
      EntreeJournalPoste(
        action: ActionJournalPoste.creation,
        table: 'clients',
        entiteId: 'b',
        dateHeure: base,
        utilisateur: 'koffi',
      ),
      EntreeJournalPoste(
        action: ActionJournalPoste.creation,
        table: 'clients',
        entiteId: 'c',
        dateHeure: base,
      ),
    ];
    final vue = filtrerJournalPoste(liste, recherche: 'AWA');
    expect(vue.entrees.map((e) => e.entiteId), ['a']);
  });
}
