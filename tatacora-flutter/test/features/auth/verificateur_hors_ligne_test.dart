import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/auth/data/verificateur_hors_ligne.dart';

/// Le vérificateur de connexion hors ligne.
///
/// ## Le premier cas est le plus important du fichier
///
/// PBKDF2 est écrit à la main, faute de KDF dans `crypto`. **Une dérivation
/// fausse serait invisible** : elle produirait un vérificateur parfaitement
/// cohérent avec lui-même — on pose une empreinte, on la retrouve, tout passe
/// au vert — tout en n'ayant pas la résistance qu'on lui prête. Seul un
/// **vecteur de référence externe** peut le dire.
///
/// C'est la même famille que PA-59/60/61 : un mécanisme qui affirme une
/// garantie qu'il n'a pas.
void main() {
  group('PBKDF2 — éprouvé contre des vecteurs de référence', () {
    String hexDe(String motDePasse, String sel, int tours) =>
        VerificateurHorsLigne.deriver(
          motDePasse: motDePasse,
          sel: Uint8List.fromList(utf8.encode(sel)),
          iterations: tours,
        ).map((o) => o.toRadixString(16).padLeft(2, '0')).join();

    test('P="password" S="salt" c=1 donne le condensé public attendu', () {
      expect(
        hexDe('password', 'salt', 1),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('c=2 — le seul cas qui éprouve la boucle de chaînage', () {
      // Avec un seul tour, une boucle fausse — ou absente — passerait au vert :
      // U1 seul EST le résultat. Le second vecteur est donc indispensable.
      expect(
        hexDe('password', 'salt', 2),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('c=4096 — le régime réellement employé', () {
      expect(
        hexDe('password', 'salt', 4096),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('Vérification d’un mot de passe', () {
    final maintenant = DateTime(2026, 8, 21, 10);

    VerificateurHorsLigne poser(String motDePasse) =>
        VerificateurHorsLigne.creer(
          login: 'n.nabogou',
          motDePasse: motDePasse,
          maintenant: maintenant,
          // Peu de tours : ces cas éprouvent la logique, pas le coût.
          iterations: 100,
        );

    test('le bon mot de passe est reconnu', () {
      expect(poser('Un mot de passe').correspond('Un mot de passe'), isTrue);
    });

    test('un mot de passe faux est refusé', () {
      final v = poser('Un mot de passe');
      expect(v.correspond('Un mot de passe '), isFalse);
      expect(v.correspond('un mot de passe'), isFalse);
      expect(v.correspond(''), isFalse);
    });

    test('le mot de passe n’apparaît NULLE PART dans ce qui est conservé', () {
      const secret = 'Motdepasse-tres-reconnaissable-2026';
      final json = jsonEncode(poser(secret).versJson());

      // La garantie qui compte : ce qui sera écrit sur le disque du poste ne
      // doit contenir aucune trace du secret, ni en clair, ni encodé.
      expect(json, isNot(contains(secret)));
      expect(json, isNot(contains(base64Encode(utf8.encode(secret)))));
    });

    test('deux postes ne produisent pas la même empreinte', () {
      // Le sel est aléatoire : sans lui, deux employés ayant le même mot de
      // passe porteraient la même empreinte, et une seule cassée les
      // ouvrirait tous les deux.
      final a = poser('identique');
      final b = poser('identique');
      expect(a.sel, isNot(b.sel));
      expect(a.empreinte, isNot(b.empreinte));
      expect(a.correspond('identique'), isTrue);
      expect(b.correspond('identique'), isTrue);
    });

    test('il survit à un aller-retour JSON', () {
      final origine = poser('secret');
      final relu = VerificateurHorsLigne.depuisJson(
        jsonDecode(jsonEncode(origine.versJson())) as Map<String, dynamic>,
      );

      expect(relu.login, 'n.nabogou');
      expect(relu.correspond('secret'), isTrue);
      expect(relu.correspond('autre'), isFalse);
      expect(
        relu.derniereConnexionEnLigne.toUtc(),
        origine.derniereConnexionEnLigne.toUtc(),
      );
    });
  });

  group('Fenêtre de validité — la borne qui protège d’un compte révoqué', () {
    final connexion = DateTime(2026, 8, 21, 10);
    final v = VerificateurHorsLigne.creer(
      login: 'n.nabogou',
      motDePasse: 'secret',
      maintenant: connexion,
      iterations: 100,
    );

    test('valide dans la fenêtre', () {
      expect(v.estValide(connexion), isTrue);
      expect(
        v.estValide(connexion.add(const Duration(days: 6, hours: 23))),
        isTrue,
      );
    });

    test('expiré au-delà', () {
      // Sans cette borne, un compte révoqué garderait l'accès indéfiniment sur
      // un poste qu'on garde hors ligne — précisément parce qu'on le garde
      // hors ligne.
      expect(v.estValide(connexion.add(const Duration(days: 7))), isFalse);
      expect(v.estValide(connexion.add(const Duration(days: 30))), isFalse);
    });

    test('la fenêtre est un paramètre, pas une constante enfouie', () {
      // ⚠ Les 7 jours sont posés PAR DÉFAUT, non arbitrés. Ce cas garantit que
      // l'arbitrage du Product Owner coûtera un argument, pas une refonte.
      expect(
        v.estValide(
          connexion.add(const Duration(days: 10)),
          fenetre: const Duration(days: 14),
        ),
        isTrue,
      );
      expect(
        v.estValide(
          connexion.add(const Duration(days: 2)),
          fenetre: const Duration(days: 1),
        ),
        isFalse,
      );
    });
  });
}
