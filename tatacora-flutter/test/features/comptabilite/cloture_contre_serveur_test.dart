@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/entete_etablissement.dart';
import 'package:tatacora_flutter/features/comptabilite/data/archive_cloture_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/cloture_exercice_locale.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/data/moteur_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/cloture_exercice.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/comptes_syscohada.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/entities/comptabilite.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/etats_financiers.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/grand_livre_analytique.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/messages_cloture.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/montant_comptable.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/refus_comptable.dart';

import 'support/outils_comptabilite.dart';

/// La CLÔTURE ANNUELLE SYSCOHADA du poste, CONFRONTÉE au vrai serveur
/// (26/10/2026) : le même scénario — pièces, démarrage, refus, clôture,
/// à-nouveaux, perte, réouverture, re-clôture, archive — passe par
/// `ClotureExerciceService` (PHP exécuté, `tool/comptabilite/rejouer_cloture.php`)
/// et par `ClotureExerciceLocale`, et le poste doit rendre :
///
///  - les mêmes statuts d'exercice après chaque geste ;
///  - les mêmes PHRASES de refus, mot pour mot ;
///  - les mêmes lignes de pièces CL et AN (journal, date, compte, centre,
///    débit, crédit, libellé), contre-passations comprises, au centime ;
///  - les mêmes numéros de pièce, le même résultat ;
///  - la même liste de contrôle (blocages, avertissements, résultat à reporter,
///    compte de destination) et la même balance (à-nouveaux provisoires compris) ;
///  - le même `ecritures.csv` (colonnes, lignes — hors date et auteur de saisie)
///    et le MÊME `balance.csv`, octet pour octet.
///
/// Les phrases (`MessagesCloture`) sont relues du serveur, des deux côtés ; les
/// constantes (journaux, centre, motif, rôle) aussi.
typedef _Ev = Map<String, Object?>;

_Ev _piece(
  String journal,
  String date,
  String libelle,
  List<(String, String?, String?, String?)> lignes, {
  bool valide = true,
  List<String>? admis,
}) => {
  't': 'piece',
  'journal': journal,
  'date': date,
  'libelle': libelle,
  'valide': valide,
  'statuts_admis': ?admis,
  'lignes': [
    for (final (compte, debit, credit, centre) in lignes)
      {'compte': compte, 'debit': ?debit, 'credit': ?credit, 'centre': ?centre},
  ],
};

_Ev _geste(String action, int annee, {String? motif, String? role}) => {
  't': 'geste',
  'action': action,
  'annee': annee,
  'motif': ?motif,
  'role': ?role,
};

