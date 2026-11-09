import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RendererBinding;
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fenetre/boutons_fenetre.dart';
import 'package:tatacora_flutter/core/fenetre/controle_fenetre.dart';
import 'package:tatacora_flutter/core/fenetre/controle_fenetre_windows.dart';
import 'package:tatacora_flutter/core/fenetre/libelles_fenetre.dart';
import 'package:tatacora_flutter/core/fenetre/providers_fenetre.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/responsive/breakpoints.dart';
import 'package:tatacora_flutter/core/router/disposition_barre.dart';
import 'package:tatacora_flutter/features/caisse/domain/indicateur_caisse.dart';
import 'package:tatacora_flutter/features/caisse/presentation/providers_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/exercice_consulte.dart';
import 'package:tatacora_flutter/core/theme/app_spacing.dart';
import 'package:tatacora_flutter/core/theme/mesures_fenetre.dart';

import '../../support/coquille_montee.dart';

/// Les TROIS boutons de fenêtre du poste (réduire, agrandir / restaurer,
/// fermer) et la zone de déplacement de la barre supérieure — demande du PO du
/// 09/11/2026.
///
/// Aucun code natif : le contrôle de fenêtre est le SEAM `ControleFenetre`, ici
/// remplacé par une fausse réalisation qui NOTE l'action reçue. « Windows
/// simulé » = le fournisseur rend la fausse ; « ailleurs » = il rend `null`
/// (son défaut, hors Windows et tant que la barre native n'est pas masquée).
class _FauxControleFenetre implements ControleFenetre {
  final List<String> actions = [];
  final ValueNotifier<bool> _agrandie = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get agrandie => _agrandie;

  void agrandir(bool valeur) => _agrandie.value = valeur;

  @override
  Future<void> reduire() async => actions.add('reduire');

  @override
  Future<void> basculerAgrandissement() async {
    actions.add('basculer');
    _agrandie.value = !_agrandie.value;
  }

  @override
  Future<void> fermer() async => actions.add('fermer');

  @override
  Future<void> deplacer() async => actions.add('deplacer');

  @override
  Future<void> redimensionner(BordFenetre bord) async =>
      actions.add('redimensionner:${bord.name}');
}

ExerciceComptable _exercice(int annee, StatutExercice statut) =>
    ExerciceComptable(
      id: 'ex-$annee',
      annee: annee,
      dateDebut: '$annee-01-01',
      dateFin: '$annee-12-31',
      statut: statut,
    );

const _droits = {
  'M1': 'C', 'M2': 'C', 'M3': 'C', 'M4': 'C', 'M5': 'C', 'M6': 'C', //
  'M7': 'C', 'M8': 'C', 'M9': 'C', 'M10': 'C', 'M11': 'C', 'M12': 'C',
  'M13': 'C', 'M14': 'C', 'ROLES': 'C', 'PARAM': 'C',
};

const _reduire = Key('bouton-fenetre-reduire');
const _agrandir = Key('bouton-fenetre-agrandir');
const _fermer = Key('bouton-fenetre-fermer');
const _zone = Key('zone-deplacement-fenetre');

Future<void> _monter(
  WidgetTester tester, {
  _FauxControleFenetre? controle,
  Size taille = const Size(1600, 900),
  String route = '/stocks',
  String? login,
  List<Override> autres = const [],
}) async {
  final base = AppDatabase.enMemoire();
  addTearDown(base.close);
  await monterCoquille(
    tester,
    role: 'administrateur',
    droits: _droits,
    routeActive: route,
    taille: taille,
    login: login,
    surcharges: [
      baseLocaleProvider.overrideWithValue(base),
      controleFenetreProvider.overrideWithValue(controle),
      ...autres,
    ],
  );
}

