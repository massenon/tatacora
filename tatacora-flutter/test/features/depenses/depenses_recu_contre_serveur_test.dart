@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/depenses/data/recus_depenses_locaux.dart';
import 'package:tatacora_flutter/features/depenses/domain/recu_depense.dart';

import 'support/corpus_recus.dart';

/// Le reçu en image d'une dépense, jugé par le VRAI `RecuDepenseService` du
/// serveur (lot L4, 27/10/2026) : chaque fichier du corpus passe par
/// `tool/depenses/rejouer_recus.php` — règles `image` et `max:400` de Laravel,
/// `finfo` pour le type — et par `verifierRecu` du poste. Les deux doivent dire
/// la même chose : le même type quand le fichier est accepté, la MÊME phrase
/// quand il est refusé.
///
/// Un corpus recopié à la main des deux côtés ne prouverait rien : celui-ci est
/// UN seul JSON, lu par les deux moteurs, et il contient des fichiers que le
/// poste pourrait être tenté d'accepter sur leur seule signature (un PNG sans
/// son bloc IHDR, un « BM » suivi de texte, trois octets de JPEG).
///
/// Aucune base n'est ouverte par le script : il ne lit que des octets. Le test
/// ÉCHOUE si PHP est absent ou si le script casse, il ne saute pas.
void main() {
  late Map<String, dynamic> serveur;
  late Map<String, List<int>> corpus;

  setUpAll(() async {
    corpus = corpusRecus();
    final php = await Process.start('php', ['tool/depenses/rejouer_recus.php']);
    php.stdin.write(
      jsonEncode({
        'fichiers': [
          for (final e in corpus.entries)
            {'nom': e.key, 'base64': base64Encode(e.value)},
        ],
      }),
    );
    await php.stdin.close();
    final sortie = utf8.decodeStream(php.stdout);
    final erreurs = utf8.decodeStream(php.stderr);
    final code = await php.exitCode;
    final texte = await sortie;
    if (code != 0) {
      fail(
        'Le serveur n’a pas pu juger le corpus (php, code $code).\n'
        'STDERR : ${await erreurs}\nSTDOUT : $texte\n'
        'C’est un ÉCHEC, pas un saut.',
      );
    }
    serveur = jsonDecode(texte) as Map<String, dynamic>;
  });

  Map<String, dynamic> duServeur(String nom) => (serveur['resultats'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((r) => r['nom'] == nom);

  test(
    'le corpus est RELU en entier : aucun fichier n’échappe au jugement',
    () {
      expect(corpus.length, greaterThanOrEqualTo(15));
      expect((serveur['resultats'] as List).length, corpus.length);
    },
  );

  test('chaque fichier : le poste dit ce que le serveur dira — type accepté, '
      'ou LA MÊME phrase de refus', () {
    final divergences = <String>[];
    for (final e in corpus.entries) {
      final attendu = duServeur(e.key);
      final poste = verifierRecu(e.value);
      switch (poste) {
        case RecuAccepte(:final type):
          if (attendu['ok'] != true || attendu['type'] != type.mime) {
            divergences.add(
              '${e.key} : le poste accepte (${type.mime}), le serveur dit '
              '$attendu',
            );
          }
        case RecuRefuse(:final phrase):
          // Le serveur dit « vide » par une phrase qui lui est propre ; les
          // refus de contenu sont ceux du validateur.
          if (attendu['ok'] == true || attendu['message'] != phrase) {
            divergences.add(
              '${e.key} : le poste refuse (« $phrase »), le serveur dit '
              '$attendu',
            );
          }
      }
    }
    expect(divergences, isEmpty, reason: divergences.join('\n'));
  });

  test('les VRAIES images du corpus sont reconnues pour ce qu’elles sont, '
      'avec l’extension que le serveur range', () {
    for (final (nom, type) in const [
      ('png', TypeRecu.png),
      ('jpeg', TypeRecu.jpeg),
      ('gif', TypeRecu.gif),
      ('bmp', TypeRecu.bmp),
      ('webp', TypeRecu.webp),
    ]) {
      expect(typeRecuDepuisOctets(corpus[nom]!), type, reason: nom);
      final s = duServeur(nom);
      expect(s['ok'], isTrue, reason: nom);
      expect(s['type'], type.mime, reason: nom);
      expect(s['extension'], type.extension, reason: nom);
      expect(
        s['sha256'],
        RecusDepensesLocaux.empreinte(corpus[nom]!),
        reason: '$nom : la MÊME empreinte SHA-256 des deux côtés',
      );
    }
  });

  test('la borne est PILE celle du web : 400 × 1024 octets passent, un octet '
      'de plus est refusé', () {
    final constantes = serveur['constantes'] as Map<String, dynamic>;
    expect(tailleMaxRecuKo, constantes['taille_max_ko']);
    expect(tailleMaxRecuOctets, 409600);
    expect(duServeur('png-a-la-borne')['ok'], isTrue);
    expect(verifierRecu(corpus['png-a-la-borne']!), isA<RecuAccepte>());
    final trop = duServeur('png-un-octet-de-trop');
    expect(trop['refus'], 'recu_trop_lourd');
    expect(trop['statut'], 413);
    expect(verifierRecu(corpus['png-un-octet-de-trop']!), isA<RecuRefuse>());
    expect(
      (verifierRecu(corpus['png-un-octet-de-trop']!) as RecuRefuse).phrase,
      trop['message'],
    );
  });

  test('les phrases et les constantes du poste sont celles du serveur', () {
    final c = serveur['constantes'] as Map<String, dynamic>;
    final phrases = c['phrases'] as Map<String, dynamic>;
    expect(dossierRecusDepenses, c['dossier']);
    expect(TextesRecu.vide, phrases['recu_vide']);
    expect(TextesRecuPoste.autreRecuAuServeur, isNot(isEmpty));
    // Le libellé du champ et les deux mots de la colonne « Pièces » : ceux de
    // la vue (`depenses_pwa`), lus par PHP.
    expect(phrases['champ_recu'], 'Reçu / facture (photo)');
    expect(phrases['recu'], 'reçu');
    expect(phrases['sans_recu'], 'sans reçu');
  });

  test('l’aide de la vue promet une réduction que rien ne fait : la fausseté '
      'est épinglée à la SOURCE, et la phrase fausse n’est pas rendue', () {
    final constantes = serveur['constantes'] as Map<String, dynamic>;
    final aide = (constantes['phrases'] as Map)['champ_recu_aide'];
    // Elle rougit le jour où la vue est corrigée : l’écart nommé au code
    // (`_ChampRecu`) devra alors être relu.
    expect(
      aide,
      "L'image est réduite avant enregistrement. Le navigateur ne peut en "
      "conserver qu'une douzaine : au-delà, tout le registre cesserait d'être "
      'enregistré.',
    );
    final vue = File(
      '../tatacora-api/resources/views/pwa/depenses/depenses.blade.php',
    ).readAsStringSync();
    expect(
      vue,
      contains('Reduction du recu joint : le maitre l\'offre a la saisie, '),
      reason: 'la vue dit elle-même que la réduction n’est PAS portée',
    );

    // Et le code RENDU ne la répète pas : on lit les fichiers qui rendent le
    // champ (sans leurs commentaires, qui la citent pour la nommer).
    for (final chemin in const [
      'lib/features/depenses/presentation/widgets/modale_depense.dart',
      'lib/features/depenses/presentation/widgets/dialogue_recu_depense.dart',
      'lib/features/depenses/presentation/widgets/table_depenses.dart',
    ]) {
      final code = File(chemin)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('est réduite avant enregistrement')));
      expect(code, isNot(contains('qu\'une douzaine')));
      expect(code, isNot(contains('qu’une douzaine')));
    }
  });
}
