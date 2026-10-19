@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/mode_reglement.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/croise_local.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/presentation/onglets_tableau_de_bord.dart';

/// Le tableau croisé du poste, CONFRONTÉ au serveur par exécution.
///
/// `tool/tableau_de_bord/rejouer_croise.php` appelle le VRAI
/// `Accueil::croiser` (méthode privée, par réflexion) sur un SQLite en mémoire
/// portant les mêmes ventes, dépenses et réservations que le poste reçoit ici,
/// sous la VRAIE `Periode::resoudre`. Le poste rejoue `faitsCroises` puis
/// `croiser` sur les bornes que le serveur a résolues : seul le croisement est
/// comparé, la résolution de période l'est déjà par
/// `indicateurs_contre_serveur_test.dart`.
///
/// PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute pas.
Future<Map<String, dynamic>> _executer(Map<String, dynamic> cas) async {
  final php = await Process.start('php', [
    'tool/tableau_de_bord/rejouer_croise.php',
  ]);
  php.stdin.write(jsonEncode(cas));
  await php.stdin.close();
  final sortie = utf8.decodeStream(php.stdout);
  final erreur = utf8.decodeStream(php.stderr);
  final code = await php.exitCode;
  if (code != 0) {
    fail(
      'Le serveur n’a pas pu rejouer le croisement (php, code $code) : '
      '${await erreur}. C’est un ÉCHEC, pas un saut.',
    );
  }
  return jsonDecode(await sortie) as Map<String, dynamic>;
}

/// Une vente : son en-tête (comme `ventes`) et ses lignes.
typedef _Vente = ({
  String id,
  String quand,
  String point,
  ModeReglement mode,
  bool annulee,
  List<(String module, String categorie, String nom, int quantite, int montant)>
  lignes,
});

DateTime _instant(String s) => DateTime.parse(s.replaceFirst(' ', 'T'));

String _decimal(int v) => '$v.00';

