@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/domain/dettes_fournisseurs.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/commande_achat.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/reglement_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_reglement.dart';
import 'package:tatacora_flutter/features/achats/domain/regles_reglement.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/etats/domain/apercus_etats.dart'
    show apercuAchats;
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/depenses/domain/categories_depense.dart';
import 'package:tatacora_flutter/features/facturation/domain/messages_encaissement.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// LE MÊME scénario de règlement fournisseur, joué par les VRAIS services du
/// serveur (`ReglementFournisseurService`, `CommandeAchatService`, le composant
/// `Approvisionnement`) sur MySQL, et par le poste sur sa base locale, comparé
/// CHAMP À CHAMP : le refus de chaque geste (dans l'ordre, avec sa phrase), le
/// règlement écrit, la pièce comptable, le reste dû, les cartes, la liste des
/// dettes, le droit de chaque rôle.
///
/// `tool/achats/rejouer_reglements.php` travaille sur `tatacora_test` (il refuse
/// toute autre base), sème les rôles et le référentiel comptable par les vrais
/// seeders, puis ANNULE tout : la base n'est pas modifiée. MySQL injoignable : le
/// test ÉCHOUE, il ne saute pas.
///
/// Le scénario est UN seul JSON lu par les deux moteurs : un scénario recopié à
/// la main des deux côtés ne prouverait rien.
///
/// ## Les écarts de représentation, normalisés avant la comparaison
///
/// 1. un montant que `bcmath` ne sait pas lire (« 1e3 », « abc », « 100 » avec
///    espace) fait PLANTER le serveur au rendu de la modale (`ViewException`,
///    HTTP 500) AVANT toute écriture ; le poste le refuse avec une phrase. Les
///    deux sont ramenés à « plantage » (D259) ;
/// 2. le serveur affiche toutes les erreurs de validation à la fois, le poste la
///    première : seule la PREMIÈRE du serveur (dans l'ordre commande, montant,
///    trésorerie) est comparée ;
/// 3. l'identifiant d'un règlement, présent dans le libellé de sa pièce (PA-52),
///    est ramené à son rang de création (`REGL:n`) ;
/// 4. l'ordre des lignes comptables est canonique (le serveur ne fixe aucun
///    ordre entre deux lignes de la même seconde) ;
/// 5. les erreurs vides sont `[]` côté PHP et `{}` côté Dart.
void main() {
  const aujourdhui = '2026-10-13';
  final maintenant = DateTime(2026, 10, 13, 10);

  // ------------------------------------------------------------------ scénario
  Map<String, Object?> reglerPwa(
    String commande,
    String montant, {
    String tresorerie = 'caisse',
    String user = 'g',
    bool ouvrir = true,
  }) => {
    'op': 'regler_pwa',
    'commande': commande,
    'user': user,
    'montant': montant,
    'tresorerie': tresorerie,
    'ouvrir': ouvrir,
  };
  Map<String, Object?> reglerService(
    String commande,
    String montant,
    String tresorerie, {
    String user = 'g',
  }) => {
    'op': 'regler_service',
    'commande': commande,
    'user': user,
    'montant': montant,
    'tresorerie': tresorerie,
  };
  Map<String, Object?> vue({String statut = '', String recherche = ''}) => {
    'op': 'vue',
    'user': 'g',
    'statut': statut,
    'recherche': recherche,
  };
  Map<String, Object?> commande(
    String ref,
    String fournisseur,
    String date,
    String statut,
    String article,
    String quantite,
    String prix,
  ) => {
    'op': 'commande',
    'ref': ref,
    'fournisseur': fournisseur,
    'user': 'g',
    'date': date,
    'statut': statut,
    'lignes': [
      {'article': article, 'quantite': quantite, 'prix': prix},
    ],
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'libelles'},
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'utilisateur', 'ref': 'b', 'role': 'barman'},
    {'op': 'utilisateur', 'ref': 'a', 'role': 'achats'},
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Grand Marche SARL'},
    {'op': 'fournisseur', 'ref': 'f2', 'nom': 'Boulangerie du Nord'},
    {'op': 'article', 'ref': 'a1', 'libelle': 'Sucre'},
    {'op': 'article', 'ref': 'a2', 'libelle': 'Farine'},
    // c1 : 4 000 F, la commande qu'on règle en plusieurs fois.
    commande('c1', 'f1', '2026-10-01', 'envoyee', 'a1', '4', '1000'),
    // c2 : un brouillon (le serveur le règle sans broncher).
    commande('c2', 'f1', '2026-09-01', 'brouillon', 'a1', '2', '500'),
    // c3 : 2 505 F, deux décimales dans le prix.
    commande('c3', 'f2', '2026-07-01', 'envoyee', 'a2', '10', '250.50'),
    // c4 : DATÉE DU FUTUR — une ancienneté négative.
    commande('c4', 'f2', '2026-10-20', 'envoyee', 'a1', '1', '300'),
    // c5 : réceptionnée, jamais payée — hors de l'onglet, dans le total.
    commande('c5', 'f1', '2026-08-15', 'envoyee', 'a1', '3', '1000'),
    {'op': 'statut', 'commande': 'c5', 'statut': 'receptionnee'},
    // c6 : clôturée, jamais payée.
    commande('c6', 'f2', '2026-06-01', 'envoyee', 'a2', '2', '400'),
    {'op': 'statut', 'commande': 'c6', 'statut': 'cloturee'},

    // --- Avant tout règlement : les cartes, la liste, l'ouverture ------------
    vue(),
    {'op': 'etat_achats'},
    {'op': 'ouvrir_pwa', 'commande': 'c1', 'user': 'g'},
    {'op': 'ouvrir_pwa', 'commande': 'c1', 'user': 'b'}, // M7 = '-'
    {
      'op': 'ouvrir_pwa',
      'commande': 'c1',
      'user': 'g',
      'commande_inconnue': '00000000-0000-4000-8000-000000000000',
    },

    // --- Les refus de la validation du composant, dans l'ordre ---------------
    reglerPwa('c1', ''),
    reglerPwa('c1', '0'),
    reglerPwa('c1', '-5'),
    reglerPwa('c1', 'abc'), // plantage au rendu
    reglerPwa('c1', '1e3'), // plantage au rendu
    reglerPwa('c1', ' 100'), // plantage au rendu
    reglerPwa('c1', '100 '), // plantage au rendu
    reglerPwa('c1', '1,5'), // plantage au rendu
    // --- Les refus du service -------------------------------------------------
    reglerPwa('c1', '0.004'), // > 0 mais tronqué à 0.00
    reglerPwa('c1', '0.005'),
    reglerPwa('c1', '4000.01'), // dépasse le reste dû d'un centime
    reglerPwa('c1', '9000'),
    reglerPwa('c1', '1000', user: 'b'), // le barman : 403
    reglerPwa('c1', '1000', tresorerie: 'cheque'), // validation `in`
    reglerPwa('c1', '1000', tresorerie: ''), // validation `required`
    {'op': 'etat'},

    // --- Les écritures --------------------------------------------------------
    reglerPwa('c1', '1500'), // règlement 0 : caisse
    vue(),
    reglerPwa('c1', '2500.50'), // dépasse le reste (2 500.00)
    reglerPwa('c1', '.5', tresorerie: 'momo'), // règlement 1 : forme tolérée
    reglerPwa('c1', '5.', tresorerie: 'momo'), // règlement 2
    reglerPwa('c1', '+5', tresorerie: 'banque'), // règlement 3
    reglerPwa('c1', '00012', user: 'a'), // règlement 4 : zéros de tête
    reglerPwa('c1', '1.000'), // règlement 5 : tronqué à 1.00
    reglerPwa('c1', '2.999', tresorerie: 'banque'), // règlement 6 : 2.99
    {'op': 'ouvrir_pwa', 'commande': 'c1', 'user': 'g'},
    // c1 reste à 2 500 - 0.5 - 5 - 5 - 12 - 1 - 2.99 = 2 473.51
    reglerPwa('c1', '2473.51', tresorerie: 'banque'), // règlement 7 : solde
    {'op': 'ouvrir_pwa', 'commande': 'c1', 'user': 'g'}, // déjà soldée
    reglerPwa('c1', '1', ouvrir: false), // reste dû = 0.00
    vue(),

    // --- Le service seul : l'ordre de SES refus -------------------------------
    reglerService('c3', '100', 'cheque'),
    reglerService('c3', 'abc', 'cheque'), // la trésorerie d'abord
    reglerService('c3', 'abc', 'caisse'),
    reglerService('c3', '0', 'caisse'),
    reglerService('c3', '-1', 'caisse'),
    reglerService('c3', '1e3', 'caisse'), // ValueError
    reglerService('c3', '9999999', 'caisse'),
    reglerService('c3', '1000.999', 'momo'), // règlement 8 : 1000.99
    reglerService('c2', '500', 'banque'), // règlement 9 : un brouillon
    reglerService('c5', '1000', 'caisse'), // règlement 10 : une réceptionnée
    reglerService('c6', '400', 'caisse'), // règlement 11 : une clôturée
    reglerService('c4', '300', 'caisse'), // règlement 12 : datée du futur
    // --- L'annulation (PA-168) ------------------------------------------------
    {'op': 'annuler', 'reglement': 0, 'motif': '   ', 'user': 'g'},
    {
      'op': 'annuler',
      'reglement': 0,
      'motif': 'Doublon de saisie',
      'user': 'g',
    },
    {'op': 'annuler', 'reglement': 0, 'motif': 'Encore', 'user': 'g'},
    {
      'op': 'annuler',
      'reglement': 8,
      'motif': "Erreur d'écriture",
      'user': 'a',
    },
    vue(),
    vue(statut: 'brouillon'),
    vue(statut: 'receptionnee'),
    vue(recherche: 'Boulang'),
    vue(recherche: 'zzz'),
    {'op': 'etat'},
    // L'état M14 « achats et dettes fournisseurs » : « Réglé » et « Reste dû »
    // lus des règlements actifs (D264).
    {'op': 'etat_achats'},

    // --- Le droit, pour CHAQUE rôle du serveur ---
    for (final role in [
      'super_admin',
      'administrateur',
      'gerant',
      'receptionniste',
      'cuisine',
      'barman',
      'magasinier',
      'achats',
      'vehicules',
      'guide',
      'rh',
      'comptable',
    ])
      {'op': 'droits', 'role': role, 'commande': 'c3'},
  ];

  // LA CORRESPONDANCE DES COMPTES modifiée (26/10/2026) : la MÊME pièce de
  // règlement, avant et après chaque changement de compte (fournisseurs,
  // caisse, banque, Mobile Money). Les comptes choisis n'ont AUCUN centre par
  // défaut au plan (4012, 5712, 5212, 558) : seul le repli sur le centre du
  // compte par défaut du rôle les fait passer, des deux côtés.
  final scenarioCorrespondance = <Map<String, Object?>>[
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Grand Marche SARL'},
    {'op': 'article', 'ref': 'a1', 'libelle': 'Sucre'},
    commande('c1', 'f1', '2026-10-01', 'envoyee', 'a1', '10', '1000'),
    reglerService('c1', '1000', 'caisse'), // défauts : 4011 / 5711
    reglerService('c1', '500', 'momo'), // 552
    reglerService('c1', '250', 'banque'), // 5211
    {'op': 'parametre', 'cle': 'compte_fournisseurs', 'valeur': '4012'},
    {'op': 'parametre', 'cle': 'compte_caisse', 'valeur': '5712'},
    {'op': 'parametre', 'cle': 'compte_banque', 'valeur': '5212'},
    {'op': 'parametre', 'cle': 'compte_mobile_money', 'valeur': '558'},
    reglerService('c1', '1000', 'caisse'),
    reglerService('c1', '500', 'momo'),
    reglerService('c1', '250', 'banque'),
    reglerPwa('c1', '100', tresorerie: 'momo'), // le chemin de l'écran
    {'op': 'etat'},
    // Retour au défaut : la valeur est relue à chaque règlement.
    {'op': 'parametre', 'cle': 'compte_fournisseurs', 'valeur': null},
    {'op': 'parametre', 'cle': 'compte_caisse', 'valeur': null},
    reglerService('c1', '10', 'caisse'),
    // Un compte CHOISI que le plan refuse : même refus, rien d'écrit.
    {'op': 'parametre', 'cle': 'compte_fournisseurs', 'valeur': '7999'},
    reglerService('c1', '10', 'caisse'),
    {'op': 'parametre', 'cle': 'compte_fournisseurs', 'valeur': '40'},
    reglerService('c1', '10', 'caisse'),
    {'op': 'etat'},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;
  late List<dynamic> serveurCorrespondance;
  late List<Map<String, Object?>> localCorrespondance;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_reglements.php',
      dossier: 'achats',
      entree: {'aujourdhui': aujourdhui, 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _rejouerSurLePoste(scenario, serveur, maintenant);

    final reponseCorrespondance = await executerPhp(
      'rejouer_reglements.php',
      dossier: 'achats',
      entree: {'aujourdhui': aujourdhui, 'ops': scenarioCorrespondance},
    );
    serveurCorrespondance = reponseCorrespondance['resultats'] as List<dynamic>;
    localCorrespondance = await _rejouerSurLePoste(
      scenarioCorrespondance,
      serveurCorrespondance,
      maintenant,
    );
  });

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(scenario.length, greaterThan(80));
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));

    final issues = [
      for (final r in serveur) _normaliserServeur(r as Map<String, dynamic>),
    ];
    // Le serveur a RÉELLEMENT refusé ET RÉELLEMENT accepté : un scénario où tout
    // passerait (ou tout serait refusé) ne comparerait aucune règle.
    expect(issues.where((i) => i['refus'] == 'refus'), isNotEmpty);
    expect(issues.where((i) => i['refus'] == 'mal_forme'), isNotEmpty);
    expect(issues.where((i) => i['plantage'] == true), hasLength(5));
    expect(issues.where((i) => i['reglement'] != null), isNotEmpty);
    expect(issues.where((i) => i['statut'] == 403), isNotEmpty);
    expect(
      issues.where((i) => (i['erreurs'] as Map?)?.isNotEmpty ?? false),
      isNotEmpty,
    );
    // Treize règlements ont été ÉCRITS par le serveur (rangs 0 à 12).
    final dernierEtat =
        serveur[scenario.lastIndexWhere((o) => o['op'] == 'etat')]
            as Map<String, dynamic>;
    expect(dernierEtat['nb_reglements'], 13);
    // Deux lignes de pièce par règlement, plus deux d'inverses par annulation.
    expect(dernierEtat['nb_ecritures'], 13 * 2 + 2 * 2);
    // Les deux annulations ont contre-passé : des lignes `contrepasse`.
    expect(
      (dernierEtat['ecritures'] as List).where(
        (e) => (e as Map<String, dynamic>)['contrepasse'] == true,
      ),
      hasLength(4),
    );
    // Les deux moitiés du RBAC : des rôles qui règlent, des rôles qui ne le font
    // pas — leur droit est LU du serveur.
    final droits = [
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['op'] == 'droits')
          (serveur[i] as Map<String, dynamic>)['refus'],
    ];
    expect(droits.where((r) => r == false), isNotEmpty);
    expect(droits.where((r) => r == true), isNotEmpty);
    expect(droits, hasLength(12));
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

  test('CORRESPONDANCE DES COMPTES modifiée : la MÊME pièce de règlement que '
      'le serveur, avant et après chaque changement (parité)', () {
    expect(serveurCorrespondance, hasLength(scenarioCorrespondance.length));
    expect(localCorrespondance, hasLength(scenarioCorrespondance.length));
    final ecarts = <String>[];
    for (var i = 0; i < scenarioCorrespondance.length; i++) {
      final s = _normaliserServeur(
        serveurCorrespondance[i] as Map<String, dynamic>,
      );
      final l = _normaliserLocal(localCorrespondance[i]);
      if (_canon(s) != _canon(l)) {
        ecarts.add(
          'op #$i ${scenarioCorrespondance[i]}\n  ${_difference(s, l)}',
        );
      }
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });

  test('la parité du règlement n’est pas verte à vide : les comptes choisis '
      'portent les pièces futures, jamais les passées', () {
    final etats = [
      for (var i = 0; i < scenarioCorrespondance.length; i++)
        if (scenarioCorrespondance[i]['op'] == 'etat')
          serveurCorrespondance[i] as Map<String, dynamic>,
    ];
    final milieu = (etats.first['ecritures'] as List)
        .cast<Map<String, dynamic>>();
    List<String> comptes(Iterable<Map<String, dynamic>> l) => [
      for (final e in l) e['compte'] as String,
    ];
    // Sept règlements, deux lignes chacun ; les trois premiers sur les défauts.
    expect(milieu, hasLength(14));
    expect(
      comptes(milieu.take(6)),
      containsAll(<String>['4011', '5711', '552', '5211']),
    );
    expect(
      comptes(milieu.skip(6)),
      containsAll(<String>['4012', '5712', '5212', '558']),
    );
    expect(comptes(milieu.skip(6)), isNot(contains('4011')));
    expect(comptes(milieu.skip(6)), isNot(contains('5711')));
    // La fin : les deux refus (compte inconnu, division) n'ont RIEN écrit.
    final fin = etats.last;
    expect(fin['nb_ecritures'], 16);
    final refus = [
      for (var i = 0; i < scenarioCorrespondance.length; i++)
        if (serveurCorrespondance[i] is Map &&
            (serveurCorrespondance[i] as Map).containsKey('refus'))
          (serveurCorrespondance[i] as Map)['message'] ??
              serveurCorrespondance[i],
    ];
    expect(refus, hasLength(2));
  });

  test('les phrases et les libellés sont ceux du serveur', () {
    final lib =
        (serveur[0] as Map<String, dynamic>)['libelles']
            as Map<String, dynamic>;
    String sans(String v, Map<String, String> remplacements) {
      var r = v;
      for (final e in remplacements.entries) {
        r = r.replaceAll(e.key, e.value);
      }
      return r;
    }

    expect(
      sans(lib['tresorerie_inconnue'] as String, {':code': 'cheque'}),
      MessagesReglement.tresorerieInconnue('cheque'),
    );
    expect(lib['montant_invalide'], MessagesReglement.montantInvalide);
    expect(
      sans(lib['superieur_au_reste'] as String, {':reste': '2500.00'}),
      MessagesReglement.superieurAuReste('2500.00'),
    );
    expect(lib['deja_annule'], MessagesReglement.dejaAnnule);
    expect(lib['motif_requis'], MessagesReglement.motifRequis);
    expect(
      sans(lib['piece_introuvable'] as String, {':libelle': 'L'}),
      MessagesReglement.pieceIntrouvable('L'),
    );
    // L'ouverture d'une commande inconnue répond par la phrase d'une AUTRE
    // situation (D258) : c'est celle de `achats.commande_cloturee`.
    expect(lib['commande_cloturee'], MessagesAchats.commandeCloturee);
    expect(
      sans(lib['form_reglement'] as String, {':fournisseur': 'F'}),
      MessagesReglement.titreModale('F'),
    );
    expect(
      sans(lib['form_reglement_sous_titre'] as String, {
        ':commande': 'C',
        ':reste': 'R',
      }),
      MessagesReglement.sousTitreModale('C', 'R'),
    );
    expect(lib['form_montant_regle'], MessagesReglement.libelleMontant);
    expect(lib['form_tresorerie'], MessagesReglement.libelleTresorerie);
    expect(lib['form_valider_reglement'], MessagesReglement.libelleValider);
    expect(lib['annuler'], MessagesReglement.libelleAnnuler);
    expect(
      sans(lib['reglement_enregistre'] as String, {
        ':montant': 'M',
        ':fournisseur': 'F',
      }),
      MessagesReglement.enregistre('M', 'F'),
    );
    expect(lib['reglement_commande_soldee'], MessagesReglement.commandeSoldee);
    expect(lib['tresorerie_caisse'], MessagesReglement.tresorerieCaisse);
    expect(lib['tresorerie_momo'], MessagesReglement.tresorerieMobileMoney);
    expect(lib['tresorerie_banque'], MessagesReglement.tresorerieBanque);
    expect(lib['regler'], MessagesReglement.regler);
    expect(lib['col_regle'], MessagesReglement.colRegle);
    expect(lib['col_reste_du'], MessagesReglement.colResteDu);
    expect(lib['col_numero_commande'], MessagesReglement.colNumeroCommande);
    expect(lib['col_anciennete'], MessagesReglement.colAnciennete);
    expect(lib['kpi_a_payer'], MessagesReglement.kpiAPayer);
    expect(lib['kpi_total_du'], MessagesReglement.totalDu);
    expect(lib['total_du'], MessagesReglement.totalDu);
    expect(lib['dettes_titre'], MessagesReglement.dettesTitre);
    expect(lib['dettes_portee'], MessagesReglement.dettesPortee);
    expect(lib['dettes_vide'], MessagesReglement.dettesVide);
    expect(
      sans(lib['jours'] as String, {':nombre': '12'}),
      MessagesReglement.jours(12),
    );
    expect(lib['validation_gt'], MessagesReglement.superieurAZero);
    expect(
      sans(lib['validation_required'] as String, {':attribute': 'A'}),
      MessagesEncaissement.obligatoire('A'),
    );
    expect(
      sans(lib['validation_numeric'] as String, {':attribute': 'A'}),
      MessagesEncaissement.nombre('A'),
    );
    expect(
      sans(lib['validation_in'] as String, {':attribute': 'A'}),
      MessagesEncaissement.invalide('A'),
    );
    expect(
      sans(lib['validation_exists'] as String, {':attribute': 'A'}),
      MessagesEncaissement.invalide('A'),
    );
    // Le registre fermé des trésoreries : compte et journal.
    final tresoreries = (lib['tresoreries'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as Map<String, dynamic>),
    );
    expect(tresoreries.keys.toSet(), {
      for (final t in TresorerieDepense.values) t.code,
    });
    for (final t in TresorerieDepense.values) {
      expect(tresoreries[t.code]!['compte'], t.compte, reason: t.code);
      expect(tresoreries[t.code]!['journal'], t.journal, reason: t.code);
    }
    // Le plafond de la liste des commandes : celui de `AchatsApi.commandes`.
    expect(lib['plafond'], 200);
  });

  test('le droit : le serveur refuse tout rôle qui n’écrit pas sur M7 — le '
      'poste lit le MÊME niveau', () {
    var vus = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['op'] != 'droits') continue;
      vus++;
      final s = serveur[i] as Map<String, dynamic>;
      final garde = GardeAcces.depuisJson({'M7': s['niveau_m7'] as String});
      expect(
        garde.peutEcrire(ModuleTatacora.m7Achats),
        s['refus'] == false,
        reason: '${scenario[i]['role']} : ${s['niveau_m7']} -> $s',
      );
    }
    expect(vus, 12);
  });
}

