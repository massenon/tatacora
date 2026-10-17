@Timeout(Duration(minutes: 4))
library;

import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart'
    show PointDeVenteCaisse;
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/calcul_tva.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/pos/data/piece_de_la_vente.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/messages_ventes.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../facturation/support/outils_encaissement.dart'
    show semerReservation, creerClient;
import 'support/outils_ventes.dart';

/// LE MÊME scénario de ventes, joué par les VRAIS composants du serveur
/// (`PosComptant` pour le comptoir, `VenteService` pour la note de chambre et
/// l'appel direct, `CalculTvaService` pour la TVA) sur MySQL — observer RG-11,
/// contraintes, clés étrangères et verrou de séquence compris — et par
/// `PanierDao.cloturer` sur le moteur comptable local, comparé CHAMP À CHAMP :
/// le montant, le mode, le rattachement à la caisse, chaque ligne de la pièce
/// (journal, numéro, date, compte, centre, débit, crédit, statut) et chaque
/// refus (sa PHRASE).
///
/// `tool/ventes/rejouer_ventes.php` travaille sur `tatacora_test` (il refuse
/// toute autre base), sème le référentiel par le vrai seeder, puis ANNULE tout.
/// MySQL injoignable : le test ÉCHOUE, il ne saute pas.
///
/// ## Ce que cette confrontation ne compare PAS, et pourquoi
///
/// * **Le libellé de la pièce** : le serveur y met le numéro `V-AAAA-NNNNN`, le
///   poste n'en a pas. Un test vérifie à part qu'il commence par « Vente ».
/// * **La sortie de stock** (RG-05/06) : non portée par le poste (voir
///   `PanierDao.cloturer`). Le script sème un stock énorme pour qu'AUCUNE
///   rupture ne parle à la place de la pièce.
///
/// Un scénario recopié à la main des deux côtés ne prouverait rien ; celui-ci
/// est UN seul JSON, lu par les deux moteurs.
const _biere = '00000000-0000-4000-8000-0000000000b1';
const _cocktail = '00000000-0000-4000-8000-0000000000b2';
const _ephemere = '00000000-0000-4000-8000-0000000000b3';
const _riz = '00000000-0000-4000-8000-0000000000a1';
const _brochette = '00000000-0000-4000-8000-0000000000a2';

const _catalogue = <Map<String, Object?>>[
  {
    'ref': 'biere',
    'id': _biere,
    'module': 'M5',
    'libelle': 'Béninoise 65cl',
    'prix': '1000',
  },
  {
    'ref': 'cocktail',
    'id': _cocktail,
    'module': 'M5',
    'libelle': 'Cocktail maison',
    'prix': '2500',
  },
  {
    'ref': 'ephemere',
    'id': _ephemere,
    'module': 'M5',
    'libelle': 'Jus du jour',
    'prix': '1500',
  },
  {
    'ref': 'riz',
    'id': _riz,
    'module': 'M4',
    'libelle': 'Riz sauce arachide',
    'prix': '2500',
  },
  {
    'ref': 'brochette',
    'id': _brochette,
    'module': 'M4',
    'libelle': 'Brochettes de bœuf',
    'prix': '3333',
  },
];

Map<String, Object?> _ligne(String ref, int quantite) => {
  'ref': ref,
  'quantite': quantite,
};

Map<String, Object?> _vente(
  String canal,
  String mode,
  List<Map<String, Object?>> lignes, {
  bool session = true,
  List<String> retirer = const [],
}) => {
  'op': 'vente',
  'canal': canal,
  'mode': mode,
  'session': session,
  'lignes': lignes,
  if (retirer.isNotEmpty) 'retirer': retirer,
};

Map<String, Object?> _parametre(String cle, String? valeur) => {
  'op': 'parametre',
  'cle': cle,
  'valeur': valeur,
};

