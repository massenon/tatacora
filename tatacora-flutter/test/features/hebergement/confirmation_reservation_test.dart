import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/core/impression/texte_ticket.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/impression/confirmation_reservation.dart';

/// Le document remis au client à la prise de réservation.
///
/// ## Ce que ces cas protègent avant tout
///
/// **Que ce papier ne devienne jamais une facture.** Il n'a ni numéro, ni
/// cachet fiscal, ni identifiant fiscal — et il ne doit rien affirmer de tel.
/// Un document titré « FACTURE » remis à un client au Bénin sans numéro MECeF
/// est un faux document fiscal : c'est PA-61 sur du papier, celui qu'on ne
/// rattrape pas.
void main() {
  Reservation reservation({
    int acompte = 0,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService>? lignes,
    CanalReservation? canal = CanalReservation.booking,
  }) => Reservation(
    id: 'res-1',
    reference: 'LOC-A1B2C3D4',
    clientId: 'cli-1',
    clientNom: 'KORA Jean',
    uniteId: 'u-1',
    periode: PeriodeSejour(
      arrivee: DateTime(2026, 9, 20),
      depart: DateTime(2026, 9, 22),
    ),
    tarifNuit: 28000,
    statut: StatutReservation.enAttente,
    statutSynchronisation: StatutSynchronisation.local,
    creeeLe: DateTime(2026, 9, 1),
    acompte: acompte,
    typeClient: TypeClient.agencePartenaire,
    canal: canal,
    modePaiement: ModePaiementReservation.virement,
    remiseType: remiseType,
    remiseValeur: remiseValeur,
    lignes:
        lignes ??
        const [
          LigneService(
            id: 'l-1',
            service: ServiceReservation.hebergement,
            itemId: 'u-1',
            libelle: 'Bungalow (BNG-01)',
            prixUnitaire: 28000,
            quantite: 2,
          ),
        ],
  );

  ConfirmationReservation document({
    int acompte = 0,
    TypeRemise? remiseType,
    num? remiseValeur,
    List<LigneService>? lignes,
    CanalReservation? canal = CanalReservation.booking,
  }) => ConfirmationReservation(
    reservation: reservation(
      acompte: acompte,
      remiseType: remiseType,
      remiseValeur: remiseValeur,
      lignes: lignes,
      canal: canal,
    ),
    emiseLe: DateTime(2026, 9, 2, 10, 30),
  );

  /* ================================================================== */
  group('Ce papier n’affirme jamais être une facture', () {
    test('son titre ne contient pas le mot « facture »', () {
      expect(ConfirmationReservation.titre, 'CONFIRMATION DE RÉSERVATION');
      expect(
        ConfirmationReservation.titre.toLowerCase(),
        isNot(contains('facture')),
      );
    });

    test('il porte la mention qui le distingue, au CORPS du document', () {
      // Pas en pied de page en petits caractères : c'est la première chose
      // qu'un client regarde s'il cherche une facture.
      expect(ConfirmationReservation.mention, contains('ne vaut pas facture'));
      expect(
        ConfirmationReservation.mention,
        contains('émise à l’encaissement'),
      );
    });

    test('aucun identifiant fiscal n’est imprimé', () {
      // IFU et RCCM ne sont pas renseignés sur ce dépôt ; `EnteteEtablissement`
      // les écarte à la source. Un exemple de format imprimé sur un document
      // remis serait un faux identifiant fiscal.
      final entete = document().entete.lignesA4.join(' ');
      expect(entete, isNot(contains('IFU')));
      expect(entete, isNot(contains('RCCM')));
    });

    test('aucun numéro n’apparaît sur le document', () {
      // Le seul identifiant porté est la RÉFÉRENCE de la réservation
      // (`LOC-…`), provisoire et non fiscale. Un numéro de séquence sur ce
      // papier le ferait passer pour une pièce du registre.
      final texte = document().identification.join(' ');
      expect(texte, contains('LOC-A1B2C3D4'));
      expect(texte, isNot(contains('FAC')));
      expect(texte, isNot(contains('MECEF')));
    });

    test('composer le document ne CONSOMME aucun numéro de facture', () async {
      // `FactureDao.numeroSuivant()` alloue et persiste : ce n'est jamais une
      // lecture (PA-101). Ce module ne doit pas l'appeler — un numéro brûlé
      // pour un document non fiscal laisserait un trou dans la séquence
      // continue, à justifier plus tard.
      final db = AppDatabase.enMemoire();
      addTearDown(db.close);

      await document().pdf();

      final sequences = await db.select(db.sequencesFactureLocal).get();
      expect(
        sequences,
        isEmpty,
        reason:
            'un numéro de facture a été alloué pour un document qui n’en '
            'est pas une',
      );
    });
  });

  /* ================================================================== */
  group('Le contenu est celui du maître', () {
    test('les cinq colonnes du tableau', () {
      expect(ConfirmationReservation.entetes, [
        'Service',
        'Désignation',
        'Qté',
        'Prix unitaire',
        'Sous-total',
      ]);
    });

    test('les cinq lignes du récapitulatif, dans l’ordre', () {
      final libelles = document().recapitulatif.map((l) => l.$1).toList();
      expect(libelles, [
        'Sous-total',
        'Remise',
        'Total à payer',
        'Acompte versé',
        'Reste à payer',
      ]);
    });

    test('les deux déductions sont précédées d’un moins', () {
      // Sans le signe, « Remise 5 000 F » se lit comme un montant dû et non
      // comme un montant retiré.
      final recap = document(acompte: 20000).recapitulatif;
      expect(recap[1].$2, startsWith('- '));
      expect(recap[3].$2, startsWith('- '));
    });

    test('le calcul vient de l’entité, remise comprise', () {
      final recap = document(
        acompte: 20000,
        remiseType: TypeRemise.pourcentage,
        remiseValeur: 10,
      ).recapitulatif;

      // 56 000 − 10 % = 50 400 ; reste 30 400. Une seconde formule ici
      // finirait par diverger de l'écran, et c'est le papier remis au client
      // qui l'emporterait.
      expect(recap[0].$2, contains('56 000'));
      expect(recap[1].$2, contains('5 600'));
      expect(recap[2].$2, contains('50 400'));
      expect(recap[4].$2, contains('30 400'));
    });

    test('une ligne par service retenu', () {
      final doc = document(
        lignes: const [
          LigneService(
            id: 'l-1',
            service: ServiceReservation.hebergement,
            itemId: 'u-1',
            libelle: 'Bungalow (BNG-01)',
            prixUnitaire: 28000,
            quantite: 2,
          ),
          LigneService(
            id: 'l-2',
            service: ServiceReservation.tourisme,
            itemId: 'c-1',
            libelle: 'Cascades de Tanougou',
            prixUnitaire: 15000,
            quantite: 4,
          ),
        ],
      );

      expect(doc.lignes, hasLength(2));
      expect(doc.lignes[1][0], 'Tourisme');
      expect(doc.lignes[1][2], '4');
      expect(doc.lignes[1][4], contains('60 000'));
    });

    test('un canal absent s’écrit « — », jamais rien', () {
      final texte = document(canal: null).identification.join(' ');
      expect(texte, contains('Canal : —'));
    });
  });

  /* ================================================================== */
  group('Le PDF est réellement produit', () {
    test('les octets sortent, et ce sont bien ceux d’un PDF', () async {
      final octets = await document(acompte: 20000).pdf();
      expect(octets.length, greaterThan(1000));
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('une réservation SANS ligne produit quand même le document', () async {
      // Celles d'avant le détail par service. Un tableau vide passerait pour
      // une erreur d'impression ; le document le dit.
      final octets = await document(lignes: const []).pdf();
      expect(String.fromCharCodes(octets.take(4)), '%PDF');
    });

    test('aucun caractère ne peut être PERDU sur le papier', () {
      // Les polices intégrées du PDF couvrent Latin-1 : un caractère non
      // couvert disparaît du papier sans erreur ni trace.
      final doc = document(acompte: 20000);
      final textes = <String>[
        ConfirmationReservation.titre,
        ConfirmationReservation.mention,
        ...ConfirmationReservation.entetes,
        ...doc.identification,
        ...doc.lignes.expand((l) => l),
        ...doc.recapitulatif.expand((l) => [l.$1, l.$2]),
        ...doc.entete.lignesA4,
      ].map(texteTicket);

      for (final texte in textes) {
        expect(
          caracteresNonImprimables(texte),
          isEmpty,
          reason: '« $texte » perdrait des caractères à l’impression.',
        );
      }
    });
  });
}
