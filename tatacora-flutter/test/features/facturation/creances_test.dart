import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';

/// La créance d'une facture — **unitaire, sans base ni écran**.
///
/// ## Ce que ces cas protègent
///
/// **Que le reste dû soit celui du serveur** (`Facture::SQL_RESTE_DU`) : TTC −
/// avoirs − paiements ACTIFS − acomptes liés, sans plancher dans le prédicat. La
/// formule est lue par le solde des clients, le refus de sur-encaissement, M11 et
/// M14 : une erreur ici fausse les quatre à la fois, sans qu'aucun ne s'en
/// aperçoive. Chaque terme a son cas ; chaque cas est prouvé non vide par une
/// mutation (voir le journal du lot).
void main() {
  PieceFacturation facture(
    String id, {
    int montant = 50000,
    String? clientId = 'c1',
    String? reservationId,
    OrigineFacture origine = OrigineFacture.factureDirecte,
    ModuleFacturable module = ModuleFacturable.m5Bar,
    DateTime? emise,
    StatutPiece statut = StatutPiece.emise,
  }) => PieceFacturation(
    id: id,
    numero: 'F-2026-$id',
    origine: origine,
    dateEmission: emise ?? DateTime(2026, 10, 1, 9),
    clientNom: 'KORA',
    statut: statut,
    clientId: clientId,
    reservationId: reservationId,
    lignes: [
      LigneFacture(
        id: '$id-l1',
        module: module,
        libelle: 'Prestation',
        prixUnitaire: montant,
        quantite: 1,
        ordre: 0,
      ),
    ],
  );

  PieceFacturation avoirDe(PieceFacturation f, {int? montant}) =>
      PieceFacturation(
        id: 'a-${f.id}',
        numero: 'F-2026-a${f.id}',
        origine: f.origine,
        dateEmission: DateTime(2026, 10, 2),
        clientNom: f.clientNom,
        statut: StatutPiece.emise,
        clientId: f.clientId,
        reservationId: f.reservationId,
        avoirDe: f.numero,
        lignes: [
          LigneFacture(
            id: 'a-${f.id}-l1',
            module: f.lignes.first.module,
            libelle: 'Prestation',
            prixUnitaire: montant ?? f.lignes.first.prixUnitaire,
            // Sens inverse par la QUANTITÉ, comme `FactureDao.annuler`.
            quantite: -1,
            ordre: 0,
          ),
        ],
      );

  PaiementFacture paiement(
    String id,
    PieceFacturation f,
    int centimes, {
    StatutPaiementFacture statut = StatutPaiementFacture.actif,
    DateTime? date,
    String session = 's1',
  }) => PaiementFacture(
    id: id,
    pieceId: f.id,
    sessionId: session,
    mode: ModePaiementFacture.especes,
    montantCentimes: centimes,
    datePaiement: date ?? DateTime(2026, 10, 5, 10),
    statut: statut,
    utilisateurCreationId: 'u1',
  );

  CreanceFacture creanceDe(
    PieceFacturation f, {
    List<PieceFacturation> avoirs = const [],
    List<PaiementFacture> paiements = const [],
    Map<String, int> acomptes = const {},
  }) => composerCreances(
    pieces: [f, ...avoirs],
    paiements: paiements,
    acomptesParReservation: acomptes,
  ).firstWhere((c) => c.piece.id == f.id);

  group('Le reste dû', () {
    test('une facture sans rien d’autre vaut son TTC, en centimes', () {
      final c = creanceDe(facture('f1', montant: 50000));
      expect(c.ttcCentimes, 5000000);
      expect(c.resteDuBrutCentimes, 5000000);
      expect(c.estImpayee, isTrue);
    });

    test('un encaissement ACTIF le diminue', () {
      final f = facture('f1');
      final c = creanceDe(f, paiements: [paiement('p1', f, 3000000)]);
      expect(c.paiementsActifsCentimes, 3000000);
      expect(c.resteDuCentimes, 2000000);
    });

    test('un encaissement ANNULÉ ne compte plus', () {
      final f = facture('f1');
      final c = creanceDe(
        f,
        paiements: [
          paiement('p1', f, 3000000, statut: StatutPaiementFacture.annule),
        ],
      );
      expect(c.paiementsActifsCentimes, 0);
      expect(c.resteDuCentimes, 5000000);
    });

    test('un avoir le diminue (en valeur absolue)', () {
      final f = facture('f1');
      final c = creanceDe(f, avoirs: [avoirDe(f, montant: 12000)]);
      expect(c.avoirsCentimes, 1200000);
      expect(c.resteDuCentimes, 3800000);
    });

    test('l’avoir d’UNE facture ne diminue pas celle d’une autre', () {
      final f1 = facture('f1');
      final f2 = facture('f2');
      final c = creanceDe(f2, avoirs: [avoirDe(f1)]);
      expect(c.avoirsCentimes, 0);
    });

    test('l’acompte de la réservation liée le diminue, SI la facture porte '
        'une ligne d’hébergement', () {
      final f = facture(
        'f1',
        reservationId: 'r1',
        module: ModuleFacturable.m1Hebergement,
      );
      final c = creanceDe(f, acomptes: {'r1': 20000});
      expect(c.acomptesCentimes, 2000000);
      expect(c.resteDuCentimes, 3000000);
    });

    test('sans ligne d’hébergement, l’acompte n’est PAS déduit', () {
      // Une facture de consommations rattachée à la réservation ne reprend pas
      // l'avance de la nuitée : `source_module = 'M1'` du serveur.
      final f = facture('f1', reservationId: 'r1');
      final c = creanceDe(f, acomptes: {'r1': 20000});
      expect(c.acomptesCentimes, 0);
    });

    test('sans réservation, aucun acompte', () {
      final f = facture('f1', module: ModuleFacturable.m1Hebergement);
      final c = creanceDe(f, acomptes: {'r1': 20000});
      expect(c.acomptesCentimes, 0);
    });

    test('le brut n’est PAS plafonné, le reste dû l’est', () {
      // Le prédicat « impayée » et le solde lisent le brut ; l'écran et le refus
      // de sur-encaissement lisent le plafonné. Un négatif doit se voir.
      final f = facture('f1', montant: 10000);
      final c = creanceDe(f, paiements: [paiement('p1', f, 1500000)]);
      expect(c.resteDuBrutCentimes, -500000);
      expect(c.resteDuCentimes, 0);
      expect(c.estImpayee, isFalse);
      expect(c.estSoldee, isTrue);
    });

    test('exactement soldée : ni impayée, ni négative', () {
      final f = facture('f1', montant: 10000);
      final c = creanceDe(f, paiements: [paiement('p1', f, 1000000)]);
      expect(c.resteDuBrutCentimes, 0);
      expect(c.estImpayee, isFalse);
    });

    test('les quatre termes se combinent', () {
      final f = facture(
        'f1',
        montant: 100000,
        reservationId: 'r1',
        module: ModuleFacturable.m1Hebergement,
      );
      final c = creanceDe(
        f,
        avoirs: [avoirDe(f, montant: 10000)],
        paiements: [
          paiement('p1', f, 2500000),
          paiement('p2', f, 999999, statut: StatutPaiementFacture.annule),
        ],
        acomptes: {'r1': 15000},
      );
      // 100 000 − 10 000 − 25 000 − 15 000 = 50 000 F
      expect(c.resteDuBrutCentimes, 5000000);
    });
  });

  group('Ce qui est une facture', () {
    test('un avoir n’est pas une créance', () {
      final f = facture('f1');
      final creances = composerCreances(
        pieces: [f, avoirDe(f)],
        paiements: const [],
        acomptesParReservation: const {},
      );
      expect(creances.map((c) => c.piece.id), ['f1']);
    });

    test('un ticket de vente au comptant n’est pas une créance : la vente l’a '
        'déjà encaissé', () {
      final ticket = facture('t1', origine: OrigineFacture.posComptant);
      expect(estUneCreance(ticket), isFalse);
      expect(
        composerCreances(
          pieces: [ticket],
          paiements: const [],
          acomptesParReservation: const {},
        ),
        isEmpty,
      );
    });

    test('la facture de départ d’un séjour et la facture directe le sont', () {
      expect(
        estUneCreance(facture('s1', origine: OrigineFacture.posSejour)),
        isTrue,
      );
      expect(estUneCreance(facture('d1')), isTrue);
    });

    test(
      'une facture ANNULÉE (neutralisée par son avoir) ne doit plus rien',
      () {
        final f = facture('f1', statut: StatutPiece.annulee);
        final c = creanceDe(f, avoirs: [avoirDe(f)]);
        expect(c.resteDuBrutCentimes, 0);
        expect(c.estImpayee, isFalse);
      },
    );
  });

  group('Le solde d’un client', () {
    test('additionne le reste dû de ses factures impayées', () {
      final f1 = facture('f1', montant: 30000);
      final f2 = facture('f2', montant: 20000);
      final soldes = soldesParClient(
        composerCreances(
          pieces: [f1, f2],
          paiements: [paiement('p1', f1, 1000000)],
          acomptesParReservation: const {},
        ),
      );
      // 20 000 + 20 000
      expect(soldes['c1']!.soldeCentimes, 4000000);
      expect(soldes['c1']!.nbPieces, 2);
    });

    test('une facture soldée n’entre ni dans le solde ni dans le nombre', () {
      final f1 = facture('f1', montant: 30000);
      final f2 = facture('f2', montant: 20000);
      final soldes = soldesParClient(
        composerCreances(
          pieces: [f1, f2],
          paiements: [paiement('p1', f1, 3000000)],
          acomptesParReservation: const {},
        ),
      );
      expect(soldes['c1']!.soldeCentimes, 2000000);
      expect(soldes['c1']!.nbPieces, 1);
    });

    test(
      'un client dont tout est soldé est ABSENT (le COALESCE le rend à 0)',
      () {
        final f1 = facture('f1', montant: 30000);
        final soldes = soldesParClient(
          composerCreances(
            pieces: [f1],
            paiements: [paiement('p1', f1, 3000000)],
            acomptesParReservation: const {},
          ),
        );
        expect(soldes, isEmpty);
      },
    );

    test('la plus ancienne facture impayée donne l’ancienneté', () {
      final f1 = facture('f1', emise: DateTime(2026, 9, 1, 15));
      final f2 = facture('f2', emise: DateTime(2026, 8, 10, 8));
      final f3 = facture('f3', emise: DateTime(2026, 7, 1), montant: 100);
      final soldes = soldesParClient(
        composerCreances(
          pieces: [f1, f2, f3],
          // La plus vieille est SOLDÉE : elle ne compte pas.
          paiements: [paiement('p1', f3, 10000)],
          acomptesParReservation: const {},
        ),
      );
      expect(soldes['c1']!.plusAncienne, DateTime(2026, 8, 10, 8));
    });

    test('une facture sans client n’a pas de solde de client', () {
      final f = facture('f1', clientId: null);
      expect(
        soldesParClient(
          composerCreances(
            pieces: [f],
            paiements: const [],
            acomptesParReservation: const {},
          ),
        ),
        isEmpty,
      );
    });

    test('les totaux : somme, nombre de pièces, clients DISTINCTS', () {
      final f1 = facture('f1', montant: 30000, clientId: 'c1');
      final f2 = facture('f2', montant: 20000, clientId: 'c1');
      final f3 = facture('f3', montant: 10000, clientId: 'c2');
      final f4 = facture('f4', montant: 5000, clientId: null);
      final t = totauxCreances(
        composerCreances(
          pieces: [f1, f2, f3, f4],
          paiements: const [],
          acomptesParReservation: const {},
        ),
      );
      expect(t.totalDuCentimes, 6500000);
      expect(t.nbPieces, 4);
      // COUNT(DISTINCT client_id) ne compte pas le NULL.
      expect(t.nbClients, 2);
    });
  });

  group('Encaissé sur 30 jours', () {
    test('il y a 30 jours, c’est 30 jours CALENDAIRES à la même heure', () {
      expect(
        ilYa30Jours(DateTime(2026, 10, 12, 14, 30, 5)),
        DateTime(2026, 9, 12, 14, 30, 5),
      );
      // À cheval sur un mois court.
      expect(ilYa30Jours(DateTime(2026, 3, 5, 8)), DateTime(2026, 2, 3, 8));
    });

    test(
      'ne somme que les encaissements ACTIFS, à partir de la borne incluse',
      () {
        final f = facture('f1');
        final depuis = DateTime(2026, 9, 12, 10);
        final total = encaisseDepuisCentimes([
          paiement('a', f, 100, date: depuis), // borne incluse
          paiement('b', f, 200, date: DateTime(2026, 10, 1)),
          paiement('c', f, 400, date: DateTime(2026, 9, 12, 9, 59)), // avant
          paiement(
            'd',
            f,
            800,
            date: DateTime(2026, 10, 2),
            statut: StatutPaiementFacture.annule,
          ),
        ], depuis);
        expect(total, 300);
      },
    );
  });

  group('La balance âgée', () {
    final aujourdhui = DateTime(2026, 10, 12, 15, 30);
    const repertoire = {
      'c1': (nom: 'KORA', prenom: 'Jean'),
      'c2': (nom: 'YAYI', prenom: null),
    };

    List<LigneDetteAgee> balance(
      List<PieceFacturation> pieces, {
      List<PaiementFacture> paiements = const [],
      String? terme,
    }) => detteAgeeParClient(
      composerCreances(
        pieces: pieces,
        paiements: paiements,
        acomptesParReservation: const {},
      ),
      repertoire,
      aujourdhui,
      terme: terme,
    );

    /// Une facture émise il y a [jours] jours ENTIERS, quelle que soit l'heure.
    PieceFacturation vieille(String id, int jours, {String client = 'c1'}) =>
        facture(
          id,
          montant: 1000,
          clientId: client,
          emise: DateTime(2026, 10, 12 - jours, 23, 59),
        );

    test('les bornes : 30 | 31, 60 | 61, 90 | 91 jours', () {
      for (final (jours, tranche) in [
        (0, TrancheAge.jusqua30),
        (30, TrancheAge.jusqua30),
        (31, TrancheAge.de31a60),
        (60, TrancheAge.de31a60),
        (61, TrancheAge.de61a90),
        (90, TrancheAge.de61a90),
        (91, TrancheAge.plus90),
      ]) {
        final l = balance([vieille('f', jours)]).single;
        expect(l.tranchesCentimes[tranche], 100000, reason: '$jours jours');
        expect(
          l.tranchesCentimes.values.where((v) => v != 0),
          hasLength(1),
          reason: '$jours jours : une seule tranche',
        );
      }
    });

    test('une facture datée du FUTUR tombe en « + de 90 jours » (le serveur '
        'n’a pas de tranche négative)', () {
      final l = balance([vieille('f', -3)]).single;
      expect(l.tranchesCentimes[TrancheAge.plus90], 100000);
    });

    test('un client dont tout est SOLDÉ n’a pas de ligne', () {
      final payee = vieille('p', 40);
      final due = vieille('d', 5, client: 'c2');
      final lignes = balance(
        [payee, due],
        paiements: [paiement('x', payee, 100000)],
      );
      expect(lignes.map((l) => l.clientId), ['c2']);
    });

    test('le reste dû d’une facture partiellement réglée, pas son TTC', () {
      final f = vieille('f', 10);
      final l = balance([f], paiements: [paiement('x', f, 30000)]).single;
      expect(l.tranchesCentimes[TrancheAge.jusqua30], 70000);
      expect(l.totalCentimes, 70000);
    });

    test('tri : total décroissant, puis le nom ; le nom porte le prénom', () {
      final lignes = balance([
        vieille('a', 5, client: 'c2'),
        vieille('b', 5),
        facture('c', montant: 5000, clientId: 'c1'),
      ]);
      expect(lignes.map((l) => l.nom), ['KORA Jean', 'YAYI']);
    });

    test('la recherche filtre sur le nom ET le prénom, sans casse', () {
      final pieces = [vieille('a', 5, client: 'c2'), vieille('b', 5)];
      expect(balance(pieces, terme: 'kor').map((l) => l.clientId), ['c1']);
      expect(balance(pieces, terme: 'JEA').map((l) => l.clientId), ['c1']);
      expect(balance(pieces, terme: 'zzz'), isEmpty);
    });

    test('un client absent du référentiel n’a pas de ligne, sa dette reste '
        'dans les totaux', () {
      final inconnu = vieille('f', 5, client: 'c9');
      expect(balance([inconnu]), isEmpty);
      expect(
        totauxCreances(
          composerCreances(
            pieces: [inconnu],
            paiements: const [],
            acomptesParReservation: const {},
          ),
        ).totalDuCentimes,
        100000,
      );
    });

    test('le total d’une tranche se lit sur la balance donnée', () {
      final lignes = balance([
        vieille('a', 5),
        vieille('b', 100, client: 'c2'),
      ]);
      expect(totalDeLaTranche(lignes, TrancheAge.jusqua30), 100000);
      expect(totalDeLaTranche(lignes, TrancheAge.plus90), 100000);
      expect(totalDeLaTranche(lignes, TrancheAge.de31a60), 0);
    });
  });
}
