import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/crm/domain/detection_doublons.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';

/// RG-18 — la règle elle-même, éprouvée hors de tout widget.
///
/// ## Pourquoi ce fichier en plus des tests de la modale
///
/// `modale_nouveau_client_test.dart` monte l'écran et vérifie que
/// l'avertissement apparaît. C'est le bon test pour le comportement, et c'est
/// un mauvais test pour la **règle** : il ne peut éprouver qu'un cas à la fois,
/// à travers deux champs de saisie, et il ne dit rien des bords.
///
/// Or les deux bords sont là où la règle se trompe :
///
/// 1. le **repli des accents** — `cleDeNom` remplace le `normalize('NFD')` du
///    maître, que Dart n'expose pas. Une table écrite à la main peut oublier
///    une lettre, et l'oubli est invisible : « KORA Jéan » cesserait
///    simplement d'être reconnu comme « KORA Jean », sans erreur ;
/// 2. le **seuil de huit chiffres** — `m3-clients-creances.js` l.54. Sans lui,
///    un numéro tapé à moitié correspondrait à tout le référentiel et
///    l'avertissement s'afficherait en permanence, jusqu'à ce que personne ne
///    le lise. C'est une borne : elle ne se teste que **de part et d'autre**,
///    jamais au milieu (piège 7).
Client client({
  required String id,
  required String nom,
  required String telephone,
}) => Client(
  id: id,
  nom: nom,
  telephone: telephone,
  type: TypeClientReferentiel.particulier,
);