void main() {
  group('hors poste Windows', () {
    test('le fournisseur ne rend AUCUN contrôle par défaut', () {
      // Hors Windows, et même sur Windows tant que `preparer()` n'a pas masqué
      // la barre native : sans contrôle, aucun bouton n'est dessiné.
      final conteneur = ProviderContainer();
      addTearDown(conteneur.dispose);
      expect(conteneur.read(controleFenetreProvider), isNull);
    });

    testWidgets('aucun bouton de fenêtre ni zone de déplacement', (
      tester,
    ) async {
      await _monter(tester);
      expect(find.byKey(_reduire), findsNothing);
      expect(find.byKey(_agrandir), findsNothing);
      expect(find.byKey(_fermer), findsNothing);
      expect(find.byKey(_zone), findsNothing);
      // La barre, elle, est celle de la vue.
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
    });
  });

  group('disposition de la barre (fonction pure de la largeur)', () {
    DispositionBarre pour(double l, {bool boutons = true}) =>
        DispositionBarre.pour(l, avecBoutonsFenetre: boutons);

    test('large : rien n\'est replié', () {
      final d = pour(2560);
      expect(d.compacte, isFalse);
      expect(d.rechercheIcone, isFalse);
      expect(d.caisseIcone, isFalse);
      expect(d.exerciceReduit, isFalse);
      expect(d.exerciceMasque, isFalse);
      expect(d.venteIcone, isFalse);
      expect(d.logoMasque, isFalse);
      expect(d.synchroMasquee, isFalse);
    });

    test('le repli est MONOTONE : un élément replié le reste plus étroit', () {
      var precedent = pour(2560);
      for (var l = 2560.0; l >= 320; l -= 8) {
        final d = pour(l);
        for (final (avant, apres) in [
          (precedent.compacte, d.compacte),
          (precedent.rechercheIcone, d.rechercheIcone),
          (precedent.caisseIcone, d.caisseIcone),
          (precedent.exerciceReduit, d.exerciceReduit),
          (precedent.exerciceMasque, d.exerciceMasque),
          (precedent.venteIcone, d.venteIcone),
          (precedent.logoMasque, d.logoMasque),
          (precedent.synchroMasquee, d.synchroMasquee),
        ]) {
          if (avant) expect(apres, isTrue, reason: 'à $l px');
        }
        precedent = d;
      }
    });

    test('sans boutons de fenêtre, la barre n\'est jamais « compacte »', () {
      expect(pour(500, boutons: false).compacte, isFalse);
      expect(pour(500).compacte, isTrue);
    });
  });

  group('poste Windows simulé', () {
    testWidgets('les trois boutons sont à l\'extrême droite, après le menu de '
        'compte, dans l\'ordre réduire / agrandir / fermer', (tester) async {
      await _monter(tester, controle: _FauxControleFenetre());
      final r = tester.getRect(find.byKey(_reduire));
      final a = tester.getRect(find.byKey(_agrandir));
      final f = tester.getRect(find.byKey(_fermer));
      expect(r.right, a.left);
      expect(a.right, f.left);
      expect(
        f.right,
        1600,
        reason: 'la croix touche le bord droit, comme celle de Windows',
      );
      final compte = tester.getRect(find.byType(PopupMenuButton<String>));
      expect(compte.right, lessThanOrEqualTo(r.left));
      final cloche = tester.getRect(find.byKey(const Key('bouton-vente')));
      expect(cloche.right, lessThan(compte.left));
    });

    testWidgets('cibles de 46 px de large sur toute la hauteur de la barre '
        '(au moins 32 px)', (tester) async {
      await _monter(tester, controle: _FauxControleFenetre());
      for (final cle in [_reduire, _agrandir, _fermer]) {
        final t = tester.getSize(find.byKey(cle));
        expect(t.width, MesuresFenetre.largeurBouton);
        expect(t.height, AppLayout.hauteurBarreSuperieure);
        expect(t.height, greaterThanOrEqualTo(MesuresFenetre.hauteurMinimale));
      }
    });

    testWidgets('chaque clic appelle la BONNE action du contrôle', (
      tester,
    ) async {
      final controle = _FauxControleFenetre();
      await _monter(tester, controle: controle);
      await tester.tap(find.byKey(_reduire));
      expect(controle.actions, ['reduire']);
      await tester.tap(find.byKey(_agrandir));
      expect(controle.actions, ['reduire', 'basculer']);
      await tester.tap(find.byKey(_fermer));
      expect(controle.actions, ['reduire', 'basculer', 'fermer']);
    });

    testWidgets('« Agrandir » devient « Restaurer » (et inversement) selon '
        'l\'état de la fenêtre', (tester) async {
      final controle = _FauxControleFenetre();
      await _monter(tester, controle: controle);
      expect(find.byTooltip(LibellesFenetre.agrandir), findsOneWidget);
      expect(find.byTooltip(LibellesFenetre.restaurer), findsNothing);
      Finder icone(String trace) => find.descendant(
        of: find.byKey(_agrandir),
        matching: find.byWidgetPredicate(
          (w) => w is IconeTrace && w.trace == trace,
        ),
      );
      expect(icone(TracesFenetre.agrandir), findsOneWidget);
      expect(icone(TracesFenetre.restaurer), findsNothing);

      controle.agrandir(true);
      await tester.pump();
      expect(find.byTooltip(LibellesFenetre.restaurer), findsOneWidget);
      expect(find.byTooltip(LibellesFenetre.agrandir), findsNothing);
      // L'icône change aussi : un carré, puis deux carrés.
      expect(icone(TracesFenetre.restaurer), findsOneWidget);
      expect(icone(TracesFenetre.agrandir), findsNothing);

      // Un clic bascule : l'état suit, le libellé suit.
      await tester.tap(find.byKey(_agrandir));
      await tester.pump();
      expect(controle.agrandie.value, isFalse);
      expect(find.byTooltip(LibellesFenetre.agrandir), findsOneWidget);
      expect(icone(TracesFenetre.agrandir), findsOneWidget);
    });

    testWidgets('infobulles « Réduire », « Agrandir », « Fermer »', (
      tester,
    ) async {
      await _monter(tester, controle: _FauxControleFenetre());
      expect(find.byTooltip('Réduire'), findsOneWidget);
      expect(find.byTooltip('Agrandir'), findsOneWidget);
      expect(find.byTooltip('Fermer'), findsOneWidget);
    });

    testWidgets('accessibilité : chaque bouton est un bouton nommé, une seule '
        'fois', (tester) async {
      final poignee = tester.ensureSemantics();
      final controle = _FauxControleFenetre();
      await _monter(tester, controle: controle);
      for (final (cle, nom) in [
        (_reduire, 'Réduire'),
        (_agrandir, 'Agrandir'),
        (_fermer, 'Fermer'),
      ]) {
        final s = tester.getSemantics(find.byKey(cle));
        expect(s.label, nom);
        expect(s.flagsCollection.isButton, isTrue);
        expect(s.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      controle.agrandir(true);
      await tester.pump();
      expect(tester.getSemantics(find.byKey(_agrandir)).label, 'Restaurer');
      poignee.dispose();
    });

    testWidgets('aucun débordement sur toute la plage du poste (1024 px, le '
        'minimum du runner, à un écran large)', (tester) async {
      // 1093 px : le portable 1366 x 768 à 125 % que vise le poste. 1159 / 1160 :
      // de part et d'autre du seuil de la barre compacte.
      for (final largeur in <double>[
        1024,
        1093,
        1159,
        1160,
        1383,
        1600,
        1920,
        2560,
      ]) {
        await _monter(
          tester,
          controle: _FauxControleFenetre(),
          taille: Size(largeur, 900),
        );
        expect(
          tester.takeException(),
          isNull,
          reason: 'débordement à $largeur px',
        );
        expect(
          tester.getRect(find.byKey(_fermer)).right,
          largeur,
          reason: 'la croix doit rester visible, au bord droit, à $largeur px',
        );
      }
    });

    testWidgets('la barre ne déborde JAMAIS, de 320 à 2560 px, dans les cas '
        'les plus larges (caisse à clôturer, exercice autre que le défaut, '
        'login long)', (tester) async {
      // Le runner borne le poste à 1024 px ; la barre doit pourtant tenir de
      // 320 à 2560 px (demande du PO du 09/11/2026 : « déborde déjà à 320 px
      // et à 400 px »). Pas de 24 px, plus les deux côtés de chaque seuil.
      final largeurs = <double>{
        for (var l = 320.0; l <= 2560; l += 24) l,
        2560,
        for (final seuil in [
          MesuresFenetre.seuilBarreCompacte,
          MesuresFenetre.seuilRechercheIcone,
          MesuresFenetre.seuilCaisseIcone,
          MesuresFenetre.seuilExerciceReduit,
          MesuresFenetre.seuilExerciceMasque,
          MesuresFenetre.seuilVenteIcone,
          MesuresFenetre.seuilLogoMasque,
          MesuresFenetre.seuilSynchroMasquee,
          Breakpoints.tablette,
          Breakpoints.desktop,
        ]) ...[seuil - 1, seuil, seuil + 1],
      }.toList()..sort();

      final defaut = _exercice(2027, StatutExercice.ouvert);
      final autre = _exercice(2026, StatutExercice.enCloture);
      final cas = <(String, String, String?, List<Override>)>[
        ('caisse fermée', '/stocks', null, const []),
        (
          'caisse à clôturer, exercice autre, login long',
          '/facturation',
          'utilisateur.au.login.tres.long',
          [
            indicateurCaisseProvider.overrideWith(
              (ref) async => const IndicateurCaisse(etat: EtatCaisse.tardive),
            ),
            exercicesDuPosteProvider.overrideWith(
              (ref) async => [defaut, autre],
            ),
            exerciceConsulteProvider.overrideWith((ref) => autre),
          ],
        ),
      ];
      for (final (nom, route, login, autres) in cas) {
        for (final largeur in largeurs) {
          // Démonte : le nombre de surcharges change d'un cas à l'autre.
          await tester.pumpWidget(const SizedBox());
          await _monter(
            tester,
            controle: _FauxControleFenetre(),
            taille: Size(largeur, 900),
            route: route,
            login: login,
            autres: autres,
          );
          await tester.pump();
          await tester.pump();
          expect(
            tester.takeException(),
            isNull,
            reason: 'débordement de la barre à $largeur px ($nom)',
          );
          // Toujours visibles, à toute largeur.
          expect(find.byKey(_reduire), findsOneWidget, reason: '$largeur px');
          expect(find.byKey(_agrandir), findsOneWidget, reason: '$largeur px');
          expect(find.byKey(_fermer), findsOneWidget, reason: '$largeur px');
          expect(
            tester.getRect(find.byKey(_fermer)).right,
            largeur,
            reason: 'la croix reste au bord droit à $largeur px ($nom)',
          );
          expect(
            find.byType(PopupMenuButton<String>),
            findsOneWidget,
            reason: 'menu de compte à $largeur px',
          );
          expect(
            find.byKey(
              Key(
                largeur >= Breakpoints.desktop
                    ? 'bouton-plein-ecran'
                    : 'bouton-menu-mobile',
              ),
            ),
            findsOneWidget,
            reason: 'bouton de menu à $largeur px',
          );
        }
      }
    });

    testWidgets('les cibles de la barre font au moins 32 px, à toute largeur', (
      tester,
    ) async {
      final cles = <Key>[
        _reduire,
        _agrandir,
        _fermer,
        const Key('bouton-vente'),
        const Key('bouton-synchronisation'),
        const Key('bouton-cloche-notifications'),
        const Key('indicateur-caisse'),
        const Key('bouton-menu-mobile'),
        const Key('bouton-plein-ecran'),
        const Key('recherche-globale-icone'),
      ];
      for (final largeur in <double>[320, 400, 640, 800, 1000, 1100, 1600]) {
        await _monter(
          tester,
          controle: _FauxControleFenetre(),
          taille: Size(largeur, 900),
        );
        for (final cle in cles) {
          final f = find.byKey(cle);
          if (f.evaluate().isEmpty) continue;
          final t = tester.getSize(f.first);
          // Au repos sur un grand écran, ces deux-là gardent la mesure de la
          // vue (tracé de 22 px) : la contrainte vaut sous le seuil compact.
          if (largeur >= MesuresFenetre.seuilBarreCompacte &&
              cle == const Key('bouton-plein-ecran')) {
            continue;
          }
          expect(
            t.shortestSide,
            greaterThanOrEqualTo(MesuresFenetre.hauteurMinimale),
            reason: '$cle à $largeur px : $t',
          );
        }
      }
    });

    testWidgets('priorité du repli : recherche et caisse en icône, '
        '« Vente » en icône plus bas, logo et synchronisation ensuite', (
      tester,
    ) async {
      Future<void> a(double largeur) => _monter(
        tester,
        controle: _FauxControleFenetre(),
        taille: Size(largeur, 900),
      );
      final recherche = find.byKey(const Key('recherche-globale'));
      final rechercheIcone = find.byKey(const Key('recherche-globale-icone'));
      final libelleVente = find.descendant(
        of: find.byKey(const Key('bouton-vente')),
        matching: find.text('Vente'),
      );
      final logo = find.byKey(const Key('logo-barre-superieure'));
      final synchro = find.byKey(const Key('bouton-synchronisation'));

      await a(1600);
      expect(recherche, findsOneWidget);
      expect(rechercheIcone, findsNothing);
      expect(libelleVente, findsOneWidget);
      expect(logo, findsOneWidget);
      expect(synchro, findsOneWidget);

      await a(1300);
      expect(recherche, findsNothing);
      expect(rechercheIcone, findsOneWidget);
      expect(libelleVente, findsOneWidget);

      await a(1000);
      expect(libelleVente, findsNothing);

      await a(1010);
      expect(logo, findsOneWidget);

      await a(500);
      expect(libelleVente, findsNothing);
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(logo, findsNothing);

      await a(320);
      expect(synchro, findsNothing);
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(
        find.byKey(const Key('bouton-cloche-notifications')),
        findsOneWidget,
      );
    });

    testWidgets('la recherche en icône ouvre le champ par-dessus la barre, '
        'qui se referme', (tester) async {
      await _monter(
        tester,
        controle: _FauxControleFenetre(),
        taille: const Size(900, 900),
      );
      expect(find.byKey(const Key('recherche-globale-champ')), findsNothing);
      await tester.tap(find.byKey(const Key('recherche-globale-icone')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recherche-globale-champ')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('recherche-globale-champ')),
        'zz',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const Key('recherche-globale-fermer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recherche-globale-champ')), findsNothing);
    });

    group('redimensionnement par le haut (barre de titre native masquée)', () {
      const haut = Key('zone-redimensionnement-haut');
      const hautGauche = Key('zone-redimensionnement-haut-gauche');
      const hautDroit = Key('zone-redimensionnement-haut-droit');

      testWidgets('trois zones invisibles, minces, au bord haut ; aucune hors '
          'du poste', (tester) async {
        await _monter(tester);
        expect(find.byKey(haut), findsNothing);
        expect(find.byKey(hautGauche), findsNothing);
        expect(find.byKey(hautDroit), findsNothing);

        await _monter(tester, controle: _FauxControleFenetre());
        final h = tester.getRect(find.byKey(haut));
        expect(h.top, 0);
        expect(h.height, MesuresFenetre.epaisseurBordRedimensionnement);
        expect(h.height, lessThanOrEqualTo(6));
        final g = tester.getRect(find.byKey(hautGauche));
        expect(g.topLeft, Offset.zero);
        expect(
          g.size,
          const Size.square(MesuresFenetre.tailleCoinRedimensionnement),
        );
        final d = tester.getRect(find.byKey(hautDroit));
        expect(d.topRight, const Offset(1600, 0));
        // Le bord s'arrête au coin gauche et AVANT les trois boutons.
        expect(h.left, g.right);
        expect(h.right, tester.getRect(find.byKey(_reduire)).left);
      });

      testWidgets('chaque zone appelle le BON bord et le bon curseur', (
        tester,
      ) async {
        final controle = _FauxControleFenetre();
        await _monter(tester, controle: controle);
        final souris = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        addTearDown(souris.removePointer);
        for (final (cle, bord, curseur) in [
          (haut, 'haut', SystemMouseCursors.resizeUpDown),
          (hautGauche, 'hautGauche', SystemMouseCursors.resizeUpLeftDownRight),
          (hautDroit, 'hautDroite', SystemMouseCursors.resizeUpRightDownLeft),
        ]) {
          final centre = tester.getCenter(find.byKey(cle));
          await souris.moveTo(centre);
          await tester.pump();
          expect(
            RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
            curseur,
            reason: bord,
          );
          await souris.down(centre);
          await souris.up();
          expect(controle.actions.last, 'redimensionner:$bord');
        }
        expect(controle.actions, hasLength(3));
      });

      testWidgets('les boutons restent cliquables jusqu\'au pixel du haut', (
        tester,
      ) async {
        final controle = _FauxControleFenetre();
        await _monter(tester, controle: controle);
        for (final (cle, action) in [
          (_reduire, 'reduire'),
          (_agrandir, 'basculer'),
          (_fermer, 'fermer'),
        ]) {
          final r = tester.getRect(find.byKey(cle));
          // Au centre de la rangée du haut (y = 0,5 px), hors de l'angle.
          await tester.tapAt(Offset(r.center.dx - 4, 0.5));
          expect(controle.actions.last, action, reason: '$cle');
        }
        expect(
          controle.actions.where((a) => a.startsWith('redimensionner')),
          isEmpty,
        );
      });

      testWidgets('inactives fenêtre agrandie, actives de nouveau restaurée', (
        tester,
      ) async {
        final controle = _FauxControleFenetre()..agrandir(true);
        await _monter(tester, controle: controle);
        expect(find.byKey(haut), findsNothing);
        expect(find.byKey(hautGauche), findsNothing);
        expect(find.byKey(hautDroit), findsNothing);
        controle.agrandir(false);
        await tester.pump();
        expect(find.byKey(haut), findsOneWidget);
      });

      testWidgets('barre compacte : le bord s\'arrête devant les boutons de '
          '32 px', (tester) async {
        await _monter(
          tester,
          controle: _FauxControleFenetre(),
          taille: const Size(900, 900),
        );
        expect(
          tester.getRect(find.byKey(haut)).right,
          tester.getRect(find.byKey(_reduire)).left,
        );
      });

      testWidgets('le clic droit ne redimensionne pas', (tester) async {
        final controle = _FauxControleFenetre();
        await _monter(tester, controle: controle);
        final souris = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryButton,
        );
        await souris.down(tester.getCenter(find.byKey(haut)));
        await souris.up();
        expect(controle.actions, isEmpty);
      });
    });

    testWidgets('fenêtre étroite : boutons de 32 px et identité du compte '
        'masquée ; large : boutons de 46 px et identité visible', (
      tester,
    ) async {
      // Le login à côté de l'avatar (la barre latérale l'affiche aussi).
      final identite = find.descendant(
        of: find.byType(PopupMenuButton<String>),
        matching: find.text('barre.administrateur'),
      );
      await _monter(
        tester,
        controle: _FauxControleFenetre(),
        taille: const Size(1100, 900),
      );
      expect(
        tester.getSize(find.byKey(_fermer)).width,
        MesuresFenetre.largeurBoutonCompact,
      );
      expect(identite, findsNothing);

      await _monter(
        tester,
        controle: _FauxControleFenetre(),
        taille: const Size(1600, 900),
      );
      expect(
        tester.getSize(find.byKey(_fermer)).width,
        MesuresFenetre.largeurBouton,
      );
      expect(identite, findsOneWidget);
    });

    testWidgets('les trois boutons seuls tiennent à 320 px', (tester) async {
      tester.view
        ..physicalSize = const Size(320, 200)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            controleFenetreProvider.overrideWithValue(_FauxControleFenetre()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: Row(children: [Spacer(), BoutonsFenetre()])),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(_fermer)).right, 320);
    });

    testWidgets('la zone libre de la barre déplace la fenêtre au glisser et '
        'agrandit / restaure au double-clic', (tester) async {
      final controle = _FauxControleFenetre();
      await _monter(tester, controle: controle);
      final zone = find.byKey(_zone);
      expect(zone, findsOneWidget);

      await tester.dragFrom(tester.getCenter(zone), const Offset(60, 10));
      expect(controle.actions, ['deplacer']);

      controle.actions.clear();
      final centre = tester.getCenter(zone);
      await tester.tapAt(centre);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(centre);
      await tester.pumpAndSettle();
      expect(controle.actions, ['basculer']);
    });

    testWidgets('la zone ne couvre ni les boutons ni la recherche : les '
        'glisser ne déplace pas la fenêtre', (tester) async {
      final controle = _FauxControleFenetre();
      await _monter(tester, controle: controle);
      final zone = tester.getRect(find.byKey(_zone));
      for (final cle in [_reduire, _agrandir, _fermer]) {
        expect(
          tester.getRect(find.byKey(cle)).left,
          greaterThanOrEqualTo(zone.right),
        );
      }
      await tester.dragFrom(
        tester.getCenter(find.byKey(_agrandir)),
        const Offset(-20, 0),
      );
      expect(controle.actions, isNot(contains('deplacer')));
    });

    testWidgets('le reste de la barre fonctionne : « Vente » reste présent et '
        'la bascule du menu latéral répond', (tester) async {
      await _monter(tester, controle: _FauxControleFenetre());
      expect(find.byKey(const Key('bouton-vente')), findsOneWidget);
      expect(find.byKey(const Key('bouton-plein-ecran')), findsOneWidget);
    });
  });

  group('le côté natif, relu dans le source (invérifiable sans Windows)', () {
    String lire(String chemin) {
      final f = File(chemin);
      if (!f.existsSync()) {
        fail('Source introuvable : $chemin (échoue plutôt que de sauter).');
      }
      return f.readAsStringSync();
    }

    test('hors Windows, la préparation ne fait rien et ne lève pas', () async {
      if (Platform.isWindows) return;
      expect(await ControleFenetreWindows.preparer(), isNull);
      expect(ControleFenetreWindows.instance, isNull);
    });

    test('le style de la fenêtre porte SYSMENU, MINIMIZEBOX et MAXIMIZEBOX : '
        'le plugin commande la fenêtre par WM_SYSCOMMAND', () {
      final source = lire('windows/runner/win32_window.cpp');
      expect(
        source,
        contains('const DWORD style = WS_OVERLAPPEDWINDOW;'),
        reason:
            'sans ces bits, DefWindowProc ignore SC_CLOSE / SC_MINIMIZE / '
            'SC_MAXIMIZE et les boutons dessinés en Dart ne font rien',
      );
      expect(
        source,
        isNot(contains('& ~(WS_SYSMENU')),
        reason: 'le retrait de 24/08/2026 est renversé (PO, 09/11/2026)',
      );
    });

    test('WM_GETMINMAXINFO passe AVANT les greffons : le plugin y répond 0 '
        'et court-circuiterait le minimum et la zone de travail', () {
      final source = lire('windows/runner/flutter_window.cpp');
      final minmax = source.indexOf('message == WM_GETMINMAXINFO');
      final greffons = source.indexOf('HandleTopLevelWindowProc');
      expect(minmax, greaterThan(0));
      expect(greffons, greaterThan(minmax));
    });

    test('le Windows réel mappe chaque bord sur le BON ResizeEdge', () {
      final source = lire('lib/core/fenetre/controle_fenetre_windows.dart');
      for (final (bord, arete) in [
        ('haut', 'top'),
        ('hautGauche', 'topLeft'),
        ('hautDroite', 'topRight'),
      ]) {
        expect(
          source,
          contains('BordFenetre.$bord => ResizeEdge.$arete,'),
          reason: bord,
        );
      }
    });

    test('la fenêtre est préparée AVANT runApp, au poste comme en démo', () {
      for (final f in ['lib/main.dart', 'lib/main_demo.dart']) {
        final source = lire(f);
        final prep = source.indexOf('ControleFenetreWindows.preparer()');
        final run = source.indexOf('runApp(');
        expect(prep, greaterThan(0), reason: f);
        expect(run, greaterThan(prep), reason: f);
      }
    });
  });
}