final _scenario = <Map<String, Object?>>[
  {'op': 'libelles'},

  // --- Le comptoir, les quatre modes encaissés : où va l'argent -------------
  _vente('comptoir', 'especes', [_ligne('biere', 3), _ligne('riz', 2)]),
  _vente('comptoir', 'mobile_money', [_ligne('cocktail', 2)]),
  _vente('comptoir', 'carte', [_ligne('brochette', 1), _ligne('biere', 1)]),
  _vente('comptoir', 'virement', [_ligne('riz', 1)]),
  // L'ordre du panier ne change pas la pièce (M4 puis M5).
  _vente('comptoir', 'especes', [_ligne('biere', 2), _ligne('brochette', 2)]),
  {'op': 'compter'},

  // --- Les refus du comptoir, DANS L'ORDRE du serveur -----------------------
  // Panier vide avant tout, caisse fermée comprise.
  _vente('comptoir', 'especes', [], session: false),
  // La note de chambre est refusée AVANT de regarder la caisse.
  _vente('comptoir', 'note_chambre', [_ligne('biere', 1)], session: false),
  _vente('comptoir', 'note_chambre', [_ligne('biere', 1)]),
  // Puis la caisse.
  _vente('comptoir', 'especes', [_ligne('biere', 1)], session: false),
  // Un mode inconnu n'est vu qu'APRÈS la caisse.
  _vente('comptoir', 'cheque', [_ligne('biere', 1)], session: false),
  _vente('comptoir', 'cheque', [_ligne('biere', 1)]),
  {'op': 'compter'},

  // --- Le service : module non encaissable, article retiré, mode ------------
  {
    'op': 'vente',
    'canal': 'service',
    'mode': 'especes',
    'session': true,
    'lignes': [
      {'module': 'M8', 'id': 'veh-1', 'quantite': 1},
    ],
  },
  // Le module est jugé AVANT la référence, ligne par ligne, dans l'ordre.
  {
    'op': 'vente',
    'canal': 'service',
    'mode': 'especes',
    'session': true,
    'lignes': [
      {'ref': 'biere', 'quantite': 1},
      {'module': 'M9', 'id': 'cir-1', 'quantite': 1},
    ],
  },
  _vente(
    'service',
    'especes',
    [_ligne('ephemere', 2), _ligne('biere', 1)],
    retirer: ['ephemere'],
  ),
  {'op': 'compter'},

  // --- La TVA : l'intention (tva_active) et la capacité (le taux) -----------
  _parametre('tva_active', 'true'),
  // Active SANS taux : la vente est refusée, rien n'est écrit.
  _vente('comptoir', 'especes', [_ligne('biere', 3), _ligne('riz', 2)]),
  _parametre('taux_tva', '18'),
  // Convention absente = « ht » : la taxe n'est PAS ajoutée (défaut du
  // serveur, répliqué) — aucune ligne de TVA, mais le taux était exigé.
  _vente('comptoir', 'especes', [_ligne('biere', 3), _ligne('riz', 2)]),
  _parametre('convention_prix', 'ttc'),
  _vente('comptoir', 'especes', [_ligne('biere', 3), _ligne('riz', 2)]),
  // TVA sur UN SEUL module : la ligne de l'autre compte n'existe pas.
  _vente('comptoir', 'mobile_money', [_ligne('cocktail', 3)]),
  _vente('comptoir', 'carte', [_ligne('riz', 4)]),
  // Une note de chambre : 4111 au débit, mêmes lignes de TVA.
  _vente('sejour', 'note_chambre', [
    _ligne('biere', 5),
    _ligne('brochette', 3),
  ]),
  // Des arrondis qui ne tombent pas juste.
  _parametre('taux_tva', '18.5'),
  _vente('comptoir', 'virement', [
    _ligne('brochette', 7),
    _ligne('cocktail', 1),
  ]),
  _parametre('taux_tva', '5.55'),
  _vente('comptoir', 'especes', [_ligne('brochette', 3), _ligne('biere', 7)]),
  _parametre('taux_tva', '0'),
  _vente('comptoir', 'especes', [_ligne('biere', 1), _ligne('riz', 1)]),
  // La convention est normalisée comme le serveur (trim + minuscules).
  _parametre('taux_tva', '18'),
  _parametre('convention_prix', '  TTC '),
  _vente('comptoir', 'especes', [_ligne('biere', 2)]),
  // Illisible : refus, et la CONVENTION est jugée avant le taux.
  _parametre('convention_prix', 'xyz'),
  _vente('comptoir', 'especes', [_ligne('biere', 2)]),
  _parametre('taux_tva', null),
  _vente('comptoir', 'especes', [_ligne('biere', 2)]),
  _parametre('convention_prix', 'ttc'),
  // Un taux blanc vaut un taux absent (`blank()`).
  _parametre('taux_tva', '   '),
  _vente('comptoir', 'especes', [_ligne('biere', 2)]),
  _parametre('taux_tva', '18'),
  // `filter_var(FILTER_VALIDATE_BOOLEAN)` : « on », « yes », « 1 » sont vrais,
  // « oui » et « 0 » ne le sont pas.
  _parametre('tva_active', 'on'),
  _vente('comptoir', 'especes', [_ligne('riz', 1)]),
  _parametre('tva_active', '1'),
  _vente('comptoir', 'especes', [_ligne('riz', 1)]),
  _parametre('tva_active', 'oui'),
  _vente('comptoir', 'especes', [_ligne('riz', 1)]),
  _parametre('tva_active', '0'),
  _vente('comptoir', 'especes', [_ligne('riz', 1)]),
  _parametre('tva_active', 'true'),
  _vente('sejour', 'note_chambre', [_ligne('riz', 2)]),
  _parametre('tva_active', 'false'),
  _vente('sejour', 'note_chambre', [_ligne('riz', 2), _ligne('biere', 1)]),
  {'op': 'compter'},

  // --- L'exercice : absent, puis non ouvert --------------------------------
  // Avant 2038 : une colonne TIMESTAMP de MySQL ne va pas plus loin, et le
  // panier du serveur y échouerait pour une tout autre raison.
  {'op': 'horloge', 'date': '2035-01-02'},
  _vente('comptoir', 'especes', [_ligne('biere', 1)]),
  {'op': 'horloge', 'date': '2031-06-15'},
  {'op': 'statut_exercice', 'annee': 2031, 'statut': 'en_cloture'},
  _vente('comptoir', 'especes', [_ligne('biere', 1)]),
  _vente('sejour', 'note_chambre', [_ligne('biere', 1)]),
  {'op': 'compter'},
];

