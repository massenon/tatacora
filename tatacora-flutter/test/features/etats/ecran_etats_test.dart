import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/etats/domain/apercu_etat.dart';
import 'package:tatacora_flutter/features/etats/domain/entities/etat_catalogue.dart';
import 'package:tatacora_flutter/features/etats/presentation/ecran_etats.dart';
import 'package:tatacora_flutter/features/etats/presentation/providers_etats.dart';
import 'package:tatacora_flutter/features/etats/presentation/widgets/panneau_apercu_etat.dart';
import 'package:tatacora_flutter/features/etats/presentation/widgets/textes_etats.dart';

/// L'écran États & Rapports, confronté à `pwa/etats/studio.blade.php`.
///
/// Reprise du 09/10/2026 (D48). Ce fichier n'existait pas : l'écran n'avait
/// AUCUN test propre, seulement les mesures de géométrie et d'emplacement.
/// Chaque cas est une valeur ou un libellé EXACT, relu de la vue Blade ou de
/// `lang/fr/pwa.php` (`etats.*`), et a été prouvé non vide par mutation.
EtatCatalogue _etat(String code, String module, String libelle) =>
    EtatCatalogue(
      code: code,
      module: module,
      libelle: libelle,
      niveau: NiveauAcces.complet,
    );

/// Cinq états sur quatre modules, dans un ordre de réponse VOLONTAIREMENT
/// différent de l'ordre alphabétique des codes ET de l'ordre du CdCF :
/// M6, M11, M8, M8, M1.
final List<EtatCatalogue> _catalogue = [
  _etat('stocks', 'M6', 'État des stocks'),
  _etat('tableau-de-bord', 'M11', 'Tableau de bord — synthèse consolidée'),
  _etat('parc-vehicules', 'M8', 'État du parc de véhicules'),
  _etat('locations', 'M8', 'État des locations de véhicules'),
  _etat('reservations', 'M1', 'État des réservations'),
];

