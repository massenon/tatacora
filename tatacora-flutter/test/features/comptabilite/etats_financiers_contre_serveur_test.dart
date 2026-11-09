@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/tafire_notes.dart';

import 'support/outils_comptabilite.dart';

/// Compte de résultat et bilan du poste, CONFRONTÉS au vrai serveur : le même
/// jeu d'écritures validées passe par `BalanceGeneraleService`,
/// `CompteResultatService` et `BilanService` (PHP exécuté), et le poste doit
/// rendre les mêmes montants au centime — report provisoire, journal de
/// clôture, compte hors rubrique, perte comme bénéfice compris.
///
/// La cascade et les préfixes du bilan sont relus du serveur : une rubrique
/// ajoutée là-bas fait rougir ici, au lieu de laisser deux listes diverger.
typedef _L = (int, String, String, String, String, String);

void main() {
  // (année, journal, compte, débit, crédit, date)
  final jeu = <_L>[
    // 2029 — clôturé : une vente, un capital, un matériel amorti.
    (2029, 'OD', '101', '0.00', '5000000.00', '2029-01-02'),
    (2029, 'OD', '521', '5000000.00', '0.00', '2029-01-02'),
    (2029, 'OD', '231', '1200000.00', '0.00', '2029-02-01'),
    (2029, 'OD', '521', '0.00', '1200000.00', '2029-02-01'),
    (2029, 'VTE', '411', '300000.00', '0.00', '2029-06-01'),
    (2029, 'VTE', '706', '0.00', '300000.00', '2029-06-01'),
    // 2030 — en clôture, déficitaire : charges > produits.
    (2030, 'AN', '101', '0.00', '5000000.00', '2030-01-01'),
    (2030, 'AN', '521', '3800000.00', '0.00', '2030-01-01'),
    (2030, 'AN', '231', '1200000.00', '0.00', '2030-01-01'),
    (2030, 'AN', '411', '300000.00', '0.00', '2030-01-01'),
    (2030, 'VTE', '5711', '250000.00', '0.00', '2030-03-05'),
    (2030, 'VTE', '706', '0.00', '200000.00', '2030-03-05'),
    (2030, 'VTE', '4431', '0.00', '50000.00', '2030-03-05'),
    (2030, 'ACH', '601', '900000.00', '0.00', '2030-04-02'),
    (2030, 'ACH', '4011', '0.00', '900000.00', '2030-04-02'),
    (2030, 'OD', '661', '400000.00', '0.00', '2030-05-31'),
    (2030, 'OD', '421', '0.00', '400000.00', '2030-05-31'),
    (2030, 'OD', '681', '120000.00', '0.00', '2030-12-31'),
    (2030, 'OD', '281', '0.00', '120000.00', '2030-12-31'),
    (2030, 'OD', '671', '15000.00', '0.00', '2030-12-31'),
    (2030, 'OD', '561', '0.00', '15000.00', '2030-12-31'),
    // Un compte que AUCUNE rubrique ne capte (4811) : le cas « hors
    // nomenclature » ; 4431 n'en est plus un depuis le 09/11/2026.
    (2030, 'OD', '4811', '0.00', '30000.00', '2030-09-01'),
    (2030, 'OD', '5711', '30000.00', '0.00', '2030-09-01'),
    (2030, 'CL', '706', '200000.00', '0.00', '2030-12-31'),
    (2030, 'CL', '131', '0.00', '200000.00', '2030-12-31'),
    // 2031 — ouvert : bénéfice, hors activités ordinaires et impôt.
    (2031, 'VTE', '5711', '1500000.00', '0.00', '2031-02-01'),
    (2031, 'VTE', '706', '0.00', '1300000.00', '2031-02-01'),
    (2031, 'VTE', '707', '0.00', '200000.00', '2031-02-01'),
    (2031, 'ACH', '31', '80000.00', '0.00', '2031-03-01'),
    (2031, 'ACH', '4011', '0.00', '80000.00', '2031-03-01'),
    (2031, 'VTE', '411', '90000.00', '0.00', '2031-04-01'),
    (2031, 'VTE', '4191', '0.00', '90000.00', '2031-04-01'),
    (2031, 'OD', '82', '0.00', '60000.00', '2031-05-01'),
    (2031, 'OD', '521', '60000.00', '0.00', '2031-05-01'),
    (2031, 'OD', '87', '10000.00', '0.00', '2031-06-01'),
    (2031, 'OD', '447', '0.00', '10000.00', '2031-06-01'),
    (2031, 'OD', '89', '30000.00', '0.00', '2031-06-10'),
    (2031, 'OD', '447', '0.00', '30000.00', '2031-06-10'),
    (2031, 'OD', '622', '45000.00', '0.00', '2031-06-12'),
    (2031, 'OD', '521', '0.00', '45000.00', '2031-06-12'),
    // TVA : collectée (443), due (4441), récupérable (445), crédit à reporter (4449).
    (2031, 'VTE', '5711', '118000.00', '0.00', '2031-07-01'),
    (2031, 'VTE', '706', '0.00', '100000.00', '2031-07-01'),
    (2031, 'VTE', '4432', '0.00', '18000.00', '2031-07-01'),
    (2031, 'OD', '4452', '9000.00', '0.00', '2031-07-02'),
    (2031, 'OD', '4441', '0.00', '4000.00', '2031-07-02'),
    (2031, 'OD', '4449', '2500.00', '0.00', '2031-07-02'),
    (2031, 'OD', '521', '0.00', '7500.00', '2031-07-02'),
    // Dividendes à payer (465) : décidés puis réglés en partie — la note 4
    // les porte comme le bilan (10/11/2026).
    (2031, 'OD', '111', '40000.00', '0.00', '2031-08-01'),
    (2031, 'OD', '465', '0.00', '40000.00', '2031-08-01'),
    (2031, 'OD', '465', '15000.00', '0.00', '2031-08-20'),
    (2031, 'OD', '521', '0.00', '15000.00', '2031-08-20'),
    // 2032 — ouvert, une seule écriture : tout le reste est reporté.
    (2032, 'VTE', '5711', '10000.00', '0.00', '2032-01-05'),
    (2032, 'VTE', '706', '0.00', '10000.00', '2032-01-05'),
  ];
  const statuts = <int, String>{
    2029: 'cloture',
    2030: 'en_cloture',
    2031: 'ouvert',
    2032: 'ouvert',
  };
  const annees = [2032, 2031, 2030, 2029];

  late Map<String, dynamic> serveur;
  late DonneesEtats donnees;

  int cts(Object? v) => centimesDepuisChaine('$v');

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_etats_financiers.php',
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
    final plan = serveur['plan'] as Map<String, dynamic>;
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
      plan: {
        for (final e in plan.entries)
          e.key: CompteDeReport(
            libelle: (e.value as Map)['libelle'] as String,
            classe: (e.value as Map)['classe'] as String,
          ),
      },
    );
  });

  test('la cascade et les préfixes du bilan sont ceux du serveur', () {
    final distante = (serveur['cascade'] as List).cast<Map<String, dynamic>>();
    expect(distante, hasLength(cascadeResultat.length));
    for (var i = 0; i < distante.length; i++) {
      final d = distante[i];
      final r = cascadeResultat[i];
      expect(r.code, d['code'], reason: 'rang $i');
      expect(r.libelle, d['libelle'], reason: r.code);
      expect(r.sens.name, d['sens'], reason: r.code);
      expect(r.prefixes, (d['prefixes'] as List?) ?? const [], reason: r.code);
      expect(
        r.composants,
        (d['composants'] as List?) ?? const [],
        reason: r.code,
      );
    }
    final rub = serveur['rubriques'] as Map<String, dynamic>;
    expect(RubriquesBilan.immobilisationsBrutes, rub['immobilisations_brutes']);
    expect(RubriquesBilan.amortissements, rub['amortissements']);
    expect(RubriquesBilan.stocks, rub['stocks']);
    expect(RubriquesBilan.creances, rub['creances']);
    expect(RubriquesBilan.tresorerieActif, rub['tresorerie_actif']);
    expect(RubriquesBilan.capital, rub['capital']);
    expect(RubriquesBilan.resultatReporte, rub['resultat_reporte']);
    expect(RubriquesBilan.dettesCirculantes, rub['dettes_circulantes']);
    expect(RubriquesBilan.dettesAssocies, rub['dettes_associes']);
    expect(RubriquesBilan.tresoreriePassif, rub['tresorerie_passif']);
    expect(rubriqueDotations, rub['dotations_amortissements']);
  });

  // Note annexe 4 (10/11/2026) : le 465 est une ligne de la note, au libellé du
  // PLAN (le même que celui du web), et le total des dettes de la note est le
  // passif circulant du bilan (465 compris). Les écritures portent ici le
  // libellé du plan, pas le numéro : c'est ce qui rend le libellé comparable.
  for (final annee in [2031, 2032]) {
    test('note 4 $annee : le 465 figure, libellé du serveur, total des dettes '
        '= passif circulant du bilan', () {
      final plan = serveur['libelles_plan'] as Map<String, dynamic>;
      String libelle(String compte) => plan[compte] as String;
      final avecLibelles = DonneesEtats(
        ecrituresParAnnee: {
          for (final e in donnees.ecrituresParAnnee.entries)
            e.key: [
              for (final x in e.value)
                EcritureServeur(
                  annee: x.annee,
                  codeJournal: x.codeJournal,
                  numeroCompte: x.numeroCompte,
                  libelleCompte: libelle(x.numeroCompte),
                  classe: x.classe,
                  debitCentimes: x.debitCentimes,
                  creditCentimes: x.creditCentimes,
                ),
            ],
        },
        statutParAnnee: donnees.statutParAnnee,
        plan: donnees.plan,
      );
      final attendues =
          ((serveur['etats'] as Map<String, dynamic>)['$annee']
                  as Map<String, dynamic>)['notes']
              as List;
      final serveur4 =
          ((attendues.cast<Map<String, dynamic>>().firstWhere(
                    (n) => n['numero'] == 4,
                  ))['postes']
                  as List)
              .cast<Map<String, dynamic>>();
      final poste4 = notesDe(
        annee,
        avecLibelles,
      ).firstWhere((n) => n.numero == 4).postes;

      // Les libellés, au mot près, comme le web les écrit.
      expect(
        [for (final p in poste4) p.libelle],
        [for (final p in serveur4) p['libelle']],
      );
      final ligne465 = poste4.where((p) => p.libelle.endsWith('(465)'));
      expect(ligne465, hasLength(1), reason: 'le 465 doit être une ligne');
      expect(ligne465.single.libelle, '${libelle('465')} (465)');
      if (annee == 2031) {
        expect(ligne465.single.montantCentimes, cts('25000.00'));
      }

      // Cohérence avec le bilan : toutes les dettes du bilan sont dans la note.
      final prefixesDettes = [
        ...RubriquesBilan.dettesCirculantes,
        ...RubriquesBilan.dettesAssocies,
      ];
      final totalNote = poste4
          .where(
            (p) => prefixesDettes.any(
              RegExp(r'\((\d+)\)$').firstMatch(p.libelle)![1]!.startsWith,
            ),
          )
          .fold(0, (t, p) => t + p.montantCentimes);
      final passifCirculant = bilanDe(
        annee,
        avecLibelles,
      ).passif.firstWhere((p) => p.code == 'passif_circulant');
      expect(totalNote, passifCirculant.netCentimes);
    });
  }

  for (final annee in annees) {
    group('exercice $annee', () {
      Map<String, dynamic> etat() =>
          (serveur['etats'] as Map<String, dynamic>)['$annee']
              as Map<String, dynamic>;

      test('balance : mêmes comptes, mêmes totaux, même report provisoire', () {
        final b = etat()['balance'] as Map<String, dynamic>;
        final poste = balanceDe(annee, donnees);
        expect(poste.aNouveauxProvisoiresDe, b['a_nouveaux_provisoires_de']);
        final lignes = (b['lignes'] as List).cast<Map<String, dynamic>>();
        expect(poste.lignes, hasLength(lignes.length));
        for (var i = 0; i < lignes.length; i++) {
          expect(poste.lignes[i].numeroCompte, lignes[i]['numero_compte']);
          expect(poste.lignes[i].debitCentimes, cts(lignes[i]['debit']));
          expect(poste.lignes[i].creditCentimes, cts(lignes[i]['credit']));
        }
      });

      test('TAFIRE : ressources, emplois, BFR, variation et cohérence', () {
        final t = etat()['tafire'] as Map<String, dynamic>;
        final poste = tafireDe(annee, donnees);
        expect(poste.resultatExerciceCentimes, cts(t['resultat']));
        expect(poste.dotationsCentimes, cts(t['dotations']));
        expect(poste.cafgCentimes, cts(t['cafg']));
        expect(poste.augmentationCapitalCentimes, cts(t['capital']));
        expect(poste.totalRessourcesCentimes, cts(t['ressources']));
        expect(poste.acquisitionsCentimes, cts(t['acquisitions']));
        expect(poste.totalEmploisCentimes, cts(t['emplois']));
        expect(poste.variationStocksCentimes, cts(t['stocks']));
        expect(poste.variationCreancesCentimes, cts(t['creances']));
        expect(poste.variationDettesCentimes, cts(t['dettes']));
        expect(poste.variationBfrCentimes, cts(t['bfr']));
        expect(poste.variationCalculeeCentimes, cts(t['calculee']));
        expect(poste.variationReelleCentimes, cts(t['reelle']));
        expect(poste.ecartCentimes, cts(t['ecart']));
        expect(poste.coherent, t['coherent']);
      });

      test(
        'notes annexes : sept notes, leurs postes, ouverture et variation',
        () {
          final attendues = (etat()['notes'] as List)
              .cast<Map<String, dynamic>>();
          final notes = notesDe(annee, donnees);
          expect(notes, hasLength(attendues.length));
          for (final (i, a) in attendues.indexed) {
            final n = notes[i];
            final raison = 'note ${a['numero']}';
            expect(n.numero, a['numero'], reason: raison);
            expect(n.titre, a['titre'], reason: raison);
            expect(n.etat.name, switch (a['etat']) {
              'non_saisie' => 'nonSaisie',
              final String e => e,
              _ => '',
            }, reason: raison);
            expect(n.motif, a['motif'], reason: raison);
            expect(n.texte, a['texte'], reason: raison);
            final postes = (a['postes'] as List).cast<Map<String, dynamic>>();
            expect(n.postes, hasLength(postes.length), reason: raison);
            for (final (j, p) in postes.indexed) {
              final poste = n.postes[j];
              // Le libellé du jeu est le numéro de compte : « 231 (231) ».
              expect(
                RegExp(r'\((\d+)\)$').firstMatch(poste.libelle)![1],
                (p['prefixes'] as List).single,
                reason: raison,
              );
              expect(poste.montantCentimes, cts(p['montant']), reason: raison);
              expect(
                poste.ouvertureCentimes,
                p['ouverture'] == null ? null : cts(p['ouverture']),
                reason: '$raison ouverture',
              );
              expect(
                poste.variationCentimes,
                p['variation'] == null ? null : cts(p['variation']),
                reason: '$raison variation',
              );
            }
          }
        },
      );

      test('compte de résultat : chaque ligne, avant impôt, impôt, net', () {
        final r = etat()['resultat'] as Map<String, dynamic>;
        final poste = compteResultatDe(annee, donnees);
        final lignes = (r['lignes'] as List).cast<Map<String, dynamic>>();
        expect(poste.lignes, hasLength(lignes.length));
        for (var i = 0; i < lignes.length; i++) {
          expect(poste.lignes[i].rubrique.code, lignes[i]['code']);
          expect(
            poste.lignes[i].montantCentimes,
            cts(lignes[i]['montant']),
            reason: '${lignes[i]['code']}',
          );
        }
        expect(poste.resultatAvantImpotCentimes, cts(r['avant_impot']));
        expect(poste.impotCentimes, cts(r['impot']));
        expect(poste.resultatNetCentimes, cts(r['net']));
        expect(poste.impotNonComptabilise, r['impot_non_comptabilise']);
      });

      test(
        'bilan : postes, totaux, écart, résultat, comptes hors rubrique',
        () {
          final b = etat()['bilan'] as Map<String, dynamic>;
          final poste = bilanDe(annee, donnees);
          void postes(List<PosteBilanEtat> p, List<dynamic> d) {
            expect(p, hasLength(d.length));
            for (var i = 0; i < d.length; i++) {
              final m = d[i] as Map<String, dynamic>;
              expect(p[i].code, m['code']);
              expect(p[i].brutCentimes, cts(m['brut']), reason: '${m['code']}');
              expect(
                p[i].amortissementCentimes,
                cts(m['amortissement']),
                reason: '${m['code']}',
              );
              expect(p[i].netCentimes, cts(m['net']), reason: '${m['code']}');
            }
          }

          postes(poste.actif, b['actif'] as List);
          postes(poste.passif, b['passif'] as List);
          expect(poste.totalActifBrutCentimes, cts(b['total_actif_brut']));
          expect(
            poste.totalActifAmortissementCentimes,
            cts(b['total_actif_amortissement']),
          );
          expect(poste.totalActifCentimes, cts(b['total_actif']));
          expect(poste.totalPassifCentimes, cts(b['total_passif']));
          expect(poste.equilibre, b['equilibre']);
          expect(poste.ecartCentimes, cts(b['ecart']));
          expect(poste.resultatExerciceCentimes, cts(b['resultat_exercice']));
          expect(poste.impotNonComptabilise, b['impot_non_comptabilise']);
          final hors = (b['hors_rubrique'] as List)
              .cast<Map<String, dynamic>>();
          expect(
            [for (final h in poste.comptesHorsRubrique) h.numeroCompte],
            [for (final h in hors) h['numero_compte']],
          );
          for (var i = 0; i < hors.length; i++) {
            expect(
              poste.comptesHorsRubrique[i].soldeCentimes,
              cts(hors[i]['solde']),
            );
          }
        },
      );
    });
  }

  test('le jeu est assez riche : perte, bénéfice, impôt, hors rubrique, '
      'report en chaîne', () {
    expect(compteResultatDe(2030, donnees).resultatNetCentimes, isNegative);
    expect(compteResultatDe(2031, donnees).resultatNetCentimes, isPositive);
    expect(compteResultatDe(2031, donnees).impotNonComptabilise, isFalse);
    expect(compteResultatDe(2030, donnees).impotNonComptabilise, isTrue);
    expect(bilanDe(2030, donnees).comptesHorsRubrique, isNotEmpty);
    // 09/11/2026 : la TVA collectée (443/4432), due (4441), récupérable (445)
    // et à reporter (4449) ont une rubrique : le bilan 2031, qui en porte, ne
    // liste en « hors nomenclature » que le 4811 reporté de 2030 (mutation :
    // retirer '443' ou '445' fait apparaître 4432 / 4452 ici).
    expect(
      bilanDe(2031, donnees).comptesHorsRubrique.map((c) => c.numeroCompte),
      ['4811'],
    );
    expect(balanceDe(2031, donnees).aNouveauxProvisoiresDe, 2030);
    expect(balanceDe(2032, donnees).aNouveauxProvisoiresDe, 2031);
    expect(balanceDe(2030, donnees).aNouveauxProvisoiresDe, isNull);
  });
}
