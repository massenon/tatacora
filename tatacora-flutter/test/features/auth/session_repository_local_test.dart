import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/auth/data/session_repository_local.dart';
import 'package:tatacora_flutter/features/auth/domain/session_repository.dart';

/// L'authentification **locale** — décision du Product Owner, 21/08/2026.
///
/// *« Je veux une connexion avec les RBAC et accès sans l'API de Laravel, un
/// login sans synchronisation avec Laravel ; on peut faire la synchronisation
/// des modules du système comme ventes, POS, rapports, et non la
/// synchronisation du login. »*
///
/// ## Le premier groupe est le plus important
///
/// Il ne vérifie pas un comportement mais une **absence** : que le fichier ne
/// puisse pas appeler le serveur. Une garantie de ce genre ne se tient pas par
/// un commentaire — elle se tient par une vérification qui échoue le jour où
/// quelqu'un ajoute un import de bonne foi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase base;
  late SessionRepositoryLocal depot;

  const droitsReceptionniste = {
    'M1': 'C',
    'M2': 'L',
    'M3': 'C',
    'M4': '-',
    'M5': '-',
    'M6': 'L',
    'M7': '-',
    'M8': '-',
    'M9': '-',
    'M10': '-',
    'M11': 'L',
    'M12': '-',
    'M13': '-',
    'M14': '-',
    'ROLES': '-',
    'PARAM': '-',
  };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    base = AppDatabase.enMemoire();
    depot = SessionRepositoryLocal(base);
  });

  tearDown(() => base.close());

  Future<void> poserCompte({
    String login = 'jkora',
    String motDePasse = 'motdepasse123',
  }) => depot.creerCompte(
    login: login,
    nom: 'KORA Jean',
    motDePasse: motDePasse,
    role: 'receptionniste',
    droits: droitsReceptionniste,
  );

  group('AUCUN appel réseau — la garantie structurelle', () {
    test('le fichier n’importe ni dio ni http', () {
      // La preuve la plus solide qu'on puisse écrire ici : le code source
      // lui-même. Un dépôt qui n'a pas de client HTTP ne peut pas appeler le
      // serveur — ni maintenant, ni par une modification distraite plus tard.
      final source = File(
        'lib/features/auth/data/session_repository_local.dart',
      ).readAsStringSync();

      for (final interdit in const [
        'package:dio/',
        'package:http/',
        'HttpClient',
        'localhost',
        '/api/',
      ]) {
        expect(
          source,
          isNot(contains(interdit)),
          reason:
              'l’authentification locale ne doit RIEN savoir du réseau : '
              '« $interdit » y figure',
        );
      }
    });
  });

  group('Connexion locale', () {
    test('un compte créé peut se connecter, sans aucun serveur', () async {
      await poserCompte();
      final session = await depot.connecter('jkora', 'motdepasse123');

      expect(session.login, 'jkora');
      expect(session.nom, 'KORA Jean');
      expect(session.role, 'receptionniste');
    });

    test('les droits RBAC viennent du référentiel local', () async {
      await poserCompte();
      final session = await depot.connecter('jkora', 'motdepasse123');

      expect(
        session.droits.niveau(ModuleTatacora.m1Hebergement).peutEcrire,
        isTrue,
      );
      expect(session.droits.peutLire(ModuleTatacora.m2Facturation), isTrue);
      expect(
        session.droits.niveau(ModuleTatacora.m2Facturation).peutEcrire,
        isFalse,
      );
      expect(session.droits.peutLire(ModuleTatacora.m13Rh), isFalse);
      expect(session.droits.peutLire(ModuleTatacora.roles), isFalse);
    });

    test('l’identifiant est insensible à la casse et aux espaces', () async {
      await poserCompte();
      // « N.Kora » et « jkora » désignent la même personne ; deux lignes pour
      // un seul employé donneraient deux jeux de droits qui divergeraient.
      final session = await depot.connecter('  JKORA  ', 'motdepasse123');
      expect(session.login, 'jkora');
    });
  });

  group('Refus — un seul message, toujours le même', () {
    test('mot de passe faux', () async {
      await poserCompte();
      await expectLater(
        depot.connecter('jkora', 'mauvais'),
        throwsA(
          isA<EchecConnexion>().having(
            (e) => e.message,
            'message',
            SessionRepositoryLocal.refusIdentifiants,
          ),
        ),
      );
    });

    test('compte inconnu — MÊME message que le mot de passe faux', () async {
      await poserCompte();
      // Les distinguer dirait à un attaquant quels identifiants existent : il
      // lui suffirait d'essayer des logins jusqu'à ce que le message change.
      await expectLater(
        depot.connecter('inconnu', 'motdepasse123'),
        throwsA(
          isA<EchecConnexion>().having(
            (e) => e.message,
            'message',
            SessionRepositoryLocal.refusIdentifiants,
          ),
        ),
      );
    });

    test('AUCUN message ne peut venir d’un serveur', () async {
      await poserCompte();
      try {
        await depot.connecter('jkora', 'mauvais');
        fail('la connexion aurait dû être refusée');
      } on EchecConnexion catch (e) {
        // Le défaut signalé par le Product Owner : « The route api/v1/login
        // could not be found » s'affichait au comptoir. Cette phrase nomme le
        // préfixe d'API, la version, et révèle qu'aucun contrôle
        // d'identifiants n'a même été tenté.
        for (final fuite in const ['route', 'api/', 'v1', 'http', '404']) {
          expect(
            e.message.toLowerCase(),
            isNot(contains(fuite)),
            reason: 'le message de refus laisse fuir « $fuite »',
          );
        }
      }
    });
  });

  group('Poste vierge', () {
    test('aucun compte n’existe au départ', () async {
      expect(await depot.aucunCompteExiste(), isTrue);
    });

    test('un compte créé le fait basculer', () async {
      await poserCompte();
      expect(await depot.aucunCompteExiste(), isFalse);
    });

    test('sur un poste vierge, toute connexion est refusée', () async {
      // Et avec le message standard : un poste vierge ne dit pas non plus
      // qu'il est vierge à qui tente sa chance.
      await expectLater(
        depot.connecter('admin', 'motdepasse123'),
        throwsA(isA<EchecConnexion>()),
      );
    });
  });

  group('Création de compte', () {
    test('un mot de passe trop court est refusé', () async {
      await expectLater(
        depot.creerCompte(
          login: 'x',
          nom: 'X',
          motDePasse: '1234567',
          role: 'administrateur',
          droits: droitsReceptionniste,
        ),
        throwsA(isA<EchecConnexion>()),
      );
      expect(await depot.aucunCompteExiste(), isTrue);
    });

    test('le mot de passe n’est écrit NULLE PART en base', () async {
      const secret = 'Motdepasse-tres-reconnaissable-2026';
      await poserCompte(motDePasse: secret);

      // On relit la ligne entière : rien ne doit y ressembler au secret.
      final lignes = await base
          .customSelect('SELECT * FROM utilisateurs_local')
          .get();
      for (final ligne in lignes) {
        for (final valeur in ligne.data.values) {
          expect('$valeur', isNot(contains(secret)));
        }
      }
    });
  });

  group('Session courante', () {
    test('elle survit à une nouvelle instance du dépôt', () async {
      await poserCompte();
      await depot.connecter('jkora', 'motdepasse123');

      final autre = SessionRepositoryLocal(base);
      final session = await autre.sessionCourante();
      expect(session?.login, 'jkora');
    });

    test('elle est relue depuis la base, pas restaurée figée', () async {
      await poserCompte();
      await depot.connecter('jkora', 'motdepasse123');

      // Le compte est désactivé après coup. Une session restaurée depuis un
      // profil figé rouvrirait avec ses anciens droits ; ici on relit la
      // ligne, donc le refus est immédiat.
      await base.customStatement(
        "UPDATE utilisateurs_local SET actif = 0 WHERE login = 'jkora'",
      );
      expect(await depot.sessionCourante(), isNull);
    });

    test('la déconnexion efface la session', () async {
      await poserCompte();
      await depot.connecter('jkora', 'motdepasse123');
      await depot.deconnecter();
      expect(await depot.sessionCourante(), isNull);
    });
  });
}
