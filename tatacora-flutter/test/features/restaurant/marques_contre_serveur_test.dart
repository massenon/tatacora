@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/restaurant/domain/calcul_restaurant.dart';

/// La déduction de « corrigé à la main » (PA-161 b), CONFRONTÉE au serveur en
/// exécutant PHP : `tool/restaurant/exporter_marques.php` applique le VRAI
/// `MarquesDePrix::completer()` à un `Plat` dont les attributs sont posés à la
/// main (aucune base), et rend la marque qui résulte de l'enregistrement.
///
/// Une règle recopiée à la main dans un test ne vérifierait qu'elle-même
/// (piège 12). PHP absent, ou `vendor/` absent : le test ÉCHOUE, il ne saute
/// pas.
Future<List<bool>> _serveur(List<Map<String, Object>> cas) async {
  final php = await Process.start('php', [
    'tool/restaurant/exporter_marques.php',
  ]);
  php.stdin.write(jsonEncode({'cas': cas}));
  await php.stdin.close();

  final sortie = utf8.decodeStream(php.stdout);
  final erreur = utf8.decodeStream(php.stderr);
  final code = await php.exitCode;
  if (code != 0) {
    fail(
      'Le serveur n’a pas pu rejouer la déduction (php, code $code) : '
      '${await erreur}. C’est un ÉCHEC, pas un saut.',
    );
  }
  return (jsonDecode(await sortie) as List<dynamic>).cast<bool>();
}

void main() {
  test('la marque déduite est celle du serveur : les huit combinaisons, puis '
      '300 cas tirés', () async {
    final hasard = Random(20261009);
    final cas = <({bool provisoire, bool corrige, int prix, int soumis})>[
      // Les huit combinaisons, sans hasard : un balayage ne doit pas dépendre
      // d'un tirage pour atteindre chaque cas.
      for (final provisoire in [true, false])
        for (final corrige in [true, false])
          for (final change in [true, false])
            (
              provisoire: provisoire,
              corrige: corrige,
              prix: 1000,
              soumis: change ? 1200 : 1000,
            ),
      for (var i = 0; i < 300; i++)
        (
          provisoire: hasard.nextBool(),
          corrige: hasard.nextBool(),
          prix: hasard.nextInt(30000),
          // Un cas sur trois soumet le même prix.
          soumis: i % 3 == 0 ? -1 : hasard.nextInt(30000),
        ),
    ];

    final entrees = [
      for (final c in cas)
        {
          'provisoire': c.provisoire,
          'corrige': c.corrige,
          // Le serveur stocke un DECIMAL(15,2) : « 1000.00 » ; le formulaire
          // soumet « 1000 ». La comparaison est numérique (`bccomp`).
          'prix': '${c.prix}.00',
          'soumis': c.soumis == -1 ? '${c.prix}' : '${c.soumis}',
        },
    ];
    final attendus = await _serveur(entrees);
    expect(attendus, hasLength(cas.length));

    var poses = 0;
    var gardees = 0;
    for (var i = 0; i < cas.length; i++) {
      final c = cas[i];
      final local = prixCorrigeMainApres(
        corrigeActuel: c.corrige,
        provisoireActuel: c.provisoire,
        prixActuelFrancs: c.prix,
        prixSoumisFrancs: c.soumis == -1 ? c.prix : c.soumis,
      );
      expect(
        local,
        attendus[i],
        reason:
            'provisoire=${c.provisoire} corrige=${c.corrige} '
            'prix=${c.prix} soumis=${c.soumis == -1 ? c.prix : c.soumis}',
      );
      if (local && !c.corrige) poses++;
      if (local && c.corrige) gardees++;
    }

    // Le balayage n'est pas vert à vide : la marque a été POSÉE, GARDÉE, et
    // refusée.
    expect(poses, greaterThan(20), reason: 'des marques posées');
    expect(gardees, greaterThan(20), reason: 'des marques gardées');
    expect(attendus.where((a) => !a).length, greaterThan(20));
  });
}
