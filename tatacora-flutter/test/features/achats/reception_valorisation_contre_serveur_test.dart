@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/bon_reception.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// LA RÉCEPTION M7 ET SA VALORISATION, jouées par le vrai `ReceptionService`
/// (et le vrai composant `Approvisionnement`) du serveur sur MySQL, puis par le
/// poste sur sa base locale — D132.
///
/// La question posée au serveur, par EXÉCUTION : *la réception valorise-t-elle
/// l'entrée de stock ?* Réponse relevée : NON. `ReceptionService::receptionner`
/// appelle `MouvementStockService::entree()` sans coût, et `entree()` ne
/// valorise que si on lui en passe un. Après une réception, le coût moyen
/// pondéré et le dernier prix d'achat de chaque article sont exactement ceux
/// d'avant ; un article qui n'est jamais entré que par réception garde le coût
/// `0.0000` du schéma et n'a aucun `prix_achat`.
///
/// Le poste valorisait pourtant, au prix de la ligne de commande (D131 : « le
/// serveur n'exécute pas son intention »). Il ne le fait plus : ce test pose
/// que, sur le MÊME scénario, le poste et le serveur rendent les mêmes stocks,
/// les mêmes coûts, les mêmes derniers prix et les mêmes valeurs.
///
/// ## Ce que le test épingle aussi : deux phrases FAUSSES du serveur
///
/// Le message de succès (`achats_pwa.appro.reception_enregistree`) dit « stock et
/// coût moyen pondéré mis à jour », et le sous-titre de l'onglet Réceptions « une
/// entrée de stock valorisée au prix de la commande, qui a recalculé le coût
/// moyen pondéré ». Le même scénario montre que le coût n'a pas bougé. Le test
/// le ÉCRIT : le jour où le serveur corrige l'une ou l'autre, il échoue et force
/// à retirer l'écart du ticket (D266). Aucune de ces phrases n'est corrigée ici.
///
/// ## Le « coût 0.0000 » du serveur et le « — » du poste
///
/// Un article jamais valorisé a, au serveur, un coût moyen pondéré de `0.0000` ;
/// le poste dit « inconnu » (`cmpInconnu`) plutôt que d'afficher un zéro qui se
/// somme (D130). Les deux sont ramenés à la même chose avant la comparaison :
/// *pas de coût connu*. La VALEUR en francs est la même (zéro) des deux côtés.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const aujourdhui = '2026-10-13';
  final maintenant = DateTime(2026, 10, 13, 10);

  Map<String, Object?> entree(String article, String quantite, String? cout) =>
      {
        'op': 'entree',
        'article': article,
        'point': 'p1',
        'quantite': quantite,
        'cout': cout,
        'user': 'g',
      };
  Map<String, Object?> reception(String commande, Map<String, String> q) => {
    'op': 'reception',
    'commande': commande,
    'user': 'g',
    'point': 'p1',
    'quantites': q,
  };
  Map<String, Object?> commande(
    String ref,
    List<List<String>> lignes, {
    String date = '2026-10-01',
  }) => {
    'op': 'commande',
    'ref': ref,
    'fournisseur': 'f1',
    'user': 'g',
    'date': date,
    'statut': 'envoyee',
    'lignes': [
      for (final l in lignes) {'article': l[0], 'quantite': l[1], 'prix': l[2]},
    ],
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'libelles'},
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'point', 'ref': 'p1', 'libelle': 'Magasin'},
    // a1 : une entrée valorisée à 500 ; a2 : JAMAIS valorisé ; a3 : deux
    // entrées valorisées (800 puis 1 000 : CMP 900, dernier prix 1 000) ;
    // a4 : hors commande.
    {'op': 'article', 'ref': 'a1', 'libelle': 'Sucre', 'seuil': '4'},
    {'op': 'article', 'ref': 'a2', 'libelle': 'Farine', 'seuil': '4'},
    {'op': 'article', 'ref': 'a3', 'libelle': 'Huile', 'seuil': '4'},
    {'op': 'article', 'ref': 'a4', 'libelle': 'Sel', 'seuil': '4'},
    entree('a1', '2', '500'),
    entree('a3', '10', '800'),
    entree('a3', '10', '1000'),
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Grand Marche SARL'},
    commande('c1', [
      ['a1', '4', '1000'],
      ['a2', '6', '250'],
      ['a3', '10', '1200'],
    ]),
    {'op': 'etat_stock'},

    // --- Sans tolérance configurée : la réception est REFUSÉE (RG-10) -------
    reception('c1', {'a1': '4', 'a2': '6', 'a3': '10'}),
    {'op': 'etat_stock'},
    {'op': 'tolerance', 'valeur': '5'},

    // --- Une réception partielle : trois articles, trois prix de commande ----
    reception('c1', {'a1': '4', 'a2': '3', 'a3': '10'}),
    {'op': 'etat_stock'},

    // --- Une seconde réception du même bon, et un article HORS commande ------
    reception('c1', {'a2': '3', 'a4': '2'}),
    {'op': 'etat_stock'},

    // --- Par le composant (la PWA) : même chose, et son message de succès ----
    commande('c2', [
      ['a1', '10', '1500'],
    ], date: '2026-10-05'),
    {
      'op': 'reception_pwa',
      'commande': 'c2',
      'user': 'g',
      'point': 'p1',
      'quantites': {'a1': '10'},
    },
    {'op': 'etat_stock'},
    {'op': 'bons'},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_receptions.php',
      dossier: 'achats',
      entree: {'aujourdhui': aujourdhui, 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _rejouerSurLePoste(scenario, maintenant);
  });

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));

    final issues = [for (final r in serveur) r as Map<String, dynamic>];
    // Le serveur a REFUSÉ une réception (tolérance absente) et en a ACCEPTÉ
    // d'autres : un scénario où tout passe ne comparerait pas le refus.
    expect(issues.where((i) => i['refus'] != null), hasLength(1));
    expect(issues.where((i) => i['conformite'] != null), hasLength(2));
    // Des articles valorisés ET un jamais valorisé : la valorisation a de quoi
    // se voir.
    final avant = issues[scenario.indexWhere((o) => o['op'] == 'etat_stock')];
    final articles = (avant['articles'] as Map).cast<String, dynamic>();
    expect(_a(articles, 'a1')['prix_achat'], '500.0000');
    expect(_a(articles, 'a2')['prix_achat'], isNull);
    expect(_a(articles, 'a3')['cmp'], '900.0000');
  });

  test('chaque opération rend le MÊME résultat des deux côtés', () {
    final ecarts = <String>[];
    for (var i = 0; i < scenario.length; i++) {
      final s = _normaliserServeur(serveur[i] as Map<String, dynamic>);
      final l = _normaliserLocal(local[i]);
      if (_canon(s) != _canon(l)) {
        ecarts.add('op #$i ${scenario[i]}\n  ${_difference(s, l)}');
      }
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });

  test('LA question : la réception ne change NI le coût moyen pondéré NI le '
      'dernier prix — relevé sur le serveur', () {
    final avant = _etat(serveur, scenario, rang: 0);
    final apres = _etat(serveur, scenario, rang: 2);

    // a1 : valorisé à 500 avant, commandé à 1 000, 4 reçus -> toujours 500.
    expect(_a(apres, 'a1')['cmp'], _a(avant, 'a1')['cmp']);
    expect(_a(apres, 'a1')['prix_achat'], _a(avant, 'a1')['prix_achat']);
    expect(_a(avant, 'a1')['cmp'], '500.0000');
    // a3 : valorisé (CMP 900, dernier prix 1 000), commandé à 1 200 -> inchangés.
    expect(_a(apres, 'a3')['cmp'], '900.0000');
    expect(_a(apres, 'a3')['prix_achat'], '1000.0000');
    // a2 : JAMAIS valorisé -> le coût du schéma, aucun prix d'achat.
    expect(_a(apres, 'a2')['cmp'], '0.0000');
    expect(_a(apres, 'a2')['prix_achat'], isNull);
    // Le stock, lui, a bien bougé (la réception a écrit ses entrées).
    expect(_a(avant, 'a1')['stock'], '2.00');
    expect(_a(apres, 'a1')['stock'], '6.00');
    expect(_a(apres, 'a2')['stock'], '3.00');
    expect(_a(apres, 'a3')['stock'], '30.00');
  });

  test('le serveur DIT le contraire de ce qu’il fait (D266) — épinglé', () {
    final lib =
        (serveur[0] as Map<String, dynamic>)['libelles']
            as Map<String, dynamic>;
    // Les deux phrases fausses, telles que le serveur les écrit.
    expect(
      lib['reception_enregistree'],
      contains('coût moyen pondéré mis à jour'),
    );
    expect(
      lib['receptions_detail'],
      contains('valorisée au prix de la commande'),
    );
    expect(
      lib['form_avertissement_double'],
      contains('met à jour le coût moyen'),
    );
    // Et le poste ne les REPRODUIT PAS (D276, décision du Lead : la règle
    // d'honnêteté de l'argent prévaut sur la fidélité littérale) : aucun
    // gabarit de succès n'est porté, aucune des trois affirmations n'est dans
    // le code rendu du module.
    // R-G (D285) : tout `lib/`, plus le seul module des achats.
    // Balayage non vide, et qui dépasse réellement M7 : le même plancher que
    // `conformite_achats_test.dart` (R6 du contrôle du 12/10/2026). Un
    // `isNotEmpty` seul resterait vert sur le seul module des achats — la garde
    // ne verrait alors plus la phrase fausse posée ailleurs (stock, M11, état).
    expect(
      Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where(
            (f) => !f.path.replaceAll(r'\', '/').contains('features/achats/'),
          ),
      hasLength(greaterThan(300)),
    );
    final code = _codeSansCommentaires(Directory('lib'));
    expect(code, isNotEmpty);
    expect(code, isNot(contains('receptionEnregistree')));
    for (final fausse in const [
      'valorisée au prix de la commande',
      'recalculé le coût moyen',
      'met à jour le coût moyen',
      'coût moyen pondéré mis à jour',
    ]) {
      expect(code, isNot(contains(fausse)), reason: fausse);
    }
    // Preuve que ces phrases mentent : le même scénario, le coût n'a pas bougé.
    final apres = _etat(serveur, scenario, rang: 4);
    expect(_a(apres, 'a1')['cmp'], '500.0000');
  });

  test('la modale se ferme sans erreur au serveur comme au poste ; le message '
      'de succès du serveur n’est PAS porté (D276)', () {
    final i = scenario.indexWhere((o) => o['op'] == 'reception_pwa');
    final s = serveur[i] as Map<String, dynamic>;
    expect(s['modale_fermee'], isTrue);
    expect(s['erreurs'], isEmpty);
    // Le serveur affiche un succès qui ment sur le coût...
    expect(s['succes'], contains('coût moyen pondéré mis à jour'));
    // ...le poste, lui, ferme la modale et ne dit rien de tel.
    expect(local[i]['modale_fermee'], isTrue);
    expect(local[i].containsKey('succes'), isFalse);
  });
}

/// Un article d'un relevé, typé : le JSON du serveur est dynamique.
Map<String, dynamic> _a(Map<String, dynamic> releve, String ref) =>
    (releve[ref] as Map).cast<String, dynamic>();

/// L'état des stocks du serveur, au [rang]-ième relevé `etat_stock`.
Map<String, dynamic> _etat(
  List<dynamic> serveur,
  List<Map<String, Object?>> scenario, {
  required int rang,
}) {
  var vu = -1;
  for (var i = 0; i < scenario.length; i++) {
    if (scenario[i]['op'] == 'etat_stock' && ++vu == rang) {
      return ((serveur[i] as Map<String, dynamic>)['articles'] as Map)
          .cast<String, dynamic>();
    }
  }
  fail('Relevé $rang introuvable');
}

// ------------------------------------------------------- rejeu sur le poste

Future<List<Map<String, Object?>>> _rejouerSurLePoste(
  List<Map<String, Object?>> scenario,
  DateTime maintenant,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db, id: 'u-g');

  final stocks = StocksDao(db, maintenant: () => maintenant);
  final achats = AchatsDao(db, stocks: stocks, maintenant: () => maintenant);

  final points = <String, String>{};
  final articles = <String, String>{};
  final fournisseurs = <String, String>{};
  final commandes = <String, String>{};
  final resultats = <Map<String, Object?>>[];

  String refArticle(String id) =>
      articles.entries.firstWhere((e) => e.value == id).key;

  for (final op in scenario) {
    switch (op['op']) {
      case 'libelles':
        resultats.add({'libelles': 'rien'});

      case 'utilisateur':
        resultats.add({'ok': true});

      case 'tolerance':
        await db
            .into(db.parametresSystemeLocal)
            .insertOnConflictUpdate(
              ParametresSystemeLocalCompanion.insert(
                cle: AchatsDao.cleTolerance,
                valeur: op['valeur']! as String,
                modifieLe: maintenant,
              ),
            );
        resultats.add({'ok': true});

      case 'point':
        final ref = op['ref']! as String;
        points[ref] = 'p-$ref';
        await stocks.creerPoint(
          libelle: op['libelle']! as String,
          id: 'p-$ref',
        );
        resultats.add({'ok': true});

      case 'article':
        final ref = op['ref']! as String;
        articles[ref] = 'a-$ref';
        await stocks.creerArticle(
          id: 'a-$ref',
          libelle: op['libelle']! as String,
          categorie: 'Denrées',
          uniteMesure: 'kg',
          seuilCentiemes: int.parse(op['seuil']! as String) * 100,
          suivi: SuiviArticle.permanent,
          pointStockageId: null,
        );
        resultats.add({'ok': true});

      case 'entree':
        final cout = op['cout'] as String?;
        await stocks.ajouterMouvement(
          articleId: articles[op['article']]!,
          pointId: points[op['point']]!,
          type: TypeMouvement.entree,
          centiemes: int.parse(op['quantite']! as String) * 100,
          motif: 'Entrée de test',
          auteurId: 'u-g',
          coutDixMilliemes: cout == null ? null : int.parse(cout) * 10000,
        );
        resultats.add({'ok': true});

      case 'fournisseur':
        final ref = op['ref']! as String;
        fournisseurs[ref] = 'f-$ref';
        await achats.creerFournisseur(
          SaisieFournisseur(
            id: 'f-$ref',
            raisonSociale: op['nom']! as String,
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: 'u-g',
        );
        resultats.add({'ok': true});

      case 'commande':
        final detail = await achats.creerCommande(
          SaisieCommande(
            fournisseurId: fournisseurs[op['fournisseur']]!,
            dateCommande: op['date']! as String,
            statut: StatutCommande.envoyee,
            lignes: [
              for (final l in op['lignes']! as List)
                LigneSaisieCommande(
                  articleId: articles[(l as Map)['article']]!,
                  libelle: 'ignoré',
                  uniteMesure: 'ignorée',
                  quantite: l['quantite']! as String,
                  prixUnitaire: l['prix']! as String,
                ),
            ],
          ),
          auteurId: 'u-g',
        );
        commandes[op['ref']! as String] = detail.commande.id;
        resultats.add({'ok': true});

      case 'reception' || 'reception_pwa':
        final commandeId = commandes[op['commande']]!;
        final detail = (await achats.commande(commandeId))!;
        final quantites = (op['quantites']! as Map).cast<String, String>();
        final avant = await db.select(db.mouvementsStockLocal).get();
        final connus = {for (final m in avant) m.id};
        try {
          final bon = await achats.enregistrerReception(
            SaisieReception(
              commandeId: commandeId,
              pointStockageId: points[op['point']]!,
              dateReception: null,
              lignes: [
                for (final e in quantites.entries)
                  LigneSaisieReception(
                    articleId: articles[e.key]!,
                    libelle: 'ignoré',
                    uniteMesure: 'ignorée',
                    quantiteCommandee:
                        detail.lignes
                            .where((l) => l.articleId == articles[e.key])
                            .map((l) => l.quantiteCommandee)
                            .firstOrNull ??
                        '0.00',
                    quantiteDejaRecue: '0.00',
                    quantiteRecue: e.value,
                  ),
              ],
            ),
            auteurId: 'u-g',
          );
          final ecrits = [
            for (final m in await db.select(db.mouvementsStockLocal).get())
              if (!connus.contains(m.id))
                {
                  'article': refArticle(m.articleId),
                  'type': m.typeMouvement,
                  'quantite': (m.quantite).toStringAsFixed(2),
                  'motif': m.motif
                      .replaceAll(commandeId, 'COMMANDE')
                      .replaceAll(bon.id, 'BON'),
                },
          ]..sort((a, b) => '${a['article']}'.compareTo('${b['article']}'));
          final apres = (await achats.commande(commandeId))!;
          if (op['op'] == 'reception_pwa') {
            resultats.add({
              'erreurs': <String, Object?>{},
              'modale_fermee': true,
            });
          } else {
            resultats.add({
              'conformite': bon.conformiteCode,
              'statut_commande': apres.commande.statutCode,
              'mouvements': ecrits,
            });
          }
        } on ToleranceAbsente catch (e) {
          resultats.add({'refus': 'RuntimeException', 'message': e.message});
        } on RefusAchats catch (e) {
          resultats.add({'refus': 'RuntimeException', 'message': e.motif});
        }

      case 'etat_stock':
        final etat = await stocks.etat();
        resultats.add({
          'articles': {
            for (final l in etat.lignes)
              refArticle(l.id): {
                'stock': l.stock,
                // « inconnu » (poste) et « 0.0000 » (serveur) : même fait.
                'cmp': l.cmpInconnu ? '0.0000' : l.coutMoyenPondere,
                'prix_achat': l.prixAchat,
                'valeur': '${l.valeurStock}.00',
              },
          },
          'valeur_totale': '${etat.kpis.valeurStock}.00',
          'valeur_stock_m11': '${etat.kpis.valeurStock}.00',
        });

      case 'bons':
        final bons = await db.select(db.bonsReceptionLocal).get();
        final mouvements = await db.select(db.mouvementsStockLocal).get();
        resultats.add({
          'nb_bons': bons.length,
          'nb_mouvements': mouvements.length,
        });

      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}

// ------------------------------------------------------------ normalisation

Map<String, Object?> _normaliserServeur(Map<String, dynamic> brut) {
  final r = Map<String, Object?>.from(brut);
  if (r.containsKey('libelles')) return {'libelles': 'rien'};
  // Le message de succès du serveur n'est pas porté (D276) : il affirme une
  // mise à jour du coût moyen pondéré que la réception ne fait pas.
  r.remove('succes');
  if (r['refus'] != null) {
    return {'refus': 'RuntimeException', 'message': r['message']};
  }
  if (r['erreurs'] is List && (r['erreurs'] as List).isEmpty) {
    r['erreurs'] = <String, Object?>{};
  }
  if (r.containsKey('articles')) {
    // Le serveur compte aussi l'article `a4` (hors commande) dès sa création ;
    // le poste aussi. La valeur d'un article sans coût vaut zéro des deux côtés.
    final articles = (r['articles'] as Map).cast<String, dynamic>();
    r['articles'] = {
      for (final e in articles.entries)
        e.key: {
          ...(e.value as Map<String, dynamic>),
          'valeur': _entier((e.value as Map)['valeur'] as String),
        },
    };
    r['valeur_totale'] = _entier(r['valeur_totale']! as String);
    r['valeur_stock_m11'] = _entier(r['valeur_stock_m11']! as String);
  }
  return r;
}

Map<String, Object?> _normaliserLocal(Map<String, Object?> brut) {
  final r = Map<String, Object?>.from(brut);
  if (r.containsKey('articles')) {
    final articles = (r['articles']! as Map).cast<String, dynamic>();
    r['articles'] = {
      for (final e in articles.entries)
        e.key: {
          ...(e.value as Map<String, dynamic>),
          'valeur': _entier((e.value as Map)['valeur'] as String),
        },
    };
    r['valeur_totale'] = _entier(r['valeur_totale']! as String);
    r['valeur_stock_m11'] = _entier(r['valeur_stock_m11']! as String);
  }
  return r;
}

/// Une valeur en francs ENTIERS : le serveur écrit deux décimales, le poste
/// arrondit à l'unité (`valeurStock`) ; les montants du scénario sont ronds.
int _entier(String montant) => int.parse(montant.split('.').first);

String _canon(Object? valeur) => jsonEncode(_trier(valeur));

Object? _trier(Object? v) {
  if (v is Map) {
    return {
      for (final k in (v.keys.map((e) => '$e').toList()..sort()))
        k: _trier(v[k]),
    };
  }
  if (v is List) return [for (final e in v) _trier(e)];
  return v;
}

String _difference(Map<String, Object?> s, Map<String, Object?> l) {
  final cles = {...s.keys, ...l.keys}.toList()..sort();
  return [
    for (final k in cles)
      if (_canon(s[k]) != _canon(l[k]))
        '$k : serveur=${_canon(s[k])} / poste=${_canon(l[k])}',
  ].join('\n  ');
}

/// Le code rendu d'un dossier, lignes de commentaire retirées : les écarts nommés
/// CITENT la phrase fausse de la vue, ils ne la rendent pas.
String _codeSansCommentaires(Directory dossier) => dossier
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .map(
      (f) => f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n'),
    )
    .join('\n')
    .replaceAll(RegExp(r'''(?:'|")\s*[\r\n]+\s*(?:'|")'''), '');
