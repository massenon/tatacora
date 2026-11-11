@Timeout(Duration(minutes: 5))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/affectation_resultat.dart';

import 'support/outils_comptabilite.dart';
import 'support/rejeu_affectation.dart';

/// L'AFFECTATION DU RÉSULTAT SELON LA FORME JURIDIQUE, CONFRONTÉE au vrai serveur
/// (09/11/2026, décision du PO : « le Gîte est une ENTREPRISE INDIVIDUELLE »).
///
/// Trois scénarios passent par `AffectationResultatService` (PHP exécuté,
/// `tool/comptabilite/rejouer_affectation.php`, base d'essai `TATACORA_BASE_ESSAI`) et
/// par `AffectationResultatLocale` ; le poste doit rendre, événement par événement, le
/// MÊME verdict, les MÊMES mots de refus, la MÊME carte (postes offerts, proposition,
/// alertes, avertissements) et les MÊMES lignes de journal :
///
///  A. ENTREPRISE INDIVIDUELLE (aucun réglage posé : le DÉFAUT) — ni dividende ni
///     réserve légale (refus), bénéfice vers le compte de l'exploitant (1041), perte
///     au compte de l'exploitant / report / imputation dans la limite du solde ;
///  B. SA (bénéfice) — réserve légale obligatoire nette des pertes antérieures,
///     plafond de 20 % du capital, dividendes bornés par les capitaux propres,
///     contre-passation (jamais avant la pièce, dans N, refusée si un dividende est
///     réglé, référence de la décision) ;
///  C. SARL (perte) — ordre d'imputation 121, 1181, 1291, alerte sous la moitié du
///     capital (non bloquante), jamais la réserve légale.
///
/// La forme n'est PAS écrite par ce poste (réglage du serveur, reçu en lecture) : le
/// rejeu la pose dans les deux bases par l'événement `forme`.
const _structure = 'Structure';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  /// Joue [scenario] au serveur (PHP) puis au poste, et rend les deux sorties.
  Future<({List<dynamic> serveur, List<Map<String, Object?>> poste})> jouer(
    List<Ev> scenario, {
    required List<Map<String, Object?>> exercices,
    required List<int> anneesAvant,
  }) async {
    final serveur = await executerPhp(
      'rejouer_affectation.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'exercices': exercices,
        'cles_messages': const <String>[],
        'evenements': scenario,
      },
    );
    final rejeu = await rejouerSurLePoste(scenario, anneesAvant: anneesAvant);
    addTearDown(rejeu.db.close);
    return (
      serveur: serveur['resultats'] as List<dynamic>,
      poste: rejeu.sortie,
    );
  }

  /// Le verdict de chaque événement : réussi, ou refusé aux mêmes mots ; la carte, la
  /// balance et l'instantané identiques ; le numéro de pièce d'une affectation aussi.
  void memeVerdict(
    List<Ev> scenario,
    List<dynamic> serveur,
    List<Map<String, Object?>> poste,
  ) {
    expect(serveur, hasLength(scenario.length));
    expect(poste, hasLength(scenario.length));
    for (var i = 0; i < scenario.length; i++) {
      final s = serveur[i] as Map<String, dynamic>;
      final p = poste[i];
      final contexte = 'événement $i : ${texte(scenario[i])}';
      if (s.containsKey('refus')) {
        expect(p['refus'], isTrue, reason: '$contexte — le poste a accepté');
        expect(p['message'], s['message'], reason: contexte);
        continue;
      }
      expect(
        p.containsKey('refus'),
        isFalse,
        reason: '$contexte — ${p['message']}',
      );
      switch (scenario[i]['t']) {
        case 'affecter':
          expect(p['piece'], s['piece'], reason: contexte);
        case 'etat_affectation':
        case 'balance':
        case 'geste':
          if (scenario[i]['t'] == 'balance') {
            expect(p['lignes'], s['lignes'], reason: contexte);
          } else {
            expect(p, s, reason: contexte);
          }
        case 'forme':
          expect(p['forme'], s['forme'], reason: contexte);
      }
    }
  }

  /// Les lignes de journal de l'affectation (OD) : mêmes comptes, centres, montants,
  /// dates, contre-passations comprises.
  void memesLignesDAffectation(
    Map<String, dynamic> s,
    Map<String, Object?> p,
    String contexte,
  ) {
    List<String> od(Object? brut) {
      final parAnnee = (brut! as Map).cast<String, dynamic>();
      return [
        for (final e in parAnnee.entries)
          for (final l in (e.value as List).cast<Map<String, dynamic>>())
            if (l['journal'] == 'OD' &&
                ('${l['libelle']}'.toLowerCase().contains('affectation') ||
                    '${l['libelle']}'.toLowerCase().contains('règlement')))
              '${e.key}|${cleLigne(l)}',
      ]..sort();
    }

    expect(p['statuts'], s['statuts'], reason: contexte);
    expect(od(p['lignes']), od(s['lignes']), reason: contexte);
  }

  Map<String, dynamic> dernier(List<dynamic> serveur, String t, List<Ev> sc) =>
      serveur[sc.lastIndexWhere((e) => e['t'] == t)] as Map<String, dynamic>;

  /* ================================================================== */
  /* A. Entreprise individuelle : le défaut du Gîte                      */
  /* ================================================================== */

  group('A. entreprise individuelle (aucun réglage posé : le défaut)', () {
    final scenario = <Ev>[
      evPiece('OD', '2030-01-02', 'Capital', [
        ('5711', '5000000.00', null, _structure),
        ('1011', null, '5000000.00', _structure),
      ]),
      evPiece('OD', '2030-01-03', 'Report créditeur', [
        ('5711', '8000.00', null, _structure),
        ('121', null, '8000.00', _structure),
      ]),
      evPiece('OD', '2030-01-04', 'Réserves facultatives', [
        ('5711', '5000.00', null, _structure),
        ('1181', null, '5000.00', _structure),
      ]),
      evPiece('CAI', '2030-03-10', 'Ventes bar', [
        ('5711', '100000.00', null, 'Bar'),
        ('7011', null, '100000.00', 'Bar'),
      ]),
      evPiece('CAI', '2030-03-11', 'Ventes restaurant', [
        ('5711', '80000.00', null, 'Restaurant'),
        ('7011', null, '80000.00', 'Restaurant'),
      ]),
      evPiece('ACH', '2030-04-02', 'Achats du bar', [
        ('6011', '70000.00', null, 'Bar'),
        ('4011', null, '70000.00', _structure),
      ]),
      evPiece('CAI', '2031-02-01', 'Ventes 2031', [
        ('5711', '50000.00', null, 'Bar'),
        ('7011', null, '50000.00', 'Bar'),
      ]),
      evPiece('ACH', '2031-03-01', 'Gros achats', [
        ('6011', '120000.00', null, 'Bar'),
        ('4011', null, '120000.00', _structure),
      ]),
      evGeste('demarrer', 2030),
      evGeste('cloturer', 2030),
      // 0 — la forme n'est pas posée : le défaut est l'entreprise individuelle.
      evCarte(2030), // 10
      // Dividende, réserve légale : refusés aux mots de l'entreprise individuelle.
      evAffecter(2030, '2031-04-30', {
        'dividendes': '10000.00',
        'compte_exploitant': '100000.00',
      }),
      evAffecter(2030, '2031-04-30', {
        'reserve_legale': '11000.00',
        'compte_exploitant': '99000.00',
      }),
      evAffecter(2030, '2031-04-30', {
        'compte_exploitant': '109999.99',
      }), // somme
      evAffecter(2030, '2031-04-30', {
        'imputation_report_crediteur': '1000.00',
        'compte_exploitant': '109000.00',
      }), // imputation sur un bénéfice
      // Bénéfice : 80 000 à l'exploitant, 20 000 au report, 10 000 aux réserves.
      evAffecter(2030, '2031-04-30', {
        'compte_exploitant': '80000.00',
        'report_a_nouveau': '20000.00',
        'autres_reserves': '10000.00',
      }),
      evCarte(2030),
      {'t': 'balance', 'annee': 2031},
      {'t': 'instantane'},
      // Contre-passation : aujourd'hui (15/06/2031), dans N, référence de la décision.
      evContrepasser(
        2030,
        'Décision de l’exploitant révisée',
        reference: 'Décision du 15/06/2031',
      ),
      evCarte(2030),
      {'t': 'instantane'},
      // 2031 : perte de 70 000, exercice clôturé.
      evGeste('demarrer', 2031),
      evGeste('cloturer', 2031),
      evCarte(2031),
      // Imputation sur le 121 au-delà de son solde : refusée.
      evAffecter(2031, '2032-03-31', {
        'imputation_report_crediteur': '99000.00',
        'compte_exploitant': '1.00',
      }),
      // Perte EI : 8 000 sur le 121, 5 000 sur le 1181, 7 000 au report débiteur, 50 000 à l'exploitant.
      evAffecter(2031, '2032-03-31', {
        'imputation_report_crediteur': '8000.00',
        'autres_reserves': '5000.00',
        'report_a_nouveau': '7000.00',
        'compte_exploitant': '50000.00',
      }),
      evCarte(2031),
      {'t': 'balance', 'annee': 2032},
      {'t': 'instantane'},
    ];

    late List<dynamic> serveur;
    late List<Map<String, Object?>> poste;

    setUpAll(() async {
      final r = await jouer(
        scenario,
        exercices: [
          {'annee': 2030, 'statut': 'ouvert'},
          {'annee': 2031, 'statut': 'ouvert'},
        ],
        anneesAvant: const [2030],
      );
      serveur = r.serveur;
      poste = r.poste;
    });

    test('même verdict, mêmes mots, même carte, même balance', () {
      memeVerdict(scenario, serveur, poste);
    });

    test('le défaut est l’entreprise individuelle : ni dividende ni réserve '
        'légale offerts, le reste au compte de l’exploitant', () {
      final i = scenario.indexWhere((e) => e['t'] == 'etat_affectation');
      final carte = serveur[i] as Map<String, dynamic>;
      expect(carte['forme'], 'entreprise_individuelle');
      expect(carte['est_societe'], isFalse);
      expect(carte['postes'], postesBeneficeEi);
      expect(carte['postes'], isNot(contains('dividendes')));
      expect(carte['postes'], isNot(contains('reserve_legale')));
      expect(carte['poste_du_reste'], 'compte_exploitant');
      expect((carte['proposition'] as Map)['compte_exploitant'], '110000.00');
      expect((carte['proposition'] as Map)['reserve_legale'], '0.00');
      expect(poste[i], carte);
    });

    test('dividende et réserve légale refusés aux mots du serveur', () {
      final refus = [
        for (final r in serveur)
          if ((r as Map).containsKey('refus')) r['message'] as String,
      ];
      expect(
        refus.where((m) => m.contains('ne verse pas de dividendes')),
        hasLength(1),
      );
      expect(
        refus.where((m) => m.contains('n\'a pas de réserve légale')),
        hasLength(1),
      );
      expect(refus.length, greaterThanOrEqualTo(5));
    });

    test('le résultat va au compte de l’exploitant, perte comprise : mêmes '
        'lignes de journal', () {
      var vus = 0;
      for (var i = 0; i < scenario.length; i++) {
        if (scenario[i]['t'] != 'instantane') continue;
        vus++;
        memesLignesDAffectation(
          serveur[i] as Map<String, dynamic>,
          poste[i],
          'instantané $i',
        );
      }
      expect(vus, 3);
      final dernierInstantane = dernier(serveur, 'instantane', scenario);
      final comptes = {
        for (final e in (dernierInstantane['lignes'] as Map).values)
          for (final l in (e as List).cast<Map<String, dynamic>>())
            if ('${l['libelle']}'.contains('Affectation')) l['compte'],
      };
      expect(comptes, containsAll(['131', '1041', '121', '1181', '139']));
      expect(comptes, isNot(contains('465')));
      expect(comptes, isNot(contains('111')));
    });

    test('la contre-passation est datée du jour de la correction, avec sa '
        'référence', () {
      final i = scenario.indexWhere(
        (e) => e['t'] == 'contrepasser_affectation',
      );
      final s = serveur[i] as Map<String, dynamic>;
      expect(s['date'], '2031-06-15');
      expect(s['reference'], 'Décision du 15/06/2031');
      // Le poste date ses lignes inverses du même jour (instantané suivant).
      final apres = scenario.indexWhere((e) => e['t'] == 'instantane', i);
      final lignes = [
        for (final e in (poste[apres]['lignes']! as Map).values)
          for (final l in (e as List).cast<Map<String, Object?>>())
            if (l['contrepasse'] == true &&
                '${l['libelle']}'.contains('Contre-passation'))
              l['date'],
      ];
      expect(lignes, isNotEmpty);
      expect(lignes.toSet(), {'2031-06-15'});
    });
  });

  /* ================================================================== */
  /* B. SA : réserve légale, dividendes, contre-passation               */
  /* ================================================================== */

  group('B. SA : réserve légale obligatoire, dividendes, contre-passation', () {
    final scenario = <Ev>[
      evForme('sa'),
      evPiece('OD', '2030-01-02', 'Capital', [
        ('5711', '1000000.00', null, _structure),
        ('1011', null, '1000000.00', _structure),
      ]),
      // 150 000 de réserve légale (plafond 200 000 : il reste 50 000) et
      // 30 000 de pertes antérieures (report à nouveau débiteur).
      evPiece('OD', '2030-01-03', 'Réserve légale existante', [
        ('5711', '150000.00', null, _structure),
        ('111', null, '150000.00', _structure),
      ]),
      evPiece('OD', '2030-01-04', 'Pertes antérieures', [
        ('1291', '30000.00', null, _structure),
        ('5711', null, '30000.00', null),
      ]),
      evPiece('CAI', '2030-03-10', 'Ventes bar', [
        ('5711', '100000.00', null, 'Bar'),
        ('7011', null, '100000.00', 'Bar'),
      ]),
      evPiece('CAI', '2030-03-11', 'Ventes restaurant', [
        ('5711', '80000.00', null, 'Restaurant'),
        ('7011', null, '80000.00', 'Restaurant'),
      ]),
      evPiece('ACH', '2030-04-02', 'Achats du bar', [
        ('6011', '70000.00', null, 'Bar'),
        ('4011', null, '70000.00', _structure),
      ]),
      evGeste('demarrer', 2030),
      evGeste('cloturer', 2030),
      // Base nette : 110 000 − 30 000 = 80 000 → 10 % = 8 000 (sous les 50 000 de place).
      evCarte(2030), // 9
      evAffecter(2030, '2031-09-30', {
        'reserve_legale': '7999.99',
        'report_a_nouveau': '102000.01',
      }), // réserve légale insuffisante
      evAffecter(2030, '2031-09-30', {
        'report_a_nouveau': '110000.00',
      }), // aucune réserve légale
      // Capitaux propres 1 230 000, plancher 1 158 000 : 72 000 de dividendes au plus.
      evAffecter(2030, '2031-09-30', {
        'reserve_legale': '8000.00',
        'dividendes': '72001.00',
        'report_a_nouveau': '29999.00',
      }),
      evAffecter(2030, '2031-09-30', {
        'compte_exploitant': '110000.00',
      }), // pas de compte de l'exploitant dans une société
      evAffecter(2030, '2031-09-30', {
        'reserve_legale': '8000.00',
        'dividendes': '30000.00',
        'report_a_nouveau': '72000.00',
      }),
      evCarte(2030),
      // Aujourd'hui (15/06/2031) est avant la pièce d'origine (30/09/2031) : refusé.
      evContrepasser(2030, 'Reprise de la ventilation'),
      evHorloge('2031-10-02'),
      // Un règlement partiel du dividende : la contre-passation est refusée.
      evPiece('OD', '2031-10-01', 'Règlement partiel du dividende', [
        ('465', '10000.00', null, _structure),
        ('5711', null, '10000.00', null),
      ], ref: 'reglement'),
      evContrepasser(2030, 'Reprise de la ventilation'),
      evContrepasserPiece('reglement'),
      evContrepasser(
        2030,
        'Reprise de la ventilation',
        reference: 'PV d’assemblée du 02/10/2031',
      ),
      evCarte(2030),
      {'t': 'instantane'},
      // Refaite, puis le jour est hors de N (2032) : la contre-passation est refusée.
      evAffecter(2030, '2031-10-05', {
        'reserve_legale': '8000.00',
        'report_a_nouveau': '102000.00',
      }),
      evHorloge('2032-01-10'),
      evContrepasser(2030, 'Reprise après la fin de l’exercice'),
      // N entre en clôture : la contre-passation ne se passe que dans un exercice ouvert.
      evHorloge('2031-12-20'),
      evGeste('demarrer', 2031),
      evContrepasser(2030, 'Reprise pendant la clôture de N'),
      {'t': 'instantane'},
    ];

    late List<dynamic> serveur;
    late List<Map<String, Object?>> poste;

    setUpAll(() async {
      final r = await jouer(
        scenario,
        exercices: [
          {'annee': 2030, 'statut': 'ouvert'},
          {'annee': 2031, 'statut': 'ouvert'},
        ],
        anneesAvant: const [2030],
      );
      serveur = r.serveur;
      poste = r.poste;
    });

    test('même verdict, mêmes mots, même carte', () {
      memeVerdict(scenario, serveur, poste);
    });

    test('la réserve légale obligatoire est nette des pertes antérieures et '
        'proposée en conséquence', () {
      final carte =
          serveur[scenario.indexWhere((e) => e['t'] == 'etat_affectation')]
              as Map<String, dynamic>;
      expect(carte['forme'], 'sa');
      expect(carte['est_societe'], isTrue);
      expect(carte['postes'], postesBenefice);
      expect((carte['proposition'] as Map)['reserve_legale'], '8000.00');
      expect((carte['proposition'] as Map)['report_a_nouveau'], '102000.00');
      expect(carte['alertes'], isEmpty);
    });

    test('les refus de la société portent les mots du serveur', () {
      final refus = [
        for (final r in serveur)
          if ((r as Map).containsKey('refus')) r['message'] as String,
      ];
      bool a(String m) => refus.any((r) => r.contains(m));
      expect(a('La réserve légale est obligatoire'), isTrue);
      expect(
        a(
          '(10 % de 80000.00, le bénéfice net des pertes antérieures de 30000.00)',
        ),
        isTrue,
      );
      expect(
        a(
          'La distribution de 72001.00 ferait passer les capitaux propres à 1157999.00',
        ),
        isTrue,
      );
      expect(
        a(
          'Le compte de l\'exploitant n\'existe que dans une entreprise individuelle',
        ),
        isTrue,
      );
      expect(
        a('ne peut pas être datée avant la pièce d\'affectation (2031-09-30)'),
        isTrue,
      );
      expect(
        a(
          'un dividende est déjà réglé en tout ou partie (10000.00 réglé sur 30000.00). Annulez d\'abord le règlement',
        ),
        isTrue,
      );
      expect(a('elle doit tomber dans l\'exercice 2031'), isTrue);
      expect(
        a(
          'est en_cloture. La contre-passation ne se passe que dans un exercice ouvert',
        ),
        isTrue,
      );
    });

    test('la contre-passation passe une fois le règlement annulé, avec sa '
        'référence et à la date du jour', () {
      final i = scenario.lastIndexWhere(
        (e) => e['t'] == 'contrepasser_affectation' && e['reference'] != null,
      );
      final s = serveur[i] as Map<String, dynamic>;
      expect(s.containsKey('refus'), isFalse);
      expect(s['date'], '2031-10-02');
      expect(s['reference'], 'PV d’assemblée du 02/10/2031');
      expect(poste[i]['ok'], isTrue);
    });

    test(
      'mêmes lignes de journal : affectations, contre-passations, règlement',
      () {
        var vus = 0;
        for (var i = 0; i < scenario.length; i++) {
          if (scenario[i]['t'] != 'instantane') continue;
          vus++;
          memesLignesDAffectation(
            serveur[i] as Map<String, dynamic>,
            poste[i],
            'instantané $i',
          );
        }
        expect(vus, 2);
      },
    );
  });

  /* ================================================================== */
  /* C. SARL : perte, ordre d'imputation, alerte                         */
  /* ================================================================== */

  group('C. SARL : ordre d’imputation d’une perte et alerte sous la moitié '
      'du capital', () {
    final scenario = <Ev>[
      evForme('sarl'),
      evPiece('OD', '2030-01-02', 'Capital', [
        ('5711', '100000.00', null, _structure),
        ('1011', null, '100000.00', _structure),
      ]),
      evPiece('OD', '2030-01-03', 'Report créditeur', [
        ('5711', '8000.00', null, _structure),
        ('121', null, '8000.00', _structure),
      ]),
      evPiece('OD', '2030-01-04', 'Réserves facultatives', [
        ('5711', '5000.00', null, _structure),
        ('1181', null, '5000.00', _structure),
      ]),
      evPiece('OD', '2030-01-05', 'Réserve légale', [
        ('5711', '9000.00', null, _structure),
        ('111', null, '9000.00', _structure),
      ]),
      evPiece('CAI', '2030-03-10', 'Ventes bar', [
        ('5711', '10000.00', null, 'Bar'),
        ('7011', null, '10000.00', 'Bar'),
      ]),
      evPiece('ACH', '2030-04-02', 'Achats du bar', [
        ('6011', '70000.00', null, 'Bar'),
        ('4011', null, '70000.00', _structure),
      ]),
      evGeste('demarrer', 2030),
      evGeste('cloturer', 2030),
      // Perte de 60 000 : 121 (8 000), 1181 (5 000), 1291 (47 000) ; jamais la réserve légale.
      // Capitaux propres : 100 000 + 8 000 + 5 000 + 9 000 − 60 000 = 62 000 ≥ 50 000 : pas d'alerte.
      evCarte(2030), // 8
      evAffecter(2030, '2031-04-30', {'reserve_legale': '60000.00'}),
      evAffecter(2030, '2031-04-30', {'compte_exploitant': '60000.00'}),
      evAffecter(2030, '2031-04-30', {
        'imputation_report_crediteur': '8000.01',
        'report_a_nouveau': '51999.99',
      }),
      evAffecter(2030, '2031-04-30', {
        'imputation_report_crediteur': '8000.00',
        'autres_reserves': '5000.00',
        'report_a_nouveau': '47000.00',
      }),
      evCarte(2030),
      {'t': 'instantane'},
    ];

    // La variante qui franchit le seuil : perte de 80 000 → capitaux propres 42 000.
    final alerte = <Ev>[
      evForme('sarl'),
      evPiece('OD', '2030-01-02', 'Capital', [
        ('5711', '100000.00', null, _structure),
        ('1011', null, '100000.00', _structure),
      ]),
      evPiece('CAI', '2030-03-10', 'Ventes bar', [
        ('5711', '10000.00', null, 'Bar'),
        ('7011', null, '10000.00', 'Bar'),
      ]),
      evPiece('ACH', '2030-04-02', 'Achats du bar', [
        ('6011', '70000.00', null, 'Bar'),
        ('4011', null, '70000.00', _structure),
      ]),
      evGeste('demarrer', 2030),
      evGeste('cloturer', 2030),
      evCarte(2030), // 6 : capitaux propres 40 000 < 50 000 : ALERTE
      evAffecter(2030, '2031-04-30', {'report_a_nouveau': '60000.00'}),
      evCarte(2030),
    ];

    // Une PETITE perte (4 000) : l'ordre compte — le 121 d'abord, avant le 1181.
    final petite = <Ev>[
      evForme('sarl'),
      evPiece('OD', '2030-01-03', 'Report créditeur', [
        ('5711', '8000.00', null, _structure),
        ('121', null, '8000.00', _structure),
      ]),
      evPiece('OD', '2030-01-04', 'Réserves facultatives', [
        ('5711', '5000.00', null, _structure),
        ('1181', null, '5000.00', _structure),
      ]),
      evPiece('CAI', '2030-03-10', 'Ventes bar', [
        ('5711', '10000.00', null, 'Bar'),
        ('7011', null, '10000.00', 'Bar'),
      ]),
      evPiece('ACH', '2030-04-02', 'Achats du bar', [
        ('6011', '14000.00', null, 'Bar'),
        ('4011', null, '14000.00', _structure),
      ]),
      evGeste('demarrer', 2030),
      evGeste('cloturer', 2030),
      evCarte(2030),
    ];

    late List<dynamic> serveur;
    late List<Map<String, Object?>> poste;
    late List<dynamic> serveurAlerte;
    late List<Map<String, Object?>> posteAlerte;
    late List<dynamic> serveurPetite;
    late List<Map<String, Object?>> postePetite;

    setUpAll(() async {
      final exercices = [
        {'annee': 2030, 'statut': 'ouvert'},
        {'annee': 2031, 'statut': 'ouvert'},
      ];
      final r = await jouer(
        scenario,
        exercices: exercices,
        anneesAvant: const [2030],
      );
      serveur = r.serveur;
      poste = r.poste;
      final a = await jouer(
        alerte,
        exercices: exercices,
        anneesAvant: const [2030],
      );
      serveurAlerte = a.serveur;
      posteAlerte = a.poste;
      final pe = await jouer(
        petite,
        exercices: exercices,
        anneesAvant: const [2030],
      );
      serveurPetite = pe.serveur;
      postePetite = pe.poste;
    });

    test('une petite perte entame le 121 AVANT le 1181, des deux côtés', () {
      memeVerdict(petite, serveurPetite, postePetite);
      final carte = serveurPetite.last as Map<String, dynamic>;
      final v = carte['proposition'] as Map<String, dynamic>;
      expect(v['imputation_report_crediteur'], '4000.00');
      expect(v['autres_reserves'], '0.00');
      expect(v['report_a_nouveau'], '0.00');
      expect(postePetite.last, carte);
    });

    test('même verdict, mêmes mots, même carte', () {
      memeVerdict(scenario, serveur, poste);
      memeVerdict(alerte, serveurAlerte, posteAlerte);
    });

    test('l’ordre d’imputation proposé : 121, puis 1181, puis le report '
        'débiteur ; jamais la réserve légale', () {
      final carte =
          serveur[scenario.indexWhere((e) => e['t'] == 'etat_affectation')]
              as Map<String, dynamic>;
      final v = carte['proposition'] as Map<String, dynamic>;
      expect(v['imputation_report_crediteur'], '8000.00');
      expect(v['autres_reserves'], '5000.00');
      expect(v['report_a_nouveau'], '47000.00');
      expect(v['reserve_legale'], '0.00');
      expect(v['dividendes'], '0.00');
      expect(carte['alertes'], isEmpty);
      expect(carte['postes'], postesPerte);
    });

    test('la réserve légale ne reçoit pas une perte ; une société n’a pas de '
        'compte de l’exploitant', () {
      final refus = [
        for (final r in serveur)
          if ((r as Map).containsKey('refus')) r['message'] as String,
      ];
      expect(
        refus.any(
          (m) => m.contains('Une perte ne s\'affecte pas à la réserve légale'),
        ),
        isTrue,
      );
      expect(
        refus.any(
          (m) => m.contains(
            'Le compte de l\'exploitant n\'existe que dans une entreprise individuelle',
          ),
        ),
        isTrue,
      );
      expect(
        refus.any((m) => m.contains('dépasse son solde créditeur (8000.00)')),
        isTrue,
      );
    });

    test('l’alerte de l’article 664 : sous la moitié du capital, non '
        'bloquante, rendue par la carte des deux côtés', () {
      final avant =
          serveurAlerte[alerte.indexWhere((e) => e['t'] == 'etat_affectation')]
              as Map<String, dynamic>;
      expect(avant['alertes'], hasLength(1));
      expect(
        (avant['alertes'] as List).single,
        allOf(
          contains('ALERTE'),
          contains('(40000.00)'),
          contains('(100000.00)'),
          contains('art. 664'),
        ),
      );
      expect(
        posteAlerte[alerte.indexWhere((e) => e['t'] == 'etat_affectation')],
        avant,
      );
      // Non bloquante : l'affectation passe, et la carte garde l'alerte.
      final passee = alerte.indexWhere((e) => e['t'] == 'affecter');
      expect((serveurAlerte[passee] as Map).containsKey('refus'), isFalse);
      expect((posteAlerte[passee]).containsKey('refus'), isFalse);
      final apres = serveurAlerte.last as Map<String, dynamic>;
      expect(apres['alertes'], hasLength(1));
    });
  });
}
