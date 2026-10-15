import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Le registre des états de M14 du SERVEUR, relu en exécutant PHP.
///
/// `tool/etats/exporter_registre.php` lit `CatalogueEtatsService::REGISTRE`, les
/// douze classes `Etat*` (module, clés de langue du libellé, de la période, des
/// indicateurs et des en-têtes) et les fichiers de langue qu'elles emploient,
/// puis résout chaque clé. Les tests confrontent la copie locale à CETTE
/// sortie : une liste recopiée dans un test ne vérifierait qu'elle-même et
/// resterait verte le jour où le serveur renomme une colonne.
///
/// PHP absent, ou `tatacora-api` absent : le test ÉCHOUE, il ne saute pas — un
/// garde qui saute est vert à vide.
final class ServeurEtats {
  ServeurEtats._(this.etats, this._langue, this.pwaEtats);

  /// Les états du registre, dans l'ordre du serveur.
  final List<EtatServeur> etats;
  final Map<String, dynamic> _langue;

  /// `lang/fr/pwa.php`, clé `etats` : les phrases de l'écran.
  final Map<String, dynamic> pwaEtats;

  static ServeurEtats? _cache;

  static ServeurEtats charger() {
    final deja = _cache;
    if (deja != null) return deja;

    final r = Process.runSync('php', [
      'tool/etats/exporter_registre.php',
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) {
      fail(
        'Le registre des états du serveur n’a pas pu être relu (php, code '
        '${r.exitCode}) : ${r.stderr}. C’est un ÉCHEC, pas un saut.',
      );
    }
    final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    return _cache = ServeurEtats._(
      [
        for (final e in json['etats'] as List<dynamic>)
          EtatServeur._(e as Map<String, dynamic>),
      ],
      json['langue'] as Map<String, dynamic>,
      json['pwa_etats'] as Map<String, dynamic>,
    );
  }

  /// Une phrase de langue par sa clé pointée (`etats_m14.ventes.encaisse_oui`).
  /// Une clé absente ÉCHOUE : elle ne rend pas une chaîne vide.
  String langue(String cle) {
    final parties = cle.split('.');
    dynamic noeud = _langue;
    for (final p in parties) {
      if (noeud is! Map || !noeud.containsKey(p)) {
        fail('Clé de langue absente du serveur : $cle');
      }
      noeud = noeud[p];
    }
    if (noeud is! String) fail('La clé $cle ne désigne pas une phrase.');
    return noeud;
  }

  EtatServeur etat(String code) =>
      etats.firstWhere((e) => e.code == code, orElse: () => fail(code));
}

final class EtatServeur {
  EtatServeur._(Map<String, dynamic> j)
    : code = j['code'] as String,
      module = j['module'] as String,
      libelle = _texte(j['libelle']),
      periode = _texte(j['periode']),
      indicateurs = [for (final k in j['kpis'] as List<dynamic>) _texte(k)!],
      entetes = [for (final k in j['entetes'] as List<dynamic>) _texte(k)!];

  final String code;
  final String module;
  final String? libelle;
  final String? periode;
  final List<String> indicateurs;
  final List<String> entetes;

  static String? _texte(dynamic cle) {
    if (cle == null) return null;
    final texte = (cle as Map<String, dynamic>)['texte'];
    if (texte == null) {
      fail('Clé de langue non résolue : ${cle['cle']}');
    }
    return texte as String;
  }
}
