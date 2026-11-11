@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/tafire_notes.dart';

import 'support/outils_comptabilite.dart';

/// Le TAFIRE du poste sur le RÉSULTAT DE N SEUL (10/11/2026), confronté au vrai
/// `TafireService` (PHP exécuté, `tool/etats/rejouer_tafire.php`) sur un jeu qui
/// porte : un exercice clôturé dont les à-nouveaux (131 compris) sont écrits en
/// AN, puis, dans l'exercice suivant, une cession, un emprunt, un achat de stock,
/// l'AFFECTATION du résultat de N-1 écrite à la main (D 131 / C 121, 111, 118,
/// 465) et un règlement partiel des dividendes ; enfin un exercice de plus dont
/// le précédent n'est pas clôturé (à-nouveaux provisoires). Tous les champs se
/// comparent au centime, et le TAFIRE doit être ÉQUILIBRÉ partout.
///
/// Avis de l'expert-comptable (10/11/2026) : l'exercice 2031 porte aussi une
/// provision financière dotée (697 / 19) puis reprise, une subvention
/// d'investissement reçue (14) avec sa quote-part virée (14 / 799), le compte de
/// l'exploitant (104 : apport, prélèvement, bénéfice de 2030 affecté), une dette
/// de participation (18), des dotations HAO (851 / 15, 852 / 281, 854 / 19), une
/// reprise d'amortissement (798) et un transfert de charges (781) porté à
/// l'immobilisation. Le 19 n'est dans aucun flux de financement ; le 465 reste
/// hors du BFR.
typedef _L = (int, String, String, String, String, String);

