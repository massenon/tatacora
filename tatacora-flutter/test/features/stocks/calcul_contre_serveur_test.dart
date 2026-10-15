@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/messages_stock.dart';

/// Les calculs de stock du client, CONFRONTÉS au serveur en exécutant PHP.
///
/// `tool/stocks/exporter_calculs.php` charge `ValorisationStockService`,
/// `Article` et les fichiers de langue par l'autoloader de Composer (aucune
/// base, aucun démarrage de l'application) et rejoue les cas qu'on lui donne.
/// Une formule recopiée à la main dans un test ne vérifierait qu'elle-même, et
/// resterait verte le jour où le serveur changerait (piège 12).
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas.
Future<Map<String, dynamic>> _executer(Map<String, dynamic> cas) async {
  final php = await Process.start('php', ['tool/stocks/exporter_calculs.php']);
  php.stdin.write(jsonEncode(cas));
  await php.stdin.close();

  final sortie = utf8.decodeStream(php.stdout);
  final erreur = utf8.decodeStream(php.stderr);
  final code = await php.exitCode;

  if (code != 0) {
    fail(
      'Le serveur n’a pas pu rejouer les calculs (php, code $code) : '
      '${await erreur}. C’est un ÉCHEC, pas un saut.',
    );
  }
  return jsonDecode(await sortie) as Map<String, dynamic>;
}

void main() {
  group('Le coût moyen pondéré rejoue celui du serveur', () {
    final aleatoire = Random(20261009);

    // 300 cas, dont les bords : stock avant nul, négatif, très grand ; coût
    // nul ; entrée d'un centième.
    final cas = <List<int>>[
      for (var i = 0; i < 300; i++)
        [
          i % 7 == 0
              ? 0
              : (i % 11 == 0
                    ? -aleatoire.nextInt(900)
                    : aleatoire.nextInt(500000)),
          aleatoire.nextInt(80000000),
          1 + aleatoire.nextInt(i % 5 == 0 ? 1 : 300000),
          i % 13 == 0 ? 0 : aleatoire.nextInt(80000000),
        ],
    ];

    test('300 entrées : le même résultat, au dix-millième près', () async {
      final reponse = await _executer({
        'cmp': [
          for (final c in cas)
            [
              ecrireCentiemes(c[0]),
              ecrireCout(c[1]),
              ecrireCentiemes(c[2]),
              ecrireCout(c[3]),
            ],
        ],
      });

      final attendus = (reponse['cmp'] as List<dynamic>).cast<String>();
      expect(attendus, hasLength(cas.length));

      for (var i = 0; i < cas.length; i++) {
        final c = cas[i];
        final local = moyennePonderee(
          quantiteAvant: c[0],
          cmpAvant: c[1],
          quantiteEntree: c[2],
          coutEntree: c[3],
        );
        expect(
          ecrireCout(local),
          attendus[i],
          reason:
              'avant ${ecrireCentiemes(c[0])} à ${ecrireCout(c[1])}, entrée '
              '${ecrireCentiemes(c[2])} à ${ecrireCout(c[3])}',
        );
      }
    });

    test('la dérive du CMP contre le prix d’achat : 200 cas', () async {
      final paires = <List<int>>[
        for (var i = 0; i < 200; i++)
          // Le prix est un multiple du CENTIME : la colonne `prix_achat` du
          // serveur est un DECIMAL(15,2) et arrondit tout ce qui est plus
          // fin. Ce poste garde les quatre décimales du coût saisi (écart
          // nommé dans `dernierPrixAchatDe`) ; la FORMULE, elle, est la même.
          [aleatoire.nextInt(80000000), (1 + aleatoire.nextInt(800000)) * 100],
      ];
      final reponse = await _executer({
        'derive': [
          for (final p in paires) [ecrireCout(p[0]), ecrireCout(p[1])],
        ],
      });

      final attendus = (reponse['derive'] as List<dynamic>).cast<int>();
      expect(attendus, hasLength(paires.length));

      for (var i = 0; i < paires.length; i++) {
        expect(
          deriveCoutMoyenPondere(cmp: paires[i][0], prixAchat: paires[i][1]),
          attendus[i],
          reason:
              'cmp ${ecrireCout(paires[i][0])} / prix ${ecrireCout(paires[i][1])}',
        );
      }
    });
  });

  group('Les phrases de refus sont celles du serveur, mot pour mot', () {
    late Map<String, dynamic> langue;
    setUpAll(() async => langue = await _executer(const {}));

    String validation(String cle) =>
        (langue['validation'] as Map<String, dynamic>)[cle] as String;

    test('l’extraction n’est pas vide', () {
      // Sans ce contrôle, un renommage de clé rendrait un balayage vide, donc
      // vert (piège 4).
      expect(
        (langue['validation'] as Map<String, dynamic>).length,
        greaterThan(10),
      );
      expect(langue['rupture'], isNotEmpty);
    });

    test('chaque phrase reprise du serveur y est identique', () {
      expect(MessagesStock.typeInconnu, validation('type_inconnu'));
      expect(MessagesStock.quantitePositive, validation('quantite_positive'));
      expect(MessagesStock.motifObligatoire, validation('motif_obligatoire'));
      expect(MessagesStock.articleInexistant, validation('article_inexistant'));
      expect(MessagesStock.pointInexistant, validation('point_inexistant'));
      expect(
        MessagesStock.coutReserveEntree,
        validation('cout_reserve_entree'),
      );
      expect(MessagesStock.ruptureSurSortie, validation('rupture_sur_sortie'));
      expect(
        MessagesStock.identifiantDejaPris,
        validation('identifiant_deja_pris'),
      );
      expect(
        MessagesStock.libelleObligatoire,
        validation('libelle_obligatoire'),
      );
      expect(MessagesStock.uniteObligatoire, validation('unite_obligatoire'));
      expect(MessagesStock.seuilObligatoire, validation('seuil_obligatoire'));
      expect(MessagesStock.periodeInversee, validation('periode_inversee'));
      expect(MessagesStock.coutNegatif, langue['cout_negatif']);
    });

    test('le motif de l’entrée d’ouverture est celui de la vue', () {
      expect(MessagesStock.motifOuverture, langue['motif_ouverture']);
    });

    test('le refus d’un article journalier remplace :article', () {
      expect(
        MessagesStock.refusJournalier('Tomates'),
        (langue['refus_journalier'] as String).replaceAll(
          ':article',
          'Tomates',
        ),
      );
    });

    test('la phrase de RG-06 remplace :disponible et :demande', () {
      final attendue = (langue['rupture'] as String)
          .replaceAll(':disponible', '3.00')
          .replaceAll(':demande', '4.50');
      expect(messageRupture(disponible: '3.00', demande: '4.50'), attendue);
    });
  });
}
