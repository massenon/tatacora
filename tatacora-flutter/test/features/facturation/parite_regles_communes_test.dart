import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/mode_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/statut_normalisation.dart';
import 'package:tatacora_flutter/features/parametres/domain/regles_parametres.dart';
import 'package:tatacora_flutter/features/parametres/domain/registre_parametres_local.dart';

/// PARITÉ serveur / poste des règles communes de la facturation normalisée :
/// le mode, la lecture d'une valeur inconnue, l'IFU de 13 chiffres, les statuts.
/// Le poste est confronté au VRAI PHP (`tool/facturation/rejouer_regles_communes.php`),
/// jamais à une liste recopiée. PHP absent : le test ÉCHOUE, il ne saute pas.
void main() {
  late Map<String, dynamic> serveur;

  setUpAll(() {
    final r = Process.runSync('php', [
      'tool/facturation/rejouer_regles_communes.php',
    ], stdoutEncoding: utf8);
    if (r.exitCode != 0) {
      fail(
        'Le serveur n’a pas pu être rejoué (php, code ${r.exitCode}) : '
        '${r.stderr}. C’est un ÉCHEC, pas un saut.',
      );
    }
    serveur = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  });

  test('le balayage n’est pas vide', () {
    expect((serveur['modes'] as List), hasLength(3));
    expect((serveur['statuts'] as List), hasLength(4));
    expect((serveur['mode_depuis'] as Map).length, greaterThanOrEqualTo(8));
    expect((serveur['ifu_valide'] as Map).length, greaterThanOrEqualTo(9));
  });

  test('la clé du mode et les modes sont ceux du serveur, libellés compris', () {
    expect(cleModeFacturation, serveur['cle_mode']);
    final modes = serveur['modes'] as List;
    expect(
      [for (final m in ModeFacturation.values) m.code],
      [for (final m in modes) (m as Map)['valeur']],
    );
    expect(
      [for (final m in ModeFacturation.values) m.libelle],
      [for (final m in modes) (m as Map)['libelle']],
    );
    // Les libellés du registre local (choix du mode) sont ceux du serveur aussi.
    final spec = RegistreParametresLocal.parCle(cleModeFacturation)!;
    expect(spec.choix, [for (final m in modes) (m as Map)['valeur']]);
  });

  test('lire une valeur de mode : même résultat que le serveur, y compris '
      'pour une valeur inconnue (toujours « désactivé »)', () {
    final attendu = serveur['mode_depuis'] as Map<String, dynamic>;
    attendu.forEach((brut, mode) {
      expect(ModeFacturation.depuisCode(brut).code, mode, reason: '« $brut »');
    });
  });

  test('l’IFU : mêmes 13 chiffres, mêmes refus (espace, retour à la ligne, '
      'chiffres pleine chasse)', () {
    final spec = RegistreParametresLocal.parCle('entreprise_ifu')!;
    final attendu = serveur['ifu_valide'] as Map<String, dynamic>;
    attendu.forEach((brut, valide) {
      // Le poste normalise (trim) AVANT de juger ; le serveur juge la valeur
      // brute reçue. Comparer les deux sur la valeur déjà rognée.
      final ecran = normaliser(spec, brut.trim());
      final accepte = ecran is ValeurNormalisee && ecran.valeur != null;
      final serveurValide = valide as bool;
      if (brut == brut.trim()) {
        expect(accepte, serveurValide, reason: '« $brut »');
      } else {
        // Une espace de bord est rognée par le poste ; le serveur la refuse :
        // le poste n'envoie JAMAIS la valeur brute, il envoie la rognée.
        expect(accepte, isTrue, reason: 'rognée : « ${brut.trim()} »');
      }
    });
  });

  test('les statuts de normalisation : mêmes codes, mêmes libellés, même '
      'notion de « rejouable », dans le même ordre', () {
    final statuts = serveur['statuts'] as List;
    expect(
      [for (final s in StatutNormalisation.values) s.code],
      [for (final s in statuts) (s as Map)['valeur']],
    );
    expect(
      [for (final s in StatutNormalisation.values) s.libelle],
      [for (final s in statuts) (s as Map)['libelle']],
    );
    expect(
      [for (final s in StatutNormalisation.values) s.rejouable],
      [for (final s in statuts) (s as Map)['rejouable']],
    );
  });

  test('les clés réglées au serveur seul sont celles que le poste refuse '
      'd’écrire', () {
    final cles = (serveur['cles_administrateur'] as List).cast<String>();
    expect(cles, isNotEmpty);
    for (final cle in cles) {
      expect(
        RegistreParametresLocal.parCle(cle)!.serveurSeulement,
        isTrue,
        reason: cle,
      );
    }
    expect(
      [
        for (final s in RegistreParametresLocal.definitions)
          if (s.serveurSeulement) s.cle,
      ]..sort(),
      ([...cles]..sort()),
    );
  });
}