void main() {
  // ---------------------------------------------------------------- données
  final ventes = <_Vente>[
    (
      id: 'v1',
      quand: '2026-10-03 10:00:00',
      point: 'Comptoir',
      mode: ModeReglement.especes,
      annulee: false,
      lignes: [
        ('M5', 'locale', 'Béninoise 33cl', 2, 2000),
        ('M4', '', 'Riz sauce', 1, 2500),
        ('M5', 'locale', '100', 1, 700),
        ('M5', 'locale', '9', 3, 900),
        // Hors du plan multilingue de base contre un caractère « pleine
        // largeur » : l'ordre UTF-16 (`String.compareTo` de Dart) et l'ordre
        // des OCTETS UTF-8 (`strcmp` de PHP) s'y contredisent.
        ('M5', 'locale', '\u{1D400}lpha', 1, 100),
        ('M5', 'locale', '\u{FF21}lpha', 1, 100),
      ],
    ),
    // La borne EXCLUE est comptée par le serveur (deux bornes incluses).
    (
      id: 'v2',
      quand: '2026-11-01 00:00:00',
      point: 'Réception',
      mode: ModeReglement.mobileMoney,
      annulee: false,
      lignes: [('M5', 'importée', 'Heineken', 3, 4500)],
    ),
    (
      id: 'v3',
      quand: '2026-10-10 20:15:00',
      point: 'Séjour',
      mode: ModeReglement.noteChambre,
      annulee: false,
      lignes: [
        ('M4', 'Plats', 'Été au jardin', 2, 6000),
        ('M4', 'Plats', 'Zèbre grillé', 1, 3500),
        ('M4', 'Plats', 'éclair', 1, 1000),
      ],
    ),
    (
      id: 'v4',
      quand: '2026-09-30 23:59:59',
      point: 'Comptoir',
      mode: ModeReglement.carte,
      annulee: false,
      lignes: [('M5', 'locale', 'Hors période', 1, 1000)],
    ),
    (
      id: 'v5',
      quand: '2026-10-21 09:00:00',
      point: 'Comptoir',
      mode: ModeReglement.virement,
      annulee: false,
      lignes: [('M5', 'locale', 'Béninoise 33cl', 5, 5000)],
    ),
    // Une vente ANNULÉE : le serveur l'écarte ; le poste n'en a pas (il
    // n'annule que des paniers ouverts). L'égalité prouve l'écart du serveur.
    (
      id: 'v6',
      quand: '2026-10-11 11:00:00',
      point: 'Comptoir',
      mode: ModeReglement.especes,
      annulee: true,
      lignes: [('M5', 'locale', 'Annulée', 9, 9000)],
    ),
  ];

  final depenses =
      <
        (
          String id,
          String date,
          String tresorerie,
          List<(String, String, int)> lignes,
        )
      >[
        (
          'd1',
          '2026-10-04',
          'caisse',
          [('Achats', 'Riz', 5000), ('Transport', 'Carburant', 3000)],
        ),
        // Le LENDEMAIN de la période : compté par le serveur (défaut répliqué).
        ('d2', '2026-11-01', 'momo', [('Énergie', 'Électricité', 7000)]),
        ('d3', '2026-11-02', 'banque', [('Énergie', 'Hors période', 1000)]),
        ('d4', '2026-09-30', 'caisse', [('Achats', 'Hors période', 1000)]),
        ('d5', '2026-10-31', 'caisse', [('', '', 250)]),
      ];

  final clients = [
    ('c1', 'KORA', 'Jean'),
    ('c2', 'DOSSOU', ''),
    ('c3', 'AHOUNOU', 'Marie'),
  ];
  final reservations =
      <(String id, String statut, String arrivee, int acompte, String client)>[
        ('r1', 'confirmee', '2026-10-05', 10000, 'c1'),
        ('r2', 'en_attente', '2026-11-01', 0, 'c2'),
        ('r3', 'annulee', '2026-10-07', 5000, 'c3'),
        ('r4', 'en_cours', '2026-10-20', 2500, 'c3'),
        ('r5', 'confirmee', '2026-11-02', 4000, 'c1'),
      ];

  // ------------------------------------------- les mêmes données, côté poste
  final lignesVente = [
    for (final v in ventes)
      if (!v.annulee)
        for (final l in v.lignes)
          LigneVenteCroisee(
            clotureLe: _instant(v.quand),
            pointVente: v.point,
            modeLibelle: v.mode.libelle,
            encaisse: v.mode.encaisse,
            module: l.$1,
            categorie: l.$2,
            nom: l.$3,
            quantite: l.$4,
            montant: l.$5,
          ),
  ];
  final lignesDepense = [
    for (final d in depenses)
      for (final l in d.$4)
        LigneDepenseCroisee(
          dateTransaction: DateTime.parse(d.$2),
          tresorerie: d.$3,
          famille: l.$1,
          nature: l.$2,
          montant: l.$3,
        ),
  ];
  final reservationsCroisees = [
    for (final r in reservations)
      () {
        final c = clients.firstWhere((c) => c.$1 == r.$5);
        return ReservationCroisee(
          dateArrivee: DateTime.parse(r.$3),
          annulee: r.$2 == 'annulee',
          acompte: r.$4,
          nom: c.$2,
          prenom: c.$3,
        );
      }(),
  ];

  // ---------------------------------------------------------- les requêtes
  const tout = ['ventes', 'depenses', 'reservations'];
  final requetes = <Map<String, Object?>>[
    for (final (ligne, colonne, mesure, sources) in [
      ('activite', 'mois', 'montant', tout),
      ('source', 'module', 'encaisse', tout),
      ('libelle', 'aucun', 'quantite', tout),
      ('tiers', 'mode', 'nombre', ['ventes']),
      ('jour', 'source', 'montant', tout),
      ('mois', 'activite', 'montant', ['depenses', 'reservations']),
      ('module', 'jour', 'encaisse', <String>[]),
      ('mode', 'tiers', 'encaisse', ['ventes', 'reservations']),
      ('aucun', 'aucun', 'nombre', tout),
      ('libelle', 'jour', 'montant', ['ventes']),
    ])
      {
        'reference': '2026-10-15 12:00:00',
        'periode': 'mois',
        'ligne': ligne,
        'colonne': colonne,
        'mesure': mesure,
        'sources': sources,
      },
    // Une période personnalisée étroite, et une période sans aucun fait.
    {
      'reference': '2026-10-15 12:00:00',
      'periode': 'personnalisee',
      'du': '2026-10-03',
      'au': '2026-10-04',
      'ligne': 'activite',
      'colonne': 'jour',
      'mesure': 'montant',
      'sources': tout,
    },
    {
      'reference': '2026-12-15 12:00:00',
      'periode': 'aujourdhui',
      'ligne': 'activite',
      'colonne': 'mois',
      'mesure': 'montant',
      'sources': tout,
    },
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await _executer({
      'ventes': [
        for (final v in ventes)
          {
            'id': v.id,
            'statut': v.annulee ? 'annulee' : 'validee',
            'created_at': v.quand,
            'point_vente': v.point,
            'mode_paiement': v.mode.code,
            'encaisse': v.mode.encaisse,
            'lignes': [
              for (final l in v.lignes)
                {
                  'module': l.$1,
                  'categorie': l.$2,
                  'nom': l.$3,
                  'quantite': l.$4,
                  'montant': _decimal(l.$5),
                },
            ],
          },
      ],
      'depenses': [
        for (final d in depenses)
          {
            'id': d.$1,
            'date_transaction': d.$2,
            'tresorerie': d.$3,
            'lignes': [
              for (final l in d.$4)
                {'famille': l.$1, 'nature': l.$2, 'montant': _decimal(l.$3)},
            ],
          },
      ],
      'clients': [
        for (final c in clients) {'id': c.$1, 'nom': c.$2, 'prenom': c.$3},
      ],
      'reservations': [
        for (final r in reservations)
          {
            'id': r.$1,
            'statut': r.$2,
            'date_arrivee': r.$3,
            'acompte': _decimal(r.$4),
            'client_id': r.$5,
          },
      ],
      'requetes': requetes,
    });
  });

  Map<String, Object?> versServeur(ResultatCroise r) => {
    'lignes': r.lignes,
    'colonnes': r.colonnes,
    'grille': [
      for (final rangee in r.grille) [for (final v in rangee) _decimal(v)],
    ],
    'totauxLignes': [for (final v in r.totauxLignes) _decimal(v)],
    'totauxColonnes': [for (final v in r.totauxColonnes) _decimal(v)],
    'total': _decimal(r.total),
    'nbFaits': r.nbFaits,
    'vide': r.vide,
    'monnaie': r.monnaie,
    'axeLigne': r.axeLigne.name,
    'mesure': r.mesure.name,
  };

  test('chaque requête : le croisement du poste est CELUI du serveur, cellule '
      'par cellule', () {
    final resultats = serveur['resultats'] as List<dynamic>;
    expect(resultats, hasLength(requetes.length));

    for (var i = 0; i < requetes.length; i++) {
      final q = requetes[i];
      final s = resultats[i] as Map<String, dynamic>;
      final periode = s['periode'] as Map<String, dynamic>;
      final sources = {
        for (final code in q['sources']! as List<String>)
          SourceCroise.values.byName(code),
      };
      final local = croiser(
        faits: faitsCroises(
          debut: _instant(periode['debut'] as String),
          finExclue: _instant(periode['fin'] as String),
          sources: sources,
          ventes: lignesVente,
          depenses: lignesDepense,
          reservations: reservationsCroisees,
        ),
        axeLigne: AxeCroise.values.byName(q['ligne']! as String),
        axeColonne: AxeCroise.values.byName(q['colonne']! as String),
        mesure: MesureCroise.values.byName(q['mesure']! as String),
      );
      expect(
        versServeur(local),
        s['croise'],
        reason: 'requête $i : ${jsonEncode(q)}',
      );
      // La liste des sources retenues est celle des cases cochées.
      expect(s['sources_retenues'], q['sources']);
    }
  });

  test('le scénario éprouve ce qui compte (pas un vert à vide)', () {
    final resultats = [
      for (final r in serveur['resultats'] as List<dynamic>)
        (r as Map<String, dynamic>)['croise'] as Map<String, dynamic>,
    ];
    final premier = resultats.first;
    // La dépense du 1er novembre ouvre une colonne « novembre 2026 » dans le
    // mois d'octobre : le défaut du serveur est bien rejoué.
    expect(premier['colonnes'], ['octobre 2026', 'novembre 2026']);
    // Un solde négatif, une ligne « — » (catégorie vide), les numériques.
    expect(premier['totauxLignes'], contains('-5000.00'));
    expect(premier['lignes'], contains('—'));
    expect(resultats[2]['lignes'], containsAll(<String>['100', '9']));
    // `asort` numérique : « 9 » avant « 100 ».
    final libelles = resultats[2]['lignes'] as List<dynamic>;
    expect(libelles.indexOf('9'), lessThan(libelles.indexOf('100')));
    // Octets UTF-8 : « Ａ » (EF BC A1) avant « 𝐀 » (F0 9D 90 80) — l'inverse
    // de l'ordre UTF-16.
    expect(
      libelles.indexOf('\u{FF21}lpha'),
      lessThan(libelles.indexOf('\u{1D400}lpha')),
    );
    // Aucune source : vide. Une période sans fait : vide.
    expect(resultats[6]['vide'], isTrue);
    expect(resultats.last['vide'], isTrue);
    // L'axe « Jour » trié sur `d/m/Y` : 01/11 avant 31/10 (défaut répliqué).
    final jours = resultats[4]['lignes'] as List<dynamic>;
    expect(jours.indexOf('01/11/2026'), lessThan(jours.indexOf('31/10/2026')));
  });

  test('les registres et les mots de la vue sont ceux du serveur', () {
    final registres = serveur['registres'] as Map<String, dynamic>;
    final libelles = serveur['libelles'] as Map<String, dynamic>;
    final croise = libelles['croise'] as Map<String, dynamic>;

    expect([for (final a in AxeCroise.values) a.name], registres['axes']);
    expect({
      for (final m in MesureCroise.values) m.name: m.monnaie,
    }, registres['mesures']);
    expect([for (final s in SourceCroise.values) s.name], registres['sources']);

    final defauts = registres['defauts'] as Map<String, dynamic>;
    expect(defauts['ligne'], AxeCroise.activite.name);
    expect(defauts['colonne'], AxeCroise.mois.name);
    expect(defauts['mesure'], MesureCroise.montant.name);
    expect(defauts['sources'], [for (final s in SourceCroise.values) s.name]);

    expect({
      for (final a in AxeCroise.values) a.name: a.libelleOption,
    }, croise['axes']);
    expect({
      for (final m in MesureCroise.values) m.name: m.libelleOption,
    }, croise['mesures']);
    expect({
      for (final s in SourceCroise.values) s.name: s.libelle,
    }, croise['sources_libelles']);
    expect(MotsCroise.intro, croise['intro']);
    expect(MotsCroise.aucuneSource, croise['aucune_source']);
    expect(MotsCroise.vide, croise['vide']);
    expect(
      MotsCroise.note(7),
      (croise['note'] as String).replaceAll(':nombre', '7'),
    );
    expect(MotsCroise.noteReservations, croise['note_reservations']);
    expect(MotsCroise.lignes, croise['lignes']);
    expect(MotsCroise.colonnes, croise['colonnes']);
    expect(MotsCroise.mesure, croise['mesure']);
    expect(MotsCroise.sources, croise['sources']);
    expect(MotsCroise.total, croise['total']);
    expect(MotsCroise.colonneAxe, croise['col_axe']);
    expect(MotsCroise.activiteHebergement, croise['activite_hebergement']);
    expect(MotsCroise.tiret, libelles['tiret']);
    expect(OngletTableauDeBord.croise.libelle, libelles['onglet']);
    expect('Exporter', libelles['export_bouton']);
    expect('Non consulté', libelles['non_consulte']);
  });
}
