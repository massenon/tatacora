@Timeout(Duration(minutes: 3))
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/rbac/garde_acces.dart';
import 'package:tatacora_flutter/core/rbac/regle_archivage.dart';
import 'package:tatacora_flutter/features/achats/data/achats_api.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/archivage_fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/entities/fournisseur.dart';
import 'package:tatacora_flutter/features/achats/domain/messages_achats.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_dao.dart';
import 'package:tatacora_flutter/features/parametres/domain/options_systeme.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import 'support/outils_reglement.dart';

/// L'ARCHIVAGE D'UN FOURNISSEUR (M7, D63) et la bascule `activation_suppression`,
/// joués par le VRAI composant `Achats`, les vrais `ReferentielFournisseurService`
/// et `OptionsSystemeService` et la vraie règle `AutoriseArchivage` du serveur sur
/// MySQL, puis par le poste sur sa base locale, comparés CHAMP À CHAMP : qui peut
/// archiver (chaque rôle, bascule absente / fermée / ouverte), la lecture de la
/// bascule pour treize valeurs brutes, le lot composé (bloqué, partiel, nominal),
/// les motifs de verrou, l'exécution (refus par élément, succès), la restauration,
/// le sélecteur des commandes.
///
/// `tool/achats/rejouer_archivage.php` travaille sur `tatacora_test` (il refuse
/// toute autre base), sème les rôles par le vrai seeder, puis ANNULE tout. MySQL
/// injoignable : le test ÉCHOUE, il ne saute pas.
///
/// ## Ce que ce test a relevé sur le serveur
///
/// * une sélection qui ne porte que des fiches DÉJÀ archivées ouvre la modale
///   BLOQUÉE, sans motif — elle ne retourne pas (D271) ;
/// * la question de la modale compte les fiches qui PARTENT, pas la sélection ;
/// * `oui` n'est pas un booléen pour PHP : la bascule reste fermée.
///
/// ## Écarts de représentation, normalisés avant la comparaison
///
/// 1. un refus d'archivage par la bascule fermée est un 403 SANS module refusé
///    (aucune trace de sécurité n'est écrite : le droit d'écrire, lui, est passé) ;
///    un refus par le droit d'écriture manquant nomme M7 — le poste rend le
///    module du droit qu'il a testé ;
/// 2. l'ordre des fiches d'un lot est celui de la raison sociale.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const aujourdhui = '2026-10-13';
  final maintenant = DateTime(2026, 10, 13, 10);

  Map<String, Object?> commande(
    String ref,
    String fournisseur,
    String statut,
    String date,
  ) => {
    'op': 'commande',
    'ref': ref,
    'fournisseur': fournisseur,
    'user': 'a',
    'date': date,
    'statut':
        statut == 'receptionnee' ||
            statut == 'cloturee' ||
            statut == 'receptionnee_partiellement'
        ? 'envoyee'
        : statut,
    'lignes': [
      {'article': 'a1', 'quantite': '4', 'prix': '1000'},
    ],
  };
  Map<String, Object?> statut(String commande, String statut) => {
    'op': 'statut',
    'commande': commande,
    'statut': statut,
  };
  Map<String, Object?> archiver(
    String user,
    List<String> fournisseurs, {
    String mode = 'ligne',
    bool confirmer = false,
    List<String> engager = const [],
  }) => {
    'op': 'archiver',
    'user': user,
    'fournisseurs': fournisseurs,
    'mode': mode,
    'confirmer': confirmer,
    if (engager.isNotEmpty) 'engager_entre_les_deux': engager,
  };
  Map<String, Object?> parametre(String? valeur) => {
    'op': 'parametre',
    'valeur': valeur,
  };

  const roles = [
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
  ];

  final scenario = <Map<String, Object?>>[
    {'op': 'libelles'},
    {'op': 'utilisateur', 'ref': 'a', 'role': 'administrateur'},
    {'op': 'utilisateur', 'ref': 'ac', 'role': 'achats'},
    {'op': 'utilisateur', 'ref': 'co', 'role': 'comptable'},
    {'op': 'fournisseur', 'ref': 'f1', 'nom': 'Alpha'},
    {'op': 'fournisseur', 'ref': 'f2', 'nom': 'Bravo'},
    {'op': 'fournisseur', 'ref': 'f3', 'nom': 'Charlie'},
    {'op': 'fournisseur', 'ref': 'f4', 'nom': 'Delta'},
    {'op': 'fournisseur', 'ref': 'f5', 'nom': 'Echo'},
    {'op': 'fournisseur', 'ref': 'f6', 'nom': 'Foxtrot'},
    {'op': 'article', 'ref': 'a1', 'libelle': 'Sucre'},
    // Bravo : une commande envoyée (engage). Charlie : un brouillon ET une
    // envoyée (engage deux fois). Delta : réceptionnée et clôturée (n'engage
    // PLUS). Echo, Foxtrot : libres.
    commande('c1', 'f2', 'envoyee', '2026-10-01'),
    commande('c2', 'f3', 'brouillon', '2026-10-02'),
    commande('c3', 'f3', 'envoyee', '2026-10-03'),
    commande('c4', 'f4', 'receptionnee', '2026-10-04'),
    statut('c4', 'receptionnee'),
    commande('c5', 'f4', 'cloturee', '2026-10-05'),
    statut('c5', 'cloturee'),

    // --- Qui peut archiver : la bascule ABSENTE (défaut fermé) --------------
    {'op': 'bascule'},
    for (final r in roles) {'op': 'peut_archiver', 'role': r},

    // --- La bascule OUVERTE ---------------------------------------------------
    parametre('true'),
    {'op': 'bascule'},
    for (final r in roles) {'op': 'peut_archiver', 'role': r},

    // --- La bascule FERMÉE explicitement -------------------------------------
    parametre('false'),
    {'op': 'bascule'},
    for (final r in ['administrateur', 'achats', 'comptable'])
      {'op': 'peut_archiver', 'role': r},

    // --- La lecture de la valeur BRUTE (OptionsSystemeService::actif) --------
    for (final brut in [
      'true',
      'TRUE',
      ' true ',
      '1',
      'on',
      'yes',
      'false',
      '0',
      'oui',
      'garbage',
      '2',
      '',
      '   ',
    ]) ...[
      parametre(brut),
      {'op': 'bascule'},
    ],
    parametre(null),
    {'op': 'bascule'},

    // --- Le refus du geste : l'écriture d'abord, puis la bascule -------------
    archiver('co', ['f1']), // M7 = L : 403 M7
    archiver('ac', ['f1']), // écrit, bascule fermée : 403 sans module
    {'op': 'etat'},

    // --- L'ouverture de la confirmation, le lot ------------------------------
    archiver('a', ['f1']), // une fiche libre : NOMINAL, nommée
    archiver('a', ['f2']), // une fiche engagée : BLOQUÉ
    archiver('a', ['f3']), // engagée deux fois
    archiver('a', ['f4']), // réceptionnée / clôturée : n'engagent plus
    archiver('a', ['f5', 'f6'], mode: 'lot'), // deux libres : le NOMBRE
    archiver('a', ['f2', 'f5'], mode: 'lot'), // PARTIEL
    archiver('a', ['f6', 'f2', 'f3'], mode: 'lot'), // un libre, deux engagés
    archiver('a', ['f2', 'f3'], mode: 'lot'), // tout engagé : BLOQUÉ
    // --- L'exécution ---------------------------------------------------------
    archiver('a', ['f1'], confirmer: true),
    {'op': 'etat'},
    // Que des archivés : la modale s'ouvre BLOQUÉE, sans motif (D271).
    archiver('a', ['f1'], mode: 'lot'),
    archiver('a', ['f1', 'f2'], mode: 'lot'),
    // Un engagement né ENTRE l'ouverture et le clic : le lot partait, le service
    // refuse, rien n'est écrit.
    archiver('a', ['f4'], confirmer: true, engager: ['f4']),
    {'op': 'etat'},
    // … et quand une partie du lot part malgré tout : succès ET refus.
    archiver('a', ['f5', 'f6'], mode: 'lot', confirmer: true, engager: ['f6']),
    {'op': 'etat'},
    // Avec la bascule ouverte, un acheteur archive.
    parametre('true'),
    archiver('ac', ['f3'], mode: 'lot'),
    archiver('ac', ['f2', 'f3'], mode: 'lot', confirmer: true),

    // --- La restauration : l'écriture seule ----------------------------------
    parametre('false'),
    {'op': 'restaurer', 'user': 'co', 'fournisseur': 'f1'}, // L : 403 M7
    {'op': 'restaurer', 'user': 'ac', 'fournisseur': 'f1'}, // bascule fermée
    {'op': 'restaurer', 'user': 'ac', 'fournisseur': 'f1'}, // déjà actif
    {'op': 'restaurer', 'user': 'a', 'fournisseur': 'f5'},
    {'op': 'etat'},

    // --- Le sélecteur de la commande ------------------------------------------
    {'op': 'selecteur', 'user': 'a'},
  ];

  late List<dynamic> serveur;
  late List<Map<String, Object?>> local;

  setUpAll(() async {
    final reponse = await executerPhp(
      'rejouer_archivage.php',
      dossier: 'achats',
      entree: {'aujourdhui': aujourdhui, 'ops': scenario},
    );
    serveur = reponse['resultats'] as List<dynamic>;
    local = await _rejouerSurLePoste(scenario, serveur, maintenant);
  });

  test('le scénario est assez large pour que la comparaison compte', () {
    expect(serveur, hasLength(scenario.length));
    expect(local, hasLength(scenario.length));

    final issues = [for (final r in serveur) r as Map<String, dynamic>];
    // Les trois états de la modale ont été vus du serveur.
    final ouvertures = [
      for (final i in issues)
        if (i['ouverture'] != null) i['ouverture'] as Map<String, dynamic>,
    ];
    expect(ouvertures.where((o) => o['bloque'] == true), isNotEmpty);
    expect(
      ouvertures.where(
        (o) => o['bloque'] == false && (o['conserves'] as int) > 0,
      ),
      isNotEmpty,
      reason: 'l’état PARTIEL',
    );
    expect(
      ouvertures.where((o) => o['bloque'] == false && o['conserves'] == 0),
      isNotEmpty,
      reason: 'l’état NOMINAL',
    );
    // Des 403, des succès, et un refus de service par élément.
    expect(issues.where((i) => i['statut'] == 403), isNotEmpty);
    expect(
      issues.where(
        (i) => (i['succes'] as String?)?.contains('archivé') ?? false,
      ),
      isNotEmpty,
    );
    expect(
      issues.where((i) {
        final e = i['erreurs'];
        return e is Map && e.containsKey('archivage');
      }),
      hasLength(2),
    );
    // Les deux moitiés de la règle : des rôles qui archivent, d'autres non.
    final regles = [
      for (final i in issues)
        if (i.containsKey('peutArchiver')) i['peutArchiver'] as bool,
    ];
    expect(regles.where((p) => p), isNotEmpty);
    expect(regles.where((p) => !p), isNotEmpty);
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

  test('les phrases et les registres sont ceux du serveur', () {
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
      sans(lib['verrou'] as String, {':nombre': '3'}),
      MessagesAchats.verrouArchivage(3),
    );
    expect(lib['succes_un'], MessagesAchats.archivesSucces(1));
    expect(lib['succes_deux'], MessagesAchats.archivesSucces(2));
    expect(lib['succes_trois'], MessagesAchats.archivesSucces(3));
    expect(
      sans(lib['restaure'] as String, {':nom': 'Alpha'}),
      MessagesAchats.restaure('Alpha'),
    );
    expect(lib['refus_bascule'], MessagesAchats.refusBascule);
    expect(lib['bouton_ligne'], 'Supprimer');
    expect(lib['bouton_lot'], 'Supprimer');
    expect(lib['bouton_restaurer'], 'Restaurer');
    expect(lib['badge'], 'Archivé');

    // Le registre des bascules et ses défauts, relus du serveur.
    expect(
      (lib['defauts'] as Map<String, dynamic>).cast<String, bool>(),
      OptionsSysteme.defauts,
    );
    // Les deux rôles qui archivent sans la bascule.
    expect({
      ...(lib['roles_administration'] as List<dynamic>).cast<String>(),
    }, rolesAdministration);
  });
}

