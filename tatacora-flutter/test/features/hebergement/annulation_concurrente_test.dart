import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/messages_annulation.dart';

import '../caisse/support/outils_caisse.dart' show compterLignes;
import '../comptabilite/support/outils_comptabilite.dart';
import '../pos/support/outils_ventes.dart' show jourDeVente;

/// Le double geste d'annulation ne rembourse qu'UNE fois.
///
/// `annulerAvecConditions` lisait la réservation et validait « déjà annulée ? »
/// HORS de la transaction d'écriture : deux gestes concurrents voyaient tous
/// deux « pas encore annulée », et chacun passait sa pièce de remboursement.
/// L'argent sortait deux fois pour une seule annulation, sur une table gardée
/// par une règle du Product Owner (une écriture d'argent, une pièce). La lecture
/// et la validation vivent désormais dans la transaction : la seconde relit une
/// réservation déjà annulée et est refusée avant d'écrire.
///
/// Les deux cas empruntent le VRAI chemin (DAO, moteur comptable, base Drift) ;
/// la mutation qui les prouve non vides est décrite en tête du ticket (D249).
void main() {
  late AppDatabase db;
  late ReservationDao dao;

  setUp(() async {
    db = await baseInstallee(maintenant: jourDeVente);
    await db.customStatement(
      'INSERT INTO categories_hebergement_local (id, libelle, capacite_max, '
      "tarif_base) VALUES ('cat-1', 'Bungalow', 2, 28000)",
    );
    await db.customStatement(
      'INSERT INTO unites_hebergement_local (id, categorie_id, numero, statut) '
      "VALUES ('u-1', 'cat-1', 'BNG-01', 'libre')",
    );
    await db.customStatement(
      'INSERT INTO clients_local (id, nom, prenom, telephone, type_client) '
      "VALUES ('cli-1', 'KORA', 'Jean', '+229 01 00 00 00 01', 'particulier')",
    );
    // 2 nuits à 28 000 F, acompte 5 000 F en espèces : un remboursement existe.
    await db.customStatement(
      'INSERT INTO reservations_local (id, reference, client_id, unite_id, '
      'date_arrivee, date_depart, statut, tarif_nuit, acompte, mode_paiement) '
      "VALUES ('res-1', 'LOC-1', 'cli-1', 'u-1', 1790000000, 1790172800, "
      "'confirmee', 28000, 5000, 'especes')",
    );
    dao = ReservationDao(
      db,
      maintenant: () => jourDeVente,
      moteur: () async => moteurSur(db, maintenant: () => jourDeVente),
    );
  });

  tearDown(() => db.close());

  Future<Reservation> annuler() => dao.annulerAvecConditions(
    'res-1',
    tauxSaisi: '50',
    modeRemboursement: 'pourcentage',
    valeurRemboursement: '100',
    auteurId: auteurEssai,
  );

  Matcher refusDejaAnnulee() => throwsA(
    isA<Object>().having(
      (e) => '$e',
      'message',
      contains(MessagesAnnulation.dejaAnnulee),
    ),
  );

  test(
    'deux appels SUCCESSIFS : le second est refusé et n\'écrit rien',
    () async {
      final premiere = await annuler();
      expect(premiere.statut, StatutReservation.annulee);
      // Une pièce de remboursement : deux lignes (Dr 4191 / Cr 5711).
      expect(await compterLignes(db, 'ecritures_local'), 2);

      await expectLater(annuler(), refusDejaAnnulee());
      expect(await compterLignes(db, 'ecritures_local'), 2);
    },
  );

  test(
    'deux appels CONCURRENTS : un seul remboursement, un seul refus',
    () async {
      final resultats = await Future.wait([
        annuler().then<Object>((r) => r).catchError((Object e) => e),
        annuler().then<Object>((r) => r).catchError((Object e) => e),
      ]);

      final reussis = resultats.whereType<Reservation>().toList();
      final refus = resultats.where((r) => r is! Reservation).toList();
      expect(reussis, hasLength(1), reason: 'un seul geste doit aboutir');
      expect(refus, hasLength(1));
      expect('${refus.single}', contains(MessagesAnnulation.dejaAnnulee));

      // L'argent n'est sorti qu'une fois : UNE pièce, soit deux lignes.
      expect(
        await compterLignes(db, 'ecritures_local'),
        2,
        reason: 'une pièce de remboursement par annulation, jamais deux',
      );
      final r = await db
          .customSelect(
            'SELECT montant_rembourse_annulation_centimes AS m, statut '
            "FROM reservations_local WHERE id = 'res-1'",
          )
          .getSingle();
      expect(r.data['m'], 500000);
      expect(r.data['statut'], 'annulee');
    },
  );
}
