import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/navigation/trace_svg.dart';
import 'package:tatacora_flutter/core/theme/app_colors.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/core/theme/mesures_connexion.dart';
import 'package:tatacora_flutter/features/auth/data/identifiant_memorise.dart';
import 'package:tatacora_flutter/features/parametres/data/apparence_poste.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/auth/presentation/ecran_connexion.dart';
import 'package:tatacora_flutter/features/auth/presentation/formulaire_premier_compte.dart';

import '../../support/vue_blade.dart';

/// Conformité de l'écran de connexion au maître de mise en page.
///
/// Le maître est la vue Blade `pwa/livewire/connexion.blade.php` (PA-182,
/// PA-183 — l'ancien prototype ne fait plus foi), refondue le 29/10/2026 en
/// carte unique (`docs/HANDOFF_ECRAN_CONNEXION_LOGIRESTOCK.md`). Ces cas ne
/// jugent pas l'esthétique : ils vérifient la **structure**, les **libellés**
/// (confrontés à la langue du serveur, résolue par PHP), les **pictogrammes**
/// (confrontés aux tracés de la vue) et l'**accessibilité** clavier.
///
/// ## Pourquoi un test de rendu, et pas une relecture
///
/// Une relecture ne voit pas un débordement. Monter l'écran à une largeur
/// donnée le révèle, parce que le moteur de rendu lève sur un dépassement.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory memoire;
  late AppDatabase base;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    memoire = Directory.systemTemp.createTempSync('tatacora-connexion-');
    base = AppDatabase.enMemoire();
    // La VRAIE authentification locale, sur une base en mémoire : un compte.
    await SessionRepositoryLocal(base).creerCompte(
      login: 'n.nabogou',
      nom: 'NABOGOU Noël',
      motDePasse: 'motdepasse123',
      role: 'receptionniste',
      droits: const {'M1': 'C'},
    );
  });
  tearDown(() async {
    await base.close();
    if (memoire.existsSync()) memoire.deleteSync(recursive: true);
  });

  /// Soumet le formulaire et laisse le temps RÉEL à la base de répondre.
  Future<void> soumettre(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(TextesConnexion.valider));
    await tester.pumpAndSettle();
    await tester.tap(find.text(TextesConnexion.valider));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
    await tester.pump();
  }

  Session? sessionOuverte(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(EcranConnexion)),
  ).read(sessionProvider);

  /// Monte l'écran à une largeur donnée.
  Future<void> monter(
    WidgetTester tester,
    double largeur, {
    double hauteur = 900,
    bool aucunCompte = false,
    Uint8List? logo,
  }) async {
    tester.view.physicalSize = Size(largeur, hauteur);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // **Le poste porte déjà un compte.** Depuis PA-103, l'écran cède la
          // place à la création du premier compte quand la base est vierge.
          aucunCompteProvider.overrideWith((ref) async => aucunCompte),
          baseLocaleProvider.overrideWithValue(base),
          logoTeleverseProvider.overrideWith((ref) async => logo),
          // La mémoire de « Se souvenir » vit dans un dossier d'essai.
          dossierConnexionProvider.overrideWithValue(() async => memoire),
        ],
        child: MaterialApp(theme: AppTheme.clair, home: const EcranConnexion()),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// La vue, commentaires Blade retirés.
  String vue() => VueBlade.brute(
    'livewire/connexion',
  ).replaceAll(RegExp(r'\{\{--.*?--\}\}', dotAll: true), '');

  group('Structure — une carte unique, dans l\'ordre de la vue', () {
    testWidgets('aucune photo, aucune colonne : la carte seule', (
      tester,
    ) async {
      for (final largeur in const [800.0, 1440.0]) {
        await monter(tester, largeur);
        // Plus de panneau image (`hidden lg:block lg:w-1/2` retiré de la vue).
        expect(find.byType(Image), findsNothing);
        expect(vue(), isNot(contains('gite-cover')));
        expect(vue(), contains('max-w-[560px]'));
      }
    });

    testWidgets('la carte est bornée à 560 px et centrée', (tester) async {
      await monter(tester, 1440);
      final carte = find.byType(Form);
      final boite = tester.getRect(carte);
      expect(
        boite.width,
        MesuresConnexion.largeurCarte - 2 * MesuresConnexion.interieurLarge - 2,
        reason: 'la largeur du formulaire = carte 560 − 2 × 32 − 2 de bordure',
      );
      expect(
        (boite.center.dx - 1440 / 2).abs(),
        lessThan(1),
        reason: 'la carte est centrée horizontalement',
      );
    });

    testWidgets('les éléments se suivent de haut en bas comme dans la vue', (
      tester,
    ) async {
      await monter(tester, 1280);
      // L'ordre du handoff §1, relu dans la vue ET vérifié dans le rendu.
      final textes = <String>[
        TextesConnexion.slogan,
        TextesConnexion.bienvenue,
        TextesConnexion.accroche,
        TextesConnexion.login,
        TextesConnexion.motDePasse,
        TextesConnexion.seSouvenir,
        TextesConnexion.motDePasseOublie,
        TextesConnexion.valider,
        TextesConnexion.piedDePage,
      ];
      var yPrecedent = -1.0;
      for (final t in textes) {
        final y = tester.getTopLeft(find.text(t)).dy;
        expect(y, greaterThan(yPrecedent), reason: '« $t » hors d\'ordre');
        yPrecedent = y;
      }

      // La marque (deux tons) est AU-DESSUS du slogan.
      final marque = find.text('Logi');
      expect(marque, findsOneWidget);
      expect(
        tester.getTopLeft(marque).dy,
        lessThan(tester.getTopLeft(find.text(TextesConnexion.slogan)).dy),
      );

      // Le même ordre, dans le document de la vue.
      final v = VueBlade.resolue('livewire/connexion');
      var p = 0;
      for (final t in textes.take(8)) {
        final i = v.indexOf(t.replaceAll("'", "'"), p);
        expect(i, greaterThanOrEqualTo(0), reason: '« $t » absent de la vue');
        p = i + t.length;
      }
    });

    testWidgets('la marque est en DEUX tons : Logi navy, ReStock gold', (
      tester,
    ) async {
      await monter(tester, 1280);
      final logi = tester.widget<Text>(find.text('Logi'));
      final restock = tester.widget<Text>(find.text('ReStock'));
      expect(logi.style!.color, AppColors.navy);
      expect(restock.style!.color, AppColors.gold);
      // Collés : « LogiReStock » est UN mot, deux tons.
      expect(
        tester.getTopRight(find.text('Logi')).dx,
        closeTo(tester.getTopLeft(find.text('ReStock')).dx, 0.5),
      );
      expect(find.text('TATACORA AFRIQUE'), findsOneWidget);
    });

    testWidgets('le bandeau porte SEPT pictogrammes, chacun avec son nom', (
      tester,
    ) async {
      await monter(tester, 1280);
      const modules = [
        'Restauration',
        'Hébergement',
        'Éco-tourisme',
        'Stock',
        'Location',
        'Caisse',
        'Comptabilité',
      ];
      for (final m in modules) {
        expect(find.byTooltip(m), findsOneWidget, reason: 'infobulle « $m »');
        final icone = find.descendant(
          of: find.byTooltip(m),
          matching: find.byType(IconeTrace),
        );
        expect(icone, findsOneWidget);
        expect(tester.widget<IconeTrace>(icone).taille, 26);
      }
      // Les sept se partagent la largeur à égale distance.
      final xs = [
        for (final m in modules) tester.getCenter(find.byTooltip(m)).dx,
      ];
      final pas = xs[1] - xs[0];
      for (var i = 2; i < xs.length; i++) {
        expect(xs[i] - xs[i - 1], closeTo(pas, 0.5));
      }
    });
  });

  group('Logo téléversé — décision du PO du 29/10/2026', () {
    // PNG 1 × 1 valide.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    testWidgets(
      'présent : il coiffe la carte (64 px), le pictogramme s\'efface',
      (tester) async {
        await monter(tester, 1280, logo: png);
        await tester.pump();
        final image = tester.widget<Image>(find.byType(Image));
        expect(image.height, 64);
        expect(image.fit, BoxFit.contain);
        expect(image.semanticLabel, 'Logo TATACORA AFRIQUE');
        expect(
          tester.getTopLeft(find.byType(Image)).dy,
          lessThan(tester.getTopLeft(find.text('Logi')).dy),
          reason: 'le logo est AU-DESSUS de la marque',
        );
        expect(
          find.byWidgetPredicate(
            (w) => w is IconeTrace && w.trace == MesuresConnexion.traceMarque,
          ),
          findsNothing,
        );
        // La marque et le slogan restent sous le logo.
        expect(find.text('Logi'), findsOneWidget);
        expect(find.text(TextesConnexion.slogan), findsOneWidget);
      },
    );

    testWidgets('absent : repli sur le pictogramme de marque', (tester) async {
      await monter(tester, 1280);
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) => w is IconeTrace && w.trace == MesuresConnexion.traceMarque,
        ),
        findsOneWidget,
      );
    });

    testWidgets('aucun débordement avec le logo, de 320 px au large', (
      tester,
    ) async {
      for (final largeur in const [320.0, 1440.0]) {
        await monter(tester, largeur, logo: png);
        expect(tester.takeException(), isNull, reason: 'à $largeur px');
      }
    });
  });

  group('Libellés — au caractère près, relus dans la langue du serveur', () {
    test('chaque texte de l\'écran est celui de `lang/fr/pwa.php`', () {
      const attendu = <String, String>{
        'pwa.connexion.titre_h1': TextesConnexion.titreH1,
        'pwa.connexion.marque_logi': TextesConnexion.marqueLogi,
        'pwa.connexion.marque_restock': TextesConnexion.marqueRestock,
        'pwa.marque': TextesConnexion.sousMarque,
        'pwa.connexion.slogan': TextesConnexion.slogan,
        'pwa.connexion.modules.restauration': TextesConnexion.restauration,
        'pwa.connexion.modules.hebergement': TextesConnexion.hebergement,
        'pwa.connexion.modules.eco_tourisme': TextesConnexion.ecoTourisme,
        'pwa.connexion.modules.stock': TextesConnexion.stock,
        'pwa.connexion.modules.location': TextesConnexion.location,
        'pwa.connexion.modules.caisse': TextesConnexion.caisse,
        'pwa.connexion.modules.comptabilite': TextesConnexion.comptabilite,
        'pwa.connexion.bandeau_modules': TextesConnexion.bandeauModules,
        'pwa.connexion.bienvenue': TextesConnexion.bienvenue,
        'pwa.connexion.accroche': TextesConnexion.accroche,
        'pwa.connexion.login': TextesConnexion.login,
        'pwa.connexion.mot_de_passe': TextesConnexion.motDePasse,
        'pwa.connexion.afficher_mot_de_passe':
            TextesConnexion.afficherMotDePasse,
        'pwa.connexion.masquer_mot_de_passe': TextesConnexion.masquerMotDePasse,
        'pwa.connexion.se_souvenir': TextesConnexion.seSouvenir,
        'pwa.connexion.mot_de_passe_oublie': TextesConnexion.motDePasseOublie,
        'pwa.connexion.mot_de_passe_oublie_aide':
            TextesConnexion.motDePasseOublieAide,
        'pwa.connexion.valider': TextesConnexion.valider,
        'pwa.connexion.connexion_en_cours': TextesConnexion.connexionEnCours,
        'pwa.pied_de_page': TextesConnexion.piedDePage,
      };
      expect(attendu.length, greaterThan(20), reason: 'plancher');
      attendu.forEach((cle, dart) {
        expect(VueBlade.libelle(cle), dart, reason: 'la clé $cle a dérivé');
      });
    });

    test('la vue rend bien chacune de ces clés (aucune clé orpheline)', () {
      final v = vue();
      for (final cle in const [
        'titre_h1',
        'marque_logi',
        'marque_restock',
        'slogan',
        'bandeau_modules',
        'bienvenue',
        'accroche',
        'login',
        'mot_de_passe',
        'afficher_mot_de_passe',
        'masquer_mot_de_passe',
        'se_souvenir',
        'mot_de_passe_oublie',
        'mot_de_passe_oublie_aide',
        'valider',
        'connexion_en_cours',
      ]) {
        expect(v, contains('pwa.connexion.$cle'), reason: 'vue sans $cle');
      }
    });

    testWidgets('les textes affichés sont ceux de la vue', (tester) async {
      await monter(tester, 1280);
      for (final t in [
        TextesConnexion.sousMarque,
        TextesConnexion.slogan,
        TextesConnexion.bienvenue,
        TextesConnexion.accroche,
        TextesConnexion.login,
        TextesConnexion.motDePasse,
        TextesConnexion.seSouvenir,
        TextesConnexion.motDePasseOublie,
        TextesConnexion.valider,
        TextesConnexion.piedDePage,
      ]) {
        expect(find.text(t), findsOneWidget, reason: '« $t » absent');
      }
      // Les anciens libellés ont disparu.
      expect(find.text('Se connecter'), findsNothing);
      expect(find.text('Identifiant'), findsNothing);
      expect(find.textContaining('espace de travail'), findsNothing);
      expect(find.textContaining('LogiRestock'), findsNothing);
    });

    testWidgets('les refus de saisie vide sont dits sous les champs', (
      tester,
    ) async {
      await monter(tester, 1280);
      await tester.tap(find.text(TextesConnexion.valider));
      await tester.pump();

      expect(find.text('Veuillez saisir votre identifiant.'), findsOneWidget);
      expect(find.text('Veuillez saisir votre mot de passe.'), findsOneWidget);
      expect(sessionOuverte(tester), isNull, reason: 'rien ne part à vide');
    });
  });

  group('Pictogrammes — les mêmes tracés que la vue', () {
    /// `nom → éléments (balise, attributs sans stroke-*)` du partial Blade.
    Map<String, List<String>> tracesDeLaVue() {
      final source = VueBlade.brute('partials/pictogramme-connexion');
      final blocs = RegExp(
        r"@case\('([a-z_]+)'\)(.*?)@break",
        dotAll: true,
      ).allMatches(source);
      return {for (final b in blocs) b.group(1)!: _elements(b.group(2)!)};
    }

    test('les treize tracés de Dart sont ceux du partial Blade', () {
      final vueTraces = tracesDeLaVue();
      final dart = <String, String>{
        'marque': MesuresConnexion.traceMarque,
        'restauration': MesuresConnexion.traceRestauration,
        'hebergement': MesuresConnexion.traceHebergement,
        'eco_tourisme': MesuresConnexion.traceEcoTourisme,
        'stock': MesuresConnexion.traceStock,
        'location': MesuresConnexion.traceLocation,
        'caisse': MesuresConnexion.traceCaisse,
        'comptabilite': MesuresConnexion.traceComptabilite,
        'utilisateur': MesuresConnexion.traceUtilisateur,
        'cadenas': MesuresConnexion.traceCadenas,
        'cadenas_ouvert': MesuresConnexion.traceCadenasOuvert,
        'oeil': MesuresConnexion.traceOeil,
        'oeil_barre': MesuresConnexion.traceOeilBarre,
      };
      // Plancher : sans lui, un partial renommé rendrait la boucle vide.
      expect(vueTraces.keys.toSet(), dart.keys.toSet());
      dart.forEach((nom, trace) {
        expect(_elements(trace), vueTraces[nom], reason: 'tracé « $nom »');
        // Et le lecteur de tracés sait les dessiner (il lève sinon).
        expect(TraceSvg.lire(trace).elements, isNotEmpty);
      });
    });

    test('la vue pose le fil arrondi de 2 sur chaque pictogramme', () {
      final source = VueBlade.brute('partials/pictogramme-connexion');
      expect(source, contains('stroke-width="2"'));
      expect(source, contains('stroke-linecap="round"'));
      expect(source, contains('aria-hidden="true"'));
      // Aucune dépendance : pas d'image, pas de CDN.
      expect(source, isNot(contains('http')));
    });
  });

  group('Accessibilité — clavier, étiquettes, œil', () {
    testWidgets('l\'ordre de tabulation est celui du handoff §8', (
      tester,
    ) async {
      await monter(tester, 1280);
      await tester.pump();

      bool sur<T extends Widget>() =>
          FocusManager.instance.primaryFocus?.context
              ?.findAncestorWidgetOfExactType<T>() !=
          null;

      // L'identifiant a le focus d'emblée (`autofocus`).
      expect(sur<EditableText>(), isTrue);
      final premier = FocusManager.instance.primaryFocus!.context!
          .findAncestorWidgetOfExactType<EditableText>()!;
      expect(
        premier.autofocus && !premier.obscureText,
        isTrue,
        reason: 'le premier arrêt est l\'identifiant',
      );

      Future<void> tab() async {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }

      await tab(); // mot de passe
      expect(sur<EditableText>(), isTrue);
      expect(
        FocusManager.instance.primaryFocus!.context!
            .findAncestorWidgetOfExactType<EditableText>()!
            .obscureText,
        isTrue,
        reason: 'le deuxième arrêt est le mot de passe',
      );
      await tab(); // œil
      expect(sur<IconButton>(), isTrue, reason: 'l\'œil vient après le champ');
      await tab(); // case
      expect(sur<Checkbox>(), isTrue, reason: '« Se souvenir de moi »');
      await tab(); // lien
      expect(sur<TextButton>(), isTrue, reason: '« Mot de passe oublié ? »');
      await tab(); // bouton
      expect(sur<ElevatedButton>(), isTrue, reason: '« SE CONNECTER »');
    });

    testWidgets('chaque champ porte son étiquette en sémantique', (
      tester,
    ) async {
      final poignee = tester.ensureSemantics();
      await monter(tester, 1280);
      for (final etiquette in [
        TextesConnexion.login,
        TextesConnexion.motDePasse,
      ]) {
        final i = [
          TextesConnexion.login,
          TextesConnexion.motDePasse,
        ].indexOf(etiquette);
        final noeud = tester.getSemantics(find.byType(TextFormField).at(i));
        expect(noeud.label, contains(etiquette), reason: 'champ $i');
      }
      poignee.dispose();
    });

    testWidgets(
      'l\'œil bascule le texte, nomme l\'action et se pose en bouton',
      (tester) async {
        await monter(tester, 1280);
        EditableText champMotDePasse() => tester.widget<EditableText>(
          find.descendant(
            of: find.byType(TextFormField).last,
            matching: find.byType(EditableText),
          ),
        );

        expect(champMotDePasse().obscureText, isTrue);
        expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
        await tester.tap(find.byTooltip('Afficher le mot de passe'));
        await tester.pump();
        expect(champMotDePasse().obscureText, isFalse);
        expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
        expect(find.byTooltip('Afficher le mot de passe'), findsNothing);

        // Au clavier : Entrée et Espace activent l'œil focalisé.
        // Deux Tab depuis l'identifiant (autofocus) : mot de passe, puis œil.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(champMotDePasse().obscureText, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(champMotDePasse().obscureText, isFalse);
      },
    );

    testWidgets(
      '« Mot de passe oublié ? » dit de contacter l\'administrateur',
      (tester) async {
        await monter(tester, 1280);
        expect(find.text("Contactez l'administrateur"), findsNothing);
        await tester.tap(find.text('Mot de passe oublié ?'));
        await tester.pump();
        expect(find.text("Contactez l'administrateur"), findsOneWidget);
        await tester.tap(find.text('Mot de passe oublié ?'));
        await tester.pump();
        expect(find.text("Contactez l'administrateur"), findsNothing);
      },
    );

    testWidgets('Entrée dans un champ soumet le formulaire', (tester) async {
      await monter(tester, 1280);
      await tester.enterText(find.byType(TextFormField).first, 'n.nabogou');
      await tester.enterText(find.byType(TextFormField).last, 'motdepasse123');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      expect(sessionOuverte(tester)?.login, 'n.nabogou');
    });

    testWidgets('un refus s\'annonce, et aucun message « réseau » n\'existe', (
      tester,
    ) async {
      await monter(tester, 1280);
      await tester.enterText(find.byType(TextFormField).first, 'n.nabogou');
      await tester.enterText(
        find.byType(TextFormField).last,
        'faux-mot-de-passe',
      );
      await soumettre(tester);
      expect(find.textContaining('⚠ '), findsOneWidget);
      expect(sessionOuverte(tester), isNull);
      expect(find.textContaining('réseau'), findsNothing);
      expect(find.textContaining('injoignable'), findsNothing);
    });
  });

  group('« Se souvenir de moi » — l\'identifiant seul', () {
    testWidgets('coché, l\'identifiant est mémorisé, jamais le mot de passe', (
      tester,
    ) async {
      await monter(tester, 1280);
      await tester.tap(find.text(TextesConnexion.seSouvenir));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).first, 'n.nabogou');
      await tester.enterText(
        find.byType(TextFormField).last,
        'motdepasse-secret',
      );
      await soumettre(tester);

      final fichiers = memoire.listSync(recursive: true).whereType<File>();
      expect(fichiers, hasLength(1));
      expect(fichiers.single.readAsStringSync(), 'n.nabogou');
      for (final f in fichiers) {
        expect(
          f.readAsStringSync(),
          isNot(contains('motdepasse-secret')),
          reason: 'le mot de passe ne touche JAMAIS le disque',
        );
      }
    });

    testWidgets(
      'au lancement suivant, l\'identifiant revient, pas le mot de passe',
      (tester) async {
        File('${memoire.path}/identifiant.txt').writeAsStringSync('n.nabogou');
        await monter(tester, 1280);
        await tester.pump();

        final champs = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .toList();
        expect(champs.first.controller!.text, 'n.nabogou');
        expect(champs.last.controller!.text, isEmpty);
        final case_ = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(case_.value, isTrue, reason: 'la case reflète la mémoire');
      },
    );

    testWidgets('décoché, la mémoire est effacée', (tester) async {
      File('${memoire.path}/identifiant.txt').writeAsStringSync('n.nabogou');
      await monter(tester, 1280);
      await tester.pump();
      await tester.tap(find.text(TextesConnexion.seSouvenir)); // décoche
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).last, 'x');
      await soumettre(tester);
      expect(File('${memoire.path}/identifiant.txt').existsSync(), isFalse);
    });
  });

  group('Sécurité — ce qui ne se porte jamais', () {
    testWidgets('aucune grille de comptes de démonstration', (tester) async {
      await monter(tester, 1280);

      // `SECURITY_STRICT.md` §12 : interdite dans TOUT environnement, y
      // compris `demo`.
      expect(find.text('Comptes de démonstration (RBAC)'), findsNothing);
      expect(find.textContaining('cliquez pour vous connecter'), findsNothing);
      expect(find.textContaining('démonstration'), findsNothing);

      // Aucun identifiant ne doit être pré-rempli, par quelque chemin que ce
      // soit : un champ pré-rempli fuit à la première capture d'écran.
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

  group('Poste vierge — seul l\'en-tête de marque est repris', () {
    testWidgets('le formulaire de premier compte garde son écran', (
      tester,
    ) async {
      await monter(tester, 1280, aucunCompte: true);
      expect(find.byType(FormulairePremierCompte), findsOneWidget);
      expect(
        find.text('Logi'),
        findsOneWidget,
        reason: 'la marque reste en tête',
      );
      expect(find.text('ReStock'), findsOneWidget);
      // Ni slogan, ni bandeau, ni champs de connexion.
      expect(find.text(TextesConnexion.slogan), findsNothing);
      expect(find.text(TextesConnexion.valider), findsNothing);
    });
  });

  group('Mise en page — ce qu\'une relecture ne voit pas', () {
    testWidgets('aucun débordement, de 320 px au plus large', (tester) async {
      // Du plus étroit des téléphones aux écrans larges, en passant par les
      // deux seuils de la vue (`md` 768 pour les marges, 560 + marges pour la
      // carte pleine).
      for (final largeur in const [
        320.0,
        360.0,
        480.0,
        767.0,
        768.0,
        1023.0,
        1440.0,
        2560.0,
      ]) {
        await monter(tester, largeur);
        expect(
          tester.takeException(),
          isNull,
          reason: 'débordement ou contrainte non satisfaite à $largeur px',
        );
        // Aucun défilement horizontal : la carte ne dépasse jamais l'écran.
        final carte = tester.getRect(find.byType(Form));
        expect(carte.left, greaterThanOrEqualTo(0));
        expect(carte.right, lessThanOrEqualTo(largeur));
      }
    });

    testWidgets(
      'aucun débordement en cours de connexion, erreur et aide ouvertes',
      (tester) async {
        for (final largeur in const [320.0, 1440.0]) {
          await monter(tester, largeur, hauteur: 500);
          await tester.ensureVisible(find.text('Mot de passe oublié ?'));
          await tester.tap(find.text('Mot de passe oublié ?'));
          await tester.enterText(find.byType(TextFormField).first, 'x' * 80);
          await tester.enterText(find.byType(TextFormField).last, 'y');
          // Un identifiant de 80 caractères : refusé, le bandeau d'erreur se
          // montre avec l'aide ouverte, hauteur réduite à 500 px.
          await soumettre(tester);
          expect(find.textContaining('⚠ '), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'à $largeur px');
        }
      },
    );

    testWidgets('le champ et le bouton font au moins 48 px (cible tactile)', (
      tester,
    ) async {
      await monter(tester, 360);
      for (final f in tester.widgetList(find.byType(TextFormField))) {
        final h = tester.getSize(find.byWidget(f)).height;
        expect(h, greaterThanOrEqualTo(48));
      }
      expect(
        tester.getSize(find.byType(ElevatedButton)).height,
        greaterThanOrEqualTo(48),
      );
    });
  });
}

/// Les éléments d'un tracé, sans les attributs `stroke-*` (la vue les pose sur
/// le `<svg>`, Dart sur chaque élément), attributs triés : deux tracés égaux
/// donnent la même liste.
List<String> _elements(String source) {
  final balise = RegExp(r'<\s*(path|rect|circle)\b([^>]*?)/?>');
  final attribut = RegExp(r'([a-zA-Z][\w-]*)\s*=\s*"([^"]*)"');
  return [
    for (final m in balise.allMatches(source))
      '${m.group(1)} '
          '${(attribut.allMatches(m.group(2)!).where((a) => !a.group(1)!.startsWith('stroke')).map((a) => '${a.group(1)}=${a.group(2)}').toList()..sort()).join(' ')}',
  ];
}