/// Le scénario où le centre « Bar » a disparu : RG-12 refuse, naming le compte.
final _scenarioSansCentre = <Map<String, Object?>>[
  {'op': 'retirer_centre', 'libelle': 'Bar'},
  _vente('comptoir', 'especes', [_ligne('biere', 1)]),
  // Le restaurant a son centre : la vente M4 seule passe.
  _vente('comptoir', 'especes', [_ligne('riz', 1)]),
  // Mixte : le Bar manque, donc TOUT est refusé (rien d'écrit).
  _vente('comptoir', 'especes', [_ligne('riz', 1), _ligne('biere', 1)]),
  {'op': 'compter'},
];

/// La phrase « Accepter la ligne obligerait l'écran à transmettre un prix au
/// clavier… » du serveur (`ventes.module_non_encaissable`, seconde phrase) est
/// RETIRÉE de l'écran du poste (directive du PO, 14/10/2026). On la retranche
/// du résultat du serveur avant comparaison — et SEULEMENT elle : tout autre
/// écart reste rouge.
dynamic _sansFinRetiree(dynamic resultat) {
  if (resultat is! Map || resultat['refus'] is! String) return resultat;
  const marque = ' Accepter la ligne obligerait';
  final refus = resultat['refus'] as String;
  final i = refus.indexOf(marque);
  if (i < 0) return resultat;
  return {...resultat, 'refus': refus.substring(0, i)};
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;
  late List<dynamic> serveurSansCentre;
  late List<Map<String, Object?>> localSansCentre;

  setUpAll(() async {
    final r = await executerPhp(
      'rejouer_ventes.php',
      dossier: 'ventes',
      entree: {
        'aujourdhui': '2031-06-15',
        'catalogue': _catalogue,
        'ops': _scenario,
      },
    );
    serveur = r['resultats'] as List<dynamic>;
    local = await _jouerLocalement(_scenario);

    final r2 = await executerPhp(
      'rejouer_ventes.php',
      dossier: 'ventes',
      entree: {
        'aujourdhui': '2031-06-15',
        'catalogue': _catalogue,
        'ops': _scenarioSansCentre,
      },
    );
    serveurSansCentre = r2['resultats'] as List<dynamic>;
    localSansCentre = await _jouerLocalement(_scenarioSansCentre);
  });

  test('chaque opération du scénario a un résultat des deux côtés', () {
    expect(serveur, hasLength(_scenario.length));
    expect(local, hasLength(_scenario.length));
    expect(serveurSansCentre, hasLength(_scenarioSansCentre.length));
    expect(localSansCentre, hasLength(_scenarioSansCentre.length));
  });

  test('chaque résultat est identique au serveur, opération par opération', () {
    for (var i = 0; i < _scenario.length; i++) {
      // Les phrases sont comparées à part, une à une (voir plus bas).
      if (_scenario[i]['op'] == 'libelles') continue;
      expect(
        local[i],
        equals(_sansFinRetiree(serveur[i])),
        reason: 'opération $i : ${_scenario[i]}',
      );
    }
  });

  test('sans le centre « Bar », même résultat que le serveur (RG-12)', () {
    for (var i = 0; i < _scenarioSansCentre.length; i++) {
      expect(
        localSansCentre[i],
        equals(serveurSansCentre[i]),
        reason: 'opération $i : ${_scenarioSansCentre[i]}',
      );
    }
    // Le refus nomme le COMPTE, jamais un centre deviné.
    expect(
      (serveurSansCentre[1] as Map)['refus'],
      contains('7011'),
      reason: 'le refus nomme le compte de produits du bar',
    );
    // La vente du restaurant seul passe ; la mixte est refusée en bloc.
    expect((serveurSansCentre[2] as Map)['ok'], isTrue);
    expect((serveurSansCentre[3] as Map).containsKey('refus'), isTrue);
    expect((serveurSansCentre[4] as Map)['compte'], {
      'ventes': 1,
      'ecritures': 2,
    });
  });

  test('le scénario éprouve les chemins qui comptent (pas un vert à vide)', () {
    final ok = serveur.where((r) => (r as Map)['piece'] != null).toList();
    final refus = serveur.where((r) => (r as Map).containsKey('refus'));
    final comptes = <String>{
      for (final r in ok)
        for (final l in ((r as Map)['piece'] as List))
          (l as Map)['compte'] as String,
    };
    // Les trois trésoreries, la créance client, les deux produits, les deux TVA.
    expect(
      comptes,
      containsAll(<String>[
        '5711',
        '552',
        '5211',
        '4111',
        '7011',
        '7061',
        '4431',
        '4432',
      ]),
    );
    // Une dizaine de refus, tous de causes différentes.
    expect(refus.length, greaterThanOrEqualTo(14));
    final phrases = {for (final r in refus) (r as Map)['refus'] as String};
    expect(phrases.length, greaterThanOrEqualTo(10));
    // Les pièces portent le NET encaissé : débit = somme des crédits.
    for (final r in ok) {
      final piece = ((r as Map)['piece'] as List).cast<Map<String, dynamic>>();
      var debit = 0;
      var credit = 0;
      for (final l in piece) {
        debit += centimesDepuisChaine(l['debit'] as String);
        credit += centimesDepuisChaine(l['credit'] as String);
      }
      expect(debit, credit);
      expect(debit, centimesDepuisChaine(r['montant'] as String));
    }
  });

  test('un refus n’écrit RIEN : les comptes sont ceux des seuls succès', () {
    final comptes = [
      for (final r in serveur)
        if ((r as Map).containsKey('compte')) r['compte'] as Map,
    ];
    // 5 ventes -> 5 + 4 (carte : 3 lignes... ) : on lit plutôt l'invariant
    // « écritures = somme des lignes des pièces des succès jusque-là ».
    var attendu = 0;
    var ventes = 0;
    var index = 0;
    for (var i = 0; i < _scenario.length; i++) {
      final res = serveur[i] as Map;
      if (res['piece'] != null) {
        attendu += (res['piece'] as List).length;
        ventes++;
      }
      if (_scenario[i]['op'] == 'compter') {
        expect(comptes[index]['ecritures'], attendu, reason: 'compteur $index');
        expect(comptes[index]['ventes'], ventes, reason: 'compteur $index');
        index++;
      }
    }
    expect(index, comptes.length);
    expect(attendu, greaterThan(40));
  });

  test('le libellé de la pièce commence par « Vente » (écart nommé : pas de '
      'numéro V-)', () {
    final libelle = libelleDeLaPiece('3f2a1b9c-0000-4000-8000-000000000001');
    expect(libelle, startsWith('Vente '));
    expect(libelle, contains('3F2A1B9C'));
    expect(libelle, contains('3f2a1b9c-0000-4000-8000-000000000001'));
    // Deux paniers n'ont jamais le même libellé : l'identifiant entier y est.
    expect(
      libelleDeLaPiece('aaaaaaaa-0000-4000-8000-000000000001'),
      isNot(libelleDeLaPiece('aaaaaaaa-0000-4000-8000-000000000002')),
    );
  });

  test('les phrases et les tables sont celles du serveur, lues par PHP', () {
    final l = (serveur.first as Map)['libelles'] as Map<dynamic, dynamic>;
    expect(l['refus_panier_vide'], const PanierVide.auComptoir().message);
    expect(l['panier_vide'], const PanierVide.auComptoir().message);
    expect(
      l['refus_note_chambre_comptoir'],
      MessagesVentes.noteChambreAuComptoir,
    );
    expect(l['mode_paiement_inconnu'], MessagesVentes.modeInconnu(':mode'));
    expect(
      l['reference_inconnue'],
      MessagesVentes.referenceInconnue(':reference'),
    );
    // Le poste rend la PREMIÈRE phrase du serveur ; la seconde (« Accepter la
    // ligne… anti-patron… ») est retirée de l'écran par directive du PO du
    // 14/10/2026. Le début reste celui du serveur, au mot.
    expect(
      l['module_non_encaissable'],
      startsWith(MessagesVentes.moduleNonEncaissable(':module')),
    );
    expect(
      (_sansFinRetiree({'refus': l['module_non_encaissable']}) as Map)['refus'],
      MessagesVentes.moduleNonEncaissable(':module'),
    );
    expect(
      l['compte_produit_absent'],
      MessagesVentes.compteProduitAbsent(':module'),
    );
    expect(
      l['convention_inconnue'],
      PhrasesTva.conventionInconnue(':convention', ':cle'),
    );
    expect(l['taux_absent'], PhrasesTva.tauxAbsent(':cle'));
    expect(l['refus_sans_caisse'], contains('Aucune caisse'));

    // Les tables : le journal, les comptes, les centres, les contreparties.
    expect(l['journal'], journalDesVentes);
    expect(l['modules_encaissables'], modulesEncaissables);
    expect(l['comptes_produit'], comptesProduitParModule);
    expect(l['comptes_tva'], comptesTvaParModule);
    expect(l['centres_par_module'], centresParModule);
    expect(
      l['compte_clients'],
      compteDeContrepartie(ModeReglement.noteChambre),
    );
    expect(l['modules'], MessagesVentes.modulesDuServeur);
    final contreparties = (l['contreparties'] as Map).cast<String, String>();
    expect(contreparties.length, 4);
    for (final e in contreparties.entries) {
      final mode = ModeReglement.parCode(e.key);
      expect(
        compteDeContrepartie(mode),
        TresorerieDepense.depuisCode(e.value)!.compte,
        reason: e.key,
      );
    }
    // Non vide : sinon l'égalité ci-dessus comparerait des vides.
    expect(l['comptes_produit'], isNotEmpty);
  });

  test('la TVA du poste est celle de bcmath, centime pour centime', () async {
    // Des montants choisis pour tomber sur les arrondis (demi-centimes), des
    // taux à 0, 1, 2 et 7 décimales, les deux conventions.
    final hasard = Random(20261012);
    final montants = <int>[
      1,
      2,
      5,
      7,
      99,
      100,
      101,
      333,
      1000,
      1234,
      3333,
      9999,
      100000,
      250000,
      333300,
      999999,
      12345678,
      for (var i = 0; i < 160; i++) 1 + hasard.nextInt(40000000),
    ];
    const taux = [
      '18',
      '18.00',
      '18.5',
      '5.55',
      '0',
      '100',
      '7.777777',
      '0.01',
      '19.999999',
      '3.1234567',
      '12.3456789012',
      '1',
      '33.3333',
    ];

    final ops = <Map<String, Object?>>[
      for (final t in taux)
        for (final c in ['ttc', 'ht'])
          {
            'op': 'ventiler',
            'taux': t,
            'convention': c,
            'montants': [for (final m in montants) chaineDepuisCentimes(m)],
          },
    ];
    final r = await executerPhp(
      'rejouer_ventes.php',
      dossier: 'ventes',
      entree: {'aujourdhui': '2031-06-15', 'catalogue': <Object>[], 'ops': ops},
    );
    final resultats = r['resultats'] as List<dynamic>;

    var compares = 0;
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      final parametres = ParametresTva(
        active: 'true',
        taux: op['taux'] as String,
        convention: op['convention'] as String,
      );
      final attendues = ((resultats[i] as Map)['ventilations'] as List)
          .cast<Map<String, dynamic>>();
      for (var k = 0; k < montants.length; k++) {
        final v = parametres.ventiler(montants[k]);
        final a = attendues[k];
        final cas = 'taux ${op['taux']} ${op['convention']} ${montants[k]}';
        expect(chaineDepuisCentimes(v.htCentimes), a['ht'], reason: cas);
        expect(chaineDepuisCentimes(v.tvaCentimes), a['tva'], reason: cas);
        expect(chaineDepuisCentimes(v.ttcCentimes), a['ttc'], reason: cas);
        compares++;
      }
    }
    // 13 taux x 2 conventions x 177 montants : un balayage qui ne comparerait
    // rien serait vert à vide.
    expect(compares, 13 * 2 * montants.length);
    expect(compares, greaterThan(4000));
  }, timeout: const Timeout(Duration(minutes: 3)));
}

