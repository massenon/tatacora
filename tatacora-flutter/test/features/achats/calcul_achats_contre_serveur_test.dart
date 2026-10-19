@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/achats/domain/calcul_achats.dart';
import 'package:tatacora_flutter/features/achats/domain/decimal_texte.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';

/// Les règles de calcul de M7, CONFRONTÉES au serveur en exécutant PHP.
///
/// `tool/achats/exporter_calculs.php` charge `ReceptionService` (ses vraies
/// méthodes `conformiteLigne`, `ecartPourcentage` et `evaluerConformite`),
/// `LigneCommandeAchat::montant` et les fichiers de langue par l'autoloader de
/// Composer — aucune base, aucun démarrage de l'application — et rejoue les cas
/// qu'on lui donne. Une formule recopiée à la main dans un test ne
/// vérifierait qu'elle-même, et resterait verte le jour où le serveur
/// changerait (piège 12).
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas.
Future<Map<String, dynamic>> _executer(Map<String, dynamic> cas) async {
  final php = await Process.start('php', ['tool/achats/exporter_calculs.php']);
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

String _q(int centiemes) => depuisCentiemes(centiemes);

void main() {
  final aleatoire = Random(20261009);

  group('Le montant d’une ligne est celui de bcmul (troncature)', () {
    final cas = <List<int>>[
      for (var i = 0; i < 300; i++)
        [
          1 + aleatoire.nextInt(i % 5 == 0 ? 30 : 5000000),
          i % 9 == 0 ? 1 : 1 + aleatoire.nextInt(900000000),
        ],
    ];

    test('300 lignes : le même montant, au centime près', () async {
      final reponse = await _executer({
        'montants': [
          for (final c in cas) [_q(c[0]), _q(c[1])],
        ],
      });
      final attendus = (reponse['montants'] as List<dynamic>).cast<String>();
      expect(attendus, hasLength(cas.length));

      for (var i = 0; i < cas.length; i++) {
        expect(
          _q(
            montantLigneCentimes(
              quantiteCentiemes: cas[i][0],
              prixUnitaireCentimes: cas[i][1],
            ),
          ),
          attendus[i],
          reason: 'quantité ${_q(cas[i][0])} × prix ${_q(cas[i][1])}',
        );
      }
    });

    test('la troncature n’arrondit jamais au plus proche', () async {
      // 0,01 × 0,01 = 0,0001 -> 0,00 ; 12,50 × 3,33 = 41,625 -> 41,62.
      expect(
        montantLigneCentimes(quantiteCentiemes: 1, prixUnitaireCentimes: 1),
        0,
      );
      expect(
        montantLigneCentimes(
          quantiteCentiemes: 1250,
          prixUnitaireCentimes: 333,
        ),
        4162,
      );
      final reponse = await _executer({
        'montants': [
          ['0.01', '0.01'],
          ['12.50', '3.33'],
        ],
      });
      expect(reponse['montants'], ['0.00', '41.62']);
    });
  });

  group('L’écart reçu / commandé en pourcentage est celui de bcdiv', () {
    final cas = <List<int>>[
      // Bords nommés : tout reçu pour rien commandé, rien pour rien, exact.
      [0, 0],
      [1, 0],
      [500, 500],
      [0, 500],
      [700, 300],
      for (var i = 0; i < 300; i++)
        [
          aleatoire.nextInt(i % 4 == 0 ? 3000 : 900000),
          i % 17 == 0 ? 0 : 1 + aleatoire.nextInt(900000),
        ],
    ];

    test('${cas.length} cas, y compris la quantité commandée nulle', () async {
      final reponse = await _executer({
        'ecarts': [
          for (final c in cas) [_q(c[0]), _q(c[1])],
        ],
        'ecart_incalculable': true,
      });
      final attendus = (reponse['ecarts'] as List<dynamic>).cast<String>();
      expect(attendus, hasLength(cas.length));

      for (var i = 0; i < cas.length; i++) {
        expect(
          _q(
            ecartPourcentageCentiemes(
              recueCentiemes: cas[i][0],
              commandeeCentiemes: cas[i][1],
            ),
          ),
          attendus[i],
          reason: 'reçu ${_q(cas[i][0])} / commandé ${_q(cas[i][1])}',
        );
      }
      // La constante d'écart « incalculable » est celle du serveur.
      expect(_q(ecartIncalculableCentiemes), reponse['ecart_incalculable']);
    });
  });

  group('Le verdict RG-10 d’une ligne est celui de conformiteLigne', () {
    final cas = <List<int>>[
      // PILE sur la tolérance : 5,00 % de 100 = 105 reçus -> totale ; un
      // centième de plus -> non conforme. Idem en deçà -> partielle.
      [10500, 10000, 500],
      [10501, 10000, 500],
      [9500, 10000, 500],
      [9499, 10000, 500],
      // Tolérance nulle : le moindre écart décide.
      [10000, 10000, 0],
      [10001, 10000, 0],
      [9999, 10000, 0],
      // Quantité commandée nulle : excédent infini, jamais « totale ».
      [1, 0, 10000],
      [0, 0, 500],
      for (var i = 0; i < 300; i++)
        [
          aleatoire.nextInt(300000),
          i % 19 == 0 ? 0 : 1 + aleatoire.nextInt(300000),
          aleatoire.nextInt(10001),
        ],
    ];

    test('${cas.length} cas, dont les bords PILE sur la tolérance', () async {
      final reponse = await _executer({
        'lignes': [
          for (final c in cas) [_q(c[0]), _q(c[1]), _q(c[2])],
        ],
      });
      final attendus = (reponse['lignes'] as List<dynamic>).cast<String>();
      expect(attendus, hasLength(cas.length));

      final vus = <String>{};
      for (var i = 0; i < cas.length; i++) {
        final local = conformiteLigne(
          recueCentiemes: cas[i][0],
          commandeeCentiemes: cas[i][1],
          toleranceCentiemes: cas[i][2],
        );
        vus.add(local.code);
        expect(
          local.code,
          attendus[i],
          reason:
              'reçu ${_q(cas[i][0])} / commandé ${_q(cas[i][1])} / '
              'tolérance ${_q(cas[i][2])} %',
        );
      }
      // Le balayage atteint les TROIS verdicts : sans cela il pourrait être
      // vert en ne vérifiant qu'un seul cas.
      expect(vus, {'totale', 'partielle', 'non_conforme'});
    });
  });

  group('Le verdict d’une réception est celui d’evaluerConformite', () {
    final articles = ['a', 'b', 'c', 'd'];

    final cas =
        <({Map<String, int> commandees, Map<String, int> recues, int t})>[
          // Un article reçu hors commande : non conforme, quoi qu'il arrive.
          (commandees: {'a': 500}, recues: {'z': 100}, t: 1000),
          // Un article commandé jamais reçu : partielle.
          (commandees: {'a': 500, 'b': 200}, recues: {'a': 500}, t: 1000),
          for (var i = 0; i < 200; i++)
            () {
              final n = 1 + aleatoire.nextInt(4);
              final commandees = {
                for (var k = 0; k < n; k++)
                  articles[k]: i % 23 == 0 ? 0 : 1 + aleatoire.nextInt(5000),
              };
              final recues = <String, int>{
                for (final e in commandees.entries)
                  if (aleatoire.nextInt(5) != 0)
                    e.key: 1 + (e.value * (80 + aleatoire.nextInt(45)) ~/ 100),
                if (i % 11 == 0) 'z': 1 + aleatoire.nextInt(100),
              };
              if (recues.isEmpty) recues[articles[0]] = 1;
              return (
                commandees: commandees,
                recues: recues,
                t: aleatoire.nextInt(2001),
              );
            }(),
        ];

    test(
      '${cas.length} réceptions, le même verdict que le service réel',
      () async {
        final reponse = await _executer({
          'evaluer': [
            for (final c in cas)
              {
                'commandees': {
                  for (final e in c.commandees.entries) e.key: _q(e.value),
                },
                'recues': {
                  for (final e in c.recues.entries) e.key: _q(e.value),
                },
                'tolerance': _q(c.t),
              },
          ],
        });
        final attendus = (reponse['evaluer'] as List<dynamic>).cast<String>();
        expect(attendus, hasLength(cas.length));

        final vus = <String>{};
        for (var i = 0; i < cas.length; i++) {
          final local = evaluerConformite(
            commandees: cas[i].commandees,
            recues: cas[i].recues,
            toleranceCentiemes: cas[i].t,
          );
          vus.add(local.code);
          expect(
            local.code,
            attendus[i],
            reason:
                'commandé ${cas[i].commandees} / reçu ${cas[i].recues} / '
                'tolérance ${_q(cas[i].t)} %',
          );
        }
        expect(vus, {'totale', 'partielle', 'non_conforme'});
      },
    );
  });

  group('Le rapprochement : écart et concordance de ControleTroisVoies', () {
    test(
      '150 lignes : l’écart est reçu - commandé, la concordance son signe',
      () async {
        final paires = <List<int>>[
          for (var i = 0; i < 150; i++)
            [
              i % 6 == 0 ? 0 : aleatoire.nextInt(9000),
              1 + aleatoire.nextInt(9000),
            ],
          [500, 500],
        ];
        final reponse = await _executer({
          'rapprocher': [
            for (var i = 0; i < paires.length; i++)
              {
                'commandees': {'a': _q(paires[i][1])},
                'recues': {'a': _q(paires[i][0])},
              },
          ],
        });
        final attendus = (reponse['rapprocher'] as List<dynamic>)
            .map((l) => ((l as List<dynamic>).single) as Map<String, dynamic>)
            .toList();
        expect(attendus, hasLength(paires.length));

        final vus = <String>{};
        for (var i = 0; i < paires.length; i++) {
          final recue = paires[i][0];
          final commandee = paires[i][1];
          final concordance = concordanceLigne(
            recueCentiemes: recue,
            commandeeCentiemes: commandee,
          );
          vus.add(concordance);
          expect(_q(recue - commandee), attendus[i]['ecart']);
          expect(concordance, attendus[i]['concordance']);
        }
        expect(vus, {'conforme', 'manquant', 'excedent'});
      },
    );
  });

  group('Les registres fermés sont ceux du serveur', () {
    late Map<String, dynamic> serveur;
    setUpAll(() async => serveur = await _executer(const {}));

    test('l’extraction n’est pas vide', () {
      // Sans ce contrôle, un renommage de clé rendrait un balayage vide, donc
      // vert (piège 4).
      expect((serveur['statuts'] as List<dynamic>), hasLength(5));
      expect(
        (serveur['phrases'] as Map<String, dynamic>).length,
        greaterThan(15),
      );
    });

    test('les cinq statuts de commande, dans l’ordre du serveur', () {
      expect([
        for (final s in StatutCommande.values) s.code,
      ], serveur['statuts']);
    });

    test('les deux statuts saisissables, et ils sont une DONNÉE', () {
      expect([
        for (final s in StatutCommande.saisissables) s.code,
      ], serveur['statuts_saisissables']);
    });

    test('les trois conformités', () {
      expect([
        for (final c in ConformiteReception.values) c.code,
      ], serveur['conformites']);
    });

    test('les quatre évaluations de fournisseur', () {
      expect([
        for (final e in EvaluationFournisseur.values) e.code,
      ], serveur['evaluations']);
    });

    test(
      'la réception complète pose « receptionnee », le reste « partiellement »',
      () {
        expect(
          statutApresReception(ConformiteReception.totale),
          StatutCommande.receptionnee,
        );
        expect(
          statutApresReception(ConformiteReception.partielle),
          StatutCommande.receptionneePartiellement,
        );
        expect(
          statutApresReception(ConformiteReception.nonConforme),
          StatutCommande.receptionneePartiellement,
        );
      },
    );
  });

  group('Les phrases sont celles du serveur, mot pour mot', () {
    late Map<String, String> p;
    setUpAll(() async {
      final serveur = await _executer(const {});
      p = (serveur['phrases'] as Map<String, dynamic>).cast<String, String>();
    });

    test('chaque refus repris du serveur y est identique', () {
      expect(MessagesAchats.commandeCloturee, p['commande_cloturee']);
      expect(MessagesAchats.receptionVide, p['reception_vide']);
      expect(MessagesAchats.clotureImpossible, p['cloture_impossible']);
      expect(MessagesAchats.toleranceAbsente, p['tolerance_absente']);
      expect(MessagesAchats.envoiImpossible, p['envoi_impossible']);
      expect(MessagesAchats.factureAbsente, p['facture_absente']);
      expect(MessagesAchats.fournisseurInexistant, p['fournisseur_inexistant']);
      expect(
        MessagesAchats.raisonSocialeObligatoire,
        p['raison_sociale_obligatoire'],
      );
      expect(MessagesAchats.evaluationInconnue, p['evaluation_inconnue']);
      expect(MessagesAchats.lignesObligatoires, p['lignes_obligatoires']);
      expect(MessagesAchats.articleInexistant, p['article_inexistant']);
      expect(MessagesAchats.articleEnDouble, p['article_en_double']);
      expect(MessagesAchats.quantitePositive, p['quantite_positive']);
      expect(MessagesAchats.pointInexistant, p['point_inexistant']);
      // ÉCART NOMMÉ (D276) : la fin « , ni aucun coût moyen pondéré mis à jour
      // à la réception » est FAUSSE (le serveur exécuté ne valorise pas à la
      // réception, D265) et le poste la retire. Le reste est au mot. Si le
      // serveur corrige sa phrase, l'une des deux lignes ci-dessous rougit.
      const finFausse =
          ', ni aucun coût moyen pondéré mis à jour à la réception.';
      expect(
        p['prix_obligatoire'],
        endsWith(finFausse),
        reason: 'le serveur a changé la phrase : retirer l’écart D276',
      );
      expect(
        MessagesAchats.prixObligatoire,
        '${(p['prix_obligatoire'] as String).replaceFirst(finFausse, '')}.',
      );
      expect(MessagesAchats.aucunPoint, p['aucun_point']);
      expect(MessagesAchats.aucunFournisseur, p['aucun_fournisseur']);
      expect(MessagesAchats.pointIntrouvable, p['point_introuvable']);
    });

    test('les gabarits à trous, avec leurs marqueurs :nom', () {
      expect(
        MessagesAchats.motifReception(commande: ':commande', bon: ':bon'),
        p['motif_reception'],
      );
      expect(MessagesAchats.commandeCreee(':fournisseur'), p['commande_creee']);
      // `reception_enregistree` n'est pas portée (D276) : le poste n'a aucun
      // toast de réception et la phrase du serveur est fausse sur le coût
      // moyen pondéré. Le serveur la porte toujours (sinon l'épinglage de
      // `reception_valorisation_contre_serveur_test.dart` n'a plus d'objet).
      expect(p['reception_enregistree'], contains(':conformite'));
      expect(MessagesAchats.fournisseurCree(':nom'), p['fournisseur_cree']);
      expect(
        MessagesAchats.fournisseurModifie(':nom'),
        p['fournisseur_modifie'],
      );
    });

    test(
      'aucune apostrophe typographique : les polices des PDF ne la couvrent pas',
      () {
        // U+2019 disparaît du papier sans rien signaler ; le serveur écrit
        // l'apostrophe droite, et ce poste de même.
        for (final v in p.values) {
          expect(v.contains('’'), isFalse, reason: v);
        }
      },
    );
  });

  group('La lecture de la tolérance saisie en Paramètres', () {
    test(
      'absente, illisible, lisible : trois issues qui ne se confondent pas',
      () {
        expect(lireTolerance(null), (centiemes: null, illisible: false));
        expect(lireTolerance('  '), (centiemes: null, illisible: false));
        expect(lireTolerance('5'), (centiemes: 500, illisible: false));
        expect(lireTolerance('2,5'), (centiemes: 250, illisible: false));
        expect(lireTolerance('0'), (centiemes: 0, illisible: false));
        // Trois décimales : refusé, pas tronqué en silence.
        expect(lireTolerance('2.555'), (centiemes: null, illisible: true));
        expect(lireTolerance('abc'), (centiemes: null, illisible: true));
        expect(lireTolerance('-1'), (centiemes: null, illisible: true));
      },
    );

    test('zéro est une tolérance, pas une absence', () {
      // Confondre « 0 » et « non renseignée » forcerait la saisie d'une
      // valeur devinée à qui veut une tolérance nulle.
      expect(lireTolerance('0').centiemes, 0);
      expect(lireTolerance('0.00').centiemes, 0);
    });
  });

  group('Réceptionnable / clôturable : les prédicats du serveur', () {
    test(
      'estCloturee compte « receptionnee » (le nom du serveur est trompeur)',
      () {
        expect(estCloturee(StatutCommande.receptionnee), isTrue);
        expect(estCloturee(StatutCommande.cloturee), isTrue);
        expect(estCloturee(StatutCommande.brouillon), isFalse);
        expect(estCloturee(StatutCommande.envoyee), isFalse);
        expect(estCloturee(StatutCommande.receptionneePartiellement), isFalse);
      },
    );

    test(
      'réceptionnable = non « clôturée » ; un statut inconnu ne l’est pas',
      () {
        for (final s in StatutCommande.values) {
          expect(receptionnable(s), !estCloturee(s));
        }
        expect(receptionnable(null), isFalse);
      },
    );

    test('clôturable : « receptionnee » seulement', () {
      for (final s in StatutCommande.values) {
        expect(cloturable(s), s == StatutCommande.receptionnee);
      }
      expect(cloturable(null), isFalse);
    });

    test('le reste à recevoir est planché à zéro', () {
      expect(
        resteARecevoirCentiemes(commandeeCentiemes: 1000, recueCentiemes: 400),
        600,
      );
      expect(
        resteARecevoirCentiemes(commandeeCentiemes: 1000, recueCentiemes: 1300),
        0,
      );
    });

    test(
      'le total est la somme des montants tronqués, jamais le produit de totaux',
      () {
        // Deux lignes de 1,50 × 0,33 = 0,495 -> 0,49 chacune : 0,98. Le produit
        // des totaux (3,00 × 0,33) donnerait 0,99 : c'est la somme des lignes
        // tronquées que le serveur écrit (`bcadd` des `montant()`).
        expect(
          montantTotalCentimes([
            (quantiteCentiemes: 150, prixUnitaireCentimes: 33),
            (quantiteCentiemes: 150, prixUnitaireCentimes: 33),
          ]),
          98,
        );
        expect(enCentiemes(_q(98)), 98);
      },
    );
  });
}
