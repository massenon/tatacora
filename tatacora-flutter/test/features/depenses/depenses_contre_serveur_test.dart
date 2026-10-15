@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_comptables.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/depenses/data/depense_dao.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/depenses/domain/entities/depense.dart';
import 'package:tatacora_flutter/features/depenses/presentation/ecran_depenses.dart';
import 'package:tatacora_flutter/features/depenses/presentation/widgets/table_depenses.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// LE MÊME scénario de dépenses, joué par le VRAI `DepenseService` du serveur
/// (et `PasserEcritureService` derrière lui) sur MySQL — observer RG-11,
/// contraintes CHECK, clés étrangères et verrou de séquence compris — et par
/// `DepenseDao` sur le moteur comptable local, comparé CHAMP À CHAMP : la
/// dépense, ses lignes, la pièce (journal, numéro, date, comptes, centres,
/// libellés, débits, crédits, statut) et chaque refus (classe ET phrase).
///
/// `tool/depenses/rejouer_depenses.php` travaille sur `tatacora_test` (il refuse
/// toute autre base), sème le référentiel par le vrai seeder, puis ANNULE tout :
/// la base n'est pas modifiée. MySQL injoignable : le test ÉCHOUE, il ne saute
/// pas.
///
/// Un scénario recopié à la main des deux côtés ne prouverait rien ; celui-ci
/// est UN seul JSON, lu par les deux moteurs.
void main() {
  Map<String, Object?> ligne(
    String compte,
    String libelle,
    int montant,
    NatureDepense nature,
  ) => {
    'compte': compte,
    'libelle': libelle,
    'montant': '$montant',
    'nature': nature.libelle,
    'famille': nature.famille.libelle,
  };

  Map<String, Object?> depense(
    String date,
    String tresorerie,
    String libelle,
    List<Map<String, Object?>> lignes, {
    String? centre,
  }) => {
    'op': 'depense',
    'date': date,
    'tresorerie': tresorerie,
    'libelle': libelle,
    'centre': centre,
    'lignes': lignes,
  };

  Map<String, Object?> ancienne(
    String ref,
    String date,
    String libelle,
    List<Map<String, Object?>> lignes,
  ) => {
    'op': 'depense_ancienne',
    'ref': ref,
    'date': date,
    'tresorerie': 'caisse',
    'libelle': libelle,
    'lignes': lignes,
  };

  Map<String, Object?> rattrapage(String ref, {String? centre}) => {
    'op': 'rattrapage',
    'ref': ref,
    'centre': centre,
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'tresoreries'},
    {'op': 'ouvrir_exercice', 'annee': 2032},

    // --- Les trois trésoreries, un centre EXPLICITE ------------------------
    depense('2031-03-04', 'caisse', 'Marché du matin', [
      ligne('6011', 'Oignons', 15000, NatureDepense.oignon),
      ligne('6011', 'Tomates', 8500, NatureDepense.tomate),
      ligne('6223', 'Transport du marché', 3500, NatureDepense.transport),
    ], centre: 'Restaurant'),
    depense('2031-03-05', 'caisse', 'Gaz', [
      ligne('6052', 'Bouteille de gaz', 7000, NatureDepense.electriciteEau),
    ], centre: 'Structure'),
    depense('2031-03-05', 'momo', 'Location minibus', [
      ligne('6223', 'Minibus à la journée', 25000, NatureDepense.transport),
    ], centre: 'Tourisme'),
    depense('2031-03-06', 'banque', 'Électricité et eau', [
      ligne('6052', 'Recharge compteur', 45000, NatureDepense.electriciteEau),
      ligne('6051', 'Abonnement eau', 18000, NatureDepense.electriciteEau),
    ], centre: 'Structure'),

    // --- RG-12 : ni centre ni défaut du compte -> refus, RIEN d'écrit ------
    depense('2031-03-07', 'caisse', 'Sans centre', [
      ligne('6011', 'Piment', 2000, NatureDepense.piment),
    ]),
    {'op': 'compter'},

    // --- Le défaut du compte joue (charge ET trésorerie 5711) --------------
    {'op': 'poser_centre_defaut', 'compte': '6052', 'centre': 'Structure'},
    depense('2031-03-08', 'caisse', 'Défaut du compte', [
      ligne('6052', 'Recharge', 12000, NatureDepense.electriciteEau),
    ]),
    // Le défaut du compte de trésorerie suffit, mais pas celui de la charge.
    depense('2031-03-08', 'banque', 'Banque sans centre de charge', [
      ligne('6011', 'Viande', 48000, NatureDepense.viande),
    ]),

    // --- Exercices : absent, non ouvert, rouvert par l'année --------------
    depense('2035-01-01', 'caisse', 'Hors exercice', [
      ligne('6052', 'Futur', 1000, NatureDepense.electriciteEau),
    ], centre: 'Structure'),
    depense('2032-01-02', 'banque', 'Premier de 2032', [
      ligne('6052', 'Recharge 2032', 9000, NatureDepense.electriciteEau),
    ], centre: 'Structure'),
    {'op': 'poser_statut_exercice', 'annee': 2032, 'statut': 'en_cloture'},
    depense('2032-01-03', 'banque', 'Exercice en clôture', [
      ligne('6052', 'Trop tard', 9000, NatureDepense.electriciteEau),
    ], centre: 'Structure'),
    {'op': 'compter'},

    // --- Le rattrapage d'une dépense ANTÉRIEURE (sans pièce) ---------------
    // Le centre de coût est un paramètre OBLIGATOIRE du geste (10/10/2026) :
    // chaque rattrapage porte le sien, ou aucun — et alors le moteur refuse.
    ancienne('a1', '2031-02-01', 'Dépense héritée (compte inconnu)', [
      ligne('601', 'Oignons', 15000, NatureDepense.oignon),
    ]),
    rattrapage('a1', centre: 'Restaurant'),
    ancienne('a2', '2031-02-02', 'Dépense héritée (sans centre)', [
      ligne('6011', 'Riz', 20000, NatureDepense.riz),
    ]),
    // SANS centre, le compte 6011 n'en porte pas par défaut : refus RG-12, et la
    // raison est consignée sur la dépense.
    rattrapage('a2'),
    // AVEC un centre, le même geste aboutit et efface la raison consignée.
    rattrapage('a2', centre: 'Restaurant'),
    ancienne('a3', '2031-02-03', 'Dépense héritée rattrapable', [
      ligne('6052', 'Plomberie', 12500, NatureDepense.entretien),
      ligne('6052', 'Main d\'œuvre', 7500, NatureDepense.entretien),
    ]),
    // Le compte 6052 porte « Structure » par défaut (posé plus haut) : le centre
    // EXPLICITE l'emporte, sur les charges ET sur la trésorerie.
    rattrapage('a3', centre: 'Tourisme'),
    // Idempotent : repasser (même avec un autre centre) ne crée pas une seconde
    // pièce et ne change pas celle qui existe.
    rattrapage('a3', centre: 'Structure'),
    {'op': 'compter'},

    // --- Les libellés du bandeau, lus de lang/fr par le VRAI traducteur ----
    {'op': 'libelles'},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_depenses.php',
      dossier: 'depenses',
      entree: {'aujourdhui': '2031-06-15', 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _jouerLocalement(scenario);
  });

  test('chaque opération du scénario a un résultat des deux côtés', () {
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));
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

  test('le scénario éprouve les chemins qui comptent (pas un vert à vide)', () {
    final ok = serveur.where((r) => (r as Map).containsKey('depense')).length;
    final refus = serveur.where((r) => (r as Map).containsKey('refus')).length;
    final phrases = <String>{
      for (final r in serveur)
        if ((r as Map)['message'] != null) r['message'] as String,
    };
    // Sept dépenses écrites par le chemin normal + quatre rattrapages réussis
    // ou rendus tels quels, et deux refusés : les refus comptent pour les deux.
    expect(ok, greaterThanOrEqualTo(10));
    expect(refus, 6);
    // Les quatre causes locales : centre, exercice absent, exercice non
    // ouvert, compte inconnu.
    expect(phrases, hasLength(4));
    // La pièce d'une dépense comptabilisée porte l'argent des deux côtés.
    final premiere = (serveur[2] as Map)['depense'] as Map;
    expect(premiere['comptabilisee'], isTrue);
    expect(premiere['numero_piece'], 'CAI-2031-00001');
    expect((premiere['piece'] as List), hasLength(4));
  });

  test('un refus n’écrit RIEN : les comptes sont ceux des seuls succès', () {
    final comptes = [
      for (final r in serveur)
        if ((r as Map).containsKey('compte')) r['compte'] as Map,
    ];
    // Après quatre dépenses réussies (4 + 2 + 2 + 3 écritures) et UN refus
    // (RG-12) : si le refus avait écrit, on lirait 5 / 8 / 13.
    expect(comptes[0], {'depenses': 4, 'lignes_depense': 7, 'ecritures': 11});
    // Deux réussies de plus (2 + 2 écritures) entourant trois refus.
    expect(comptes[1], {'depenses': 6, 'lignes_depense': 9, 'ecritures': 15});
    // Trois dépenses héritées (sans pièce) et DEUX rattrapages réussis (2 + 3
    // écritures), le second répété sans effet.
    expect(comptes[2], {'depenses': 9, 'lignes_depense': 13, 'ecritures': 20});
  });

  /// Le résultat serveur de la n-ième opération `rattrapage` de [ref].
  Map<dynamic, dynamic> rattrapageServeur(String ref, int rang) {
    var vu = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['op'] == 'rattrapage' && scenario[i]['ref'] == ref) {
        if (vu++ == rang) return serveur[i] as Map;
      }
    }
    throw StateError('Rattrapage $ref #$rang absent du scénario.');
  }

  test('le centre du rattrapage est EXPLICITE : charges ET trésorerie, et il '
      'l’emporte sur le défaut du compte', () {
    final faite = rattrapageServeur('a3', 0)['depense'] as Map;
    final piece = (faite['piece'] as List).cast<Map<String, dynamic>>();
    // Deux charges au débit + la trésorerie au crédit.
    expect(piece, hasLength(3));
    // 6052 porte « Structure » par défaut ; le centre choisi est « Tourisme ».
    expect(piece.map((l) => l['centre']), everyElement('Tourisme'));
    // La trésorerie en fait partie (le serveur pose le centre sur les deux).
    expect(piece.where((l) => l['credit'] != '0.00'), hasLength(1));
    // Et le même scénario donne la même chose ici (comparaison champ à champ
    // faite plus haut) : le défaut n'a pas servi de repli silencieux.
    expect(
      local[scenario.indexOf(
        scenario.firstWhere((o) => o['op'] == 'rattrapage' && o['ref'] == 'a3'),
      )],
      equals(rattrapageServeur('a3', 0)),
    );
  });

  test('sans centre, le rattrapage est REFUSÉ avec la phrase du serveur, la '
      'raison est consignée, et un second essai AVEC centre l’efface', () {
    final refuse = rattrapageServeur('a2', 0);
    expect(refuse['refus'], 'RuntimeException');
    expect(
      refuse['message'],
      MessagesComptables.dire('depenses.centre_absent', {'numero': '6011'}),
    );
    final apres = refuse['depense'] as Map;
    expect(apres['comptabilisee'], isFalse);
    expect(apres['ecriture_refus'], refuse['message']);

    final reussi = rattrapageServeur('a2', 1)['depense'] as Map;
    expect(reussi['comptabilisee'], isTrue);
    expect(reussi['ecriture_refus'], isNull);
    expect(
      (reussi['piece'] as List).map((l) => (l as Map)['centre']),
      everyElement('Restaurant'),
    );
  });

  test('idempotence : repasser avec un autre centre ne change rien', () {
    final premiere = rattrapageServeur('a3', 0)['depense'] as Map;
    final seconde = rattrapageServeur('a3', 1)['depense'] as Map;
    expect(seconde, equals(premiere));
    expect(
      (seconde['piece'] as List).map((l) => (l as Map)['centre']),
      everyElement('Tourisme'),
    );
  });

  test('les libellés du bandeau sont ceux de lang/fr, lus par PHP', () {
    final libelles = (serveur.last as Map)['libelles'] as Map<dynamic, dynamic>;
    expect(libelles['centre'], LibellesRattrapage.centre);
    expect(libelles['choisir'], LibellesRattrapage.choisir);
    expect(libelles['action'], libelleComptabiliser);
    expect(libelles['bandeau'], LibellesRattrapage.bandeau(':nombre'));
    // Non vide : sinon l'égalité ci-dessus comparerait deux vides.
    expect(libelles['centre'], isNotEmpty);
    expect(libelles['choisir'], isNotEmpty);
  });
}

