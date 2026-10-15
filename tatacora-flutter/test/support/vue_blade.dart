import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// La VUE BLADE de la PWA, lue par les tests — le maître du client Flutter
/// depuis le 10/09/2026 (PA-182, PA-183). `prototype_v2/` est une ancienne
/// version : aucun test ne la lit plus.
///
/// Trois sources, toutes dans `tatacora-api/` :
///
/// - les vues `resources/views/pwa/**.blade.php` ;
/// - les libellés `lang/fr/*.php` et `lang/fr.json`, **résolus par PHP** — la
///   sémantique exacte de Laravel, sans analyseur écrit à la main qui
///   pourrait se tromper en silence (même script que
///   `tool/conformite_blade/t-blade-flutter.js`) ;
/// - ce que la PWA sert (`public/assets/`) et son code (`app/Pwa/`,
///   `app/Domain/`), lus par [VueBlade.fichier].
///
/// ## Tout est ÉCHEC, jamais saut
///
/// Un fichier introuvable, ou PHP absent, fait rougir le test qui lit. Une
/// garde dont la source manque passe à vide, et le vert qu'elle affiche est le
/// plus dangereux du dépôt.
///
/// ## Éprouver un test par mutation
///
/// `VUE_BLADE_API` désigne une COPIE de `tatacora-api` : on mute la copie, on
/// relance le test, on constate qu'il rougit. On ne retouche jamais le dépôt
/// pour prouver une garde.
abstract final class VueBlade {
  /// La racine de `tatacora-api`, vue depuis `tatacora_flutter/`.
  static String get racine =>
      Platform.environment['VUE_BLADE_API'] ?? '../tatacora-api';

  /// Un fichier de `tatacora-api/`, lu tel quel.
  static String fichier(String relatif, {String? role}) {
    final f = File('$racine/$relatif');
    if (!f.existsSync()) {
      fail(
        'Introuvable : tatacora-api/$relatif'
        '${role == null ? '' : ' — $role'}.\n'
        'La vue Blade est le maître (PA-183) : sans elle, la conformité ne se '
        'vérifie pas, elle se suppose.',
      );
    }
    return f.readAsStringSync();
  }

  /// Le gabarit BRUT d'une vue — `brute('crm/clients-creances')`.
  static String brute(String vue) =>
      fichier('resources/views/pwa/$vue.blade.php', role: 'vue Blade');

  /// La vue, ses appels de langue remplacés par leur valeur (voir [resoudre]).
  static String resolue(String vue) => resoudre(brute(vue));

  /// Un libellé de langue — `libelle('pwa.clients.titre')`. `null` si la clé
  /// n'existe pas ou désigne un groupe.
  static String? libelle(String cle) {
    final v = langue()[cle];
    return v is String ? v : null;
  }

  /// Les libellés d'un groupe — `groupe('accueil_pwa.periodes')`.
  static List<String> groupe(String cle) {
    final v = langue()[cle];
    return v is List<String> ? v : const <String>[];
  }

  static const _cle = r'([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)';

  /// Remplace chaque appel de langue par sa valeur :
  ///
  /// - `{{ __('k') }}` et `{!! __('k') !!}` → le texte lui-même, pour qu'une
  ///   expression régulière qui lit `<th>…</th>` y trouve le libellé ;
  /// - `@lang('k')` → le texte ;
  /// - `__('k')` restant (dans un bloc `@php`, un attribut `:titre`) →
  ///   `'texte'`, entre apostrophes comme le littéral qu'il remplace.
  ///
  /// Une clé inconnue est LAISSÉE telle quelle : la remplacer par du vide
  /// ferait passer une absence pour un libellé vide.
  static String resoudre(String source) {
    final l = langue();
    String? valeur(String cle) {
      final v = l[cle];
      return v is String ? v : null;
    }

    var t = source.replaceAllMapped(
      RegExp(r"\{\{\s*(?:__|trans|trans_choice)\(\s*'" + _cle + r"'[^}]*\}\}"),
      (m) => valeur(m[1]!) ?? m[0]!,
    );
    t = t.replaceAllMapped(
      RegExp(
        r"\{!!\s*(?:__|trans|trans_choice)\(\s*'" + _cle + r"'.*?!!\}",
        dotAll: true,
      ),
      (m) => valeur(m[1]!) ?? m[0]!,
    );
    t = t.replaceAllMapped(
      RegExp(r"@lang\(\s*'" + _cle + r"'\s*\)"),
      (m) => valeur(m[1]!) ?? m[0]!,
    );
    return t.replaceAllMapped(
      RegExp(r"(?:__|trans)\(\s*'" + _cle + r"'\s*\)"),
      (m) {
        final v = valeur(m[1]!);
        return v == null ? m[0]! : "'$v'";
      },
    );
  }