void main() {
  final jeu = <_L>[
    // 2030 — clôturé : capital, matériel, vente, charge, dotation (résultat +130 000).
    (2030, 'OD', '521', '5000000.00', '0.00', '2030-01-02'),
    (2030, 'OD', '101', '0.00', '5000000.00', '2030-01-02'),
    (2030, 'OD', '231', '1200000.00', '0.00', '2030-02-01'),
    (2030, 'OD', '521', '0.00', '1200000.00', '2030-02-01'),
    (2030, 'VTE', '411', '300000.00', '0.00', '2030-06-01'),
    (2030, 'VTE', '706', '0.00', '300000.00', '2030-06-01'),
    (2030, 'ACH', '601', '50000.00', '0.00', '2030-07-01'),
    (2030, 'ACH', '401', '0.00', '50000.00', '2030-07-01'),
    (2030, 'OD', '681', '120000.00', '0.00', '2030-12-30'),
    (2030, 'OD', '281', '0.00', '120000.00', '2030-12-30'),
    // 2031 — en clôture : à-nouveaux AN (131 = résultat de 2030, NON affecté).
    (2031, 'AN', '521', '3800000.00', '0.00', '2031-01-01'),
    (2031, 'AN', '231', '1200000.00', '0.00', '2031-01-01'),
    (2031, 'AN', '411', '300000.00', '0.00', '2031-01-01'),
    (2031, 'AN', '101', '0.00', '5000000.00', '2031-01-01'),
    (2031, 'AN', '401', '0.00', '50000.00', '2031-01-01'),
    (2031, 'AN', '281', '0.00', '120000.00', '2031-01-01'),
    (2031, 'AN', '131', '0.00', '130000.00', '2031-01-01'),
    // acquisition
    (2031, 'OD', '231', '400000.00', '0.00', '2031-02-01'),
    (2031, 'OD', '521', '0.00', '400000.00', '2031-02-01'),
    // cession : brut 100 000, amorti 60 000, VNC 40 000, prix 50 000
    (2031, 'OD', '521', '50000.00', '0.00', '2031-03-01'),
    (2031, 'OD', '281', '60000.00', '0.00', '2031-03-01'),
    (2031, 'OD', '81', '40000.00', '0.00', '2031-03-01'),
    (2031, 'OD', '231', '0.00', '100000.00', '2031-03-01'),
    (2031, 'OD', '82', '0.00', '50000.00', '2031-03-01'),
    // emprunt
    (2031, 'OD', '521', '1000000.00', '0.00', '2031-03-15'),
    (2031, 'OD', '162', '0.00', '1000000.00', '2031-03-15'),
    // exploitation
    (2031, 'VTE', '521', '200000.00', '0.00', '2031-04-01'),
    (2031, 'VTE', '706', '0.00', '200000.00', '2031-04-01'),
    (2031, 'ACH', '601', '60000.00', '0.00', '2031-04-02'),
    (2031, 'ACH', '521', '0.00', '60000.00', '2031-04-02'),
    (2031, 'OD', '681', '130000.00', '0.00', '2031-12-30'),
    (2031, 'OD', '281', '0.00', '130000.00', '2031-12-30'),
    (2031, 'OD', '521', '100000.00', '0.00', '2031-05-01'),
    (2031, 'OD', '411', '0.00', '100000.00', '2031-05-01'),
    (2031, 'ACH', '31', '20000.00', '0.00', '2031-05-02'),
    (2031, 'ACH', '401', '0.00', '20000.00', '2031-05-02'),
    // affectation du résultat de 2030 (+130 000), écrite à la main
    (2031, 'OD', '131', '130000.00', '0.00', '2031-06-01'),
    (2031, 'OD', '121', '0.00', '30000.00', '2031-06-01'),
    (2031, 'OD', '111', '0.00', '10000.00', '2031-06-01'),
    (2031, 'OD', '118', '0.00', '20000.00', '2031-06-01'),
    (2031, 'OD', '465', '0.00', '70000.00', '2031-06-01'),
    // règlement partiel des dividendes
    (2031, 'OD', '465', '30000.00', '0.00', '2031-06-20'),
    (2031, 'OD', '521', '0.00', '30000.00', '2031-06-20'),
    // provision financière dotée puis reprise : aucun flux de financement
    (2031, 'OD', '697', '30000.00', '0.00', '2031-07-01'),
    (2031, 'OD', '19', '0.00', '30000.00', '2031-07-01'),
    (2031, 'OD', '19', '5000.00', '0.00', '2031-07-02'),
    (2031, 'OD', '797', '0.00', '5000.00', '2031-07-02'),
    // subvention d'investissement reçue, puis sa quote-part virée au résultat
    (2031, 'OD', '521', '200000.00', '0.00', '2031-07-03'),
    (2031, 'OD', '14', '0.00', '200000.00', '2031-07-03'),
    (2031, 'OD', '14', '40000.00', '0.00', '2031-12-31'),
    (2031, 'OD', '799', '0.00', '40000.00', '2031-12-31'),
    // compte de l'exploitant : apport, prélèvement, bénéfice de 2030 (30 000 de report à nouveau en 121 ci-dessus)
    (2031, 'OD', '521', '60000.00', '0.00', '2031-07-04'),
    (2031, 'OD', '104', '0.00', '60000.00', '2031-07-04'),
    (2031, 'OD', '104', '10000.00', '0.00', '2031-07-05'),
    (2031, 'OD', '521', '0.00', '10000.00', '2031-07-05'),
    // dette de participation (18)
    (2031, 'OD', '521', '70000.00', '0.00', '2031-07-06'),
    (2031, 'OD', '18', '0.00', '70000.00', '2031-07-06'),
    // dotations HAO : provisions réglementées, amortissement, provision
    (2031, 'OD', '851', '8000.00', '0.00', '2031-12-30'),
    (2031, 'OD', '15', '0.00', '8000.00', '2031-12-30'),
    (2031, 'OD', '852', '6000.00', '0.00', '2031-12-30'),
    (2031, 'OD', '281', '0.00', '6000.00', '2031-12-30'),
    (2031, 'OD', '854', '4000.00', '0.00', '2031-12-30'),
    (2031, 'OD', '19', '0.00', '4000.00', '2031-12-30'),
    // reprise d'amortissement (798) et transfert de charges (781) porté à l'actif
    (2031, 'OD', '281', '2000.00', '0.00', '2031-12-31'),
    (2031, 'OD', '798', '0.00', '2000.00', '2031-12-31'),
    (2031, 'OD', '622', '9000.00', '0.00', '2031-12-31'),
    (2031, 'OD', '521', '0.00', '9000.00', '2031-12-31'),
    (2031, 'OD', '231', '9000.00', '0.00', '2031-12-31'),
    (2031, 'OD', '781', '0.00', '9000.00', '2031-12-31'),
    // 2032 — ouvert, précédent non clôturé : à-nouveaux provisoires.
    (2032, 'VTE', '521', '10000.00', '0.00', '2032-01-05'),
    (2032, 'VTE', '706', '0.00', '10000.00', '2032-01-05'),
  ];
  const statuts = <int, String>{
    2030: 'cloture',
    2031: 'en_cloture',
    2032: 'ouvert',
  };
  const annees = [2032, 2031, 2030];

  late Map<String, dynamic> serveur;
  late DonneesEtats donnees;

  int cts(Object? v) => centimesDepuisChaine('$v');

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_tafire.php',
      dossier: 'etats',
      entree: {
        'aujourdhui': '2031-06-15',
        'exercices': [
          for (final e in statuts.entries) {'annee': e.key, 'statut': e.value},
        ],
        'ecritures': [
          for (final l in jeu)
            {
              'annee': l.$1,
              'journal': l.$2,
              'compte': l.$3,
              'debit': l.$4,
              'credit': l.$5,
              'date': l.$6,
            },
        ],
        'annees': annees,
      },
    );
    donnees = DonneesEtats(
      ecrituresParAnnee: {
        for (final a in annees)
          a: [
            for (final l in jeu.where((l) => l.$1 == a))
              EcritureServeur(
                annee: a,
                codeJournal: l.$2,
                numeroCompte: l.$3,
                libelleCompte: l.$3,
                classe: l.$3.substring(0, 1),
                debitCentimes: cts(l.$4),
                creditCentimes: cts(l.$5),
              ),
          ],
      },
      statutParAnnee: {
        for (final e in statuts.entries) e.key: StatutExercice.depuis(e.value),
      },
      plan: const {
        '131': CompteDeReport(libelle: 'Résultat net : bénéfice', classe: '1'),
        '139': CompteDeReport(libelle: 'Résultat net : perte', classe: '1'),
      },
    );
  });

  test('les préfixes propres au TAFIRE sont ceux du serveur', () {
    final r = serveur['rubriques'] as Map<String, dynamic>;
    expect(RubriquesTafire.dotations, r['dotations']);
    expect(RubriquesTafire.reprises, r['reprises']);
    expect(
      RubriquesTafire.dotationsAmortissements,
      r['dotations_amortissements'],
    );
    expect(
      RubriquesTafire.reprisesSurImmobilisations,
      r['reprises_sur_immobilisations'],
    );
    expect(RubriquesTafire.quotePartSubventions, r['quote_part_subventions']);
    expect(RubriquesTafire.dettesParticipations, r['dettes_participations']);
    expect(
      RubriquesTafire.valeurComptableCessions,
      r['valeur_comptable_cessions'],
    );
    expect(RubriquesTafire.produitsCessions, r['produits_cessions']);
    expect(RubriquesTafire.apportsCapital, r['apports_capital']);
    expect(RubriquesTafire.autresCapitauxPropres, r['autres_capitaux_propres']);
    expect(RubriquesTafire.dettesFinancieres, r['dettes_financieres']);
    expect(RubriquesTafire.dividendesAPayer, r['dividendes_a_payer']);
  });

  for (final annee in annees) {
    test('TAFIRE $annee : tous les champs du serveur, au centime', () {
      final t =
          (serveur['etats'] as Map<String, dynamic>)['$annee']
              as Map<String, dynamic>;
      final p = tafireDe(annee, donnees);
      expect(p.resultatExerciceCentimes, cts(t['resultat']));
      expect(p.dotationsCentimes, cts(t['dotations']));
      expect(p.reprisesCentimes, cts(t['reprises']));
      expect(p.valeurComptableCessionsCentimes, cts(t['vnc_cessions']));
      expect(p.quotePartSubventionsCentimes, cts(t['quote_part_subventions']));
      expect(
        p.variationDettesParticipationsCentimes,
        cts(t['dettes_participations']),
      );
      expect(p.cafgCentimes, cts(t['cafg']));
      expect(p.produitsCessionsCentimes, cts(t['produits_cessions']));
      expect(p.augmentationCapitalCentimes, cts(t['capital']));
      expect(p.variationEmpruntsCentimes, cts(t['emprunts']));
      expect(p.totalRessourcesCentimes, cts(t['ressources']));
      expect(p.acquisitionsCentimes, cts(t['acquisitions']));
      expect(
        p.variationAutresCapitauxPropresCentimes,
        cts(t['autres_capitaux_propres']),
      );
      expect(p.variationDividendesAPayerCentimes, cts(t['dividendes_a_payer']));
      expect(p.dividendesVersesCentimes, cts(t['dividendes_verses']));
      expect(p.totalEmploisCentimes, cts(t['emplois']));
      expect(p.fluxExploitationCentimes, cts(t['flux_exploitation']));
      expect(p.fluxInvestissementCentimes, cts(t['flux_investissement']));
      expect(p.fluxFinancementCentimes, cts(t['flux_financement']));
      expect(p.variationStocksCentimes, cts(t['stocks']));
      expect(p.variationCreancesCentimes, cts(t['creances']));
      expect(p.variationDettesCentimes, cts(t['dettes']));
      expect(p.variationBfrCentimes, cts(t['bfr']));
      expect(p.variationCalculeeCentimes, cts(t['calculee']));
      expect(p.variationReelleCentimes, cts(t['reelle']));
      expect(p.ecartCentimes, cts(t['ecart']));
      // ÉQUILIBRÉ au serveur comme au poste, et les trois flux somment la variation.
      expect(t['coherent'], isTrue);
      expect(p.coherent, isTrue);
      expect(
        p.fluxExploitationCentimes +
            p.fluxInvestissementCentimes +
            p.fluxFinancementCentimes,
        p.variationReelleCentimes,
      );
    });
  }

  test('2031 : résultat de N seul, affectation de N-1 au financement', () {
    final p = tafireDe(2031, donnees);
    // 200 000 − 60 000 − 130 000 + 50 000 − 40 000 : le 131 de 2030 n'y est pas ;
    // puis l'avis du 10/11/2026 : −30 000 (697) + 5 000 (797) + 40 000 (799) −
    // 8 000 (851) − 6 000 (852) − 4 000 (854) + 2 000 (798) − 9 000 (622) + 9 000
    // (781) = −1 000.
    expect(p.resultatExerciceCentimes, 1900000);
    // CAFG = 19 000 + dotations 178 000 − reprises 16 000 + VNC 40 000 − cessions
    // 50 000 − quote-part 40 000 (produit non encaissé).
    expect(p.dotationsCentimes, 17800000);
    expect(p.reprisesCentimes, 1600000);
    expect(p.quotePartSubventionsCentimes, 4000000);
    expect(p.cafgCentimes, 13100000);
    // 131 −130 000, 121 +30 000, 111 +10 000, 118 +20 000, 104 +60 000 − 10 000 ;
    // 465 : +70 000 − 30 000 ; le 15 (8 000) n'est PAS un dividende.
    expect(p.variationAutresCapitauxPropresCentimes, -2000000);
    expect(p.variationDividendesAPayerCentimes, 4000000);
    expect(p.dividendesVersesCentimes, -2000000);
    // Le 19 (+29 000) n'est ni un emprunt ni une acquisition ; le 18 a sa ligne.
    expect(p.variationEmpruntsCentimes, 100000000);
    expect(p.variationDettesParticipationsCentimes, 7000000);
    // Subvention reçue 200 000 (14 : +200 000 − 40 000, + quote-part 40 000).
    expect(p.augmentationCapitalCentimes, 20000000);
    expect(p.acquisitionsCentimes, 40000000);
    expect(p.variationReelleCentimes, 117100000);
  });
}