/// Joue le scénario avec `DepenseDao` sur le moteur local, dans le format de
/// sortie du script PHP.
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> scenario,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  // Le référentiel est installé par la vraie fonction, à la date du scénario :
  // l'exercice 2031 est ouvert, comme le seeder du serveur l'ouvre pour l'année
  // du jour.
  await baseInstalleeSur(db, DateTime(2031, 6, 15));
  final moteur = moteurSur(db);
  final dao = DepenseDao(
    db,
    maintenant: () => DateTime(2031, 6, 15, 10),
    moteur: () async => moteur,
  );
  final compta = ComptabiliteDao(db);

  final journaux = {for (final j in await compta.journaux()) j.id: j.code};
  final centres = {for (final c in await compta.centres()) c.libelle: c.id};
  final libellesCentre = {for (final e in centres.entries) e.value: e.key};

  final anciennes = <String, String>{};
  var serie = 0;

  String cle(List<Object?> parties) => parties.join('|');

  Future<Map<String, Object?>> decrireLigne(EcritureComptable e) async {
    final compte = (await compta.compteParId(e.compteId))!;
    return {
      'numero_piece': e.numeroPiece,
      'journal': journaux[e.journalId],
      'date': e.dateEcriture,
      'compte': compte.numero,
      'centre': libellesCentre[e.centreId],
      'libelle': e.libelle,
      'debit': e.debit,
      'credit': e.credit,
      'statut': e.statut.valeur,
    };
  }

  Future<Map<String, Object?>> decrire(Depense d) async {
    final piece = <Map<String, Object?>>[];
    String? numero;
    if (d.ecritureId != null) {
      numero = (await compta.ecriture(d.ecritureId!))!.numeroPiece;
      for (final e in await compta.lignesDeLaPiece(numero!)) {
        piece.add(await decrireLigne(e));
      }
      piece.sort(
        (a, b) => cle([
          a['compte'],
          a['debit'],
          a['credit'],
          a['libelle'],
        ]).compareTo(cle([b['compte'], b['debit'], b['credit'], b['libelle']])),
      );
    }
    final lignes =
        [
          for (final l in d.lignes)
            {
              'compte_charge': l.compteCharge,
              'libelle': l.libelle,
              'nature': l.nature,
              'famille': l.famille,
              'montant': chaineDepuisCentimes(l.montant * 100),
            },
        ]..sort(
          (a, b) => cle([
            a['compte_charge'],
            a['libelle'],
            a['montant'],
          ]).compareTo(cle([b['compte_charge'], b['libelle'], b['montant']])),
        );
    final t = d.tresorerie!;
    return {
      'tresorerie': t.code,
      'compte_tresorerie': t.compte,
      'montant_total': chaineDepuisCentimes(d.montantTotal * 100),
      'libelle': d.libelle,
      'date':
          '${d.dateTransaction.year.toString().padLeft(4, '0')}-'
          '${d.dateTransaction.month.toString().padLeft(2, '0')}-'
          '${d.dateTransaction.day.toString().padLeft(2, '0')}',
      'comptabilisee': d.estComptabilisee,
      'numero_piece': numero,
      'ecriture_refus': d.ecritureRefus,
      'lignes': lignes,
      'piece': piece,
    };
  }

  Map<String, Object?> refus(RefusComptable r) {
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

  DateTime date(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  List<SaisieLigneDepense> saisies(List<dynamic> lignes) => [
    for (final l in lignes.cast<Map<String, Object?>>())
      SaisieLigneDepense(
        libelle: l['libelle'] as String,
        compteCharge: l['compte'] as String,
        nature: NatureDepense.depuisLibelle(l['nature'] as String)!,
        montant: int.parse(l['montant'] as String),
      ),
  ];

  Future<int> compter(String table) async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM $table').getSingle())
              .data['n']
          as int;

  final resultats = <Map<String, Object?>>[];

  for (final op in scenario) {
    try {
      switch (op['op']) {
        case 'depense':
          final d = await dao.enregistrer(
            dateTransaction: date(op['date'] as String),
            tresorerie: TresorerieDepense.depuisCode(
              op['tresorerie'] as String,
            )!,
            libelle: op['libelle'] as String,
            lignes: saisies(op['lignes'] as List),
            auteurId: auteurEssai,
            centreId: op['centre'] == null ? null : centres[op['centre']],
          );
          resultats.add({'ok': true, 'depense': await decrire(d)});
        case 'depense_ancienne':
          // Écrite DIRECTEMENT en base : le compte d'une dépense héritée peut
          // ne plus être au plan, et le DAO le refuserait à la saisie.
          serie++;
          final id = 'ancienne-$serie';
          final lignes = (op['lignes'] as List).cast<Map<String, Object?>>();
          await db
              .into(db.depensesLocal)
              .insert(
                DepensesLocalCompanion.insert(
                  id: id,
                  dateTransaction: date(op['date'] as String),
                  tresorerie: op['tresorerie'] as String,
                  libelle: op['libelle'] as String,
                ),
              );
          for (var i = 0; i < lignes.length; i++) {
            await db
                .into(db.lignesDepenseLocal)
                .insert(
                  LignesDepenseLocalCompanion.insert(
                    id: '$id-$i',
                    depenseId: id,
                    libelle: lignes[i]['libelle'] as String,
                    compteCharge: lignes[i]['compte'] as String,
                    nature: lignes[i]['nature'] as String,
                    famille: lignes[i]['famille'] as String,
                    montant: int.parse(lignes[i]['montant'] as String),
                  ),
                );
          }
          anciennes[op['ref'] as String] = id;
          resultats.add({
            'ok': true,
            'depense': await decrire((await dao.parId(id))!),
          });
        case 'rattrapage':
          final id = anciennes[op['ref']]!;
          try {
            final centre = op['centre'] as String?;
            final d = await dao.comptabiliser(
              id,
              auteurId: auteurEssai,
              // Vide quand l'opération n'en nomme aucun : c'est ce que la vue
              // passe au service avec le `<select>` sur « Choisir un centre ».
              centreId: centre == null ? '' : centres[centre]!,
            );
            resultats.add({'ok': true, 'depense': await decrire(d)});
          } on RefusComptable catch (e) {
            resultats.add({
              ...refus(e),
              'depense': await decrire((await dao.parId(id))!),
            });
          }
        case 'poser_centre_defaut':
          await db.customStatement(
            'UPDATE plan_comptable_local SET centre_cout_defaut_id = ? '
            'WHERE numero_compte = ?',
            [centres[op['centre']], op['compte']],
          );
          resultats.add({'ok': true});
        case 'ouvrir_exercice':
          final e = await moteur.ouvrirExercice(op['annee'] as int);
          resultats.add({'ok': true, 'annee': e.annee});
        case 'poser_statut_exercice':
          await db.customStatement(
            'UPDATE exercices_local SET statut = ? WHERE annee = ?',
            [op['statut'], op['annee']],
          );
          resultats.add({'ok': true});
        case 'compter':
          // Le référentiel installé n'écrit aucune écriture : le total de la
          // base est le delta du scénario, comme le script PHP le calcule.
          resultats.add({
            'ok': true,
            'compte': {
              'depenses': await compter('depenses_local'),
              'lignes_depense': await compter('lignes_depense_local'),
              'ecritures': await compter('ecritures_local'),
            },
          });
        case 'libelles':
          resultats.add({
            'ok': true,
            'libelles': {
              'centre': LibellesRattrapage.centre,
              'choisir': LibellesRattrapage.choisir,
              'action': libelleComptabiliser,
              'bandeau': LibellesRattrapage.bandeau(':nombre'),
              'centre_absent': MessagesComptables.dire(
                'depenses.centre_absent',
                {'numero': ':numero'},
              ),
            },
          });
        case 'tresoreries':
          resultats.add({
            'ok': true,
            'tresoreries': {
              for (final t in TresorerieDepense.values)
                t.code: {'compte': t.compte, 'journal': t.journal},
            },
          });
        default:
          throw StateError('Opération inconnue : ${op['op']}');
      }
    } on RefusComptable catch (e) {
      resultats.add(refus(e));
    }
  }
  return resultats;
}
