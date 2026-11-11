import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/theme/app_theme.dart';
import 'package:tatacora_flutter/core/theme/mesures_verrou_session.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/data/stockage_activite_verrou.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/auth/domain/verrou_session.dart';
import 'package:tatacora_flutter/features/auth/presentation/providers_verrou.dart';
import 'package:tatacora_flutter/features/auth/presentation/voile_verrou_session.dart';

/// Le VOILE de verrouillage : minuteur d'inactivité, activité, déverrouillage,
/// et ce que « suspendue, pas fermée » veut dire pour la page dessous.
///
/// L'horloge, le coffre et la vérification du mot de passe sont injectés : le
/// test avance le temps de quinze minutes sans les attendre.
void main() {
  late DateTime maintenant;
  late _StockageFaux stockage;
  final conteneursOuverts = <ProviderContainer>[];

  /// Un cas de widget qui DÉMONTE l'arbre puis libère les providers avant la
  /// vérification des minuteurs du banc : le minuteur d'inactivité du verrou
  /// (périodique) s'arrête à la libération du notifier, et le banc refuse tout
  /// minuteur survivant.
  void cas(String nom, Future<void> Function(WidgetTester) corps) {
    testWidgets(nom, (tester) async {
      try {
        await corps(tester);
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final c in conteneursOuverts) {
          c.dispose();
        }
        conteneursOuverts.clear();
      }
    });
  }

  const session = Session(
    utilisateurId: 'u-1',
    login: 'jkora',
    nom: 'Jean Kora',
    role: 'gerant',
    droits: GardeAcces.deconnecte(),
  );

  setUp(() {
    maintenant = DateTime(2026, 10, 27, 10);
    stockage = _StockageFaux();
  });

  /// La page dessous : un champ à moitié rempli, un compteur, une modale.
  Future<ProviderContainer> monter(
    WidgetTester tester, {
    Session? ouverte = session,
    List<Override> enPlus = const [],
  }) async {
    final conteneur = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild((ref, notifier) => ouverte),
        horlogeVerrouProvider.overrideWithValue(() => maintenant),
        stockageActiviteVerrouProvider.overrideWithValue(stockage),
        deverrouillageSessionProvider.overrideWithValue(
          DeverrouillageSession(
            verifier: (login, mdp) async => mdp == 'secret',
            limiteur: LimiteurTentatives(horloge: () => maintenant),
          ),
        ),
        ...enPlus,
      ],
    );
    conteneursOuverts.add(conteneur);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: conteneur,
        child: MaterialApp(
          theme: AppTheme.clair,
          builder: (context, child) =>
              VoileVerrouSession(child: child ?? const SizedBox.shrink()),
          home: const _PageDessous(),
        ),
      ),
    );
    // Le tour de la lecture du coffre (microtâche) : le verrou est « prêt ».
    await tester.pump();
    await tester.pump();
    return conteneur;
  }

  /// Le temps passe, puis le contrôle de 5 secondes de la vue a lieu.
  Future<void> laisserPasser(WidgetTester tester, Duration duree) async {
    maintenant = maintenant.add(duree);
    await tester.pump(controleVerrou);
    await tester.pump();
  }

  Finder voile() => find.byKey(const Key('verrou-voile'));

  Future<void> saisirEtValider(WidgetTester tester, String mdp) async {
    await tester.enterText(find.byKey(const Key('verrou-mot-de-passe')), mdp);
    await tester.tap(find.byKey(const Key('verrou-deverrouiller')));
    await tester.pump();
    await tester.pump();
  }

  group('Le minuteur d’inactivité', () {
    cas('le voile se pose à 15 minutes, pas avant', (tester) async {
      await monter(tester);
      expect(voile(), findsNothing);

      await laisserPasser(tester, const Duration(minutes: 14, seconds: 55));
      expect(voile(), findsNothing, reason: '14 min 55 s + un tour de 5 s');

      await laisserPasser(tester, const Duration(seconds: 6));
      expect(voile(), findsOneWidget);
    });

    cas('une activité (survol de la souris) repousse l’échéance', (
      tester,
    ) async {
      await monter(tester);
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);

      await laisserPasser(tester, const Duration(minutes: 10));
      await souris.moveTo(const Offset(40, 40));
      await laisserPasser(tester, const Duration(minutes: 10));
      expect(
        voile(),
        findsNothing,
        reason: '10 min depuis la dernière activité',
      );

      await laisserPasser(tester, const Duration(minutes: 6));
      expect(voile(), findsOneWidget);
    });

    cas('une touche du clavier est une activité', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 10));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await laisserPasser(tester, const Duration(minutes: 10));
      expect(voile(), findsNothing);
    });

    cas('un appui est une activité', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 10));
      await tester.tapAt(const Offset(5, 5));
      await laisserPasser(tester, const Duration(minutes: 10));
      expect(voile(), findsNothing, reason: 'l’appui repousse');

      await laisserPasser(tester, const Duration(minutes: 6));
      expect(voile(), findsOneWidget);
    });

    cas('la molette est une activité', (tester) async {
      await monter(tester);
      final souris = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(souris.hover(const Offset(30, 30)));

      await laisserPasser(tester, const Duration(minutes: 10));
      await tester.sendEventToBinding(souris.scroll(const Offset(0, 40)));
      await laisserPasser(tester, const Duration(minutes: 10));
      expect(
        voile(),
        findsNothing,
        reason: '20 min après le survol, mais 10 min après la molette',
      );

      await laisserPasser(tester, const Duration(minutes: 6));
      expect(voile(), findsOneWidget);
    });

    cas('sans session, aucun voile — même après des heures', (tester) async {
      await monter(tester, ouverte: null);
      await laisserPasser(tester, const Duration(hours: 3));
      expect(voile(), findsNothing);
    });
  });

  group('Suspendue, pas fermée', () {
    cas('la page dessous garde sa saisie ET ne reçoit rien tant que le '
        'voile est posé', (tester) async {
      await monter(tester);
      await tester.enterText(
        find.byKey(const Key('page-champ')),
        'saisie en cours',
      );
      await tester.tap(find.byKey(const Key('page-bouton')));
      await tester.pump();
      expect(find.text('clics : 1'), findsOneWidget);

      await laisserPasser(tester, const Duration(minutes: 16));
      expect(voile(), findsOneWidget);

      // Un clic sur le bouton de la page, DESSOUS le voile, n'arrive pas.
      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('page-bouton'))),
      );
      await tester.pump();
      expect(find.text('clics : 1'), findsOneWidget);

      // Le bon mot de passe lève le voile : la saisie est intacte.
      await saisirEtValider(tester, 'secret');
      expect(voile(), findsNothing);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('page-champ')))
            .controller!
            .text,
        'saisie en cours',
      );
      expect(find.text('clics : 1'), findsOneWidget);
    });

    cas('il couvre aussi une MODALE ouverte', (tester) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('page-ouvrir-modale')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modale-bouton')), findsOneWidget);

      await laisserPasser(tester, const Duration(minutes: 16));
      expect(voile(), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(
          find.byKey(const Key('modale-bouton')),
          warnIfMissed: false,
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('modale-bouton')), findsOneWidget);

      await saisirEtValider(tester, 'secret');
      expect(voile(), findsNothing);
      expect(find.byKey(const Key('modale-bouton')), findsOneWidget);
    });

    cas('Échap ne lève pas le voile', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(voile(), findsOneWidget);
    });

    cas('la frappe va au champ du voile, jamais à la page dessous', (
      tester,
    ) async {
      await monter(tester);
      await tester.tap(find.byKey(const Key('page-champ')));
      await tester.pump();
      await laisserPasser(tester, const Duration(minutes: 16));
      await tester.pump();

      // Le clavier est LIVRÉ au client de saisie qui a le focus : c'est celui
      // du voile, pas le champ de la page où l'on tapait.
      tester.testTextInput.enterText('abc');
      await tester.pump();

      expect(
        tester
            .widget<TextField>(find.byKey(const Key('verrou-mot-de-passe')))
            .controller!
            .text,
        'abc',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('page-champ')))
            .controller!
            .text,
        isEmpty,
      );
    });
  });

  group('Le déverrouillage', () {
    cas('un mot de passe faux : la phrase du serveur, le champ est '
        'vidé, le voile reste', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));

      await saisirEtValider(tester, 'faux');

      expect(find.text(TextesVerrou.erreur), findsOneWidget);
      expect(voile(), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('verrou-mot-de-passe')))
            .controller!
            .text,
        isEmpty,
        reason: 'le mot de passe ne reste pas après l’essai',
      );
    });

    cas('cinq échecs : le sixième essai est refusé même avec le BON '
        'mot de passe', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));

      for (var i = 0; i < 5; i++) {
        await saisirEtValider(tester, 'faux');
        expect(
          find.text(TextesVerrou.erreur),
          findsOneWidget,
          reason: 'essai ${i + 1}',
        );
      }
      await saisirEtValider(tester, 'secret');

      expect(voile(), findsOneWidget);
      expect(find.text(TextesVerrou.tropDeTentatives(60)), findsOneWidget);

      // La fenêtre de 60 secondes close, l’essai repasse.
      maintenant = maintenant.add(const Duration(seconds: 61));
      await saisirEtValider(tester, 'secret');
      expect(voile(), findsNothing);
    });

    cas('après le déverrouillage, l’inactivité repart de zéro', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));
      await saisirEtValider(tester, 'secret');
      expect(voile(), findsNothing);

      await laisserPasser(tester, const Duration(minutes: 10));
      expect(voile(), findsNothing);
      await laisserPasser(tester, const Duration(minutes: 6));
      expect(voile(), findsOneWidget);
    });

    cas('l’œil montre puis masque le mot de passe', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));

      bool masque() => tester
          .widget<TextField>(find.byKey(const Key('verrou-mot-de-passe')))
          .obscureText;
      expect(masque(), isTrue);
      await tester.tap(find.byKey(const Key('verrou-oeil')));
      await tester.pump();
      expect(masque(), isFalse);
      await tester.tap(find.byKey(const Key('verrou-oeil')));
      await tester.pump();
      expect(masque(), isTrue);
    });

    cas('le voile dit les mots de la vue', (tester) async {
      await monter(tester);
      await laisserPasser(tester, const Duration(minutes: 16));

      expect(find.text('Session verrouillée'), findsOneWidget);
      expect(
        find.text('Votre session est suspendue, pas fermée.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Ressaisissez votre mot de passe pour reprendre exactement où vous '
          'en étiez.',
        ),
        findsOneWidget,
      );
      expect(find.text('Mot de passe'), findsOneWidget);
      expect(find.text('Déverrouiller'), findsOneWidget);
    });
  });

  group('Le verrou tient à travers un redémarrage (le F5 de la vue)', () {
    cas('une dernière activité vieille de 20 minutes : le voile est '
        'posé dès l’ouverture, sans attendre un tour de minuteur', (
      tester,
    ) async {
      stockage.valeur = maintenant.subtract(const Duration(minutes: 20));
      await monter(tester);
      expect(voile(), findsOneWidget);
    });

    cas('une activité vieille de 5 minutes : pas de voile', (tester) async {
      stockage.valeur = maintenant.subtract(const Duration(minutes: 5));
      await monter(tester);
      expect(voile(), findsNothing);
    });

    cas('aucun horodatage : jamais verrouillé', (tester) async {
      await monter(tester);
      expect(voile(), findsNothing);
    });

    cas('la souris qui bouge au redémarrage NE contourne PAS le '
        'verrou (l’inactivité est jugée avant d’enregistrer l’activité)', (
      tester,
    ) async {
      stockage.valeur = maintenant.subtract(const Duration(minutes: 20));
      await monter(tester);
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      await souris.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(voile(), findsOneWidget);
    });

    cas('une activité qui précède la lecture du coffre NE la fausse PAS (la '
        'première activité est enregistrée APRÈS le jugement)', (tester) async {
      stockage.valeur = maintenant.subtract(const Duration(minutes: 20));
      final lecture = Completer<void>();
      stockage.attente = lecture.future;
      await monter(tester);
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      await souris.moveTo(const Offset(50, 50));
      await tester.pump();
      expect(voile(), findsNothing, reason: 'le coffre n’a pas encore répondu');

      lecture.complete();
      await tester.pump();
      await tester.pump();
      expect(
        voile(),
        findsOneWidget,
        reason: 'l’horodatage rangé date de 20 min',
      );
    });

    cas('l’horodatage est rangé, mais pas à chaque mouvement (20 s)', (
      tester,
    ) async {
      await monter(tester);
      final avant = stockage.ecritures;
      final souris = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await souris.addPointer(location: Offset.zero);
      addTearDown(souris.removePointer);
      for (var i = 1; i <= 10; i++) {
        await souris.moveTo(Offset(i * 3.0, i * 3.0));
      }
      expect(stockage.ecritures, avant, reason: 'dans la même fenêtre de 20 s');

      maintenant = maintenant.add(const Duration(seconds: 21));
      await souris.moveTo(const Offset(100, 100));
      expect(stockage.ecritures, avant + 1);
      expect(stockage.valeur, maintenant);
    });

    cas('un verrou périmé n’enferme pas une CONNEXION toute fraîche', (
      tester,
    ) async {
      stockage.valeur = maintenant.subtract(const Duration(hours: 5));
      final conteneur = await monter(tester, ouverte: null);
      // Le mot de passe de connexion se tape : c’est une activité.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      conteneur.read(sessionProvider.notifier).state = session;
      await tester.pump();
      expect(voile(), findsNothing);
    });
  });

  group('Un coffre illisible ne bloque jamais', () {
    test('le coffre du poste : lecture et écriture ne lèvent pas', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final coffre = StockageActiviteCoffre();
      expect(await coffre.lire(), isNull);
      final instant = DateTime(2026, 10, 27, 9, 30);
      await coffre.ecrire(instant);
      expect(await coffre.lire(), instant);
    });
  });

  group('Les mesures et tracés sont ceux de la vue', () {
    final blade = File(
      '../tatacora-api/resources/views/pwa/livewire/verrou-session.blade.php',
    );

    test('la vue est lue (jamais verte à vide)', () {
      expect(blade.existsSync(), isTrue);
      expect(blade.readAsStringSync(), contains('max-w-[380px]'));
    });

    test('chaque tracé d’icône figure tel quel dans la vue', () {
      final texte = blade.readAsStringSync();
      for (final d in [
        'M7 11V7a5 5 0 0110 0v4',
        'M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z',
        'M17.94 17.94A10.94 10.94 0 0112 20c-7 0-11-8-11-8a21.62 21.62 0 015.06-6.94M9.9 4.24A10.94 10.94 0 0112 4c7 0 11 8 11 8a21.6 21.6 0 01-2.66 3.94M14.12 14.12a3 3 0 11-4.24-4.24',
        'M1 1l22 22',
      ]) {
        expect(texte, contains('d="$d"'), reason: d);
        expect(
          MesuresVerrouSession.traceCadenas +
              MesuresVerrouSession.traceOeilOuvert +
              MesuresVerrouSession.traceOeilBarre,
          contains('d="$d"'),
          reason: 'le tracé du poste est celui de la vue',
        );
      }
      expect(
        texte,
        contains('<rect x="3" y="11" width="18" height="11" rx="2"/>'),
      );
      expect(texte, contains('<circle cx="12" cy="12" r="3"/>'));
    });

    test('le voile : couleur, flou et largeur de la vue', () {
      final texte = blade.readAsStringSync();
      expect(texte, contains('rgba(15,23,42,0.72)'));
      expect(texte, contains('blur(2px)'));
      expect(MesuresVerrouSession.voile, const Color(0xB80F172A));
      expect(MesuresVerrouSession.flou, 2);
      expect(MesuresVerrouSession.largeurCarte, 380);
      expect(MesuresVerrouSession.disqueIcone, 56); // w-14 h-14
      expect(texte, contains('w-14 h-14'));
    });
  });

  group('Le voile est MONTÉ par les deux points d’entrée', () {
    for (final fichier in ['lib/main.dart', 'lib/main_demo.dart']) {
      test(
        '$fichier pose VoileVerrouSession dans le builder de l’application',
        () {
          final source = File(fichier).readAsStringSync();
          expect(source, contains('builder: (context, child)'));
          expect(source, contains('VoileVerrouSession('));
        },
      );
    }
  });

  group('Vérifier un mot de passe n’ouvre aucune session', () {
    test('verifierMotDePasse : vrai pour le bon, faux pour le reste, le coffre '
        'est intact', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final base = AppDatabase.enMemoire();
      addTearDown(base.close);
      final depot = SessionRepositoryLocal(base);
      await depot.creerCompte(
        login: 'jkora',
        nom: 'Jean Kora',
        motDePasse: 'motdepasse123',
        role: 'gerant',
        droits: const {'M1': 'C'},
      );

      expect(await depot.verifierMotDePasse('jkora', 'motdepasse123'), isTrue);
      expect(await depot.verifierMotDePasse('JKora ', 'motdepasse123'), isTrue);
      expect(await depot.verifierMotDePasse('jkora', 'autre'), isFalse);
      expect(
        await depot.verifierMotDePasse('inconnu', 'motdepasse123'),
        isFalse,
      );
      // Aucune session n’a été mémorisée.
      expect(await depot.sessionCourante(), isNull);
    });
  });
}

