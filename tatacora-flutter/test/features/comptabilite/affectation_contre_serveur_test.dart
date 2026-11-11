@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/affectation_resultat.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/cloture_exercice.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/comptes_syscohada.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/correspondance_comptes.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/forme_juridique.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_affectation.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import 'support/outils_comptabilite.dart';
import 'support/rejeu_affectation.dart';

/// L'AFFECTATION DU RÉSULTAT du poste, CONFRONTÉE au vrai serveur (09/11/2026) :
/// le même scénario — bénéfice affecté, refus de chaque règle, double
/// affectation, contre-passation, réouverture refusée, perte, imputation —
/// passe par `AffectationResultatService` (PHP exécuté,
/// `tool/comptabilite/rejouer_affectation.php`, base d'essai
/// `TATACORA_BASE_ESSAI`) et par `AffectationResultatLocale`, et le poste doit
/// rendre :
///
///  - les mêmes PHRASES de refus, mot pour mot (exercice non clôturé, résultat
///    nul, somme, négatif, dividende ou réserve légale sur une perte, imputation
///    excessive, date, comptable seul, double affectation, motif, aucune
///    affectation, réouverture refusée…) ;
///  - la même carte (résultat, compte, proposition de réserve légale, plafond,
///    affectation active, date par défaut) ;
///  - les mêmes lignes de pièce (journal OD, date, compte, centre, débit, crédit,
///    libellé), contre-passations comprises, et les mêmes numéros ;
///  - le même bilan (équilibré, résultat reporté tombé à zéro, mêmes postes) et
///    la même balance ;
///  - les mêmes rubriques du bilan (réserves, report à nouveau, dividendes).
///
/// Les phrases (`MessagesAffectation`) sont relues du serveur, des deux côtés ;
/// les constantes (journal, rôle, postes, taux) aussi.
void main() {
  final scenario = <Ev>[
    // Ce scénario éprouve une SOCIÉTÉ (réserve légale, dividendes) ; l'entreprise
    // individuelle, forme par défaut du Gîte, a le sien (`affectation_forme_contre_serveur_test`).
    evForme('sarl'),
    // --- 2030 : bénéfice de 110 000, capital de 5 000 000 -------------------
    evPiece('OD', '2030-01-02', 'Capital', [
      ('5711', '5000000.00', null, 'Structure'),
      ('1011', null, '5000000.00', 'Structure'),
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
      ('6011', '30000.00', null, 'Bar'),
      ('4011', null, '30000.00', 'Structure'),
    ]),
    evPiece('OD', '2030-05-31', 'Salaires', [
      ('6611', '40000.00', null, 'RH'),
      ('5711', null, '40000.00', 'RH'),
    ]),
    // --- 2031 : déficitaire, perte de 70 000 --------------------------------
    evPiece('CAI', '2031-02-01', 'Ventes 2031', [
      ('5711', '50000.00', null, 'Bar'),
      ('7011', null, '50000.00', 'Bar'),
    ]),
    evPiece('ACH', '2031-03-01', 'Gros achats', [
      ('6011', '120000.00', null, 'Bar'),
      ('4011', null, '120000.00', 'Structure'),
    ]),
    // --- 2029 : un exercice VIDE, clôturé : résultat nul --------------------
    evGeste('demarrer', 2029),
    evGeste('cloturer', 2029),
    evCarte(2029),
    evAffecter(2029, '2030-04-30', {'report_a_nouveau': '0.00'}),
    // --- avant la clôture : aucune carte, un refus --------------------------
    evCarte(2030),
    evAffecter(2030, '2031-04-30', {'report_a_nouveau': '110000.00'}),
    evGeste('demarrer', 2030),
    evAffecter(2030, '2031-04-30', {'report_a_nouveau': '110000.00'}),
    evGeste('cloturer', 2030),
    // --- la carte : proposition 10 % (11 000), plafond 1 000 000 ------------
    evCarte(2030),
    evCarte(2030, role: 'administrateur'),
    // --- les refus de la ventilation et de la date --------------------------
    evAffecter(2030, '2031-04-30', {'report_a_nouveau': '109999.99'}),
    evAffecter(2030, '2031-04-30', {'report_a_nouveau': '110001.00'}),
    evAffecter(2030, '2031-04-30', {
      'reserve_legale': '-1000.00',
      'report_a_nouveau': '111000.00',
    }),
    evAffecter(2030, '2031-04-30', {'report_a_nouveau': '11o'}),
    evAffecter(2030, '2031-04-30', {
      'imputation_report_crediteur': '1000.00',
      'report_a_nouveau': '109000.00',
    }),
    evAffecter(2030, '2030-12-31', {'report_a_nouveau': '110000.00'}),
    evAffecter(2030, '2031-02-30', {'report_a_nouveau': '110000.00'}),
    evAffecter(2030, '2031-04-30', {
      'report_a_nouveau': '110000.00',
    }, role: 'administrateur'),
    {'t': 'instantane'},
    // --- l'affectation : réserve légale, autres réserves, dividendes, RAN ----
    evAffecter(2030, '2031-04-30', {
      'reserve_legale': '11000.00',
      'autres_reserves': '4000.00',
      'dividendes': '30000.00',
      'report_a_nouveau': '65000.00',
    }),
    evAffecter(2030, '2031-05-02', {'report_a_nouveau': '110000.00'}),
    evCarte(2030),
    {'t': 'bilan', 'annee': 2031},
    {'t': 'balance', 'annee': 2031},
    {'t': 'etat', 'annee': 2031},
    // --- la réouverture de N-1 est refusée sous une affectation active ------
    evGeste('rouvrir', 2030, motif: 'Correction d’un compte de 2030'),
    // --- la contre-passation : motif, comptable seul, une seule fois --------
    evContrepasser(2030, 'court'),
    evContrepasser(
      2030,
      'Ventilation rejetée en assemblée',
      role: 'administrateur',
    ),
    evContrepasser(2030, '  Ventilation rejetée en assemblée  '),
    evContrepasser(2030, 'Une seconde fois, motif long'),
    evCarte(2030),
    {'t': 'bilan', 'annee': 2031},
    {'t': 'instantane'},
    // --- une affectation contre-passée se refait ----------------------------
    evAffecter(2030, '2031-05-02', {
      'reserve_legale': '11000.00',
      'report_a_nouveau': '99000.00',
    }),
    evCarte(2030),
    {'t': 'bilan', 'annee': 2031},
    // --- 2031 : clôture (perte), puis N est clôturé ------------------------
    evGeste('demarrer', 2031),
    {'t': 'etat', 'annee': 2031},
    evGeste('cloturer', 2031),
    evContrepasser(2030, 'Trop tard pour corriger'),
    {'t': 'bilan', 'annee': 2031},
    {'t': 'bilan', 'annee': 2032},
    {'t': 'balance', 'annee': 2032},
    // --- la perte de 2031 (139) dans 2032 -----------------------------------
    evCarte(2031),
    evAffecter(2031, '2032-03-31', {'dividendes': '70000.00'}),
    evAffecter(2031, '2032-03-31', {'reserve_legale': '70000.00'}),
    evAffecter(2031, '2032-03-31', {'autres_reserves': '70000.00'}),
    evAffecter(2031, '2032-03-31', {'imputation_report_crediteur': '99000.00'}),
    evAffecter(2031, '2032-03-31', {
      'imputation_report_crediteur': '30000.00',
      'report_a_nouveau': '40000.00',
    }),
    evCarte(2031),
    {'t': 'bilan', 'annee': 2032},
    {'t': 'balance', 'annee': 2032},
    evGeste('rouvrir', 2031, motif: 'Correction d’un compte de 2031'),
    {'t': 'instantane'},
  ];

  late Map<String, dynamic> serveur;
  late List<dynamic> serveurResultats;

  setUpAll(() async {
    final cles = {
      ...MessagesAffectation.gabarits.keys,
      'comptabilite.cloture_exige_en_cloture',
    }.toList();
    serveur = await executerPhp(
      'rejouer_affectation.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'exercices': [
          {'annee': 2029, 'statut': 'ouvert'},
          {'annee': 2030, 'statut': 'ouvert'},
          {'annee': 2031, 'statut': 'ouvert'},
        ],
        'cles_messages': cles,
        'evenements': scenario,
      },
    );
    serveurResultats = serveur['resultats'] as List<dynamic>;
  });

  /* ================================================================== */
  /* Le même scénario côté poste                                         */
  /* ================================================================== */

  late AppDatabase db;
  late List<Map<String, Object?>> poste;
  late ComptabiliteDao dao;

  setUpAll(() async {
    final rejeu = await rejouerSurLePoste(scenario);
    db = rejeu.db;
    dao = rejeu.dao;
    poste = rejeu.sortie;
  });

  tearDownAll(() async {
    await db.close();
  });

  String cle(Map<String, Object?> l) => cleLigne(l);

  /* ================================================================== */
  /* Les constats                                                        */
  /* ================================================================== */

  test('le scénario du serveur a bien rendu un résultat par événement', () {
    expect(serveurResultats, hasLength(scenario.length));
    expect(poste, hasLength(scenario.length));
    // Garde contre un scénario qui ne ferait rien : de vraies affectations, de
    // vrais refus, de vraies contre-passations.
    final refus = [
      for (final r in serveurResultats)
        if ((r as Map).containsKey('refus')) r['message'] as String,
    ];
    expect(refus.length, greaterThanOrEqualTo(18));
    final reussies = serveurResultats
        .where((r) => (r as Map).containsKey('piece'))
        .length;
    expect(reussies, greaterThanOrEqualTo(4));
  });

  test('chaque événement rend le MÊME verdict : réussi, ou refusé aux mêmes '
      'mots', () {
    for (var i = 0; i < scenario.length; i++) {
      final s = serveurResultats[i] as Map<String, dynamic>;
      final p = poste[i];
      final contexte = 'événement $i : ${jsonEncode(scenario[i])}';
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
        case 'geste':
          expect(p['statut'], s['statut'], reason: contexte);
          expect(p['statuts'], s['statuts'], reason: contexte);
          expect(p['cloture'], s['cloture'], reason: contexte);
        case 'affecter':
          expect(p['piece'], s['piece'], reason: contexte);
      }
    }
  });

  test('la carte est la même : résultat, compte, proposition, plafond, '
      'affectation active, date par défaut, droit', () {
    var vues = 0;
    var avecCarte = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'etat_affectation') continue;
      vues++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      if (s['carte'] == true) avecCarte++;
      // PHP rend `proposition` en chaînes décimales, comme le poste.
      expect(poste[i], s, reason: 'carte $i : ${jsonEncode(scenario[i])}');
    }
    expect(vues, 9);
    expect(avecCarte, greaterThanOrEqualTo(7));
    // La proposition de réserve légale : 10 % de 110 000, sous le plafond.
    final propose = serveurResultats
        .whereType<Map<String, dynamic>>()
        .firstWhere((r) => r['reserve_legale_proposee'] == true);
    expect((propose['proposition'] as Map)['reserve_legale'], '11000.00');
    expect((propose['proposition'] as Map)['report_a_nouveau'], '99000.00');
  });

  test('le bilan est le même et RESTE ÉQUILIBRÉ ; le résultat reporté tombe à '
      'zéro après l’affectation intégrale', () {
    var vus = 0;
    var apresAffectation = false;
    for (var i = 0; i < scenario.length; i++) {
      final ev = scenario[i];
      if (ev['t'] == 'affecter' &&
          (serveurResultats[i] as Map).containsKey('piece')) {
        apresAffectation = true;
      }
      if (ev['t'] == 'geste' &&
          ev['action'] == 'rouvrir' &&
          !(serveurResultats[i] as Map).containsKey('refus')) {
        apresAffectation = false;
      }
      if (ev['t'] != 'bilan') continue;
      vus++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      expect(poste[i], s, reason: 'bilan $i : ${jsonEncode(ev)}');
      expect(s['equilibre'], isTrue, reason: 'bilan $i (serveur)');
      expect(s['hors_rubrique'], isEmpty, reason: 'bilan $i : compte orphelin');
    }
    expect(vus, 6);
    expect(apresAffectation, isTrue);
    // Après la première affectation (bilan 2031), le 131 est soldé.
    final premier = scenario.indexWhere((e) => e['t'] == 'bilan');
    expect((serveurResultats[premier] as Map)['resultat_reporte'], '0.00');
    expect((poste[premier])['resultat_reporte'], '0.00');
    // Après contre-passation, il retrouve le résultat de 2030.
    final second = scenario.indexWhere((e) => e['t'] == 'bilan', premier + 1);
    expect((serveurResultats[second] as Map)['resultat_reporte'], '110000.00');
    expect(poste[second]['resultat_reporte'], '110000.00');
  });

  test('la balance est la même et la liste de contrôle de N aussi', () {
    var vues = 0;
    for (var i = 0; i < scenario.length; i++) {
      final t = scenario[i]['t'];
      if (t != 'balance' && t != 'etat') continue;
      vues++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      if (t == 'balance') {
        // Le serveur ajoute `equilibree` ; le poste compare les lignes.
        expect(
          poste[i]['a_nouveaux_provisoires_de'],
          s['a_nouveaux_provisoires_de'],
          reason: 'balance $i',
        );
        expect(poste[i]['lignes'], s['lignes'], reason: 'balance $i');
        expect(s['equilibree'], isTrue, reason: 'balance $i (serveur)');
      } else {
        expect(poste[i], s, reason: '$t $i : ${jsonEncode(scenario[i])}');
      }
    }
    expect(vues, 5);
  });

  test('les lignes de la pièce d’affectation et de sa contre-passation sont '
      'les mêmes : journal OD, date, compte, centre, débit, crédit', () {
    List<String> od(Object? brut) {
      final parAnnee = (brut as Map).cast<String, dynamic>();
      return [
        for (final e in parAnnee.entries)
          for (final l in (e.value as List).cast<Map<String, dynamic>>())
            if (l['journal'] == 'OD' &&
                '${l['libelle']}'.toLowerCase().contains('affectation'))
              '${e.key}|${cle(l)}',
      ]..sort();
    }

    var vues = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'instantane') continue;
      vues++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      expect(poste[i]['statuts'], s['statuts'], reason: 'instantané $i');
      expect(od(poste[i]['lignes']), od(s['lignes']), reason: 'instantané $i');
    }
    expect(vues, 3);
    // Le dernier instantané porte les affectations et leurs inverses.
    final derniere = serveurResultats.last as Map<String, dynamic>;
    final lignes =
        [
              for (final e in (derniere['lignes'] as Map).values)
                ...(e as List).cast<Map<String, dynamic>>(),
            ]
            .where(
              (l) => '${l['libelle']}'.toLowerCase().contains('affectation'),
            )
            .toList();
    expect(lignes.where((l) => l['contrepasse'] == true), isNotEmpty);
    expect(
      lignes.map((l) => l['compte']).toSet(),
      containsAll(['131', '111', '1181', '465', '121', '139', '1291']),
    );
  });

  test('les phrases de l’affectation sont EXACTEMENT celles du serveur, des '
      'deux côtés', () {
    final messages = (serveur['messages'] as Map).cast<String, String>();
    for (final e in MessagesAffectation.gabarits.entries) {
      expect(messages[e.key], isNotNull, reason: e.key);
      expect(e.value, messages[e.key], reason: e.key);
    }
    expect(
      messages.keys.toSet().difference(
        MessagesAffectation.gabarits.keys.toSet(),
      ),
      {'comptabilite.cloture_exige_en_cloture'},
    );
  });

  test('les constantes et les rubriques sont celles du serveur', () {
    final c = serveur['constantes'] as Map<String, dynamic>;
    expect(journalAffectation, c['journal']);
    expect(roleAffectation, c['role']);
    expect(longueurMinMotifAffectation, c['motif_min']);
    expect(postesAffectation, c['postes']);
    expect(postesBenefice, c['postes_benefice']);
    expect(postesPerte, c['postes_perte']);
    expect(postesBeneficeEi, c['postes_benefice_ei']);
    expect(postesPerteEi, c['postes_perte_ei']);
    expect(prefixesCapitauxPropres, c['prefixes_capitaux_propres']);
    expect(prefixesPertesAnterieures, c['prefixes_pertes_anterieures']);
    expect(
      prefixesReservesNonDistribuables,
      c['prefixes_reserves_non_distribuables'],
    );
    expect(longueurMaxReferenceDecision, c['reference_longueur_max']);
    expect([for (final f in FormeJuridique.values) f.code], c['formes']);
    expect(centreDeCloture, c['centre']);
    // Les taux de la réserve légale : 10 % du bénéfice, 20 % du capital.
    expect(c['taux_reserve_legale'], '0.10');
    expect(c['plafond_reserve_legale'], '0.20');
    final r = serveur['rubriques'] as Map<String, dynamic>;
    // Le capital SOCIAL de l'affectation (101 seul) ; le capital du bilan, lui, couvre
    // tout le groupe 10 (compte de l'exploitant compris) : il a ses propres tests.
    expect(prefixesCapital, r['capital']);
    expect(RubriquesBilan.reserves, r['reserves']);
    expect(RubriquesBilan.reportANouveau, r['report_a_nouveau']);
    expect(RubriquesBilan.resultatReporte, r['resultat_reporte']);
    expect(RubriquesBilan.dettesCirculantes, r['dettes_circulantes']);
    expect(RubriquesBilan.dettesAssocies, r['dettes_associes']);
  });

  test('les six rôles de la correspondance existent au plan du poste et '
      'sont imputables (aucune division)', () async {
    for (final role in const [
      'RESERVE_LEGALE',
      'AUTRES_RESERVES',
      'DIVIDENDES_A_PAYER',
      'REPORT_A_NOUVEAU_CREDITEUR',
      'REPORT_A_NOUVEAU_DEBITEUR',
      'COMPTE_EXPLOITANT',
    ]) {
      final defaut = ComptesSyscohada.tous[role]!;
      expect(await dao.compteParNumero(defaut), isNotNull, reason: role);
      expect(await dao.aDesSousComptes(defaut), isFalse, reason: role);
      expect(RolesCorrespondance.parCode(role), isNotNull, reason: role);
    }
  });

  test(
    'l’affectation du poste est ENFILÉE comme une pièce saisie à la main '
    '(bloc affectation, validée), sa contre-passation comme une demande',
    () async {
      final file = await OperationsSyncDao(db).operations();
      final pieces = [
        for (final o in file)
          if (o.table == TableSynchronisee.piecesSaisie) o,
      ];
      final demandes = [
        for (final o in file)
          if (o.table == TableSynchronisee.demandesClotureExercice) o,
      ];
      final affectees = [
        for (final o in pieces)
          if (jsonDecode(o.payload) case {
            'affectation': {'annee': final int _},
          })
            jsonDecode(o.payload) as Map<String, dynamic>,
      ];
      // Trois affectations réussies au poste : deux de 2030, une de 2031.
      expect(affectees, hasLength(3));
      for (final p in affectees) {
        expect(p['journal'], 'OD');
        expect(p['statut'], 'validee');
        final v = (p['affectation'] as Map)['ventilation'] as Map;
        expect(v.values.every((m) => m is int && m >= 0), isTrue);
      }
      final annulations = [
        for (final o in demandes)
          if ((jsonDecode(o.payload) as Map)['action'] == 'annuler_affectation')
            jsonDecode(o.payload) as Map<String, dynamic>,
      ];
      expect(annulations, hasLength(1));
      expect(annulations.single['annee'], 2030);
      expect(annulations.single['motif'], 'Ventilation rejetée en assemblée');
    },
  );
}