void main() {
  final referentiel = <Client>[
    client(id: 'c1', nom: 'KORA Jean', telephone: '01 90 12 34 56'),
    client(id: 'c2', nom: 'Agence Bénin Tour', telephone: '97 00 11 22'),
    client(id: 'c3', nom: 'SOSSOU Amélie', telephone: '96 55 44 33'),
  ];

  List<String> idsPour({String nom = '', String telephone = ''}) =>
      doublonsPotentiels(
        referentiel: referentiel,
        nom: nom,
        telephone: telephone,
      ).map((c) => c.id).toList();

  group('Le nom, replié comme le fait le maître', () {
    test(
      'la casse et les espaces ne distinguent pas deux fois le même nom',
      () {
        expect(idsPour(nom: 'kora jean'), ['c1']);
        expect(idsPour(nom: '  KORA   JEAN  '), ['c1']);
        // La ponctuation aussi : le maître ne garde que `[a-z0-9]`.
        expect(idsPour(nom: 'Kora-Jean.'), ['c1']);
      },
    );

    test('un accent ne fait pas échapper un homonyme', () {
      // Le cas qui perdrait le repli sans qu on le voie : le client existe
      // avec un accent, la saisie n en a pas — ou l inverse.
      expect(idsPour(nom: 'KORA Jéan'), ['c1']);
      expect(idsPour(nom: 'SOSSOU Amelie'), ['c3']);
      expect(idsPour(nom: 'agence benin tour'), ['c2']);
    });

    test('un nom vide ne rapproche personne', () {
      expect(idsPour(nom: ''), isEmpty);
      expect(idsPour(nom: '   '), isEmpty);
      expect(idsPour(nom: '...'), isEmpty);
    });

    test('la garde du nom vide protège d une fiche SANS nom lisible', () {
      // ⚠ Second cas écrit après une mutation muette : retirer
      // `cle.isNotEmpty` ne faisait rougir aucune assertion, parce qu'aucun
      // client du référentiel n'avait de nom qui se replie sur la chaîne vide.
      // La garde ne peut mordre que face à une fiche dont le nom ne contient
      // aucune lettre ni aucun chiffre — « --- », « ... », un nom saisi de
      // travers. Sans elle, la clé vide de cette fiche égalerait la clé vide
      // d'un formulaire encore blanc, et l'avertissement s'afficherait AVANT
      // la première frappe, sur chaque création.
      final sansNomLisible = [
        client(id: 'y', nom: '---', telephone: '96 12 34 56'),
      ];

      expect(
        doublonsPotentiels(referentiel: sansNomLisible, nom: '', telephone: ''),
        isEmpty,
      );
      expect(
        doublonsPotentiels(
          referentiel: sansNomLisible,
          nom: '...',
          telephone: '',
        ),
        isEmpty,
        reason:
            'Deux noms illisibles ne sont pas le même nom : leur clé est vide '
            'des deux côtés, et l égalité de deux vides ne dit rien.',
      );
    });

    test('deux noms réellement différents ne se rapprochent pas', () {
      expect(idsPour(nom: 'KORA Jeanne'), isEmpty);
      expect(idsPour(nom: 'DOSSOU Amélie'), isEmpty);
    });
  });

  group('Le téléphone, et sa borne de huit chiffres', () {
    test('la mise en forme ne compte pas — seuls les chiffres comptent', () {
      expect(idsPour(telephone: '0190123456'), ['c1']);
      expect(idsPour(telephone: '01-90-12-34-56'), ['c1']);
      expect(idsPour(telephone: '+229 01 90 12 34 56'), isEmpty);
    });

    test('la borne se tient DES DEUX CÔTÉS, jamais au milieu', () {
      // Sept chiffres : sous le seuil, aucun rapprochement — même si ces sept
      // chiffres sont bien le début d un numéro existant.
      expect(chiffresDe('01 90 123').length, 7);
      expect(idsPour(telephone: '01 90 123'), isEmpty);

      // Huit chiffres : au seuil. Le maître compare le numéro ENTIER, donc un
      // préfixe de huit chiffres ne correspond toujours à rien — c est
      // l égalité qui décide, pas le préfixe.
      expect(chiffresDe('01 90 12 34').length, 8);
      expect(idsPour(telephone: '01 90 12 34'), isEmpty);

      // Et un numéro complet de huit chiffres correspond bien.
      expect(chiffresDe('97 00 11 22').length, 8);
      expect(idsPour(telephone: '97 00 11 22'), ['c2']);
    });

    test('un numéro vide ne rapproche personne', () {
      expect(idsPour(telephone: ''), isEmpty);
      expect(idsPour(telephone: '01'), isEmpty);
    });

    test('la borne protège d un numéro court DÉJÀ EN BASE', () {
      // ⚠ Ce cas a été écrit APRÈS une mutation qui n'a pas mordu, et il vaut
      // d'être expliqué : abaisser le seuil de 8 à 1 ne faisait rougir aucune
      // assertion. La mutation accusait le **cas**, pas le code (piège 7).
      //
      // La raison : le maître compare le numéro par ÉGALITÉ, pas par préfixe
      // (`m3-clients-creances.js` l.54). Taper « 01 » ne peut donc jamais
      // égaler « 0190123456 », seuil ou pas. Le seuil ne mord que dans un seul
      // cas — celui où c'est le **référentiel** qui porte un numéro court, par
      // exemple une fiche créée avec « 9700 » au lieu du numéro complet. Sans
      // le seuil, quiconque taperait ces quatre mêmes chiffres serait accusé
      // d'être un doublon de cette fiche-là.
      final court = [
        client(id: 'x', nom: 'Fiche incomplète', telephone: '9700'),
      ];

      expect(
        doublonsPotentiels(referentiel: court, nom: '', telephone: '9700'),
        isEmpty,
        reason:
            'Quatre chiffres sont sous la borne des huit : deux numéros '
            'également incomplets ne désignent pas la même personne.',
      );
      // Et la même fiche reste rapprochable par son NOM, qui n'a pas de borne.
      expect(
        doublonsPotentiels(
          referentiel: court,
          nom: 'fiche incomplete',
          telephone: '',
        ).map((c) => c.id),
        ['x'],
      );
    });
  });

  group('Les deux critères sont un OU, pas un ET', () {
    test('le nom seul suffit, le téléphone seul aussi', () {
      expect(idsPour(nom: 'KORA Jean', telephone: '97 88 88 88'), ['c1']);
      expect(idsPour(nom: 'PARFAIT Inconnu', telephone: '97 00 11 22'), ['c2']);
    });

    test('deux clients peuvent correspondre en même temps', () {
      // Le maître distingue le singulier du pluriel dans son avertissement :
      // il faut donc que le cas pluriel puisse réellement se produire, sans
      // quoi la moitié de sa formulation ne serait jamais atteinte.
      final deux = doublonsPotentiels(
        referentiel: [
          client(id: 'a', nom: 'KORA Jean', telephone: '97 11 11 11'),
          client(id: 'b', nom: 'Autre Personne', telephone: '01 90 12 34 56'),
        ],
        nom: 'KORA Jean',
        telephone: '01 90 12 34 56',
      );
      expect(deux.map((c) => c.id), ['a', 'b']);
    });

    test('un référentiel vide ne rapproche rien, et ne lève pas', () {
      expect(
        doublonsPotentiels(
          referentiel: const [],
          nom: 'KORA Jean',
          telephone: '01 90 12 34 56',
        ),
        isEmpty,
      );
    });
  });
}
