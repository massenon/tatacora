@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/comptabilite/data/comptabilite_dao.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/comptes_syscohada.dart';
import 'package:tatacora_flutter/features/comptabilite/domain/correspondance_comptes.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/ecran_correspondance_comptes.dart';
import 'package:tatacora_flutter/features/comptabilite/presentation/widgets/onglets_plan_clotures.dart';
import 'package:tatacora_flutter/features/parametres/data/parametres_depot_local.dart';
import 'package:tatacora_flutter/features/parametres/domain/enregistrer_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/resultats_parametres.dart';

import 'support/outils_comptabilite.dart';

/// La CORRESPONDANCE rôle -> compte (26/10/2026, décision du PO : « on peut
/// impérativement modifier les comptes sur poste et le web »), CONFRONTÉE au
/// serveur par EXÉCUTION de PHP — jamais deux listes qui divergent.
///
/// 1. `exporter_correspondance.php` : les rôles (groupe, libellé, aide,
///    préfixes admis, clé de paramètre, défaut) et les gabarits de langue de
///    l'écran, relus de `RolesCorrespondance` et de
///    `lang/fr/comptes_correspondance.php`.
/// 2. `rejouer_correspondance.php` : la VALIDATION et la LECTURE, rejouées par
///    le vrai `EnregistrerParametreService` et le vrai
///    `CorrespondanceComptesService` ; le poste joue le MÊME scénario par
///    `EnregistrerParametres` et `ComptabiliteDao.compteDuRole`. Chaque refus
///    est comparé à sa PHRASE, chaque compte retenu à son numéro.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Map<String, dynamic> export;

  setUpAll(() async {
    export = await executerPhp('exporter_correspondance.php');
  });

  group('Les rôles et les phrases sont ceux du serveur', () {
    test('quinze rôles relus du serveur — un export tronqué échouerait', () {
      final roles = (export['roles'] as List).cast<Map<String, dynamic>>();
      expect(roles, hasLength(15));
      expect(RolesCorrespondance.roles, hasLength(15));
      expect(export['groupes'], RolesCorrespondance.groupes);
    });

    test('chaque rôle : même groupe, libellé, aide, préfixes, clé et défaut, '
        'dans le même ordre', () {
      final roles = (export['roles'] as List).cast<Map<String, dynamic>>();
      expect(
        [for (final r in RolesCorrespondance.roles) r.code],
        [for (final r in roles) r['role']],
      );
      for (final s in roles) {
        final l = RolesCorrespondance.parCode(s['role'] as String)!;
        expect(l.groupe, s['groupe'], reason: l.code);
        expect(l.libelle, s['libelle'], reason: l.code);
        expect(l.aide, s['aide'], reason: l.code);
        expect(l.prefixes, (s['prefixes'] as List).cast<String>());
        expect(l.cle, s['cle'], reason: l.code);
        expect(l.defaut, s['defaut'], reason: l.code);
      }
    });

    test('chaque rôle est un rôle de ComptesSyscohada, et les charges n’en '
        'sont pas', () {
      for (final r in RolesCorrespondance.roles) {
        expect(ComptesSyscohada.tous, contains(r.code));
      }
      for (final charge in const [
        'ACHATS_MARCHANDISES',
        'ELECTRICITE',
        'EAU',
        'LOCATION_MATERIEL_TRANSPORT',
        'TELEPHONE_INTERNET',
      ]) {
        expect(RolesCorrespondance.parCode(charge), isNull, reason: charge);
      }
    });

    test('chaque gabarit de langue est EXACTEMENT celui du serveur, dans les '
        'deux sens', () {
      final serveur = (export['gabarits'] as Map<String, dynamic>)
          .cast<String, String>();
      expect(serveur, isNotEmpty);
      expect(
        MessagesCorrespondance.gabarits.keys.toSet(),
        serveur.keys.toSet(),
      );
      for (final e in serveur.entries) {
        expect(MessagesCorrespondance.gabarits[e.key], e.value, reason: e.key);
      }
    });

    test('les mots de la modale, du lien et du retour — écrits en littéraux '
        'dans l’écran — sont ceux du serveur', () {
      final g = (export['gabarits'] as Map<String, dynamic>)
          .cast<String, String>();
      expect(TextesModaleCorrespondance.titre, g['modale_titre']);
      expect(TextesModaleCorrespondance.champCompte, g['champ_compte']);
      expect(
        TextesModaleCorrespondance.champCompteAide,
        g['champ_compte_aide'],
      );
      expect(
        '${TextesModaleCorrespondance.roleAttendu}X.',
        g['role_attendu']!.replaceAll(':attendu', 'X'),
      );
      expect(
        '${TextesModaleCorrespondance.defautRappel}7073.',
        g['defaut_rappel']!.replaceAll(':defaut', '7073'),
      );
      expect(TextesModaleCorrespondance.annuler, g['annuler']);
      expect(TextesModaleCorrespondance.retablir, g['retablir']);
      expect(TextesModaleCorrespondance.enregistrer, g['enregistrer']);
      expect(TextesOngletsPlanClotures.correspondance, g['lien_hub']);
      expect(TextesCorrespondancePoste.retourHub, export['retour_hub']);
    });

    test('« ce que le rôle attend » : la phrase du serveur', () {
      expect(RolesCorrespondance.attendu(['7']), 'est de la classe 7');
      expect(RolesCorrespondance.attendu(['443']), 'commence par 443');
      expect(
        RolesCorrespondance.attendu(['7', '443']),
        'est de la classe 7 ou commence par 443',
      );
    });
  });

  group('La validation et la lecture : le MÊME scénario que le serveur', () {
    // Pour chaque rôle : le défaut, le vide, des comptes de toutes les natures
    // de refus (absent du plan, mauvaise classe, division, hors format) et des
    // comptes admis.
    const candidats = <String>[
      '',
      '7999',
      '6011',
      '4452',
      '57',
      '70',
      '13',
      '7',
      '07073',
      '70739',
      'abcd',
      ' 7078 ',
      '7078',
      '4112',
      '4012',
      '4192',
      '4433',
      '4434',
      '445',
      '5212',
      '5712',
      '552',
      '558',
      '131',
      '139',
    ];

    final ops = <Map<String, Object?>>[
      for (final role in RolesCorrespondance.roles) ...[
        {'op': 'compte', 'role': role.code},
        for (final n in [role.defaut, ...candidats]) ...[
          {
            'op': 'enregistrer',
            'valeurs': {role.cle: n},
          },
          {'op': 'compte', 'role': role.code},
          // Le retour au défaut, pour que chaque candidat parte du même état.
          {
            'op': 'enregistrer',
            'valeurs': {role.cle: ''},
          },
        ],
      ],
      // Un lot refusé n'écrit AUCUNE de ses clés.
      {
        'op': 'enregistrer',
        'valeurs': {'compte_caisse': '5712', 'compte_banque': '6011'},
      },
      {'op': 'compte', 'role': 'CAISSE'},
      // Un lot accepté les écrit toutes, et `comptes_lus` rend le choisi puis
      // le défaut (les pièces d'avant le changement y sont restées).
      {
        'op': 'enregistrer',
        'valeurs': {
          'compte_caisse': '5712',
          'compte_tva_facturee_prestations': '4433',
        },
      },
      {'op': 'compte', 'role': 'CAISSE'},
      {'op': 'compte', 'role': 'TVA_FACTUREE_PRESTATIONS'},
      {'op': 'comptes_lus', 'role': 'TVA_FACTUREE_PRESTATIONS'},
      {'op': 'comptes_lus', 'role': 'PRODUIT_LOCATIONS'},
    ];

    late List<dynamic> serveur;
    late List<Map<String, Object?>> local;

    setUpAll(() async {
      final r = await executerPhp(
        'rejouer_correspondance.php',
        entree: {'aujourdhui': '2031-06-15', 'ops': ops},
      );
      serveur = r['resultats'] as List<dynamic>;
      local = await _jouerLocalement(ops);
    });

    test('chaque opération a un résultat des deux côtés', () {
      expect(serveur, hasLength(ops.length));
      expect(local, hasLength(ops.length));
      expect(ops.length, greaterThan(1000));
    });

    test(
      'chaque résultat est identique au serveur, opération par opération',
      () {
        final ecarts = <String>[];
        for (var i = 0; i < ops.length; i++) {
          final s = _normaliser(ops[i], serveur[i] as Map<String, dynamic>);
          final l = _normaliser(ops[i], local[i]);
          if (jsonEncode(s) != jsonEncode(l)) {
            ecarts.add('op #$i ${ops[i]}\n  serveur : $s\n  poste   : $l');
          }
        }
        expect(ecarts, isEmpty, reason: ecarts.take(8).join('\n'));
      },
    );

    test('le scénario n’est pas vert à vide : des refus de TOUTES les causes '
        'ET des comptes retenus', () {
      final refus = <String>{
        for (var i = 0; i < ops.length; i++)
          if (ops[i]['op'] == 'enregistrer' &&
              (serveur[i] as Map).containsKey('refus'))
            (serveur[i] as Map)['refus'] as String,
      };
      // Format, absent du plan, mauvaise classe, division : quatre familles.
      expect(
        refus.any((p) => p.startsWith('Numéro de compte invalide')),
        isTrue,
      );
      expect(refus.any((p) => p.contains('n’existe pas au plan')), isTrue);
      expect(refus.any((p) => p.contains('ne convient pas au rôle')), isTrue);
      expect(refus.any((p) => p.contains('est une division')), isTrue);
      expect(refus.length, greaterThanOrEqualTo(60));

      final retenus = {
        for (var i = 0; i < ops.length; i++)
          if (ops[i]['op'] == 'compte') (serveur[i] as Map)['compte'],
      };
      // Le défaut ET des comptes choisis.
      expect(retenus, containsAll(<String>['5711', '7073', '5712', '4433']));
      // Le lot refusé n'a rien écrit : la caisse y vaut encore son défaut.
      final iLot = ops.indexWhere(
        (o) =>
            o['op'] == 'enregistrer' &&
            (o['valeurs']! as Map).containsKey('compte_banque') &&
            (o['valeurs']! as Map).containsKey('compte_caisse'),
      );
      expect((serveur[iLot] as Map).containsKey('refus'), isTrue);
      expect((serveur[iLot + 1] as Map)['compte'], '5711');
      // `comptes_lus` : le choisi, puis le défaut.
      final lus = serveur.lastIndexWhere(
        (r) => r is Map && r.containsKey('comptes'),
      );
      expect((serveur[lus] as Map)['comptes'], ['7073']);
      expect((serveur[lus - 1] as Map)['comptes'], ['4433', '4432']);
    });
  });
}

