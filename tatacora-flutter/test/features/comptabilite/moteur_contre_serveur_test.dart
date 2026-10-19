@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/data/pilotage_api.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/analytique_locale.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// LE MÊME scénario de pièces, joué par le VRAI `PasserEcritureService` (et
/// `EcritureComptableService`, `ExerciceComptableService`,
/// `PlanComptableService`) du serveur — sur MySQL, observer RG-11, contraintes
/// CHECK et clés étrangères compris — et par le moteur Dart, comparé CHAMP À
/// CHAMP : numéros de pièce, équilibre, centres, statuts, liens de
/// contre-passation, et chaque refus (classe d'exception ET phrase).
///
/// `tool/comptabilite/rejouer_scenario.php` travaille sur `tatacora_test` (il
/// refuse toute autre base), sème le référentiel par le vrai seeder, puis
/// ANNULE tout : la base n'est pas modifiée. MySQL injoignable : le test
/// ÉCHOUE, il ne saute pas.
///
/// Un scénario recopié à la main des deux côtés ne prouverait rien ; celui-ci
/// est UN seul JSON, lu par les deux moteurs.
void main() {
  /// Les lignes d'une vente : la caisse puis un produit.
  List<Map<String, Object?>> vente(
    String montant, {
    String? centre = 'Restaurant',
  }) => [
    {'compte': '5711', 'debit': montant},
    {'compte': '7061', 'credit': montant, 'centre': centre},
  ];

  Map<String, Object?> passer(
    String ref,
    String date,
    List<Map<String, Object?>> lignes, {
    bool valide = false,
    String journal = 'VTE',
    String libelle = 'Vente comptoir',
  }) => {
    'op': 'passer',
    'ref': ref,
    'valide': valide,
    'journal': journal,
    'date': date,
    'libelle': libelle,
    'lignes': lignes,
  };

  final scenario = <Map<String, Object?>>[
    // --- Exercices ---------------------------------------------------------
    {'op': 'ouvrir_exercice', 'annee': 2032},
    {'op': 'ouvrir_exercice', 'annee': 2032},
    {'op': 'ouvrir_exercice', 'annee': 1999},
    {'op': 'ouvrir_exercice', 'annee': 2101},

    // --- Pièces valides : numéros, centres, troncature ---------------------
    passer('p1', '2031-03-04', vente('12500.00'), valide: true),
    passer('p2', '2031-03-05', [
      {'compte': '5711', 'debit': '100.999'},
      {'compte': '7061', 'credit': '100.99', 'centre': 'Bar'},
    ], libelle: 'Vente 2'),
    passer(
      'p3',
      '2031-04-01',
      [
        {'compte': '6011', 'debit': '5000', 'centre': 'Structure'},
        {'compte': '4011', 'credit': '5000'},
      ],
      valide: true,
      journal: 'ACH',
      libelle: 'Achat marchandises',
    ),
    passer('p4', '2032-01-02', vente('750'), valide: true),
    passer('p5', '2031-03-06', vente('1.05'), valide: true),
    passer(
      'p5b',
      '2031-03-06',
      [
        {'compte': '5711', 'debit': '10.00', 'libelle': 'Espèces'},
        {'compte': '552', 'debit': '5.00', 'centre': 'Structure'},
        {'compte': '131', 'credit': '8.50'},
        {'compte': '139', 'credit': '6.50'},
      ],
      journal: 'OD',
      libelle: 'Pièce à quatre lignes',
    ),

    // --- Valider -----------------------------------------------------------
    {'op': 'valider', 'ref': 'p2'},
    {'op': 'valider', 'ref': 'p2'},

    // --- Contre-passer -----------------------------------------------------
    {'op': 'contrepasser_piece', 'ref': 'p1'},
    {'op': 'contrepasser_piece', 'ref': 'p1'},
    {'op': 'contrepasser_piece', 'ref': 'p5', 'motif': 'Erreur de caisse'},
    {'op': 'contrepasser_ligne', 'ref': 'p3', 'index': 0},
    {'op': 'contrepasser_ligne', 'ref': 'p3', 'index': 0},
    // La pièce entière : la ligne 0 est déjà inversée, donc TOUT est refusé…
    {'op': 'contrepasser_piece', 'ref': 'p3'},
    // … et la ligne 1 n'a pas été inversée par cette tentative.
    {'op': 'contrepasser_ligne', 'ref': 'p3', 'index': 1},
    // Une contre-passation se contre-passe (le serveur l'admet).
    {'op': 'contrepasser_ligne', 'ref': 'p1/inverse', 'index': 0},
    passer('p6', '2031-03-07', vente('42.00')),
    {'op': 'contrepasser_piece', 'ref': 'p6'},
    {'op': 'contrepasser_piece_vide'},

    // --- RG-11 : modifier, supprimer ---------------------------------------
    {
      'op': 'modifier',
      'ref': 'p1',
      'index': 0,
      'champs': {'libelle': 'Falsifié'},
    },
    {
      'op': 'modifier',
      'ref': 'p1',
      'index': 0,
      'champs': {'debit': '1.00'},
    },
    {
      'op': 'modifier',
      'ref': 'p6',
      'index': 0,
      'champs': {'libelle': 'Brouillon corrigé'},
    },
    {'op': 'supprimer', 'ref': 'p6', 'index': 0},
    {'op': 'supprimer', 'ref': 'p1', 'index': 1},

    // --- Les refus de passer(), dans l'ordre du serveur --------------------
    passer('r1', '2031-03-04', vente('1.00'), journal: 'ZZZ'),
    passer('r1b', '2035-01-01', vente('1.00'), journal: 'ZZZ'),
    passer('r2', '2035-01-01', vente('1.00')),
    passer('r2b', '2031-02-30', vente('1.00')),
    passer('r2c', 'hier', vente('1.00')),
    passer('r3', '2031-03-04', [
      {'compte': '5711', 'debit': '1.00'},
      {'compte': '9999', 'credit': '1.00'},
    ]),
    passer('r3b', '2031-03-04', [
      {'compte': '6011', 'debit': '1.00'},
      {'compte': '9999', 'credit': '1.00'},
    ]),
    passer('r4', '2031-03-04', [
      {'compte': '60', 'debit': '1.00'},
      {'compte': '5711', 'credit': '1.00'},
    ], journal: 'ACH'),
    passer('r4b', '2031-03-04', [
      {'compte': '601', 'debit': '1.00'},
      {'compte': '5711', 'credit': '1.00'},
    ], journal: 'ACH'),
    passer('r4c', '2031-03-04', [
      {'compte': '4', 'debit': '1.00'},
      {'compte': '5711', 'credit': '1.00'},
    ], journal: 'ACH'),
    passer('r5', '2031-03-04', [
      {'compte': '6011', 'debit': '1.00'},
      {'compte': '5711', 'credit': '1.00'},
    ], journal: 'ACH'),
    passer('r6', '2031-03-04', []),
    passer('r7', '2031-03-04', [
      {'compte': '5711', 'debit': '10.00'},
      {'compte': '7061', 'credit': '7.50', 'centre': 'Bar'},
    ]),
    passer('r7b', '2031-03-04', [
      {'compte': '5711', 'debit': '7.50'},
      {'compte': '7061', 'credit': '10.00', 'centre': 'Bar'},
    ]),
    passer('r7c', '2031-03-04', [
      {'compte': '5711', 'debit': '0.01'},
      {'compte': '7061', 'credit': '0.00', 'centre': 'Bar'},
    ]),
    passer('r8', '2031-03-04', [
      {'compte': '5711'},
      {'compte': '7061', 'centre': 'Bar'},
    ]),
    passer('r9', '2031-03-04', [
      {'compte': '5711', 'debit': '-5.00'},
      {'compte': '7061', 'credit': '-5.00', 'centre': 'Bar'},
    ]),
    passer('r10', '2031-03-04', [
      {'compte': '5711', 'debit': '5.00', 'credit': '5.00'},
      {'compte': '7061', 'centre': 'Bar'},
    ]),

    // --- L'analytique (13/10/2026) : la marge par centre de l'accueil -------
    // La classe 8 se range selon le SENS du solde : une cession (821,
    // créditrice) est un produit, sa valeur comptable (812, débitrice) une
    // charge. Une pièce en BROUILLON compte aussi (les deux statuts).
    passer(
      'a1',
      '2031-05-02',
      [
        {'compte': '5711', 'debit': '9000', 'centre': 'Restaurant'},
        {'compte': '821', 'credit': '9000', 'centre': 'Restaurant'},
      ],
      journal: 'OD',
      libelle: 'Cession',
      valide: true,
    ),
    passer(
      'a2',
      '2031-05-03',
      [
        {'compte': '812', 'debit': '4000', 'centre': 'Restaurant'},
        {'compte': '5711', 'credit': '4000', 'centre': 'Restaurant'},
      ],
      journal: 'OD',
      libelle: 'Valeur comptable cédée',
    ),
    passer(
      'a3',
      '2031-05-04',
      [
        {'compte': '6011', 'debit': '250.50', 'centre': 'Bar'},
        {'compte': '5711', 'credit': '250.50', 'centre': 'Bar'},
      ],
      journal: 'ACH',
      libelle: 'Achat bar',
    ),
    {'op': 'analytique', 'annee': 2031},
    {'op': 'analytique', 'annee': 2032},
    // Validées ensuite : la clôture de 2031, plus bas, ne doit pas changer de
    // sens à cause de ces deux brouillons.
    {'op': 'valider', 'ref': 'a2'},
    {'op': 'valider', 'ref': 'a3'},

    // --- Exercice en clôture, puis clôturé --------------------------------
    passer('p7', '2032-01-03', vente('9.00')),
    {'op': 'poser_statut_exercice', 'annee': 2032, 'statut': 'en_cloture'},
    passer('r11', '2032-01-04', vente('1.00')),
    // `en_cloture` n'est pas fermé par l'observer : valider reste possible.
    {'op': 'valider', 'ref': 'p7'},
    {'op': 'contrepasser_piece', 'ref': 'p4'},
    {'op': 'poser_statut_exercice', 'annee': 2032, 'statut': 'cloture'},
    passer('r12', '2032-01-04', vente('1.00')),
    {'op': 'contrepasser_piece', 'ref': 'p7'},
    {'op': 'cloturer_exercice', 'annee': 2032},

    // --- Clôturer 2031 : brouillons restants, puis réussite ----------------
    passer('p8', '2031-12-31', vente('3.00')),
    {'op': 'cloturer_exercice', 'annee': 2031},
    {'op': 'valider', 'ref': 'p8'},
    {'op': 'valider', 'ref': 'p6'},
    {'op': 'valider', 'ref': 'p5b'},
    {'op': 'cloturer_exercice', 'annee': 2031},
    {'op': 'cloturer_exercice', 'annee': 2031},
    passer('r13', '2031-12-30', vente('1.00')),
    {'op': 'contrepasser_piece', 'ref': 'p8'},

    // --- Plan comptable ----------------------------------------------------
    {
      'op': 'creer_compte',
      'numero': '6099',
      'libelle': '  Divers  ',
      'nature': 'charge',
    },
    {
      'op': 'creer_compte',
      'numero': '10',
      'libelle': 'Deux chiffres',
      'nature': 'actif',
    },
    {
      'op': 'creer_compte',
      'numero': '6099',
      'libelle': 'Doublon',
      'nature': 'charge',
    },
    {
      'op': 'creer_compte',
      'numero': '4111',
      'libelle': 'Doublon',
      'nature': 'actif',
    },
    {
      'op': 'creer_compte',
      'numero': '7',
      'libelle': 'Un chiffre',
      'nature': 'actif',
    },
    {
      'op': 'creer_compte',
      'numero': '12345',
      'libelle': 'Cinq',
      'nature': 'actif',
    },
    {
      'op': 'creer_compte',
      'numero': '0123',
      'libelle': 'Zéro',
      'nature': 'actif',
    },
    {
      'op': 'creer_compte',
      'numero': '6098',
      'libelle': '   ',
      'nature': 'charge',
    },
    {
      'op': 'creer_compte',
      'numero': '6098',
      'libelle': 'Ok',
      'nature': 'bizarre',
    },
    {'op': 'comptes_de_charge'},
    // Après les clôtures et les contre-passations : l'analytique les reflète.
    {'op': 'analytique', 'annee': 2031},
    {'op': 'analytique', 'annee': 2032},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final r = await executerPhp(
      'rejouer_scenario.php',
      entree: {'aujourdhui': '2031-06-15', 'ops': scenario},
    );
    serveur = r['resultats'] as List<dynamic>;
    local = await _jouerLocalement(scenario);
  });

  test('l’analytique compare quelque chose : la classe 8 dans les deux sens, '
      'un brouillon compté, le tri par résultat décroissant', () {
    final premiere =
        (serveur[scenario.indexWhere((o) => o['op'] == 'analytique')]
                as Map)['centres']
            as List<dynamic>;
    final parLibelle = {for (final c in premiere) (c as Map)['libelle']: c};
    final restaurant = parLibelle['Restaurant'] as Map;
    // ⚠ Le serveur groupe par CLASSE, pas par compte : la cession (821,
    // 9 000 créditeur) et la valeur cédée (812, 4 000 débiteur, en
    // BROUILLON) se COMPENSENT dans la classe 8 du centre, et le solde net
    // (5 000 créditeur) va aux produits — alors que son commentaire promet
    // « une cession est un produit, sa valeur comptable une charge ». Défaut
    // du SERVEUR, répliqué (le poste rend la même chose, comparée plus bas).
    expect(
      double.parse(restaurant['produits'] as String),
      greaterThanOrEqualTo(5000),
    );
    expect(
      double.parse(restaurant['produits'] as String),
      lessThan(9000),
      reason:
          'la cession entière en produit dirait que les deux comptes de '
          'la classe 8 sont classés séparément',
    );
    final resultats = [
      for (final c in premiere) double.parse((c as Map)['resultat'] as String),
    ];
    expect(resultats, [...resultats]..sort((a, b) => b.compareTo(a)));
    expect(premiere.length, greaterThanOrEqualTo(2));
  });

  test('chaque opération du scénario a un résultat des deux côtés', () {
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));
    // Non vide : le scénario a produit des pièces ET des refus (sinon la
    // comparaison ne comparerait que des deux côtés vides).
    final ok = serveur.where((r) => (r as Map)['ok'] == true).length;
    final refus = serveur.where((r) => (r as Map).containsKey('refus')).length;
    // 28, plus les trois pièces, les deux validations et les quatre lectures
    // de l'analytique du 13/10/2026.
    expect(ok, 37);
    expect(refus, 46);
    final lignes = serveur
        .where((r) => (r as Map)['lignes'] != null)
        .fold<int>(0, (s, r) => s + ((r as Map)['lignes'] as List).length);
    // 42, plus les six lignes des trois pièces de l'analytique et les quatre
    // relues par leurs deux validations (13/10/2026).
    expect(lignes, 52);
  });

  test('chaque résultat est identique au serveur, opération par opération', () {
    for (var i = 0; i < scenario.length; i++) {
      expect(
        local[i],
        equals(serveur[i]),
        reason: 'opération $i : ${scenario[i]}',
      );
    }
  });

  test(
    'les refus portent la même CLASSE et la même PHRASE (quarante au moins)',
    () {
      var compares = 0;
      var phrases = 0;
      for (var i = 0; i < scenario.length; i++) {
        final s = serveur[i] as Map;
        if (!s.containsKey('refus')) continue;
        final l = local[i];
        expect(l['refus'], s['refus'], reason: 'classe, opération $i');
        expect(l['message'], s['message'], reason: 'phrase, opération $i');
        compares++;
        if (s['message'] != null) phrases++;
      }
      expect(compares, 46);
      expect(phrases, 44);
    },
  );

  test('les trois sortes de refus sont réellement présentes', () {
    final classes = serveur
        .whereType<Map<String, dynamic>>()
        .where((r) => r.containsKey('refus'))
        .map((r) => r['refus'])
        .toSet();
    expect(classes, {
      'RuntimeException',
      'EcritureImmuableException',
      'contrainte_base',
    });
  });
}

