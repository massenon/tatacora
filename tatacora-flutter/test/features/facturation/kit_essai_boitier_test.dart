import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/conversion_boitier.dart';

import '../../outils/kit_essai_boitier.dart';

/// Le kit d'essai du boîtier (`presentation/05_essai_boitier/`) contre `bill.spec.json`
/// (copie du schéma du pilote, draft-04) et contre les règles de `ClientMecefBoitier`.
///
/// Le validateur ci-dessous couvre le sous-ensemble du schéma qu'il emploie : `type`, `enum`,
/// `maxLength`, `minItems`, `required`, `properties`, `items`, `allOf`, `oneOf`, `$ref`. Il est
/// lui-même éprouvé par des documents INVALIDES (un validateur qui accepte tout prouve du vide).
void main() {
  final dossierKit = Directory('../presentation/05_essai_boitier');
  final schema =
      jsonDecode(File('${dossierKit.path}/bill.spec.json').readAsStringSync())
          as Map<String, Object?>;

  /// Les erreurs de [valeur] contre [s] ; vide = valide.
  List<String> valider(Object? valeur, Map<String, Object?> s, String chemin) {
    final erreurs = <String>[];
    final ref = s[r'$ref'];
    if (ref is String) {
      final nom = ref.split('/').last;
      final definitions = schema['definitions']! as Map<String, Object?>;
      return valider(valeur, definitions[nom]! as Map<String, Object?>, chemin);
    }
    final type = s['type'];
    if (type == 'object' && valeur is! Map) {
      return ['$chemin : objet attendu'];
    }
    if (type == 'array' && valeur is! List) {
      return ['$chemin : tableau attendu'];
    }
    if (type == 'string' && valeur is! String) {
      return ['$chemin : chaîne attendue'];
    }
    if (type == 'number' && valeur is! num) {
      return ['$chemin : nombre attendu'];
    }
    final enumeration = s['enum'];
    if (enumeration is List && !enumeration.contains(valeur)) {
      erreurs.add('$chemin : $valeur hors énumération');
    }
    final max = s['maxLength'];
    if (max is int && valeur is String && valeur.length > max) {
      erreurs.add('$chemin : plus de $max caractères');
    }
    final min = s['minItems'];
    if (min is int && valeur is List && valeur.length < min) {
      erreurs.add('$chemin : moins de $min éléments');
    }
    if (valeur is Map) {
      for (final r in (s['required'] as List?) ?? const []) {
        if (!valeur.containsKey(r)) erreurs.add('$chemin : "$r" manquant');
      }
      final props = (s['properties'] as Map<String, Object?>?) ?? const {};
      for (final e in props.entries) {
        if (valeur.containsKey(e.key)) {
          erreurs.addAll(
            valider(
              valeur[e.key],
              e.value! as Map<String, Object?>,
              '$chemin.${e.key}',
            ),
          );
        }
      }
    }
    if (valeur is List && s['items'] is Map) {
      for (var i = 0; i < valeur.length; i++) {
        erreurs.addAll(
          valider(
            valeur[i],
            s['items']! as Map<String, Object?>,
            '$chemin[$i]',
          ),
        );
      }
    }
    for (final sous in (s['allOf'] as List?) ?? const []) {
      erreurs.addAll(valider(valeur, sous as Map<String, Object?>, chemin));
    }
    final oneOf = s['oneOf'];
    if (oneOf is List) {
      final valides = [
        for (final sous in oneOf)
          if (valider(valeur, sous as Map<String, Object?>, chemin).isEmpty)
            sous,
      ];
      if (valides.length != 1) {
        erreurs.add(
          '$chemin : ${valides.length} variantes valides (1 attendue)',
        );
      }
    }
    return erreurs;
  }

  Map<String, Object?> corps(String json) =>
      jsonDecode(json) as Map<String, Object?>;

  test('le schéma est bien lu (garde contre un balayage à vide)', () {
    expect(schema['title'], 'Bill');
    expect(schema['oneOf'], hasLength(2));
  });

  test('le validateur refuse des documents invalides', () {
    final ok = corps(jsonDuKit()['bill_essai_1_simple.json']!);
    expect(valider(ok, schema, r'$'), isEmpty);

    final sansVt = Map<String, Object?>.of(ok)..remove('vt');
    expect(valider(sansVt, schema, r'$'), isNotEmpty);

    final nomLong = Map<String, Object?>.of(ok)..['seller_name'] = 'X' * 31;
    expect(valider(nomLong, schema, r'$'), isNotEmpty);

    final modeInconnu = Map<String, Object?>.of(ok)
      ..['payments'] = [
        {'mode': 'Z', 'amount': 100},
      ];
    expect(valider(modeInconnu, schema, r'$'), isNotEmpty);

    final vtEtRt = Map<String, Object?>.of(ok)
      ..['rt'] = 'FA'
      ..['rn'] = 'X-1';
    expect(valider(vtEtRt, schema, r'$'), isNotEmpty, reason: 'oneOf exclusif');
  });

  group('les trois JSON du kit', () {
    final kit = jsonDuKit();

    test('trois fichiers, valides contre bill.spec.json', () {
      expect(kit.keys, [
        'bill_essai_1_simple.json',
        'bill_essai_2_multi.json',
        'bill_essai_3_avoir.json',
      ]);
      for (final e in kit.entries) {
        expect(valider(corps(e.value), schema, r'$'), isEmpty, reason: e.key);
      }
    });

    test('règles du client : entiers, libellés <= 60 ASCII, vendeur <= 30', () {
      for (final e in kit.entries) {
        final j = corps(e.value);
        expect((j['seller_name']! as String).length, lessThanOrEqualTo(30));
        var total = 0;
        for (final p in j['products']! as List) {
          final produit = p as Map<String, Object?>;
          expect(produit['price'], isA<int>(), reason: e.key);
          expect(produit['items'], isA<int>(), reason: e.key);
          final label = produit['label']! as String;
          expect(label.length, lessThanOrEqualTo(60));
          expect(
            label,
            matches(RegExp(r'^[ -~]+$')),
            reason: 'ASCII imprimable',
          );
          expect(label, isNot(matches(RegExp('[<>&,;*]'))));
          expect(produit.containsKey('specific_tax'), isFalse);
          expect(produit.containsKey('original_price'), isFalse);
          total += (produit['price']! as int) * (produit['items']! as int);
        }
        var paye = 0;
        for (final p in j['payments']! as List) {
          expect((p as Map)['amount'], isA<int>());
          paye += p['amount'] as int;
        }
        expect(total, paye, reason: '${e.key} : lignes = paiements');
        expect(total, lessThanOrEqualTo(maxEntierFloat32));
      }
    });

    test('contenu attendu de chaque essai', () {
      final un = corps(kit['bill_essai_1_simple.json']!);
      expect(un['vt'], 'FV');
      expect(un['products'], hasLength(1));
      expect(((un['products']! as List).single as Map)['tax'], 'B');
      expect(un['payments'], [
        {'mode': 'E', 'amount': 100},
      ]);

      final deux = corps(kit['bill_essai_2_multi.json']!);
      final taxes = [
        for (final p in deux['products']! as List) (p as Map)['tax'],
      ];
      expect(taxes, contains('F'));
      final labels = [
        for (final p in deux['products']! as List) (p as Map)['label'],
      ];
      expect(labels, contains('TAXE DE SEJOUR'));
      expect(
        [for (final p in deux['payments']! as List) (p as Map)['mode']],
        ['E', 'M'],
      );

      final trois = corps(kit['bill_essai_3_avoir.json']!);
      expect(trois['rt'], 'FA');
      expect(trois['rn'], rnARemplacer);
      expect(trois.containsKey('vt'), isFalse);
      expect(trois['rn'], matches(RegExp(r'^.+-.+$')), reason: 'format NIM-TC');
    });

    test('les fichiers de presentation/ sont ceux que le code produit', () {
      for (final e in kit.entries) {
        final f = File('${dossierKit.path}/${e.key}');
        expect(f.existsSync(), isTrue, reason: '${e.key} : régénérer');
        expect(f.readAsStringSync(), e.value, reason: '${e.key} périmé');
      }
    });
  });
}
