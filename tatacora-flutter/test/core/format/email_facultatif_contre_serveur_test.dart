@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/format/adresse_email_facultative.dart';

import '../../features/comptabilite/support/outils_comptabilite.dart';

/// L'e-mail FACULTATIF (28/10/2026) : la règle du poste (`AdresseEmailFacultative`)
/// confrontée à la VRAIE règle du serveur (`nullable|email:filter|max:255` de
/// Laravel + `normaliser`), sur des adresses ordinaires et sur les pièges :
/// espaces, majuscules, point en bout de partie locale, deux points de suite,
/// domaine sans point, trait d'union en bout d'étiquette, longueurs limites.
///
/// Les deux phrases (`email_invalide`, `email_enregistre`) sont relues du fichier
/// de langue du serveur : une copie figée côté Dart ne vérifierait qu'elle-même.
void main() {
  final etiquette63 = 'a' * 63;
  final adresses = <String>[
    '',
    '   ',
    'kora@exemple.bj',
    '  Paul.DOSSOU@Exemple.BJ  ',
    'a@b.co',
    'a@b',
    'a@b.',
    'a@.b.co',
    '@exemple.bj',
    'kora@',
    'kora',
    'kora@@exemple.bj',
    'ko ra@exemple.bj',
    '.kora@exemple.bj',
    'kora.@exemple.bj',
    'ko..ra@exemple.bj',
    'ko.ra@exemple.bj',
    "o'brien@exemple.bj",
    'kora+tag@exemple.bj',
    'kora_ra-ko@exemple.bj',
    'kora@exemple-.bj',
    'kora@-exemple.bj',
    'kora@exemple..bj',
    'kora@ex_emple.bj',
    'kora@exemple.b-j',
    'kora@sous.domaine.exemple.bj',
    'kora@exemple.123',
    'kora@$etiquette63.bj',
    'kora@${'a' * 64}.bj',
    '${'k' * 64}@exemple.bj',
    '${'k' * 65}@exemple.bj',
    '${'k' * 250}@exemple.bj',
    'kora@exémple.bj',
    'kôra@exemple.bj',
    'kora@exemple.bj.',
    'kora@exemple.bj ',
    '<kora@exemple.bj>',
    '"kora"@exemple.bj',
    'kora@[127.0.0.1]',
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_email_facultatif.php',
      dossier: 'rh',
      entree: {'adresses': adresses},
    );
  });

  List<Map<String, dynamic>> lignes() => [
    for (final l in serveur['resultats'] as List) l as Map<String, dynamic>,
  ];

  test('la liste est assez large pour que la comparaison compte', () {
    final valides = lignes().where((l) => l['valide'] == true).length;
    final refusees = lignes().where((l) => l['valide'] == false).length;
    expect(lignes(), hasLength(adresses.length));
    expect(valides, greaterThan(8));
    expect(refusees, greaterThan(15));
  });

  test('chaque adresse est normalisée ET jugée comme le serveur', () {
    final ecarts = <String>[];
    for (final l in lignes()) {
      final saisie = l['saisie'] as String;
      final normalisee = AdresseEmailFacultative.normaliser(saisie);
      final valide = normalisee == null
          ? true
          : AdresseEmailFacultative.estValide(normalisee);
      if (normalisee != l['normalisee']) {
        ecarts.add(
          '« $saisie » normalisée : poste ${normalisee ?? 'null'} / '
          'serveur ${l['normalisee']}',
        );
      }
      if (valide != l['valide']) {
        ecarts.add(
          '« $saisie » valide : poste $valide / serveur ${l['valide']}',
        );
      }
      final phrase = AdresseEmailFacultative.erreur(saisie);
      final attendue = l['valide'] == true
          ? null
          : AdresseEmailFacultative.messageInvalide;
      if (phrase != attendue) {
        ecarts.add('« $saisie » refus : poste $phrase / attendu $attendue');
      }
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });

  test('les phrases du poste sont celles du fichier de langue du serveur', () {
    final phrases = serveur['phrases'] as Map<String, dynamic>;
    expect(AdresseEmailFacultative.messageInvalide, phrases['invalide']);
    expect(AdresseEmailFacultative.messageEnregistree, phrases['enregistree']);
  });
}