Future<void> _monter(
  WidgetTester tester, {
  List<EtatCatalogue>? catalogue,
  Size taille = const Size(1600, 1000),
}) async {
  tester.view
    ..physicalSize = taille
    ..devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogueEtatsProvider.overrideWith(
          (ref) async => catalogue ?? _catalogue,
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.clair,
        home: const Scaffold(body: EcranEtats()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _texte(WidgetTester tester, Key cle) {
  final w = tester.widget<Text>(find.byKey(cle));
  return w.data ?? w.textSpan!.toPlainText();
}

/// 61 états : la liste dépasse largement 1 000 px de haut.
List<EtatCatalogue> _longue() => [
  _catalogue.first,
  for (var i = 0; i < 60; i++) _etat('x$i', 'M6', 'État numéro $i'),
];

void main() {
  group('La barre d’outils (studio.blade.php l.40-58)', () {
    testWidgets('porte le titre, et ni période ni export', (tester) async {
      await _monter(tester);

      // Le titre : `pwa.etats.titre`. Une seule occurrence à l'accueil.
      expect(find.text('États & Rapports'), findsOneWidget);

      // l.50-55 : « Période », « Exercice », « Imprimer », « Excel » et
      // « PDF » sont ABSENTS, pas grisés (Article 3.3).
      for (final libelle in [
        'Imprimer',
        'Excel',
        'PDF',
        'Période',
        'Exercice',
      ]) {
        expect(find.textContaining(libelle), findsNothing, reason: libelle);
      }
      for (final cle in [
        'etats-imprimer',
        'etats-excel',
        'etats-pdf',
        'etats-periode-refusee',
        'etats-non-rendu',
      ]) {
        expect(find.byKey(Key(cle)), findsNothing, reason: cle);
      }
    });

    testWidgets('reste sans bouton une fois un état choisi', (tester) async {
      await _monter(tester);
      await tester.tap(find.byKey(const Key('etats-entree-stocks')));
      await tester.pumpAndSettle();

      expect(find.text('Imprimer'), findsNothing);
      expect(find.text('Excel'), findsNothing);
      expect(find.text('PDF'), findsNothing);
      expect(find.byType(GestureDetector).evaluate().length, greaterThan(0));
    });
  });

  group('Le catalogue (l.62-115)', () {
    testWidgets('groupe dans l’ordre de la réponse, avec le CODE seul', (
      tester,
    ) async {
      await _monter(tester);

      // `collect($liste)->groupBy('module')` (l.87) : ordre d'apparition,
      // M6, M11, M8, M1 — ni alphabétique, ni celui du CdCF.
      final y = <String, double>{
        for (final m in ['M6', 'M11', 'M8', 'M1'])
          m: tester.getTopLeft(find.byKey(Key('etats-groupe-$m'))).dy,
      };
      expect(y['M6']! < y['M11']!, isTrue);
      expect(y['M11']! < y['M8']!, isTrue);
      expect(y['M8']! < y['M1']!, isTrue);

      // `{{ $codeModule }}` (l.89) : « M6 », pas « M6 — STOCKS ».
      expect(_texte(tester, const Key('etats-groupe-M6')), 'M6');
      expect(_texte(tester, const Key('etats-groupe-M1')), 'M1');
    });

    testWidgets('les pastilles : Tous, puis les codes triés comme sort()', (
      tester,
    ) async {
      final etats = [
        ..._catalogue,
        _etat('compte-resultat', 'M10', 'Compte de résultat'),
        _etat('clients', 'M3', 'Clients'),
      ];
      await _monter(tester, catalogue: etats);

      // PHP `sort(['M6','M11','M8','M1','M10','M3'])` : tri de chaînes.
      final attendu = ['M1', 'M10', 'M11', 'M3', 'M6', 'M8'];
      final pos = <String, Offset>{
        'Tous': tester.getTopLeft(find.byKey(const Key('etats-module-tous'))),
        for (final m in attendu)
          m: tester.getTopLeft(find.byKey(Key('etats-module-$m'))),
      };
      // Les pastilles passent à la ligne (`flex-wrap`) : ordre de LECTURE,
      // de haut en bas puis de gauche à droite.
      final ordre = pos.keys.toList()
        ..sort((a, b) {
          final dy = pos[a]!.dy - pos[b]!.dy;
          return dy.abs() > 2
              ? dy.sign.toInt()
              : pos[a]!.dx.compareTo(pos[b]!.dx);
        });
      expect(ordre, ['Tous', ...attendu]);
    });

    test('modulesDuCatalogue : tri de chaînes, sans doublon', () {
      expect(
        modulesDuCatalogue([
          _etat('a', 'M6', 'A'),
          _etat('b', 'M10', 'B'),
          _etat('c', 'M6', 'C'),
          _etat('d', 'M1', 'D'),
          _etat('e', 'M3', 'E'),
        ]),
        ['M1', 'M10', 'M3', 'M6'],
      );
    });

    test('grouperParModule : ordre d’apparition, en-tête = code', () {
      final groupes = grouperParModule(_catalogue);
      expect([for (final g in groupes) g.module], ['M6', 'M11', 'M8', 'M1']);
      expect([for (final g in groupes) g.enTete], ['M6', 'M11', 'M8', 'M1']);
      expect(
        [for (final e in groupes[2].etats) e.code],
        ['parc-vehicules', 'locations'],
      );
    });

    testWidgets('l’invite de recherche porte DEUX espaces, comme la clé', (
      tester,
    ) async {
      await _monter(tester);
      final champ = tester.widget<TextField>(
        find.byKey(const Key('etats-recherche')),
      );
      expect(champ.decoration!.hintText, 'Rechercher un état…  (touche /)');
    });

    testWidgets('le compteur dit le nombre d’états rendus', (tester) async {
      await _monter(tester);
      expect(
        _texte(tester, const Key('etats-compteur')),
        '5 état(s) · droits portés par le module source',
      );
    });

    testWidgets('une pastille de module filtre, « Tous » rétablit', (
      tester,
    ) async {
      await _monter(tester);

      await tester.tap(find.byKey(const Key('etats-module-M8')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('etats-entree-parc-vehicules')), findsOne);
      expect(find.byKey(const Key('etats-entree-locations')), findsOne);
      expect(find.byKey(const Key('etats-entree-stocks')), findsNothing);
      expect(find.byKey(const Key('etats-groupe-M6')), findsNothing);
      expect(
        _texte(tester, const Key('etats-compteur')),
        '2 état(s) · droits portés par le module source',
      );

      await tester.tap(find.byKey(const Key('etats-module-tous')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('etats-entree-stocks')), findsOne);
      expect(
        _texte(tester, const Key('etats-compteur')),
        '5 état(s) · droits portés par le module source',
      );
    });

    testWidgets('la recherche porte sur le libellé ET le module', (
      tester,
    ) async {
      await _monter(tester);

      await tester.enterText(find.byKey(const Key('etats-recherche')), 'PARC');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('etats-entree-parc-vehicules')), findsOne);
      expect(find.byKey(const Key('etats-entree-stocks')), findsNothing);

      // « m11 » n'est dans aucun libellé : seul le module le porte.
      await tester.enterText(find.byKey(const Key('etats-recherche')), 'm11');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('etats-entree-tableau-de-bord')), findsOne);
      expect(
        find.byKey(const Key('etats-entree-parc-vehicules')),
        findsNothing,
      );

      await tester.enterText(find.byKey(const Key('etats-recherche')), 'zzz');
      await tester.pumpAndSettle();
      expect(
        _texte(tester, const Key('etats-catalogue-vide')),
        'Aucun état ne correspond.',
      );
    });

    testWidgets('la touche / place le curseur dans la recherche', (
      tester,
    ) async {
      await _monter(tester);
      FocusNode noeud() => tester
          .widget<TextField>(find.byKey(const Key('etats-recherche')))
          .focusNode!;

      expect(noeud().hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(noeud().hasFocus, isTrue);
    });

    testWidgets('l’entrée sélectionnée est navy, les autres non', (
      tester,
    ) async {
      await _monter(tester);
      Color? fond(String code) {
        final c = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(Key('etats-entree-$code')),
                matching: find.byType(Container),
              )
              .first,
        );
        return (c.decoration as BoxDecoration).color;
      }

      expect(fond('stocks'), isNull);
      await tester.tap(find.byKey(const Key('etats-entree-stocks')));
      await tester.pumpAndSettle();
      expect(fond('stocks'), AppColors.navy);
      expect(fond('locations'), isNull);
    });

    testWidgets('sans débordement, l’entrée prend les 330 px du catalogue', (
      tester,
    ) async {
      await _monter(tester, catalogue: _catalogue.take(3).toList());
      expect(
        tester.getSize(find.byKey(const Key('etats-entree-stocks'))).width,
        AppLayout.catalogueEtats,
      );
    });

    testWidgets('la barre de défilement réserve ses 8 px quand ça déborde', (
      tester,
    ) async {
      await _monter(tester, catalogue: _longue());
      expect(
        tester.getSize(find.byKey(const Key('etats-entree-stocks'))).width,
        AppLayout.catalogueEtats - AppLayout.gouttiereDefilement,
      );
      expect(AppLayout.gouttiereDefilement, 8);
    });

    testWidgets('filtrer jusqu’à ne plus déborder rend les 8 px', (
      tester,
    ) async {
      await _monter(tester, catalogue: _longue());
      expect(
        tester.getSize(find.byKey(const Key('etats-entree-stocks'))).width,
        322,
      );

      await tester.enterText(
        find.byKey(const Key('etats-recherche')),
        'stocks',
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(const Key('etats-entree-stocks'))).width,
        330,
      );
    });
  });

  group('L’accueil (l.119-131)', () {
    testWidgets('dit le titre, le décompte et la note des droits', (
      tester,
    ) async {
      await _monter(tester);

      expect(find.text('Choisissez un état dans le catalogue'), findsOne);
      // `pwa.etats.accueil_detail`, AU MOT : la seconde phrase est vraie
      // depuis que ce poste calcule l'aperçu (10/10/2026). Un test relit la
      // langue du serveur (`registre_contre_serveur_test.dart`).
      expect(
        _texte(tester, const Key('etats-accueil-decompte')),
        "5 état(s) sont éditables avec vos droits. L'aperçu s'affiche "
        "immédiatement : vous ne consultez que ce que le moteur d'états "
        'calcule réellement.',
      );
      // `pwa.etats.accueil_rbac`, apostrophe droite, `<strong>` rendu en gras.
      expect(
        _texte(tester, const Key('etats-accueil-rbac')),
        'Les droits sont portés par le module source de chaque état, pas par '
        "M14 : un magasinier ne lit pas le livre de paie parce qu'il a accès "
        'aux « États ».',
      );
    });

    testWidgets('« module source » est en gras, le reste de la note non', (
      tester,
    ) async {
      await _monter(tester);
      final racine = tester
          .widget<Text>(find.byKey(const Key('etats-accueil-rbac')))
          .textSpan!;
      final gras = <String>[];
      racine.visitChildren((s) {
        if (s is TextSpan &&
            s.text != null &&
            s.style?.fontWeight == FontWeight.bold) {
          gras.add(s.text!);
        }
        return true;
      });
      expect(gras, ['module source']);
    });

    testWidgets('annonce l’aperçu immédiat, ce qui est VRAI depuis le 10/10', (
      tester,
    ) async {
      await _monter(tester);
      expect(find.textContaining('immédiatement'), findsOne);
      expect(find.textContaining('vous ne consultez que'), findsOne);
      // L'ancienne seconde phrase disait le contraire.
      expect(find.textContaining('vit au serveur'), findsNothing);
      expect(find.textContaining('ne s’affiche pas'), findsNothing);
    });

    testWidgets('le bloc est centré dans la hauteur du panneau', (
      tester,
    ) async {
      await _monter(tester);
      final panneau = tester.getRect(find.byKey(const Key('etats-accueil')));
      final haut = tester
          .getTopLeft(find.byIcon(Icons.description_outlined).last)
          .dy;
      final bas = tester
          .getBottomLeft(find.byKey(const Key('etats-accueil-rbac')))
          .dy;
      // `h-full flex items-center justify-center p-8` : marges égales en haut
      // et en bas, au pixel près (le `p-8` est symétrique).
      expect(haut - panneau.top, closeTo(panneau.bottom - bas, 0.5));
    });

    test('le décompte est « — » tant que le catalogue n’est pas lu', () {
      const fin =
          " état(s) sont éditables avec vos droits. L'aperçu s'affiche "
          "immédiatement : vous ne consultez que ce que le moteur d'états "
          'calcule réellement.';
      expect(decompteAccueilEtats(null), '—$fin');
      expect(decompteAccueilEtats(0), '0$fin');
      expect(decompteAccueilEtats(12), '12$fin');
    });

    testWidgets('catalogue vide : « 0 », qui est une mesure, et rien d’autre', (
      tester,
    ) async {
      // Le catalogue est COMPOSÉ ici, depuis les droits : une liste vide veut
      // dire « aucun module source lisible », pas « catalogue non reçu ».
      await _monter(tester, catalogue: const <EtatCatalogue>[]);

      expect(
        _texte(tester, const Key('etats-compteur')),
        '0 état(s) · droits portés par le module source',
      );
      expect(
        _texte(tester, const Key('etats-accueil-decompte')),
        startsWith('0 état(s) sont éditables'),
      );
      expect(
        _texte(tester, const Key('etats-catalogue-vide')),
        'Aucun état ne correspond.',
      );
    });
  });

  group('L’aperçu (l.132-203)', () {
    ApercuEtat apercu({List<List<String>>? lignes}) => ApercuEtat(
      code: 'stocks',
      titre: 'État des stocks — tous points de stockage',
      periode: 'Arrêté au 09/10/2026 à 14:03',
      moduleSource: 'M6',
      indicateurs: const [
        IndicateurApercu('Références', '2'),
        IndicateurApercu('Valeur du stock (CMP)', ''),
      ],
      entetes: const ['Article', 'Quantité', 'Valeur'],
      lignes:
          lignes ??
          const [
            ['Riz', '12.50', '125000.00'],
            ['Sel', 'non suivi', ''],
            ['Huile', '3.00', '9000.00'],
          ],
      mentions: const ['Première mention.', 'Seconde mention.'],
    );

    Future<void> monterAvec(
      WidgetTester tester,
      ResultatApercu Function(String code) resultat,
    ) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogueEtatsProvider.overrideWith((ref) async => _catalogue),
            apercuEtatProvider.overrideWith(
              (ref, code) async => resultat(code),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranEtats()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('etats-entree-stocks')));
      await tester.pumpAndSettle();
    }

    testWidgets('titre, période, module source et nombre de lignes', (
      tester,
    ) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu()));

      // L'accueil a cédé la place.
      expect(find.byKey(const Key('etats-accueil')), findsNothing);
      expect(
        _texte(tester, const Key('etats-apercu-titre')),
        'État des stocks — tous points de stockage',
      );
      // `{{ $periodeEtat }} · module source M6 · N ligne(s)` (l.140-144).
      expect(
        _texte(tester, const Key('etats-apercu-sous-ligne')),
        'Arrêté au 09/10/2026 à 14:03 · module source M6 · 3 ligne(s)',
      );
    });

    testWidgets('un indicateur par puce : libellé en capitales, valeur', (
      tester,
    ) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu()));

      expect(find.text('RÉFÉRENCES'), findsOne);
      expect(
        _texte(tester, const Key('etats-indicateur-valeur-Références')),
        '2',
      );
      // Une valeur vide est « sans valeur » : « — », jamais « 0 ».
      expect(
        _texte(
          tester,
          const Key('etats-indicateur-valeur-Valeur du stock (CMP)'),
        ),
        '—',
      );
    });

    testWidgets('le tableau : en-têtes en capitales, cellules vides en « — »', (
      tester,
    ) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu()));

      for (final e in ['ARTICLE', 'QUANTITÉ', 'VALEUR']) {
        expect(find.text(e), findsOne, reason: e);
      }
      expect(_texte(tester, const Key('etats-cellule-0-0')), 'Riz');
      expect(_texte(tester, const Key('etats-cellule-0-2')), '125000.00');
      expect(_texte(tester, const Key('etats-cellule-1-1')), 'non suivi');
      // `$cellule !== '' ? $cellule : MontantFcfa::TIRET` (l.183).
      expect(_texte(tester, const Key('etats-cellule-1-2')), '—');
      expect(find.byType(Table), findsOne);
    });

    testWidgets('lignes impaires rayées (bg-slate-50/40), les autres non', (
      tester,
    ) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu()));

      final lignes = tester.widget<Table>(find.byType(Table)).children;
      // En-tête + 3 lignes.
      expect(lignes.length, 4);
      Color? fond(int i) => (lignes[i].decoration as BoxDecoration?)?.color;
      expect(fond(0), AppColors.navy);
      expect(fond(1), isNull); // $index 0
      expect(fond(2), TextesEtats.fondRayure); // $index 1
      expect(fond(3), isNull); // $index 2
    });

    testWidgets('l’encadré « Sur ce poste » est RETIRÉ de l’écran (directive '
        'du PO, 14/10/2026) : les mentions ne sont pas rendues, le tableau '
        'garde ses « — »', (tester) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu()));

      expect(find.byKey(const Key('etats-mention-0')), findsNothing);
      expect(find.text('Première mention.'), findsNothing);
      expect(find.text('Sur ce poste'), findsNothing);
      expect(_texte(tester, const Key('etats-cellule-1-2')), '—');
    });

    testWidgets('sans mention, aucun encadré', (tester) async {
      await monterAvec(
        tester,
        (_) => const ApercuRecu(
          ApercuEtat(
            code: 'x',
            titre: 'T',
            periode: 'P',
            moduleSource: 'M6',
            indicateurs: [],
            entetes: ['A'],
            lignes: [
              ['1'],
            ],
          ),
        ),
      );
      expect(find.byKey(const Key('etats-apercu-mentions')), findsNothing);
    });

    testWidgets('un état vide dit la phrase de la vue, sans tableau', (
      tester,
    ) async {
      await monterAvec(tester, (_) => ApercuRecu(apercu(lignes: const [])));

      expect(
        _texte(tester, const Key('etats-apercu-vide')),
        'Aucune ligne sur cette période.',
      );
      expect(find.byType(Table), findsNothing);
      // Les indicateurs et le décompte restent affichés : « 0 ligne(s) » est
      // ici une MESURE (la liste a été lue et elle est vide).
      expect(
        _texte(tester, const Key('etats-apercu-sous-ligne')),
        endsWith('0 ligne(s)'),
      );
    });

    testWidgets('un état refusé dit sa raison, sans chiffre ni tableau', (
      tester,
    ) async {
      await monterAvec(
        tester,
        (_) => const ApercuRefuse(motif: 'Raison vraie et datée.'),
      );

      expect(
        find.textContaining(
          'Aperçu indisponible Raison vraie et datée.',
          findRichText: true,
        ),
        findsOne,
      );
      expect(find.byType(Table), findsNothing);
      expect(find.byKey(const Key('etats-apercu-indicateurs')), findsNothing);
      expect(
        find.textContaining('Aucune ligne sur cette période'),
        findsNothing,
      );
      // La période et le décompte n'ont aucune source : « — », pas « 0 ».
      expect(
        _texte(tester, const Key('etats-apercu-sous-ligne')),
        '— · module source M6 · — ligne(s)',
      );
    });

    testWidgets('une lecture qui échoue le dit, sans chiffre ni tableau', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1600, 1000)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            catalogueEtatsProvider.overrideWith((ref) async => _catalogue),
            apercuEtatProvider.overrideWith(
              (ref, code) async => throw StateError('base illisible'),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranEtats()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('etats-entree-stocks')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Aperçu indisponible $messageLectureEchouee',
          findRichText: true,
        ),
        findsOne,
      );
      expect(find.byKey(const Key('etats-apercu-erreur')), findsOne);
      // Jamais l'exception brute.
      expect(
        find.textContaining('Bad state', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('base illisible', findRichText: true),
        findsNothing,
      );
      expect(find.byType(Table), findsNothing);
      expect(
        _texte(tester, const Key('etats-apercu-sous-ligne')),
        '— · module source M6 · — ligne(s)',
      );
    });

    testWidgets(
      'pendant le calcul : un indicateur de chargement, rien d’autre',
      (tester) async {
        final attente = Completer<ResultatApercu>();
        tester.view
          ..physicalSize = const Size(1600, 1000)
          ..devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              catalogueEtatsProvider.overrideWith((ref) async => _catalogue),
              apercuEtatProvider.overrideWith((ref, code) => attente.future),
            ],
            child: MaterialApp(
              theme: AppTheme.clair,
              home: const Scaffold(body: EcranEtats()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('etats-entree-stocks')));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOne);
        expect(find.byType(Table), findsNothing);
        // Le titre est celui du catalogue ; ni période ni décompte inventés.
        expect(
          _texte(tester, const Key('etats-apercu-titre')),
          'État des stocks',
        );
        expect(
          _texte(tester, const Key('etats-apercu-sous-ligne')),
          '— · module source M6 · — ligne(s)',
        );
      },
    );

    testWidgets('changer d’état change le titre', (tester) async {
      await monterAvec(
        tester,
        (code) => ApercuRecu(
          ApercuEtat(
            code: code,
            titre: 'titre-$code',
            periode: 'P',
            moduleSource: 'M1',
            indicateurs: const [],
            entetes: const ['A'],
            lignes: const [],
          ),
        ),
      );
      expect(_texte(tester, const Key('etats-apercu-titre')), 'titre-stocks');

      await tester.tap(find.byKey(const Key('etats-entree-reservations')));
      await tester.pumpAndSettle();
      expect(
        _texte(tester, const Key('etats-apercu-titre')),
        'titre-reservations',
      );
    });
  });

  group('Cet écran n’ÉCRIT jamais et ne produit AUCUN document', () {
    test('aucune source de présentation ne génère ni n’imprime', () {
      final dossier = Directory('lib/features/etats/presentation');
      final fichiers = dossier
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // Plancher : sans lui, un dossier renommé rendrait le balayage vide,
      // donc vert.
      expect(fichiers.length, greaterThanOrEqualTo(6));

      for (final f in fichiers) {
        final code = f
            .readAsLinesSync()
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(code.contains('.generer('), isFalse, reason: f.path);
        expect(code.contains('Printing'), isFalse, reason: f.path);
        expect(code.contains('editerEtatProvider'), isFalse, reason: f.path);
        expect(code.contains('writeAsBytes'), isFalse, reason: f.path);
      }
    });
  });
}
