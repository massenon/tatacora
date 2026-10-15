import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/client.dart';
import 'package:tatacora_flutter/features/crm/domain/entities/registre_clients.dart';
import 'package:tatacora_flutter/features/facturation/domain/creances.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/paiement_facture.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';

/// La composition du registre clients — **unitaire, sans base ni écran**.
///
/// ## Ce que ces cas protègent
///
/// **Que le solde soit celui du SERVEUR** (`SoldeClientService::registre()`) :
/// le reste dû des factures impayées d'un client, par la formule UNIQUE de
/// `creances.dart`. `clients_local` porte une colonne `solde` que rien n'écrit :
/// elle vaut zéro pour tout le monde, et l'afficher donnerait un zéro plausible
/// sur la fiche d'un client qui doit 200 000 F.
///
/// ⚠ Jusqu'au 12/10/2026 ce fichier éprouvait une AUTRE grandeur (restes à payer
/// sur séjours + consommations non facturées, PA-112/PA-126). Elle est retirée :
/// les cas qui la décrivaient ne sont pas « adaptés », ils sont REMPLACÉS, parce
/// qu'ils protégeaient une définition que le serveur n'a jamais eue.
void main() {
  Client client(String id, {String nom = 'KORA', String tel = '97000000'}) =>
      Client(
        id: id,
        nom: nom,
        telephone: tel,
        type: TypeClientReferentiel.particulier,
      );

  PieceFacturation facture(
    String id, {
    required String clientId,
    int montant = 50000,
    DateTime? emise,
  }) => PieceFacturation(
    id: id,
    numero: 'F-2026-$id',
    origine: OrigineFacture.factureDirecte,
    dateEmission: emise ?? DateTime(2026, 10, 1, 9),
    clientNom: 'Client',
    statut: StatutPiece.emise,
    clientId: clientId,
    lignes: [
      LigneFacture(
        id: '$id-l1',
        module: ModuleFacturable.m5Bar,
        libelle: 'Prestation',
        prixUnitaire: montant,
        quantite: 1,
        ordre: 0,
      ),
    ],
  );

  PaiementFacture paiement(String id, PieceFacturation f, int centimes) =>
      PaiementFacture(
        id: id,
        pieceId: f.id,
        sessionId: 's1',
        mode: ModePaiementFacture.especes,
        montantCentimes: centimes,
        datePaiement: DateTime(2026, 10, 5),
        statut: StatutPaiementFacture.actif,
        utilisateurCreationId: 'u1',
      );

  List<CreanceFacture> creances(
    List<PieceFacturation> pieces, [
    List<PaiementFacture> paiements = const [],
  ]) => composerCreances(
    pieces: pieces,
    paiements: paiements,
    acomptesParReservation: const {},
  );

  /* ================================================================== */
  group('Le solde', () {
    test('est le reste dû des factures impayées, en centimes', () {
      final f1 = facture('f1', clientId: 'c1', montant: 50000);
      final f2 = facture('f2', clientId: 'c1', montant: 4000);
      final lignes = composerRegistre(
        clients: [client('c1')],
        creances: creances([f1, f2]),
      );

      final l = lignes.single;
      expect(l.soldeCentimes, 5400000);
      expect(l.nbPieces, 2);
      expect(l.estDebiteur, isTrue);
    });

    test('un encaissement le DIMINUE — c’est le point du lot', () {
      final f = facture('f1', clientId: 'c1', montant: 50000);
      final lignes = composerRegistre(
        clients: [client('c1')],
        creances: creances([f], [paiement('p1', f, 3000000)]),
      );

      expect(lignes.single.soldeCentimes, 2000000);
    });

    test('une facture soldée sort du solde ET du nombre de pièces', () {
      final f1 = facture('f1', clientId: 'c1', montant: 50000);
      final f2 = facture('f2', clientId: 'c1', montant: 4000);
      final lignes = composerRegistre(
        clients: [client('c1')],
        creances: creances([f1, f2], [paiement('p1', f2, 400000)]),
      );

      expect(lignes.single.soldeCentimes, 5000000);
      expect(lignes.single.nbPieces, 1);
    });

    test('le solde d’UN client n’est pas celui d’un autre', () {
      final lignes = composerRegistre(
        clients: [
          client('c1', nom: 'KORA'),
          client('c2', nom: 'DOSSOU'),
        ],
        creances: creances([
          facture('f1', clientId: 'c1', montant: 7000),
          facture('f2', clientId: 'c2', montant: 9000),
        ]),
      );

      final kora = lignes.firstWhere((l) => l.client.id == 'c1');
      final dossou = lignes.firstWhere((l) => l.client.id == 'c2');
      expect(kora.soldeCentimes, 700000);
      expect(dossou.soldeCentimes, 900000);
    });

    test('un client sans facture apparaît quand même, à zéro', () {
      // Le masquer ferait disparaître du référentiel un client qu'on vient de
      // créer, et on le recréerait.
      final lignes = composerRegistre(
        clients: [client('c1')],
        creances: const [],
      );

      expect(lignes, hasLength(1));
      expect(lignes.single.soldeCentimes, 0);
      expect(lignes.single.nbPieces, 0);
      expect(lignes.single.estDebiteur, isFalse);
      expect(lignes.single.ancienneteJours(DateTime(2026, 10, 12)), isNull);
    });

    test('les plus gros débiteurs viennent en tête, puis l’alphabet', () {
      final lignes = composerRegistre(
        clients: [
          client('c1', nom: 'KORA'),
          client('c2', nom: 'DOSSOU'),
          client('c3', nom: 'AGBO'),
        ],
        creances: creances([
          facture('f1', clientId: 'c1', montant: 10000),
          facture('f2', clientId: 'c2', montant: 80000),
        ]),
      );

      expect(lignes.map((l) => l.client.id), ['c2', 'c1', 'c3']);
    });

    test('à solde égal, le nom départage', () {
      final lignes = composerRegistre(
        clients: [
          client('c1', nom: 'KORA'),
          client('c2', nom: 'DOSSOU'),
        ],
        creances: const [],
      );
      expect(lignes.map((l) => l.client.nom), ['DOSSOU', 'KORA']);
    });
  });

  /* ================================================================== */
  group('L’ancienneté', () {
    test('est celle de la plus ancienne facture impayée, en jours ENTIERS '
        'depuis sa DATE d’émission', () {
      final lignes = composerRegistre(
        clients: [client('c1')],
        creances: creances([
          facture('f1', clientId: 'c1', emise: DateTime(2026, 9, 1, 15)),
          facture('f2', clientId: 'c1', emise: DateTime(2026, 8, 10, 23, 59)),
        ]),
      );

      // Du 10/08 00:00 au 12/10 10:00 : 63 jours et 10 heures -> 63.
      expect(lignes.single.ancienneteJours(DateTime(2026, 10, 12, 10)), 63);
      // Le matin du même jour : toujours 63, jamais 64 avant minuit.
      expect(lignes.single.ancienneteJours(DateTime(2026, 10, 12, 0, 1)), 63);
      expect(lignes.single.ancienneteJours(DateTime(2026, 10, 13, 0, 1)), 64);
    });
  });

  /* ================================================================== */
  group('Les filtres', () {
    late List<LigneClient> registre;

    setUp(() {
      registre = composerRegistre(
        clients: [
          client('c1', nom: 'KORA', tel: '97111111'),
          client('c2', nom: 'DOSSOU', tel: '96222222'),
        ],
        creances: creances([facture('f1', clientId: 'c1', montant: 30000)]),
      );
    });

    test('la recherche porte sur le nom ET sur le téléphone', () {
      // Au comptoir, le téléphone est souvent le seul élément donné.
      expect(filtrerRegistre(registre, terme: 'dossou'), hasLength(1));
      expect(filtrerRegistre(registre, terme: '97111'), hasLength(1));
      expect(
        filtrerRegistre(registre, terme: '97111').single.client.nom,
        'KORA',
      );
    });

    test('« Débiteurs » et « Sans dette » partagent le registre', () {
      final debiteurs = filtrerRegistre(registre, etat: EtatCreance.debiteur);
      final soldes = filtrerRegistre(registre, etat: EtatCreance.solde);

      expect(debiteurs, hasLength(1));
      expect(soldes, hasLength(1));
      expect(debiteurs.single.client.id, 'c1');
      expect(debiteurs.length + soldes.length, registre.length);
    });

    test('le filtre « À relancer » du maître n’existe PAS', () {
      // Sans historique de relances (M12 vide), l'entrée classerait tous les
      // débiteurs comme « à relancer » — une affirmation sur un fait jamais
      // vérifié. Son absence est une décision, pas un oubli.
      expect(EtatCreance.values, hasLength(3));
      expect(EtatCreance.values.map((e) => e.code), isNot(contains('relance')));
    });
  });

  /* ================================================================== */
  group('Les indicateurs', () {
    test('comptent les débiteurs, le total dû et les pièces', () {
      final registre = composerRegistre(
        clients: [
          client('c1', nom: 'KORA'),
          client('c2', nom: 'DOSSOU'),
        ],
        creances: creances([
          facture('f1', clientId: 'c1', montant: 30000),
          facture('f2', clientId: 'c1', montant: 5000),
        ]),
      );

      final kpis = KpisClients.calculer(registre);
      expect(kpis.nbClients, 2);
      expect(kpis.nbDebiteurs, 1);
      expect(kpis.totalDuCentimes, 3500000);
      expect(kpis.nbPieces, 2);
    });
  });
}
