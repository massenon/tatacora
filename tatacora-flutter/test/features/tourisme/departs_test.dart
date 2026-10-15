import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/tourisme/domain/departs.dart';
import 'package:tatacora_flutter/features/tourisme/domain/entities/reservation_tour.dart';

/// Les RÈGLES de M9, éprouvées **hors de tout widget et de toute base**.
///
/// ## Pourquoi ce fichier en plus des tests de l'écran et du DAO
///
/// L'écran ne peut éprouver qu'un cas à la fois, à travers un formulaire, et
/// le DAO passe par SQLite. Or les deux endroits où cette règle se trompe sont
/// des **bords** : la place exactement disponible, et le cumul qui la dépasse
/// d'une unité. Une borne ne se teste que de part et d'autre (piège 7).
void main() {
  ReservationTour ligne({
    String id = 'r1',
    String circuitId = 'cir-1',
    String circuitNom = 'Cascades de Tanougou',
    int prix = 4500,
    int capacite = 12,
    String guideId = 'gui-1',
    String guideNom = 'ADJOVI Paul',
    DateTime? date,
    int participants = 5,
    StatutReservationTour statut = StatutReservationTour.reservee,
    String? duree,
  }) => ReservationTour(
    id: id,
    circuitId: circuitId,
    circuitNom: circuitNom,
    prixUnitaire: prix,
    capaciteCircuit: capacite,
    dureeCircuit: duree,
    clientId: 'cli-1',
    clientNom: 'KORA Jean',
    guideId: guideId,
    guideNom: guideNom,
    dateCircuit: date ?? DateTime(2026, 10, 12),
    nbParticipants: participants,
    statut: statut,
  );

  /* ================================================================== */
  group('RG-13 — la capacité est cumulée SUR LE DÉPART', () {
    test('trois groupes de 5 sur un circuit à 12 places : le 3e est refusé', () {
      // C'est le cas que la règle existe pour empêcher, et celui qu'une
      // lecture littérale (« une réservation ne dépasse pas la capacité »)
      // laisse passer : chaque groupe pris isolément tient dans 12 places.
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 0, demandes: 5),
        isNull,
      );
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 5, demandes: 5),
        isNull,
      );

      final refus = refusDeCapaciteCumulee(
        capacite: 12,
        dejaVendues: 10,
        demandes: 5,
      );

      expect(refus, isNotNull);
      // Le message NOMME les trois nombres : un « Départ complet » sec
      // laisserait croire à une erreur de saisie, alors que c'est le cumul qui
      // bloque.
      expect(refus, contains('5 participants demandés'));
      expect(refus, contains('2 place(s) encore disponible(s)'));
      expect(refus, contains('capacité du circuit : 12'));
    });

    test('la borne exacte passe, une place de plus est refusée', () {
      // De part et d'autre : sans le second cas, un `>=` fautif resterait vert.
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 10, demandes: 2),
        isNull,
      );
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 10, demandes: 3),
        isNotNull,
      );
    });

    test('un départ complet refuse même une seule place', () {
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 12, demandes: 1),
        contains('0 place(s) encore disponible(s)'),
      );
    });

    test('zéro participant est refusé, et pas par le message de capacité', () {
      // Une quantité saisie à zéro ne devient jamais une réservation vide :
      // le refus le dit avec ses propres mots.
      expect(
        refusDeCapaciteCumulee(capacite: 12, dejaVendues: 0, demandes: 0),
        MessagesTourisme.participantsMinimum,
      );
    });

    test('les places restantes ne sont jamais négatives', () {
      // Une base déjà sur-réservée (deux postes, ou une reprise) ne doit pas
      // afficher « -3 places » : le tableau dirait qu'il en reste.
      expect(placesRestantesPour(capacite: 12, dejaVendues: 15), 0);
    });
  });

  /* ================================================================== */
  group('Un départ est DÉRIVÉ de ses lignes', () {
    test('deux groupes du même jour font UN départ, pas deux', () {
      final departs = departsDerives([
        ligne(id: 'r1', participants: 5),
        ligne(id: 'r2', participants: 4),
      ]);

      expect(departs, hasLength(1));
      expect(departs.single.placesVendues, 9);
      expect(departs.single.placesRestantes, 3);
      // Le chiffre d'affaires est la somme des lignes ACTIVES.
      expect(departs.single.chiffreAffaires, 9 * 4500);
    });

    test('deux dates du même circuit font DEUX départs', () {
      final departs = departsDerives([
        ligne(id: 'r1', date: DateTime(2026, 10, 12)),
        ligne(id: 'r2', date: DateTime(2026, 10, 13)),
      ]);

      expect(departs, hasLength(2));
    });

    test('une ligne annulée ne compte ni en places ni en argent', () {
      final departs = departsDerives([
        ligne(id: 'r1', participants: 5),
        ligne(id: 'r2', participants: 4, statut: StatutReservationTour.annulee),
      ]);

      expect(departs.single.placesVendues, 5);
      expect(departs.single.chiffreAffaires, 5 * 4500);
      // Le départ reste ACTIF : il lui reste une ligne vivante.
      expect(departs.single.annule, isFalse);
    });

    test(
      'un départ dont TOUTES les lignes sont annulées reste visible, annulé',
      () {
        // Le faire disparaître de la grille empêcherait de savoir ce qu'il est
        // devenu. Il naît `annule: true` et ne repasse à `false` que si une
        // ligne active est rencontrée.
        final departs = departsDerives([
          ligne(id: 'r1', statut: StatutReservationTour.annulee),
        ]);

        expect(departs, hasLength(1));
        expect(departs.single.annule, isTrue);
        expect(departs.single.placesVendues, 0);
        // Aucun guide : une ligne annulée n'en donne pas au départ.
        expect(departs.single.guideNom, isNull);
      },
    );

    test('le guide du départ vient de sa première ligne ACTIVE', () {
      final departs = departsDerives([
        ligne(
          id: 'r1',
          guideId: 'gui-annule',
          guideNom: 'Guide annulé',
          statut: StatutReservationTour.annulee,
        ),
        ligne(id: 'r2', guideId: 'gui-2', guideNom: 'SOSSOU Amélie'),
      ]);

      expect(departs.single.guideNom, 'SOSSOU Amélie');
      expect(departs.single.guideId, 'gui-2');
    });

    test('une prestation CLÔTURÉE occupe toujours ses places', () {
      // `STATUTS_INACTIFS` ne contient que `annulee` : un circuit qui a eu
      // lieu a bien consommé ses places.
      final departs = departsDerives([
        ligne(participants: 5, statut: StatutReservationTour.terminee),
      ]);

      expect(departs.single.placesVendues, 5);
    });

    test('l\'heure de saisie ne fabrique pas deux départs', () {
      // Un départ est un JOUR. Sans normalisation, deux saisies du même jour à
      // des heures différentes donneraient deux départs de 12 places chacun.
      final departs = departsDerives([
        ligne(id: 'r1', date: DateTime(2026, 10, 12, 8, 30)),
        ligne(id: 'r2', date: DateTime(2026, 10, 12, 17, 5)),
      ]);

      expect(departs, hasLength(1));
    });
  });

  /* ================================================================== */
  group('L\'état d\'un départ se DÉDUIT — il n\'est stocké nulle part', () {
    Depart departAvec({required int vendues, bool annule = false}) =>
        departsDerives([
          ligne(
            participants: vendues,
            statut: annule
                ? StatutReservationTour.annulee
                : StatutReservationTour.reservee,
          ),
        ]).single;

    test('il reste des places', () {
      final d = departAvec(vendues: 5);
      expect(d.etat, EtatDepart.placesDisponibles);
      expect(d.placesRestantes, 7);
    });

    test('plus une seule place : complet', () {
      expect(departAvec(vendues: 12).etat, EtatDepart.complet);
    });

    test('toutes les lignes annulées : annulé', () {
      // ⚠ L'annulation PRIME sur le remplissage : un départ annulé dont les
      // 12 places étaient vendues n'est pas « complet », il n'a plus lieu.
      final d = departAvec(vendues: 12, annule: true);
      expect(d.etat, EtatDepart.annule);
    });

    test('la jauge est plafonnée à 100 %', () {
      // Une base sur-réservée ne doit pas rendre une barre qui déborde.
      final d = departsDerives([
        ligne(id: 'r1', participants: 12),
        ligne(id: 'r2', participants: 6),
      ]).single;

      expect(d.pourcentageRemplissage, 100);
    });
  });

  /* ================================================================== */
  group('Les agrégats de la bande d\'indicateurs', () {
    test('places, capacité, chiffre d\'affaires et complets', () {
      final departs = departsDerives([
        ligne(id: 'r1', circuitId: 'cir-1', participants: 12),
        ligne(
          id: 'r2',
          circuitId: 'cir-2',
          circuitNom: 'Chutes de Kota',
          participants: 4,
          capacite: 10,
          prix: 3000,
        ),
      ]);

      final a = agregerDeparts(departs);

      expect(a.departs, 2);
      expect(a.placesVendues, 16);
      expect(a.capaciteOfferte, 22);
      expect(a.complets, 1);
      expect(a.chiffreAffaires, 12 * 4500 + 4 * 3000);
    });

    test('aucune capacité offerte : le taux est NUL, jamais « 0 % »', () {
      // « 0 % » se lirait comme un départ désert, alors qu'il n'y a rien à
      // remplir. Les deux situations ne se corrigent pas de la même façon.
      expect(agregerDeparts(const []).tauxRemplissage, isNull);
    });

    test('le taux est arrondi à UNE décimale, comme au serveur', () {
      final a = agregerDeparts(
        departsDerives([ligne(participants: 5, capacite: 12)]),
      );

      // 5/12 = 41,666… %
      expect(a.tauxRemplissage, 41.7);
      expect(formaterTaux(a.tauxRemplissage!), '41.7');
    });

    test('un taux entier ne traîne pas de décimale', () {
      expect(formaterTaux(100), '100');
      expect(formaterTaux(50), '50');
    });

    test('une durée ABSENTE compte comme « durée indéterminée »', () {
      // ⚠ Ce cas exigeait l'INVERSE (`0`), et il avait raison en v9 : `null`
      // disait alors « colonne absente », et compter aurait mesuré l'absence
      // de la colonne, pas les durées (PA-59/60/61). Son propre commentaire
      // annonçait la suite — « le jour où la colonne existera, le compte
      // reprendra tout seul ». La v10 l'a livrée le 14/09/2026 : `null` veut
      // désormais dire « aucune durée renseignée », ce que la règle du serveur
      // traite comme indéterminée. Garder le garde-fou exclurait du compte les
      // circuits sans durée — les plus indéterminés de tous.
      final a = agregerDeparts(departsDerives([ligne(duree: null)]));
      expect(a.dureeIndeterminee, 1);

      // Et le jour où la colonne existera, le compte reprendra tout seul.
      final b = agregerDeparts(
        departsDerives([ligne(duree: 'Plusieurs jours')]),
      );
      expect(b.dureeIndeterminee, 1);
    });
  });

  /* ================================================================== */
  group('« duree » est un texte LIBRE — la règle teste un chiffre', () {
    test('une durée exploitable contient un chiffre', () {
      expect(dureeIndeterminee('3 jours / 2 nuits'), isFalse);
      expect(dureeIndeterminee('1 journée'), isFalse);
      // La règle teste la PRÉSENCE d'un chiffre, pas sa position : reprise
      // telle quelle du serveur, sans « correction » silencieuse.
      expect(dureeIndeterminee('journée de 8 heures'), isFalse);
    });

    test('« Plusieurs jours » n\'est pas une durée exploitable', () {
      // Conséquence métier : un tel circuit ne bloque que son JOUR de départ.
      expect(dureeIndeterminee('Plusieurs jours'), isTrue);
      expect(dureeIndeterminee('Variable'), isTrue);
      expect(dureeIndeterminee(''), isTrue);
      expect(dureeIndeterminee(null), isTrue);
    });
  });

  /* ================================================================== */
  group('Le montant d\'une réservation est CALCULÉ', () {
    test('prix du circuit x participants', () {
      expect(ligne(prix: 4500, participants: 4).montant, 18000);
    });

    test('le statut ne change pas le montant, seulement son décompte', () {
      // Une ligne annulée garde son montant : c'est la dérivation du départ
      // qui l'écarte, pas l'entité qui le met à zéro.
      expect(
        ligne(
          prix: 4500,
          participants: 4,
          statut: StatutReservationTour.annulee,
        ).montant,
        18000,
      );
    });
  });

  /* ================================================================== */
  group('Le statut est un registre FERMÉ', () {
    test('les quatre valeurs du serveur sont reconnues', () {
      expect(
        StatutReservationTour.depuisCle('reservee'),
        StatutReservationTour.reservee,
      );
      expect(
        StatutReservationTour.depuisCle('annulee'),
        StatutReservationTour.annulee,
      );
      expect(
        StatutReservationTour.depuisCle('terminee'),
        StatutReservationTour.terminee,
      );
      expect(
        StatutReservationTour.depuisCle('en_cours'),
        StatutReservationTour.enCours,
      );
    });

    test('une valeur inconnue rend `null`, jamais « réservée »', () {
      // Un `default => reservee` ferait compter une ligne cassée comme une
      // place vendue, et fausserait la capacité du départ.
      expect(StatutReservationTour.depuisCle('brouillon'), isNull);
      expect(StatutReservationTour.depuisCle(''), isNull);
    });

    test('seule l\'annulation libère une place', () {
      expect(StatutReservationTour.annulee.estAnnulee, isTrue);
      expect(StatutReservationTour.terminee.estAnnulee, isFalse);
      expect(StatutReservationTour.enCours.estAnnulee, isFalse);
    });
  });
}
