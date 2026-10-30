import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/adresse_serveur.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/frequence_synchronisation.dart';
import 'package:tatacora_flutter/features/synchronisation/presentation/providers_synchronisation.dart';

/// La VALIDATION et la normalisation de l'adresse du serveur (29/10/2026).
void main() {
  String? racine(String saisie) {
    final r = validerAdresseServeur(saisie);
    return r is AdresseValide ? r.adresse.racine : null;
  }

  String? erreur(String? saisie) {
    final r = validerAdresseServeur(saisie);
    return r is AdresseInvalide ? r.message : null;
  }

  group('adresses valides, normalisées', () {
    const cas = {
      'https://logirestock.digitonpro.com':
          'https://logirestock.digitonpro.com',
      '  https://logirestock.digitonpro.com/  ':
          'https://logirestock.digitonpro.com',
      'https://logirestock.digitonpro.com/api':
          'https://logirestock.digitonpro.com',
      'https://logirestock.digitonpro.com/api/':
          'https://logirestock.digitonpro.com',
      'https://logirestock.digitonpro.com/api/v1':
          'https://logirestock.digitonpro.com',
      'HTTPS://LogiReStock.DigitonPro.com/API/V1/':
          'https://logirestock.digitonpro.com',
      'https://exemple.bj:8443': 'https://exemple.bj:8443',
      'http://localhost:8000': 'http://localhost:8000',
      'http://localhost:8000/api/v1': 'http://localhost:8000',
      'http://127.0.0.1:8000': 'http://127.0.0.1:8000',
      'http://10.0.0.5': 'http://10.0.0.5',
      'http://192.168.1.20:8080': 'http://192.168.1.20:8080',
      'https://203.0.113.9': 'https://203.0.113.9',
    };
    for (final e in cas.entries) {
      test('« ${e.key} » → ${e.value}', () => expect(racine(e.key), e.value));
    }

    test('l’adresse d’API et l’adresse de santé se déduisent de la racine', () {
      final r =
          (validerAdresseServeur('https://logirestock.digitonpro.com/api/')
                  as AdresseValide)
              .adresse;
      expect(r.urlApi, 'https://logirestock.digitonpro.com/api/v1');
      expect(r.urlSante, 'https://logirestock.digitonpro.com/up');
    });
  });

  group('adresses refusées, en français', () {
    test('vide ou absente', () {
      expect(erreur(''), TextesAdresseServeur.vide);
      expect(erreur('   '), TextesAdresseServeur.vide);
      expect(erreur(null), TextesAdresseServeur.vide);
    });

    test('sans schéma, ou avec un autre schéma', () {
      expect(erreur('logirestock.digitonpro.com'), TextesAdresseServeur.schema);
      expect(
        erreur('ftp://logirestock.digitonpro.com'),
        TextesAdresseServeur.schema,
      );
      expect(
        erreur('//logirestock.digitonpro.com'),
        TextesAdresseServeur.schema,
      );
    });

    test('un espace, où que ce soit', () {
      expect(erreur('https://logirestock .com'), TextesAdresseServeur.espaces);
      expect(
        erreur('https://logirestock.com/ api'),
        TextesAdresseServeur.espaces,
      );
    });

    test('http hors réseau local', () {
      expect(
        erreur('http://logirestock.digitonpro.com'),
        TextesAdresseServeur.httpsExige,
      );
      expect(erreur('http://203.0.113.9'), TextesAdresseServeur.httpsExige);
      // 172.16.x n'est pas dans la liste du PO : https exigé.
      expect(erreur('http://172.16.0.4'), TextesAdresseServeur.httpsExige);
      expect(erreur('http://192.169.0.1'), TextesAdresseServeur.httpsExige);
      expect(
        erreur('http://localhost.evil.com'),
        TextesAdresseServeur.httpsExige,
      );
    });

    test('un chemin superflu', () {
      expect(
        erreur('https://logirestock.com/app'),
        TextesAdresseServeur.chemin,
      );
      expect(
        erreur('https://logirestock.com/api/v2'),
        TextesAdresseServeur.chemin,
      );
      expect(
        erreur('https://logirestock.com/api/v1/clients'),
        TextesAdresseServeur.chemin,
      );
    });

    test('paramètres, ancre, identifiants', () {
      expect(
        erreur('https://logirestock.com?x=1'),
        TextesAdresseServeur.parametres,
      );
      expect(
        erreur('https://logirestock.com/#haut'),
        TextesAdresseServeur.parametres,
      );
      expect(
        erreur('https://admin:mdp@logirestock.com'),
        TextesAdresseServeur.identifiants,
      );
    });

    test('hôte illisible', () {
      expect(erreur('https://'), TextesAdresseServeur.illisible);
      expect(erreur('https://_x_.com'), TextesAdresseServeur.illisible);
      expect(erreur('http://'), TextesAdresseServeur.illisible);
    });

    test('255 caractères au plus', () {
      final hote = 'a' * 63;
      final ok = 'https://$hote.$hote.${'b' * 60}.com'; // < 255
      expect(ok.length, lessThanOrEqualTo(255));
      expect(racine(ok), isNotNull);
      final trop = 'https://${'a' * 250}.com';
      expect(trop.length, greaterThan(255));
      expect(erreur(trop), TextesAdresseServeur.tropLongue);
    });

    test('aucune phrase ne laisse passer une adresse invalide', () {
      for (final mauvaise in [
        '',
        'x',
        'http://exemple.com',
        'https://exemple.com/a',
        'https://a b.com',
      ]) {
        expect(racine(mauvaise), isNull, reason: mauvaise);
      }
    });
  });

  test(
    'racineDepuisUrlApi : ce que l’écran montre d’une adresse enregistrée',
    () {
      expect(
        racineDepuisUrlApi('https://logirestock.digitonpro.com/api/v1'),
        'https://logirestock.digitonpro.com',
      );
      expect(racineDepuisUrlApi('https://x.bj/api/v1/'), 'https://x.bj');
      expect(racineDepuisUrlApi('https://x.bj'), 'https://x.bj');
      expect(racineDepuisUrlApi(''), isNull);
      expect(racineDepuisUrlApi(null), isNull);
    },
  );

  group('fréquence de la synchronisation automatique', () {
    test('le défaut est 5 minutes, comme la période livrée', () {
      expect(
        FrequenceSynchronisation.parDefaut.periode,
        periodeSynchronisation,
      );
      expect(FrequenceSynchronisation.parDefaut.libelle, contains('défaut'));
    });

    test('chaque option porte sa période ; manuelle : aucune', () {
      expect(
        {for (final f in FrequenceSynchronisation.values) f.minutes: f.periode},
        {
          1: const Duration(minutes: 1),
          2: const Duration(minutes: 2),
          5: const Duration(minutes: 5),
          10: const Duration(minutes: 10),
          15: const Duration(minutes: 15),
          30: const Duration(minutes: 30),
          60: const Duration(hours: 1),
          0: null,
        },
      );
    });

    test('une valeur inconnue du fichier retombe sur le défaut', () {
      expect(
        FrequenceSynchronisation.depuisMinutes(7),
        FrequenceSynchronisation.parDefaut,
      );
      expect(
        FrequenceSynchronisation.depuisMinutes('10'),
        FrequenceSynchronisation.parDefaut,
      );
      expect(
        FrequenceSynchronisation.depuisMinutes(null),
        FrequenceSynchronisation.parDefaut,
      );
      expect(
        FrequenceSynchronisation.depuisMinutes(0),
        FrequenceSynchronisation.manuelle,
      );
    });

    test('l’aide ne promet pas un déclencheur qui n’existe pas', () {
      for (final faux in [
        'retour du réseau',
        'après une vente',
        'ouverture de la session',
      ]) {
        expect(TextesFrequenceSynchronisation.aide, isNot(contains(faux)));
      }
    });
  });
}
