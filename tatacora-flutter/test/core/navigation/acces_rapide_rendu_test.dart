import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/navigation/acces_rapide.dart';
import 'package:tatacora_flutter/core/navigation/coquille_vue.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/coquille_application.dart';
import 'package:tatacora_flutter/core/router/panneau_acces_rapide.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/app_text_styles.dart';
import 'package:tatacora_flutter/features/hebergement/presentation/panneau_historique.dart';

import '../../support/coquille_montee.dart';

/// Le panneau « Accès rapides » RENDU (lot 3, 13/10/2026) : le bouton, son
/// ouverture et ses trois fermetures, les deux sections, leur ordre, leurs
/// droits, le sous-titre, l'état vide, les gestes et les mesures. La
/// confrontation du registre au serveur est dans
/// `acces_rapide_contre_serveur_test.dart`.

const _fenetre = Size(1600, 1000);

/// Tous les modules à `C`, puis les exceptions.
Map<String, dynamic> _droits([Map<String, String> exceptions = const {}]) => {
  for (final m in ModuleTatacora.values) m.code: exceptions[m.code] ?? 'C',
};

Future<void> _monter(
  WidgetTester tester, {
  String route = '/tableau-de-bord',
  String role = 'administrateur',
  Map<String, dynamic>? droits,
  Size taille = _fenetre,
  bool partagee = true,
}) => monterCoquille(
  tester,
  role: role,
  droits: droits ?? _droits(),
  routeActive: route,
  taille: taille,
  coquillePartagee: partagee,
);

Future<void> _ouvrir(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('bouton-acces-rapide')));
  await tester.pumpAndSettle();
}

Finder get _panneau => find.byKey(const Key('panneau-acces-rapide'));

/// Les libellés d'une section, dans l'ordre vertical du rendu.
List<String> _libelles(WidgetTester tester, String section) {
  final textes = find.descendant(
    of: find.byKey(Key('acces-rapide-section-$section')),
    matching: find.byType(Text),
  );
  final elements = [
    for (var i = 0; i < textes.evaluate().length; i++)
      (
        t: tester.widget<Text>(textes.at(i)).data ?? '',
        y: tester.getTopLeft(textes.at(i)).dy,
      ),
  ]..sort((a, b) => a.y.compareTo(b.y));
  return [for (final e in elements.skip(1)) e.t]; // le titre de section ôté
}

String _routeAffichee(WidgetTester tester) => tester
    .widget<CoquilleApplication>(find.byType(CoquilleApplication))
    .routeActive;

