@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/entities/tableau_de_bord.dart'
    show PeriodeADate, PeriodeTableauDeBord, SelectionPeriode;
import 'package:tatacora_flutter/features/tableau_de_bord/domain/indicateurs_locaux.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/periode_locale.dart';

/// « Dépenses cumulées » et la série mensuelle du tableau de bord, calculées
/// SUR LE POSTE, contre le VRAI `TableauDeBordService` (`depensesCumulees`,
/// `serieMensuelle`) : mêmes bornes (fin comprise), brouillons exclus, avoirs
/// fournisseurs en diminution, mois ancrés au premier du mois.
void main() {
  const ecritures = <(String, String, String, String, String)>[
    // (classe, statut, date, débit, crédit)
    ('6', 'validee', '2026-10-05', '300.00', '0.00'),
    ('6', 'validee', '2026-10-31', '50.00', '0.00'),
    // L'avoir fournisseur vient en diminution.
    ('6', 'validee', '2026-10-12', '0.00', '20.50'),
    // Un brouillon n'est pas opposable.
    ('6', 'brouillon', '2026-10-06', '9999.00', '0.00'),
    // Une autre classe ne compte pas.
    ('7', 'validee', '2026-10-07', '0.00', '800.00'),
    // Le 1er du mois suivant : la borne de fin du serveur est INCLUSE.
    ('6', 'validee', '2026-11-01', '11.00', '0.00'),
    ('6', 'validee', '2026-09-30', '70.00', '0.00'),
    ('6', 'validee', '2026-08-15', '15.00', '0.00'),
    ('6', 'validee', '2026-05-10', '5.00', '0.00'),
  ];
  const paiements = <(String, String)>[
    ('2026-10-03 10:00:00', '1000.00'),
    ('2026-09-20 10:00:00', '400.00'),
    ('2026-08-31 23:00:00', '25.00'),
  ];

  Future<Map<String, dynamic>> executer(Map<String, dynamic> cas) async {
    final php = await Process.start('php', [
      'tool/tableau_de_bord/exporter_indicateurs.php',
    ]);
    php.stdin.write(jsonEncode(cas));
    await php.stdin.close();
    final sortie = utf8.decodeStream(php.stdout);
    final erreur = utf8.decodeStream(php.stderr);
    final code = await php.exitCode;
    if (code != 0) {
      fail('Le serveur n’a pas pu rejouer (php, code $code) : ${await erreur}');
    }
    return jsonDecode(await sortie) as Map<String, dynamic>;
  }

  int c(String s) {
    final m = RegExp(r'^(-?)(\d+)\.(\d{2})$').firstMatch(s)!;
    final v = int.parse(m[2]!) * 100 + int.parse(m[3]!);
    return m[1] == '-' ? -v : v;
  }

  final charges = [
    for (final e in ecritures)
      if (e.$2 == 'validee' && e.$1 == '6')
        ChargeDatee(
          date: e.$3,
          debitCentimes: c(e.$4),
          creditCentimes: c(e.$5),
        ),
  ];
  final encaissements = [
    for (final (i, p) in paiements.indexed)
      PaiementFacture(
        id: 'p$i',
        pieceId: 'f',
        sessionId: 's',
        mode: ModePaiementFacture.especes,
        montantCentimes: c(p.$2),
        datePaiement: DateTime.parse(p.$1),
        statut: StatutPaiementFacture.actif,
        utilisateurCreationId: 'u',
      ),
  ];

  late Map<String, dynamic> serveur;

  setUpAll(() async {
    serveur = await executer({
      'requetes': [
        for (final code in ['30j', '7j', 'trimestre', 'annee'])
          {'code': code, 'reference': '2026-10-31 14:30:00'},
        {'calendaire': 'mois', 'reference': '2026-10-20 10:00:00'},
        {'calendaire': 'mois', 'reference': '2026-09-15 10:00:00'},
      ],
      'ecritures': [
        for (final e in ecritures)
          {
            'classe': e.$1,
            'statut': e.$2,
            'date': e.$3,
            'debit': e.$4,
            'credit': e.$5,
          },
      ],
      'paiements': [
        for (final p in paiements) {'date': p.$1, 'montant': p.$2},
      ],
      'series': [
        {'reference': '2026-10-31 14:30:00', 'mois': 6},
        {'reference': '2026-10-31 14:30:00', 'mois': 12},
        {'reference': '2026-03-31 08:00:00', 'mois': 4},
        {'reference': '2026-10-15 08:00:00', 'mois': 1},
      ],
    });
  });

  test('les dépenses cumulées, période par période, courant ET précédent', () {
    final resultats = (serveur['resultats'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(resultats, isNotEmpty);
    final demandes = <FenetreTableauDeBord>[
      for (final p in [
        PeriodeADate.trenteJours,
        PeriodeADate.septJours,
        PeriodeADate.trimestre,
        PeriodeADate.annee,
      ])
        FenetreTableauDeBord.depuis(p, DateTime(2026, 10, 31, 14, 30)),
      FenetreTableauDeBord.resoudre(
        const SelectionPeriode(PeriodeTableauDeBord.mois),
        DateTime(2026, 10, 20, 10),
      ),
      FenetreTableauDeBord.resoudre(
        const SelectionPeriode(PeriodeTableauDeBord.mois),
        DateTime(2026, 9, 15, 10),
      ),
    ];
    expect(demandes.length, resultats.length);
    for (final (i, f) in demandes.indexed) {
      expect(
        depensesCumuleesCentimes(charges, f),
        c(resultats[i]['courant']['depenses_cumulees'] as String),
        reason: 'courant, demande $i',
      );
      expect(
        depensesCumuleesCentimes(charges, f.precedente),
        c(resultats[i]['avant']['depenses_cumulees'] as String),
        reason: 'précédent, demande $i',
      );
    }
    // La fenêtre d'octobre contient le 1er novembre (borne de fin incluse) :
    // 300 + 50 − 20,50 + 11 = 340,50.
    expect(
      depensesCumuleesCentimes(charges, demandes[4]),
      c('340.50'),
      reason: 'le chiffre est celui du serveur, particularité comprise',
    );
  });

  test('la série mensuelle : mêmes mois (du plus ancien au plus récent), '
      'même chiffre d’affaires encaissé, mêmes dépenses', () {
    final series = (serveur['series'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    expect(series, hasLength(4));
    for (final s in series) {
      final reference = DateTime.parse(s['reference'] as String);
      final points = serieMensuelleLocale(
        encaissements: encaissements,
        charges: charges,
        mois: s['mois'] as int,
        reference: reference,
      );
      final attendus = (s['points'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(points.length, attendus.length, reason: '${s['reference']}');
      for (final (i, a) in attendus.indexed) {
        expect(points[i].mois, a['mois'], reason: 'mois $i ${s['reference']}');
        expect(
          c(points[i].chiffreAffaires),
          c(a['chiffre_affaires_encaisse'] as String),
          reason: 'CA ${a['mois']}',
        );
        expect(
          c(points[i].depenses),
          c(a['depenses'] as String),
          reason: 'dépenses ${a['mois']}',
        );
      }
    }
  });
}
