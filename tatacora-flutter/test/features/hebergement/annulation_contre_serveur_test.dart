@Timeout(Duration(minutes: 4))
library;

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart'
    show formaterDateIso;
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';
import 'package:tatacora_flutter/features/hebergement/data/pieces_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/annulation_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/annuler_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/creer_reservation.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// LE MÊME scénario d'acomptes et d'annulations, joué par les VRAIS composants du
/// serveur — `ReservationService::creer` (la pièce de l'acompte) et le composant
/// `Hebergement\Reservations` qui appelle `AnnulationReservationService` (la
/// commission sur le montant GLOBAL, le remboursement borné par l'acompte, la
/// pièce du remboursement) — sur MySQL, et par `ReservationDao` sur le moteur
/// comptable local, comparé CHAMP À CHAMP : l'ouverture de la modale (taux,
/// remboursement suggéré, délai), chaque refus (sa PHRASE et son CHAMP), chaque
/// montant fixé, chaque ligne de chaque pièce.
///
/// `tool/hebergement/rejouer_annulations.php` travaille sur `tatacora_test` (il
/// refuse toute autre base), sème le référentiel par le vrai seeder, puis ANNULE
/// tout. MySQL injoignable : le test ÉCHOUE, il ne saute pas.
///
/// ## Ce que cette confrontation NE compare PAS
///
/// * **Le droit `ANNULATIONS`** : le serveur exige M1 ET `ANNULATIONS` (17e module
///   RBAC, du 01/09/2026) ; le poste n'a que seize modules et exige M1. Le
///   script joue un rôle qui a les deux. Écart nommé au ticket du lot 6.
/// * **Le remboursement d'un acompte « à crédit »** : voir le scénario — le
///   serveur l'accepte (et débite `4191`, jamais crédité), le poste fait pareil.
const _parc = <String, Object?>{
  'categories': [
    {
      'id': '00000000-0000-4000-8000-0000000000c1',
      'libelle': 'Bungalow',
      'tarif': '20000',
    },
  ],
  'unites': [
    {
      'ref': 'u1',
      'id': '00000000-0000-4000-8000-0000000000d1',
      'categorie': '00000000-0000-4000-8000-0000000000c1',
      'numero': 'BG-01',
    },
    {
      'ref': 'u2',
      'id': '00000000-0000-4000-8000-0000000000d2',
      'categorie': '00000000-0000-4000-8000-0000000000c1',
      'numero': 'BG-02',
    },
    {
      'ref': 'u3',
      'id': '00000000-0000-4000-8000-0000000000d3',
      'categorie': '00000000-0000-4000-8000-0000000000c1',
      'numero': 'BG-03',
    },
  ],
  'clients': [
    {
      'ref': 'c1',
      'id': '00000000-0000-4000-8000-0000000000e1',
      'nom': 'ALLALE',
      'prenom': 'Rodrigue',
    },
    {
      'ref': 'c2',
      'id': '00000000-0000-4000-8000-0000000000e2',
      'nom': 'KORA',
      'prenom': null,
    },
    {
      'ref': 'c3',
      'id': '00000000-0000-4000-8000-0000000000e3',
      'nom': 'DOSSOU',
      'prenom': 'Marie',
    },
  ],
};

Map<String, Object?> _reserver(
  String ref,
  String unite,
  String arrivee,
  String depart,
  String acompte,
  String? mode, {
  String client = 'c1',
  String remiseType = 'aucune',
  String remiseValeur = '0',
}) => {
  'op': 'reserver',
  'ref': ref,
  'client': client,
  'unite': unite,
  'arrivee': arrivee,
  'depart': depart,
  'acompte': acompte,
  'mode': mode,
  'remise_type': remiseType,
  'remise_valeur': remiseValeur,
};

Map<String, Object?> _annuler(
  String ref,
  String? taux, {
  String mode = 'pourcentage',
  String valeur = '0',
  bool directe = false,
}) => {
  'op': 'annuler',
  'ref': ref,
  'directe': directe,
  'taux': taux,
  'mode': mode,
  'valeur': valeur,
};

