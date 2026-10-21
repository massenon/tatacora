import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/navigation/coquille_vue.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_demarrage.dart';

import '../../support/vue_blade.dart';

/// Conformité de l'écran de démarrage au maître.
///
/// Source : la vue Blade `pwa/demarrage.blade.php` (PA-182, PA-183).
///
/// ## L'assertion qui compte le plus n'est pas visuelle
///
/// Le maître **connecte automatiquement en Administrateur système** (l.68-75).
/// `SECURITY_STRICT.md` §12bis l'interdit dans tout environnement. Le dernier
/// groupe de ce fichier tient cette exclusion — et il la tient par une
/// vérification de **contenu**, pas par une bonne intention en commentaire.
void main() {
  /// Le dernier arrivage du routeur, pour vérifier OÙ le démarrage aiguille.
  ///
  /// Un vrai `GoRouter` plutôt qu'un `home:` nu : sans lui, `context.go` lève
  /// et l'aiguillage — la seule chose que cet écran fait vraiment — ne serait
  /// jamais éprouvé. C'est le premier essai qui l'a montré.
  late String destination;

  Future<void> monter(WidgetTester tester, {double largeur = 1280}) async {
    tester.view.physicalSize = Size(largeur, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    destination = '/demarrage';
    final routeur = GoRouter(
      initialLocation: '/demarrage',
      routes: [
        GoRoute(path: '/demarrage', builder: (_, _) => const EcranDemarrage()),
        GoRoute(
          path: '/connexion',
          builder: (_, _) => const Scaffold(body: Text('ECRAN CONNEXION')),
        ),
        GoRoute(
          path: '/hebergement',
          builder: (_, _) => const Scaffold(body: Text('ECRAN HEBERGEMENT')),
        ),
      ],
    );
    routeur.routerDelegate.addListener(() {
      destination = routeur.state.matchedLocation;
    });
    addTearDown(routeur.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp.router(theme: AppTheme.clair, routerConfig: routeur),
      ),
    );
    await tester.pump();
  }

  group('Contenu — les textes du maître, au caractère près', () {
    testWidgets('titre, accroches et bandeau institutionnel', (tester) async {
      await monter(tester);

      for (final attendu in const [
        'TATACORA AFRIQUE',
        'GÎTE CHEZ NOËL — AGENCE DE VOYAGES & HÉBERGEMENT',
        // Décisions du PO du 13/10/2026 (PA-208, D385 ; PA-209, D389) puis du
        // 14/10/2026 — voir le cas suivant, qui relit la vue et la langue.
        'Système de gestion Intégré — Gîte Chez Noël, Natitingou (Bénin)',
        'PAEB',
        'FAGUEZ SARL',
        'Projet d\'Appui à l\'Entrepreneuriat au Bénin',
      ]) {
        expect(
          find.text(attendu),
          findsOneWidget,
          reason: 'texte du maître absent ou modifié : « $attendu »',
        );
      }

      // Le maître écrit la mention en minuscules et la met en capitales par
      // CSS (`uppercase`). Le résultat affiché est ce qui compte.
      expect(find.text('RÉALISÉ DANS LE CADRE DU'), findsOneWidget);
      // Le logo porte son `alt` (`pwa.alt_logo`), rendu en sémantique.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.label == 'Logo TATACORA AFRIQUE' &&
              w.properties.image == true,
        ),
        findsOneWidget,
      );

      // Deux images : la photo de fond et le logo.
      expect(
        find.byWidgetPredicate((w) => w is Image && w.image is AssetImage),
        findsNWidgets(2),
      );

      // Décision du PO du 14/10/2026 (D392, PA-210) : le logo PNG paysage,
      // contenu dans le cadre carré comme la vue l'écrit — jamais rogné.
      final vue = VueBlade.brute(
        'demarrage',
      ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
      expect(
        vue,
        contains(
          '<img src="{{ asset(\'assets/img/logo.png\') }}" '
          'alt="{{ __(\'pwa.alt_logo\') }}" class="w-24 h-24 rounded-2xl '
          'ring-4 ring-[var(--gold)]/60 object-contain shadow-2xl">',
        ),
      );
      final logo = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == AppAssets.logo,
      );
      expect(logo, findsOneWidget);
      expect(tester.widget<Image>(logo).fit, BoxFit.contain);

      // `shadow-2xl` est peint AUTOUR du cadre, jamais dessous : avec
      // `contain`, la bande libre sous le paysage montrerait sinon l'ombre.
      final decoupe = tester
          .widget<ClipPath>(find.byKey(const Key('ombre-logo-demarrage')))
          .clipper!
          .getClip(const Size.square(96));
      expect(decoupe.contains(const Offset(48, 48)), isFalse);
      expect(decoupe.contains(const Offset(48, 90)), isFalse);
      expect(decoupe.contains(const Offset(48, 120)), isTrue);
    });

    // Décision du PO du 13/10/2026 (PA-208, D385, étend D373) : la vue de
    // démarrage ne rend plus la clé dédiée (« … — LogiRestock ») mais la clé
    // de localisation des états, celle de la barre supérieure. Le cas relit
    // la VUE (quelle clé est rendue sous l'enseigne), puis la LANGUE (sa
    // valeur résolue par PHP), puis l'écran : remettre l'ancienne mention
    // dans `localisationDemarrage` le fait rougir.
    testWidgets(
      'la ligne sous l’enseigne est la clé de langue que la vue rend',
      (tester) async {
        final vue = VueBlade.brute(
          'demarrage',
        ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
        final ligne = RegExp(
          r'<p class="anim-2 text-white/50 text-\[15px\] mt-1">(.*?)</p>',
        ).firstMatch(vue);
        expect(ligne, isNotNull, reason: 'ligne sous l’enseigne introuvable');
        expect(
          ligne!.group(1)!.trim(),
          "{{ __('rapports.entete.localisation') }}",
        );
        expect(vue, isNot(contains('LogiRestock')));

        final valeur = VueBlade.libelle('rapports.entete.localisation');
        expect(valeur, localisationDemarrage);
        // Un seul texte pour la barre supérieure et le démarrage, comme la vue.
        expect(valeur, LibellesCoquille.localisation);

        await monter(tester);
        expect(find.text(valeur!), findsOneWidget);
        expect(find.textContaining('LogiRestock'), findsNothing);
        // PA-209, D389 : l'ancienne mention ne s'affiche plus.
        expect(
          find.textContaining(
            RegExp("syst[eè]me d['’]information", caseSensitive: false),
          ),
          findsNothing,
        );
      },
    );

    testWidgets('les cinq étapes défilent dans l’ordre du maître', (
      tester,
    ) async {
      await monter(tester);

      // `progression += 4` toutes les 60 ms, `floor(progression / 22)` désigne
      // l'étape. La première s'affiche avant tout avancement.
      expect(find.text('Initialisation du système...'), findsOneWidget);

      // 22 % atteint après 6 pas — on avance de quoi franchir deux seuils.
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Initialisation du système...'), findsNothing);

      // À la fin de la course (1 500 ms), la dernière étape est affichée.
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.text('Prêt.'), findsOneWidget);

      // La barre a bien avancé jusqu'au bout — sinon le texte final serait
      // affiché sans que la progression l'ait rejoint.
      final barre = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(barre.value, 1.0);

      // On laisse la pause de 300 ms s'écouler pour que le minuteur soit
      // arrêté avant le démontage.
      await tester.pump(const Duration(milliseconds: 400));
    });
  });

  group('Sécurité — §12bis, aucune connexion automatique', () {
    testWidgets('aucun compte, aucun rôle n’apparaît à l’écran', (
      tester,
    ) async {
      await monter(tester);

      // Le maître fabrique une session Administrateur. Rien de tel ici : cet
      // écran ne connecte personne, il lit une session existante ou renvoie
      // vers la connexion.
      for (final interdit in const [
        'Administrateur',
        'admin',
        'Connexion automatique',
      ]) {
        expect(
          find.textContaining(interdit),
          findsNothing,
          reason: '§12bis : « $interdit » ne doit pas figurer au démarrage',
        );
      }

      // Et l'aiguillage : sans session, on part vers la CONNEXION. Le maître
      // serait entré directement, en Administrateur.
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();
      expect(
        destination,
        '/connexion',
        reason: '§12bis : sans session, le démarrage exige une connexion',
      );
      expect(find.text('ECRAN CONNEXION'), findsOneWidget);
    });
  });

  group('Mise en page — ce qu’une relecture ne voit pas', () {
    testWidgets('aucun débordement, du plus étroit au plus large', (
      tester,
    ) async {
      // Le bandeau institutionnel est en position absolue au bas ; c'est lui
      // qui déborde en premier sur un écran court ou étroit.
      for (final largeur in const [360.0, 767.0, 1440.0]) {
        await monter(tester, largeur: largeur);
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.takeException(),
          isNull,
          reason: 'débordement à $largeur px',
        );
        await tester.pump(const Duration(milliseconds: 2000));
      }
    });
  });
}