  static Map<String, Object>? _langue;

  /// Toutes les chaînes de langue, clé aplatie (`pwa.clients.titre`) →
  /// `String`, ou `List<String>` pour un groupe. Les clés littérales de
  /// `fr.json` sont préfixées `json:`.
  static Map<String, Object> langue() {
    final dejaLue = _langue;
    if (dejaLue != null) return dejaLue;

    // Le script passe par un FICHIER, jamais par `-r` : sur Windows, les
    // guillemets d'un argument `-r` sont réinterprétés par la ligne de
    // commande, et un script mutilé rendrait un JSON vide — vert à vide.
    final script = File(
      '${Directory.systemTemp.path}/vue_blade_langue_$pid.php',
    )..writeAsStringSync(_scriptLangue);

    final ProcessResult r;
    try {
      // UTF-8 EXPLICITE. Sans lui, la sortie est décodée dans l'encodage du
      // système — sur Windows, chaque accent arrivait corrompu (« DÃ©tail »
      // pour « Détail ») et le test de garde de cet outil passait quand même,
      // la clé et la valeur étant corrompues de la même façon. Mesuré le
      // 10/09/2026 : 41 cas rouges sur 306 dans les tests d'écrans.
      r = Process.runSync(
        'php',
        [script.path, '$racine/lang/fr'],
        runInShell: true,
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
    } on ProcessException catch (e) {
      fail(
        'PHP est introuvable : les libellés de la vue Blade se résolvent par '
        'PHP, et ce test ne peut pas passer à vide.\n$e',
      );
    }
    if (r.exitCode != 0) {
      fail(
        'Les libellés de la PWA sont illisibles (PHP absent, ou un fichier de '
        '`lang/fr/` en erreur) :\n${r.stdout}${r.stderr}',
      );
    }

    final brut = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    final plat = <String, Object>{
      for (final e in brut.entries)
        e.key: e.value is List
            ? (e.value as List).whereType<String>().toList()
            : e.value as String,
    };

    // La garde de la garde : un dictionnaire vide ferait croire que chaque
    // libellé est absent — ou, pire, que rien n'est à comparer.
    final nbChaines = plat.values.whereType<String>().length;
    if (nbChaines < 1000) {
      fail(
        'Seules $nbChaines chaînes de langue lues dans $racine/lang/fr : la '
        'lecture est cassée, pas la PWA.',
      );
    }
    return _langue = plat;
  }

  static const _scriptLangue = r'''<?php
$plat = [];
foreach (glob($argv[1] . "/*.php") as $f) {
  $v = require $f;
  if (!is_array($v)) { continue; }
  $pile = [[basename($f, ".php"), $v]];
  while ($pile) {
    [$p, $t] = array_pop($pile);
    foreach ($t as $k => $x) {
      $c = $p . "." . $k;
      if (is_array($x)) {
        $pile[] = [$c, $x];
        $feuilles = [];
        array_walk_recursive($x, function ($y) use (&$feuilles) { if (is_string($y)) { $feuilles[] = $y; } });
        $plat[$c] = $feuilles;
      } elseif (is_string($x)) {
        $plat[$c] = $x;
      }
    }
  }
}
$json = dirname($argv[1]) . "/fr.json";
if (is_file($json)) {
  foreach (json_decode(file_get_contents($json), true) ?: [] as $k => $x) {
    if (is_string($x)) { $plat["json:" . $k] = $x; }
  }
}
echo json_encode($plat, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
''';
}