// ------------------------------------------------------- rejeu sur le poste

Future<List<Map<String, Object?>>> _rejouerSurLePoste(
  List<Map<String, Object?>> scenario,
  List<dynamic> serveur,
  DateTime maintenant,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');

  final parametres = ParametresDao(db, maintenant: () => maintenant);
  final utilisateurs = <String, String>{}; // ref -> id
  final niveaux = <String, String>{}; // ref -> niveau M7
  final rolesDe = <String, String>{}; // ref -> libellé du rôle
  final fournisseurs = <String, String>{}; // ref -> id
  final noms = <String, String>{};
  final commandes = <String, String>{};
  final resultats = <Map<String, Object?>>[];

  Future<bool> peutArchiverMaintenant(String niveau, String role) async {
    final valeurs = await parametres.lireTout();
    return peutArchiver(
      droits: GardeAcces.depuisJson({'M7': niveau}),
      module: ModuleTatacora.m7Achats,
      role: role,
      suppressionActive: OptionsSysteme.suppressionActive(
        valeurs[OptionsSysteme.cleSuppression],
      ),
    );
  }

  Future<AchatsApi> api(String user) async {
    final niveau = niveaux[user]!;
    final role = rolesDe[user]!;
    return AchatsApi(
      dao: achatsDaoSur(db, maintenant: maintenant),
      peutLire: () => true,
      peutEcrire: () => GardeAcces.depuisJson({
        'M7': niveau,
      }).peutEcrire(ModuleTatacora.m7Achats),
      auteurId: () => utilisateurs[user],
      peutArchiver: () => peutArchiverMaintenant(niveau, role),
    );
  }

  String refDe(String id) =>
      fournisseurs.entries.firstWhere((e) => e.value == id).key;

  for (var i = 0; i < scenario.length; i++) {
    final op = scenario[i];
    switch (op['op']) {
      case 'libelles':
        resultats.add({'libelles': 'rien'});

      case 'utilisateur':
        final ref = op['ref']! as String;
        utilisateurs[ref] = 'u-$ref';
        rolesDe[ref] = op['role']! as String;
        await semerAuteur(db, id: 'u-$ref');
        final n = (serveur[i] as Map<String, dynamic>)['niveau_m7']! as String;
        niveaux[ref] = n;
        resultats.add({'ok': true, 'niveau_m7': n});

      case 'fournisseur':
        final ref = op['ref']! as String;
        fournisseurs[ref] = 'f-$ref';
        noms[ref] = op['nom']! as String;
        await achatsDaoSur(db, maintenant: maintenant).creerFournisseur(
          SaisieFournisseur(
            id: 'f-$ref',
            raisonSociale: op['nom']! as String,
            contact: null,
            categorie: null,
            conditionsPaiement: null,
            evaluationCode: null,
          ),
          auteurId: utilisateurs['a'],
        );
        resultats.add({'ok': true});

      case 'article':
        resultats.add({'ok': true});

      case 'commande':
        final ligne = (op['lignes']! as List).single as Map<String, dynamic>;
        final ref = op['fournisseur']! as String;
        commandes[op['ref']! as String] = await semerCommande(
          db,
          fournisseurId: fournisseurs[ref]!,
          fournisseur: noms[ref]!,
          articleId: 'a-${ligne['article']}',
          quantite: ligne['quantite']! as String,
          prix: ligne['prix']! as String,
          date: op['date']! as String,
          statut: op['statut']! as String,
          auteurId: utilisateurs[op['user']]!,
          maintenant: maintenant,
        );
        resultats.add({'ok': true});

      case 'statut':
        await poserStatut(
          db,
          commandes[op['commande']]!,
          op['statut']! as String,
        );
        resultats.add({'ok': true});

      case 'parametre':
        await parametres.ecrire({
          OptionsSysteme.cleSuppression: op['valeur'] as String?,
        }, auteurId: null);
        resultats.add({'ok': true});

      case 'bascule':
        final valeurs = await parametres.lireTout();
        resultats.add({
          'suppression_active': OptionsSysteme.suppressionActive(
            valeurs[OptionsSysteme.cleSuppression],
          ),
        });

      case 'peut_archiver':
        final role = op['role']! as String;
        final niveau =
            (serveur[i] as Map<String, dynamic>)['niveau_m7']! as String;
        resultats.add({
          'role': role,
          'niveau_m7': niveau,
          'peutArchiver': await peutArchiverMaintenant(niveau, role),
          'peutEcrire': GardeAcces.depuisJson({
            'M7': niveau,
          }).peutEcrire(ModuleTatacora.m7Achats),
        });

      case 'archiver':
        final user = op['user']! as String;
        final a = await api(user);
        final ids = [
          for (final r in (op['fournisseurs']! as List)) fournisseurs[r]!,
        ];

        final ouverture = await a.preparerArchivage(ids);
        if (ouverture is AchatsRefuse<LotArchivage>) {
          // La bascule fermée n'écrit aucune trace de sécurité (le droit d'écrire
          // est passé) : le serveur ne nomme alors AUCUN module.
          resultats.add({
            'statut': 403,
            'module_refuse': ouverture.motif == MessagesAchats.refusBascule
                ? null
                : 'M7',
          });
          break;
        }
        final lot = (ouverture as AchatsRecu<LotArchivage>).donnees;
        final etat = {
          'modale': 'archivage',
          'a_archiver': [for (final id in lot.ids) refDe(id)],
          'verrous': lot.motifs,
          'bloque': lot.bloque,
          'conserves': lot.conserves,
          'libelle': lot.libelle,
        };
        if (op['confirmer'] != true) {
          resultats.add({'ouverture': etat});
          break;
        }
        for (final ref in (op['engager_entre_les_deux'] as List? ?? const [])) {
          await semerCommande(
            db,
            fournisseurId: fournisseurs[ref]!,
            fournisseur: noms[ref]!,
            articleId: 'a-a1',
            date: '2026-10-13',
            auteurId: utilisateurs[user]!,
            maintenant: maintenant,
          );
        }
        // `if ($this->fournisseursAArchiver === []) return;` : un lot vide ne
        // ferme PAS la modale et ne vide PAS la sélection. (Sur le poste le bouton
        // de confirmation n'existe pas dans cet état : le cas se joue par
        // l'appel direct, comme le serveur le reçoit.)
        if (lot.ids.isEmpty) {
          resultats.add({
            'ouverture': etat,
            'succes': null,
            'erreurs': <String, Object?>{},
            'modale_fermee': false,
            'selection_videe': false,
          });
          break;
        }
        final r = await a.archiverFournisseurs(lot.ids);
        final resultat = (r as AchatsRecu<ResultatArchivage>).donnees;
        resultats.add({
          'ouverture': etat,
          'succes': resultat.archives > 0
              ? MessagesAchats.archivesSucces(resultat.archives)
              : null,
          'erreurs': resultat.refus == null
              ? <String, Object?>{}
              : {
                  'archivage': [resultat.refus],
                },
          'modale_fermee': true,
          'selection_videe': true,
        });

      case 'restaurer':
        final user = op['user']! as String;
        final r = await (await api(
          user,
        )).restaurerFournisseur(fournisseurs[op['fournisseur']]!);
        resultats.add(switch (r) {
          AchatsRecu(:final donnees) => {
            'succes': MessagesAchats.restaure(donnees.raisonSociale),
          },
          AchatsRefuse() => {'statut': 403, 'module_refuse': 'M7'},
          AchatsInjoignable() => fail('Jamais produite.'),
        });

      case 'selecteur':
        final liste = await achatsDaoSur(
          db,
          maintenant: maintenant,
        ).tousLesFournisseurs();
        resultats.add({
          'fournisseurs': [for (final f in liste) refDe(f.id)],
        });

      case 'etat':
        final etat = <String, Object?>{};
        for (final e in fournisseurs.entries) {
          etat[e.key] = (await (db.select(
            db.fournisseursLocal,
          )..where((f) => f.id.equals(e.value))).getSingle()).actif;
        }
        resultats.add({
          'actifs': etat,
          'nb_commandes':
              (await db.select(db.commandesAchatLocal).get()).length,
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
  if (r['erreurs'] is List && (r['erreurs'] as List).isEmpty) {
    r['erreurs'] = <String, Object?>{};
  }
  return r;
}

Map<String, Object?> _normaliserLocal(Map<String, Object?> brut) =>
    Map<String, Object?>.from(brut);

String _canon(Object? valeur) => jsonEncode(_trier(valeur));

Object? _trier(Object? v) {
  if (v is Map) {
    return {
      for (final k in (v.keys.map((e) => '$e').toList()..sort()))
        k: _trier(v[k]),
    };
  }
  if (v is List) return [for (final e in v) _trier(e)];
  if (v is String) return v.replaceAll(' ', ' ');
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
