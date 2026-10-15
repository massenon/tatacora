@Timeout(Duration(minutes: 2))
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/caisse/data/sessions_caisse_dao.dart';
import 'package:tatacora_flutter/features/caisse/domain/entities/session_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/messages_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/montant_caisse.dart';
import 'package:tatacora_flutter/features/caisse/domain/regles_caisse.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';

import '../comptabilite/support/outils_comptabilite.dart';

/// LE MÊME scénario de caisse, joué par le VRAI composant `PosComptant` du
/// serveur (Livewire, ses règles de validation, son calcul du théorique, ses
/// messages `lang/fr`) sur MySQL, et par `SessionsCaisseDao` sur la base locale,
/// comparé CHAMP À CHAMP : le statut (403 du RBAC), les erreurs de validation
/// (champ ET phrase), le message de succès, les montants stockés, et les trois
/// lectures « session ouverte » du serveur (le POS, l'encaissement de facture,
/// l'indicateur de la barre supérieure).
///
/// `tool/caisse/rejouer_caisse.php` travaille sur `tatacora_test` (il refuse
/// toute autre base), sème les rôles par le vrai seeder, puis ANNULE tout : la
/// base n'est pas modifiée. MySQL injoignable : le test ÉCHOUE, il ne saute pas.
///
/// Le scénario est UN seul JSON lu par les deux moteurs : un scénario recopié à
/// la main des deux côtés ne prouverait rien. Les fixtures de ventes (le serveur
/// les INSÈRE en base) sont rejouées côté poste comme les ESPÈCES de la session
/// que le DAO reçoit — c'est la seule jonction que ce poste n'a pas de table
/// pour porter (voir `especesDeLaSessionProvider`).
///
/// ## Quatre écarts de représentation, normalisés avant la comparaison
///
/// 1. le séparateur de milliers du serveur est l'insécable U+00A0 ; celui du
///    poste, l'espace ordinaire ;
/// 2. un refus que le serveur ne traduit pas (`QueryException`, `ValueError`,
///    HTTP 500) devient, au poste, un refus AVEC phrase — la comparaison porte
///    sur « rien n'est écrit » et sur la classe du refus ;
/// 3. un tableau vide PHP (`[]`) et un objet vide sont la même absence d'erreur ;
/// 4. l'ordre des sessions est celui de CRÉATION, tenu par le scénario.
void main() {
  final aujourdhui = DateTime(2026, 10, 12, 7);

  // ------------------------------------------------------------------ scénario
  Map<String, Object?> ouvrir(String u, String fond) => {
    'op': 'ouvrir',
    'user': u,
    'fond': fond,
  };
  Map<String, Object?> cloturer(String u, String constate) => {
    'op': 'cloturer',
    'user': u,
    'constate': constate,
  };
  Map<String, Object?> vente(
    String mode,
    String statut,
    String montant,
    String point,
  ) => {
    'op': 'semer_vente',
    'mode': mode,
    'statut': statut,
    'montant': montant,
    'point_session': point,
  };

  final scenario = <Map<String, Object?>>[
    {'op': 'libelles'},
    {'op': 'utilisateur', 'ref': 'g', 'role': 'gerant'},
    {'op': 'utilisateur', 'ref': 'c', 'role': 'comptable'},
    {'op': 'utilisateur', 'ref': 'r', 'role': 'receptionniste'},
    {'op': 'utilisateur', 'ref': 'b', 'role': 'barman'},

    // --- Une réception ouverte depuis plus de 24 h : l'indicateur "tardive" ---
    {'op': 'indicateur', 'user': 'g'},
    {
      'op': 'semer_session',
      'user': 'g',
      'point_vente': 'reception',
      'fond': '20000',
      'ouverte': true,
      'il_y_a_minutes': 1500,
    },
    {'op': 'indicateur', 'user': 'g'},
    {'op': 'session_pour_encaissement'},

    // --- RBAC : le 403 précède TOUTE validation -----------------------------
    ouvrir('c', '1000'),
    ouvrir('r', ''),
    cloturer('c', '1000'),

    // --- Validation de FORME du fond ----------------------------------------
    ouvrir('g', ''),
    ouvrir('g', '  '),
    ouvrir('g', ' '),
    ouvrir('g', '\t\n'),
    ouvrir('g', 'abc'),
    ouvrir('g', '-5'),
    ouvrir('g', '-0.001'),
    ouvrir('g', '-.5'),
    ouvrir('g', '5e'),
    ouvrir('g', '1,5'),
    ouvrir('g', '0x1A'),
    ouvrir('g', '1 000'),

    // --- Clôturer sans caisse BAR (une réception est ouverte, ce n'est pas
    //     celle du POS) : la validation passe AVANT ce refus.
    cloturer('g', ''),
    cloturer('g', 'abc'),
    cloturer('g', '1000'),
    cloturer('g', '1.5e3'),

    // --- Ouverture, puis "déjà ouverte" -------------------------------------
    {'op': 'etat'},
    ouvrir('b', ' 1000'),
    ouvrir('g', '10'),
    ouvrir('g', ''),
    {'op': 'etat'},
    {'op': 'indicateur', 'user': 'g'},
    {'op': 'session_pour_encaissement'},

    // --- Théorique : seules les espèces VALIDÉES de la session -------------
    {'op': 'theorique_propose', 'user': 'g'},
    vente('especes', 'validee', '12345.67', 'bar'),
    vente('especes', 'annulee', '400', 'bar'),
    vente('mobile_money', 'validee', '700', 'bar'),
    vente('carte', 'validee', '650', 'bar'),
    vente('note_chambre', 'validee', '900', 'bar'),
    vente('especes', 'validee', '1000', 'reception'),
    {'op': 'theorique_propose', 'user': 'g'},
    {'op': 'tresorerie_caisse'},

    // --- Clôtures refusées : RIEN n'est écrit, la session reste ouverte ----
    cloturer('g', '1.5e3'),
    cloturer('g', ' 13345.67'),
    cloturer('g', '13345.67 '),
    cloturer('g', '99999999999999999'),
    cloturer('g', '-1'),
    {'op': 'etat'},

    // --- Une saisie à trois décimales : écart TRONQUÉ, constaté ARRONDI ----
    cloturer('g', '13345.675'),
    {'op': 'etat'},
    {'op': 'indicateur', 'user': 'g'},
    {'op': 'session_pour_encaissement'},
  ];

  // Une série d'ouvertures et de clôtures qui éprouve l'arrondi du fond, la
  // troncature de l'écart et le format du message — chacune sur une caisse
  // neuve (la précédente est close).
  const fonds = [
    '1e3',
    '+5',
    '5.',
    '.5e1',
    '1E-2',
    '-0',
    '5 ',
    '0.005',
    '0.0049',
    '1.005',
    '12345678.995',
    '1e12',
    '1e13',
    '9999999999999.99',
    '9999999999999.995',
    '00012',
    '1500',
  ];
  const constates = [
    '0',
    '-0',
    '1500.40',
    '1499.60',
    '3234567.89',
    '0.999',
    '1.5',
    '1500',
    '1500.999',
    '.5',
    '5.',
    '+7',
    '100000000',
  ];
  for (var i = 0; i < fonds.length; i++) {
    scenario.add(ouvrir('g', fonds[i]));
    scenario.add(cloturer('g', constates[i % constates.length]));
    // Un second constaté sur la même caisse, quand elle a pu s'ouvrir : le
    // premier la clôt, le second doit donc dire « aucune caisse ».
    if (i % 4 == 0) scenario.add(cloturer('g', '1000'));
  }
  scenario.addAll([
    // --- Plusieurs points, plusieurs ouvertures simultanées ------------------
    ouvrir('g', '10000'),
    {
      'op': 'semer_session',
      'user': 'g',
      'point_vente': 'restaurant',
      'fond': '5000',
      'ouverte': true,
      'il_y_a_minutes': -5,
    },
    {'op': 'session_pour_encaissement'},
    {'op': 'indicateur', 'user': 'g'},
    vente('especes', 'validee', '1000', 'restaurant'),
    vente('especes', 'validee', '2500', 'bar'),
    {'op': 'theorique_propose', 'user': 'g'},
    {'op': 'tresorerie_caisse'},
    cloturer('g', '12000'),
    {'op': 'session_pour_encaissement'},
    {'op': 'tresorerie_caisse'},
    {'op': 'etat'},
  ]);

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_caisse.php',
      dossier: 'caisse',
      entree: {'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _jouerLocalement(scenario, serveur, aujourdhui);
  });

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(scenario.length, greaterThan(100));
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));
    // Le serveur a RÉELLEMENT refusé et RÉELLEMENT accepté : un scénario où tout
    // passerait (ou tout serait refusé) ne comparerait aucune règle.
    final niveaux = {
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['op'] == 'utilisateur')
          scenario[i]['role']: (serveur[i] as Map)['m5'],
    };
    // Les deux moitiés du RBAC sont éprouvées : des rôles qui écrivent sur M5 et
    // des rôles qui n'y écrivent pas (leur droit est LU du serveur).
    expect(niveaux['gerant'], 'C');
    expect(niveaux['barman'], 'C');
    expect(niveaux['comptable'], isNot('C'));
    expect(niveaux['receptionniste'], isNot('C'));
    final issues = [
      for (final r in serveur) _normaliserServeur(r as Map<String, dynamic>),
    ];
    expect(issues.where((i) => i['statut'] == 403), isNotEmpty);
    expect(
      issues.where(
        (i) => (i['succes'] as String?)?.contains('ouverte.') ?? false,
      ),
      isNotEmpty,
    );
    expect(
      issues.where(
        (i) => (i['succes'] as String?)?.contains('clôturée') ?? false,
      ),
      isNotEmpty,
    );
    expect(issues.where((i) => i['refus'] == 'ValueError'), isNotEmpty);
    expect(issues.where((i) => i['refus'] == 'QueryException'), isNotEmpty);
    expect(
      issues.where((i) => (i['erreurs'] as Map?)?.isNotEmpty ?? false),
      isNotEmpty,
    );
  });

  test('chaque opération rend le MÊME résultat des deux côtés', () {
    final ecarts = <String>[];
    for (var i = 0; i < scenario.length; i++) {
      final s = _normaliserServeur(serveur[i] as Map<String, dynamic>);
      final l = _normaliserLocal(local[i]);
      if (_texte(s) != _texte(l)) {
        ecarts.add(
          'op #$i ${scenario[i]}\n  serveur : ${_texte(s)}\n  poste   : ${_texte(l)}',
        );
      }
    }
    expect(ecarts, isEmpty, reason: ecarts.join('\n'));
  });

  test('les libellés de la barre et des modales sont ceux du serveur', () {
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

    expect(lib['point_caisse'], pointDeCaisseDuComptoirCode);
    expect(
      sans(lib['caisse_ouverte'] as String, {':point': 'bar'}),
      MessagesCaisse.caisseOuverte('bar'),
    );
    expect(
      sans(lib['caisse_depuis'] as String, {':heure': '07:00'}),
      MessagesCaisse.depuis('07:00'),
    );
    expect(
      sans(lib['caisse_fond'] as String, {':montant': 'X'}),
      MessagesCaisse.fond('X'),
    );
    expect(lib['caisse_aucune'], MessagesCaisse.aucuneCaisse);
    expect(lib['ouvrir_caisse'], MessagesCaisse.ouvrirLaCaisse);
    expect(lib['cloturer_caisse'], MessagesCaisse.cloturerLaCaisse);
    expect(
      sans(lib['ouverture_titre'] as String, {':point': 'bar'}),
      MessagesCaisse.titreOuverture('bar'),
    );
    expect(lib['ouverture_fond'], MessagesCaisse.etiquetteFond);
    expect(
      sans(lib['cloture_titre'] as String, {':point': 'bar'}),
      MessagesCaisse.titreCloture('bar'),
    );
    expect(lib['cloture_theorique'], MessagesCaisse.sousTitreCloture);
    expect(lib['cloture_recap_fond'], MessagesCaisse.recapFond);
    expect(lib['cloture_recap_especes'], MessagesCaisse.recapEspeces);
    expect(lib['cloture_recap_theorique'], MessagesCaisse.recapTheorique);
    expect(lib['cloture_constate'], MessagesCaisse.etiquetteConstate);
    expect(lib['cloture_recap_aide'], MessagesCaisse.aideRecap);
    expect(lib['annuler'], MessagesCaisse.annuler);
    expect(
      sans(lib['caisse_ouverte_message'] as String, {':point': 'bar'}),
      MessagesCaisse.ouverte('bar'),
    );
    expect(
      sans(lib['caisse_cloturee'] as String, {':point': 'bar', ':ecart': 'E'}),
      MessagesCaisse.cloturee('bar', 'E'),
    );
    expect(
      sans(lib['caisse_cloturee_sans_ecart'] as String, {':point': 'bar'}),
      MessagesCaisse.clotureeSansEcart('bar'),
    );
    expect(lib['refus_sans_caisse'], MessagesCaisse.refusSansCaisse);
    expect(lib['refus_caisse_deja_ouverte'], MessagesCaisse.refusDejaOuverte);
  });

  test('le format du message d’écart suit MontantFcfa::format sur des écarts '
      'choisis', () {
    // Les cas qui font diverger un arrondi naïf : la demi-unité négative, un
    // écart qui s'arrondit à zéro (le signe disparaît), un écart de quelques
    // centimes (« écart de 0 FCFA », pas « aucun écart »).
    expect(formaterCentimesEnFcfa(-50), '-1 FCFA');
    expect(formaterCentimesEnFcfa(-49), '0 FCFA');
    expect(formaterCentimesEnFcfa(49), '0 FCFA');
    expect(formaterCentimesEnFcfa(50), '1 FCFA');
    expect(formaterCentimesEnFcfa(-323306789), '-3 233 068 FCFA');
    expect(
      messageCloture(PointDeVenteCaisse.bar, 1),
      contains('écart de 0 FCFA'),
    );
    expect(messageCloture(PointDeVenteCaisse.bar, 0), contains('aucun écart'));
  });
}

