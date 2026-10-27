@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/alertes/domain/modales_ouverture.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/stocks/domain/calcul_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/etat_stock.dart';
import 'package:tatacora_flutter/features/stocks/domain/entities/mouvement_stock.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// Les DEUX modales d'ouverture de session CONTRE le vrai serveur.
///
/// `tool/alertes/rejouer_modales_ouverture.php` sème un monde (articles,
/// mouvements, clients, séjours, factures, relances — les dates sont des
/// DÉCALAGES par rapport à aujourd'hui, le test ne dépend d'aucun jour) puis
/// appelle les trois collecteurs de `AlertesOuverture` et les deux gestes du
/// composant `AlertesOuvertureModales`. Le même monde passe par les fonctions
/// pures du poste ; ce qui se compare : libellé, détail, criticité, action
/// proposée, montant réclamé, et les mots (relus de `lang/fr/pwa.php`).
///
/// Base d'essai privée : `TATACORA_BASE_ESSAI=tatacora_<nom>_test`.
void main() {
  final aujourdhui = DateTime(2026, 10, 27, 14);
  final minuit = DateTime(2026, 10, 27);
  DateTime ilYA(int jours) =>
      DateTime(minuit.year, minuit.month, minuit.day - jours);

  // --- Le monde ------------------------------------------------------------
  final points = ['p1', 'p2'];
  final articlesMonde = <Map<String, Object?>>[
    {'ref': 'a1', 'libelle': 'Bière', 'unite': 'casier', 'seuil': '5.00'},
    {'ref': 'a2', 'libelle': 'Riz', 'unite': 'kg', 'seuil': '10.50'},
    {'ref': 'a3', 'libelle': 'Sel', 'unite': 'sac', 'seuil': '1.00'},
  ];
  final mouvementsMonde = <Map<String, Object?>>[
    {'article': 'a1', 'point': 'p1', 'type': 'entree', 'quantite': 3},
    {'article': 'a2', 'point': 'p1', 'type': 'entree', 'quantite': 4},
    {'article': 'a2', 'point': 'p1', 'type': 'sortie', 'quantite': 4},
    {'article': 'a2', 'point': 'p2', 'type': 'entree', 'quantite': 8.5},
    // Au-dessus du seuil : aucune ligne.
    {'article': 'a3', 'point': 'p1', 'type': 'entree', 'quantite': 40},
    // Au seuil EXACT : listé (`<=`).
    {'article': 'a1', 'point': 'p2', 'type': 'entree', 'quantite': 5},
  ];
  final clientsMonde = <Map<String, Object?>>[
    {'ref': 'c1', 'nom': 'KORA', 'prenom': 'Jean'},
    {'ref': 'c2', 'nom': 'DOSSOU', 'prenom': null},
    {'ref': 'c3', 'nom': 'YAYI', 'prenom': 'Awa'},
    {'ref': 'c4', 'nom': 'ADJOVI', 'prenom': 'Paul'},
  ];
  final sejoursMonde = <Map<String, Object?>>[
    {'ref': 's1', 'client': 'c1', 'unite': 'U1', 'depart': 0, 'etat': 'ouvert'},
    {
      'ref': 's2',
      'client': 'c2',
      'unite': 'U2',
      'depart': -2,
      'etat': 'ouvert',
    },
    {'ref': 's3', 'client': 'c2', 'unite': 'U1', 'depart': -1, 'etat': 'clos'},
    // Départ DEMAIN : pas encore à échéance.
    {'ref': 's4', 'client': 'c3', 'unite': 'U3', 'depart': 1, 'etat': 'ouvert'},
    // Jamais arrivé : aucune action.
    {
      'ref': 's5',
      'client': 'c3',
      'unite': 'U3',
      'depart': 0,
      'etat': 'non_arrive',
    },
  ];
  final facturesMonde = <Map<String, Object?>>[
    {'ref': 'f1', 'client': 'c1', 'emission': 40, 'ttc': '10000.00'},
    {'ref': 'f2', 'client': 'c1', 'emission': 100, 'ttc': '2500.40'},
    {'ref': 'f3', 'client': 'c2', 'emission': 35, 'ttc': '7000.00'},
    // Émise il y a 30 jours EXACTEMENT : listée (`<=`).
    {'ref': 'f4', 'client': 'c3', 'emission': 30, 'ttc': '4000.00'},
    // Trop récente.
    {'ref': 'f5', 'client': 'c4', 'emission': 29, 'ttc': '9000.00'},
  ];
  final relancesMonde = <Map<String, Object?>>[
    {'client': 'c2', 'il_y_a': 3},
    // Relancée il y a 14 jours EXACTEMENT : encore RÉCENTE (seuil strict).
    {'client': 'c3', 'il_y_a': 14},
  ];
  final monde = <String, Object?>{
    'points': points,
    'articles': articlesMonde,
    'mouvements': mouvementsMonde,
    'clients': clientsMonde,
    'unites': ['U1', 'U2', 'U3'],
    'sejours': sejoursMonde,
    'factures': facturesMonde,
    'relances': relancesMonde,
  };

  final ops = <Map<String, Object?>>[
    {'op': 'lignes'},
    {'op': 'checkout', 'sejour': 's1'},
    {'op': 'checkout', 'sejour': 's3'},
    {'op': 'checkout', 'sejour': 'zzz'},
    {'op': 'relancer', 'client': 'c1', 'canal': 'whatsapp'},
    {'op': 'relancer', 'client': 'c2', 'canal': 'email'},
    {'op': 'relancer', 'client': 'zzz', 'canal': 'email'},
    {'op': 'libelles'},
  ];

  late List<dynamic> serveur;

  setUpAll(() async {
    final r = await executerPhp(
      'rejouer_modales_ouverture.php',
      dossier: 'alertes',
      entree: {'monde': monde, 'ops': ops},
    );
    serveur = r['resultats'] as List<dynamic>;
  });

  /// L'espace insécable de `MontantFcfa::format` -> une espace.
  String sansNbsp(String t) => t.replaceAll(' ', ' ');

  /// Une liste d'objets du rapport JSON du serveur, typée.
  List<Map<String, dynamic>> objets(Object? o) => [
    for (final e in o! as List) e as Map<String, dynamic>,
  ];

  Map<String, dynamic> lignesServeur() => serveur[0] as Map<String, dynamic>;

  // --- Le monde, côté poste ------------------------------------------------
  int centiemes(Object q) => (double.parse('$q') * 100).round();

  List<ArticleCalcul> articles() => [
    for (final a in articlesMonde)
      ArticleCalcul(
        id: a['ref'] as String,
        libelle: a['libelle'] as String,
        categorie: null,
        uniteMesure: a['unite'] as String,
        seuilCentiemes: centiemes(a['seuil']!),
        suivi: SuiviArticle.permanent,
      ),
  ];

  List<MouvementCalcul> mouvements() => [
    for (final (i, m) in mouvementsMonde.indexed)
      MouvementCalcul(
        id: 'm$i',
        articleId: m['article'] as String,
        pointId: m['point'] as String,
        type: TypeMouvement.values.firstWhere((t) => t.code == m['type']),
        centiemes: centiemes(m['quantite']!),
        ordre: i,
        date: aujourdhui,
      ),
  ];

  Map<String, Map<String, Object?>> clients() => {
    for (final c in clientsMonde) c['ref']! as String: c,
  };

  List<DepartAEcheance> departs() {
    final parClient = clients();
    final liste = <DepartAEcheance>[];
    for (final s in sejoursMonde) {
      if (s['etat'] != 'ouvert') continue;
      final depart = ilYA(-(s['depart'] as int));
      if (depart.isAfter(minuit)) continue;
      final c = parClient[s['client']]!;
      liste.add((
        sejourId: s['ref'] as String,
        reservationId: 'r-${s['ref']}',
        dateDepart: depart,
        clientPrenom: c['prenom'] as String?,
        clientNom: c['nom'] as String,
        uniteNumero: s['unite'] as String,
      ));
    }
    return liste..sort((a, b) => a.dateDepart.compareTo(b.dateDepart));
  }

  List<CreanceFacture> creances() {
    final parClient = clients();
    return [
      for (final f in facturesMonde)
        CreanceFacture(
          piece: PieceFacturation(
            id: f['ref'] as String,
            numero: 'F-${f['ref']}',
            origine: OrigineFacture.factureDirecte,
            dateEmission: ilYA(f['emission'] as int),
            clientNom: [
              parClient[f['client']]!['prenom'],
              parClient[f['client']]!['nom'],
            ].whereType<String>().join(' '),
            statut: StatutPiece.emise,
            lignes: const [],
            clientId: f['client'] as String,
          ),
          ttcCentimes: centiemes(f['ttc']!),
          avoirsCentimes: 0,
          paiementsActifsCentimes: 0,
          acomptesCentimes: 0,
        ),
    ];
  }

  Map<String, DateTime> relances() => {
    for (final r in relancesMonde)
      r['client'] as String: ilYA(r['il_y_a'] as int),
  };

  List<LigneCreanceOuverture> lignesCreances() => creancesModale(
    creances: creances(),
    derniereRelance: relances(),
    maintenant: aujourdhui,
    formaterFcfa: (f) {
      final chiffres = '$f';
      final groupes = <String>[];
      for (var i = chiffres.length; i > 0; i -= 3) {
        groupes.insert(0, chiffres.substring(i - 3 < 0 ? 0 : i - 3, i));
      }
      return '${groupes.join(' ')} FCFA';
    },
  );

  test('le monde est assez large pour que la comparaison compte', () {
    final l = lignesServeur();
    expect(objets(l['stock']).length, greaterThanOrEqualTo(3));
    expect(objets(l['departs']).length, 2);
    expect(objets(l['creances']).length, greaterThanOrEqualTo(3));
    expect(
      objets(l['stock']).any((x) => x['critique'] == true),
      isTrue,
      reason: 'une rupture au moins',
    );
    expect(
      objets(l['creances']).any((x) => x['relance_requise'] == true),
      isTrue,
    );
    expect(
      objets(l['creances']).any((x) => x['relance_requise'] == false),
      isTrue,
    );
  });

  test('stock critique : mêmes lignes, ruptures d\'abord, sans plafond', () {
    final poste = [
      for (final l in stockCritiqueModale(
        articles: articles(),
        mouvements: mouvements(),
      ))
        '${l.articleId}|${l.libelle}|${l.detail}|${l.critique}',
    ];
    final srv = [
      for (final l in objets(lignesServeur()['stock']))
        '${l['article']}|${l['libelle']}|${l['detail']}|${l['critique']}',
    ];
    // L'ordre hors criticité est celui du serveur (MySQL) : écart nommé. On
    // compare la partition (ruptures puis le reste) et le contenu de chaque.
    final rupturesPoste = poste.where((p) => p.endsWith('|true')).toList()
      ..sort();
    final rupturesSrv = srv.where((p) => p.endsWith('|true')).toList()..sort();
    final resteP = poste.where((p) => p.endsWith('|false')).toList()..sort();
    final resteS = srv.where((p) => p.endsWith('|false')).toList()..sort();
    expect(rupturesPoste, rupturesSrv);
    expect(resteP, resteS);
    expect(
      poste.indexWhere((p) => p.endsWith('|false')),
      greaterThan(poste.lastIndexWhere((p) => p.endsWith('|true'))),
      reason: 'les ruptures d\'abord',
    );
    // Les ruptures sont bien en tête chez le serveur aussi.
    expect(
      srv.indexWhere((p) => p.endsWith('|false')),
      greaterThan(srv.lastIndexWhere((p) => p.endsWith('|true'))),
    );
  });

  test('départs à échéance : mêmes lignes, même ordre, même criticité', () {
    final poste = [
      for (final l in departsAEcheance(
        departs: departs(),
        maintenant: aujourdhui,
      ))
        '${l.sejourId}|${l.libelle}|${l.detail}|${l.critique}',
    ];
    final srv = [
      for (final l in objets(lignesServeur()['departs']))
        '${l['sejour']}|${l['libelle']}|${l['detail']}|${l['critique']}',
    ];
    // La date du détail dépend du jour réel du serveur : le décalage est le
    // même, on compare la forme du détail (date -> JJ/MM/AAAA).
    String forme(String s) => s.replaceAll(RegExp(r'\d{2}/\d{2}/\d{4}'), 'D');
    expect(poste.map(forme).toList(), srv.map(forme).toList());
  });

  test('créances à relancer : mêmes lignes, même criticité, même relance', () {
    final poste = lignesCreances();
    final srv = objets(lignesServeur()['creances']);
    String forme(String s) =>
        sansNbsp(s).replaceAll(RegExp(r'\d{2}/\d{2}/\d{4}'), 'D');
    expect(
      [
        for (final l in poste)
          '${l.clientId}|${l.libelle}|${forme(l.detail)}|${l.critique}|'
              '${l.relanceRequise}|${l.resteCentimes}',
      ],
      [
        for (final l in srv)
          '${l['client']}|${l['libelle']}|${forme(l['detail'] as String)}|'
              '${l['critique']}|${l['relance_requise']}|'
              '${(double.parse(l['reste'] as String) * 100).round()}',
      ],
    );
  });

  test('les mots, le plafond et les seuils sont ceux du serveur', () {
    final l = (serveur.last as Map<String, dynamic>);
    final mots = l['mots'] as Map<String, dynamic>;
    expect(TextesOuverture.titreStock, mots['titre_stock']);
    expect(TextesOuverture.sousTitreStock, mots['sous_titre_stock']);
    expect(TextesOuverture.titreOperations, mots['titre_operations']);
    expect(TextesOuverture.sousTitreOperations, mots['sous_titre_operations']);
    expect(TextesOuverture.blocStockTitre, mots['bloc_stock_titre']);
    expect(TextesOuverture.blocStockSousTitre, mots['bloc_stock_sous_titre']);
    expect(TextesOuverture.lienStocks, mots['lien_stocks']);
    expect(TextesOuverture.blocDepartsTitre, mots['bloc_departs_titre']);
    expect(
      TextesOuverture.blocDepartsSousTitre,
      mots['bloc_departs_sous_titre'],
    );
    expect(TextesOuverture.departAujourdhui, mots['depart_aujourdhui']);
    expect(TextesOuverture.lienReservations, mots['lien_reservations']);
    expect(TextesOuverture.checkout, mots['checkout']);
    expect(TextesOuverture.fait, mots['fait']);
    expect(TextesOuverture.sejourIntrouvable, mots['sejour_introuvable']);
    expect(TextesOuverture.blocCreancesTitre, mots['bloc_creances_titre']);
    expect(
      TextesOuverture.blocCreancesSousTitre,
      mots['bloc_creances_sous_titre'],
    );
    expect(TextesOuverture.jamaisRelance, mots['jamais_relance']);
    expect(TextesOuverture.lienCreances, mots['lien_creances']);
    expect(TextesOuverture.relancer, mots['relancer']);
    expect(TextesOuverture.tracee, mots['tracee']);
    expect(TextesOuverture.relanceRecente, mots['relance_recente']);
    expect(TextesOuverture.relanceIndisponible, mots['relance_indisponible']);
    expect(TextesOuverture.relanceCommentaire, mots['relance_commentaire']);
    expect(TextesOuverture.suivant, mots['suivant']);
    expect(TextesOuverture.prisConnaissance, mots['pris_connaissance']);
    expect(TextesOuverture.droitManquant, mots['droit_manquant']);
    // Les phrases à paramètres.
    expect(
      TextesOuverture.stockDetail(':stock', ':unite', ':seuil'),
      mots['stock_detail'],
    );
    expect(TextesOuverture.departDepasse(':date'), mots['depart_depasse']);
    expect(
      TextesOuverture.creanceDetail(
        ':montant',
        0,
      ).replaceFirst('0 j', ':jours j'),
      mots['creance_detail'],
    );
    expect(TextesOuverture.relanceLe(':date'), mots['relance_le']);
    expect(
      TextesOuverture.etAutres(0).replaceFirst('0', ':nombre'),
      mots['et_autres'],
    );
    // Les canaux, dans l'ordre du serveur, et le défaut.
    expect([for (final (c, _) in canauxRelanceOuverture) c], l['canaux']);
    expect(canauxRelanceOuverture.first.$1, l['canal_defaut']);
    expect(
      [for (final (_, lib) in canauxRelanceOuverture) lib],
      [
        mots['canal_telephone'],
        mots['canal_whatsapp'],
        mots['canal_email'],
        mots['canal_courrier'],
        mots['canal_visite'],
      ],
    );
    // Le plafond par bloc et les seuils.
    expect(lignesParBloc, l['ligne_par_bloc']);
    expect(joursRelanceRecente, l['relance_recente_jours']);
    expect(ancienneteJoursServeur(l), 30);
    expect(l['ligne_par_bloc'], 10, reason: 'extraction non vide');
  });

  test('les gestes du serveur : ce que le poste doit reproduire', () {
    // Check-out : le séjour est clos, l'unité passe en NETTOYAGE, la ligne est
    // « traitée ».
    final checkout = serveur[1] as Map<String, dynamic>;
    expect(checkout['erreur'], isNull);
    expect(checkout['statut_unite'], 'nettoyage');
    expect(checkout['sejour_clos'], true);
    expect(checkout['traites'], hasLength(1));
    // Séjour déjà clos : la phrase du service, avec sa DATE.
    expect(
      (serveur[2] as Map)['erreur'],
      matches(
        RegExp(
          r'^Le départ a déjà été enregistré le \d{2}/\d{2}/\d{4} \d{2}:\d{2}\.$',
        ),
      ),
    );
    // Séjour inconnu.
    expect((serveur[3] as Map)['erreur'], TextesOuverture.sejourIntrouvable);
    // Relance : canal choisi, montant = reste dû réel, commentaire fixe.
    final relance = (serveur[4] as Map)['relance'] as Map;
    expect(relance['canal'], 'whatsapp');
    expect(relance['montant'], '12500.40');
    expect(relance['commentaire'], TextesOuverture.relanceCommentaire);
    // Créance relancée récemment, ou client inconnu : refusée.
    expect((serveur[5] as Map)['erreur'], TextesOuverture.relanceIndisponible);
    expect((serveur[6] as Map)['erreur'], TextesOuverture.relanceIndisponible);
  });
}

int ancienneteJoursServeur(Map<String, dynamic> l) =>
    l['anciennete_jours'] as int;
