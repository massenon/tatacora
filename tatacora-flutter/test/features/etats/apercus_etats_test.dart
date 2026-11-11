import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/etats/data/etats_api.dart';
import 'package:tatacora_flutter/features/etats/domain/apercu_etat.dart';
import 'package:tatacora_flutter/features/etats/domain/apercus_etats.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/reservation_tour.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/contrat_location.dart';
import 'package:tatacora_flutter/features/vehicules/domain/entities/vehicule.dart';

/// Les outils et les cas limites des aperçus — des fonctions PURES.
///
/// Les valeurs de chaque état sont éprouvées sur la base réelle
/// (`chaine_reelle_etats_test.dart`). Ce fichier ne porte que ce qu'une base
/// produit mal : un montant illisible, un véhicule inconnu, une date limite —
/// et les formats du serveur, un par un.
void main() {
  group('Les formats du serveur', () {
    test('un montant : deux décimales, sans séparateur', () {
      expect(montantServeur(0), '0.00');
      expect(montantServeur(12500), '12500.00');
      expect(montantServeur(1234567), '1234567.00');
    });

    test('une date : d/m/Y, zéros de tête compris', () {
      expect(dateServeur(DateTime(2026, 1, 5)), '05/01/2026');
      expect(dateServeur(DateTime(2026, 10, 25)), '25/10/2026');
      // `Y` de PHP : quatre chiffres.
      expect(dateServeur(DateTime(5, 1, 2)), '02/01/0005');
    });

    test('une date et une heure : d/m/Y H:i', () {
      expect(dateHeureServeur(DateTime(2026, 10, 8, 9, 5)), '08/10/2026 09:05');
      expect(
        dateHeureServeur(DateTime(2026, 10, 8, 21, 40)),
        '08/10/2026 21:40',
      );
    });

    test('l’instant d’une photographie : « d/m/Y à H:i »', () {
      expect(instantServeur(DateTime(2026, 10, 8, 9, 5)), '08/10/2026 à 09:05');
    });

    test(
      'une date ISO se retourne ; une date illisible reste telle quelle',
      () {
        expect(dateIsoServeur('2026-10-08'), '08/10/2026');
        expect(dateIsoServeur('2026-10-08 00:00:00'), '08/10/2026');
        // Une date devinée serait pire qu'une date mal formatée.
        expect(dateIsoServeur('bientôt'), 'bientôt');
        expect(dateIsoServeur(''), '');
      },
    );
  });

  group('Le mois courant de la paie (periodeValide du serveur)', () {
    test('AAAA-MM, jamais AAAA-JJ : le 25 mars est « 2026-03 »', () {
      // Le 10/10 ne prouverait rien : jour et mois y sont égaux.
      expect(moisDe(DateTime(2026, 3, 25)), '2026-03');
      expect(moisDe(DateTime(2026, 12, 1)), '2026-12');
      expect(moisDe(DateTime(2027, 1, 31)), '2027-01');
    });
  });

  group('Somme : des centièmes exacts, jamais un double', () {
    test('additionne sans dérive', () {
      final s = Somme.de(['0.10', '0.20', '12.50', '7']);
      expect(s.centiemes, 1980);
      expect(s.ecrite, '19.80');
      expect(s.illisibles, 0);
    });

    test('une chaîne illisible est COMPTÉE, jamais avalée', () {
      final s = Somme.de(['10.00', 'abc', '', '5.5']);
      expect(s.illisibles, 2);
      expect(s.ecrite, '15.50');
    });

    test('une liste vide vaut zéro, qui est une mesure', () {
      expect(Somme.de(const <String>[]).ecrite, '0.00');
    });
  });

  group('Les cas qu’une base produit mal', () {
    Vehicule vehicule(String immat, String tarif, String statut) => Vehicule(
      id: immat,
      immatriculation: immat,
      categorie: CategorieVehicule.voiture,
      categorieBrute: 'voiture',
      annee: 2020,
      transmission: null,
      capacite: 5,
      tarifJour: tarif,
      statut: StatutVehicule.depuisCode(statut),
      statutBrut: statut,
      exigePermis: true,
    );

    test('un tarif illisible sort du cumul, et la mention le dit', () {
      final a = apercuParcVehicules([
        vehicule('A-1', '30000.00', 'disponible'),
        vehicule('B-2', 'beaucoup', 'disponible'),
      ], maintenant: DateTime(2026, 10, 10, 14, 30));

      expect(a.indicateur('Tarif journalier cumulé'), '30000.00');
      expect(a.indicateur('Louables'), '2');
      expect(
        a.mentions.single,
        startsWith('1 tarif(s) journalier(s) illisible'),
      );
      // L'année et les places présentes sont écrites ; l'année est un entier.
      expect(a.lignes.first.sublist(2, 4), ['2020', '5']);
    });

    test('un parc vide : « 0 » et un cumul à 0.00, mesurés', () {
      final a = apercuParcVehicules(
        const [],
        maintenant: DateTime(2026, 10, 10),
      );
      expect(a.indicateurs.map((i) => i.valeur), ['0', '0', '0', '0.00']);
      expect(a.estVide, isTrue);
    });

    test(
      'un contrat dont le véhicule est inconnu ne devine pas sa catégorie',
      () {
        final a = apercuLocations(
          const [
            ContratLocation(
              id: 'c-1',
              immatriculation: 'XX-9',
              clientId: 'cli-1',
              debut: '2026-10-05',
              fin: '2026-10-07',
              nombreJours: 2,
              montant: '70000.00',
              packageAvecGuide: false,
            ),
          ],
          [vehicule('A-1', '35000.00', 'disponible')],
        );

        expect(a.lignes.single, [
          '', // client inconnu : vide, rendu « — » par l'écran.
          '— — XX-9',
          '05/10/2026',
          '07/10/2026',
          '2',
          '70000.00',
        ]);
        expect(a.indicateur('Montant total'), '70000.00');
      },
    );

    group('case « Inclure les contrats annulés »', () {
      const actif = ContratLocation(
        id: 'c-1',
        immatriculation: 'A-1',
        clientId: 'cli-1',
        debut: '2026-10-05',
        fin: '2026-10-07',
        nombreJours: 2,
        montant: '70000.00',
        statut: statutContratActif,
        packageAvecGuide: false,
      );
      const annule = ContratLocation(
        id: 'c-2',
        immatriculation: 'A-1',
        clientId: 'cli-1',
        debut: '2026-10-20',
        fin: '2026-10-22',
        nombreJours: 2,
        montant: '70000.00',
        statut: statutContratAnnule,
        packageAvecGuide: false,
      );
      final parc = [vehicule('A-1', '35000.00', 'disponible')];

      test('décochée (défaut) : annulé exclu, six colonnes, la période le '
          'dit', () {
        final a = apercuLocations(const [annule, actif], parc);
        expect(a.lignes, hasLength(1));
        expect(a.entetes, hasLength(6));
        expect(a.periode, 'Toutes dates · contrats annulés exclus');
        expect(a.indicateur('Contrats'), '1');
        expect(a.indicateur('Montant total'), '70000.00');
      });

      test('cochée : l’annulé est listé APRÈS les actifs, statut « Annulé », '
          'montant vide, et JAMAIS compté', () {
        // L'annulé est volontairement donné AVANT l'actif.
        final a = apercuLocations(
          const [annule, actif],
          parc,
          inclureAnnules: true,
        );
        expect(a.entetes.last, 'Statut');
        expect(a.lignes.map((l) => l.last), ['Actif', 'Annulé']);
        expect(a.lignes[0][5], '70000.00');
        expect(a.lignes[1][5], isEmpty);
        // Les totaux ne bougent pas.
        expect(a.indicateur('Contrats'), '1');
        expect(a.indicateur('Montant total'), '70000.00');
        expect(a.periode, contains('annulés inclus, non comptés'));
        expect(a.mentions.single, contains('listé(s) à part'));
      });

      test('cochée sans aucun annulé : même état qu’avant, plus la colonne '
          '« Statut »', () {
        final a = apercuLocations(const [actif], parc, inclureAnnules: true);
        expect(a.lignes.single.last, 'Actif');
        expect(a.mentions, isEmpty);
      });
    });

    test('un contrat d’AVANT la v41 n’a pas de montant : case vide, hors du '
        'cumul, jamais le tarif d’aujourd’hui', () {
      final a = apercuLocations(
        const [
          ContratLocation(
            id: 'c-1',
            immatriculation: 'A-1',
            clientId: 'cli-1',
            debut: '2026-10-05',
            fin: '2026-10-07',
            nombreJours: 2,
            packageAvecGuide: false,
          ),
          ContratLocation(
            id: 'c-2',
            immatriculation: 'A-1',
            clientId: 'cli-1',
            debut: '2026-10-10',
            fin: '2026-10-11',
            nombreJours: 1,
            montant: '35000.00',
            packageAvecGuide: false,
          ),
        ],
        [vehicule('A-1', '35000.00', 'disponible')],
      );

      expect(a.lignes.map((l) => l.last), ['', '35000.00']);
      expect(a.indicateur('Montant total'), '35000.00');
      expect(a.mentions.single, contains('1 contrat(s) sans montant connu'));
    });

    test(
      'une réservation de circuit annulée n’entre ni dans les comptes ni dans le montant',
      () {
        ReservationTour tour(
          String id,
          StatutReservationTour s,
          int n,
          DateTime d,
        ) => ReservationTour(
          id: id,
          circuitId: 'c',
          circuitNom: 'Pendjari',
          prixUnitaire: 25000,
          capaciteCircuit: 8,
          clientId: 'cli',
          clientNom: 'KORA Jean',
          guideId: 'g',
          guideNom: 'Koffi',
          dateCircuit: d,
          nbParticipants: n,
          statut: s,
        );

        final a = apercuTourisme([
          tour('t1', StatutReservationTour.reservee, 2, DateTime(2026, 10, 12)),
          tour('t2', StatutReservationTour.annulee, 5, DateTime(2026, 10, 13)),
          tour('t3', StatutReservationTour.terminee, 3, DateTime(2026, 10, 14)),
        ], illisibles: 2);

        expect(a.nombreLignes, 2);
        // Du plus récent au plus ancien, comme `orderByDesc('date_circuit')`.
        expect(a.lignes.map((l) => l[3]), ['14/10/2026', '12/10/2026']);
        expect(a.indicateurs.map((i) => i.valeur), ['2', '5', '125000.00']);
        expect(
          a.mentions.last,
          startsWith('2 réservation(s) de statut inconnu'),
        );
      },
    );
  });
}
