@Timeout(Duration(minutes: 3))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/modules_pilotage.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/especes_de_la_session.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/crm/data/client_dao.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/registre_clients.dart';
import 'package:tatacora_flutter/features/etats/domain/apercus_etats.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/facturation/domain/messages_encaissement.dart';
import 'package:tatacora_flutter/features/facturation/domain/regles_encaissement.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_api.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/data/tableau_de_bord_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_encaissement.dart';

/// LE MÊME scénario d'encaissement, joué par les VRAIS services du serveur
/// (`EncaissementFactureService`, `ClientsCreances`, `SoldeClientService`,
/// `TableauDeBordService`, `EtatCreancesClients`, `PosComptant`) sur MySQL, et
/// par le poste sur sa base locale, comparé CHAMP À CHAMP : le refus de chaque
/// geste (dans l'ordre, avec sa phrase), le paiement écrit, la pièce comptable,
/// le reste dû, le solde de chaque client, les trois indicateurs de M11, l'état
/// de M14, la session rattachée à une vente, le théorique et l'écart de clôture.
///
/// `tool/encaissement/rejouer_encaissement.php` travaille sur `tatacora_test` (il
/// refuse toute autre base), sème les rôles et le référentiel comptable par les
/// vrais seeders, puis ANNULE tout : la base n'est pas modifiée. MySQL
/// injoignable : le test ÉCHOUE, il ne saute pas.
///
/// Le scénario est UN seul JSON lu par les deux moteurs : un scénario recopié à
/// la main des deux côtés ne prouverait rien.
///
/// ## Les écarts de représentation, normalisés avant la comparaison
///
/// 1. le séparateur de milliers du serveur est l'insécable U+00A0 ; celui du
///    poste, l'espace ordinaire ;
/// 2. un refus que le serveur ne traduit pas (`ValueError` de `bcmath`, HTTP 500
///    sur « 1e3 ») devient, au poste, un refus AVEC phrase : la comparaison porte
///    sur « rien n'est écrit » et sur le refus lui-même ;
/// 3. le serveur identifie une facture par `numero_mecef`, le poste par le numéro
///    de pièce `F-AAAA-NNNNN` : les deux sont ramenés à la référence du scénario ;
/// 4. le serveur affiche toutes les erreurs de validation à la fois, le poste la
///    première : seule la PREMIÈRE du serveur (dans l'ordre pièce, montant, mode)
///    est comparée ;
/// 5. l'ordre des lignes comptables est canonique (le serveur ne fixe aucun ordre
///    entre deux lignes de la même seconde).
void main() {
  const aujourdhui = '2026-10-12';
  final maintenant = DateTime(2026, 10, 12, 10);

  // ------------------------------------------------------------------ scénario
  Map<String, Object?> encaisser(
    String facture,
    String montant,
    String mode, {
    String user = 'g',
  }) => {
    'op': 'encaisser',
    'facture': facture,
    'montant': montant,
    'mode': mode,
    'user': user,
  };
  Map<String, Object?> recouvrer(
    String facture,
    String montant,
    String mode, {
    String user = 'g',
    String client = 'd',
  }) => {
    'op': 'recouvrer',
    'user': user,
    'client': client,
    'facture': facture,
    'montant': montant,
    'mode': mode,
  };
  Map<String, Object?> annuler(int paiement, String motif) => {
    'op': 'annuler',
    'paiement': paiement,
    'motif': motif,
    'user': 'g',
  };
  Map<String, Object?> kpis(String periode) => {
    'op': 'kpis',
    'periode': periode,
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'libelles'},
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'utilisateur', 'ref': 'b', 'role': 'barman'},
    {'op': 'client', 'ref': 'k', 'nom': 'KORA', 'prenom': 'Jean'},
    {'op': 'client', 'ref': 'd', 'nom': 'DOSSOU', 'prenom': null},
    {'op': 'client', 'ref': 'z', 'nom': 'ZOUNON', 'prenom': null},
    {'op': 'reservation', 'ref': 'r1', 'client': 'k', 'acompte': '20000'},
    {
      'op': 'facture',
      'ref': 'f1',
      'client': 'k',
      'ttc': '50000',
      'date': '2026-10-01',
      'reservation': 'r1',
    },
    {
      'op': 'facture',
      'ref': 'f2',
      'client': 'k',
      'ttc': '30000',
      'date': '2026-09-01',
    },
    {
      'op': 'facture',
      'ref': 'f3',
      'client': 'd',
      'ttc': '12000',
      'date': '2026-10-10',
    },
    {
      'op': 'facture',
      'ref': 'f4',
      'client': 'd',
      'ttc': '8000',
      'date': '2026-08-20',
    },
    {'op': 'avoir', 'facture': 'f4', 'montant': '8000'},
    // La balance âgée : une facture de 133 jours (+ de 90), une de 84 jours
    // (61 à 90), et une datée du FUTUR (un nombre de jours négatif, que le serveur
    // range en « + de 90 jours » faute de tranche qui le contienne).
    {'op': 'client', 'ref': 'y', 'nom': 'YAYI', 'prenom': 'Rose'},
    {
      'op': 'facture',
      'ref': 'f5',
      'client': 'y',
      'ttc': '7000',
      'date': '2026-06-01',
    },
    {
      'op': 'facture',
      'ref': 'f6',
      'client': 'y',
      'ttc': '3000',
      'date': '2026-07-20',
    },
    {
      'op': 'facture',
      'ref': 'f7',
      'client': 'd',
      'ttc': '500',
      'date': '2026-10-20',
    },
    // Les bornes du graphique de l'ACCUEIL (13/10/2026) : 30 jours pile
    // (J-30) et 90 jours pile (J-90) — `>` / `<=` côté serveur, une facture de
    // 30 jours pile tombe en « 31 à 60 jours » (et en « 0 à 30 » sur l'écran
    // Clients & créances).
    {
      'op': 'facture',
      'ref': 'f8',
      'client': 'y',
      'ttc': '1500',
      'date': '2026-09-12',
    },
    {
      'op': 'facture',
      'ref': 'f9',
      'client': 'y',
      'ttc': '2500',
      'date': '2026-07-14',
    },

    // --- Les refus du service, dans l'ordre, AVANT toute caisse ouverte ---
    encaisser('f1', 'abc', 'cheque'), // mode inconnu avant montant
    encaisser('f1', 'abc', 'especes'), // montant illisible
    encaisser('f1', '0', 'especes'),
    encaisser('f1', '-5', 'especes'),
    encaisser('f1', '0.004', 'especes'), // > 0 mais tronqué à 0.00
    encaisser('f1', '', 'especes'),
    encaisser('f1', '30000.01', 'especes'), // sur-encaissement avant la caisse
    encaisser('f1', '1e3', 'especes'), // ValueError au serveur
    encaisser('f1', ' 100', 'especes'), // ValueError au serveur
    encaisser('f1', '100', 'especes'), // caisse fermée
    encaisser('f4', '1', 'especes'), // facture neutralisée par son avoir
    {'op': 'etat'},

    // --- Le point de vente exige la caisse du BAR, la facture n'importe laquelle
    {'op': 'catalogue_bar', 'prix': '1000'},
    {
      'op': 'session',
      'user': 'g',
      'point': 'reception',
      'fond': '5000',
      'ouverte': true,
      'il_y_a_minutes': 120,
    },
    {'op': 'vente_pos', 'user': 'g', 'mode': 'especes'},
    encaisser('f1', '1000.5', 'especes'), // session de la réception
    {
      'op': 'session',
      'user': 'g',
      'point': 'bar',
      'fond': '10000',
      'ouverte': true,
      'il_y_a_minutes': 60,
    },
    encaisser('f1', '2000', 'mobile_money'), // la PLUS RÉCENTE : le bar
    encaisser('f1', '100.999', 'carte'), // tronqué à 100.99
    encaisser('f2', '30000', 'virement'),
    encaisser('f2', '1', 'especes'), // plus rien à devoir
    {'op': 'etat'},
    {'op': 'soldes'},
    kpis('mois'),

    // --- Le geste « Recouvrement » d'une ligne : ce que la modale propose ---
    {'op': 'ouvrir_recouvrement', 'user': 'g', 'client': 'k'},
    {'op': 'ouvrir_recouvrement', 'user': 'g', 'client': 'd'},
    {'op': 'ouvrir_recouvrement', 'user': 'g', 'client': 'z'},

    // --- Le composant : droit, puis validation, puis service ---
    recouvrer('f3', '1000', 'especes', user: 'b'),
    recouvrer('', 'abc', 'x'),
    recouvrer('fantome', '5', 'especes'), // la règle `uuid` d'abord
    recouvrer('00000000-0000-4000-8000-000000000000', '5', 'especes'),
    recouvrer('f3', '', 'especes'),
    recouvrer('f3', '   ', 'especes'),
    recouvrer('f3', 'abc', 'especes'),
    recouvrer('f3', '0', 'especes'),
    recouvrer('f3', '-5', 'especes'),
    recouvrer('f3', '5', ''),
    recouvrer('f3', '5', 'cheque'),
    recouvrer('f3', '1e3', 'especes'),
    recouvrer('f3', '99999', 'especes'),
    recouvrer('f3', '12000', 'especes'),
    recouvrer('f3', '1', 'especes'),
    // Un client qui ne doit rien : la phrase « aucune créance ».
    {'op': 'ouvrir_recouvrement', 'user': 'g', 'client': 'z'},
    {'op': 'dette_agee'},
    {'op': 'dette_agee', 'terme': 'dossou'},
    {'op': 'dette_agee', 'terme': 'ROS'}, // le PRÉNOM, sans casse
    {'op': 'anciennete_accueil'},
    {'op': 'etat'},
    {'op': 'soldes'},
    {'op': 'soldes', 'etat': 'debiteur'},

    // --- L'annulation ---
    annuler(0, '   '),
    annuler(0, 'Doublon'),
    annuler(0, 'Encore'),
    {'op': 'renommer_facture', 'facture': 'f2', 'numero': 'AILLEURS'},
    annuler(3, 'Doublon'), // la pièce ne se retrouve plus par son libellé
    {'op': 'etat'},
    {'op': 'soldes'},
    // Les sept périodes du SÉLECTEUR de la vue (`Periode::resoudre`, D296) —
    // « personnalisee » sans ses dates se résout sur le mois.
    for (final p in [
      'aujourdhui',
      'semaine',
      'mois',
      'trimestre',
      'semestre',
      'annee',
      'personnalisee',
    ])
      kpis(p),
    {'op': 'etat_creances'},

    // --- La caisse du bar : espèces des VENTES seulement ---
    {'op': 'vente_pos', 'user': 'g', 'mode': 'especes'},
    {'op': 'vente_pos', 'user': 'g', 'mode': 'mobile_money'},
    {'op': 'vente_pos', 'user': 'g', 'mode': 'especes'},
    {'op': 'theorique_propose', 'user': 'g'},
    {'op': 'cloturer', 'user': 'g', 'constate': '12345'},
    {'op': 'vente_pos', 'user': 'g', 'mode': 'especes'}, // le bar est CLOS
    kpis('mois'),
    {'op': 'etat'},

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
      {'op': 'droits_recouvrement', 'role': role, 'client': 'k'},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_encaissement.php',
      dossier: 'encaissement',
      entree: {'aujourdhui': aujourdhui, 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _rejouerSurLePoste(scenario, serveur, maintenant);
  });

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(scenario.length, greaterThan(90));
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));

    final issues = [
      for (final r in serveur) _normaliserServeur(r as Map<String, dynamic>),
    ];
    // Le serveur a RÉELLEMENT refusé ET RÉELLEMENT accepté : un scénario où tout
    // passerait (ou tout serait refusé) ne comparerait aucune règle.
    expect(issues.where((i) => i['refus'] == 'refus'), isNotEmpty);
    expect(issues.where((i) => i['refus'] == 'mal_forme'), isNotEmpty);
    expect(issues.where((i) => i['paiement'] != null), isNotEmpty);
    expect(issues.where((i) => i['statut'] == 403), isNotEmpty);
    expect(
      issues.where((i) => (i['erreurs'] as Map?)?.isNotEmpty ?? false),
      isNotEmpty,
    );
    expect(
      issues.where(
        (i) => (i['succes'] as String?)?.startsWith('Recouvrement') ?? false,
      ),
      isNotEmpty,
    );
    // Les deux moitiés du RBAC : des rôles qui encaissent, des rôles qui ne le
    // font pas — leur droit est LU du serveur.
    final droits = [
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['op'] == 'droits_recouvrement')
          (serveur[i] as Map<String, dynamic>)['statut'],
    ];
    expect(droits.where((s) => s == 200), hasLength(4));
    expect(droits.where((s) => s == 403), hasLength(8));
    // La balance âgée a de quoi comparer : plusieurs clients, une facture de plus
    // de 90 jours, et un filtre par prénom qui ne garde qu'une ligne.
    final dettes = [
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['op'] == 'dette_agee')
          serveur[i] as Map<String, dynamic>,
    ];
    expect(dettes, hasLength(3));
    expect((dettes[0]['dette_agee'] as List).length, greaterThanOrEqualTo(3));
    expect(dettes[0]['kpi_douteux'], isNot('0.00'));
    expect(dettes[0]['kpi_recent'], isNot('0.00'));
    expect((dettes[1]['dette_agee'] as List), hasLength(1));
    expect((dettes[2]['dette_agee'] as List), hasLength(1));
    // Le KPI se lit sur la balance COMPLÈTE, jamais sur le filtre.
    expect(dettes[1]['kpi_douteux'], dettes[0]['kpi_douteux']);
    // Le graphique de l'ACCUEIL a ses propres bornes (13/10/2026) : la facture
    // de 30 jours pile (f8, 1 500 F) est en « 31 à 60 jours », celle de 90
    // jours pile (f9, 2 500 F) en « plus de 90 » ; la facture datée du futur
    // (f7) est en « 0 à 30 ». Sans ces cas, la comparaison serait verte sur des
    // bornes jamais éprouvées.
    final anciennete =
        (serveur[scenario.indexWhere((o) => o['op'] == 'anciennete_accueil')]
                as Map<String, dynamic>)['anciennete']
            as List<dynamic>;
    expect(
      [for (final t in anciennete) (t as Map)['cle']],
      ['0_30', '30_60', '60_90', 'plus_90'],
    );
    for (final t in anciennete) {
      expect((t as Map)['pieces'], greaterThan(0), reason: '${t['cle']}');
    }
    // Le filtre n'est pas un trou : le serveur a bien passé des pièces VTE, et
    // le poste aussi depuis le lot 6 — mais leur comparaison est dans
    // `ventes_contre_serveur_test.dart`. Sans cette ligne, le filtre ne
    // cacherait plus rien et le test ne dirait pas qu'il écarte quelque chose.
    final dernierEtat =
        serveur[scenario.lastIndexWhere((o) => o['op'] == 'etat')]
            as Map<String, dynamic>;
    expect(
      (dernierEtat['ecritures'] as List).where(
        (e) => (e as Map<String, dynamic>)['journal'] == _journalDesVentes,
      ),
      isNotEmpty,
      reason:
          'sans cette ligne, le filtre des pièces de vente ne cacherait '
          'plus rien et le test ne dirait pas ce qu’il écarte',
    );
    // La session ouverte au moment de la vente est celle du bar.
    expect(
      issues.where(
        (i) => i['session_point'] == 'bar' && i['vente_creee'] == true,
      ),
      isNotEmpty,
    );
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

    expect(lib['non_figee'], MessagesEncaissement.factureNonFigee);
    expect(
      sans(lib['mode_inconnu'] as String, {':mode': 'cheque'}),
      MessagesEncaissement.modeInconnu('cheque'),
    );
    expect(lib['montant_invalide'], MessagesEncaissement.montantInvalide);
    expect(
      sans(lib['superieur_au_reste'] as String, {':reste': '6000.00'}),
      MessagesEncaissement.superieurAuReste('6000.00'),
    );
    expect(lib['caisse_fermee'], MessagesEncaissement.caisseFermee);
    expect(lib['deja_annule'], MessagesEncaissement.dejaAnnule);
    expect(lib['motif_requis'], MessagesEncaissement.motifRequis);
    expect(
      sans(lib['piece_introuvable'] as String, {':libelle': 'L'}),
      MessagesEncaissement.pieceIntrouvable('L'),
    );
    expect(lib['module_refuse'], MessagesEncaissement.refusDroit);
    expect(lib['aucune_creance'], MessagesEncaissement.aucuneCreance);
    expect(lib['avertissement'], MessagesEncaissement.avertissement);
    expect(
      sans(lib['succes'] as String, {':montant': 'M', ':client': 'C'}),
      MessagesEncaissement.succes('M', 'C'),
    );
    expect(lib['validation_gt'], MessagesEncaissement.superieurAZero);
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
    expect(lib['encaisser_sans_caisse'], MessagesCaisse.encaisserSansCaisse);
    expect(lib['refus_sans_caisse'], MessagesCaisse.refusSansCaisse);

    // La modale et le tableau.
    expect(lib['titre_modale'], 'Ajouter un recouvrement');
    expect(lib['champ_piece'], 'Pièce réglée');
    expect(lib['champ_du'], 'dû');
    expect(lib['champ_montant'], 'Montant reçu (FCFA)');
    expect(lib['champ_mode'], 'Mode');
    expect(lib['champ_enregistrer'], 'Enregistrer le recouvrement');
    expect(lib['action_recouvrement'], 'Recouvrement');
    expect(
      sans(lib['recouvrements_titre'] as String, {':nombre': '3'}),
      'Recouvrements encaissés (3)',
    );
    expect(lib['recouvrements_vide'], 'Aucun recouvrement enregistré.');

    // Le registre fermé des modes, leur libellé et leur trésorerie.
    expect(lib['modes'], [for (final m in ModePaiementFacture.values) m.code]);
    expect(lib['mode_especes'], ModePaiementFacture.especes.libelle);
    expect(lib['mode_mobile_money'], ModePaiementFacture.mobileMoney.libelle);
    expect(lib['mode_carte'], ModePaiementFacture.carte.libelle);
    expect(lib['mode_virement'], ModePaiementFacture.virement.libelle);
    expect(lib['tresorerie_par_mode'], {
      for (final m in ModePaiementFacture.values) m.code: m.tresorerie.code,
    });
    final tresoreries = (lib['tresoreries'] as Map<String, dynamic>).map(
      (k, v) => MapEntry(k, v as Map<String, dynamic>),
    );
    expect(tresoreries.keys.toSet(), {
      for (final t in TresorerieEncaissement.values) t.code,
    });
    // Le plafond des journaux de la vue.
    expect((lib['tableau_dates'] as Map<String, dynamic>)['plafond'], 200);
  });

  test('le droit : le serveur refuse M3 d’abord, puis M2 — le poste exige '
      'les deux', () {
    var vus = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['op'] != 'droits_recouvrement') continue;
      vus++;
      final s = serveur[i] as Map<String, dynamic>;
      final niveaux = (s['niveaux'] as Map<String, dynamic>)
          .cast<String, String>();
      final garde = GardeAcces.depuisJson(niveaux);
      expect(
        peutEncaisserUneFacture(garde),
        s['statut'] == 200,
        reason: '${scenario[i]['role']} : $niveaux -> ${s['statut']}',
      );
      final premier = niveaux['M3'] != 'C'
          ? 'M3'
          : (niveaux['M2'] != 'C' ? 'M2' : null);
      expect(s['module_refuse'], premier, reason: '${scenario[i]['role']}');
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
  final db = await baseEncaissement();
  addTearDown(db.close);

  final dao = paiementsDaoSur(db);
  final factures = factureDaoSur(db);
  final comptabilite = ComptabiliteDao(db);

  final utilisateurs = <String, String>{}; // ref -> id
  final niveaux = <String, Map<String, String>>{}; // ref -> M2/M3
  final clients = <String, String>{}; // ref -> id
  final noms = <String, String>{}; // ref -> nom complet
  final pieces = <String, PieceFacturation>{}; // ref -> pièce
  final numeros = <String, String>{}; // numéro local -> jeton
  final paiements = <PaiementFacture>[];
  var boissonSemee = false;

  /// Le panier du comptoir EN COURS : une vente refusée (caisse fermée) le laisse
  /// ouvert avec ses lignes — le caissier appuie de nouveau, et la ligne
  /// s'ajoute (la quantité passe à deux). C'est le comportement des DEUX côtés.
  String? panierDuComptoir;

  String refDeUtilisateur(String id) =>
      utilisateurs.entries.firstWhere((e) => e.value == id).key;

  String jetonDeFacture(String ref) => 'FACT:${ref.toLowerCase()}';

  Future<Map<String, String>> pointsDesSessions() async => {
    for (final s in await SessionsCaisseDao(db).sessions()) s.id: s.point.code,
  };

  Future<Map<String, Object?>> decrire(PaiementFacture p) async {
    final points = await pointsDesSessions();
    final piece = pieces.entries.firstWhere((e) => e.value.id == p.pieceId);
    return {
      'facture': piece.key,
      'session_point': points[p.sessionId],
      'mode': p.mode.code,
      'montant': chaineDepuisCentimes(p.montantCentimes),
      'statut': p.statut.code,
      'motif_annulation': p.motifAnnulation,
      'annule_par_renseigne': p.annuleParId != null,
      'date_annulation_renseignee': p.dateAnnulation != null,
      'par': refDeUtilisateur(p.utilisateurCreationId),
    };
  }

  Future<String> resteDu(String ref) async {
    final piece = (await factures.parId(pieces[ref]!.id))!;
    return chaineDepuisCentimes((await dao.creanceDe(piece)).resteDuCentimes);
  }

  Future<List<CreanceFacture>> creances() async => composerCreances(
    pieces: await factures.pieces(),
    paiements: await dao.paiements(),
    acomptesParReservation: acomptesDesReservations(
      await ReservationDao(db).reservations(),
    ),
  );

  Future<List<LigneClient>> registre() async => composerRegistre(
    clients: await ClientDao(db).clients(),
    creances: await creances(),
  );

  Future<List<Map<String, Object?>>> ecritures() async {
    final journaux = {
      for (final j in await comptabilite.journaux()) j.id: j.code,
    };
    final centres = {
      for (final c in await comptabilite.centres()) c.id: c.libelle,
    };
    final out = <Map<String, Object?>>[];
    for (final e in await comptabilite.toutesLesEcritures()) {
      // Les pièces de VENTE (journal VTE) sont écartées des DEUX côtés : le
      // serveur les passe depuis le 02/09/2026, le poste depuis le lot 6, et
      // leur identité est confrontée par `ventes_contre_serveur_test.dart`, qui
      // compare chaque ligne. Ici, on compare les encaissements de FACTURE.
      if (journaux[e.journalId] == _journalDesVentes) continue;
      final compte = await comptabilite.compteParId(e.compteId);
      out.add({
        'journal': journaux[e.journalId],
        'compte': compte!.numero,
        'centre': centres[e.centreId],
        'libelle': e.libelle,
        'debit': e.debit,
        'credit': e.credit,
        'statut': e.statut.name == 'validee' ? 'validee' : e.statut.name,
        'numero_piece_renseigne': e.numeroPiece != null,
        'numero_piece': e.numeroPiece,
        'date': e.dateEcriture,
        'contrepasse': e.ecritureContrepasseeId != null,
      });
    }
    return out;
  }

  String normaliserLibelle(String l) {
    var r = l;
    for (final e in numeros.entries) {
      r = r.replaceAll(e.key, e.value);
    }
    return r;
  }

  final resultats = <Map<String, Object?>>[];

  for (var i = 0; i < scenario.length; i++) {
    final op = scenario[i];
    switch (op['op']) {
      case 'libelles':
        resultats.add({'libelles': 'rien'});

      case 'utilisateur':
        final ref = op['ref']! as String;
        utilisateurs[ref] = 'u-$ref';
        await semerAuteur(db, id: 'u-$ref');
        final n =
            ((serveur[i] as Map<String, dynamic>)['niveaux']
                    as Map<String, dynamic>)
                .cast<String, String>();
        niveaux[ref] = n;
        resultats.add({'ok': true, 'niveaux': n});

      case 'client':
        final c = await ClientDao(db).creer(
          nom: op['nom']! as String,
          prenom: op['prenom'] as String?,
          telephone: '97111111',
          type: _particulier,
        );
        clients[op['ref']! as String] = c.id;
        noms[op['ref']! as String] = c.nomComplet;
        resultats.add({'ok': true});

      case 'reservation':
        await semerReservation(
          db,
          id: op['ref']! as String,
          clientId: clients[op['client']]!,
          acompte: int.parse(op['acompte']! as String),
        );
        resultats.add({'ok': true});

      case 'facture':
        final ref = op['ref']! as String;
        final reservation = op['reservation'] as String?;
        final p = await emettreFacture(
          db,
          montant: int.parse(op['ttc']! as String),
          clientId: clients[op['client']],
          clientNom: noms[op['client']]!,
          reservationId: reservation,
          module: reservation == null
              ? ModuleFacturable.m5Bar
              : ModuleFacturable.m1Hebergement,
          horloge: DateTime.parse('${op['date']} 09:00:00'),
        );
        pieces[ref] = p;
        numeros[p.numero] = jetonDeFacture(ref);
        resultats.add({'ok': true});

      case 'avoir':
        // Un avoir TOTAL : le poste n'a pas d'avoir partiel (la facture est
        // annulée par un avoir de même montant).
        final ref = op['facture']! as String;
        await factures.annuler(pieces[ref]!.id, 'Erreur de saisie');
        resultats.add({'ok': true});

      case 'session':
        final minutes = (op['il_y_a_minutes'] as int?) ?? 30;
        final quand = maintenant.subtract(Duration(minutes: minutes));
        await SessionsCaisseDao(db, maintenant: () => quand).ouvrir(
          point: PointDeVenteCaisse.depuisCode(op['point']! as String)!,
          fondSaisi: op['fond']! as String,
          auteurId: utilisateurs[op['user']]!,
          peutEcrire: true,
        );
        resultats.add({'ok': true});

      case 'encaisser':
        final ref = op['facture']! as String;
        try {
          final p = await dao.encaisser(
            pieceId: pieces[ref]!.id,
            montant: op['montant']! as String,
            mode: op['mode']! as String,
            auteurId: utilisateurs[op['user']]!,
          );
          paiements.add(p);
          resultats.add({
            'ok': true,
            'paiement': await decrire(p),
            'reste_du': await resteDu(ref),
          });
        } on RefusEncaissement catch (e) {
          resultats.add({'refus': 'RefusEncaissement', 'message': e.message});
        }

      case 'recouvrer':
        final user = op['user']! as String;
        final n = niveaux[user]!;
        final peut = peutEncaisserUneFacture(GardeAcces.depuisJson(n));
        final refFacture = op['facture']! as String;
        final pieceId = pieces[refFacture]?.id ?? refFacture;
        try {
          final p = await dao.recouvrer(
            pieceId: pieceId,
            montantSaisi: op['montant'] as String?,
            modeSaisi: op['mode'] as String?,
            auteurId: utilisateurs[user]!,
            peutEncaisser: peut,
          );
          paiements.add(p);
          resultats.add({
            'erreurs': <String, Object?>{},
            'succes': messageDeRecouvrement(p, noms[op['client']]!),
            'paiement': await decrire(p),
            'modale_fermee': true,
          });
        } on RefusEncaissement catch (e) {
          if (!peut) {
            resultats.add({'statut': 403});
          } else {
            resultats.add({
              'erreurs': {
                (e.champ ?? ChampEncaissement.montant).propriete: [e.message],
              },
              'succes': null,
              'paiement': null,
              'modale_fermee': false,
            });
          }
        }

      case 'annuler':
        final cible = paiements[op['paiement']! as int];
        try {
          final p = await dao.annuler(
            cible.id,
            op['motif']! as String,
            auteurId: utilisateurs[op['user']]!,
          );
          final ref = pieces.entries
              .firstWhere((e) => e.value.id == p.pieceId)
              .key;
          resultats.add({
            'ok': true,
            'paiement': await decrire(p),
            'reste_du': await resteDu(ref),
          });
        } on RefusEncaissement catch (e) {
          resultats.add({
            'refus': 'RefusEncaissement',
            'message': normaliserLibelle(e.message),
          });
        }

      case 'renommer_facture':
        final ref = op['facture']! as String;
        final nouveau = 'F-${op['numero']}';
        await db.customStatement(
          'UPDATE pieces_facturation_local SET numero = ? WHERE id = ?',
          [nouveau, pieces[ref]!.id],
        );
        numeros[nouveau] = 'FACT:${(op['numero']! as String).toLowerCase()}';
        resultats.add({'ok': true});

      case 'catalogue_bar':
        await semerBoisson(db, prix: int.parse(op['prix']! as String));
        boissonSemee = true;
        resultats.add({'ok': true});

      case 'vente_pos':
        expect(boissonSemee, isTrue);
        final paniersDao = PanierDao(
          db,
          maintenant: () => maintenant,
          // Depuis le lot 6 la vente passe SA pièce (journal VTE) dans la même
          // transaction que la clôture.
          moteur: () async => moteurSur(db, maintenant: () => maintenant),
        );
        panierDuComptoir ??= (await paniersDao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Comptoir',
        )).id;
        await paniersDao.ajouterLigne(
          panierDuComptoir,
          const ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m5Bar,
              code: 'bsn-33',
            ),
            libelle: 'Béninoise 33cl',
            prix: 1000,
          ),
        );
        try {
          final panier = await paniersDao.cloturer(
            panierDuComptoir,
            modePaiement: op['mode']! as String,
            auteurId: caissierEssai,
          );
          panierDuComptoir = null;
          final points = await pointsDesSessions();
          resultats.add({
            'toast_type': 'success',
            'toast': null,
            'vente_creee': true,
            'session_point': points[panier.sessionEncaissementId],
            'session_renseignee': panier.sessionEncaissementId != null,
            'montant': chaineDepuisCentimes((panier.montantCloture ?? 0) * 100),
            'mode': panier.modePaiement,
          });
        } on RefusCaisse catch (e) {
          resultats.add({
            'toast_type': 'error',
            'toast': e.message,
            'vente_creee': false,
            'session_point': null,
            'session_renseignee': false,
            'montant': null,
            'mode': null,
          });
        }

      case 'theorique_propose':
        final session = await SessionsCaisseDao(
          db,
        ).sessionOuverte(pointDeCaisseDuComptoir);
        final paniers = await PanierDao(
          db,
        ).paniers(statut: StatutPanier.cloture);
        resultats.add({
          'propose': chaineDepuisCentimes(
            theoriqueCentimes(
              fondCentimes: session!.fondCentimes,
              especesCentimes: especesEncaisseesCentimes(paniers, session.id),
            ),
          ),
        });

      case 'cloturer':
        final sessions = SessionsCaisseDao(db, maintenant: () => maintenant);
        final session = await sessions.sessionOuverte(pointDeCaisseDuComptoir);
        final paniers = await PanierDao(
          db,
        ).paniers(statut: StatutPanier.cloture);
        final cloture = await sessions.cloturer(
          point: pointDeCaisseDuComptoir,
          constateSaisi: op['constate']! as String,
          peutEcrire: true,
          especesEncaisseesCentimes: especesEncaisseesCentimes(
            paniers,
            session!.id,
          ),
        );
        resultats.add({
          'erreurs': <String, Object?>{},
          'succes': messageCloture(
            cloture.session.point,
            cloture.ecartCentimes,
          ),
          'theorique': chaineDepuisCentimes(cloture.session.theoriqueCentimes!),
          'constate': chaineDepuisCentimes(cloture.session.constateCentimes!),
        });

      case 'etat':
        final tous = await dao.paiements();
        final ordre = [...tous]..sort((a, b) => a.id.compareTo(b.id));
        resultats.add({
          'paiements': [
            for (final p in paiements)
              await decrire(await dao.parId(p.id) ?? p),
          ],
          'ecritures': [
            for (final e in await ecritures())
              {...e, 'libelle': normaliserLibelle(e['libelle']! as String)},
          ],
          'nb_paiements': ordre.length,
          'nb_ecritures': (await ecritures()).length,
        });

      case 'soldes':
        final lignes = await registre();
        final filtrees = op['etat'] == 'debiteur'
            ? filtrerRegistre(lignes, etat: EtatCreance.debiteur)
            : lignes;
        final creancesDuPoste = await creances();
        final t = totauxCreances(creancesDuPoste);
        resultats.add({
          'registre': [
            for (final l in filtrees)
              {
                'nom': l.client.nomComplet,
                'solde': chaineDepuisCentimes(l.soldeCentimes),
                'pieces': l.nbPieces,
                'anciennete': l.ancienneteJours(maintenant),
              },
          ],
          'totaux': {
            'total_du': chaineDepuisCentimes(t.totalDuCentimes),
            'nb_pieces': t.nbPieces,
            'nb_clients': t.nbClients,
          },
          'encaisse_30j': chaineDepuisCentimes(
            encaisseDepuisCentimes(
              await dao.paiements(),
              ilYa30Jours(maintenant),
            ),
          ),
          'resteDu': {for (final ref in pieces.keys) ref: await resteDu(ref)},
        });

      case 'kpis':
        final local = TableauDeBordLocal(
          unites: () async => [],
          reservations: () async => [],
          employes: () async => [],
          stock: () async => const StockInjoignable(),
          pieces: factures.pieces,
          creances: creances,
          paiements: dao.paiements,
          sessions: SessionsCaisseDao(db).sessions,
          peutLire: () => true,
          maintenant: () => maintenant,
        );
        final recu = await local.consulter(
          SelectionPeriode(
            PeriodeTableauDeBord.parCode(op['periode']! as String)!,
          ),
        );
        final tableau = (recu as TableauDeBordRecu).tableau;
        IndicateurTableauDeBord ind(String cle) =>
            tableau.indicateurs.firstWhere((x) => x.cle == cle);
        Map<String, Object?> k(String cle) => {
          'valeur': ind(cle).valeur,
          'precedent': ind(cle).precedent,
          'variation_pct': ind(cle).variationPct,
          'unite': ind(cle).unite.code,
        };
        resultats.add({
          'kpis': {
            'chiffre_affaires_encaisse': k('chiffre_affaires_encaisse'),
            'tresorerie_caisse': k('tresorerie_caisse'),
            'factures_impayees': k('factures_impayees'),
          },
        });

      case 'dette_agee':
        final repertoire = {
          for (final c in await ClientDao(db).clients())
            c.id: (nom: c.nom, prenom: c.prenom),
        };
        final toutes = await creances();
        final globale = detteAgeeParClient(toutes, repertoire, maintenant);
        final affichee = op['terme'] == null
            ? globale
            : detteAgeeParClient(
                toutes,
                repertoire,
                maintenant,
                terme: op['terme']! as String,
              );
        resultats.add({
          'dette_agee': [
            for (final l in affichee)
              {
                'nom': l.nom,
                'tranches': {
                  for (final t in TrancheAge.values)
                    t.code: chaineDepuisCentimes(l.tranchesCentimes[t]!),
                },
                'total': chaineDepuisCentimes(l.totalCentimes),
              },
          ],
          'kpi_douteux': chaineDepuisCentimes(
            totalDeLaTranche(globale, TrancheAge.plus90),
          ),
          'kpi_recent': chaineDepuisCentimes(
            totalDeLaTranche(globale, TrancheAge.jusqua30),
          ),
          'tranches': [for (final t in TrancheAge.values) t.code],
        });

      case 'anciennete_accueil':
        resultats.add({
          'anciennete': [
            for (final t in creancesParAnciennete(await creances(), maintenant))
              {
                'cle': t.cle,
                'montant': chaineDepuisCentimes(t.montantCentimes),
                'pieces': t.pieces,
              },
          ],
        });

      case 'etat_creances':
        final lignes = await registre();
        final a = apercuCreancesClients(
          lignes,
          totaux: totauxCreances(await creances()),
          maintenant: maintenant,
        );
        resultats.add({
          'libelle': a.titre,
          'module': a.moduleSource,
          'kpis': {for (final i in a.indicateurs) i.libelle: i.valeur},
          'entetes': a.entetes,
          'lignes': a.lignes,
        });

      case 'ouvrir_recouvrement':
        final impayees = facturesImpayeesDuClient(
          await creances(),
          clients[op['client']]!,
        );
        resultats.add({
          'ouverture': true,
          'erreurs': impayees.isEmpty
              ? {
                  'recouvrementClientId': [MessagesEncaissement.aucuneCreance],
                }
              : <String, Object?>{},
          'modale_ouverte': impayees.isNotEmpty,
          'factures': [
            for (final c in impayees)
              {
                'facture': pieces.entries
                    .firstWhere((e) => e.value.id == c.piece.id)
                    .key,
                'libelle_renseigne': libelleDeLaFacture(c.piece).isNotEmpty,
                'reste': chaineDepuisCentimes(c.resteDuCentimes),
              },
          ],
          'facture_selectionnee': impayees.isEmpty
              ? null
              : pieces.entries
                    .firstWhere((e) => e.value.id == impayees.first.piece.id)
                    .key,
          'montant': impayees.isEmpty
              ? ''
              : chaineDepuisCentimes(impayees.first.resteDuCentimes),
          'mode': 'especes',
        });

      case 'droits_recouvrement':
        final n =
            ((serveur[i] as Map<String, dynamic>)['niveaux']
                    as Map<String, dynamic>)
                .cast<String, String>();
        final garde = GardeAcces.depuisJson(n);
        final peut = peutEncaisserUneFacture(garde);
        resultats.add({
          'statut': peut ? 200 : 403,
          'module_refuse': peut
              ? null
              : (garde.peutEcrire(ModuleTatacora.m3Crm) ? 'M2' : 'M3'),
          'niveaux': n,
        });

      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }

  return resultats;
}