/// Le code du point du POS, pour la comparaison avec `PosComptant::POINT_CAISSE`.
const String pointDeCaisseDuComptoirCode = 'bar';

// ------------------------------------------------------------- normalisation

String _texte(Object? v) => _canon(v);

String _canon(Object? v) {
  if (v is Map) {
    final cles = v.keys.map((k) => '$k').toList()..sort();
    return '{${cles.map((k) => '$k:${_canon(v[k])}').join(',')}}';
  }
  if (v is List) return '[${v.map(_canon).join(',')}]';
  return '$v';
}

/// L'insécable U+00A0 du serveur devient l'espace ordinaire du poste.
String _normaliserTexte(String t) =>
    t.replaceAll(String.fromCharCode(0x00A0), ' ');

Map<String, Object?> _erreurs(Object? brutes) {
  if (brutes is! Map || brutes.isEmpty) return const {};
  return {
    for (final e in brutes.entries)
      '${e.key}': [for (final m in e.value as List) _normaliserTexte('$m')],
  };
}

/// Ce que le serveur rend, ramené à la forme comparée.
Map<String, Object?> _normaliserServeur(Map<String, dynamic> r) {
  if (r.containsKey('refus')) return {'refus': r['refus']};
  if (r.containsKey('statut') && r['statut'] == 403) return {'statut': 403};
  if (r.containsKey('propose')) {
    return {'statut': r['statut'], 'propose': r['propose']};
  }
  if (r.containsKey('sessions')) {
    return {
      'sessions': [
        for (final s in (r['sessions'] as List).cast<Map<String, dynamic>>())
          {
            'point_vente': s['point_vente'],
            'ouvreur_est': s['ouvreur_est'],
            'montant_fond': s['montant_fond'],
            'cloturee': s['cloturee'],
            'montant_theorique': s['montant_theorique'],
            'montant_constate': s['montant_constate'],
          },
      ],
    };
  }
  if (r.containsKey('statut')) {
    return {
      'statut': r['statut'],
      'erreurs': _erreurs(r['erreurs']),
      'succes': r['succes'] == null ? null : _normaliserTexte('${r['succes']}'),
    };
  }
  if (r.containsKey('libelles')) return {'libelles': true};
  return {for (final e in r.entries) e.key: e.value};
}