/// L'écart de représentation, nommé : un rôle vidé alors qu'aucune valeur
/// n'était posée. Le serveur crée une ligne vide et la déclare modifiée ; le
/// poste n'a rien à supprimer. Les deux lisent « le défaut » — c'est la LECTURE
/// qui est comparée, pas ce détail de stockage.
Map<String, Object?> _normaliser(
  Map<String, Object?> op,
  Map<String, dynamic> r,
) {
  final copie = Map<String, Object?>.from(r);
  if (op['op'] == 'enregistrer') {
    final valeurs = (op['valeurs']! as Map).values;
    if (valeurs.every((v) => v == '')) copie.remove('modifiees');
  }
  return copie;
}

/// Joue le scénario sur le poste : `EnregistrerParametres` (le seul chemin
/// d'écriture) et `ComptabiliteDao.compteDuRole` (la lecture du moteur).
Future<List<Map<String, Object?>>> _jouerLocalement(
  List<Map<String, Object?>> ops,
) async {
  final db = AppDatabase.enMemoire();
  addTearDown(db.close);
  await db.customStatement('SELECT 1');
  await semerAuteur(db);
  await baseInstalleeSur(db, DateTime(2031, 6, 15));

  final compta = ComptabiliteDao(db);
  final cas = EnregistrerParametres(
    ParametresDepotLocal(db),
    verifierCompte: compta.verifierCompteDuRole,
  );

  final resultats = <Map<String, Object?>>[];
  for (final op in ops) {
    switch (op['op']) {
      case 'enregistrer':
        final valeurs = (op['valeurs']! as Map).cast<String, Object?>();
        final r = await cas.executer(
          valeurs,
          peutEcrire: true,
          auteurId: auteurEssai,
        );
        resultats.add(switch (r) {
          EcritureAcceptee(:final modifiees) => {
            'ok': true,
            'modifiees': modifiees,
          },
          EcritureRefusee(:final motif, :final parCle) => {
            'refus': parCle.isNotEmpty ? parCle.values.first : motif,
          },
        });
      case 'compte':
        resultats.add({
          'ok': true,
          'compte': await compta.compteDuRole(op['role']! as String),
        });
      case 'comptes_lus':
        final role = RolesCorrespondance.parCode(op['role']! as String)!;
        final choisi = await compta.compteDuRole(role.code);
        resultats.add({
          'ok': true,
          'comptes': {choisi, role.defaut}.toList(),
        });
      default:
        fail('Opération inconnue : ${op['op']}');
    }
  }
  return resultats;
}