const _particulier = TypeClientReferentiel.particulier;

/// Le journal où le serveur passe la pièce d'une vente.
const String _journalDesVentes = 'VTE';

// ------------------------------------------------------------- normalisation

String _canon(Object? v) {
  if (v is Map) {
    final cles = v.keys.map((k) => '$k').toList()..sort();
    return '{${cles.map((k) => '$k:${_canon(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_canon).join(',')}]';
  return '$v';
}

/// L'insécable U+00A0 du serveur devient l'espace ordinaire du poste.
String _texte(String t) => t.replaceAll(String.fromCharCode(0x00A0), ' ');

final RegExp _uuid = RegExp(
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
);
final RegExp _numeroServeur = RegExp(r'MECEF-DEMO-([A-Z0-9]+)');

String _sansIdentite(String t) => _texte(t)
    .replaceAllMapped(
      _numeroServeur,
      (m) => 'FACT:${m.group(1)!.toLowerCase()}',
    )
    .replaceAll(_uuid, '<id>');

const _ordreDesChamps = [
  'recouvrementFactureId',
  'recouvrementMontant',
  'recouvrementMode',
];

/// Ce que le serveur rend, ramené à la forme comparée.
Map<String, Object?> _normaliserServeur(Map<String, dynamic> r) {
  if (r.containsKey('libelles')) return {'libelles': 'rien'};
  if (r.containsKey('refus')) {
    return r['refus'] == 'ValueError'
        ? {'refus': 'mal_forme'}
        : {'refus': 'refus', 'message': _sansIdentite('${r['message']}')};
  }
  if (r['statut'] == 403 || r.containsKey('module_refuse')) {
    if (r.containsKey('niveaux')) {
      return {
        'statut': r['statut'],
        'module_refuse': r['module_refuse'],
        'niveaux': r['niveaux'],
      };
    }
    return {'statut': 403};
  }
  if (r.containsKey('erreurs') && r.containsKey('paiement')) {
    // `recouvrer` : la PREMIÈRE erreur du serveur, dans l'ordre pièce, montant,
    // mode — le poste n'en rend qu'une.
    final erreurs = r['erreurs'];
    Map<String, Object?> premiere = const {};
    if (erreurs is Map && erreurs.isNotEmpty) {
      for (final champ in _ordreDesChamps) {
        if (erreurs.containsKey(champ)) {
          // Plusieurs règles peuvent échouer sur le MÊME champ (« abc » n'est ni
          // un nombre ni supérieur à zéro) : seul le premier message se compare.
          premiere = {
            champ: [_sansIdentite('${(erreurs[champ] as List).first}')],
          };
          break;
        }
      }
    }
    return {
      'erreurs': premiere,
      'succes': r['succes'] == null ? null : _sansIdentite('${r['succes']}'),
      'paiement': r['paiement'],
      // « fermée » n'a de sens que pour un succès : un refus du service depuis une
      // modale jamais ouverte (aucune créance) la laisse fermée, sans rien dire.
      'modale_fermee': r['succes'] == null ? null : r['modale_fermee'],
    };
  }
  if (r.containsKey('ecritures')) {
    // ⚠ Le serveur passe AUSSI la pièce de chaque VENTE du comptoir (journal
    // `VTE`, `VenteService::enregistrer`) ; le poste la passe depuis le lot 6.
    // Ces lignes sont écartées de la comparaison DES DEUX CÔTÉS (voir
    // `ecritures()`) — elles ont leur propre confrontation — et le premier test
    // vérifie qu'elles existent bien au serveur, pour que le filtre reste
    // VISIBLE au lieu d'être silencieux.
    final sansVentes = [
      for (final e in (r['ecritures'] as List).cast<Map<String, dynamic>>())
        if (e['journal'] != _journalDesVentes)
          {...e, 'libelle': _sansIdentite('${e['libelle']}')},
    ];
    return {
      'paiements': r['paiements'],
      'ecritures': _ecrituresCanoniques(sansVentes),
      'nb_paiements': r['nb_paiements'],
      'nb_ecritures': sansVentes.length,
    };
  }
  if (r.containsKey('ouverture')) {
    return {
      ...r,
      // Un tableau PHP vide (`[]`) et un objet vide sont la même absence d'erreur.
      'erreurs': r['erreurs'] is List ? <String, Object?>{} : r['erreurs'],
    };
  }
  if (r.containsKey('toast_type')) {
    final succes = r['toast_type'] == 'success';
    return {...r, 'toast': succes ? null : _texte('${r['toast']}')};
  }
  if (r.containsKey('registre')) {
    return {
      'registre': [
        for (final l in (r['registre'] as List).cast<Map<String, dynamic>>())
          {...l, 'nom': _texte('${l['nom']}')},
      ],
      'totaux': r['totaux'],
      'encaisse_30j': r['encaisse_30j'],
      'resteDu': r['resteDu'],
    };
  }
  if (r.containsKey('succes') && r.containsKey('erreurs')) {
    return {
      'erreurs': r['erreurs'] is List ? <String, Object?>{} : r['erreurs'],
      'succes': r['succes'] == null ? null : _texte('${r['succes']}'),
      'theorique': r['theorique'],
      'constate': r['constate'],
    };
  }
  if (r.containsKey('kpis') &&
      r['kpis'] is Map &&
      (r['kpis'] as Map).containsKey('chiffre_affaires_encaisse')) {
    return {'kpis': r['kpis']};
  }
  if (r.containsKey('lignes') && r.containsKey('entetes')) {
    return {
      'libelle': r['libelle'],
      'module': r['module'],
      'kpis': r['kpis'],
      'entetes': r['entetes'],
      'lignes': r['lignes'],
    };
  }
  if (r.containsKey('paiement')) {
    return {
      'ok': r['ok'],
      'paiement': r['paiement'],
      'reste_du': r['reste_du'],
    };
  }
  return Map<String, Object?>.from(r);
}

