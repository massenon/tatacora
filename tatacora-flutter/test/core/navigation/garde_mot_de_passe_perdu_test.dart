@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:tatacora_flutter/core/di/providers.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/router/app_router.dart';
import 'package:tatacora_flutter/features/auth/domain/mot_de_passe_perdu.dart';
import 'package:tatacora_flutter/features/auth/domain/session.dart';
import 'package:tatacora_flutter/features/transverse/domain/roles_du_poste.dart';

/// La GARDE DU ROUTEUR pour un compte dont le mot de passe vient d'être
/// réinitialisé par un administrateur (PO, 29/10/2026, option A) : « tant que ce
/// n'est pas fait, aucun accès aux modules ». Éprouvée sur le VRAI `redirect` du
/// routeur (`routeurProvider`), comme `garde_routes_test.dart`.
///
/// ## Ancrages extérieurs (piège 12)
///
/// Les chemins servis sont relus dans le CODE SOURCE du routeur : une route
/// ajoutée demain entre d'elle-même dans le balayage et doit, elle aussi,
/// renvoyer vers « Définissez votre nouveau mot de passe ».
void main() {
  const repli = '/tableau-de-bord';
  const change = routeChangementMotDePasse;
  const recours = routeMotDePasseAdministrateurPerdu;

  List<String> cheminsServis() {
    final source = File('lib/core/router/app_router.dart').readAsStringSync();
    final chemins = <String>[];
    String? parent;
    for (final m in RegExp(r"path: '([^']+)'").allMatches(source)) {
      final p = m.group(1)!;
      if (p.startsWith('/')) {
        parent = p;
        chemins.add(p);
      } else {
        chemins.add('$parent/$p');
      }
    }
    return chemins;
  }

  final codes = socleRbacCdcf['super_admin']!.keys.toList();
  Map<String, String> tout(String niveau) => {for (final c in codes) c: niveau};

  Session session({required bool changement, String role = 'administrateur'}) =>
      Session(
        utilisateurId: 'u',
        login: 'u',
        nom: 'u',
        role: role,
        droits: GardeAcces.depuisJson(tout('C')),
        changementObligatoire: changement,
      );

  late ProviderContainer conteneur;
  late GoRouter routeur;
  Session? courante;

  void connecter(Session? s) {
    courante = s;
    conteneur.invalidate(sessionProvider);
  }

  setUp(() {
    courante = null;
    conteneur = ProviderContainer(
      overrides: [
        sessionProvider.overrideWithBuild((ref, notifier) => courante),
      ],
    );
    routeur = conteneur.read(routeurProvider);
  });
  tearDown(() {
    routeur.dispose();
    conteneur.dispose();
  });

  Future<BuildContext> monterMessager(WidgetTester tester) async {
    late BuildContext contexte;
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messagerApplication,
        home: Scaffold(
          body: Builder(
            builder: (c) {
              contexte = c;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    return contexte;
  }

  Future<String?> rediriger(BuildContext contexte, String chemin) async {
    final etat = GoRouterState(
      routeur.configuration,
      uri: Uri.parse(chemin),
      matchedLocation: chemin,
      fullPath: chemin,
      pathParameters: const {},
      pageKey: ValueKey<String>(chemin),
    );
    return routeur.configuration.topRedirect(contexte, etat);
  }

  test('le balayage du routeur n’est pas vide et nomme les deux écrans '
      'du mot de passe perdu', () {
    final chemins = cheminsServis();
    expect(chemins.length, greaterThanOrEqualTo(30));
    expect(chemins, containsAll([change, recours, '/connexion']));
    // Les constantes de la garde sont celles du routeur.
    expect(change, '/changement-mot-de-passe');
    expect(recours, '/mot-de-passe-administrateur-perdu');
  });

  testWidgets('un compte « changement obligatoire » n’accède à AUCUN module : '
      'tout chemin servi renvoie vers l’écran de changement', (tester) async {
    final contexte = await monterMessager(tester);
    // Même un super administrateur, même avec TOUS les droits.
    for (final role in ['administrateur', 'super_admin', 'receptionniste']) {
      connecter(session(changement: true, role: role));
      var verifies = 0;
      for (final chemin in cheminsServis()) {
        if (chemin == '/demarrage') continue; // l'aiguillage s'en charge
        final cible = await rediriger(contexte, chemin);
        if (chemin == change) {
          expect(
            cible,
            isNull,
            reason: '$role : l’écran de changement s’ouvre',
          );
        } else {
          expect(cible, change, reason: '$role $chemin');
        }
        verifies++;
      }
      expect(verifies, greaterThan(30), reason: 'balayage non vide');
      // Un chemin inconnu n'y échappe pas non plus.
      expect(await rediriger(contexte, '/nulle-part'), change);
    }
  });

  testWidgets('le démarrage s’affiche toujours (il aiguille ensuite vers '
      'l’écran de changement)', (tester) async {
    final contexte = await monterMessager(tester);
    connecter(session(changement: true));
    expect(await rediriger(contexte, '/demarrage'), isNull);
  });

  testWidgets('sans changement exigé, l’écran de changement n’a pas d’objet : '
      'retour au tableau de bord', (tester) async {
    final contexte = await monterMessager(tester);
    connecter(session(changement: false));
    expect(await rediriger(contexte, change), repli);
    expect(await rediriger(contexte, recours), repli);
    expect(await rediriger(contexte, '/stocks'), isNull);
  });

  testWidgets('sans session : le recours du dernier administrateur est '
      'ouvert, l’écran de changement non', (tester) async {
    final contexte = await monterMessager(tester);
    connecter(null);
    expect(await rediriger(contexte, recours), isNull);
    expect(await rediriger(contexte, change), '/connexion');
    expect(await rediriger(contexte, '/stocks'), '/connexion');
    expect(await rediriger(contexte, '/connexion'), isNull);
  });

  testWidgets('la levée du blocage rouvre les modules (la garde relit la '
      'session)', (tester) async {
    final contexte = await monterMessager(tester);
    connecter(session(changement: true));
    expect(await rediriger(contexte, '/stocks'), change);
    connecter(session(changement: false));
    expect(await rediriger(contexte, '/stocks'), isNull);
  });
}
