import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/occupation_mensuelle.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';

/// Le calendrier d'occupation — `m1-hebergement.html`.
///
/// ## Pourquoi ces cas portent sur des BORNES
///
/// Un taux d'occupation se joue à un jour près, et deux bornes décident de
/// tout : le jour d'arrivée compte, le jour de départ **non** — la chambre se
/// reloue le soir même. Se tromper d'un jour par séjour gonfle le taux d'un
/// tiers sur un mois plein, et c'est sur ce taux qu'on décide d'une
/// sur-réservation.
void main() {
  Reservation reservation({
    String id = 'res-1',
    required int duJour,
    required int auJour,
    int chambres = 1,
    StatutReservation statut = StatutReservation.confirmee,
    List<LigneService>? lignes,
  }) => Reservation(
    id: id,
    reference: 'LOC-$id',
    clientId: 'cli-1',
    clientNom: 'KORA Jean',
    uniteId: 'u-1',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 9, duJour),
      depart: DateTime(2026, 9, auJour),
    ),
    tarifNuit: 28000,
    statut: statut,
    statutSynchronisation: StatutSynchronisation.local,
    creeeLe: DateTime(2026, 9),
    lignes:
        lignes ??
        [
          for (var i = 0; i < chambres; i++)
            LigneService(
              id: 'l-$id-$i',
              service: ServiceReservation.hebergement,
              itemId: 'u-$i',
              libelle: 'Chambre $i',
              prixUnitaire: 28000,
              quantite: 2,
            ),
        ],
  );

  OccupationMensuelle calculer(
    List<Reservation> reservations, {
    int totalUnites = 6,
  }) => OccupationMensuelle.calculer(
    reference: DateTime(2026, 9, 15),
    reservations: reservations,
    totalUnites: totalUnites,
  );

  JourOccupation le(OccupationMensuelle o, int jour) =>
      o.jours.firstWhere((j) => j.jour.day == jour);

  /* ================================================================== */
  group('Les bornes du séjour', () {
    test('le jour d’ARRIVÉE compte', () {
      final o = calculer([reservation(duJour: 10, auJour: 12)]);
      expect(le(o, 10).unitesOccupees, 1);
    });

    test('le jour de DÉPART ne compte pas', () {
      // La chambre se libère le matin du départ : elle est relouable le soir
      // même. La compter occupée gonflerait le taux d'un jour par séjour.
      final o = calculer([reservation(duJour: 10, auJour: 12)]);
      expect(le(o, 11).unitesOccupees, 1);
      expect(le(o, 12).unitesOccupees, 0);
    });

    test('la veille de l’arrivée ne compte pas non plus', () {
      final o = calculer([reservation(duJour: 10, auJour: 12)]);
      expect(le(o, 9).unitesOccupees, 0);
    });
  });

  /* ================================================================== */
  group('Ce qui pèse, et ce qui ne pèse pas', () {
    test('une réservation ANNULÉE n’occupe rien', () {
      final o = calculer([
        reservation(duJour: 10, auJour: 12, statut: StatutReservation.annulee),
      ]);
      expect(le(o, 10).unitesOccupees, 0);
    });

    test('une fiche SANS hébergement n’occupe aucune chambre', () {
      // Un circuit seul ne retient pas d'unité : l'y compter ferait chercher
      // une chambre qui n'a jamais été prise.
      final o = calculer([
        reservation(
          duJour: 10,
          auJour: 12,
          lignes: const [
            LigneService(
              id: 'l-tour',
              service: ServiceReservation.tourisme,
              itemId: 'c-1',
              libelle: 'Cascades',
              prixUnitaire: 15000,
              quantite: 2,
            ),
          ],
        ),
      ]);
      expect(le(o, 10).unitesOccupees, 0);
    });

    test('une réservation d’avant la v8 compte pour UNE unité', () {
      // Elle n'a aucune ligne, mais elle porte bien `unite_id`. La compter
      // pour zéro ferait disparaître tout l'historique du poste de la grille.
      final o = calculer([
        reservation(duJour: 10, auJour: 12, lignes: const []),
      ]);
      expect(le(o, 10).unitesOccupees, 1);
    });

    test('une fiche à deux chambres compte pour DEUX', () {
      final o = calculer([reservation(duJour: 10, auJour: 12, chambres: 2)]);
      expect(le(o, 10).unitesOccupees, 2);
    });

    test('le compte est BORNÉ au parc', () {
      // Deux réservations sur la même chambre — un conflit que RG-01 doit
      // empêcher, mais qui peut exister le temps d'une synchronisation — ne
      // doivent pas faire afficher « 8/6 ».
      final o = calculer([
        for (var i = 0; i < 8; i++)
          reservation(id: 'res-$i', duJour: 10, auJour: 12),
      ]);
      expect(le(o, 10).unitesOccupees, 6);
      expect(le(o, 10).taux, 1);
    });
  });

  /* ================================================================== */
  group('Les paliers du maître', () {
    test('aucune unité : palier vide, et aucun compte affiché', () {
      final o = calculer(const []);
      expect(le(o, 10).palier, PalierOccupation.vide);
      expect(le(o, 10).estOccupe, isFalse);
    });

    test('sous la moitié : faible', () {
      final o = calculer([
        reservation(duJour: 10, auJour: 12, chambres: 2),
      ]); // 2/6
      expect(le(o, 10).palier, PalierOccupation.faible);
    });

    test('à la moitié exactement : moyen', () {
      // Le seuil du maître est `taux < 0.5` pour « faible » : à 0,5 pile, on
      // bascule. Un test posé à 0,4 ou 0,6 ne verrait pas ce choix.
      final o = calculer([
        reservation(duJour: 10, auJour: 12, chambres: 3),
      ]); // 3/6
      expect(le(o, 10).palier, PalierOccupation.moyen);
    });

    test('à 90 % : fort', () {
      final o = calculer([
        for (var i = 0; i < 6; i++)
          reservation(id: 'res-$i', duJour: 10, auJour: 12),
      ]); // 6/6
      expect(le(o, 10).palier, PalierOccupation.fort);
    });

    test('un parc VIDE ne produit pas de division par zéro', () {
      // Un `NaN` peint une case dans la couleur du hasard.
      final o = calculer([reservation(duJour: 10, auJour: 12)], totalUnites: 0);
      expect(le(o, 10).taux, 0);
      expect(le(o, 10).taux.isNaN, isFalse);
    });
  });

  /* ================================================================== */
  group('La grille du mois', () {
    test('septembre 2026 compte 30 jours', () {
      expect(calculer(const []).jours, hasLength(30));
    });

    test('février 2028 en compte 29 — année bissextile', () {
      // Le `0` du mois suivant donne le dernier jour du mois courant, sans
      // avoir à savoir lequel compte 28, 29, 30 ou 31 jours.
      final o = OccupationMensuelle.calculer(
        reference: DateTime(2028, 2, 15),
        reservations: const [],
        totalUnites: 6,
      );
      expect(o.jours, hasLength(29));
    });

    test('le décalage place le 1er sous le bon jour de la semaine', () {
      // Le 1er septembre 2026 est un MARDI : une case vide avant lui.
      // Sans ce décalage, la grille entière ment d'un à six jours.
      expect(calculer(const []).decalagePremierJour, 1);
    });
  });
}