void main() {
  group('Le bouton flottant', () {
    testWidgets('présent sur le tableau de bord, 56 px, à 24 px du coin '
        'bas-droit, infobulle de la vue ; le panneau n’existe pas encore', (
      tester,
    ) async {
      await _monter(tester);
      final bouton = find.byKey(const Key('bouton-acces-rapide'));
      expect(bouton, findsOneWidget);
      final r = tester.getRect(bouton);
      expect(r.width, MesuresAccesRapide.boutonFlottant);
      expect(r.height, MesuresAccesRapide.boutonFlottant);
      expect(r.right, _fenetre.width - MesuresAccesRapide.margeBoutonFlottant);
      expect(
        r.bottom,
        _fenetre.height - MesuresAccesRapide.margeBoutonFlottant,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == LibellesAccesRapide.titreBouton,
        ),
        findsOneWidget,
      );
      // Navy, rond, et l'éclair blanc à bouts ronds de la vue.
      final boite = tester.widget<AnimatedContainer>(
        find.descendant(of: bouton, matching: find.byType(AnimatedContainer)),
      );
      final deco = boite.decoration! as BoxDecoration;
      expect(deco.color, AppColors.navy);
      expect(deco.shape, BoxShape.circle);
      final eclair = tester.widget<IconeTrace>(
        find.descendant(of: bouton, matching: find.byType(IconeTrace)),
      );
      expect(eclair.trace, contains('stroke-linecap="round"'));
      expect(eclair.trace, contains('M13 2L3 14h9l-1 8 10-12h-9z'));
      expect(eclair.taille, MesuresAccesRapide.iconeBoutonFlottant);
      // `display: none` : rien du panneau n'est construit.
      expect(_panneau, findsNothing);
      expect(find.text(LibellesAccesRapide.titre), findsNothing);
    });

    testWidgets('absent d’une page dont la vue n’inclut pas le panneau '
        '(Stocks, Facturation, Point de vente)', (tester) async {
      for (final route in const ['/stocks', '/facturation', '/pos']) {
        await _monter(tester, route: route);
        expect(
          find.byKey(const Key('bouton-acces-rapide')),
          findsNothing,
          reason: route,
        );
      }
    });

    testWidgets('présent sur les onze pages qui le portent', (tester) async {
      for (final route in pagesAvecAccesRapide.keys) {
        await _monter(tester, route: route);
        expect(
          find.byKey(const Key('bouton-acces-rapide')),
          findsOneWidget,
          reason: route,
        );
      }
    });

    testWidgets('au survol : DORÉ (`hover:bg-[var(--gold)]`) et agrandi '
        '(`hover:scale-105`)', (tester) async {
      await _monter(tester);
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      await souris.moveTo(
        tester.getCenter(find.byKey(const Key('bouton-acces-rapide'))),
      );
      await tester.pumpAndSettle();
      final bouton = find.byKey(const Key('bouton-acces-rapide'));
      final deco =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: bouton,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(deco.color, AppColors.gold);
      expect(
        tester
            .widget<AnimatedScale>(
              find.descendant(of: bouton, matching: find.byType(AnimatedScale)),
            )
            .scale,
        MesuresAccesRapide.echelleSurvolBouton,
      );
    });
  });

  group('Ouvrir et fermer', () {
    testWidgets('le clic ouvre le panneau À DROITE, 320 px, sur TOUTE la '
        'hauteur (barre supérieure comprise), sous un voile', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      final r = tester.getRect(_panneau);
      expect(r.width, MesuresAccesRapide.largeurPanneau);
      expect(r.right, _fenetre.width);
      expect(r.top, 0);
      expect(r.height, _fenetre.height);
      final voile = find.byKey(const Key('voile-acces-rapide'));
      expect(tester.getRect(voile), Offset.zero & _fenetre);
      expect(
        tester
            .widget<ColoredBox>(
              find.descendant(of: voile, matching: find.byType(ColoredBox)),
            )
            .color,
        AppColors.voileModale,
      );
    });

    testWidgets('le clic sur le VOILE ferme', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
    });

    testWidgets('la croix « Fermer » ferme', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      expect(find.bySemanticsLabel(LibellesAccesRapide.fermer), findsOneWidget);
      await tester.tap(find.byKey(const Key('fermer-acces-rapide')));
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
    });

    testWidgets('Échap ferme ; sans panneau ouvert, Échap ne fait rien', (
      tester,
    ) async {
      await _monter(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
      await _ouvrir(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
    });

    testWidgets('Alt+A ouvre, puis referme (bascule de la vue)', (
      tester,
    ) async {
      await _monter(tester);
      Future<void> altA() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
      }

      await altA();
      expect(_panneau, findsOneWidget);
      await altA();
      expect(_panneau, findsNothing);
      // La touche A SEULE n'ouvre rien.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
    });

    testWidgets('Alt+A puis Échap sur /stocks (page sans panneau) : NON '
        'traités, rien ne s’ouvre — la vue n’écoute pas ces touches là', (
      tester,
    ) async {
      await _monter(tester, route: '/stocks');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final altA = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(altA, isFalse, reason: 'Alt+A avalé sur une page sans panneau');
      final echap = await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(echap, isFalse, reason: 'Échap avalé sur une page sans panneau');
      expect(_panneau, findsNothing);
      // Témoin : sur une page porteuse, la même touche EST traitée.
      await _monter(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      final porteuse = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await tester.pumpAndSettle();
      expect(porteuse, isTrue);
      expect(_panneau, findsOneWidget);
    });

    // Les trois durées et l'échelle de pression, lues sur le RENDU : chaque
    // assertion se place de part et d'autre de la borne (une milliseconde
    // avant, à la borne), de sorte qu'une durée changée la fasse rougir.
    testWidgets('pression : `active:scale-95` — échelle 0,95 tant que le '
        'doigt est posé, 1 au relâchement', (tester) async {
      await _monter(tester);
      final bouton = find.byKey(const Key('bouton-acces-rapide'));
      double echelle() => tester
          .widget<AnimatedScale>(
            find.descendant(of: bouton, matching: find.byType(AnimatedScale)),
          )
          .scale;
      expect(echelle(), 1.0);
      final doigt = await tester.startGesture(tester.getCenter(bouton));
      // `onTapDown` part au plus tard à `kPressTimeout`.
      await tester.pump(kPressTimeout);
      expect(echelle(), MesuresAccesRapide.echellePressionBouton);
      expect(MesuresAccesRapide.echellePressionBouton, 0.95);
      await doigt.up();
      await tester.pumpAndSettle();
      expect(echelle(), 1.0);
    });

    testWidgets('voile : entrée en 150 ms, SORTIE en 75 ms '
        '(`x-transition.opacity`, défauts d’Alpine)', (tester) async {
      await _monter(tester);
      final voile = find.byKey(const Key('voile-acces-rapide'));
      double opacite() => tester
          .widget<FadeTransition>(
            find.descendant(of: voile, matching: find.byType(FadeTransition)),
          )
          .opacity
          .value;
      await tester.tap(find.byKey(const Key('bouton-acces-rapide')));
      await tester.pump(); // départ de l'animation
      await tester.pump(const Duration(milliseconds: 149));
      expect(opacite(), lessThan(1));
      await tester.pump(const Duration(milliseconds: 1));
      expect(opacite(), 1);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fermer-acces-rapide')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 74));
      expect(opacite(), greaterThan(0), reason: 'voile éteint avant 75 ms');
      await tester.pump(const Duration(milliseconds: 1));
      // À la borne, la valeur est atteinte ; le contrôleur ne se déclare
      // « terminé » qu'à l'image suivante (`isDone` est strict).
      expect(opacite(), 0, reason: 'voile encore visible à 75 ms');
      // Le panneau, lui, glisse encore (200 ms).
      expect(_panneau, findsOneWidget);
      await tester.pumpAndSettle();
      expect(voile, findsNothing);
    });

    testWidgets('panneau : glissement de 200 ms dans LES DEUX sens '
        '(`duration-200`)', (tester) async {
      await _monter(tester);
      // L'ancêtre le plus PROCHE (les transitions de route en sont d'autres).
      Offset position() => tester
          .widget<SlideTransition>(
            find
                .ancestor(of: _panneau, matching: find.byType(SlideTransition))
                .first,
          )
          .position
          .value;
      await tester.tap(find.byKey(const Key('bouton-acces-rapide')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(position().dx, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 1));
      expect(position(), Offset.zero);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('fermer-acces-rapide')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(position().dx, lessThan(1), reason: 'sorti avant 200 ms');
      await tester.pump(const Duration(milliseconds: 1));
      expect(position().dx, 1, reason: 'pas encore sorti à 200 ms');
      await tester.pumpAndSettle();
      expect(_panneau, findsNothing);
    });

    // La borne ne mord que sous 364 px de fenêtre, où la barre supérieure de
    // la coquille déborde déjà (poste de bureau seulement) : elle se prouve
    // sur la fonction que le panneau appelle.
    test('`max-w-[88vw]` : 320 px, bornés à 88 % d’une fenêtre étroite', () {
      expect(
        largeurPanneauAccesRapide(1600),
        MesuresAccesRapide.largeurPanneau,
      );
      expect(largeurPanneauAccesRapide(340), closeTo(340 * 0.88, 0.001));
    });
  });

  group('Le contenu, au mot et dans l’ordre de la vue', () {
    testWidgets('tableau de bord : en-tête, « SUR CETTE PAGE » (4), '
        '« ALLER À » (7, la page courante exclue), pied', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      expect(
        find.descendant(
          of: _panneau,
          matching: find.text(LibellesAccesRapide.titre),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('acces-rapide-sous-titre')))
            .data,
        'Tableau de bord',
      );
      // `uppercase` : la casse du RENDU.
      expect(find.text('SUR CETTE PAGE'), findsOneWidget);
      expect(find.text('ALLER À'), findsOneWidget);
      expect(find.text(LibellesAccesRapide.surCettePage), findsNothing);
      expect(_libelles(tester, 'sur-cette-page'), [
        'Nouvelle réservation',
        'Encaisser au bar',
        'Stocks critiques',
        'Générer un état',
      ]);
      expect(_libelles(tester, 'aller-a'), [
        'Nouvelle réservation',
        'Clients',
        'Point de vente',
        'Facturation',
        'Stocks',
        'Comptabilité',
        'États & Rapports',
      ]);
      // « Sur cette page » AVANT « Aller à ».
      expect(
        tester.getTopLeft(find.text('SUR CETTE PAGE')).dy,
        lessThan(tester.getTopLeft(find.text('ALLER À')).dy),
      );
      final pied = tester
          .widget<Text>(find.byKey(const Key('acces-rapide-pied')))
          .textSpan!
          .toPlainText();
      expect(pied, contains(LibellesAccesRapide.pourOuvrir));
      expect(pied, contains(LibellesAccesRapide.pourFermer));
      for (final t in const ['Alt', 'A', 'Échap']) {
        expect(
          find.descendant(
            of: find.byKey(const Key('acces-rapide-pied')),
            matching: find.text(t),
          ),
          findsOneWidget,
          reason: t,
        );
      }
      expect(find.text(LibellesAccesRapide.aucun), findsNothing);
    });

    testWidgets('réservations : ses quatre actions ; « Nouvelle réservation » '
        'sort de « Aller à » (même route que la page)', (tester) async {
      await _monter(tester, route: '/hebergement/reservations');
      await _ouvrir(tester);
      expect(_libelles(tester, 'sur-cette-page'), [
        'Historique des réservations',
        'Plan des chambres',
        'Ajouter un client',
        'Facturer le séjour',
      ]);
      expect(_libelles(tester, 'aller-a'), [
        'Tableau de bord',
        'Clients',
        'Point de vente',
        'Facturation',
        'Stocks',
        'Comptabilité',
        'États & Rapports',
      ]);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('acces-rapide-sous-titre')))
            .data,
        'Réservations',
      );
    });

    testWidgets('une page sans action à elle (Tourisme) : « Aller à » seul', (
      tester,
    ) async {
      await _monter(tester, route: '/tourisme');
      await _ouvrir(tester);
      expect(
        find.byKey(const Key('acces-rapide-section-sur-cette-page')),
        findsNothing,
      );
      expect(_libelles(tester, 'aller-a'), hasLength(8));
    });

    testWidgets('une page absente du menu (Restauration) : la MARQUE en '
        'sous-titre, repli de la vue', (tester) async {
      await _monter(tester, route: '/restaurant/plats');
      await _ouvrir(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('acces-rapide-sous-titre')))
            .data,
        LibellesCoquille.marque,
      );
    });

    testWidgets('typographie de la vue (hors `<main>`) : titre 14 gras navy, '
        'entrée 13 slate-700, section 10 gras slate-400 à 0,05 em', (
      tester,
    ) async {
      await _monter(tester);
      await _ouvrir(tester);
      final titre = tester.widget<Text>(
        find.descendant(
          of: _panneau,
          matching: find.text(LibellesAccesRapide.titre),
        ),
      );
      expect(titre.style!.fontSize, Tailles.t14);
      expect(titre.style!.fontWeight, FontWeight.bold);
      expect(titre.style!.color, AppColors.navy);
      expect(titre.style!.height, Tailles.interligneSmHorsMain);
      final entree = tester.widget<Text>(find.text('Encaisser au bar'));
      expect(entree.style!.fontSize, Tailles.t13);
      expect(entree.style!.color, AppColors.neutre700);
      final section = tester.widget<Text>(find.text('SUR CETTE PAGE'));
      expect(section.style!.fontSize, Tailles.t10);
      expect(section.style!.fontWeight, FontWeight.bold);
      expect(section.style!.color, AppColors.neutre400);
      expect(
        section.style!.letterSpacing,
        AppTextStyles.suiviPlusLarge * Tailles.t10,
      );
      final sousTitre = tester.widget<Text>(
        find.byKey(const Key('acces-rapide-sous-titre')),
      );
      expect(sousTitre.style!.fontSize, Tailles.t11);
      expect(sousTitre.style!.color, AppColors.neutre400);
    });

    testWidgets('une entrée : icône DORÉE 18 px à bouts et jonctions ronds '
        '(hérités du `<svg>`), chevron 14 px à 30 %', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      final lien = find.byKey(const Key('acces-rapide-sur-cette-page-0'));
      final icones = tester
          .widgetList<IconeTrace>(
            find.descendant(of: lien, matching: find.byType(IconeTrace)),
          )
          .toList();
      expect(icones, hasLength(2));
      expect(icones.first.couleur, AppColors.gold);
      expect(icones.first.taille, MesuresAccesRapide.iconeEntree);
      expect(icones.first.trace, contains('stroke-linecap="round"'));
      expect(icones.first.trace, contains('stroke-linejoin="round"'));
      expect(icones.last.taille, MesuresAccesRapide.iconeChevron);
      expect(icones.last.trace, isNot(contains('stroke-linecap')));
      expect(
        icones.last.couleur,
        AppColors.neutre700.withValues(alpha: OpacitesAccesRapide.chevron),
      );
    });

    testWidgets('une entrée au survol : fond NAVY, texte blanc, icône qui '
        'RESTE dorée (le `group-hover` de la vue n’a pas de `group`)', (
      tester,
    ) async {
      await _monter(tester);
      await _ouvrir(tester);
      final lien = find.byKey(const Key('acces-rapide-sur-cette-page-1'));
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      await souris.moveTo(tester.getCenter(lien));
      await tester.pumpAndSettle();
      final deco =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: lien,
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(deco.color, AppColors.navy);
      expect(
        tester.widget<Text>(find.text('Encaisser au bar')).style!.color,
        AppColors.neutre0,
      );
      expect(
        tester
            .widgetList<IconeTrace>(
              find.descendant(of: lien, matching: find.byType(IconeTrace)),
            )
            .first
            .couleur,
        AppColors.gold,
      );
    });
  });

  group('Les droits — la règle du serveur, `moduleAccessible` seule', () {
    testWidgets('sans M6 ni M14 : « Stocks critiques », « Générer un état », '
        '« Stocks » et « États & Rapports » disparaissent', (tester) async {
      await _monter(tester, droits: _droits({'M6': '-', 'M14': '-'}));
      await _ouvrir(tester);
      expect(_libelles(tester, 'sur-cette-page'), [
        'Nouvelle réservation',
        'Encaisser au bar',
      ]);
      expect(_libelles(tester, 'aller-a'), [
        'Nouvelle réservation',
        'Clients',
        'Point de vente',
        'Facturation',
        'Comptabilité',
      ]);
    });

    testWidgets('un niveau L garde son entrée (masqué sur `-` seulement)', (
      tester,
    ) async {
      await _monter(tester, droits: _droits({'M6': 'L'}));
      await _ouvrir(tester);
      expect(_libelles(tester, 'sur-cette-page'), contains('Stocks critiques'));
    });

    testWidgets('sans M11 : le sous-titre est la MARQUE, jamais le nom d’un '
        'module interdit', (tester) async {
      await _monter(tester, droits: _droits({'M11': '-'}));
      await _ouvrir(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('acces-rapide-sous-titre')))
            .data,
        LibellesCoquille.marque,
      );
    });

    // Le gérant a `C` partout ; la barre latérale lui cache `pwa.clients`,
    // `pwa.facturation`, `pwa.comptabilite.hub` et `pwa.etats.studio`
    // (`ROUTES_MASQUEES_PAR_ROLE`) — le panneau de la vue, non (D346).
    testWidgets('le GÉRANT voit les QUATRE destinations de « Aller à » que '
        'la barre latérale lui cache, et « Générer un état » sur l’accueil '
        '(incohérence du serveur, reproduite et nommée)', (tester) async {
      await _monter(tester, role: 'gerant');
      await _ouvrir(tester);
      expect(
        _libelles(tester, 'aller-a'),
        containsAll(<String>[
          'Clients',
          'Facturation',
          'Comptabilité',
          'États & Rapports',
        ]),
      );
      expect(_libelles(tester, 'sur-cette-page'), contains('Générer un état'));
    });

    testWidgets('le GÉRANT, sur les réservations et l’hébergement : les '
        'actions contextuelles vers Clients et Facturation restent', (
      tester,
    ) async {
      await _monter(tester, role: 'gerant', route: '/hebergement/reservations');
      await _ouvrir(tester);
      expect(
        _libelles(tester, 'sur-cette-page'),
        containsAll(<String>['Ajouter un client', 'Facturer le séjour']),
      );
      await _monter(tester, role: 'gerant', route: '/hebergement');
      await _ouvrir(tester);
      expect(_libelles(tester, 'sur-cette-page'), contains('Facturation'));
    });

    testWidgets('aucune entrée accessible : la phrase de la vue, ni section '
        'ni titre', (tester) async {
      final seulM9 = {
        for (final m in ModuleTatacora.values)
          m.code: m == ModuleTatacora.m9Tourisme ? 'C' : '-',
      };
      await _monter(tester, route: '/tourisme', droits: seulM9);
      await _ouvrir(tester);
      expect(find.text(LibellesAccesRapide.aucun), findsOneWidget);
      expect(find.text('SUR CETTE PAGE'), findsNothing);
      expect(find.text('ALLER À'), findsNothing);
    });
  });

  group('Les gestes', () {
    testWidgets('« Nouvelle réservation » mène à l’écran des réservations, '
        'et le panneau est FERMÉ à l’arrivée', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      await tester.tap(find.byKey(const Key('acces-rapide-sur-cette-page-0')));
      await tester.pumpAndSettle();
      expect(_routeAffichee(tester), '/hebergement/reservations');
      expect(_panneau, findsNothing);
    });

    testWidgets('« Stocks » (Aller à) mène à l’écran des stocks — page sans '
        'panneau : le bouton disparaît', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      await tester.tap(find.byKey(const Key('acces-rapide-aller-a-4')));
      await tester.pumpAndSettle();
      expect(_routeAffichee(tester), '/stocks');
      expect(find.byKey(const Key('bouton-acces-rapide')), findsNothing);
    });

    testWidgets('« Historique des réservations » ouvre la page des '
        'réservations ET son panneau d’historique (`?vue=historique`)', (
      tester,
    ) async {
      await _monter(tester, route: '/hebergement');
      await _ouvrir(tester);
      await tester.tap(find.byKey(const Key('acces-rapide-sur-cette-page-1')));
      await tester.pumpAndSettle();
      expect(_routeAffichee(tester), '/hebergement/reservations');
      expect(find.byType(PanneauHistorique), findsOneWidget);
    });

    testWidgets('« Comptabilité » mène au hub porté le 14/10/2026 (D417, '
        'D424), sans message « non porté »', (tester) async {
      await _monter(tester);
      await _ouvrir(tester);
      await tester.tap(find.byKey(const Key('acces-rapide-aller-a-5')));
      await tester.pumpAndSettle();
      expect(
        find.text(LibellesCoquille.ecranNonPorte('Comptabilité')),
        findsNothing,
      );
      expect(_routeAffichee(tester), '/comptabilite');
    });
  });

  test('heriterTraitsRacine : ajoute ce qui manque, garde ce qui est posé', () {
    expect(
      heriterTraitsRacine(
        '<circle cx="1" cy="1" r="1"/><path stroke-linecap="square" d="M0 0"/>',
        cap: 'round',
        join: 'round',
      ),
      '<circle stroke-linecap="round" stroke-linejoin="round" cx="1" cy="1" '
      'r="1"/><path stroke-linejoin="round" stroke-linecap="square" '
      'd="M0 0"/>',
    );
    expect(heriterTraitsRacine('<path d="M0 0"/>'), '<path d="M0 0"/>');
  });
}