Map<String, Object?> _normaliserLocal(Map<String, Object?> r) {
  if (r.containsKey('libelles')) return {'libelles': 'rien'};
  if (r.containsKey('refus')) {
    final message = '${r['message']}';
    return message == MessagesEncaissement.malForme
        ? {'refus': 'mal_forme'}
        : {'refus': 'refus', 'message': _sansIdentite(message)};
  }
  if (r.containsKey('erreurs') && r.containsKey('paiement')) {
    final erreurs = r['erreurs'];
    if (erreurs is Map && erreurs.isNotEmpty) {
      final messages = (erreurs['recouvrementMontant'] as List?)
          ?.cast<String>();
      if (messages != null &&
          messages.single == MessagesEncaissement.malForme) {
        return {'refus': 'mal_forme'};
      }
    }
    return {
      'erreurs': erreurs,
      'succes': r['succes'],
      'paiement': r['paiement'],
      'modale_fermee': r['succes'] == null ? null : r['modale_fermee'],
    };
  }
  if (r.containsKey('ecritures')) {
    return {
      'paiements': r['paiements'],
      'ecritures': _ecrituresCanoniques([
        for (final e in (r['ecritures'] as List).cast<Map<String, Object?>>())
          {...e, 'libelle': _sansIdentite('${e['libelle']}')},
      ]),
      'nb_paiements': r['nb_paiements'],
      'nb_ecritures': r['nb_ecritures'],
    };
  }
  return r;
}

