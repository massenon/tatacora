@Timeout(Duration(minutes: 2))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/analytique_locale.dart';
import 'package:tatacora_flutter/features/tableau_de_bord/domain/modules_pilotage.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

/// Les blocs de la fin du Pilotage (13/10/2026), en FONCTIONS PURES : les
/// bornes que les écrans ne montrent qu'une à une. La confrontation au serveur
/// vit ailleurs pour les créances (`encaissement_contre_serveur_test.dart`) et
/// l'analytique (`moteur_contre_serveur_test.dart`) ; celle de la carte M8 est
/// ici (`tool/tableau_de_bord/rejouer_pilotage.php`, SQLite).
void main() {
  /* ------------------------------------------------------------ créances */
  group('creancesParAnciennete — les bornes de l’ACCUEIL', () {
    final aujourdhui = DateTime(2026, 10, 12, 15);

    CreanceFacture creance(DateTime emise, {int ttc = 1000, int paye = 0}) =>
        CreanceFacture(
          piece: PieceFacturation(
            id: 'f-${emise.toIso8601String()}',
            numero: 'F-${emise.toIso8601String()}',
            origine: OrigineFacture.factureDirecte,
            dateEmission: emise,
            clientNom: 'KORA',
            statut: StatutPiece.emise,
            lignes: const [],
          ),
          ttcCentimes: ttc * 100,
          avoirsCentimes: 0,
          paiementsActifsCentimes: paye * 100,
          acomptesCentimes: 0,
        );

    Map<String, (int, int)> tranches(List<CreanceFacture> c) => {
      for (final t in creancesParAnciennete(c, aujourdhui))
        t.cle: (t.montantCentimes, t.pieces),
    };

    test('quatre tranches, dans l’ordre du serveur, même vides', () {
      expect(creancesParAnciennete(const [], aujourdhui).map((t) => t.cle), [
        '0_30',
        '30_60',
        '60_90',
        'plus_90',
      ]);
    });

    test(
      '30 jours PILE : « 31 à 60 » (la borne est exclue en haut de 0_30)',
      () {
        final t = tranches([creance(DateTime(2026, 9, 12, 23))]);
        expect(t['0_30'], (0, 0));
        expect(t['30_60'], (100000, 1));
      },
    );

    test('29 jours : « 0 à 30 » ; 31 jours : « 31 à 60 » ; 60 jours PILE : '
        '« 61 à 90 » (même règle) ; 61 : « 61 à 90 »', () {
      expect(tranches([creance(DateTime(2026, 9, 13))])['0_30'], (100000, 1));
      expect(tranches([creance(DateTime(2026, 9, 11))])['30_60'], (100000, 1));
      expect(tranches([creance(DateTime(2026, 8, 13))])['60_90'], (100000, 1));
      expect(tranches([creance(DateTime(2026, 8, 12))])['60_90'], (100000, 1));
    });

    test('90 jours pile : « plus de 90 » ; une facture DU FUTUR : « 0 à 30 » '
        '(sans borne haute)', () {
      expect(tranches([creance(DateTime(2026, 7, 14))])['plus_90'], (
        100000,
        1,
      ));
      expect(tranches([creance(DateTime(2026, 11, 2))])['0_30'], (100000, 1));
    });

    test('une facture SOLDÉE n’entre nulle part ; le reste dû est sommé', () {
      final t = tranches([
        creance(DateTime(2026, 10, 1), paye: 1000),
        creance(DateTime(2026, 10, 2), ttc: 3000, paye: 1000),
      ]);
      expect(t['0_30'], (200000, 1));
    });
  });

  /* ---------------------------------------------------------- analytique */
  group('margesParCentre — la ventilation de `AnalytiqueService`', () {
    AgregatAnalytique a(
      String centre,
      String classe, {
      int debit = 0,
      int credit = 0,
      int lignes = 1,
    }) => AgregatAnalytique(
      centreId: centre,
      centreLibelle: centre,
      classe: classe,
      debitCentimes: debit,
      creditCentimes: credit,
      nombreLignes: lignes,
    );

    test('produits (7) moins charges (6) ; le bilan (5) ne compte pas', () {
      final m = margesParCentre([
        a('Bar', '7', credit: 10000),
        a('Bar', '6', debit: 4000),
        a('Bar', '5', debit: 99999),
      ]);
      expect(m.single.produitsCentimes, 10000);
      expect(m.single.chargesCentimes, 4000);
      expect(m.single.resultatCentimes, 6000);
      expect(m.single.nombreLignes, 3);
    });

    test('la classe 8 selon le sens de son solde NET', () {
      expect(
        margesParCentre([
          a('X', '8', credit: 500, debit: 200),
        ]).single.produitsCentimes,
        300,
      );
      expect(
        margesParCentre([
          a('X', '8', debit: 500, credit: 200),
        ]).single.chargesCentimes,
        300,
      );
    });

    test('tri par résultat décroissant, stable sur les libellés', () {
      final m = margesParCentre([
        a('Zèbre', '7', credit: 100),
        a('alpha', '7', credit: 100),
        a('Bar', '7', credit: 900),
        a('Structure', '6', debit: 50),
      ]);
      expect(m.map((x) => x.libelle), ['Bar', 'alpha', 'Zèbre', 'Structure']);
      expect(versAnalytiquePilotage(m).centres.last.resultat, '-0.50');
    });

    test('decimaleDeCentimes', () {
      expect(decimaleDeCentimes(0), '0.00');
      expect(decimaleDeCentimes(-5), '-0.05');
      expect(decimaleDeCentimes(123456), '1234.56');
    });
  });

  test('nombreCommePhp : un float entier sans décimale', () {
    expect(nombreCommePhp(50), '50');
    expect(nombreCommePhp(66.7), '66.7');
    expect(nombreCommePhp(0), '0');
  });

  /* ------------------------------------------------- véhicules (serveur) */
  group('moduleVehicules — confronté au VRAI `Accueil::moduleVehicules`', () {
    Vehicule v(String id, StatutVehicule statut) => Vehicule(
      id: id,
      immatriculation: id,
      categorie: null,
      categorieBrute: null,
      annee: null,
      transmission: null,
      capacite: null,
      tarifJour: '15000.00',
      statut: statut,
      statutBrut: statut.code,
      exigePermis: true,
    );

    final parc = [
      v('v1', StatutVehicule.disponible),
      v('v2', StatutVehicule.entretien),
      v('v3', StatutVehicule.horsService),
    ];

    final contrats = [
      for (final (id, debut, fin, jours, montant) in [
        ('c1', '2026-10-10', '2026-10-13', 3, '45000.00'), // finit le jour J
        ('c2', '2026-10-27', '2026-10-29', 2, '1000.50'), // commence à J+14
        ('c3', '2026-10-28', '2026-10-30', 2, '7000.00'), // après J+14
        ('c4', '2026-10-01', '2026-10-12', 11, '99000.00'), // fini la veille
        ('c5', '2026-10-14', '2026-10-16', 2, '30000.25'),
      ])
        ContratLocation(
          id: id,
          immatriculation: 'v1',
          clientId: 'k',
          debut: debut,
          fin: fin,
          nombreJours: jours,
          montant: montant,
          packageAvecGuide: false,
        ),
    ];

    test('le poste rend la carte du serveur, jour après jour', () async {
      const jours = ['2026-10-13', '2026-10-12', '2026-10-01', '2026-11-30'];
      final php = await Process.start('php', [
        'tool/tableau_de_bord/rejouer_pilotage.php',
      ]);
      php.stdin.write(
        jsonEncode({
          'vehicules': [
            for (final x in parc) {'id': x.id, 'statut': x.statut!.code},
          ],
          'contrats': [
            for (final c in contrats)
              {
                'id': c.id,
                'vehicule_id': 'v1',
                'date_debut': c.debut,
                'date_fin': c.fin,
                'montant': c.montant,
              },
          ],
          'jours': jours,
        }),
      );
      await php.stdin.close();
      final sortie = await utf8.decodeStream(php.stdout);
      final erreur = await utf8.decodeStream(php.stderr);
      if (await php.exitCode != 0) {
        fail('Le serveur n’a pas rejoué la carte : $erreur');
      }
      final cartes =
          (jsonDecode(sortie) as Map<String, dynamic>)['cartes'] as List;

      for (final (i, jour) in jours.indexed) {
        final s = cartes[i] as Map<String, dynamic>;
        final local = moduleVehicules(
          parc: parc,
          contrats: contrats,
          aujourdhui: DateTime.parse(jour),
        );
        expect(
          {
            'parc': local.parc,
            'contrats_actifs': local.contratsActifs,
            'chiffre_affaires': local.chiffreAffaires,
            'jours_loues': local.joursLoues,
            'immobilises': local.immobilises,
          },
          {
            'parc': s['parc'],
            'contrats_actifs': s['contrats_actifs'],
            'chiffre_affaires': s['chiffre_affaires'],
            'jours_loues': s['jours_loues'],
            'immobilises': s['immobilises'],
          },
          reason: jour,
        );
      }
      // Pas un vert à vide : les deux bornes INCLUSES comptent au 13/10.
      expect((cartes.first as Map)['contrats_actifs'], 3);
    });
  });
}
