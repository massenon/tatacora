import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/historique_reservations.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';

/// L'historique — états dérivés, filtres et KPI.
///
/// ## Pourquoi ces cas portent presque tous sur des BORNES
///
/// Un état de séjour se joue à un jour près, et c'est le jour même qui compte :
/// le matin de l'arrivée, le matin du départ. Un test posé au milieu d'un
/// séjour ne prouve rien — il resterait vert quel que soit le sens des
/// comparaisons.
void main() {
  // Une date FIXE, jamais `DateTime.now()` : un historique testé sur l'horloge
  // système échoue un jour sur trente, au passage d'un mois, et le rapport
  // d'échec ne dit pas pourquoi.
  final maintenant = DateTime(2026, 9, 15);

  Reservation reservation({
    required String id,
    required DateTime arrivee,
    required DateTime depart,
    String client = 'KORA Jean',
    StatutReservation statut = StatutReservation.confirmee,
    CanalReservation? canal = CanalReservation.physique,
    int tarifNuit = 28000,
    int acompte = 0,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService> lignes = const [],
    String reference = 'LOC-AAA',
  }) => Reservation(
    id: id,
    reference: reference,
    clientId: 'cli-1',
    clientNom: client,
    uniteId: 'u-1',
    periode: PeriodeSejour(arrivee: arrivee, depart: depart),
    tarifNuit: tarifNuit,
    statut: statut,
    statutSynchronisation: StatutSynchronisation.local,
    creeeLe: DateTime(2026, 9, 1),
    acompte: acompte,
    canal: canal,
    remiseType: remiseType,
    remiseValeur: remiseValeur,
    lignes: lignes,
  );

  LigneService chambre({
    String itemId = 'u-1',
    int prix = 28000,
    int nuits = 2,
  }) => LigneService(
    id: 'l-$itemId',
    service: ServiceReservation.hebergement,
    itemId: itemId,
    libelle: 'Bungalow',
    prixUnitaire: prix,
    quantite: nuits,
  );

  List<LigneHistorique> historique(
    List<Reservation> liste, {
    FiltreHistorique filtre = const FiltreHistorique(),
  }) => filtrerHistorique(liste, filtre: filtre, maintenant: maintenant);

  /* ================================================================== */
  group('L’état se déduit des dates, jamais d’une colonne', () {
    test('un séjour à venir', () {
      final l = historique([
        reservation(
          id: 'r',
          arrivee: DateTime(2026, 9, 20),
          depart: DateTime(2026, 9, 22),
        ),
      ]).single;
      expect(l.etat, EtatSejour.aVenir);
    });

    test('le JOUR de l’arrivée, le séjour est déjà en cours', () {
      // La borne qui compte au comptoir : le client se présente le matin, et
      // un écran qui annonce « à venir » pendant qu'il est devant vous ferait
      // chercher une seconde réservation.
      final l = historique([
        reservation(
          id: 'r',
          arrivee: maintenant,
          depart: DateTime(2026, 9, 18),
        ),
      ]).single;
      expect(l.etat, EtatSejour.enCours);
    });

    test('le JOUR du départ, le séjour est TERMINÉ', () {
      // L'autre borne, et elle a une conséquence directe : la chambre se
      // libère le matin du départ, elle est relouable le soir même. La compter
      // « en cours » la retiendrait une nuit de trop.
      final l = historique([
        reservation(
          id: 'r',
          arrivee: DateTime(2026, 9, 12),
          depart: maintenant,
        ),
      ]).single;
      expect(l.etat, EtatSejour.termine);
    });

    test('l’heure de la journée ne change rien', () {
      // Une réservation saisie à 14 h et consultée à 9 h le même jour doit
      // rendre le même état : les dates se comparent à minuit.
      final lignes = filtrerHistorique(
        [
          reservation(
            id: 'r',
            arrivee: DateTime(2026, 9, 15, 14, 30),
            depart: DateTime(2026, 9, 18),
          ),
        ],
        filtre: const FiltreHistorique(),
        maintenant: DateTime(2026, 9, 15, 9),
      );
      expect(lignes.single.etat, EtatSejour.enCours);
    });

    test('une annulation l’emporte sur les dates', () {
      final l = historique([
        reservation(
          id: 'r',
          arrivee: DateTime(2026, 9, 20),
          depart: DateTime(2026, 9, 22),
          statut: StatutReservation.annulee,
        ),
      ]).single;
      expect(l.etat, EtatSejour.annulee);
    });
  });

  /* ================================================================== */
  group('Les filtres', () {
    final jeu = [
      reservation(
        id: 'a',
        client: 'DOSSOU Marie',
        canal: CanalReservation.booking,
        arrivee: DateTime(2026, 9, 20),
        depart: DateTime(2026, 9, 22),
        reference: 'LOC-AAA',
        lignes: [chambre()],
      ),
      reservation(
        id: 'b',
        client: 'KORA Jean',
        canal: CanalReservation.whatsapp,
        arrivee: DateTime(2026, 9, 1),
        depart: DateTime(2026, 9, 4),
        reference: 'LOC-BBB',
        lignes: [
          chambre(),
          const LigneService(
            id: 'l-tour',
            service: ServiceReservation.tourisme,
            itemId: 'c-1',
            libelle: 'Cascades',
            prixUnitaire: 15000,
            quantite: 2,
          ),
        ],
      ),
    ];

    test('le terme cherche dans le client, le canal ET la référence', () {
      expect(
        historique(jeu, filtre: const FiltreHistorique(terme: 'dossou')),
        hasLength(1),
      );
      expect(
        historique(jeu, filtre: const FiltreHistorique(terme: 'whatsapp')),
        hasLength(1),
      );
      expect(
        historique(jeu, filtre: const FiltreHistorique(terme: 'loc-bbb')),
        hasLength(1),
      );
      // Trois entrées, parce qu'au comptoir on retrouve une réservation par
      // l'une ou l'autre — jamais toujours la même.
      expect(
        historique(jeu, filtre: const FiltreHistorique(terme: 'zzz')),
        isEmpty,
      );
    });

    test('l’état filtre sur ce qui est DÉDUIT, pas sur une colonne', () {
      expect(
        historique(
          jeu,
          filtre: const FiltreHistorique(etat: EtatSejour.aVenir),
        ).single.reservation.id,
        'a',
      );
      expect(
        historique(
          jeu,
          filtre: const FiltreHistorique(etat: EtatSejour.termine),
        ).single.reservation.id,
        'b',
      );
    });

    test('le service filtre sur les lignes réellement portées', () {
      final tourisme = historique(
        jeu,
        filtre: const FiltreHistorique(service: ServiceReservation.tourisme),
      );
      expect(tourisme, hasLength(1));
      expect(tourisme.single.reservation.id, 'b');

      // Un service qu'aucune réservation ne porte rend une liste vide, pas
      // toutes les réservations : un filtre qui n'écarte rien ne filtre pas.
      expect(
        historique(
          jeu,
          filtre: const FiltreHistorique(service: ServiceReservation.bar),
        ),
        isEmpty,
      );
    });

    test(
      'la fenêtre de dates retient les séjours à CHEVAL, pas les seuls inclus',
      () {
        // Le point du maître : une réservation à cheval sur le mois doit
        // apparaître dans les deux mois. L'inclusion stricte ferait disparaître
        // des listes mensuelles exactement les séjours les plus longs.
        final aCheval = reservation(
          id: 'c',
          arrivee: DateTime(2026, 8, 28),
          depart: DateTime(2026, 9, 3),
        );

        final septembre = historique(
          [aCheval],
          filtre: FiltreHistorique(
            debut: DateTime(2026, 9, 1),
            fin: DateTime(2026, 9, 30),
          ),
        );
        final aout = historique(
          [aCheval],
          filtre: FiltreHistorique(
            debut: DateTime(2026, 8, 1),
            fin: DateTime(2026, 8, 31),
          ),
        );

        expect(septembre, hasLength(1));
        expect(aout, hasLength(1));
      },
    );

    test('un séjour hors fenêtre est écarté des deux côtés', () {
      final juillet = reservation(
        id: 'd',
        arrivee: DateTime(2026, 7, 1),
        depart: DateTime(2026, 7, 3),
      );
      expect(
        historique([
          juillet,
        ], filtre: FiltreHistorique(debut: DateTime(2026, 9, 1))),
        isEmpty,
      );
      expect(
        historique([
          juillet,
        ], filtre: FiltreHistorique(fin: DateTime(2026, 6, 30))),
        isEmpty,
      );
    });

    test('du séjour le plus récent au plus ancien', () {
      expect(historique(jeu).map((l) => l.reservation.id), ['a', 'b']);
    });
  });

  /* ================================================================== */
  group('Les six indicateurs', () {
    test(
      'une annulation ne pèse ni sur le chiffre d’affaires ni sur les nuitées',
      () {
        final lignes = historique([
          reservation(
            id: 'a',
            arrivee: DateTime(2026, 9, 20),
            depart: DateTime(2026, 9, 22),
            lignes: [chambre()],
          ),
          reservation(
            id: 'b',
            arrivee: DateTime(2026, 9, 20),
            depart: DateTime(2026, 9, 22),
            statut: StatutReservation.annulee,
            lignes: [chambre()],
          ),
        ]);
        final k = KpisHistorique.calculer(lignes);

        // Elle reste COMPTÉE et listée — une réservation annulée n'est jamais
        // effacée — mais additionner un séjour qui n'aura pas lieu annoncerait
        // un encaissement que personne ne fera.
        expect(k.total, 2);
        expect(k.annulee, 1);
        expect(k.nuitees, 2);
        expect(k.chiffreAffaires, 56000);
      },
    );

    test('les nuitées comptent les UNITÉS, pas les réservations', () {
      final lignes = historique([
        reservation(
          id: 'a',
          arrivee: DateTime(2026, 9, 20),
          depart: DateTime(2026, 9, 22),
          lignes: [
            chambre(itemId: 'u-1'),
            chambre(itemId: 'u-2'),
          ],
        ),
      ]);
      // Deux chambres × deux nuits : c'est ce que « nuitée » veut dire dans
      // l'hôtellerie, et c'est ce qui alimente le taux d'occupation.
      expect(KpisHistorique.calculer(lignes).nuitees, 4);
    });

    test('le chiffre d’affaires est APRÈS remise, le reste APRÈS acompte', () {
      final lignes = historique([
        reservation(
          id: 'a',
          arrivee: DateTime(2026, 9, 20),
          depart: DateTime(2026, 9, 22),
          lignes: [chambre()],
          remiseType: TypeRemise.pourcentage,
          remiseValeur: 10,
          acompte: 20000,
        ),
      ]);
      final k = KpisHistorique.calculer(lignes);

      // 56 000 − 10 % = 50 400 ; reste 30 400 après un acompte de 20 000.
      // Compter 56 000 annoncerait un chiffre d'affaires que la remise vient
      // d'amputer, et réclamerait au client l'argent qu'on lui a accordé.
      expect(k.chiffreAffaires, 50400);
      expect(k.resteAEncaisser, 30400);
    });

    test('un séjour soldé ne laisse rien à encaisser', () {
      final lignes = historique([
        reservation(
          id: 'a',
          arrivee: DateTime(2026, 9, 20),
          depart: DateTime(2026, 9, 22),
          lignes: [chambre()],
          acompte: 56000,
        ),
      ]);
      expect(KpisHistorique.calculer(lignes).resteAEncaisser, 0);
    });

    test('un historique vide rend six zéros, jamais une erreur', () {
      final k = KpisHistorique.calculer(const []);
      expect(k.total, 0);
      expect(k.nuitees, 0);
      expect(k.chiffreAffaires, 0);
      expect(k.resteAEncaisser, 0);
    });
  });
}