void main() {
  final scenario = <_Ev>[
    // --- 2030 : un exercice complet (gestion sur plusieurs centres) --------
    _piece('OD', '2030-01-02', 'Capital', [
      ('5711', '5000000.00', null, 'Structure'),
      ('101', null, '5000000.00', 'Structure'),
    ]),
    _piece('OD', '2030-02-01', 'Matériel', [
      ('231', '1200000.00', null, 'Structure'),
      ('5711', null, '1200000.00', 'Structure'),
    ]),
    _piece('CAI', '2030-03-10', 'Ventes bar', [
      ('5711', '100000.00', null, 'Bar'),
      ('7011', null, '100000.00', 'Bar'),
    ]),
    // Le MÊME compte de produit sur deux centres : la clôture solde centre par
    // centre, l'analytique de chacun retombe à zéro.
    _piece('CAI', '2030-03-11', 'Ventes restaurant', [
      ('5711', '80000.00', null, 'Restaurant'),
      ('7011', null, '80000.00', 'Restaurant'),
    ]),
    _piece('ACH', '2030-04-02', 'Achats du bar', [
      ('6011', '30000.00', null, 'Bar'),
      ('4011', null, '30000.00', 'Structure'),
    ]),
    _piece('OD', '2030-05-31', 'Salaires', [
      ('661', '40000.00', null, 'RH'),
      ('5711', null, '40000.00', 'RH'),
    ]),
    _piece('OD', '2030-12-31', 'Dotation', [
      ('681', '10000.00', null, 'Structure'),
      ('281', null, '10000.00', 'Structure'),
    ]),
    _piece('OD', '2030-06-01', 'Participation', [
      ('87', '2000.00', null, 'Structure'),
      ('447', null, '2000.00', 'Structure'),
    ]),
    _piece('OD', '2030-06-10', 'Impôt', [
      ('89', '8000.00', null, 'Structure'),
      ('447', null, '8000.00', 'Structure'),
    ]),
    // --- 2031 : déficitaire (une perte, 139), déjà en cours -----------------
    _piece('CAI', '2031-02-01', 'Ventes 2031', [
      ('5711', '50000.00', null, 'Bar'),
      ('7011', null, '50000.00', 'Bar'),
    ]),
    _piece('ACH', '2031-03-01', 'Gros achats', [
      ('6011', '120000.00', null, 'Bar'),
      ('4011', null, '120000.00', 'Structure'),
    ]),
    _piece('OD', '2031-04-01', 'Brouillon en attente', [
      ('6011', '1000.00', null, 'Bar'),
      ('4011', null, '1000.00', 'Structure'),
    ], valide: false),
    // --- 2029 : un exercice VIDE, clôturé sans aucune pièce ----------------
    // La clôture n'écrit ni pièce de gestion ni à-nouveaux, mais elle est
    // ENREGISTRÉE : l'ouverture de 2030 est CONNUE (zéro), pas inconnue.
    _geste('demarrer', 2029),
    _geste('cloturer', 2029),
    {'t': 'ouverture', 'annee': 2030},
    // --- la liste de contrôle et les refus AVANT le démarrage ---------------
    {'t': 'etat', 'annee': 2030},
    _geste('cloturer', 2030),
    _geste('rouvrir', 2030, motif: 'Un motif assez long'),
    _geste('reprendre', 2030),
    // --- démarrer : les modules n'écrivent plus, l'inventaire oui -----------
    _geste('demarrer', 2030),
    _geste('demarrer', 2030),
    {'t': 'etat', 'annee': 2030},
    _piece('CAI', '2030-12-20', 'Module refusé', [
      ('5711', '10.00', null, 'Bar'),
      ('7011', null, '10.00', 'Bar'),
    ]),
    _piece(
      'OD',
      '2030-12-31',
      'Inventaire de fin d’année',
      [
        ('31', '12000.00', null, 'Structure'),
        ('6031', null, '12000.00', 'Bar'),
      ],
      admis: ['ouvert', 'en_cloture'],
    ),
    // --- clôturer 2030 : CL au 31/12, AN au 01/01/2031 ---------------------
    // L'ORDRE : 2031 en clôture ne peut pas être clôturé tant que 2030, en
    // clôture aussi, ne l'est pas (ses à-nouveaux en dépendent).
    _geste('cloturer', 2031), // pas encore en clôture : un autre refus
    _geste('demarrer', 2031),
    _geste('cloturer', 2031),
    _geste('reprendre', 2031),
    _geste('cloturer', 2030),
    {'t': 'etat', 'annee': 2030},
    {'t': 'balance', 'annee': 2030},
    {'t': 'balance', 'annee': 2031},
    {'t': 'ouverture', 'annee': 2031}, // 2030 clôturé : l'AN écrit
    {'t': 'ouverture', 'annee': 2030}, // exercice inaugural
    {'t': 'instantane'},
    _geste('cloturer', 2030), // déjà clôturé
    _geste('demarrer', 2030), // clôturé : pas de démarrage
    // --- 2031 : le brouillon bloque, puis la perte --------------------------
    _geste('demarrer', 2031),
    {'t': 'etat', 'annee': 2031},
    _geste('cloturer', 2031),
    {'t': 'valider_brouillons', 'annee': 2031},
    {'t': 'etat', 'annee': 2031},
    _geste('cloturer', 2031),
    {'t': 'balance', 'annee': 2031},
    {'t': 'balance', 'annee': 2032},
    {'t': 'ouverture', 'annee': 2032},
    // --- 2032 : aucun compte de gestion, aucune pièce de clôture ------------
    _geste('cloturer', 2032),
    _geste('demarrer', 2032),
    _geste('cloturer', 2032),
    // 2033 s'est ouvert avec la clôture de 2032, qui n'a AUCUNE pièce de gestion
    // et reporte les seuls soldes de bilan.
    {'t': 'ouverture', 'annee': 2033},
    {'t': 'instantane'},
    // --- la réouverture : le comptable seul, motif, dans l'ordre ------------
    _geste('rouvrir', 2030, motif: 'Un motif assez long'),
    _geste(
      'rouvrir',
      2032,
      motif: 'Un motif assez long',
      role: 'administrateur',
    ),
    _geste('rouvrir', 2032, motif: 'court'),
    _geste('rouvrir', 2031, motif: 'Un motif assez long'),
    _geste('rouvrir', 2032, motif: '  Régularisation tardive de décembre  '),
    _geste('rouvrir', 2031, motif: 'Facture fournisseur oubliée'),
    {'t': 'instantane'},
    {'t': 'balance', 'annee': 2032},
    {
      't': 'ouverture',
      'annee': 2032,
    }, // 2031 rouvert : les provisoires reviennent
    // --- re-clôturer : de nouveaux numéros, un nouvel historique ------------
    _geste('cloturer', 2031),
    _geste('cloturer', 2032),
    _geste('reprendre', 2030),
    {'t': 'instantane'},
    {'t': 'archive', 'annee': 2030},
    {'t': 'archive', 'annee': 2031},
  ];

  late Map<String, dynamic> serveur;
  late List<dynamic> serveurResultats;

  setUpAll(() async {
    serveur = await executerPhp(
      'rejouer_cloture.php',
      entree: {
        'aujourdhui': '2031-06-15',
        'exercices': [
          {'annee': 2029, 'statut': 'ouvert'},
          {'annee': 2030, 'statut': 'ouvert'},
          {'annee': 2031, 'statut': 'ouvert'},
        ],
        'cles_messages': MessagesCloture.gabarits.keys.toList(),
        'evenements': scenario,
      },
    );
    serveurResultats = serveur['resultats'] as List<dynamic>;
  });

  /* ================================================================== */
  /* Le même scénario côté poste                                         */
  /* ================================================================== */

  late AppDatabase db;
  late Directory dossierArchives;
  late List<Map<String, Object?>> poste;
  final archivesPoste = <int, Map<String, Object?>>{};

  Future<List<Map<String, Object?>>> rejouerSurLePoste() async {
    db = await baseInstallee(maintenant: DateTime(2031, 6, 15));
    final dao = ComptabiliteDao(db);
    await dao.insererExercice(
      annee: 2029,
      dateDebut: '2029-01-01',
      dateFin: '2029-12-31',
    );
    await dao.insererExercice(
      annee: 2030,
      dateDebut: '2030-01-01',
      dateFin: '2030-12-31',
    );
    await db
        .into(db.utilisateursLocal)
        .insert(
          UtilisateursLocalCompanion.insert(
            id: 'u-admin',
            login: 'admin-essai',
            nom: 'Administrateur',
            role: 'administrateur',
            droitsJson: '{}',
            sel: 's',
            empreinte: 'e',
            iterations: 1,
            dateCreation: DateTime(2026, 10, 1),
            dateMotDePasse: DateTime(2026, 10, 1),
          ),
        );
    final maintenant = DateTime(2031, 6, 15, 10);
    final moteur = MoteurComptable(dao, maintenant: () => maintenant);
    final service = ClotureExerciceLocale(
      db,
      moteur,
      maintenant: () => maintenant,
    );
    dossierArchives = await Directory.systemTemp.createTemp('archives_essai_');
    final archive = ArchiveClotureLocale(
      dao,
      service,
      () async => dossierArchives,
      maintenant: () => maintenant,
    );

    final centres = {for (final c in await dao.centres()) c.libelle: c.id};
    Future<String> exerciceDe(int annee) async =>
        (await dao.exerciceDeLAnnee(annee))!.id;
    Future<Map<String, String>> statuts() async => {
      for (final e in await dao.exercices()) '${e.annee}': e.statut.valeur,
    };

    final sortie = <Map<String, Object?>>[];
    for (final ev in scenario) {
      try {
        switch (ev['t']) {
          case 'piece':
            final admis = (ev['statuts_admis'] as List?)
                ?.map((s) => StatutExercice.depuis('$s'))
                .toSet();
            final demande = DemandePiece(
              journal: ev['journal']! as String,
              date: ev['date']! as String,
              libelle: ev['libelle']! as String,
              statutsExerciceAdmis: admis ?? const {StatutExercice.ouvert},
              lignes: [
                for (final l in ev['lignes']! as List)
                  LigneDemandee(
                    compte: (l as Map)['compte'] as String,
                    debitCentimes: centimesDepuisChaine(
                      (l['debit'] as String?) ?? '',
                    ),
                    creditCentimes: centimesDepuisChaine(
                      (l['credit'] as String?) ?? '',
                    ),
                    centreId: centres[l['centre']],
                  ),
              ],
            );
            if (ev['valide']! as bool) {
              await moteur.passerEtValider(demande, auteurId: auteurEssai);
            } else {
              await moteur.passer(demande, auteurId: auteurEssai);
            }
            sortie.add({'ok': true});
          case 'valider_brouillons':
            final id = await exerciceDe(ev['annee']! as int);
            final brouillons = [
              for (final e in await dao.toutesLesEcritures())
                if (e.exerciceId == id && !e.estValidee) e,
            ];
            final parPiece = <String, List<EcritureComptable>>{};
            for (final b in brouillons) {
              (parPiece[b.numeroPiece ?? b.id] ??= []).add(b);
            }
            for (final piece in parPiece.values) {
              await moteur.valider(piece, auteurId: auteurEssai);
            }
            sortie.add({'ok': true});
          case 'geste':
            final id = await exerciceDe(ev['annee']! as int);
            final auteur = (ev['role'] ?? 'comptable') == 'comptable'
                ? auteurEssai
                : 'u-admin';
            final apres = switch (ev['action']) {
              'demarrer' => await service.demarrer(id, auteurId: auteur),
              'reprendre' => await service.reprendreSaisie(
                id,
                auteurId: auteur,
              ),
              'cloturer' => (await dao.exercice(
                (await service.cloturer(id, auteurId: auteur)).exerciceId,
              ))!,
              'rouvrir' => await service.rouvrir(
                id,
                auteurId: auteur,
                motif: (ev['motif'] as String?) ?? '',
              ),
              _ => throw StateError('geste inconnu'),
            };
            final c = await service.clotureActive(apres.id);
            sortie.add({
              'ok': true,
              'statut': apres.statut.valeur,
              'cloture': c == null
                  ? null
                  : {
                      'piece_cloture': c.pieceCloture,
                      'piece_a_nouveaux': c.pieceANouveaux,
                      'resultat': chaineDepuisCentimes(c.resultatCentimes),
                    },
              'statuts': await statuts(),
            });
          case 'etat':
            final id = await exerciceDe(ev['annee']! as int);
            final e = await service.etat(id);
            sortie.add({
              'ok': true,
              'blocages': [for (final b in e.blocages) b.code],
              'avertissements': [for (final a in e.avertissements) a.code],
              'conditions_reunies': e.conditionsReunies,
              'resultat_a_reporter': chaineDepuisCentimes(
                e.resultatAReporterCentimes,
              ),
              'compte_destination': e.compteDeDestination,
              'statut': e.statut,
            });
          case 'balance':
            final annee = ev['annee']! as int;
            final b = balanceDe(annee, await service.donneesDesEtats());
            sortie.add({
              'ok': true,
              'a_nouveaux_provisoires_de': b.aNouveauxProvisoiresDe,
              'lignes': [
                for (final l in b.lignes)
                  {
                    'numero_compte': l.numeroCompte,
                    'libelle': l.libelle,
                    'classe': l.classe,
                    'debit': chaineDepuisCentimes(l.debitCentimes),
                    'credit': chaineDepuisCentimes(l.creditCentimes),
                  },
              ],
            });
          case 'ouverture':
            final annee = ev['annee']! as int;
            final o = reportOuverture(annee, await service.donneesDesEtats());
            sortie.add({
              'ok': true,
              'soldes': {
                for (final e in o.soldes.entries)
                  if (e.value != 0) e.key: chaineDepuisCentimes(e.value),
              },
              'provisoire': o.provisoire,
              'annee': o.annee,
              'connu': o.connu,
            });
          case 'archive':
            final annee = ev['annee']! as int;
            final c = (await service.clotureActive(await exerciceDe(annee)))!;
            final faite = await archive.archiver(
              c.id,
              entete: const EnteteEtablissement(),
            );
            final dossier = Directory(
              '${dossierArchives.path}/${faite.archiveChemin}',
            );
            archivesPoste[annee] = {
              'verifiee': await archive.verifier(faite),
              'ecritures': File(
                '${dossier.path}/ecritures.csv',
              ).readAsBytesSync(),
              'balance': File('${dossier.path}/balance.csv').readAsBytesSync(),
              'fichiers': (await dossier.list().toList())
                  .map((f) => f.uri.pathSegments.last)
                  .toList(),
            };
            sortie.add({'ok': true});
          case 'instantane':
            final lignes = <String, List<Map<String, Object?>>>{};
            for (final e in await dao.exercices()) {
              lignes['${e.annee}'] = [
                for (final l in await dao.lignesPourArchive(e.id))
                  {
                    'journal': l.codeJournal,
                    'numero_piece': l.numeroPiece,
                    'date': l.dateEcriture,
                    'compte': l.numeroCompte,
                    'centre': l.libelleCentre,
                    'libelle': l.libelle,
                    'debit': chaineDepuisCentimes(l.debitCentimes),
                    'credit': chaineDepuisCentimes(l.creditCentimes),
                    'statut': l.statut,
                    'contrepasse': l.pieceContrepassee != null,
                  },
              ];
            }
            final exercices = {for (final e in await dao.exercices()) e.id: e};
            sortie.add({
              'ok': true,
              'statuts': await statuts(),
              'lignes': lignes,
              'clotures': [
                for (final c in (await service.clotures()).reversed)
                  {
                    'annee': exercices[c.exerciceId]!.annee,
                    'piece_cloture': c.pieceCloture,
                    'piece_a_nouveaux': c.pieceANouveaux,
                    'resultat': chaineDepuisCentimes(c.resultatCentimes),
                    'active': c.estActive,
                    'motif': c.motifReouverture,
                  },
              ],
            });
        }
      } on RefusComptable catch (e) {
        sortie.add({'refus': true, 'message': e.message});
      }
    }
    return sortie;
  }

  setUpAll(() async {
    poste = await rejouerSurLePoste();
  });

  tearDownAll(() async {
    await db.close();
    if (dossierArchives.existsSync()) {
      await dossierArchives.delete(recursive: true);
    }
  });

  /* ================================================================== */
  /* Les constats                                                        */
  /* ================================================================== */

  String cle(Map<String, Object?> l) =>
      '${l['journal']}|${l['numero_piece'] ?? ''}|${l['date']}|${l['compte']}|'
      '${l['centre']}|${l['debit']}|${l['credit']}|${l['statut']}|'
      '${l['contrepasse']}|${l['libelle']}';

  /// Les lignes d'un exercice, triées pour une comparaison d'ENSEMBLES : deux
  /// lignes identiques n'ont pas d'ordre propre.
  List<String> lignesTriees(Object? brut) =>
      [for (final l in (brut as List).cast<Map<String, dynamic>>()) cle(l)]
        ..sort();

  test('le scénario du serveur a bien rendu un résultat par événement', () {
    expect(serveurResultats, hasLength(scenario.length));
    expect(poste, hasLength(scenario.length));
    // Garde contre un scénario qui ne ferait rien : de vraies clôtures, de vrais
    // refus, une vraie réouverture, de vraies archives.
    final refus = serveurResultats.where(
      (r) => (r as Map).containsKey('refus'),
    );
    expect(refus.length, greaterThanOrEqualTo(14));
    final statutsVus = <String>{
      for (final r in serveurResultats)
        if ((r as Map)['statut'] != null) r['statut'] as String,
    };
    expect(statutsVus, containsAll(['ouvert', 'en_cloture', 'cloture']));
  });

  test('chaque événement rend le MÊME verdict : réussi, ou refusé aux mêmes '
      'mots, et les mêmes statuts d’exercice', () {
    for (var i = 0; i < scenario.length; i++) {
      final s = serveurResultats[i] as Map<String, dynamic>;
      final p = poste[i];
      final contexte = 'événement $i : ${jsonEncode(scenario[i])}';
      if (s.containsKey('refus')) {
        expect(p['refus'], isTrue, reason: '$contexte — le poste a accepté');
        expect(p['message'], s['message'], reason: contexte);
        continue;
      }
      expect(
        p.containsKey('refus'),
        isFalse,
        reason: '$contexte — ${p['message']}',
      );
      if (scenario[i]['t'] == 'geste') {
        expect(p['statut'], s['statut'], reason: contexte);
        expect(p['statuts'], s['statuts'], reason: contexte);
        expect(p['cloture'], s['cloture'], reason: contexte);
      }
    }
  });

  test('la liste de contrôle est la même : blocages, avertissements, résultat '
      'à reporter, compte de destination', () {
    var vus = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'etat') continue;
      vus++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      expect(poste[i], s, reason: 'état $i : ${jsonEncode(scenario[i])}');
    }
    expect(vus, greaterThanOrEqualTo(4));
    // Un brouillon bloque ; un exercice sans impôt avertit.
    expect(
      serveurResultats
          .where((r) => (r as Map)['blocages'] != null)
          .map((r) => (r as Map)['blocages'] as List)
          .any((b) => b.contains('ecritures_en_brouillon')),
      isTrue,
    );
  });

  test('la balance est la même, à-nouveaux provisoires et clôture compris', () {
    var vues = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'balance') continue;
      vues++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      final p = poste[i];
      expect(
        p['a_nouveaux_provisoires_de'],
        s['a_nouveaux_provisoires_de'],
        reason: 'balance $i',
      );
      expect(p['lignes'], s['lignes'], reason: 'balance $i');
    }
    expect(vues, 5);
  });

  test('les soldes d’OUVERTURE (le report à nouveau) sont les mêmes : écrits '
      'au journal AN, provisoires, ou nuls mais connus', () {
    var vues = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'ouverture') continue;
      vues++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      // PHP écrit `[]` pour une table vide, là où Dart écrit `{}`.
      final soldes = s['soldes'];
      expect(
        poste[i]['soldes'],
        soldes is List && soldes.isEmpty ? <String, Object?>{} : soldes,
        reason: 'ouverture $i',
      );
      expect(poste[i]['provisoire'], s['provisoire'], reason: 'ouverture $i');
      expect(poste[i]['annee'], s['annee'], reason: 'ouverture $i');
      expect(poste[i]['connu'], s['connu'], reason: 'ouverture $i');
    }
    expect(vues, 6);
    final provisoires = [
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['t'] == 'ouverture')
          (serveurResultats[i] as Map)['provisoire'],
    ];
    expect(provisoires, contains(true));
    expect(provisoires, contains(false));
  });

  test('TOUTES les pièces — gestion soldée centre par centre, 131 ou 139, '
      'à-nouveaux, contre-passations — sont les mêmes, au centime', () {
    var vus = 0;
    for (var i = 0; i < scenario.length; i++) {
      if (scenario[i]['t'] != 'instantane') continue;
      vus++;
      final s = serveurResultats[i] as Map<String, dynamic>;
      final p = poste[i];
      expect(p['statuts'], s['statuts'], reason: 'instantané $i');
      final lignesServeur = s['lignes'] as Map<String, dynamic>;
      final lignesPoste =
          p['lignes']! as Map<String, List<Map<String, Object?>>>;
      expect(lignesPoste.keys.toSet(), lignesServeur.keys.toSet());
      for (final annee in lignesServeur.keys) {
        expect(
          lignesTriees(lignesPoste[annee]),
          lignesTriees(lignesServeur[annee]),
          reason: 'instantané $i, exercice $annee',
        );
      }
      // Toutes les clôtures partagent l'horloge du banc : leur ordre n'est pas
      // celui de la date, on compare des ENSEMBLES.
      List<String> historique(Object? brut) => [
        for (final c in (brut as List).cast<Map<String, dynamic>>())
          '${c['annee']}|${c['piece_cloture']}|${c['piece_a_nouveaux']}|'
              '${c['resultat']}|${c['active']}|${c['motif']}',
      ]..sort();
      expect(
        historique(p['clotures']),
        historique(s['clotures']),
        reason: 'clôtures de $i',
      );
    }
    expect(vus, 4);

    // Le dernier instantané porte bien un historique : clôtures rouvertes ET
    // actives, des pièces CL et AN, des contre-passations, un 139.
    final dernier =
        serveurResultats.where((r) => (r as Map)['clotures'] != null).last
            as Map<String, dynamic>;
    final clotures = (dernier['clotures'] as List).cast<Map<String, dynamic>>();
    expect(clotures.where((c) => c['active'] == false), isNotEmpty);
    expect(clotures.where((c) => c['active'] == true), isNotEmpty);
    final tout = (dernier['lignes'] as Map<String, dynamic>).values
        .expand((l) => l as List)
        .cast<Map<String, dynamic>>();
    expect(tout.any((l) => l['journal'] == 'CL'), isTrue);
    expect(tout.any((l) => l['journal'] == 'AN'), isTrue);
    expect(tout.any((l) => l['contrepasse'] == true), isTrue);
    expect(tout.any((l) => l['compte'] == '139'), isTrue);
    expect(tout.any((l) => l['compte'] == '131'), isTrue);
  });

  test('l’archive : mêmes colonnes, mêmes lignes d’écritures, MÊME balance.csv '
      'octet pour octet, même manifeste', () {
    final archives = {
      for (var i = 0; i < scenario.length; i++)
        if (scenario[i]['t'] == 'archive')
          scenario[i]['annee']! as int:
              serveurResultats[i] as Map<String, dynamic>,
    };
    expect(archives.keys, [2030, 2031]);

    List<String> lignes(List<int> octets) {
      // `utf8.decode` retire le BOM : on le constate sur les octets.
      expect(octets.sublist(0, 3), [0xEF, 0xBB, 0xBF], reason: 'BOM UTF-8');
      return const LineSplitter().convert(utf8.decode(octets));
    }

    for (final MapEntry(key: annee, value: s) in archives.entries) {
      final p = archivesPoste[annee]!;
      expect(p['verifiee'], isTrue);
      expect(s['verifiee'], isTrue);
      // Les fichiers du dossier : ceux du serveur (le manifeste en plus).
      expect((p['fichiers']! as List).toSet(), {
        ...(s['fichiers'] as List),
        'manifeste.json',
      });

      // balance.csv : OCTET POUR OCTET.
      expect(
        p['balance'],
        base64Decode(s['balance_csv'] as String),
        reason: '$annee',
      );

      // ecritures.csv : l'en-tête, puis les lignes SANS leurs deux dernières
      // colonnes (date de saisie, login) — l'horloge et le compte du banc ne
      // sont pas ceux du serveur.
      final lp = lignes(p['ecritures']! as List<int>);
      final ls = lignes(base64Decode(s['ecritures_csv'] as String));
      expect(lp.first, ls.first, reason: 'en-tête $annee');
      expect(lp.first.split(';'), ArchiveClotureLocale.colonnesEcritures);
      String sansSaisie(String l) {
        final colonnes = _decouper(l);
        return colonnes.sublist(0, colonnes.length - 2).join('\u0001');
      }

      expect(
        [for (final l in lp.skip(1)) sansSaisie(l)]..sort(),
        [for (final l in ls.skip(1)) sansSaisie(l)]..sort(),
        reason: 'écritures $annee',
      );
      expect(lp.length, greaterThan(10));
    }
  });

  test('les phrases de la clôture sont EXACTEMENT celles du serveur, des deux '
      'côtés', () {
    final messages = (serveur['messages'] as Map<String, dynamic>)
        .cast<String, String>();
    expect(messages.keys.toSet(), MessagesCloture.gabarits.keys.toSet());
    for (final e in messages.entries) {
      expect(MessagesCloture.gabarits[e.key], e.value, reason: e.key);
      // Une clé absente du serveur rend la clé elle-même : plus un texte.
      expect(e.value, isNot(e.key));
    }

    // Aucune phrase du serveur n'échappe au poste : chaque clé de langue que
    // `ClotureExerciceService` et `EtatClotureService` emploient est portée.
    String source(String chemin) => File(chemin).readAsStringSync();
    final api = '../tatacora-api/app/Domain/Comptabilite/Services';
    final cles = <String>{
      for (final f in ['ClotureExerciceService.php', 'EtatClotureService.php'])
        for (final m in RegExp(
          r"__\('((?:comptabilite|pwa\.comptabilite\.motifs)\.[a-z_0-9]+)'",
        ).allMatches(source('$api/$f')))
          m.group(1)!,
    };
    expect(cles, isNotEmpty, reason: 'le balayage serait vide');
    expect(cles.difference(MessagesCloture.gabarits.keys.toSet()), isEmpty);

    // Les gestes de l'onglet : chaque `comptabilite_pwa.*` de la vue (hors
    // l'alerte « postes non à jour » et l'ouverture d'exercice, qui ont leur
    // propre écran) est portée.
    final vue = source(
      '../tatacora-api/resources/views/pwa/comptabilite/onglets/clotures.blade.php',
    );
    final cleVues =
        <String>{
          for (final m in RegExp(
            r"__\('(comptabilite_pwa\.[a-z_0-9]+)'",
          ).allMatches(vue))
            m.group(1)!,
        }..removeWhere(
          (k) =>
              k.startsWith('comptabilite_pwa.alerte_postes') ||
              k.startsWith('comptabilite_pwa.exercice_ouvr'),
        );
    expect(cleVues, isNotEmpty);
    expect(cleVues.difference(MessagesCloture.gabarits.keys.toSet()), isEmpty);
  });

  test('les constantes de la clôture sont celles du serveur : journaux, '
      'centre, rôle, motif, classes, colonnes de l’archive', () {
    final c = serveur['constantes'] as Map<String, dynamic>;
    expect(journalDeCloture, c['journal_cloture']);
    expect(journalANouveaux, c['journal_a_nouveaux']);
    expect(journauxReserves, c['journaux_reserves']);
    expect(centreDeCloture, c['centre']);
    expect(roleReouverture, c['role_reouverture']);
    expect(longueurMinMotifReouverture, c['motif_min']);
    expect(classesDeGestion, c['classes_gestion']);
    expect(classesDeBilan, c['classes_bilan']);
    expect(ArchiveClotureLocale.colonnesEcritures, c['colonnes_ecritures']);
    expect(ArchiveClotureLocale.colonnesBalance, c['colonnes_balance']);
    expect([
      ArchiveClotureLocale.fichierEcritures,
      ArchiveClotureLocale.fichierBalance,
      ArchiveClotureLocale.fichierEtats,
      ArchiveClotureLocale.fichierManifeste,
    ], c['fichiers']);
    // Les deux journaux que SEULE la clôture écrit, avec leurs libellés.
    expect(
      ComptesSyscohada.journauxDeCloture,
      (serveur['journaux'] as Map<String, dynamic>).cast<String, String>(),
    );
  });
}

/// Découpe une ligne CSV `;` à la PHP : un champ entre guillemets peut porter
/// des `;`, et `""` y vaut un guillemet.
List<String> _decouper(String ligne) {
  final champs = <String>[];
  final courant = StringBuffer();
  var entre = false;
  for (var i = 0; i < ligne.length; i++) {
    final c = ligne[i];
    if (entre) {
      if (c == '"' && i + 1 < ligne.length && ligne[i + 1] == '"') {
        courant.write('"');
        i++;
      } else if (c == '"') {
        entre = false;
      } else {
        courant.write(c);
      }
    } else if (c == '"') {
      entre = true;
    } else if (c == ';') {
      champs.add(courant.toString());
      courant.clear();
    } else {
      courant.write(c);
    }
  }
  champs.add(courant.toString());
  return champs;
}
