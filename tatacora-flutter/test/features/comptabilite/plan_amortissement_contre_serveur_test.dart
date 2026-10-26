@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/immobilisations_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/immobilisations.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';

import 'support/outils_comptabilite.dart';

/// Le plan d'amortissement et le tableau du poste, CONFRONTÉS au vrai
/// `ImmobilisationService` : les mêmes biens passent par le service (PHP
/// exécuté), et le poste doit rendre les mêmes annuités, cumuls et VNC au
/// centime — prorata en mois entamés, arrondi absorbé par la dernière annuité,
/// annuité nulle sautée, valeurs au-delà de 64 bits comprises. Les refus de la
/// création sont ceux du service, mot pour mot.
void main() {
  // (libellé, valeur en francs décimaux, durée, mise en service)
  const biens = <(String, String, int, String)>[
    ('Toyota Land Cruiser Prado', '1200000.00', 5, '2026-03-20'),
    ('Janvier plein', '1000000.00', 3, '2026-01-01'),
    ('Décembre un seul mois', '1000000.00', 3, '2026-12-31'),
    ('Arrondi 7 ans', '100.00', 7, '2026-05-15'),
    ('Annuité nulle', '0.05', 3, '2026-06-10'),
    ('Un centime', '0.01', 1, '2026-02-02'),
    ('Tiers de centime', '1000.01', 3, '2027-04-04'),
    ('Très grande valeur', '9999999999999.99', 13, '2026-07-07'),
    ('Grande valeur, 9 ans', '123456789012.34', 9, '2028-09-09'),
    ('Durée longue', '5000000.00', 60, '2026-11-30'),
    ('Année suivante', '750000.50', 4, '2030-08-01'),
  ];
  const annees = [2026, 2027, 2028, 2030, 2031, 2035, 2090];

  late Map<String, dynamic> serveur;
  late List<Immobilisation> locales;

  int cts(Object? v) => centimesDepuisChaine('$v');

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_immobilisations.php',
      entree: {
        'biens': [
          for (final b in biens)
            {
              'libelle': b.$1,
              'valeur': b.$2,
              'duree': b.$3,
              'date': b.$4,
              'compte': null,
            },
        ],
        'annees': annees,
        'recherches': ['prado', 'IMMO-2026-0000', 'zzz', 'GRANDE'],
        'refus': [
          {'libelle': ''},
          {'libelle': '   ', 'valeur_origine': '5'},
          {'libelle': 'x', 'valeur_origine': '0'},
          {'libelle': 'x', 'valeur_origine': '-5', 'duree_annees': 2},
          {'libelle': 'x', 'valeur_origine': '5', 'duree_annees': 0},
          {
            'libelle': 'x',
            'valeur_origine': '5',
            'duree_annees': 2,
            'date_mise_service': '',
          },
          {
            'libelle': 'x',
            'valeur_origine': '5',
            'duree_annees': 2,
            'date_mise_service': '20/03/2026',
          },
          {
            'libelle': 'x',
            'valeur_origine': '5',
            'duree_annees': 2,
            'date_mise_service': '2026-01-01',
            'compte_immobilisation': '9999',
          },
        ],
      },
    );
    final codes = [
      for (final b in serveur['biens'] as List) (b as Map)['code'] as String,
    ];
    locales = [
      for (final (i, b) in biens.indexed)
        Immobilisation(
          id: 'id-$i',
          code: codes[i],
          libelle: b.$1,
          compteImmobilisation: null,
          valeurOrigineCentimes: cts(b.$2),
          dateMiseService: b.$4,
          dureeAnnees: b.$3,
        ),
    ];
  });

  test('le serveur a rendu un plan pour chaque bien (extraction non vide)', () {
    expect((serveur['biens'] as List), hasLength(biens.length));
    expect((serveur['tableaux'] as Map), hasLength(annees.length));
    expect(
      ((serveur['biens'] as List).first as Map)['plan'] as Map,
      isNotEmpty,
    );
  });

  test('chaque plan est celui du serveur, annuité par annuité', () {
    final distants = (serveur['biens'] as List).cast<Map<String, dynamic>>();
    for (final (i, d) in distants.indexed) {
      final plan = planAmortissement(locales[i]);
      final distantPlan = d['plan'] as Map<String, dynamic>;
      final lignes = (distantPlan['lignes'] as List)
          .cast<Map<String, dynamic>>();
      expect(plan.lignes, hasLength(lignes.length), reason: biens[i].$1);
      for (final (k, l) in plan.lignes.indexed) {
        final s = lignes[k];
        final contexte = '${biens[i].$1} / ${l.annee}';
        expect(l.annee, s['annee'], reason: contexte);
        expect(l.baseCentimes, cts(s['base']), reason: contexte);
        expect(l.dotationCentimes, cts(s['dotation']), reason: contexte);
        expect(l.cumulCentimes, cts(s['cumul']), reason: contexte);
        expect(l.vncCentimes, cts(s['vnc']), reason: contexte);
        expect(l.prorata, s['prorata'], reason: contexte);
      }
      expect(
        plan.totalCentimes,
        cts(distantPlan['total']),
        reason: biens[i].$1,
      );
      // La dernière annuité absorbe l'arrondi : la VNC finale est zéro.
      expect(plan.lignes.last.vncCentimes, 0, reason: biens[i].$1);
    }
  });

  test('le tableau de chaque exercice est celui du serveur', () {
    for (final annee in annees) {
      final t = tableauPourExercice(locales, annee);
      final s =
          (serveur['tableaux'] as Map<String, dynamic>)['$annee']
              as Map<String, dynamic>;
      final lignes = (s['lignes'] as List).cast<Map<String, dynamic>>();
      expect(t.lignes, hasLength(lignes.length), reason: '$annee');
      for (final (k, l) in t.lignes.indexed) {
        final d = lignes[k];
        expect(l.immobilisation.code, d['code'], reason: '$annee');
        expect(l.brutCentimes, cts(d['brut']), reason: '$annee ${d['code']}');
        expect(
          l.dotationCentimes,
          cts(d['dotation']),
          reason: '$annee ${d['code']}',
        );
        expect(l.cumulCentimes, cts(d['cumul']), reason: '$annee ${d['code']}');
        expect(l.vncCentimes, cts(d['vnc']), reason: '$annee ${d['code']}');
      }
      final totaux = s['totaux'] as Map<String, dynamic>;
      expect(t.totalBrutCentimes, cts(totaux['brut']), reason: '$annee');
      expect(
        t.totalDotationCentimes,
        cts(totaux['dotation']),
        reason: '$annee',
      );
      expect(t.totalCumulCentimes, cts(totaux['cumul']), reason: '$annee');
      expect(t.totalVncCentimes, cts(totaux['vnc']), reason: '$annee');
    }
  });

  test('la recherche filtre sur le code ou le libellé, comme le serveur', () {
    final distantes = (serveur['recherches'] as Map)
        .cast<String, List<dynamic>>();
    expect(distantes['prado'], isNotEmpty);
    expect(distantes['zzz'], isEmpty);
    for (final e in distantes.entries) {
      final locale = tableauPourExercice(
        locales,
        annees.first,
        recherche: e.key,
      ).lignes.map((l) => l.immobilisation.code).toList();
      expect(locale, e.value, reason: e.key);
    }
  });

  test('les refus de la création sont ceux du serveur, mot pour mot', () async {
    final distants = (serveur['refus'] as List).cast<String>();
    expect(distants, hasLength(8));
    final db = AppDatabase.enMemoire();
    addTearDown(db.close);
    await db.customStatement('SELECT 1');
    final dao = ImmobilisationsDao(db);

    Future<String> refus({
      String libelle = 'x',
      int? valeur = 500,
      int? duree = 2,
      String date = '2026-01-01',
      String? compte,
    }) async {
      try {
        await dao.creer(
          libelle: libelle,
          valeurOrigineCentimes: valeur,
          dureeAnnees: duree,
          dateMiseService: date,
          compteImmobilisation: compte,
        );
      } on RefusImmobilisation catch (e) {
        return e.message;
      }
      fail('Aucun refus.');
    }

    expect(await refus(libelle: '', valeur: null, duree: null), distants[0]);
    expect(await refus(libelle: '   ', duree: null, date: ''), distants[1]);
    expect(await refus(valeur: 0, duree: null), distants[2]);
    expect(await refus(valeur: -500), distants[3]);
    expect(await refus(duree: 0), distants[4]);
    expect(await refus(date: ''), distants[5]);
    expect(await refus(date: '20/03/2026'), distants[6]);
    expect(await refus(compte: '9999'), distants[7]);
    expect(
      distants.toSet(),
      hasLength(5),
      reason: 'quatre phrases du service + le compte inconnu : cinq distinctes',
    );
  });
}