/// Le coffre de l’horodatage, en mémoire, qui compte ses écritures.
class _StockageFaux implements StockageActiviteVerrou {
  DateTime? valeur;
  int ecritures = 0;

  /// Si posée, la lecture attend cette promesse avant de rendre la valeur COURANTE
  /// (celle que d'éventuelles écritures ont pu changer entre-temps).
  Future<void>? attente;

  @override
  Future<DateTime?> lire() async {
    await attente;
    return valeur;
  }

  @override
  Future<void> ecrire(DateTime instant) async {
    ecritures++;
    valeur = instant;
  }
}

/// Une page d’application : un champ à moitié rempli, un compteur, une modale.
class _PageDessous extends StatefulWidget {
  const _PageDessous();

  @override
  State<_PageDessous> createState() => _EtatPage();
}

class _EtatPage extends State<_PageDessous> {
  final _champ = TextEditingController();
  int _clics = 0;

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextField(key: const Key('page-champ'), controller: _champ),
          ElevatedButton(
            key: const Key('page-bouton'),
            onPressed: () => setState(() => _clics++),
            child: Text('clics : $_clics'),
          ),
          ElevatedButton(
            key: const Key('page-ouvrir-modale'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (c) => AlertDialog(
                content: ElevatedButton(
                  key: const Key('modale-bouton'),
                  onPressed: () => Navigator.of(c).pop(),
                  child: const Text('modale validée'),
                ),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ],
      ),
    );
  }
}