// ------------------------------------------------------- rejeu sur le poste

/// Joue [scenario] sur une base locale neuve, avec les VRAIS DAO du poste, et
/// rend un résultat par opération dans la forme du serveur.
///
/// [serveur] n'est consulté que pour les NIVEAUX de droit des utilisateurs — que
/// le poste n'a aucun moyen de calculer (ils viennent de la matrice du serveur).
Future<List<Map<String, Object?>>> _rejouerSurLePoste(
  List<Map<String, Object?>> scenario,
  List<dynamic> serveur,
  DateTime maintenant,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await baseInstalleeSur(db, maintenant);

  final utilisateurs = <String, String>{}; // ref -> id
  final niveaux = <String, String>{}; // ref -> niveau M7
  final fournisseurs = <String, String>{}; // ref -> id
  final noms = <String, String>{}; // ref fournisseur -> raison sociale
  final articles = <String, String>{}; // ref -> id
  final commandes = <String, String>{}; // ref -> id
  final fournisseurDeCommande = <String, String>{}; // ref commande -> ref f.
  final reglements = <ReglementFournisseur>[];

  final resultats = <Map<String, Object?>>[];

  String refDeCommande(String id) =>
      commandes.entries.firstWhere((e) => e.value == id).key;

  AchatsApi api(String user) => apiAchatsSur(
    db,
    peutEcrire: GardeAcces.depuisJson({
      'M7': niveaux[user]!,
    }).peutEcrire(ModuleTatacora.m7Achats),
    auteur: utilisateurs[user],
    maintenant: maintenant,
  );
  final reglementsDao = reglementsDaoSur(db, maintenant: maintenant);

  Map<String, Object?> decrire(ReglementFournisseur r) => {
    'commande': refDeCommande(r.commandeId),
    'montant': chaineDepuisCentimes(r.montantCentimes),
    'tresorerie': r.tresorerie.code,
    'date_reglement': r.dateReglement,
    'statut': r.statut.code,
    'motif_annulation': r.motifAnnulation,
    'annule_par': r.annuleParId == null
        ? null
        : utilisateurs.entries.firstWhere((e) => e.value == r.annuleParId).key,
    'date_annulation_renseignee': r.dateAnnulation != null,
    'par': utilisateurs.entries
        .firstWhere((e) => e.value == r.utilisateurCreationId)
        .key,
  };

  Future<String> regleDe(String commandeId) async =>
      chaineDepuisCentimes(await reglementsDao.totalRegleCentimes(commandeId));

  /// Une valeur qui ne se lit pas comme un nombre bien formé fait PLANTER le
  /// serveur au rendu (voir l'en-tête du test) : on la reconnaît du MÊME côté.
  bool plante(String montant) {
    if (montant.isEmpty) return false;
    return montantAffichableDuChamp(montant) == null;
  }

  for (var i = 0; i < scenario.length; i++) {
    final op = scenario[i];
    switch (op['op']) {
      case 'libelles':
        resultats.add({'libelles': 'rien'});

      case 'utilisateur':
        final ref = op['ref']! as String;
        utilisateurs[ref] = 'u-$ref';
        await semerAuteur(db, id: 'u-$ref');
        final n = (serveur[i] as Map<String, dynamic>)['niveau_m7']! as String;
        niveaux[ref] = n;
        resultats.add({'ok': true, 'niveau_m7': n});

      case 'fournisseur':
        final ref = op['ref']! as String;
        fournisseurs[ref] = 'f-$ref';
        noms[ref] = op['nom']! as String;
        resultats.add({'ok': true});

      case 'article':
        articles[op['ref']! as String] = 'a-${op['ref']}';
        resultats.add({'ok': true});

      case 'commande':
        final ref = op['ref']! as String;
        final ligne = (op['lignes']! as List).single as Map<String, dynamic>;
        final id = await semerCommande(
          db,
          fournisseurId: fournisseurs[op['fournisseur']]!,
          fournisseur: noms[op['fournisseur']]!,
          articleId: articles[ligne['article']]!,
          quantite: ligne['quantite']! as String,
          prix: ligne['prix']! as String,
          date: op['date']! as String,
          statut: op['statut']! as String,
          auteurId: utilisateurs[op['user']]!,
          maintenant: maintenant,
        );
        commandes[ref] = id;
        fournisseurDeCommande[ref] = op['fournisseur']! as String;
        final detail = (await achatsDaoSur(
          db,
          maintenant: maintenant,
        ).commande(id))!;
        resultats.add({
          'ok': true,
          'montant_total': detail.commande.montantTotal,
        });

      case 'parametre':
        // La clé `compte_<rôle>` est posée DIRECTEMENT, comme le script PHP :
        // c'est la LECTURE au moment de régler qu'on mesure, pas l'écran.
        await ParametresDao(db).ecrire({
          op['cle']! as String: op['valeur'] as String?,
        }, auteurId: null);
        resultats.add({'ok': true});

      case 'statut':
        await poserStatut(
          db,
          commandes[op['commande']]!,
          op['statut']! as String,
        );
        resultats.add({'ok': true});

      case 'regler_service':
        final user = op['user']! as String;
        try {
          final r = await reglementsDao.reglerParLeService(
            commandeId: commandes[op['commande']]!,
            montant: op['montant']! as String,
            tresorerie: op['tresorerie']! as String,
            auteurId: utilisateurs[user]!,
          );
          reglements.add(r);
          resultats.add({
            'reglement': decrire(r),
            'montant_regle': await regleDe(r.commandeId),
          });
        } on RefusReglement catch (e) {
          resultats.add({'refus': 'RefusReglement', 'message': e.message});
        } on RefusComptable catch (e) {
          // Le refus de la PIÈCE (compte choisi absent du plan, division) : le
          // serveur lève une `RuntimeException`, ramenée au même refus.
          resultats.add({'refus': 'RefusReglement', 'message': e.message});
        }

      case 'regler_pwa':
        final user = op['user']! as String;
        final ref = op['commande']! as String;
        final montant = op['montant']! as String;
        final apiUser = api(user);
        if (op['ouvrir'] == true) {
          // L'ouverture précède : elle porte le droit (403) et l'état de la
          // commande. Un refus ici arrête le geste, comme au serveur.
          final ouverture = await apiUser.ouvrirReglement(commandes[ref]!);
          if (ouverture is AchatsRefuse<OuvertureReglement>) {
            resultats.add(
              ouverture.code == 403
                  ? {'statut': 403, 'module_refuse': 'M7'}
                  : {
                      'erreurs': {
                        'selection': [ouverture.motif],
                      },
                      'succes': null,
                      'reglement': null,
                      'modale_fermee': true,
                    },
            );
            break;
          }
        }
        final resultat = await apiUser.reglerCommande(
          commandeId: commandes[ref],
          montant: montant,
          tresorerie: op['tresorerie']! as String,
        );
        switch (resultat) {
          case AchatsRecu(:final donnees):
            reglements.add(donnees);
            resultats.add({
              'erreurs': <String, Object?>{},
              'succes': MessagesReglement.enregistre(
                montant,
                // Une saisie FORGÉE (sans ouverture) ne porte pas le nom : la
                // modale ne l'a jamais posé.
                op['ouvrir'] == true ? noms[fournisseurDeCommande[ref]]! : '',
              ),
              'reglement': decrire(donnees),
              'modale_fermee': true,
              'reg_montant': montant,
            });
          case AchatsRefuse(:final code, :final erreurs):
            if (code == 403) {
              resultats.add({'statut': 403, 'module_refuse': 'M7'});
            } else if (plante(montant)) {
              resultats.add({'plantage': true});
            } else {
              resultats.add({
                'erreurs': {
                  for (final e in erreurs.entries) e.key: [e.value],
                },
                'succes': null,
                'reglement': null,
                // Une saisie FORGÉE n'a jamais ouvert la modale : elle est
                // « fermée » avant comme après (`etatFormulaire` reste nul).
                'modale_fermee': op['ouvrir'] != true,
                'reg_montant': montant,
              });
            }
          case AchatsInjoignable():
            fail('Jamais produite : la base est locale.');
        }

      case 'ouvrir_pwa':
        final user = op['user']! as String;
        final inconnue = op['commande_inconnue'] as String?;
        final r = await api(
          user,
        ).ouvrirReglement(inconnue ?? commandes[op['commande']]!);
        switch (r) {
          case AchatsRecu(:final donnees):
            resultats.add({
              'erreurs': <String, Object?>{},
              'modale_ouverte': true,
              'reg_montant': chaineDepuisCentimes(donnees.resteDuCentimes),
              'reg_tresorerie': donnees.tresorerieDeDepart.code,
              'fournisseur_nom': donnees.fournisseurNom,
            });
          case AchatsRefuse(:final code, :final motif):
            resultats.add(
              code == 403
                  ? {'statut': 403, 'module_refuse': 'M7'}
                  : {
                      'erreurs': {
                        'selection': [motif],
                      },
                      'modale_ouverte': false,
                      'reg_montant': '',
                      'reg_tresorerie': 'caisse',
                      'fournisseur_nom': '',
                    },
            );
          case AchatsInjoignable():
            fail('Jamais produite : la base est locale.');
        }

      case 'annuler':
        final cible = reglements[op['reglement']! as int];
        try {
          final r = await reglementsDao.annuler(
            cible.id,
            op['motif']! as String,
            auteurId: utilisateurs[op['user']]!,
          );
          reglements[op['reglement']! as int] = r;
          resultats.add({
            'reglement': decrire(r),
            'montant_regle': await regleDe(r.commandeId),
          });
        } on RefusReglement catch (e) {
          resultats.add({'refus': 'RefusReglement', 'message': e.message});
        }

      case 'vue':
        final statut = op['statut']! as String;
        final recherche = op['recherche']! as String;
        final r = await api('g').commandes(
          statut: statut.isEmpty ? null : StatutCommande.depuisCode(statut),
          recherche: recherche.isEmpty ? null : recherche,
        );
        final liste =
            (r as AchatsRecu<PageAchats<CommandeAchat>>).donnees.elements;
        final indicateurs = composerIndicateursDettes(liste);
        resultats.add({
          'ordre_commandes': [for (final c in liste) refDeCommande(c.id)],
          'reglesEtRestes': {
            for (final c in liste)
              refDeCommande(c.id): {
                'regle': c.montantRegle,
                'reste': c.resteDu,
              },
          },
          'totalDu': chaineDepuisCentimes(indicateurs.totalDuCentimes),
          'fournisseursAPayer': indicateurs.fournisseursAPayer,
          'dettes': [
            for (final g in composerDettes(liste))
              {
                'fournisseur': g.fournisseur,
                'commandes': [for (final c in g.commandes) refDeCommande(c.id)],
              },
          ],
          'peutEcrire': true,
        });

      case 'etat_achats':
        final liste = recu(await api('g').commandes());
        final apercu = apercuAchats(liste.elements);
        resultats.add({
          'indicateurs': [for (final k in apercu.indicateurs) k.valeur],
          'entetes': apercu.entetes,
          'lignes': apercu.lignes,
        });

      case 'droits':
        final s = serveur[i] as Map<String, dynamic>;
        final garde = GardeAcces.depuisJson({'M7': s['niveau_m7'] as String});
        resultats.add({
          'role': op['role'],
          'refus': !garde.peutEcrire(ModuleTatacora.m7Achats),
          'niveau_m7': s['niveau_m7'],
        });

      case 'etat':
        final comptabilite = ComptabiliteDao(db);
        final journaux = {
          for (final j in await comptabilite.journaux()) j.id: j.code,
        };
        final centres = {
          for (final c in await comptabilite.centres()) c.id: c.libelle,
        };
        final ecritures = <Map<String, Object?>>[];
        for (final e in await comptabilite.toutesLesEcritures()) {
          final compte = await comptabilite.compteParId(e.compteId);
          var libelle = e.libelle;
          for (var n = 0; n < reglements.length; n++) {
            libelle = libelle.replaceAll(reglements[n].id, 'REGL:$n');
          }
          ecritures.add({
            'journal': journaux[e.journalId],
            'compte': compte!.numero,
            'centre': centres[e.centreId],
            'libelle': libelle,
            'debit': e.debit,
            'credit': e.credit,
            'statut': e.statut.name,
            'numero_piece_renseigne': e.numeroPiece != null,
            'numero_piece': e.numeroPiece,
            'date': e.dateEcriture,
            'contrepasse': e.ecritureContrepasseeId != null,
          });
        }
        final tous = await reglementsDao.reglements();
        final parCreation = [
          for (final r in reglements) (await reglementsDao.parId(r.id)) ?? r,
        ];
        final cmds = <String, Object?>{};
        for (final e in commandes.entries) {
          final d = (await achatsDaoSur(
            db,
            maintenant: maintenant,
          ).commande(e.value))!;
          cmds[e.key] = {
            'montant_total': d.commande.montantTotal,
            'montant_regle': d.commande.montantRegle,
            'statut': d.commande.statutCode,
          };
        }
        resultats.add({
          'reglements': [for (final r in parCreation) decrire(r)],
          'ecritures': ecritures,
          'commandes': cmds,
          'nb_reglements': tous.length,
          'nb_ecritures': ecritures.length,
        });

      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}

// ------------------------------------------------------------ normalisation

/// Le serveur dans la forme commune : un plantage de rendu (`ViewException`) et
/// un `ValueError` de `bcmath` deviennent des refus nommés, les erreurs vides
/// sont `{}`, et les clés qui n'ont pas d'équivalent sur le poste disparaissent.
Map<String, Object?> _normaliserServeur(Map<String, dynamic> brut) {
  final r = Map<String, Object?>.from(brut);

  // Les libellés sont comparés par un test à part : ici, un résultat par
  // opération, de même forme des deux côtés.
  if (r.containsKey('libelles')) return {'libelles': 'rien'};

  final refus = r['refus'];
  if (refus == 'ViewException') return {'plantage': true};
  if (refus == 'ValueError') return {'refus': 'mal_forme'};
  if (refus == 'RuntimeException') {
    return {'refus': 'refus', 'message': r['message']};
  }
  // (`refus` est un BOOLÉEN pour l'opération `droits`, une chaîne sinon.)
  if (refus is String) {
    return {'refus': 'inattendu:$refus', 'message': r['message']};
  }

  if (r['erreurs'] is List && (r['erreurs'] as List).isEmpty) {
    r['erreurs'] = <String, Object?>{};
  }
  if (r['reglesEtRestes'] is List && (r['reglesEtRestes'] as List).isEmpty) {
    r['reglesEtRestes'] = <String, Object?>{};
  }
  if (r.containsKey('erreurs') && r['erreurs'] is Map) {
    // Seule la PREMIÈRE erreur de validation du serveur (dans l'ordre commande,
    // montant, trésorerie) est comparée : l'écran n'affiche que celle du
    // montant, et le poste lève la première.
    final erreurs = (r['erreurs'] as Map).cast<String, dynamic>();
    if (erreurs.length > 1) {
      for (final champ in ['regCommandeId', 'regMontant', 'regTresorerie']) {
        if (erreurs.containsKey(champ)) {
          r['erreurs'] = {champ: erreurs[champ]};
          break;
        }
      }
    }
  }
  // Le sous-titre et les valeurs de rendu relèvent du test de rendu (les VRAIS
  // widgets, comparés au HTML du serveur) : ils ne sont pas comparables ici.
  r
    ..remove('sous_titre')
    ..remove('rendu_commandes')
    ..remove('rendu_dettes')
    ..remove('rendu_kpis')
    ..remove('rendu_total_dettes');

  // Un refus du service rendu par le composant (hors `regMontant`) : sans objet.
  return r;
}

/// Le poste dans la même forme. Un refus que le serveur traduit par un plantage
/// est reconnu par [_normaliserServeur] ; ici, un refus de `mal_forme`.
Map<String, Object?> _normaliserLocal(Map<String, Object?> brut) {
  final r = Map<String, Object?>.from(brut);
  if (r['refus'] == 'RefusReglement') {
    if (r['message'] == MessagesReglement.malForme) {
      return {'refus': 'mal_forme'};
    }
    return {'refus': 'refus', 'message': r['message']};
  }
  return r;
}

/// Un rendu stable d'une valeur JSON : clés triées, lignes comptables dans un
/// ordre canonique, espaces insécables ramenés à l'espace.
String _canon(Object? valeur) => jsonEncode(_trier(valeur));

Object? _trier(Object? v) {
  if (v is Map) {
    return {
      for (final k in (v.keys.map((e) => '$e').toList()..sort()))
        k: _trier(v[k]),
    };
  }
  if (v is List) {
    final l = [for (final e in v) _trier(e)];
    if (l.isNotEmpty &&
        l.first is Map &&
        (l.first as Map).containsKey('compte') &&
        (l.first as Map).containsKey('journal')) {
      l.sort((a, b) => jsonEncode(a).compareTo(jsonEncode(b)));
    }
    return l;
  }
  if (v is String) {
    return v.replaceAll(' ', ' ');
  }
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
