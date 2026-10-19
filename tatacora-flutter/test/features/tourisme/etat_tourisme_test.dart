import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/tourisme/domain/departs.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/circuit.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/reservation_tour.dart';
import 'package:tatacora_flutter/features/tourisme/impression/etat_tourisme.dart';
import 'package:tatacora_flutter/features/tourisme/presentation/providers_tourisme.dart';

/// L'export de M9 (`EtatTourisme`) — le contenu du CSV, SANS écran.
///
/// Les valeurs sont celles d'un jeu écrit à la main : trois départs, un par
/// état (des places restantes, complet, annulé). Un cas qui lirait ses
/// attentes dans le code qu'il éprouve resterait vert le jour où ce code se
/// tromperait.
void main() {
  ReservationTour ligne({
    required String id,
    required String circuitId,
    required String circuitNom,
    required int prix,
    required int capacite,
    required DateTime date,
    required int participants,
    StatutReservationTour statut = StatutReservationTour.reservee,
    String client = 'KORA Jean',
    String guide = 'ADJOVI Paul',
  }) => ReservationTour(
    id: id,
    circuitId: circuitId,
    circuitNom: circuitNom,
    prixUnitaire: prix,
    capaciteCircuit: capacite,
    clientId: 'cli-$id',
    clientNom: client,
    guideId: 'gui-$guide',
    guideNom: guide,
    dateCircuit: date,
    nbParticipants: participants,
    statut: statut,
  );

  final jour = DateTime(2026, 10, 12);

  /// Départ 1 : 5 + 3 personnes sur 12 places (4 restantes), une ligne annulée
  /// qui ne compte ni en places ni en argent. Départ 2 : complet (4 sur 4).
  /// Départ 3 : toutes les lignes annulées.
  final lignes = [
    ligne(
      id: 'a',
      circuitId: 'c1',
      circuitNom: 'Cascades de Tanougou',
      prix: 4500,
      capacite: 12,
      date: jour,
      participants: 5,
    ),
    ligne(
      id: 'b',
      circuitId: 'c1',
      circuitNom: 'Cascades de Tanougou',
      prix: 4500,
      capacite: 12,
      date: jour,
      participants: 3,
      client: 'DOSSOU Marie',
    ),
    ligne(
      id: 'c',
      circuitId: 'c1',
      circuitNom: 'Cascades de Tanougou',
      prix: 4500,
      capacite: 12,
      date: jour,
      participants: 9,
      statut: StatutReservationTour.annulee,
    ),
    ligne(
      id: 'd',
      circuitId: 'c2',
      circuitNom: 'Pendjari; safari',
      prix: 20000,
      capacite: 4,
      date: DateTime(2026, 10, 14),
      participants: 4,
      guide: 'SANI Issa',
    ),
    ligne(
      id: 'e',
      circuitId: 'c3',
      circuitNom: 'Tata Somba',
      prix: 3000,
      capacite: 10,
      date: DateTime(2026, 10, 16),
      participants: 2,
      statut: StatutReservationTour.annulee,
    ),
  ];

  /// Les lignes d'un CSV, sans le BOM de tête.
  List<String> lire(EtatTourisme e) =>
      e.csv().replaceFirst('\u{FEFF}', '').split('\n');

  group('Les en-têtes sont ceux du SERVEUR, relus sur `TourismeExport`', () {
    test('trois onglets, trois listes, au mot et dans l\'ordre', () {
      final export = File('../tatacora-api/app/Exports/TourismeExport.php');
      final langue = File('../tatacora-api/lang/fr/tourisme.php');
      expect(export.existsSync() && langue.existsSync(), isTrue);

      // Seul le groupe `pwa` : `col_circuit` existe aussi plus haut dans le
      // fichier, avec un autre sens.
      final texteLangue = langue.readAsStringSync();
      final depart = texteLangue.indexOf("'pwa' => [");
      expect(depart, greaterThanOrEqualTo(0), reason: 'Groupe disparu.');
      final lang = <String, String>{};
      for (final l in texteLangue.substring(depart).split('\n')) {
        final t = l.trim();
        final eq = t.indexOf("' => '");
        if (!t.startsWith("'") || eq < 0 || !t.endsWith("',")) continue;
        lang[t.substring(1, eq)] = t.substring(eq + 6, t.length - 2);
      }
      expect(lang['col_numero'], 'N°', reason: 'Lecture de la langue.');

      final php = export.readAsStringSync();
      final corps = php.substring(php.indexOf('function entetesDe'));

      List<String> duServeur(String arme) {
        final debut = corps.indexOf(arme);
        expect(debut, greaterThanOrEqualTo(0), reason: arme);
        final fin = corps.indexOf('],', debut);
        final cles = <String>[];
        const amorce = "__('tourisme.pwa.";
        var curseur = corps.indexOf(amorce, debut);
        while (curseur >= 0 && curseur < fin) {
          final finCle = corps.indexOf("'", curseur + amorce.length);
          cles.add(corps.substring(curseur + amorce.length, finCle));
          curseur = corps.indexOf(amorce, finCle);
        }
        return [for (final c in cles) lang[c]!];
      }

      final departs = duServeur('default => [');
      final reservations = duServeur("'reservations' => [");
      final catalogue = duServeur("'catalogue' => [");

      // Prouvé NON VIDE : un balayage vide serait vert.
      expect(departs, hasLength(9));
      expect(reservations, hasLength(9));
      expect(catalogue, hasLength(7));

      expect(EtatTourisme.entetesDeparts, departs);
      expect(EtatTourisme.entetesReservations, reservations);
      expect(EtatTourisme.entetesCatalogue, catalogue);
    });
  });

  group('Onglet « Départs planifiés »', () {
    final etat = EtatTourisme.departs(
      departsDerives(lignes),
      filtre: 'du 09/10/2026 au 08/11/2026 · Statut : Planifiés',
    );

    test('une ligne par départ, aux valeurs EXACTES', () {
      expect(etat.titre, 'Départs planifiés');
      expect(etat.entetes, EtatTourisme.entetesDeparts);
      expect(etat.lignes, hasLength(3));

      // Départ 1 : 8 personnes sur 12, 36 000 F, quatre places restantes.
      expect(etat.lignes[0], [
        null,
        'Cascades de Tanougou',
        '12/10/2026',
        'ADJOVI Paul',
        null,
        '8/12',
        '4500',
        '36000',
        '4 place(s)',
      ]);
      // Départ 2 : complet — 4 sur 4, 80 000 F. Le « ; » du nom ne casse pas
      // la colonne dans le CSV (testé plus bas).
      expect(etat.lignes[1], [
        null,
        'Pendjari; safari',
        '14/10/2026',
        'SANI Issa',
        null,
        '4/4',
        '20000',
        '80000',
        'Complet',
      ]);
      // Départ 3 : annulé — 0 personne, 0 F (une MESURE : aucune ligne active),
      // et aucun guide, donc une case vide.
      expect(etat.lignes[2], [
        null,
        'Tata Somba',
        '16/10/2026',
        null,
        null,
        '0/10',
        '3000',
        '0',
        'Annulé',
      ]);
    });

    test(
      'le CSV porte le filtre, les mentions, les en-têtes, puis les lignes',
      () {
        final l = lire(etat);

        expect(
          l[0],
          'Départs planifiés;du 09/10/2026 au 08/11/2026 · Statut : Planifiés',
        );
        expect(l[1], '');
        expect(
          l[2],
          'Colonnes « N° » et « Véhicule » vides : aucune n\'a de colonne sur '
          'ce poste. Une case vide dit « la donnée n\'existe pas ».',
        );
        expect(
          l[3],
          'Colonne « État » : celle de l\'écran (Annulé, Complet, ou le nombre '
          'de places restantes).',
        );
        expect(l[4], '');
        expect(
          l[5],
          'N°;Circuit;Départ;Guide;Véhicule;Remplissage;Prix / pers.;CA;État',
        );
        expect(
          l[6],
          ';Cascades de Tanougou;12/10/2026;ADJOVI Paul;;8/12;4500;36000;'
          '4 place(s)',
        );
        // Le « ; » du nom du circuit devient « , » : il n'ajoute pas de colonne.
        expect(
          l[7],
          ';Pendjari, safari;14/10/2026;SANI Issa;;4/4;20000;80000;Complet',
        );
        expect(l[8], ';Tata Somba;16/10/2026;;;0/10;3000;0;Annulé');
        // Trois lignes, puis la fin de fichier — rien d'autre.
        expect(l.length, 10);
        expect(l[9], '');
      },
    );
  });

  group('Onglet « Réservations »', () {
    test('le montant est prix x personnes, Acompte et Reste dû VIDES', () {
      final etat = EtatTourisme.reservations([
        lignes[0],
        lignes[1],
      ], filtre: 'du 09/10/2026 au 08/11/2026 · Statut : Planifiés');

      expect(etat.titre, 'Réservations');
      expect(etat.entetes, EtatTourisme.entetesReservations);
      expect(etat.lignes, [
        [
          null,
          'KORA Jean',
          'Cascades de Tanougou',
          '12/10/2026',
          '5',
          '4500',
          '22500',
          null,
          null,
        ],
        [
          null,
          'DOSSOU Marie',
          'Cascades de Tanougou',
          '12/10/2026',
          '3',
          '4500',
          '13500',
          null,
          null,
        ],
      ]);

      final l = lire(etat);
      expect(
        l[5],
        'N°;Client;Circuit;Départ;Pers.;Prix / pers.;Montant;Acompte;Reste dû',
      );
      expect(l[6], ';KORA Jean;Cascades de Tanougou;12/10/2026;5;4500;22500;;');
      expect(
        l[7],
        ';DOSSOU Marie;Cascades de Tanougou;12/10/2026;3;4500;13500;;',
      );
    });

    test(
      'une réservation annulée est exportée avec SON montant, pas à zéro',
      () {
        // L'écran l'affiche (en grisé) avec son montant ; l'export porte sur ce
        // qui est affiché. Seuls les TOTAUX de l'écran l'excluent.
        final etat = EtatTourisme.reservations([lignes[2]], filtre: 'x');

        expect(etat.lignes.single[4], '9');
        expect(etat.lignes.single[6], '40500');
      },
    );
  });

  group('Onglet « Catalogue »', () {
    const c1 = Circuit(
      id: 'c1',
      nom: 'Cascades de Tanougou',
      theme: 'Nature',
      zone: 'Atacora',
      prix: 4500,
      capaciteMax: 12,
      duree: '1 jour',
    );
    const c2 = Circuit(
      id: 'c2',
      nom: 'Tata Somba',
      theme: 'Culture',
      zone: 'Boukoumbé',
      prix: 3000,
      capaciteMax: 10,
    );

    test(
      'Durée absente et circuit sans départ : cases VIDES, jamais « 0 »',
      () {
        final etat = EtatTourisme.catalogue(
          [c1, c2],
          departsParCircuit: const {'c1': 2},
          filtre: 'du 09/10/2026 au 08/11/2026',
        );

        expect(etat.entetes, EtatTourisme.entetesCatalogue);
        expect(etat.lignes, [
          [
            'Cascades de Tanougou',
            'Circuit',
            '1 jour',
            'Atacora · Nature',
            '4500',
            null,
            '2',
          ],
          [
            'Tata Somba',
            'Circuit',
            null,
            'Boukoumbé · Culture',
            '3000',
            null,
            null,
          ],
        ]);

        final l = lire(etat);
        expect(l[0], 'Catalogue;du 09/10/2026 au 08/11/2026');
        expect(
          l[l.length - 3],
          'Cascades de Tanougou;Circuit;1 jour;Atacora · Nature;4500;;2',
        );
        expect(
          l[l.length - 2],
          'Tata Somba;Circuit;;Boukoumbé · Culture;3000;;',
        );
      },
    );
  });

  group('Le fichier est de l\'UTF-8 RÉEL', () {
    test('BOM EF BB BF, « é » sur deux octets, jamais une unité UTF-16', () {
      final etat = EtatTourisme.departs(
        departsDerives([lignes[0]]),
        filtre: 'Recherche : é—',
      );
      final octets = etat.csvOctets();

      expect(octets.take(3), [0xEF, 0xBB, 0xBF]);
      // `utf8.decode` retire lui-même un BOM de tête : on décode après les trois
      // octets, et le texte relu est celui du CSV moins son BOM.
      expect(
        utf8.decode(octets.sublist(3)),
        etat.csv().replaceFirst('\u{FEFF}', ''),
      );
      // « é » = C3 A9, « — » = E2 80 94.
      final i = octets.indexOf(0xC3);
      expect(octets[i + 1], 0xA9);
      expect(octets.contains(0xE9), isFalse);
      expect(octets.contains(0xFF), isFalse);
    });
  });

  group('La description du filtre dit ce qui filtre réellement', () {
    final periode = PeriodeTourisme(
      debut: DateTime(2026, 10, 9),
      fin: DateTime(2026, 11, 8),
    );

    String decrire(
      OngletTourisme onglet, {
      FiltreStatutDepart statut = FiltreStatutDepart.planifie,
      FiltreRemplissage remplissage = FiltreRemplissage.tous,
      String? prestation,
      String recherche = '',
    }) => descriptionFiltreTourisme(
      onglet: onglet,
      periode: periode,
      statut: statut,
      remplissage: remplissage,
      prestation: prestation,
      recherche: recherche,
    );

    test('Départs : période, statut, prestation, remplissage, recherche', () {
      expect(
        decrire(OngletTourisme.departs),
        'du 09/10/2026 au 08/11/2026 · Statut : Planifiés',
      );
      expect(
        decrire(
          OngletTourisme.departs,
          statut: FiltreStatutDepart.annule,
          remplissage: FiltreRemplissage.complet,
          prestation: 'Tata Somba',
          recherche: '  adjovi ',
        ),
        'du 09/10/2026 au 08/11/2026 · Statut : Annulés · Prestation : Tata '
        'Somba · Remplissage : Complets · Recherche : adjovi',
      );
    });

    test(
      'Réservations : le remplissage ne s\'applique PAS, il n\'est pas cité',
      () {
        expect(
          decrire(
            OngletTourisme.reservations,
            remplissage: FiltreRemplissage.complet,
            statut: FiltreStatutDepart.tous,
          ),
          'du 09/10/2026 au 08/11/2026 · Statut : Tous',
        );
      },
    );

    test('Catalogue : la période et la recherche seulement', () {
      expect(
        decrire(
          OngletTourisme.catalogue,
          statut: FiltreStatutDepart.annule,
          prestation: 'Tata Somba',
          recherche: 'atacora',
        ),
        'du 09/10/2026 au 08/11/2026 · Recherche : atacora',
      );
    });
  });
}
