import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/fichiers/selecteur_fichiers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/parametres/data/apparence_poste.dart';
import 'package:tatacora_flutter/features/parametres/presentation/ecran_parametres.dart';

import '../../support/selecteur_essai.dart';

/// Paramètres → « Logo & Apparence » (21/10/2026) : l'onglet n'était qu'une
/// note « pas de source » ; il porte désormais les aperçus, le remplacement du
/// logo et du favicon, et la charte en lecture seule, comme la vue.
void main() {
  late AppDatabase db;
  late Directory dossier;

  // Un PNG minimal valide (1×1).
  final png = Uint8List.fromList(const [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x48,
    0x44,
    0x52,
    0x00,
    0x00,
    0x00,
    0x01,
    0x00,
    0x00,
    0x00,
    0x01,
    0x08,
    0x06,
    0x00,
    0x00,
    0x00,
    0x1F,
    0x15,
    0xC4,
    0x89,
    0x00,
    0x00,
    0x00,
    0x0D,
    0x49,
    0x44,
    0x41,
    0x54,
    0x78,
    0x9C,
    0x63,
    0xF8,
    0xCF,
    0xC0,
    0xF0,
    0x1F,
    0x00,
    0x05,
    0x00,
    0x01,
    0xFF,
    0x89,
    0x99,
    0x3D,
    0x1D,
    0x00,
    0x00,
    0x00,
    0x00,
    0x49,
    0x45,
    0x4E,
    0x44,
    0xAE,
    0x42,
    0x60,
    0x82,
  ]);

  setUp(() async {
    db = AppDatabase.enMemoire();
    dossier = await Directory.systemTemp.createTemp('tatacora_apparence_');
  });

  tearDown(() async {
    await db.close();
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  ApparencePoste couche() => ApparencePoste(() async => dossier);

  group('ApparencePoste — le fichier, remplacé et jamais accumulé', () {
    test('un logo s’enregistre, se relit, et le suivant REMPLACE le premier '
        '(même d’une autre extension)', () async {
      final a = couche();
      expect(await a.lire(UsageApparence.logo), isNull);

      await a.enregistrer(
        UsageApparence.logo,
        FichierLu(nom: 'mon.PNG', octets: png),
      );
      expect(await a.lire(UsageApparence.logo), png);

      await a.enregistrer(
        UsageApparence.logo,
        FichierLu(nom: 'autre.jpg', octets: Uint8List.fromList([1, 2, 3])),
      );
      expect(await a.lire(UsageApparence.logo), [1, 2, 3]);
      expect(dossier.listSync().map((f) => f.uri.pathSegments.last).toList(), [
        'logo.jpg',
      ], reason: 'un seul fichier par usage : logo.png est supprimé');
    });

    test('extension, vide et taille sont refusés SANS rien écrire', () async {
      final a = couche();
      await expectLater(
        a.enregistrer(
          UsageApparence.logo,
          FichierLu(nom: 'logo.gif', octets: png),
        ),
        throwsA(
          isA<RefusApparence>().having(
            (r) => r.message,
            'message',
            TextesRefusApparence.format(UsageApparence.logo),
          ),
        ),
      );
      await expectLater(
        a.enregistrer(
          UsageApparence.logo,
          FichierLu(nom: 'logo.png', octets: Uint8List(0)),
        ),
        throwsA(isA<RefusApparence>()),
      );
      await expectLater(
        a.enregistrer(
          UsageApparence.favicon,
          FichierLu(nom: 'f.ico', octets: Uint8List(512 * 1024 + 1)),
        ),
        throwsA(
          isA<RefusApparence>().having(
            (r) => r.message,
            'message',
            TextesRefusApparence.taille(UsageApparence.favicon),
          ),
        ),
      );
      // Le favicon admet .ico, le logo non.
      await a.enregistrer(
        UsageApparence.favicon,
        FichierLu(nom: 'f.ico', octets: png),
      );
      await expectLater(
        a.enregistrer(
          UsageApparence.logo,
          FichierLu(nom: 'l.ico', octets: png),
        ),
        throwsA(isA<RefusApparence>()),
      );
      expect(dossier.listSync().length, 1, reason: 'seul le favicon valide');
    });
  });

  group('L’onglet', () {
    Future<void> monter(
      WidgetTester tester, {
      String niveau = 'C',
      SelecteurEssai? selecteur,
    }) async {
      tester.view
        ..physicalSize = const Size(1600, 1400)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final droits = GardeAcces({'PARAM': niveau});
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            baseLocaleProvider.overrideWithValue(db),
            droitsProvider.overrideWithValue(droits),
            dossierApparenceProvider.overrideWithValue(() async => dossier),
            if (selecteur != null)
              selecteurFichiersProvider.overrideWithValue(selecteur),
            sessionProvider.overrideWithBuild(
              (ref, n) => Session(
                utilisateurId: 'u-essai',
                login: 'essai',
                nom: 'Essai',
                role: 'administrateur',
                droits: droits,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.clair,
            home: const Scaffold(body: EcranParametres()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('param-onglet-apparence')));
      await tester.pumpAndSettle();
    }

    testWidgets('il rend les mots de la vue, plus la note « sans source »', (
      tester,
    ) async {
      await monter(tester);

      expect(find.text("Logo de l'entreprise"), findsOneWidget);
      expect(find.text('Changer le logo'), findsOneWidget);
      expect(
        find.text('Format carré recommandé, fond transparent de préférence.'),
        findsOneWidget,
      );
      expect(find.text("Favicon (icône d'onglet navigateur)"), findsOneWidget);
      expect(find.text('Changer le favicon'), findsOneWidget);
      expect(
        find.text(
          'Couleurs de la charte graphique (lecture seule — chap. 9.3.1 du '
          'CdCF)',
        ),
        findsOneWidget,
      );
      for (final nom in ['Navy', 'Gold', 'Succès', 'Alerte', 'Erreur']) {
        expect(find.text(nom), findsOneWidget, reason: nom);
      }
      expect(find.byKey(const Key('param-onglet-sans-source')), findsNothing);
    });

    testWidgets('en lecture seule, aucun bouton de changement', (tester) async {
      await monter(tester, niveau: 'L');
      expect(find.byKey(const Key('apparence-logo-changer')), findsNothing);
      expect(find.byKey(const Key('apparence-favicon-changer')), findsNothing);
      expect(find.text("Logo de l'entreprise"), findsOneWidget);
    });

    testWidgets('changer le logo : le fichier est copié, le toast de la vue '
        'est dit, l’aperçu le relit', (tester) async {
      final selecteur = SelecteurEssai(
        lu: FichierLu(nom: 'nouveau.png', octets: png),
      );
      await monter(tester, selecteur: selecteur);

      await tester.tap(find.byKey(const Key('apparence-logo-changer')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-apparence')), findsOneWidget);
      expect(
        find.text('Sélectionnez un fichier PNG/JPG (recommandé 512×512px).'),
        findsOneWidget,
      );

      // Enregistrer sans fichier : dit, rien d'écrit.
      await tester.tap(find.byKey(const Key('modale-apparence-valider')));
      await tester.pumpAndSettle();
      expect(find.text('Choisissez d’abord un fichier.'), findsOneWidget);
      expect(dossier.listSync(), isEmpty);

      await tester.tap(find.byKey(const Key('modale-apparence-choisir')));
      await tester.pumpAndSettle();
      expect(find.text('nouveau.png'), findsOneWidget);
      await tester.tap(find.byKey(const Key('modale-apparence-valider')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-apparence')), findsNothing);
      expect(
        find.text("Logo remplacé — l'ancien fichier n'est pas conservé."),
        findsOneWidget,
      );
      expect(File('${dossier.path}/logo.png').readAsBytesSync(), png);
    });

    testWidgets('un fichier refusé reste dans la modale avec sa phrase', (
      tester,
    ) async {
      final selecteur = SelecteurEssai(
        lu: FichierLu(nom: 'photo.gif', octets: png),
      );
      await monter(tester, selecteur: selecteur);

      await tester.tap(find.byKey(const Key('apparence-favicon-changer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-apparence-choisir')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modale-apparence-valider')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('modale-apparence')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('modale-apparence-refus')),
          matching: find.text(
            TextesRefusApparence.format(UsageApparence.favicon),
          ),
        ),
        findsOneWidget,
      );
      expect(dossier.listSync(), isEmpty);
    });
  });
}
