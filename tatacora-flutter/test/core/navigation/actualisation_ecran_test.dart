import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/actualisation_ecran.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/ventes/presentation/ecran_historique_ventes.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart'
    show baseInstalleeSur, moteurSur;
import '../../features/facturation/support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;
import '../../support/coquille_montee.dart';

/// « Actualiser » : clic droit, F5 et Ctrl+R relisent la BASE LOCALE.
///
/// Le cas qui compte : une ligne est écrite en base SANS invalider un seul
/// provider ; l'écran ne la montre pas (le cache ment) ; « Actualiser » la fait
/// apparaître. Sans l'invalidation, ce cas rougit (mutation éprouvée).
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const complet = {
    'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
    'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
    'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
  };
  DateTime maintenant() => DateTime(2026, 8, 26, 18);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  late AppDatabase db;
  late PanierDao paniers;

  setUp(() async {
    db = AppDatabase.enMemoire();
    await ouvrirLaCaisseDuComptoir(db);
    await baseInstalleeSur(db, maintenant());
    paniers = PanierDao(
      db,
      maintenant: maintenant,
      moteur: () async => moteurSur(db, maintenant: maintenant),
    );
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  /// Une vente encaissée, écrite DIRECTEMENT par le DAO : aucun provider n'est
  /// invalidé, comme un autre poste ou un autre onglet qui écrirait en base.
  Future<Panier> venteEnBase() async {
    var p = await paniers.ouvrir(
      typeVente: TypeVente.comptant,
      pointVente: 'Bar principal',
    );
    p = await paniers.ajouterLigne(p.id, biere, quantite: 1);
    return paniers.cloturer(
      p.id,
      modePaiement: 'especes',
      auteurId: caissierEssai,
    );
  }

  Future<void> monter(WidgetTester tester) => monterCoquille(
    tester,
    role: 'administrateur',
    droits: complet,
    routeActive: '/historique-ventes',
    taille: const Size(1600, 1200),
    enfant: const EcranHistoriqueVentes(),
    surcharges: [baseLocaleProvider.overrideWithValue(db)],
  );

  Future<void> clicDroit(WidgetTester tester, Offset position) async {
    final geste = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await geste.down(position);
    await geste.up();
    await tester.pumpAndSettle();
  }

  Offset horsChamp(WidgetTester tester) =>
      tester.getCenter(find.byType(EcranHistoriqueVentes)) +
      const Offset(0, 300);

  final menu = find.byKey(const Key('menu-actualiser'));

  testWidgets('le clic droit sur un écran réel affiche « Actualiser »', (
    tester,
  ) async {
    await monter(tester);
    expect(menu, findsNothing);

    await clicDroit(tester, horsChamp(tester));

    expect(menu, findsOneWidget);
    expect(
      find.descendant(of: menu, matching: find.text('Actualiser')),
      findsOneWidget,
      reason: 'libellé exact demandé par le PO',
    );
  });

  testWidgets('le clic gauche n’ouvre aucun menu', (tester) async {
    await monter(tester);
    await tester.tapAt(horsChamp(tester));
    await tester.pumpAndSettle();
    expect(menu, findsNothing);
  });

  testWidgets('« Actualiser » relit la base : une ligne écrite SANS invalider '
      'apparaît (preuve que le rechargement est réel)', (tester) async {
    await monter(tester);

    final p = await tester.runAsync(venteEnBase);
    await tester.pumpAndSettle();
    final ligne = find.byKey(Key('vente-ligne-${p!.id}'));
    expect(
      ligne,
      findsNothing,
      reason:
          'la lecture est en cache : sans actualisation, la vente est absente',
    );

    await clicDroit(tester, horsChamp(tester));
    await tester.tap(menu);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(menu, findsNothing, reason: 'le menu se referme au choix');
    expect(ligne, findsOneWidget);
  });

  testWidgets('F5 et Ctrl+R déclenchent la même actualisation', (tester) async {
    await monter(tester);
    final p = await tester.runAsync(venteEnBase);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('vente-ligne-${p!.id}')), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('vente-ligne-${p.id}')), findsOneWidget);

    final q = await tester.runAsync(venteEnBase);
    await tester.pumpAndSettle();
    expect(find.byKey(Key('vente-ligne-${q!.id}')), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('vente-ligne-${q.id}')), findsOneWidget);
  });

  testWidgets('sur un champ de saisie, le menu « Actualiser » n’apparaît pas '
      '(le champ garde son menu natif)', (tester) async {
    await monter(tester);
    await clicDroit(
      tester,
      tester.getCenter(find.byKey(const Key('ventes-recherche'))),
    );
    expect(menu, findsNothing);
  });

  testWidgets('une modale ouverte : le menu n’agit pas, la modale reste', (
    tester,
  ) async {
    await monter(tester);
    final contexte = tester.element(find.byType(EcranHistoriqueVentes));
    showDialog<void>(
      context: contexte,
      builder: (_) => const AlertDialog(content: Text('Modale de l’essai')),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await clicDroit(tester, tester.getCenter(find.text('Modale de l’essai')));
    await tester.pumpAndSettle();

    expect(menu, findsNothing);
    expect(find.text('Modale de l’essai'), findsOneWidget);
  });

  group('ce que l’actualisation ne touche pas', () {
    test('seules les lectures asynchrones sont invalidées : la session, la '
        'base et les états de saisie restent', () async {
      var lectures = 0;
      final lecture = FutureProvider<int>((ref) async => ++lectures);
      final filtre = NotifierProvider<_Filtre, String>(_Filtre.new);
      final conteneur = ProviderContainer(
        overrides: [baseLocaleProvider.overrideWithValue(db)],
      );
      addTearDown(conteneur.dispose);
      conteneur.listen(lecture, (_, _) {});
      await conteneur.read(lecture.future);
      conteneur.read(filtre.notifier).filtre = 'bar';
      final base = conteneur.read(baseLocaleProvider);

      conteneur.read(actualisationEcranProvider.notifier).actualiser();
      final relue = await conteneur.read(lecture.future);

      expect(relue, 2, reason: 'la lecture a été relancée');
      expect(conteneur.read(filtre), 'bar', reason: 'le filtre est gardé');
      expect(conteneur.read(baseLocaleProvider), same(base));
      expect(conteneur.read(actualisationEcranProvider), 1);
    });

    test('les deux lectures qui ne sont pas des lectures d’écran sont '
        'déclarées conservées', () {
      expect(lecturesConservees, hasLength(2));
    });
  });

  testWidgets('hors coquille, ZoneActualisation seule fonctionne aussi '
      '(écran de connexion facultatif)', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.clair,
          home: const Scaffold(
            body: ZoneActualisation(child: SizedBox.expand()),
          ),
        ),
      ),
    );
    await clicDroit(tester, const Offset(200, 200));
    expect(menu, findsOneWidget);
  });
}

final class _Filtre extends Notifier<String> {
  @override
  String build() => '';
  set filtre(String v) => state = v;
}
