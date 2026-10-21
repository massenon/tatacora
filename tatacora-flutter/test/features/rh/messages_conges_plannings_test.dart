@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/rh/data/conges_plannings_dao.dart';
import 'package:tatacora_flutter/features/rh/domain/entities/conge_planning.dart';

/// Les phrases de refus du poste sont CELLES du serveur : `lang/fr/rh.php`,
/// EXÉCUTÉ par PHP (les chaînes y sont concaténées et commentées — une
/// recherche de texte brut ne les retrouverait pas), avec ses paramètres
/// remplacés comme le fait `__()`.
///
/// Les types et statuts de congé sont relus de la même façon
/// (`lang/fr/rh_conges_pwa.php`, `Conge::TYPES`).
void main() {
  Map<String, dynamic> fichierDeLangue(String nom) {
    final r = Process.runSync('php', [
      '-r',
      'echo json_encode(require "lang/fr/$nom.php");',
    ], workingDirectory: '../tatacora-api');
    if (r.exitCode != 0) {
      fail('PHP n’a pas pu lire lang/fr/$nom.php : ${r.stderr}');
    }
    return jsonDecode(r.stdout as String) as Map<String, dynamic>;
  }

  String traduire(String modele, Map<String, String> params) =>
      params.entries.fold(modele, (t, e) => t.replaceAll(':${e.key}', e.value));

  final rh = fichierDeLangue('rh');
  final pwa = fichierDeLangue('rh_conges_pwa');

  test('les refus de RG-13 et de RG-14 sont repris au mot', () {
    // Prouvé non vide : une extraction ratée rendrait tout vrai à vide.
    expect(rh, isNotEmpty);
    expect(rh['planning_chevauchement'], isNotNull);

    expect(
      MessagesCongesPlannings.chevauchement,
      traduire(rh['planning_chevauchement'] as String, {}),
    );
    expect(
      MessagesCongesPlannings.horsEffectif('parti'),
      traduire(rh['employe_hors_effectif'] as String, {'statut': 'parti'}),
    );
    expect(
      MessagesCongesPlannings.enConge('2026-10-22'),
      traduire(rh['employe_en_conge'] as String, {'date': '2026-10-22'}),
    );
    expect(
      MessagesCongesPlannings.dejaTraite,
      traduire(rh['conge_deja_traite'] as String, {}),
    );
    expect(
      MessagesCongesPlannings.preavisInsuffisant(reel: 12, exige: '15'),
      traduire(rh['preavis_insuffisant'] as String, {
        'reel': '12',
        'exige': '15',
      }),
    );
    expect(
      MessagesCongesPlannings.couvertureInsuffisante(restants: 1, minimum: '2'),
      traduire(rh['couverture_insuffisante'] as String, {
        'restants': '1',
        'minimum': '2',
      }),
    );
    expect(
      MessagesCongesPlannings.parametreAbsent(
        CongesPlanningsDao.cleDelaiPreavis,
      ),
      traduire(rh['parametre_absent'] as String, {
        'cle': CongesPlanningsDao.cleDelaiPreavis,
      }),
    );
  });

  test('les natures et les statuts de congé sont ceux du serveur, avec leurs '
      'libellés', () {
    final source = File(
      '../tatacora-api/app/Domain/Rh/Models/Conge.php',
    ).readAsStringSync();
    final bloc = RegExp(r'TYPES\s*=\s*\[([^\]]*)\]').firstMatch(source);
    expect(bloc, isNotNull, reason: 'Conge::TYPES introuvable');
    final serveur = RegExp(
      "'([^']+)'",
    ).allMatches(bloc!.group(1)!).map((m) => m.group(1)!).toList();
    expect(serveur, isNotEmpty);
    expect(TypeConge.values.map((t) => t.code).toList(), serveur);

    for (final t in TypeConge.values) {
      expect(t.libelle, pwa['type_${t.code}'], reason: 'type ${t.code}');
    }
    for (final s in StatutConge.values) {
      expect(s.libelle, pwa['statut_${s.code}'], reason: 'statut ${s.code}');
    }
  });

  test('aucune phrase de refus ne porte d’apostrophe typographique', () {
    final phrases = [
      MessagesCongesPlannings.chevauchement,
      MessagesCongesPlannings.horsEffectif('parti'),
      MessagesCongesPlannings.enConge('2026-10-22'),
      MessagesCongesPlannings.dejaTraite,
      MessagesCongesPlannings.preavisInsuffisant(reel: 1, exige: '2'),
      MessagesCongesPlannings.couvertureInsuffisante(restants: 1, minimum: '2'),
      MessagesCongesPlannings.parametreAbsent('x'),
      MessagesCongesPlannings.heureIllisible,
      MessagesCongesPlannings.heureFinAvantDebut,
    ];
    for (final p in phrases) {
      expect(p, isNot(contains('’')), reason: p);
    }
  });
}