/// La PREMIÈRE différence entre deux résultats, avec son chemin : un dump complet
/// de deux listes de vingt lignes comptables ne dit pas laquelle diffère.
String _difference(Object? serveur, Object? poste, [String chemin = '']) {
  if (serveur is Map && poste is Map) {
    final cles = {...serveur.keys, ...poste.keys}.map((k) => '$k').toList()
      ..sort();
    for (final k in cles) {
      final d = _difference(serveur[k], poste[k], '$chemin/$k');
      if (d.isNotEmpty) return d;
    }
    return '';
  }
  if (serveur is List && poste is List) {
    if (serveur.length != poste.length) {
      return '$chemin : ${serveur.length} élément(s) au serveur, ${poste.length} au poste';
    }
    for (var i = 0; i < serveur.length; i++) {
      final d = _difference(serveur[i], poste[i], '$chemin[$i]');
      if (d.isNotEmpty) return d;
    }
    return '';
  }
  return _canon(serveur) == _canon(poste)
      ? ''
      : '$chemin : serveur=${_canon(serveur)} poste=${_canon(poste)}';
}

/// Un tri sur une CLE TEXTE comparée octet à octet : le serveur ne fixe aucun
/// ordre entre deux lignes d'une même pièce.
List<Map<String, Object?>> _ecrituresCanoniques(List<Map<String, Object?>> l) {
  String cle(Map<String, Object?> e) => [
    e['contrepasse'],
    e['numero_piece'] ?? '',
    e['compte'],
    e['debit'],
    e['credit'],
    e['libelle'],
  ].join('|');
  return [
    for (final e in l)
      {
        'journal': e['journal'],
        'compte': e['compte'],
        'centre': e['centre'],
        'libelle': e['libelle'],
        'debit': e['debit'],
        'credit': e['credit'],
        'statut': e['statut'],
        'numero_piece_renseigne': e['numero_piece_renseigne'],
        'numero_piece': e['numero_piece'],
        'date': e['date'],
        'contrepasse': e['contrepasse'],
      },
  ]..sort((a, b) => cle(a).compareTo(cle(b)));
}
