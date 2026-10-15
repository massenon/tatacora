import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tatacora_flutter/features/synchronisation/data/service_appairage.dart';
import 'package:tatacora_flutter/features/synchronisation/data/transport_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/appairage.dart';
import 'package:tatacora_flutter/features/transverse/data/configuration_poste.dart';

/// L'APPAIRAGE du poste (lot F2a) et son transport, sur le `MockClient` de
/// `package:http` : la VRAIE pile [TransportHttp] est empruntée (en-têtes,
/// JSON, délais), seul le réseau est simulé.
void main() {
  const url = 'https://serveur.essai/api/v1';
  const secret = 'Mdp-Serveur-Tres-Secret-42';

  late Directory dossier;
  late String chemin;
  late List<http.Request> vues;

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora-appairage-');
    chemin = '${dossier.path}/poste.json';
    vues = [];
  });
  tearDown(() async {
    if (dossier.existsSync()) await dossier.delete(recursive: true);
  });

  Future<String> leChemin() async => chemin;

  ServiceAppairage service(
    FutureOr<http.Response> Function(http.Request) serveur, {
    String? urlServeur = url,
  }) => ServiceAppairage(
    transport: TransportHttp(
      client: MockClient((r) async {
        vues.add(r);
        return serveur(r);
      }),
    ),
    urlServeur: urlServeur,
    lecteur: LecteurConfigurationPoste(chemin: leChemin),
    ecrivain: EcrivainConfigurationPoste(chemin: leChemin),
    maintenant: () => DateTime.utc(2026, 10, 15, 9, 12),
  );

  http.Response json(int statut, Object corps) => http.Response(
    jsonEncode(corps),
    statut,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  http.Response connexionReussie(http.Request r) => json(200, {
    'token': '12|jeton-du-poste',
    'utilisateur': {'id': 'u1', 'login': 'gerant', 'role': 'Gérant'},
  });

  Future<Map<String, Object?>> fichier() async =>
      jsonDecode(await File(chemin).readAsString()) as Map<String, Object?>;

  group('le transport (TransportHttp sur MockClient)', () {
    test('POST : JSON, Accept, Bearer — et la réponse décodée', () async {
      late http.Request vue;
      final t = TransportHttp(
        client: MockClient((r) async {
          vue = r;
          return json(201, {'ok': true});
        }),
      );
      final issue = await t.post(
        urlServeur('$url/', '/sync'),
        corps: {'a': 'é'},
        jeton: '3|abc',
      );
      expect(vue.url.toString(), '$url/sync');
      expect(vue.method, 'POST');
      expect(vue.headers['Accept'], 'application/json');
      expect(vue.headers['Authorization'], 'Bearer 3|abc');
      expect(vue.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(vue.body), {'a': 'é'});
      expect(issue, isA<ReponseHttp>());
      expect((issue as ReponseHttp).statut, 201);
      expect(issue.corps, {'ok': true});
    });

    test('GET sans jeton : aucun en-tête Authorization', () async {
      late http.Request vue;
      final t = TransportHttp(
        client: MockClient((r) async {
          vue = r;
          return http.Response('pas du json', 500);
        }),
      );
      final issue = await t.get(Uri.parse('$url/utilisateur')) as ReponseHttp;
      expect(vue.headers.containsKey('Authorization'), isFalse);
      expect(issue.statut, 500);
      expect(issue.corps, isNull, reason: 'un corps illisible n’est pas lu');
    });

    test('délai dépassé : ServeurInjoignable, jamais une exception', () async {
      final t = TransportHttp(
        delai: const Duration(milliseconds: 50),
        client: MockClient((r) async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return json(200, {});
        }),
      );
      expect(await t.get(Uri.parse(url)), isA<ServeurInjoignable>());
    });

    test('erreur réseau et ClientException : ServeurInjoignable', () async {
      final coupe = TransportHttp(
        client: MockClient((_) => throw const SocketException('coupé')),
      );
      expect(await coupe.post(Uri.parse(url)), isA<ServeurInjoignable>());
      final client = TransportHttp(
        client: MockClient((_) => throw http.ClientException('refusé')),
      );
      expect(await client.get(Uri.parse(url)), isA<ServeurInjoignable>());
    });

    test('le délai de production est de 20 s (connexion et requête)', () {
      expect(delaiTransport, const Duration(seconds: 20));
      expect(TransportHttp().delai, const Duration(seconds: 20));
    });
  });

  group('le nom du poste', () {
    test('nettoyé : accents, blancs, caractères interdits, longueur', () {
      expect(nettoyerNomPoste('  Comptoir Bar 1 '), 'Comptoir-Bar-1');
      expect(nettoyerNomPoste('Réception’Gîte'), 'ReceptionGite');
      expect(nettoyerNomPoste('POSTE_01.lan'), 'POSTE_01.lan');
      expect(nettoyerNomPoste(' -- '), isNull);
      expect(nettoyerNomPoste(''), isNull);
      expect(nettoyerNomPoste('A' * 150)!.length, longueurMaxNomPoste);
    });
  });

  group('appairer', () {
    test('réussi : POST /login avec le poste nettoyé ; poste.json reçoit les '
        'cinq clés, garde le mot de passe SMTP, ne contient PAS le mot de '
        'passe serveur', () async {
      await File(chemin).writeAsString('{"smtp_mot_de_passe": "smtp-123"}');
      final r = await service(connexionReussie).appairer(
        identifiant: ' gerant ',
        motDePasse: secret,
        nomPoste: 'Comptoir 1',
      );
      expect(r, isA<AppairageReussi>());
      expect((r as AppairageReussi).posteId, 'Comptoir-1');

      final vue = vues.single;
      expect(vue.url.toString(), '$url/login');
      expect(jsonDecode(vue.body), {
        'identifiant': 'gerant',
        'mot_de_passe': secret,
        'poste': 'Comptoir-1',
      });

      final contenu = await fichier();
      expect(contenu, {
        'smtp_mot_de_passe': 'smtp-123',
        'poste_id': 'Comptoir-1',
        'jeton_api': '12|jeton-du-poste',
        'serveur': url,
        'appaire_le': '2026-10-15T09:12:00.000Z',
        'compte': 'gerant',
      });
      final brut = await File(chemin).readAsString();
      expect(brut, isNot(contains(secret)));
      expect(File('$chemin.tmp').existsSync(), isFalse);
      expect(dossier.listSync().map((e) => e.path.split('/').last), [
        'poste.json',
      ]);
    });

    test('l’écriture passe par un fichier TEMPORAIRE renommé : si le '
        'temporaire ne peut pas s’écrire, poste.json reste intact', () async {
      const avant = '{"smtp_mot_de_passe": "smtp-123"}';
      await File(chemin).writeAsString(avant);
      // Un DOSSIER à la place du temporaire : l'écriture échoue AVANT de
      // toucher poste.json. Écrire directement dans poste.json passerait.
      await Directory('$chemin.tmp').create();
      await expectLater(
        EcrivainConfigurationPoste(chemin: leChemin).enregistrerAppairage(
          AppairagePoste(
            posteId: 'P',
            jetonApi: 'j',
            serveur: url,
            appaireLe: DateTime.utc(2026),
            compte: 'c',
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await File(chemin).readAsString(), avant);
    });

    test('un poste.json ILLISIBLE n’est jamais écrasé', () async {
      await File(chemin).writeAsString('{ pas du json');
      final r = await service(
        connexionReussie,
      ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
      expect(r, isA<AppairageRefuse>());
      expect((r as AppairageRefuse).message, contains('illisible'));
      expect(await File(chemin).readAsString(), '{ pas du json');
    });

    for (final (code, attendu) in [
      (401, TextesAppairage.identifiantsRefuses),
      (403, TextesAppairage.compteDesactive),
      (429, TextesAppairage.tropDeTentatives),
      (422, TextesAppairage.saisieRefusee),
      (500, TextesAppairage.erreurServeur(500)),
      (404, TextesAppairage.reponseInattendue(404)),
    ]) {
      test('HTTP $code : « $attendu » — jamais le corps du serveur, rien '
          'n’est écrit', () async {
        final r = await service(
          (_) => json(code, {
            'message': 'CORPS-BRUT-DU-SERVEUR',
            'errors': {
              'identifiant': ['CORPS-BRUT-DU-SERVEUR'],
            },
          }),
        ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
        expect((r as AppairageRefuse).message, attendu);
        expect(r.message, isNot(contains('CORPS-BRUT')));
        expect(File(chemin).existsSync(), isFalse);
      });
    }

    test('serveur injoignable : la phrase le dit', () async {
      final r = await service(
        (_) => throw const SocketException('hôte introuvable'),
      ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
      expect(
        (r as AppairageRefuse).message,
        TextesAppairage.serveurInjoignable,
      );
    });

    test('200 sans jeton : refusé, rien d’écrit', () async {
      final r = await service(
        (_) => json(200, {'utilisateur': <String, Object?>{}}),
      ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
      expect(r, isA<AppairageRefuse>());
      expect(File(chemin).existsSync(), isFalse);
    });

    test('saisie incomplète ou nom illisible : refusé SANS requête', () async {
      final s = service(connexionReussie);
      expect(
        await s.appairer(identifiant: '', motDePasse: secret, nomPoste: 'P'),
        isA<AppairageRefuse>(),
      );
      expect(
        ((await s.appairer(
                  identifiant: 'g',
                  motDePasse: secret,
                  nomPoste: '***',
                ))
                as AppairageRefuse)
            .message,
        TextesAppairage.nomPosteInvalide,
      );
      expect(vues, isEmpty);
    });

    test('démonstration : aucun appairage, aucune requête', () async {
      final r = await service(
        connexionReussie,
        urlServeur: null,
      ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
      expect((r as AppairageRefuse).message, TextesAppairage.demonstration);
      expect(vues, isEmpty);
    });
  });

  group('tester, dissocier', () {
    Future<void> appairer() async {
      await File(chemin).writeAsString('{"smtp_mot_de_passe": "smtp-123"}');
      await service(
        connexionReussie,
      ).appairer(identifiant: 'gerant', motDePasse: secret, nomPoste: 'P1');
      vues.clear();
    }

    test('« Tester la connexion » : GET /utilisateur avec le jeton ; un '
        'succès efface un refus consigné', () async {
      await appairer();
      await EcrivainConfigurationPoste(
        chemin: leChemin,
      ).consignerRefus(401, DateTime.utc(2026, 10, 15));
      expect((await fichier()).containsKey(ClesAppairage.refus), isTrue);

      final m = await service(
        (_) => json(200, {'login': 'gerant'}),
      ).testerConnexion();
      expect(m, TextesAppairage.connexionEtablie('gerant'));
      expect(vues.single.method, 'GET');
      expect(vues.single.url.toString(), '$url/utilisateur');
      expect(vues.single.headers['Authorization'], 'Bearer 12|jeton-du-poste');
      expect((await fichier()).containsKey(ClesAppairage.refus), isFalse);
    });

    test(
      '« Tester la connexion » : 401 → jeton refusé ; injoignable → dit',
      () async {
        await appairer();
        expect(
          await service((_) => json(401, {})).testerConnexion(),
          TextesAppairage.jetonRefuse,
        );
        expect(
          await service(
            (_) => throw const SocketException('x'),
          ).testerConnexion(),
          TextesAppairage.serveurInjoignable,
        );
      },
    );

    test('non appairé : « Tester » le dit, sans requête', () async {
      expect(
        await service(connexionReussie).testerConnexion(),
        TextesAppairage.nonAppaire,
      );
      expect(vues, isEmpty);
    });

    test('« Dissocier » : POST /logout avec le jeton, puis les clés '
        'd’appairage retirées — le mot de passe SMTP demeure', () async {
      await appairer();
      final m = await service((_) => json(200, {})).dissocier();
      expect(m, TextesAppairage.dissocie);
      expect(vues.single.url.toString(), '$url/logout');
      expect(vues.single.headers['Authorization'], 'Bearer 12|jeton-du-poste');
      expect(await fichier(), {'smtp_mot_de_passe': 'smtp-123'});
    });

    test(
      '« Dissocier » hors connexion : le jeton est retiré quand même',
      () async {
        await appairer();
        final m = await service(
          (_) => throw const SocketException('coupé'),
        ).dissocier();
        expect(m, TextesAppairage.dissocie);
        expect(await fichier(), {'smtp_mot_de_passe': 'smtp-123'});
        expect(
          await LecteurConfigurationPoste(chemin: leChemin).appairage(),
          isNull,
        );
      },
    );
  });
}
