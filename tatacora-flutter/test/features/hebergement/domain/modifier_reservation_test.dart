import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/unite_hebergement.dart';
import 'package:tatacora_flutter/features/hebergement/domain/repositories/reservation_repository.dart';
import 'package:tatacora_flutter/features/hebergement/domain/usecases/modifier_reservation.dart';

import 'depot_reservation_memoire.dart';

/// `ModifierReservation` — EF-M1-03.
///
/// ## Le cas qui commande tous les autres
///
/// Une réservation ne chevauche jamais elle-même. Sans exclusion, rouvrir une
/// fiche pour corriger un acompte serait refusé **par elle-même**, et l'écran
/// d'édition ne pourrait rien enregistrer — jamais. C'est un défaut qui ne se
/// voit pas à la relecture et qui bloque la fonction entière.
void main() {
  late DepotReservationMemoire depot;
  late ModifierReservation modifier;

  final demain = DateTime.now().add(const Duration(days: 1));
  PeriodeSejour periode(int dans, int puis) => PeriodeSejour(
    arrivee: demain.add(Duration(days: dans)),
    depart: demain.add(Duration(days: puis)),
  );

  const unite = UniteHebergement(
    id: 'u-1',
    numero: 'BNG-01',
    categorieId: 'cat-1',
    categorieLibelle: 'Bungalow',
    capaciteMax: 2,
    tarifBase: 28000,
    statut: StatutUnite.libre,
  );
  const autreUnite = UniteHebergement(
    id: 'u-2',
    numero: 'BNG-02',
    categorieId: 'cat-1',
    categorieLibelle: 'Bungalow',
    capaciteMax: 2,
    tarifBase: 30000,
    statut: StatutUnite.libre,
  );

  LigneService chambre({
    String itemId = 'u-1',
    int prix = 28000,
    int quantite = 2,
  }) => LigneService(
    id: 'l-1',
    service: ServiceReservation.hebergement,
    itemId: itemId,
    libelle: 'Bungalow',
    prixUnitaire: prix,
    quantite: quantite,
  );

  Reservation existante({
    String id = 'res-1',
    String uniteId = 'u-1',
    StatutReservation statut = StatutReservation.confirmee,
    StatutSynchronisation sync = StatutSynchronisation.synchronise,
    int acompte = 0,
    List<LigneService>? lignes,
    PeriodeSejour? p,
  }) => Reservation(
    id: id,
    reference: 'LOC-AAA',
    clientId: 'cli-1',
    clientNom: 'KORA Jean',
    uniteId: uniteId,
    periode: p ?? periode(10, 12),
    tarifNuit: 28000,
    statut: statut,
    statutSynchronisation: sync,
    creeeLe: DateTime(2026, 9, 1),
    acompte: acompte,
    canal: CanalReservation.booking,
    lignes: lignes ?? [chambre()],
  );

  setUp(() {
    depot = DepotReservationMemoire(unites: const [unite, autreUnite]);
    modifier = ModifierReservation(depot);
  });

  /* ================================================================== */
  group('Le contrôle de chevauchement exclut la réservation elle-même', () {
    test('changer le seul acompte est ACCEPTÉ', () async {
      final r = existante();
      await depot.enregistrer(r);

      final modifiee = await modifier(
        existante: r,
        unite: unite,
        clientNom: 'KORA Jean',
        periode: r.periode,
        acompte: 20000,
        lignes: r.lignes,
      );

      expect(modifiee.acompte, 20000);
      // L'exclusion a réellement été DEMANDÉE au dépôt : sans elle, le jeu de
      // test passerait quand même tant qu'il ne contient qu'une réservation.
      expect(depot.exclusionsDemandees, contains('res-1'));
    });

    test('un chevauchement avec une AUTRE réservation reste refusé', () async {
      final r = existante();
      await depot.enregistrer(r);
      await depot.enregistrer(
        existante(id: 'res-2', p: periode(11, 14)).copyWith(),
      );

      // La seconde occupe la même unité du 11 au 14 : déplacer la première
      // dessus doit être refusé, exclusion ou pas.
      await expectLater(
        modifier(
          existante: r,
          unite: unite,
          clientNom: 'KORA Jean',
          periode: periode(12, 15),
          lignes: r.lignes,
        ),
        throwsA(isA<ChevauchementDetecte>()),
      );
    });
  });

  /* ================================================================== */
  group('Ce que la modification conserve, et ce qu’elle remet', () {
    test(
      'l’identifiant, la référence et la date de création ne bougent pas',
      () async {
        final r = existante();
        await depot.enregistrer(r);

        final modifiee = await modifier(
          existante: r,
          unite: unite,
          clientNom: 'KORA Jean-Baptiste',
          periode: r.periode,
          lignes: r.lignes,
        );

        // C'est la MÊME réservation : un nouvel identifiant produirait deux
        // réservations sur la même chambre, la première continuant de bloquer
        // le planning.
        expect(modifiee.id, r.id);
        expect(modifiee.reference, r.reference);
        expect(modifiee.creeeLe, r.creeeLe);
        expect(modifiee.clientNom, 'KORA Jean-Baptiste');
      },
    );

    test('elle repart en « local », même si elle était synchronisée', () async {
      final r = existante(sync: StatutSynchronisation.synchronise);
      await depot.enregistrer(r);

      final modifiee = await modifier(
        existante: r,
        unite: unite,
        clientNom: 'KORA Jean',
        periode: r.periode,
        acompte: 5000,
        lignes: r.lignes,
      );

      // Sans cela, la correction resterait sur le poste : l'écran la
      // montrerait « synchronisée » alors que le serveur porte l'ancienne
      // version — un indicateur qui affirme un état qu'il n'a pas vérifié.
      expect(modifiee.statutSynchronisation, StatutSynchronisation.local);
      expect(depot.appelsModifier, 1);
    });

    test('le statut métier est conservé', () async {
      final r = existante(statut: StatutReservation.confirmee);
      await depot.enregistrer(r);

      final modifiee = await modifier(
        existante: r,
        unite: unite,
        clientNom: 'KORA Jean',
        periode: r.periode,
        lignes: r.lignes,
      );

      // Modifier une fiche ne confirme pas un séjour, et ne le déconfirme pas.
      expect(modifiee.statut, StatutReservation.confirmee);
    });

    test('changer de chambre reprend le tarif de la ligne RETENUE', () async {
      final r = existante();
      await depot.enregistrer(r);

      final modifiee = await modifier(
        existante: r,
        unite: autreUnite,
        clientNom: 'KORA Jean',
        periode: r.periode,
        lignes: [chambre(itemId: 'u-2', prix: 30000)],
      );

      expect(modifiee.uniteId, 'u-2');
      // Le prix vient de la ligne, figée au moment où l'utilisateur a choisi
      // la chambre — pas du tarif courant de l'unité relu à l'écriture.
      expect(modifiee.tarifNuit, 30000);
      expect(modifiee.montantTotal, 60000);
    });

    test('la fiche du maître est reportée', () async {
      final r = existante();
      await depot.enregistrer(r);

      final modifiee = await modifier(
        existante: r,
        unite: unite,
        clientNom: 'KORA Jean',
        periode: r.periode,
        lignes: r.lignes,
        typeClient: TypeClient.entreprise,
        canal: CanalReservation.telephone,
        modePaiement: ModePaiementReservation.cheque,
      );

      expect(modifiee.typeClient, TypeClient.entreprise);
      expect(modifiee.canal, CanalReservation.telephone);
      expect(modifiee.modePaiement, ModePaiementReservation.cheque);
    });
  });

  /* ================================================================== */
  group('Les refus', () {
    test('une réservation ANNULÉE ne se modifie pas', () async {
      final r = existante(statut: StatutReservation.annulee);
      await depot.enregistrer(r);

      // La « dé-annuler » réengagerait une chambre que le planning montre
      // libre depuis, et que quelqu'un a pu revendre entre-temps.
      await expectLater(
        modifier(
          existante: r,
          unite: unite,
          clientNom: 'KORA Jean',
          periode: r.periode,
          lignes: r.lignes,
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(depot.appelsModifier, 0);
    });

    test('un acompte supérieur au séjour est refusé', () async {
      final r = existante();
      await depot.enregistrer(r);

      await expectLater(
        modifier(
          existante: r,
          unite: unite,
          clientNom: 'KORA Jean',
          periode: r.periode,
          acompte: 100000,
          lignes: r.lignes,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('deux chambres sur une fiche restent refusées', () async {
      final r = existante();
      await depot.enregistrer(r);

      await expectLater(
        modifier(
          existante: r,
          unite: unite,
          clientNom: 'KORA Jean',
          periode: r.periode,
          lignes: [
            chambre(),
            LigneService(
              id: 'l-2',
              service: ServiceReservation.hebergement,
              itemId: 'u-2',
              libelle: 'Bungalow 2',
              prixUnitaire: 30000,
              quantite: 2,
            ),
          ],
        ),
        throwsA(isA<ArgumentError>()),
      );
      expect(depot.appelsModifier, 0);
    });

    test('une unité hors service est refusée', () async {
      const horsService = UniteHebergement(
        id: 'u-hs',
        numero: 'CH-999',
        categorieId: 'cat-1',
        categorieLibelle: 'Chambre',
        capaciteMax: 2,
        tarifBase: 18000,
        statut: StatutUnite.horsService,
      );
      final r = existante();
      await depot.enregistrer(r);

      await expectLater(
        modifier(
          existante: r,
          unite: horsService,
          clientNom: 'KORA Jean',
          periode: r.periode,
          lignes: [chambre(itemId: 'u-hs')],
        ),
        throwsA(isA<UniteIndisponible>()),
      );
    });
  });
}