Map<String, Object?> _parametre(String cle, String? valeur) => {
  'op': 'parametre',
  'cle': cle,
  'valeur': valeur,
};

const _cleTaux = 'hebergement_taux_annulation_moins_24h';

final _scenario = <Map<String, Object?>>[
  {'op': 'libelles'},

  // --- L'acompte reçu produit sa pièce : où va l'argent ---------------------
  _reserver('r1', 'u1', '2031-07-10', '2031-07-12', '5000', 'mobile_money'),
  _reserver(
    'r2',
    'u2',
    '2031-07-10',
    '2031-07-12',
    '10000',
    'especes',
    client: 'c2',
  ),
  _reserver(
    'r3',
    'u3',
    '2031-07-10',
    '2031-07-12',
    '8000',
    'virement',
    client: 'c3',
  ),
  _reserver('r4', 'u1', '2031-08-01', '2031-08-03', '3000', 'cheque'),
  // Trois cas SANS pièce : à crédit (promis, pas reçu), mode absent
  // (trésorerie inconnaissable), acompte nul.
  _reserver(
    'r5',
    'u2',
    '2031-08-01',
    '2031-08-03',
    '10000',
    'credit',
    client: 'c2',
  ),
  _reserver('r6', 'u3', '2031-08-01', '2031-08-03', '4000', null, client: 'c3'),
  _reserver('r7', 'u1', '2031-09-01', '2031-09-03', '0', 'especes'),
  // Une remise : 10 % de 40 000 F -> total 36 000 F.
  _reserver(
    'r8',
    'u2',
    '2031-09-01',
    '2031-09-03',
    '6000',
    'especes',
    remiseType: 'pourcentage',
    remiseValeur: '10',
    client: 'c2',
  ),
  // Une arrivée lointaine : le délai dépasse mille heures (virgule de milliers).
  _reserver(
    'r9',
    'u3',
    '2031-09-01',
    '2031-09-03',
    '2000',
    'mobile_money',
    client: 'c3',
  ),
  // Une réservation d'avant le tarif figé : son montant total est INCONNU.
  _reserver('r10', 'u1', '2031-10-01', '2031-10-03', '1000', 'especes'),
  {'op': 'effacer_tarif', 'ref': 'r10'},
  {'op': 'compter'},

  // --- Le refus d'une pièce n'écrit RIEN : pas d'exercice -------------------
  {'op': 'horloge', 'date': '2035-01-02'},
  _reserver('rx', 'u1', '2035-02-01', '2035-02-03', '1000', 'especes'),
  {'op': 'horloge', 'date': '2031-06-15'},
  {'op': 'compter'},

  // --- L'ouverture de la modale : taux, remboursement suggéré, délai --------
  // Sans montant total fiable, la modale ne s'ouvre PAS : une bannière de page.
  _annuler('r10', null),
  // Taux de référence (50 %) : la commission (20 000) dépasse l'acompte (5 000),
  // donc rien à suggérer.
  _annuler('r1', null),
  _parametre(_cleTaux, '10'),
  // 10 % de 40 000 = 4 000 ; il reste 6 000 sur 10 000 : 60 %.
  _annuler('r2', null),
  _annuler('r9', null),
  // Un paramètre vide retombe sur 50 (le repli du serveur).
  _parametre(_cleTaux, null),
  _annuler('r3', null),

  // --- La validation Livewire, champ par champ ------------------------------
  _annuler('r4', '', mode: '', valeur: ''),
  _annuler('r4', 'abc', mode: 'xx', valeur: '-5'),
  _annuler('r4', '120', valeur: '10'),
  _annuler('r4', '-1', valeur: '10'),
  // Les refus du SERVICE, rattachés au champ du remboursement.
  _annuler('r4', '50', mode: 'montant', valeur: '3001'),
  _annuler('r4', '50', valeur: '100.01'),
  {'op': 'compter'},

  // --- Annulations réussies : commission, remboursement, pièce --------------
  // r1 : 50 % de 40 000 = 20 000 de commission ; 60 % de 5 000 = 3 000 rendus.
  _annuler('r1', '50', valeur: '60'),
  // r2 : 10 % -> 4 000 de commission ; 60 % de 10 000 = 6 000 rendus.
  _annuler('r2', '10', valeur: '60.00'),
  // r3 : taux nul, tout l'acompte (8 000 F) rendu en FCFA.
  _annuler('r3', '0', mode: 'montant', valeur: '8000'),
  // r4 : un taux à trois décimales (tronqué à 33.33) et un pourcentage à quatre.
  _annuler('r4', '33.333', valeur: '33.3333'),
  // r5 : acompte « à crédit » — jamais encaissé, mais le serveur rembourse quand
  // même et débite 4191, qui n'a jamais été crédité (défaut du serveur, répliqué).
  _annuler('r5', '20', mode: 'montant', valeur: '5000'),
  // r6 : acompte sans mode, aucun remboursement.
  _annuler('r6', '100', mode: 'montant', valeur: '0'),
  // r7 : aucun acompte.
  _annuler('r7', '50', mode: 'montant', valeur: '0'),
  // r8 : le total est NET de remise (36 000), la commission aussi : 50 % = 18 000.
  _annuler('r8', '50', valeur: '50'),
  // Une seconde annulation est refusée, dans la bannière de la page.
  // (Rouvrir la modale d'une réservation annulée est une réponse 422 du
  // serveur — `abort_if` : l'écran n'offre pas le geste, le poste non plus.)
  _annuler('r1', '50', directe: true),
  {'op': 'compter'},
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final r = await executerPhp(
      'rejouer_annulations.php',
      dossier: 'hebergement',
      entree: {'aujourdhui': '2031-06-15', 'parc': _parc, 'ops': _scenario},
    );
    serveur = r['resultats'] as List<dynamic>;
    local = await _jouerLocalement(_scenario);
  });

  test('chaque opération du scénario a un résultat des deux côtés', () {
    expect(serveur, hasLength(_scenario.length));
    expect(local, hasLength(_scenario.length));
  });

  test('chaque résultat est identique au serveur, opération par opération', () {
    for (var i = 0; i < _scenario.length; i++) {
      if (_scenario[i]['op'] == 'libelles') continue;
      expect(
        local[i],
        equals(serveur[i]),
        reason: 'opération $i : ${_scenario[i]}',
      );
    }
  });

  test('le scénario éprouve les chemins qui comptent (pas un vert à vide)', () {
    final pieces = <String>{
      for (final r in serveur)
        for (final l in ((r as Map)['piece'] as List? ?? const []))
          '${(l as Map)['journal']}/${l['compte']}',
    };
    // Les trois trésoreries d'acompte, 4191, et la caisse du remboursement.
    expect(
      pieces,
      containsAll(<String>[
        'BQ/552',
        'CAI/5711',
        'BQ/5211',
        'BQ/4191',
        'CAI/4191',
      ]),
    );
    // Des succès ET des refus, de plusieurs causes.
    final refus = serveur
        .where((r) => (r as Map).containsKey('refus'))
        .toList();
    expect(refus, hasLength(1), reason: 'le seul refus de pièce : exercice');
    final erreurs = serveur
        .where((r) => (r as Map).containsKey('erreurs'))
        .toList();
    expect(erreurs.length, greaterThanOrEqualTo(7));
    final annulees = serveur.where((r) => (r as Map)['statut'] == 'annulee');
    expect(annulees, hasLength(8));
    // Trois acomptes sans pièce (crédit, sans mode, nul), un seul remboursement
    // sans acompte encaissé (crédit).
    // La bannière de page du montant total inconnu, elle aussi, est éprouvée.
    expect(
      serveur.where((r) => (r as Map).containsKey('banniere')),
      hasLength(1),
    );
    final creations = serveur
        .where((r) => (r as Map<String, dynamic>).containsKey('acompte'))
        .cast<Map<String, dynamic>>();
    expect(creations.where((r) => (r['piece'] as List).isEmpty), hasLength(3));
  });

  test('un refus de pièce n’écrit RIEN : la réservation n’existe pas', () {
    final comptes = [
      for (final r in serveur)
        if ((r as Map).containsKey('compte')) r['compte'] as Map,
    ];
    // Neuf réservations (6 pièces d'acompte), puis une dixième avec sa pièce,
    // puis le refus de `rx` (exercice 2035 absent) : si le refus avait écrit, on
    // lirait 11 réservations.
    expect(comptes[0], {'reservations': 10, 'ecritures': 14});
    expect(comptes[1], {'reservations': 10, 'ecritures': 14});
    // Les refus de validation et de service n'ont rien écrit non plus.
    expect(comptes[2], {'reservations': 10, 'ecritures': 14});
    // Six remboursements (r1, r2, r3, r4, r5, r8) à deux lignes chacun ; r6 et r7
    // n'en ont aucun.
    expect(comptes[3], {'reservations': 10, 'ecritures': 26});
  });

  test('les phrases et les tables sont celles du serveur, lues par PHP', () {
    final l = (serveur.first as Map)['libelles'] as Map<dynamic, dynamic>;
    expect(l['annulation_impossible'], MessagesAnnulation.dejaAnnulee);
    expect(l['montant_total_inconnu'], MessagesAnnulation.montantTotalInconnu);
    expect(l['taux_invalide'], MessagesAnnulation.tauxInvalide);
    expect(l['remboursement_negatif'], MessagesAnnulation.remboursementNegatif);
    expect(l['mode_inconnu'], MessagesAnnulation.modeInconnu(':mode'));
    expect(
      l['superieur_acompte'],
      MessagesAnnulation.remboursementSuperieurAcompte,
    );
    expect(
      l['libelle_ecriture'],
      MessagesAnnulation.libelleDeLaPiece(':client'),
    );
    expect(l['delai'], MessagesAnnulation.delai(':heures'));
    expect(l['delai_passe'], MessagesAnnulation.delaiPasse);
    expect(l['sous_seuil'], MessagesAnnulation.sousSeuil);
    expect(l['titre'], MessagesAnnulation.titre);
    expect(
      l['element'],
      MessagesAnnulation.element(':client', ':arrivee', ':depart'),
    );
    expect(l['montant_total'], MessagesAnnulation.montantTotal);
    expect(l['acompte_verse'], MessagesAnnulation.acompteVerse);
    expect(l['champ_taux'], MessagesAnnulation.champTaux);
    expect(l['taux_aide'], MessagesAnnulation.tauxAide);
    expect(l['champ_remboursement'], MessagesAnnulation.champRemboursement);
    expect(l['mode_pourcentage'], MessagesAnnulation.modePourcentage);
    expect(l['mode_montant'], MessagesAnnulation.modeMontant);
    expect(l['remboursement_aide'], MessagesAnnulation.remboursementAide);
    expect(l['aucun_acompte'], MessagesAnnulation.aucunAcompte);
    // Le rappel porte un <strong> autour de « conservée » : le poste le rend en
    // gras, et les trois morceaux rejoignent la chaîne du serveur.
    expect(
      l['rappel'],
      '${MessagesAnnulation.rappelAvant}<strong>'
      '${MessagesAnnulation.rappelGras}</strong>'
      '${MessagesAnnulation.rappelApres}',
    );
    expect(l['confirmer'], MessagesAnnulation.confirmer);
    expect(l['renoncer'], MessagesAnnulation.renoncer);
    expect(
      l['validation_required'],
      MessagesAnnulation.obligatoire(':attribute'),
    );
    expect(l['validation_numeric'], MessagesAnnulation.nombre(':attribute'));
    expect(l['validation_in'], MessagesAnnulation.invalide(':attribute'));
    expect(
      l['validation_min'],
      MessagesAnnulation.minimum(':attribute', ':min'),
    );
    expect(
      l['validation_max'],
      MessagesAnnulation.maximum(':attribute', ':max'),
    );
    expect(l['seuil_heures'], ReglesAnnulation.seuilHeures);
    expect(l['taux_reference'], ReglesAnnulation.tauxReference);
    expect(
      l['cle_taux'],
      _cleTaux,
      reason: 'la clé lue par le poste est celle du serveur',
    );
    expect(l['compte_avances'], '4191');
    // Les tables de trésorerie : l'acompte entre là où le serveur le met.
    final tresorerieParMode = (l['tresorerie_acompte'] as Map)
        .cast<String, String>();
    final tresoreries = (l['tresoreries'] as Map)
        .cast<String, Map<String, dynamic>>();
    expect(tresorerieParMode.length, 4);
    const modes = {
      'especes': ModePaiementReservation.especes,
      'mobile_money': ModePaiementReservation.mobileMoney,
      'virement': ModePaiementReservation.virement,
      'cheque': ModePaiementReservation.cheque,
    };
    for (final e in tresorerieParMode.entries) {
      final t = tresorerieDeLAcompte(modes[e.key]);
      expect(t, isNotNull, reason: e.key);
      expect(t!.compte, tresoreries[e.value]!['compte'], reason: e.key);
      expect(t.journal, tresoreries[e.value]!['journal'], reason: e.key);
    }
    expect(tresorerieDeLAcompte(ModePaiementReservation.credit), isNull);
    expect(tresorerieDeLAcompte(null), isNull);
    // Non vide : sinon l'égalité ci-dessus comparerait des vides.
    expect(l['titre'], isNotEmpty);
  });
}