Map<String, Object?> _normaliserLocal(Map<String, Object?> r) => r;

// ----------------------------------------------------------------- côté poste

/// Rejoue [scenario] sur le DAO, et rend un résultat par opération dans la
/// forme du serveur normalisé.
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> scenario,
  List<dynamic> serveur,
  DateTime horloge,
) async {
  final db = AppDatabase.enMemoire();
  await db.customStatement('SELECT 1');
  addTearDown(db.close);
  final dao = SessionsCaisseDao(db, maintenant: () => horloge);

  final utilisateurs = <String, _Utilisateur>{};
  final especes = <String, int>{};
  final ordre = <String>[];

  Future<void> suivre() async {
    for (final s in await dao.sessions()) {
      if (!ordre.contains(s.id)) ordre.add(s.id);
    }
  }

  final resultats = <Map<String, Object?>>[];

  for (var indice = 0; indice < scenario.length; indice++) {
    final op = scenario[indice];
    switch (op['op']) {
      case 'libelles':
        resultats.add({'libelles': true});
      case 'utilisateur':
        final ref = op['ref']! as String;
        final id = 'u-$ref';
        await db
            .into(db.utilisateursLocal)
            .insert(
              UtilisateursLocalCompanion.insert(
                id: id,
                login: 'login-$ref',
                nom: 'Utilisateur $ref',
                role: op['role']! as String,
                droitsJson: '{}',
                sel: 's',
                empreinte: 'e',
                iterations: 1,
                dateCreation: DateTime(2026, 10, 1),
                dateMotDePasse: DateTime(2026, 10, 1),
              ),
            );
        // Le droit M5 vient du SERVEUR (matrice RBAC de `RolePermissionSeeder`,
        // lu par `niveauSurModule('M5')`), jamais recopié ici.
        final m5 = (serveur[indice] as Map<String, dynamic>)['m5'] as String;
        utilisateurs[ref] = _Utilisateur(id, m5 == 'C');
        resultats.add({'ok': true, 'm5': m5});
      case 'semer_session':
        final u = utilisateurs[op['user']]!;
        final date = horloge.subtract(
          Duration(minutes: (op['il_y_a_minutes']! as int)),
        );
        await db
            .into(db.sessionsCaisseLocal)
            .insert(
              SessionsCaisseLocalCompanion.insert(
                id: 'sem-${ordre.length}-${op['point_vente']}',
                pointVente: op['point_vente']! as String,
                utilisateurOuvertureId: u.id,
                dateOuverture: date,
                montantFondCentimes: DecimalSaisi.lire(
                  op['fond']! as String,
                )!.centimesArrondis!,
                dateCloture: Value((op['ouverte']! as bool) ? null : horloge),
              ),
            );
        await suivre();
        resultats.add({'ok': true});
      case 'semer_vente':
        final point = PointDeVenteCaisse.depuisCode(
          op['point_session']! as String,
        )!;
        final session = await dao.sessionOuverte(point);
        if (op['mode'] == 'especes' && op['statut'] == 'validee') {
          especes[session!.id] =
              (especes[session.id] ?? 0) +
              DecimalSaisi.lire(op['montant']! as String)!.centimesArrondis!;
        }
        resultats.add({'ok': true});
      case 'ouvrir':
        final u = utilisateurs[op['user']]!;
        resultats.add(
          await _issue(() async {
            final s = await dao.ouvrir(
              point: PointDeVenteCaisse.bar,
              fondSaisi: op['fond'] as String?,
              auteurId: u.id,
              peutEcrire: u.peutEcrire,
            );
            await suivre();
            return messageOuverture(s.point);
          }),
        );
      case 'theorique_propose':
        final s = await dao.sessionOuverte(PointDeVenteCaisse.bar);
        resultats.add({
          'statut': 200,
          'propose': s == null
              ? null
              : chaineDepuisCentimes(
                  theoriqueCentimes(
                    fondCentimes: s.fondCentimes,
                    especesCentimes: especes[s.id] ?? 0,
                  ),
                ),
        });
      case 'cloturer':
        final u = utilisateurs[op['user']]!;
        resultats.add(
          await _issue(() async {
            final ouverte = await dao.sessionOuverte(PointDeVenteCaisse.bar);
            final c = await dao.cloturer(
              point: PointDeVenteCaisse.bar,
              constateSaisi: op['constate'] as String?,
              peutEcrire: u.peutEcrire,
              // Le serveur somme les espèces de la session : ici, la somme des
              // fixtures rattachées à CETTE session (0 si aucune vente — pas
              // « inconnu » : le serveur sait qu'il n'y en a pas).
              especesEncaisseesCentimes: ouverte == null
                  ? null
                  : (especes[ouverte.id] ?? 0),
            );
            return messageCloture(c.session.point, c.ecartCentimes);
          }),
        );
      case 'etat':
        final toutes = {for (final s in await dao.sessions()) s.id: s};
        final parNom = {
          for (final e in utilisateurs.entries) e.value.id: e.key,
        };
        resultats.add({
          'sessions': [
            for (final id in ordre)
              {
                'point_vente': toutes[id]!.point.code,
                'ouvreur_est': parNom[toutes[id]!.utilisateurOuvertureId],
                'montant_fond': chaineDepuisCentimes(toutes[id]!.fondCentimes),
                'cloturee': !toutes[id]!.estOuverte,
                'montant_theorique': toutes[id]!.theoriqueCentimes == null
                    ? null
                    : chaineDepuisCentimes(toutes[id]!.theoriqueCentimes!),
                'montant_constate': toutes[id]!.constateCentimes == null
                    ? null
                    : chaineDepuisCentimes(toutes[id]!.constateCentimes!),
              },
          ],
        });
      case 'session_pour_encaissement':
        final s = await dao.sessionOuverteLaPlusRecente();
        resultats.add({'point_vente': s?.point.code});
      case 'indicateur':
        final s = await dao.sessionOuverteLaPlusRecente();
        resultats.add({
          'indicateur': s == null
              ? {'etat': 'fermee', 'point': null}
              : {
                  'etat': horloge.difference(s.dateOuverture).inHours >= 24
                      ? 'tardive'
                      : 'ouverte',
                  'point': s.point.libelle,
                },
        });
      case 'tresorerie_caisse':
        // La part « fonds des sessions ouvertes » du KPI (aucun paiement dans ce
        // scénario) : tous points confondus, comme `tresorerieCaisse()`.
        var fonds = 0;
        for (final s in await dao.sessions()) {
          if (s.estOuverte) fonds += s.fondCentimes;
        }
        resultats.add({'tresorerie': chaineDepuisCentimes(fonds)});
      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}

class _Utilisateur {
  const _Utilisateur(this.id, this.peutEcrire);
  final String id;
  final bool peutEcrire;
}

/// Joue [geste] et le met dans la forme du serveur : statut 403 si le droit
/// manque, refus classés, erreurs par champ.
Future<Map<String, Object?>> _issue(Future<String> Function() geste) async {
  try {
    final succes = await geste();
    return {'statut': 200, 'erreurs': const {}, 'succes': succes};
  } on RefusCaisse catch (e) {
    if (e.message == MessagesCaisse.refusDroit) return {'statut': 403};
    if (e.message == MessagesCaisse.horsPlage) {
      return {'refus': 'QueryException'};
    }
    if (e.message == MessagesCaisse.malForme) return {'refus': 'ValueError'};
    return {
      'statut': 200,
      'erreurs': {
        e.champ!.propriete: [e.message],
      },
      'succes': null,
    };
  }
}
