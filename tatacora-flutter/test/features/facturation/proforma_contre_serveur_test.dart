import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/mise_en_page_proforma.dart';
import 'package:tatacora_flutter/features/facturation/domain/montant_en_lettres.dart';
import 'package:tatacora_flutter/features/facturation/domain/numero_proforma.dart';

/// PARITÉ poste / serveur de la facture proforma (PO, 07/11/2026) : le montant en
/// lettres, la date longue, les milliers et le numéro sont réimplémentés en Dart ;
/// ce test lance le VRAI script PHP (`tool/proforma/rejouer_proforma.php`, classes du
/// serveur) et compare chaque valeur. Plus de 2 600 montants, dont la table du PO.
void main() {
  late Map<String, dynamic> serveur;

  setUpAll(() {
    final r = Process.runSync('php', ['tool/proforma/rejouer_proforma.php']);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    serveur = jsonDecode(r.stdout as String) as Map<String, dynamic>;
  });

  test(
    'le montant en lettres : même texte que le serveur, montant par montant',
    () {
      final lettres = serveur['lettres'] as Map<String, dynamic>;
      // Plancher : un script vidé ne doit pas rendre le test vert à vide.
      expect(lettres.length, greaterThan(2000));
      for (final e in lettres.entries) {
        expect(francsCfaEnLettres(int.parse(e.key)), e.value, reason: e.key);
      }
    },
  );

  test('la table de cas du PO (partagée) est respectée par le Dart', () {
    final cas =
        jsonDecode(
              File(
                'tool/proforma/cas_montant_en_lettres.json',
              ).readAsStringSync(),
            )
            as List<dynamic>;
    expect(cas.length, greaterThanOrEqualTo(30));
    for (final c in cas) {
      final m = c as Map<String, dynamic>;
      expect(
        francsCfaEnLettres(m['montant'] as int),
        m['lettres'],
        reason: '${m['montant']}',
      );
    }
  });

  test('les cas nommés par le PO', () {
    expect(francsCfaEnLettres(400000), 'QUATRE CENT MILLE FRANCS CFA');
    expect(francsCfaEnLettres(80), 'QUATRE-VINGTS FRANCS CFA');
    expect(francsCfaEnLettres(80000), 'QUATRE-VINGT MILLE FRANCS CFA');
    expect(francsCfaEnLettres(0), 'ZÉRO FRANC CFA');
    expect(() => francsCfaEnLettres(-1), throwsArgumentError);
  });

  test('la date longue française', () {
    final dates = serveur['dates'] as Map<String, dynamic>;
    expect(dates.length, greaterThanOrEqualTo(5));
    for (final e in dates.entries) {
      expect(dateLongueFr(DateTime.parse(e.key)), e.value, reason: e.key);
    }
  });

  test('les milliers avec espace insécable', () {
    final milliers = serveur['milliers'] as Map<String, dynamic>;
    for (final e in milliers.entries) {
      expect(montantAvecEspaces(int.parse(e.key)), e.value, reason: e.key);
    }
  });

  test('le numéro N°0045 FP-GCN/2026, et le provisoire jamais définitif', () {
    final numeros = serveur['numeros'] as Map<String, dynamic>;
    for (final e in numeros.entries) {
      final p = e.key.split('|');
      expect(
        formaterNumeroProforma(int.parse(p[0]), p[1], int.parse(p[2])),
        e.value,
        reason: e.key,
      );
    }
    expect(formaterNumeroProforma(45, 'GCN', 2026), 'N°0045 FP-GCN/2026');
    final provisoire = formaterNumeroProformaProvisoire(2026, 7);
    expect(provisoire, 'PROV-FP-2026-00007');
    expect(estNumeroProformaProvisoire(provisoire), isTrue);
    expect(estNumeroProformaProvisoire('N°0045 FP-GCN/2026'), isFalse);
  });
}
