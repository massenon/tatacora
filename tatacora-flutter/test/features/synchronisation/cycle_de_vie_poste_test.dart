import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/achats/data/achats_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';
import 'package:tatacora_flutter/features/stocks/data/stocks_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/data/documents_autres_postes.dart';
import 'package:tatacora_flutter/features/synchronisation/data/operations_sync_dao.dart';
import 'package:tatacora_flutter/features/synchronisation/domain/operation_sync.dart';

import '../comptabilite/support/outils_comptabilite.dart';
import '../pos/support/outils_ventes.dart' show jourDeVente;

/// Lot F6 (17/10/2026) : les gestes du cycle de vie partent au serveur —
/// annulation d'une réservation avec ses conditions, déplacement, statut
/// d'une commande — seulement pour un document que le serveur détient ; et
/// le document d'un autre poste ne s'annule que par l'administration ou le
/// comptable (Q3).
void main() {
  late AppDatabase db;
  late ReservationDao dao;

  setUp(() async {
    db = await baseInstallee(maintenant: jourDeVente);
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    for (final u in const ['u-1', 'u-2']) {
      await db.customStatement(
        'INSERT INTO unites_hebergement_local (id, categorie_id, numero, '
        "statut) VALUES ('$u', 'cat-1', '$u', 'libre')",
      );
    }
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01 00 00 00 01', 'particulier')",
    );
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte, mode_paiement) '
      "VALUES ('res-1', 'LOC-1', 'cli-1', 'u-1', 1790000000, 1790172800, "
      "'confirmee', 28000, 5000, 'especes')",
    );
    // `auteurEssai` (u-compta) est déjà le comptable de la base d'essai.
    for (final (id, role) in const [('u-recep', 'receptionniste')]) {
      await db
          .into(db.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: id,
              login: id,
              nom: id,
              role: role,
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
    }
    dao = ReservationDao(
      db,
      maintenant: () => jourDeVente,
      moteur: () async => moteurSur(db, maintenant: () => jourDeVente),
    );
  });

  tearDown(() => db.close());

  Future<void> creationEnFile(String table, String id) => db.customStatement(
    'INSERT INTO operations_sync_local (uuid_operation, table_serveur, '
    'entite_id, type, payload, horodatage_client, cree_le) VALUES '
    "('op-$id', '$table', '$id', 'creation', '{}', "
    "'2026-10-15T08:00:00.000Z', 0)",
  );

  Future<void> descendu(String table, String id) => db.customStatement(
    'INSERT INTO origines_documents_local (table_serveur, entite_id, '
    "poste_origine, recu_le) VALUES ('$table', '$id', 'POSTE-A', 0)",
  );

  Future<List<OperationSync>> modifications(TableSynchronisee t) async => [
    for (final o in await OperationsSyncDao(db).operations(table: t))
      if (o.type == TypeOperationSync.modification) o,
  ];

  Future<Reservation> annuler(String auteur) => dao.annulerAvecConditions(
    'res-1',
    tauxSaisi: '50',
    modeRemboursement: 'pourcentage',
    valeurRemboursement: '100',
    auteurId: auteur,
  );

  group('Réservation', () {
    test('l’annulation part avec le taux et le MONTANT remboursé, si le '
        'serveur détient la réservation', () async {
      await creationEnFile('reservations', 'res-1');
      await annuler(auteurEssai);

      final op = (await modifications(TableSynchronisee.reservations)).single;
      expect(jsonDecode(op.payload), {
        'statut': 'annulee',
        'taux': '50.00',
        'mode_remboursement': 'montant',
        'valeur_remboursement': '5000.00',
      });
    });

    test(
      'une réservation que le serveur ne détient pas : rien ne part',
      () async {
        await annuler(auteurEssai);
        expect(await OperationsSyncDao(db).operations(), isEmpty);
      },
    );

    test('Q3 : la réservation d’un autre poste, refusée au réceptionniste, '
        'admise au comptable — et elle part', () async {
      await descendu('reservations', 'res-1');

      await expectLater(
        annuler('u-recep'),
        throwsA(
          isA<RefusAnnulation>().having(
            (e) => e.message,
            'message',
            DocumentsAutresPostes.refus,
          ),
        ),
      );
      expect((await dao.parId('res-1'))!.statut, StatutReservation.confirmee);

      await annuler(auteurEssai);
      expect((await dao.parId('res-1'))!.statut, StatutReservation.annulee);
      expect(await modifications(TableSynchronisee.reservations), hasLength(1));
    });

    test('le déplacement part, champs changés seulement ; une retouche '
        'sans déplacement ne part pas', () async {
      await creationEnFile('reservations', 'res-1');
      final r = (await dao.parId('res-1'))!;
      Reservation vers(String unite) => Reservation(
        id: r.id,
        reference: r.reference,
        clientId: r.clientId,
        clientNom: r.clientNom,
        uniteId: unite,
        periode: r.periode,
        tarifNuit: r.tarifNuit,
        statut: r.statut,
        statutSynchronisation: r.statutSynchronisation,
        creeeLe: r.creeeLe,
        acompte: r.acompte,
        lignes: r.lignes,
        typeClient: r.typeClient,
        canal: r.canal,
        modePaiement: r.modePaiement,
        remiseType: r.remiseType,
        remiseValeur: r.remiseValeur,
      );

      await dao.enregistrer(vers('u-1'));
      expect(await modifications(TableSynchronisee.reservations), isEmpty);

      await dao.enregistrer(vers('u-2'));
      final op = (await modifications(TableSynchronisee.reservations)).single;
      expect(jsonDecode(op.payload), {'unite_id': 'u-2'});
    });
  });

  test('Commande : l’envoi part, si le serveur détient la commande', () async {
    await db.customStatement(
      'INSERT INTO fournisseurs_local (id, raison_sociale, cree_le, cree_par) '
      "VALUES ('f-1', 'SOBEBRA', 0, '$auteurEssai')",
    );
    for (final id in const ['cmd-1', 'cmd-2']) {
      await db.customStatement(
        'INSERT INTO commandes_achat_local (id, fournisseur_id, '
        "date_commande, statut, cree_le, utilisateur_id) VALUES ('$id', "
        "'f-1', '2026-10-15', 'brouillon', 0, '$auteurEssai')",
      );
    }
    await creationEnFile('commandes_achat', 'cmd-1');
    final achats = AchatsDao(db, stocks: StocksDao(db));

    await achats.envoyerCommande('cmd-1');
    await achats.envoyerCommande('cmd-2');

    final ops = await modifications(TableSynchronisee.commandesAchat);
    expect(ops.single.entiteId, 'cmd-1');
    expect(jsonDecode(ops.single.payload), {'statut': 'envoyee'});
  });

  test('Facture : celle d’un autre poste ne s’annule pas sans auteur '
      'd’administration ou comptable', () async {
    await db.customStatement(
      'INSERT INTO pieces_facturation_local (id, numero, origine, '
      'date_emission, client_nom, statut, statut_transmission) VALUES '
      "('f-srv', 'F-2026-00009', 'facture_directe', 0, 'X', 'emise', "
      "'recue')",
    );
    await db.customStatement(
      'INSERT INTO lignes_piece_facturation_local (id, piece_id, '
      'module_source, libelle, prix_unitaire, quantite, ordre) VALUES '
      "('f-srv:0', 'f-srv', 'M5', 'Bière', 1000, 1, 0)",
    );
    await descendu('factures', 'f-srv');
    final factures = FactureDao(db);

    await expectLater(
      factures.annuler('f-srv', 'Erreur', auteurId: 'u-recep'),
      throwsA(isA<AnnulationAutrePosteRefusee>()),
    );
    await factures.annuler('f-srv', 'Erreur', auteurId: auteurEssai);
    expect((await factures.parId('f-srv'))!.estAnnulee, isTrue);
  });
}
