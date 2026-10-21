import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/theme/app_assets.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';

import '../../support/vue_blade.dart';

/// Conformité de l'écran de connexion au maître de mise en page.
///
/// Le maître est la vue Blade `pwa/livewire/connexion.blade.php` (PA-182,
/// PA-183 — l'ancien prototype ne fait plus foi). Ces cas ne jugent pas
/// l'esthétique : ils vérifient que la **structure** et les **libellés** sont
/// ceux de l'écran que le commanditaire voit.
///
/// ## Pourquoi un test de rendu, et pas une relecture
///
/// Une relecture ne voit pas un débordement. Monter l'écran à une largeur
/// donnée le révèle, parce que le moteur de rendu lève sur un dépassement.
/// C'est le seul contrôle qui attrape ce qu'un œil laisse passer — et c'est
/// aussi le seul qui empêchera la mise en page de dériver au prochain
/// changement, quand plus personne n'aura le HTML sous les yeux.
void main() {
  /// Monte l'écran à une largeur donnée.
  ///
  /// La largeur est ce qui décide de tout ici : le maître bascule à `lg`,
  /// c'est-à-dire **1024 px** chez Tailwind.
  Future<void> monter(WidgetTester tester, double largeur) async {
    tester.view.physicalSize = Size(largeur, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // **Le poste porte deja un compte.** Depuis PA-103, l'ecran cede la
          // place a la creation du premier compte quand la base est vierge ;
          // sans cette declaration, ces cas monteraient le mauvais formulaire
          // et rougiraient pour une raison qui n'est pas celle qu'ils
          // eprouvent. La creation a ses propres cas.
          aucunCompteProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(theme: AppTheme.clair, home: const EcranConnexion()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('Structure — le maître impose DEUX colonnes', () {
    testWidgets('au-delà de 1024 px, la colonne image est présente', (
      tester,
    ) async {
      await monter(tester, 1280);

      // `hidden lg:block lg:w-1/2` : la photo n'existe qu'au-dessus du seuil.
      final photo = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage,
      );
      expect(
        photo,
        findsNWidgets(2),
        reason: 'la photo de couverture ET le logo doivent être montés',
      );

      // Le titre de la colonne image, avec son retour à la ligne forcé — la
      // vue le pose par un <br>, elle ne le laisse pas à la largeur. Le texte
      // est la clé de la vue résolue par PHP (décision du PO du 13/10/2026,
      // PA-208, D385 : « LogiRestock » remplacé) : remettre l'ancien nom dans
      // l'écran fait rougir ce cas.
      final vue = VueBlade.brute(
        'livewire/connexion',
      ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
      expect(vue, contains("{!! __('pwa.connexion.titre_panneau') !!}"));
      final titre = VueBlade.libelle('pwa.connexion.titre_panneau')!;
      // Seconde décision du PO du 13/10/2026 (PA-209, D389) : « Système de
      // gestion Intégré », casse exacte du PO.
      expect(titre, 'Système de gestion Intégré<br>TATACORA AFRIQUE');
      expect(find.text(titre.replaceAll('<br>', '\n')), findsOneWidget);
      expect(find.textContaining('LogiRestock'), findsNothing);
      expect(
        find.textContaining(
          RegExp("syst[eè]me d['’]information", caseSensitive: false),
        ),
        findsNothing,
      );
      expect(
        find.textContaining('une seule plateforme, pour le Gîte Chez Noël'),
        findsOneWidget,
      );
    });

    testWidgets('en deçà de 1024 px, la colonne image disparaît', (
      tester,
    ) async {
      await monter(tester, 800);

      // Ce n'est PAS une simplification : c'est `hidden lg:block`, le
      // comportement responsive du maître lui-même.
      expect(
        find.text('Système de gestion Intégré\nTATACORA AFRIQUE'),
        findsNothing,
      );

      // `lg:hidden` (l.26-28) : le logo réapparaît alors au-dessus du
      // formulaire. Un seul logo monté, jamais zéro, jamais deux.
      final logos = find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage,
      );
      expect(
        logos,
        findsOneWidget,
        reason: 'privé de colonne image, le formulaire garde SON logo',
      );
      // Décision du PO du 14/10/2026 (D392, PA-210) : le PNG paysage,
      // contenu dans son cadre carré (`object-contain` de la vue).
      expect(
        (tester.widget<Image>(logos).image as AssetImage).assetName,
        AppAssets.logo,
      );
      expect(tester.widget<Image>(logos).fit, BoxFit.contain);
    });

    testWidgets('les deux logos de la vue sont contenus, jamais rognés', (
      tester,
    ) async {
      await monter(tester, 1280);

      // Décision du PO du 14/10/2026 (D392, PA-210) : la vue garde ses deux
      // cadres carrés et passe d'`object-cover` à `object-contain`.
      final vue = VueBlade.brute(
        'livewire/connexion',
      ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');
      final balises = RegExp(
        r'<img src="\{\{ asset\(.assets/img/logo\.png.\) \}\}"[^>]*>',
      ).allMatches(vue).map((m) => m.group(0)!).toList();
      expect(balises, hasLength(2));
      for (final balise in balises) {
        expect(balise, contains('object-contain'));
        expect(balise, isNot(contains('object-cover')));
      }

      final logo = find.byWidgetPredicate(
        (w) =>
            w is Image &&
            w.image is AssetImage &&
            (w.image as AssetImage).assetName == AppAssets.logo,
      );
      expect(logo, findsOneWidget);
      expect(tester.widget<Image>(logo).fit, BoxFit.contain);
    });
  });

  group('Libellés — au caractère près', () {
    testWidgets('le bouton « œil » dit la PHRASE de la vue, et les logos '
        'portent leur `alt`', (tester) async {
      await monter(tester, 1280);
      // `pwa.connexion.afficher_mot_de_passe` / `masquer_mot_de_passe`.
      expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
      await tester.tap(find.byTooltip('Afficher le mot de passe'));
      await tester.pump();
      expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
      expect(find.byTooltip('Afficher le mot de passe'), findsNothing);
      // `pwa.alt_logo`, rendu en sémantique sur CHAQUE logo de la vue.
      expect(
        find.byWidgetPredicate(
          (w) => w is Image && w.semanticLabel == 'Logo TATACORA AFRIQUE',
        ),
        findsWidgets,
      );
    });

    testWidgets('les textes du formulaire sont ceux du maître', (tester) async {
      await monter(tester, 1280);

      for (final attendu in const [
        'TATACORA AFRIQUE',
        'Connectez-vous à votre espace de travail',
        'Se connecter',
        'TATACORA AFRIQUE © 2026 — PAEB / FAGUEZ SARL',
      ]) {
        expect(
          find.text(attendu),
          findsOneWidget,
          reason: 'libellé du maître absent ou modifié : « $attendu »',
        );
      }

      // Les étiquettes sont des `<label>` au-dessus du champ, suivis d'un
      // astérisque rouge — pas un `labelText` flottant de Material.
      expect(find.textContaining('Identifiant'), findsWidgets);
      expect(find.textContaining('Mot de passe'), findsWidgets);

      // Les indications de saisie viennent du maître, l.35 et l.40.
      expect(find.text('ex. n.nabogou'), findsOneWidget);
      expect(find.text('••••••••'), findsOneWidget);
    });

    testWidgets('les messages de refus sont ceux du maître', (tester) async {
      await monter(tester, 1280);

      // Soumettre à vide : `data-regle-requis` du maître, mot pour mot.
      await tester.tap(find.text('Se connecter'));
      await tester.pump();

      expect(find.text('Veuillez saisir votre identifiant.'), findsOneWidget);
      expect(find.text('Veuillez saisir votre mot de passe.'), findsOneWidget);
    });
  });

  group('Sécurité — ce qui ne se porte jamais', () {
    testWidgets('aucune grille de comptes de démonstration', (tester) async {
      await monter(tester, 1280);

      // `SECURITY_STRICT.md` §12 : interdite dans TOUT environnement, y
      // compris `demo`. Le maître en affiche une (l.54-67) ; c'est la seule
      // exclusion assumée de cet écran.
      expect(find.text('Comptes de démonstration (RBAC)'), findsNothing);
      expect(find.textContaining('cliquez pour vous connecter'), findsNothing);

      // Le séparateur part AVEC la grille : il n'annonce qu'elle. Le garder
      // laisserait un intitulé qui n'introduit rien — moins fidèle que de
      // retirer les deux.
      expect(find.textContaining('démonstration'), findsNothing);

      // Aucun identifiant ne doit être pré-rempli, par quelque chemin que ce
      // soit — c'est la garantie que la grille visait, et elle vaut même sans
      // grille : un champ pré-rempli fuit à la première capture d'écran.
      for (final champ in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(
          champ.controller?.text ?? '',
          isEmpty,
          reason: 'aucun champ ne doit arriver pré-rempli',
        );
      }
    });
  });

  group('Mise en page — ce qu\'une relecture ne voit pas', () {
    testWidgets('aucun débordement, du plus étroit au plus large', (
      tester,
    ) async {
      // Trois largeurs qui encadrent le seuil : bien en deçà, juste en deçà,
      // et au-delà. Le bord du seuil est l'endroit où les mises en page
      // cassent — pas le milieu des paliers.
      for (final largeur in const [360.0, 1023.0, 1440.0]) {
        await monter(tester, largeur);
        expect(
          tester.takeException(),
          isNull,
          reason: 'débordement ou contrainte non satisfaite à $largeur px',
        );
      }
    });
  });
}
