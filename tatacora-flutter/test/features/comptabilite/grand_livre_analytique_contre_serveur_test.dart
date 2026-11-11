@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/comptabilite/data/ecritures_serveur_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/consultation_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/grand_livre_analytique.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';

import 'support/outils_comptabilite.dart';

/// Le grand livre et l'analytique du POSTE contre les VRAIS services du
/// serveur (`GrandLivreService`, `AnalytiqueService`), au centime : soldes
/// progressifs, ouverture (provisoire, inconnue), clôture, marges par centre.
void main() {
  // (annee, journal, compte, centre, debit, credit, date, statut)
  const jeu = <(int, String, String, String, String, String, String, String)>[
    // 2030 : un exercice NON clôturé (à-nouveaux provisoires en 2031).
    (
      2030,
      'VTE',
      '5711',
      'Hébergement',
      '1000.00',
      '0.00',
      '2030-05-01',
      'validee',
    ),
    (
      2030,
      'VTE',
      '7061',
      'Hébergement',
      '0.00',
      '1000.00',
      '2030-05-01',
      'validee',
    ),
    (2030, 'ACH', '6011', 'Bar', '300.00', '0.00', '2030-06-01', 'validee'),
    (2030, 'ACH', '4011', 'Bar', '0.00', '300.00', '2030-06-01', 'validee'),
    // 2031.
    (2031, 'VTE', '5711', 'Bar', '500.50', '0.00', '2031-02-01', 'validee'),
    (2031, 'VTE', '7061', 'Bar', '0.00', '500.50', '2031-02-01', 'validee'),
    (
      2031,
      'VTE',
      '5711',
      'Hébergement',
      '0.00',
      '100.25',
      '2031-02-05',
      'validee',
    ),
    (
      2031,
      'VTE',
      '4011',
      'Hébergement',
      '100.25',
      '0.00',
      '2031-02-05',
      'validee',
    ),
    (2031, 'ACH', '6011', 'Bar', '75.10', '0.00', '2031-03-01', 'validee'),
    (2031, 'ACH', '4011', 'Bar', '0.00', '75.10', '2031-03-01', 'validee'),
    (
      2031,
      'VTE',
      '5711',
      'Hébergement',
      '999.99',
      '0.00',
      '2031-03-09',
      'brouillon',
    ),
    (
      2031,
      'VTE',
      '7061',
      'Hébergement',
      '0.00',
      '999.99',
      '2031-03-09',
      'brouillon',
    ),
    (
      2031,
      'VTE',
      '7061',
      'Hébergement',
      '20.00',
      '0.00',
      '2031-04-02',
      'validee',
    ),
    (
      2031,
      'VTE',
      '5711',
      'Hébergement',
      '0.00',
      '20.00',
      '2031-04-02',
      'validee',
    ),
    // 2032 : le précédent (2031) sera CLÔTURÉ dans un second jeu.
    (2032, 'VTE', '5711', 'Bar', '10.00', '0.00', '2032-01-15', 'validee'),
    (2032, 'VTE', '7061', 'Bar', '0.00', '10.00', '2032-01-15', 'validee'),
  ];

  const centresDuJeu = ['Hébergement', 'Bar'];

  Map<String, dynamic> entree(Map<int, String> statuts) => {
    'aujourdhui': '2031-06-15',
    'exercices': [
      for (final e in statuts.entries) {'annee': e.key, 'statut': e.value},
    ],
    'centres': [
      for (final c in centresDuJeu) {'libelle': c},
    ],
    'ecritures': [
      for (final l in jeu)
        {
          'annee': l.$1,
          'journal': l.$2,
          'compte': l.$3,
          'centre': l.$4,
          'debit': l.$5,
          'credit': l.$6,
          'date': l.$7,
          'statut': l.$8,
        },
    ],
    'grands_livres': [
      for (final filtre in ['toutes', 'validee', 'brouillon'])
        for (final c in ['5711', '7061', '6011', '4011'])
          {'annee': 2031, 'compte': c, 'filtre': filtre},
      {'annee': 2032, 'compte': '5711', 'filtre': 'toutes'},
      {'annee': 2030, 'compte': '5711', 'filtre': 'toutes'},
    ],
    'analytiques': [
      for (final filtre in ['toutes', 'validee', 'brouillon'])
        {'annee': 2031, 'filtre': filtre},
      {'annee': 2030, 'filtre': 'toutes'},
    ],
  };

  CompteDuPlan compte(String n) => CompteDuPlan(
    id: n,
    numero: n,
    libelle: 'Compte $n',
    classe: n.substring(0, 1),
    nature: null,
    centreCoutDefautId: null,
  );

  FiltreStatutEcritures filtre(String f) => switch (f) {
    'validee' => FiltreStatutEcritures.validee,
    'brouillon' => FiltreStatutEcritures.brouillon,
    _ => FiltreStatutEcritures.toutes,
  };

  int c(String s) => centimesDepuisChaine(s);

  group('contre le vrai serveur', () {
    late Map<String, dynamic> serveur;
    final statuts = {2030: 'ouvert', 2031: 'ouvert', 2032: 'ouvert'};
    final exercices = [
      for (final e in statuts.entries)
        ExerciceComptable(
          id: '${e.key}',
          annee: e.key,
          dateDebut: '${e.key}-01-01',
          dateFin: '${e.key}-12-31',
          statut: StatutExercice.depuis(e.value),
        ),
    ];
    final ecritures = [
      for (final (i, l) in jeu.indexed)
        EcritureComptable(
          id: 'e$i',
          exerciceId: '${l.$1}',
          journalId: l.$2,
          compteId: l.$3,
          centreId: l.$4,
          dateEcriture: l.$7,
          libelle: 'Ligne $i',
          debitCentimes: c(l.$5),
          creditCentimes: c(l.$6),
          statut: StatutEcriture.depuis(l.$8),
          ecritureContrepasseeId: null,
          numeroPiece: null,
          creeLe: DateTime(2031, 6, 15),
          creePar: 'u',
          modifieLe: null,
          modifiePar: null,
        ),
    ];
    final comptes = {
      for (final n in {for (final l in jeu) l.$3}) n: compte(n),
    };
    final centres = [
      for (final n in centresDuJeu)
        CentreDeCout(id: n, libelle: n, type: 'exploitation'),
    ];
    DonneesEtats etats(Map<int, StatutExercice> st) => DonneesEtats(
      ecrituresParAnnee: {
        for (final e in exercices)
          e.annee: [
            for (final l in jeu)
              if (l.$1 == e.annee && l.$8 == 'validee')
                EcritureServeur(
                  annee: l.$1,
                  codeJournal: l.$2,
                  numeroCompte: l.$3,
                  libelleCompte: 'Compte ${l.$3}',
                  classe: l.$3.substring(0, 1),
                  debitCentimes: c(l.$5),
                  creditCentimes: c(l.$6),
                ),
          ],
      },
      statutParAnnee: st,
      plan: const {},
    );

    setUpAll(() async {
      serveur = await executerPhp(
        'rejouer_grand_livre_analytique.php',
        entree: entree(statuts),
      );
    });

    test('le grand livre : lignes, soldes progressifs, ouverture et clôture, '
        'pour chaque filtre de statut', () {
      final livres = serveur['grands_livres'] as List<dynamic>;
      expect(livres, isNotEmpty);
      final d = etats({for (final e in exercices) e.annee: e.statut});
      for (final q in livres.cast<Map<String, dynamic>>()) {
        final annee = q['annee'] as int;
        final f = filtre(q['filtre'] as String);
        final portee = porteeEcritures(
          ecritures,
          exerciceId: '$annee',
          statut: f,
        );
        final report = reportOuverture(annee, d);
        final numero = q['compte'] as String;
        final livre = grandLivreDe(
          compte: comptes[numero] ?? compte(numero),
          portee: portee,
          reportCentimes: report.connu ? (report.soldes[numero] ?? 0) : null,
          reportProvisoire: report.provisoire,
          anneeReport: report.annee,
        );
        final raison = 'GL $annee $numero ${q['filtre']}';
        final lignes = (q['lignes'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(livre.lignes.length, lignes.length, reason: raison);
        for (final (i, l) in lignes.indexed) {
          expect(
            livre.lignes[i].soldeProgressifCentimes,
            c(l['solde'] as String),
            reason: '$raison ligne $i',
          );
          expect(
            livre.lignes[i].ecriture.libelle,
            l['libelle'],
            reason: raison,
          );
        }
        expect(
          livre.soldeMouvementsCentimes,
          c(q['solde_mouvements'] as String),
          reason: raison,
        );
        final ouverture = q['solde_ouverture'] as String?;
        expect(
          livre.soldeOuvertureCentimes,
          ouverture == null ? null : c(ouverture),
          reason: '$raison ouverture',
        );
        final cloture = q['solde_cloture'] as String?;
        expect(
          livre.soldeClotureCentimes,
          cloture == null ? null : c(cloture),
          reason: '$raison clôture',
        );
        expect(
          livre.ouvertureProvisoire,
          q['ouverture_provisoire'],
          reason: raison,
        );
        expect(livre.anneeOuverture, q['annee_ouverture'], reason: raison);
        expect(
          [for (final x in comptesMouvementes(portee, comptes)) x.numero],
          (q['comptes_mouvementes'] as List<dynamic>).cast<String>(),
          reason:
              '$raison — le sélecteur ne propose que les comptes mouvementés',
        );
      }
    });

    test('précédent CLÔTURÉ sans pièce d’à-nouveaux : l’ouverture est '
        'INCONNUE (« — »), jamais zéro ; les comptes de gestion repartent de '
        'zéro', () async {
      final st = {2030: 'cloture', 2031: 'cloture', 2032: 'ouvert'};
      final reponse = await executerPhp(
        'rejouer_grand_livre_analytique.php',
        entree: {
          ...entree(st),
          'grands_livres': [
            {'annee': 2032, 'compte': '5711', 'filtre': 'toutes'},
            {'annee': 2032, 'compte': '7061', 'filtre': 'toutes'},
          ],
          'analytiques': <Object>[],
        },
      );
      final d = etats({
        for (final e in exercices) e.annee: StatutExercice.depuis(st[e.annee]!),
      });
      for (final q
          in (reponse['grands_livres'] as List<dynamic>)
              .cast<Map<String, dynamic>>()) {
        final numero = q['compte'] as String;
        final report = reportOuverture(2032, d);
        final livre = grandLivreDe(
          compte: comptes[numero]!,
          portee: porteeEcritures(
            ecritures,
            exerciceId: '2032',
            statut: FiltreStatutEcritures.toutes,
          ),
          reportCentimes: report.connu ? (report.soldes[numero] ?? 0) : null,
          reportProvisoire: report.provisoire,
          anneeReport: report.annee,
        );
        final ouverture = q['solde_ouverture'] as String?;
        expect(
          livre.soldeOuvertureCentimes,
          ouverture == null ? null : c(ouverture),
          reason: numero,
        );
        expect(livre.ouvertureProvisoire, q['ouverture_provisoire']);
      }
      expect(
        (reponse['grands_livres'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .firstWhere((q) => q['compte'] == '5711')['solde_ouverture'],
        isNull,
        reason: 'le serveur dit lui aussi « inconnue » pour un compte de bilan',
      );
    });

    test('l’analytique : produits, charges, marge, taux, lignes, totaux, '
        'tri par marge décroissante', () {
      final analytiques = serveur['analytiques'] as List<dynamic>;
      expect(analytiques, isNotEmpty);
      for (final q in analytiques.cast<Map<String, dynamic>>()) {
        final annee = q['annee'] as int;
        final a = analytiqueDe(
          portee: porteeEcritures(
            ecritures,
            exerciceId: '$annee',
            statut: filtre(q['filtre'] as String),
          ),
          comptes: comptes,
          centres: centres,
        );
        final raison = 'analytique $annee ${q['filtre']}';
        final attendus = (q['centres'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        // Le serveur rend aussi les centres SANS mouvement du référentiel ?
        // Non : le GROUP BY porte sur les écritures.
        expect(a.centres.length, attendus.length, reason: raison);
        for (final (i, x) in attendus.indexed) {
          final l = a.centres[i];
          expect(l.libelle, x['libelle'], reason: raison);
          expect(
            l.produitsCentimes,
            c(x['produits'] as String),
            reason: raison,
          );
          expect(l.chargesCentimes, c(x['charges'] as String), reason: raison);
          expect(
            l.resultatCentimes,
            c(x['resultat'] as String),
            reason: raison,
          );
          expect(l.nombreLignes, x['lignes'], reason: raison);
          final taux = x['taux'] as String?;
          expect(
            l.tauxMargeDixiemes,
            taux == null ? null : (double.parse(taux) * 10).round(),
            reason: '$raison taux ${x['libelle']}',
          );
        }
        expect(a.totalProduitsCentimes, c(q['total_produits'] as String));
        expect(a.totalChargesCentimes, c(q['total_charges'] as String));
        expect(a.totalResultatCentimes, c(q['total_resultat'] as String));
      }
    });
  });
}