/// Joue le scénario avec `PanierDao.cloturer` sur le moteur local, dans le
/// format de sortie du script PHP.
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> scenario,
) async {
  var maintenant = DateTime(2031, 6, 15, 10);
  DateTime horloge() => maintenant;

  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  // Le référentiel est installé par la vraie fonction, à la date du scénario :
  // l'exercice 2031 est ouvert, comme le seeder du serveur l'ouvre pour l'année
  // du jour.
  await baseInstalleeSur(db, DateTime(2031, 6, 15));

  // Le catalogue local — les MÊMES identifiants que le serveur.
  await db
      .into(db.menusLocal)
      .insert(
        MenusLocalCompanion.insert(
          id: 'm-1',
          libelle: 'Carte principale',
          type: 'local',
          creeLe: DateTime(2031, 1, 1),
          creePar: auteurEssai,
        ),
      );
  await db
      .into(db.recettesLocal)
      .insert(
        RecettesLocalCompanion.insert(
          id: 'r-1',
          libelle: 'Fiche',
          creeLe: DateTime(2031, 1, 1),
          creePar: auteurEssai,
        ),
      );
  final articles = <String, ArticleVendable>{};
  for (final a in _catalogue) {
    final module = a['module'] as String;
    final prix = int.parse(a['prix'] as String);
    final id = a['id'] as String;
    if (module == 'M5') {
      await db
          .into(db.cartesBoissonLocal)
          .insert(
            CartesBoissonLocalCompanion.insert(
              id: id,
              articleId: 'art-$id',
              libelle: a['libelle'] as String,
              categorie: 'locale',
              prixVente: prix.toDouble(),
            ),
          );
    } else {
      await db
          .into(db.platsLocal)
          .insert(
            PlatsLocalCompanion.insert(
              id: id,
              menuId: 'm-1',
              recetteId: 'r-1',
              libelle: a['libelle'] as String,
              prixVente: prix,
              creeLe: DateTime(2031, 1, 1),
              creePar: auteurEssai,
            ),
          );
    }
    articles[a['ref'] as String] = ArticleVendable(
      reference: ReferenceCatalogue(
        module: ModuleVendable.depuisCode(module),
        code: id,
      ),
      libelle: a['libelle'] as String,
      prix: prix,
    );
  }
  // Un véhicule et un circuit : le poste offre ces rayons au panier (le serveur
  // les refuse dès l'ajout), et leur clôture doit être refusée.
  await db
      .into(db.vehiculesLocal)
      .insert(
        VehiculesLocalCompanion.insert(
          id: 'veh-1',
          categorie: 'Berline',
          immatriculation: 'AB-123-BJ',
          tarifJour: 25000,
          statut: 'disponible',
        ),
      );
  await db
      .into(db.circuitsLocal)
      .insert(
        CircuitsLocalCompanion.insert(
          id: 'cir-1',
          nom: 'Cascades de Tanougou',
          theme: 'Nature',
          zone: 'Atacora',
          prix: 4500,
          capaciteMax: 12,
        ),
      );
  final client = await creerClient(db);
  await semerReservation(db, id: 'res-1', clientId: client.id);

  final dao = panierDaoSur(db, lireHorloge: horloge);
  final compta = ComptabiliteDao(db);
  final parametres = ParametresDao(db);
  final caisse = SessionsCaisseDao(db, maintenant: horloge);

  final journaux = {for (final j in await compta.journaux()) j.id: j.code};
  final libellesCentre = {
    for (final c in await compta.centres()) c.id: c.libelle,
  };
  final departEcritures = (await compta.toutesLesEcritures()).length;

  Future<Map<String, Object?>> decrireLigne(EcritureComptable e) async {
    final compte = (await compta.compteParId(e.compteId))!;
    return {
      'numero_piece': e.numeroPiece,
      'journal': journaux[e.journalId],
      'date': e.dateEcriture,
      'compte': compte.numero,
      'centre': libellesCentre[e.centreId],
      'debit': e.debit,
      'credit': e.credit,
      'statut': e.statut.valeur,
    };
  }

  String cle(Map<String, Object?> l) =>
      [l['compte'], l['debit'], l['credit']].join('|');

  Future<void> poserSession({required bool ouverte}) async {
    final existantes = await (db.select(
      db.sessionsCaisseLocal,
    )..where((s) => s.dateCloture.isNull())).get();
    if (ouverte) {
      if (existantes.isEmpty) {
        await caisse.ouvrir(
          point: PointDeVenteCaisse.bar,
          fondSaisi: '10000',
          auteurId: auteurEssai,
          peutEcrire: true,
        );
      }
      return;
    }
    await db.customStatement(
      'UPDATE sessions_caisse_local SET date_cloture = ? WHERE date_cloture IS NULL',
      [maintenant.millisecondsSinceEpoch ~/ 1000],
    );
  }

  final resultats = <Map<String, Object?>>[];

  for (final op in scenario) {
    switch (op['op']) {
      case 'libelles':
        // Lu du serveur : le poste n'a rien à dire ici.
        resultats.add(<String, Object?>{'libelles': true});
      case 'parametre':
        await parametres.ecrire({
          op['cle'] as String: op['valeur'] as String?,
        }, auteurId: null);
        resultats.add({'ok': true});
      case 'horloge':
        final p = (op['date'] as String).split('-').map(int.parse).toList();
        maintenant = DateTime(p[0], p[1], p[2], 10);
        resultats.add({'ok': true});
      case 'statut_exercice':
        await db.customStatement(
          'UPDATE exercices_local SET statut = ? WHERE annee = ?',
          [op['statut'], op['annee']],
        );
        resultats.add({'ok': true});
      case 'retirer_centre':
        await db.customStatement(
          'DELETE FROM centres_cout_local WHERE libelle = ?',
          [op['libelle']],
        );
        resultats.add({'ok': true});
      case 'compter':
        final fermes = await db
            .customSelect(
              "SELECT COUNT(*) AS n FROM paniers_local WHERE statut = 'cloture'",
            )
            .getSingle();
        resultats.add({
          'ok': true,
          'compte': {
            'ventes': fermes.data['n'] as int,
            'ecritures':
                (await compta.toutesLesEcritures()).length - departEcritures,
          },
        });
      case 'vente':
        final canal = op['canal'] as String;
        final sejour = canal == 'sejour';
        if (!sejour) {
          await poserSession(ouverte: op['session'] as bool);
        }

        final panier = await dao.ouvrir(
          typeVente: sejour ? TypeVente.surSejour : TypeVente.comptant,
          pointVente: sejour ? null : 'Comptoir',
          reservationId: sejour ? 'res-1' : null,
          dateDepartPrevue: sejour ? DateTime(2026, 10, 22) : null,
        );
        for (final l in (op['lignes'] as List).cast<Map<String, Object?>>()) {
          final ArticleVendable article;
          if (l['ref'] != null) {
            article = articles[l['ref'] as String]!;
          } else {
            // Un véhicule ou un circuit : le poste les offre au panier.
            final module = l['module'] as String;
            article = ArticleVendable(
              reference: ReferenceCatalogue(
                module: ModuleVendable.depuisCode(module),
                code: l['id'] as String,
              ),
              libelle: module == 'M8' ? 'Berline' : 'Cascades',
              prix: module == 'M8' ? 25000 : 4500,
            );
          }
          await dao.ajouterLigne(
            panier.id,
            article,
            quantite: l['quantite'] as int,
          );
        }
        // Un article RETIRÉ du catalogue entre l'ajout et la clôture.
        for (final ref in (op['retirer'] as List? ?? const []).cast<String>()) {
          await db.customStatement(
            'DELETE FROM cartes_boisson_local WHERE id = ?',
            [articles[ref]!.reference.code],
          );
        }

        try {
          final cloture = await dao.cloturer(
            panier.id,
            modePaiement: op['mode'] as String,
            anticipe: true,
            auteurId: auteurEssai,
          );
          final piece = <Map<String, Object?>>[
            for (final e in await compta.lignesParLibelle(
              libelleDeLaPiece(cloture.id),
            ))
              await decrireLigne(e),
          ]..sort((a, b) => cle(a).compareTo(cle(b)));
          final mode = ModeReglement.parCode(cloture.modePaiement!);
          resultats.add({
            'ok': true,
            'montant': chaineDepuisCentimes(cloture.montantCloture! * 100),
            'mode': mode.code,
            'encaisse': mode.encaisse,
            'session': cloture.sessionEncaissementId != null,
            'piece': piece,
          });
        } on PanierVide catch (e) {
          resultats.add({'refus': e.message});
          await dao.annuler(panier.id, 'essai');
        } on RefusVente catch (e) {
          resultats.add({'refus': e.message});
          await dao.annuler(panier.id, 'essai');
        } on RefusTva catch (e) {
          resultats.add({'refus': e.message});
          await dao.annuler(panier.id, 'essai');
        } on RefusCaisse catch (e) {
          resultats.add({'refus': e.message});
          await dao.annuler(panier.id, 'essai');
        } on RefusComptable catch (e) {
          resultats.add({'refus': e.message});
          await dao.annuler(panier.id, 'essai');
        }
      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}