/// Joue le scénario avec le moteur Dart, dans le format de sortie du script PHP.
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> scenario,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  // Le référentiel est installé par la vraie fonction, à la date du scénario :
  // l'exercice 2031 est semé, comme le seeder du serveur le sème pour l'année
  // du jour.
  final moteur = moteurSur(db);
  await baseInstalleeSur(db, DateTime(2031, 6, 15));
  final dao = ComptabiliteDao(db);

  final journaux = {for (final j in await dao.journaux()) j.id: j.code};
  final centres = {for (final c in await dao.centres()) c.libelle: c.id};
  final libellesCentre = {for (final e in centres.entries) e.value: e.key};

  final pieces = <String, List<String>>{};
  final origine = <String, String>{};
  final resultats = <Map<String, Object?>>[];

  Future<Map<String, Object?>> decrire(EcritureComptable e) async {
    final compte = (await dao.compteParId(e.compteId))!;
    final relue = (await dao.ecriture(e.id))!;
    return {
      'numero_piece': relue.numeroPiece,
      'journal': journaux[relue.journalId],
      'date': relue.dateEcriture,
      'compte': compte.numero,
      'centre': libellesCentre[relue.centreId],
      'libelle': relue.libelle,
      'debit': relue.debit,
      'credit': relue.credit,
      'statut': relue.statut.valeur,
      'contrepasse_de': relue.ecritureContrepasseeId == null
          ? null
          : (origine[relue.ecritureContrepasseeId] ?? '?'),
    };
  }

  void enregistrer(String ref, List<EcritureComptable> lignes) {
    pieces[ref] = [for (final l in lignes) l.id];
    for (var i = 0; i < lignes.length; i++) {
      origine[lignes[i].id] = '$ref#$i';
    }
  }

  Future<List<EcritureComptable>> modeles(String ref) async => [
    for (final id in pieces[ref]!) (await dao.ecriture(id))!,
  ];

  Map<String, Object?> refus(Object e) {
    final r = e is RefusComptable ? e : ComptabiliteDao.traduireRefusBase(e);
    if (r == null) {
      throw StateError('Exception inattendue, ni refus ni contrainte : $e');
    }
    if (r.motif == MotifRefus.contrainteBase) {
      return {'refus': 'contrainte_base'};
    }
    return {
      'refus': r.motif.immuabilite
          ? 'EcritureImmuableException'
          : 'RuntimeException',
      'message': r.message,
    };
  }

  for (final op in scenario) {
    try {
      switch (op['op']) {
        case 'passer':
          final lignes = [
            for (final l in (op['lignes'] as List).cast<Map<String, Object?>>())
              LigneDemandee.depuisMontants(
                compte: l['compte'] as String,
                debit: l['debit'] as String?,
                credit: l['credit'] as String?,
                libelle: l['libelle'] as String?,
                centreId: l['centre'] == null ? null : centres[l['centre']],
              ),
          ];
          final demande = DemandePiece(
            journal: op['journal'] as String,
            date: op['date'] as String,
            libelle: op['libelle'] as String,
            lignes: lignes,
          );
          final ecrites = op['valide'] == true
              ? await moteur.passerEtValider(demande, auteurId: auteurEssai)
              : await moteur.passer(demande, auteurId: auteurEssai);
          enregistrer(op['ref'] as String, ecrites);
          resultats.add({
            'ok': true,
            'lignes': [for (final e in ecrites) await decrire(e)],
          });
        case 'valider':
          final validees = await moteur.valider(
            await modeles(op['ref'] as String),
            auteurId: auteurEssai,
          );
          resultats.add({
            'ok': true,
            'lignes': [for (final e in validees) await decrire(e)],
          });
        case 'contrepasser_piece':
          final ref = op['ref'] as String;
          final inverses = await moteur.contrepasserPiece(
            await modeles(ref),
            auteurId: auteurEssai,
            motif: op['motif'] as String?,
          );
          enregistrer('$ref/inverse', inverses);
          resultats.add({
            'ok': true,
            'lignes': [for (final e in inverses) await decrire(e)],
          });
        case 'contrepasser_piece_vide':
          await moteur.contrepasserPiece([], auteurId: auteurEssai);
          resultats.add({'ok': true, 'lignes': <Object?>[]});
        case 'contrepasser_ligne':
          final ref = op['ref'] as String;
          final index = op['index'] as int;
          final ligne = (await dao.ecriture(pieces[ref]![index]))!;
          final inverse = await moteur.contrepasserLigne(
            ligne,
            auteurId: auteurEssai,
            motif: op['motif'] as String?,
          );
          origine[inverse.id] = '$ref/ligne#$index';
          resultats.add({
            'ok': true,
            'lignes': [await decrire(inverse)],
          });
        case 'modifier':
          final id = pieces[op['ref']]![op['index'] as int];
          final champs = (op['champs'] as Map).cast<String, Object?>();
          final sets = <String>[];
          final valeurs = <Variable>[];
          for (final e in champs.entries) {
            if (e.key == 'debit') {
              sets.add('debit_centimes = ?');
              valeurs.add(Variable<int>(_centimes(e.value as String)));
            } else {
              sets.add('${e.key} = ?');
              valeurs.add(Variable<String>(e.value as String));
            }
          }
          await db.customStatement(
            'UPDATE ecritures_local SET ${sets.join(', ')} WHERE id = ?',
            [for (final v in valeurs) v.value, id],
          );
          resultats.add({
            'ok': true,
            'lignes': [await decrire((await dao.ecriture(id))!)],
          });
        case 'supprimer':
          final id = pieces[op['ref']]![op['index'] as int];
          await db.customStatement('DELETE FROM ecritures_local WHERE id = ?', [
            id,
          ]);
          resultats.add({'ok': true});
        case 'ouvrir_exercice':
          final e = await moteur.ouvrirExercice(op['annee'] as int);
          resultats.add({
            'ok': true,
            'exercice': {
              'annee': e.annee,
              'date_debut': e.dateDebut,
              'date_fin': e.dateFin,
              'statut': e.statut.valeur,
            },
          });
        case 'poser_statut_exercice':
          await db.customStatement(
            'UPDATE exercices_local SET statut = ? WHERE annee = ?',
            [op['statut'], op['annee']],
          );
          resultats.add({'ok': true});
        case 'cloturer_exercice':
          final exercice = (await dao.exerciceDeLAnnee(op['annee'] as int))!;
          final e = await moteur.cloturerExercice(
            exercice.id,
            auteurId: auteurEssai,
          );
          resultats.add({
            'ok': true,
            'exercice': {
              'annee': e.annee,
              'statut': e.statut.valeur,
              'date_cloture': formaterDateIso(e.dateCloture!),
              'cloture_par_renseigne': e.utilisateurClotureId != null,
            },
          });
        case 'creer_compte':
          final c = await moteur.creerCompte(
            op['numero'] as String,
            op['libelle'] as String,
            op['nature'] as String,
          );
          resultats.add({
            'ok': true,
            'compte': {
              'numero': c.numero,
              'libelle': c.libelle,
              'classe': c.classe,
              'nature': c.nature,
            },
          });
        case 'analytique':
          final exercice = (await dao.exerciceDeLAnnee(op['annee'] as int))!;
          resultats.add({
            'ok': true,
            'centres': [
              for (final m in await PilotageApi(base: db).marges(exercice.id))
                {
                  'libelle': m.libelle,
                  'produits': decimaleDeCentimes(m.produitsCentimes),
                  'charges': decimaleDeCentimes(m.chargesCentimes),
                  'resultat': decimaleDeCentimes(m.resultatCentimes),
                  'lignes': m.nombreLignes,
                },
            ],
          });
        case 'comptes_de_charge':
          resultats.add({
            'ok': true,
            'comptes': [
              for (final c in await moteur.comptesDeCharge()) c.numero,
            ],
          });
        default:
          fail('Opération inconnue : ${op['op']}');
      }
    } catch (e) {
      if (e is TestFailure) rethrow;
      resultats.add(refus(e));
    }
  }
  return resultats;
}

int _centimes(String v) {
  final p = v.split('.');
  return int.parse(p[0]) * 100 +
      (p.length > 1 ? int.parse(p[1].padRight(2, '0')) : 0);
}
