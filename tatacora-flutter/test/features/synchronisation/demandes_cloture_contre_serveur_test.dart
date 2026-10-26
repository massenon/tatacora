@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/scenario_file.dart';

/// Le CONTRAT DE SYNCHRONISATION D'EXERCICE, confronté au vrai serveur
/// (26/10/2026) : les demandes que `ClotureExerciceLocale` enfile sont poussées
/// TELLES QUELLES au vrai `SynchronisationService`
/// (`tool/comptabilite/valider_demandes_cloture.php`) ; le serveur — seul
/// comptable (D246) — rejoue `ClotureExerciceService` et passe SES pièces.
///
/// Ce que le serveur a ÉCRIT est relu : ses pièces CL et AN, ses numéros, son
/// résultat, le statut de chaque exercice. Quand son registre comptable est
/// celui du poste, elles sont IDENTIQUES à celles du poste, au centime. Quand il
/// refuse (un brouillon d'un autre poste, un rôle qui n'est pas celui du
/// comptable), le refus est dit à ses mots et ne touche à rien.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final maintenant = DateTime(2031, 6, 15, 10);

  late AppDatabase db;
  late ComptabiliteDao dao;
  late ClotureExerciceLocale service;
  late String id2031;

  // Les pièces que le POSTE passe, et que le serveur reçoit des autres postes
  // (les mêmes : « quand son registre est celui du poste »).
  const pieces = <Map<String, Object?>>[
    {
      'journal': 'CAI',
      'date': '2031-03-10',
      'libelle': 'Ventes bar',
      'lignes': [
        {'compte': '5711', 'debit': '100000.00', 'centre': 'Bar'},
        {'compte': '7011', 'credit': '100000.00', 'centre': 'Bar'},
      ],
    },
    {
      'journal': 'CAI',
      'date': '2031-03-11',
      'libelle': 'Marché',
      'lignes': [
        {'compte': '6011', 'debit': '30000.00', 'centre': 'Restaurant'},
        {'compte': '5711', 'credit': '30000.00', 'centre': 'Restaurant'},
      ],
    },
  ];

  setUp(() async {
    db = await baseInstallee(maintenant: maintenant);
    dao = ComptabiliteDao(db);
    final moteur = moteurSur(db, maintenant: () => maintenant);
    service = ClotureExerciceLocale(db, moteur, maintenant: () => maintenant);
    id2031 = (await dao.exerciceDeLAnnee(2031))!.id;
    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    for (final p in pieces) {
      await moteur.passerEtValider(
        DemandePiece(
          journal: p['journal']! as String,
          date: p['date']! as String,
          libelle: p['libelle']! as String,
          lignes: [
            for (final l in p['lignes']! as List)
              LigneDemandee(
                compte: (l as Map)['compte'] as String,
                debitCentimes: centimesDepuisChaine(
                  (l['debit'] as String?) ?? '',
                ),
                creditCentimes: centimesDepuisChaine(
                  (l['credit'] as String?) ?? '',
                ),
                centreId: centres[l['centre']],
              ),
          ],
        ),
        auteurId: auteurEssai,
      );
    }
  });
  tearDown(() => db.close());

  Future<Map<String, dynamic>> pousser({
    String role = 'comptable',
    List<Map<String, Object?>> piecesServeur = pieces,
  }) async {
    final operations = await fileAuProtocole(db);
    return executerPhp(
      'valider_demandes_cloture.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'poste_id': 'poste-essai-cloture',
        'role': role,
        'pieces_serveur': piecesServeur,
        'operations': operations,
      },
    );
  }

  List<Map<String, dynamic>> resultats(Map<String, dynamic> s) => [
    for (final r in s['resultats'] as List) r as Map<String, dynamic>,
  ];

  /// Les lignes de clôture (CL) et d'à-nouveaux (AN), comparables d'un côté à
  /// l'autre : un ensemble de chaînes.
  List<String> cloturees(Iterable<Map<String, Object?>> lignes) => [
    for (final l in lignes)
      if (l['journal'] == 'CL' || l['journal'] == 'AN')
        '${l['journal']}|${l['numero_piece']}|${l['date']}|${l['compte']}|'
            '${l['centre']}|${l['debit']}|${l['credit']}|${l['contrepasse']}',
  ]..sort();

  Future<Map<String, List<Map<String, Object?>>>> lignesDuPoste() async => {
    for (final e in await dao.exercices())
      '${e.annee}': [
        for (final l in await dao.lignesPourArchive(e.id))
          {
            'journal': l.codeJournal,
            'numero_piece': l.numeroPiece,
            'date': l.dateEcriture,
            'compte': l.numeroCompte,
            'centre': l.libelleCentre,
            'debit': chaineDepuisCentimes(l.debitCentimes),
            'credit': chaineDepuisCentimes(l.creditCentimes),
            'contrepasse': l.pieceContrepassee != null,
          },
      ],
  };

  test('démarrer, clôturer, rouvrir, re-clôturer : le serveur rejoue chaque '
      'demande et passe des pièces IDENTIQUES à celles du poste', () async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    await service.cloturer(id2031, auteurId: auteurEssai);
    await service.rouvrir(
      id2031,
      auteurId: auteurEssai,
      motif: 'Facture oubliée en décembre',
    );
    await service.cloturer(id2031, auteurId: auteurEssai);

    final serveur = await pousser();
    expect(serveur['enveloppe'], isEmpty);
    final r = resultats(serveur);
    expect(r, hasLength(4));
    for (final x in r) {
      expect(x['statut'], 'synchronise', reason: '$x');
    }
    expect(r.map((x) => x['issue']), everyElement('executee'));
    expect(r.map((x) => x['statut_exercice']), [
      'en_cloture',
      'cloture',
      'en_cloture',
      'cloture',
    ]);

    // Le statut de chaque exercice : celui du poste.
    expect(serveur['statuts'], {'2031': 'cloture', '2032': 'ouvert'});
    expect(
      {for (final e in await dao.exercices()) '${e.annee}': e.statut.valeur}
        ..remove('2030'),
      serveur['statuts'],
    );

    // Les pièces CL et AN du serveur sont celles du poste, au centime : mêmes
    // numéros, mêmes dates, mêmes comptes, mêmes centres, mêmes montants.
    final lignesServeur = (serveur['lignes'] as Map<String, dynamic>).map(
      (annee, l) => MapEntry(annee, [
        for (final x in l as List) (x as Map).cast<String, Object?>(),
      ]),
    );
    final lignesPoste = await lignesDuPoste();
    for (final annee in ['2031', '2032']) {
      expect(
        cloturees(lignesServeur[annee]!),
        cloturees(lignesPoste[annee]!),
        reason: 'pièces de clôture et d’à-nouveaux de $annee',
      );
      expect(cloturees(lignesPoste[annee]!), isNotEmpty);
    }
    // Il y a bien eu une clôture, sa réouverture et une re-clôture.
    expect(
      lignesPoste['2031']!.where(
        (l) => l['journal'] == 'CL' && l['contrepasse'] == true,
      ),
      isNotEmpty,
    );

    // L'historique des clôtures : les mêmes numéros, le même résultat.
    String historique(Map<String, Object?> c) =>
        '${c['annee']}|${c['piece_cloture']}|${c['piece_a_nouveaux']}|'
        '${c['resultat']}|${c['active']}';
    final clotures = (serveur['clotures'] as List).cast<Map<String, dynamic>>();
    expect(clotures, hasLength(2));
    expect(
      [for (final c in clotures) historique(c)]..sort(),
      [
        for (final c in await service.clotures())
          '2031|${c.pieceCloture}|${c.pieceANouveaux}|'
              '${chaineDepuisCentimes(c.resultatCentimes)}|${c.estActive}',
      ]..sort(),
    );

    // Le serveur a consigné chaque demande : l'accusé porte les pièces et
    // l'empreinte de l'archive qu'IL a produite.
    final cloture = r[1];
    expect(cloture['piece_cloture'], 'CL-2031-00001');
    expect(cloture['piece_a_nouveaux'], 'AN-2032-00001');
    expect(cloture['archive_empreinte'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      (serveur['demandes'] as List).map((d) => (d as Map)['action']).toSet(),
      {'demarrer', 'cloturer', 'rouvrir'},
    );
    for (final d in serveur['demandes'] as List) {
      expect((d as Map)['poste_id'], 'poste-essai-cloture');
    }
  });

  test(
    'un brouillon d’un AUTRE poste que le serveur détient refuse la '
    'clôture, à sa phrase ; le poste garde la sienne et le refus se lit',
    () async {
      await service.demarrer(id2031, auteurId: auteurEssai);
      await service.cloturer(id2031, auteurId: auteurEssai);

      final serveur = await pousser(
        piecesServeur: [
          ...pieces,
          const {
            'journal': 'OD',
            'date': '2031-04-01',
            'libelle': 'Brouillon d’un autre poste',
            'valide': false,
            'lignes': [
              {'compte': '6011', 'debit': '1000.00', 'centre': 'Bar'},
              {'compte': '4011', 'credit': '1000.00', 'centre': 'Structure'},
            ],
          },
        ],
      );
      final r = resultats(serveur);
      expect(r[0]['statut'], 'synchronise'); // démarrer : accepté
      expect(r[1]['statut'], 'rejete');
      expect(r[1]['code_motif'], 'regle_metier');
      expect(
        r[1]['motif'],
        "L'exercice 2031 ne peut pas être clôturé : Des écritures restent en "
        'brouillon.',
      );
      // Le serveur n'a RIEN clôturé ; le poste, lui, a clôturé ses pièces.
      expect(serveur['statuts'], {'2031': 'en_cloture', '2032': 'ouvert'});
      expect(serveur['clotures'], isEmpty);
      expect((await dao.exercice(id2031))!.statut.valeur, 'cloture');
    },
  );

  test('la réouverture est au comptable : le compte appairé qui n’en est pas '
      'un est refusé par le serveur, à sa phrase', () async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    await service.cloturer(id2031, auteurId: auteurEssai);
    await service.rouvrir(
      id2031,
      auteurId: auteurEssai,
      motif: 'Facture oubliée en décembre',
    );

    final serveur = await pousser(role: 'administrateur');
    final r = resultats(serveur);
    expect(r.map((x) => x['statut']), ['synchronise', 'synchronise', 'rejete']);
    expect(
      r[2]['motif'],
      'Seul le comptable peut rouvrir un exercice clôturé.',
    );
    expect(serveur['statuts'], {'2031': 'cloture', '2032': 'ouvert'});
  });

  test('une demande déjà satisfaite au serveur est acceptée sans rien '
      'réécrire', () async {
    await service.demarrer(id2031, auteurId: auteurEssai);
    final serveur = await pousser(piecesServeur: const []);
    expect(resultats(serveur).single['statut'], 'synchronise');
    expect(serveur['statuts'], {'2031': 'en_cloture', '2032': 'ouvert'});

    // Le serveur a déjà fait entrer l'exercice en clôture (par la PWA) : la
    // même demande l'amène où il est.
    final operations = await fileAuProtocole(db);
    final deja = await executerPhp(
      'valider_demandes_cloture.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'poste_id': 'poste-essai-cloture',
        'exercices': [
          {'annee': 2031, 'statut': 'en_cloture'},
        ],
        'operations': operations,
      },
    );
    final r = resultats(deja).single;
    expect(r['statut'], 'synchronise');
    expect(r['issue'], 'deja_dans_cet_etat');
  });
}