/// Joue le scénario avec `ReservationDao` sur le moteur local, dans le format de
/// sortie du script PHP.
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> scenario,
) async {
  var maintenant = DateTime(2031, 6, 15, 10);
  DateTime horloge() => maintenant;

  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  await baseInstalleeSur(db, DateTime(2031, 6, 15));

  // Le parc et les clients — les MÊMES identifiants que le serveur.
  final categories = (_parc['categories']! as List)
      .cast<Map<String, Object?>>();
  for (final c in categories) {
    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: c['id']! as String,
            libelle: c['libelle']! as String,
            capaciteMax: 2,
            tarifBase: double.parse(c['tarif']! as String),
          ),
        );
  }
  final unites = <String, String>{};
  for (final u in (_parc['unites']! as List).cast<Map<String, Object?>>()) {
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: u['id']! as String,
            categorieId: u['categorie']! as String,
            numero: u['numero']! as String,
            statut: 'libre',
          ),
        );
    unites[u['ref']! as String] = u['id']! as String;
  }
  final clients = <String, String>{};
  for (final c in (_parc['clients']! as List).cast<Map<String, Object?>>()) {
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: c['id']! as String,
            nom: c['nom']! as String,
            prenom: Value(c['prenom'] as String?),
            telephone: '97000000',
            typeClient: 'particulier',
          ),
        );
    clients[c['ref']! as String] = c['id']! as String;
  }

  final dao = ReservationDao(
    db,
    maintenant: horloge,
    moteur: () async => moteurSur(db, maintenant: horloge),
  );
  final depot = ReservationRepositoryLocal(dao);
  final compta = ComptabiliteDao(db);
  final parametres = ParametresDao(db);

  final journaux = {for (final j in await compta.journaux()) j.id: j.code};
  final libellesCentre = {
    for (final c in await compta.centres()) c.id: c.libelle,
  };
  final departEcritures = (await compta.toutesLesEcritures()).length;
  final reservations = <String, String>{}; // ref -> identifiant du poste

  String sansIdentifiants(String libelle) {
    var r = libelle;
    for (final e in reservations.entries) {
      r = r.replaceAll(e.value, '<${e.key}>');
    }
    return r;
  }

  Future<Map<String, Object?>> decrireLigne(EcritureComptable e) async {
    final compte = (await compta.compteParId(e.compteId))!;
    return {
      'numero_piece': e.numeroPiece,
      'journal': journaux[e.journalId],
      'date': e.dateEcriture,
      'compte': compte.numero,
      'centre': libellesCentre[e.centreId],
      'libelle': sansIdentifiants(e.libelle),
      'debit': e.debit,
      'credit': e.credit,
      'statut': e.statut.valeur,
    };
  }

  String cle(Map<String, Object?> l) =>
      [l['compte'], l['debit'], l['credit']].join('|');

  Future<List<Map<String, Object?>>> piece(
    Iterable<EcritureComptable> lignes,
  ) async =>
      [for (final e in lignes) await decrireLigne(e)]
        ..sort((a, b) => cle(a).compareTo(cle(b)));

  String tauxTexte(int centiemes) => chaineDepuisCentimes(centiemes);

  ModePaiementReservation? mode(String? code) => switch (code) {
    'especes' => ModePaiementReservation.especes,
    'mobile_money' => ModePaiementReservation.mobileMoney,
    'virement' => ModePaiementReservation.virement,
    'cheque' => ModePaiementReservation.cheque,
    'credit' => ModePaiementReservation.credit,
    _ => null,
  };

  String? codeMode(ModePaiementReservation? m) => switch (m) {
    ModePaiementReservation.especes => 'especes',
    ModePaiementReservation.mobileMoney => 'mobile_money',
    ModePaiementReservation.virement => 'virement',
    ModePaiementReservation.cheque => 'cheque',
    ModePaiementReservation.credit => 'credit',
    null => null,
  };

  DateTime jour(String iso) {
    final p = iso.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  final resultats = <Map<String, Object?>>[];

  for (final op in scenario) {
    switch (op['op']) {
      case 'libelles':
        resultats.add(<String, Object?>{'libelles': true});

      case 'parametre':
        await parametres.ecrire({
          op['cle']! as String: op['valeur'] as String?,
        }, auteurId: null);
        resultats.add({'ok': true});

      case 'horloge':
        final j = jour(op['date']! as String);
        maintenant = DateTime(j.year, j.month, j.day, 10);
        resultats.add({'ok': true});

      case 'reserver':
        final unite = (await depot.unites()).firstWhere(
          (u) => u.id == unites[op['unite']],
        );
        final p = PeriodeSejour(
          arrivee: jour(op['arrivee']! as String),
          depart: jour(op['depart']! as String),
        );
        final remiseType = TypeRemise.values.firstWhere(
          (t) => t.name == op['remise_type'],
        );
        try {
          final creee = await CreerReservation(depot, maintenant: horloge)(
            unite: unite,
            clientId: clients[op['client']]!,
            clientNom: '',
            periode: p,
            acompte: int.parse(op['acompte']! as String),
            modePaiement: mode(op['mode'] as String?),
            remiseType: remiseType,
            remiseValeur: num.parse(op['remise_valeur']! as String),
            lignes: [
              LigneService(
                id: 'l-${op['ref']}',
                service: ServiceReservation.hebergement,
                itemId: unite.id,
                libelle: unite.numero,
                prixUnitaire: unite.tarifBase,
                quantite: p.nuits,
              ),
            ],
            auteurId: auteurEssai,
          );
          reservations[op['ref']! as String] = creee.id;
          resultats.add({
            'ok': true,
            'acompte': chaineDepuisCentimes(creee.acompte * 100),
            'mode': codeMode(creee.modePaiement),
            'piece': await piece(
              await compta.lignesParLibelle(
                MessagesAnnulation.libelleDeLAcompte(creee.id),
              ),
            ),
          });
        } on RefusComptable catch (e) {
          resultats.add({'refus': e.message});
        }

      case 'annuler':
        final id = reservations[op['ref']]!;
        final sortie = <String, Object?>{};

        if (!(op['directe']! as bool)) {
          final r = (await depot.parId(id))!;
          final total = montantTotalCentimes(
            tarifNuit: r.tarifNuit,
            aDesLignes: r.lignes.isNotEmpty,
            totalDuRecapitulatifFrancs: r.recapitulatif.total,
          );
          if (total == null) {
            resultats.add({'banniere': MessagesAnnulation.montantTotalInconnu});
            continue;
          }
          final taux = tauxParDefaut(await parametres.lireTout());
          sortie['ouverture'] = {
            'taux': taux,
            'mode': ModesRemboursement.pourcentage,
            'valeur': pourcentageRembourseSuggere(
              acompteCentimes: r.acompte * 100,
              totalCentimes: total,
              taux: taux,
            ),
            'delai': formaterHeures(
              delaiHeuresAvantArrivee(r.periode.arrivee, maintenant),
            ),
            'sous_seuil': estSousLeSeuil(r.periode.arrivee, maintenant),
          };
        }

        if (op['taux'] == null) {
          resultats.add({...sortie, 'ok': true});
          continue;
        }

        final erreurs = validerSaisieAnnulation(
          taux: op['taux'] as String?,
          mode: op['mode'] as String?,
          valeur: op['valeur'] as String?,
        );
        if (erreurs.isNotEmpty) {
          resultats.add({...sortie, 'erreurs': erreurs});
          continue;
        }

        try {
          final annulee = await AnnulerReservation(depot)(
            id,
            tauxSaisi: op['taux']! as String,
            modeRemboursement: op['mode']! as String,
            valeurRemboursement: op['valeur']! as String,
            auteurId: auteurEssai,
          );
          final a = annulee.annulation!;
          final pieceRemboursement = a.ecritureRemboursementId == null
              ? <Map<String, Object?>>[]
              : await piece(
                  await compta.lignesDeLaPiece(
                    (await compta.ecriture(
                      a.ecritureRemboursementId!,
                    ))!.numeroPiece!,
                  ),
                );
          final d = a.date;
          resultats.add({
            ...sortie,
            'ok': true,
            'statut': 'annulee',
            'taux': tauxTexte(a.tauxCentiemes),
            'total': chaineDepuisCentimes(a.totalCentimes),
            'commission': chaineDepuisCentimes(a.commissionCentimes),
            'rembourse': chaineDepuisCentimes(a.rembourseCentimes),
            'mode_saisie': a.modeSaisie,
            'date_renseignee': true,
            'date': formaterDateIso(d),
            'auteur_renseigne': a.auteurId != null,
            'ecriture_renseignee': a.ecritureRemboursementId != null,
            'piece': pieceRemboursement,
          });
        } on RefusAnnulation catch (e) {
          resultats.add({
            ...sortie,
            'erreurs': {
              e.champ!: [e.message],
            },
          });
        }

      case 'effacer_tarif':
        // Le tarif figé à 0 et aucune ligne : l'état d'une ligne reprise de la
        // v1 — le montant total est INCONNU, pas nul.
        final cible = reservations[op['ref']]!;
        await db.customStatement(
          'UPDATE reservations_local SET tarif_nuit = 0 WHERE id = ?',
          [cible],
        );
        await db.customStatement(
          'DELETE FROM lignes_reservation_local WHERE reservation_id = ?',
          [cible],
        );
        resultats.add({'ok': true});

      case 'compter':
        final r = await db
            .customSelect('SELECT COUNT(*) AS n FROM reservations_local')
            .getSingle();
        resultats.add({
          'ok': true,
          'compte': {
            'reservations': r.data['n'] as int,
            'ecritures':
                (await compta.toutesLesEcritures()).length - departEcritures,
          },
        });

      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}
