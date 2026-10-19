import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/fiche_reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/periode_sejour.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/reservation.dart';
import 'package:tatacora_flutter/features/hebergement/domain/entities/service_reservation.dart';

import '../../core/database/retour_arriere_schema.dart';
import '../comptabilite/support/outils_comptabilite.dart'
    show auteurEssai, semerAuteur;

/// Les lignes de service d'une réservation (schéma v8) — persistance et
/// migration.
///
/// Ce que ces cas protègent : le maître compose une réservation de **cinq
/// services**, et le schéma n'en connaissait qu'un. Une ligne perdue, c'est un
/// circuit ou une location facturés zéro — visible seulement le jour de
/// l'addition, devant le client.
void main() {
  late Directory dossier;
  late File fichier;

  setUp(() {
    dossier = Directory.systemTemp.createTempSync('tatacora_v8_');
    fichier = File('${dossier.path}/base.sqlite');
  });

  tearDown(() {
    // Sous Windows, le fichier reste parfois verrouillé une fraction de
    // seconde après la fermeture : un échec de nettoyage ne doit pas faire
    // échouer un test qui, lui, a réussi.
    try {
      dossier.deleteSync(recursive: true);
    } on FileSystemException {
      // Rien à faire : le répertoire temporaire du système sera purgé.
    }
  });

  Future<void> semer(AppDatabase db) async {
    await db
        .into(db.categoriesHebergementLocal)
        .insert(
          CategoriesHebergementLocalCompanion.insert(
            id: 'cat-1',
            libelle: 'Bungalow',
            capaciteMax: 2,
            tarifBase: 28000,
          ),
        );
    await db
        .into(db.unitesHebergementLocal)
        .insert(
          UnitesHebergementLocalCompanion.insert(
            id: 'u-1',
            categorieId: 'cat-1',
            numero: 'BNG-01',
            statut: 'libre',
          ),
        );
    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  }

  Reservation reservation({List<LigneService> lignes = const []}) =>
      Reservation(
        id: 'res-1',
        reference: 'LOC-TEST',
        clientId: 'cli-1',
        clientNom: 'KORA',
        uniteId: 'u-1',
        periode: PeriodeSejour(
          arrivee: DateTime.utc(2026, 9, 10),
          depart: DateTime.utc(2026, 9, 12),
        ),
        tarifNuit: 28000,
        statut: StatutReservation.enAttente,
        statutSynchronisation: StatutSynchronisation.local,
        creeeLe: DateTime.utc(2026, 9, 1),
        typeClient: TypeClient.groupe,
        canal: CanalReservation.booking,
        modePaiement: ModePaiementReservation.virement,
        lignes: lignes,
      );

  LigneService ligne(
    String id,
    ServiceReservation service, {
    required String itemId,
    required String libelle,
    required int prix,
    int quantite = 1,
  }) => LigneService(
    id: id,
    service: service,
    itemId: itemId,
    libelle: libelle,
    prixUnitaire: prix,
    quantite: quantite,
  );

  /* ================================================================== */
  group('Persistance des lignes', () {
    late AppDatabase db;
    late ReservationDao dao;

    setUp(() async {
      db = AppDatabase.enMemoire();
      dao = ReservationDao(db);
      await semer(db);
    });

    tearDown(() => db.close());

    test('les lignes sont réécrites et relues dans l’ordre de saisie', () async {
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow (BNG-01)',
              prix: 28000,
              quantite: 2,
            ),
            ligne(
              'l-2',
              ServiceReservation.bar,
              itemId: 'b-1',
              libelle: 'Bière Béninoise',
              prix: 1200,
              quantite: 3,
            ),
          ],
        ),
      );

      final relue = await dao.parId('res-1');
      expect(relue, isNotNull);
      expect(relue!.lignes.map((l) => l.id), ['l-1', 'l-2']);

      // Le montant est la SOMME des lignes : 56 000 + 3 600. Avec l'ancienne
      // dérivation `tarifNuit × nuits`, la consommation du bar n'y serait pas.
      expect(relue.montantTotal, 59600);
    });

    test('libellé et prix sont relus TELS QU’ÉCRITS, pas recalculés', () async {
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              // Un libellé et un prix qui ne correspondent PLUS au catalogue :
              // c'est exactement le cas qui compte, celui d'une grille
              // tarifaire changée depuis la réservation.
              libelle: 'Bungalow (BNG-01) — tarif de septembre',
              prix: 22000,
              quantite: 2,
            ),
          ],
        ),
      );

      final relue = await dao.parId('res-1');
      expect(relue!.lignes.single.prixUnitaire, 22000);
      expect(relue.lignes.single.libelle, contains('tarif de septembre'));
      expect(relue.montantTotal, 44000);
    });

    test('une ligne retirée disparaît vraiment', () async {
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow',
              prix: 28000,
              quantite: 2,
            ),
            ligne(
              'l-2',
              ServiceReservation.bar,
              itemId: 'b-1',
              libelle: 'Bière',
              prix: 1200,
            ),
          ],
        ),
      );

      // Réécriture sans la seconde. Une fusion ligne à ligne la laisserait
      // vivre, et le total garderait une consommation que l'utilisateur vient
      // de retirer sous ses yeux.
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow',
              prix: 28000,
              quantite: 2,
            ),
          ],
        ),
      );

      final relue = await dao.parId('res-1');
      expect(relue!.lignes, hasLength(1));
      expect(relue.montantTotal, 56000);
    });

    test('le retour du serveur n’efface ni la fiche ni les lignes', () async {
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow',
              prix: 28000,
              quantite: 2,
            ),
          ],
        ),
      );

      // Le chemin réellement emprunté au retour du serveur : seul le statut de
      // synchronisation change. `copyWith` omettait la fiche jusqu'au
      // 25/08/2026 — canal et mode de paiement disparaissaient donc à la
      // première réponse du serveur, sans erreur ni trace.
      await dao.majStatutSync('res-1', StatutSynchronisation.synchronise);

      final relue = await dao.parId('res-1');
      expect(relue!.statutSynchronisation, StatutSynchronisation.synchronise);
      expect(relue.canal, CanalReservation.booking);
      expect(relue.modePaiement, ModePaiementReservation.virement);
      expect(relue.typeClient, TypeClient.groupe);
      expect(relue.lignes, hasLength(1));
    });

    test('une ANNULATION ne perd ni la fiche ni les lignes', () async {
      // Le seul chemin qui passe réellement par `Reservation.copyWith`.
      //
      // Il vaut mieux que le précédent : `majStatutSync` écrit en SQL direct
      // et ne touche pas à l'entité, si bien qu'une mutation de `copyWith`
      // le laissait vert. Une annulation, elle, reconstruit l'objet ENTIER
      // puis le réécrit — colonnes et lignes comprises. Une fiche omise dans
      // `copyWith` est donc effacée en base, et deux lignes de service
      // disparaissent avec elle.
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.hebergement,
              itemId: 'u-1',
              libelle: 'Bungalow',
              prix: 28000,
              quantite: 2,
            ),
            ligne(
              'l-2',
              ServiceReservation.tourisme,
              itemId: 'c-1',
              libelle: 'Cascades de Tanougou',
              prix: 15000,
              quantite: 2,
            ),
          ],
        ),
      );

      // L'annulation nomme celui qui annule (RG-15, clé étrangère réelle).
      await db.customStatement('SELECT 1');
      await semerAuteur(db);
      final annulee = await ReservationRepositoryLocal(dao).annuler(
        'res-1',
        tauxSaisi: '50',
        modeRemboursement: 'montant',
        valeurRemboursement: '0',
        auteurId: auteurEssai,
      );

      expect(annulee.statut, StatutReservation.annulee);
      // Le motif n'existe plus au serveur ; ce que l'annulation fixe, lui,
      // est écrit : 50 % de 86 000 F.
      expect(annulee.annulation!.commissionCentimes, 4300000);

      // Ce qui doit avoir SURVÉCU à la reconstruction de l'objet.
      expect(annulee.canal, CanalReservation.booking);
      expect(annulee.typeClient, TypeClient.groupe);
      expect(annulee.modePaiement, ModePaiementReservation.virement);
      expect(annulee.lignes, hasLength(2));
      expect(annulee.montantTotal, 86000);
    });

    test('la liste porte les lignes de chaque réservation', () async {
      await dao.enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.tourisme,
              itemId: 'c-1',
              libelle: 'Cascades de Tanougou',
              prix: 15000,
              quantite: 4,
            ),
          ],
        ),
      );

      final liste = await dao.reservations();
      expect(liste.single.lignes.single.service, ServiceReservation.tourisme);
      expect(liste.single.montantTotal, 60000);
    });
  });

  /* ================================================================== */
  group('Migration v7 → v8 — le chemin de la mise à jour', () {
    test('la table apparaît et les réservations SURVIVENT', () async {
      final prepare = AppDatabase.surFichier(fichier);
      await semer(prepare);
      final dao = ReservationDao(prepare);
      await dao.enregistrer(reservation());

      // Le retrait vient après le semis : les DAO courants écrivent les
      // colonnes de la v8, qu'un schéma déjà ramené en arrière n'a plus.
      await ramenerSchemaA(prepare, 7);
      await prepare.close();

      // Réouverture : `onUpgrade` s'exécute sur un fichier NON VIDE — le seul
      // cas qui compte, et celui qu'un `createTable` sur base vierge ne prouve
      // jamais.
      final v8 = AppDatabase.surFichier(fichier);
      final tables = await v8
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(
        tables.map((l) => l.data['name'] as String),
        contains('lignes_reservation_local'),
      );

      final relue = await ReservationDao(v8).parId('res-1');
      expect(relue, isNotNull, reason: 'la réservation v7 a été perdue');
      // AUCUNE ligne n'est fabriquée pour les réservations reprises : en
      // déduire une depuis `tarif_nuit` produirait une ligne à zéro franc sur
      // tout ce qui vient de la v1, plausible et invisible.
      expect(relue!.lignes, isEmpty);
      // Leur montant continue donc de se lire là où il a toujours été.
      expect(relue.montantTotal, 56000);

      final version = await v8.customSelect('PRAGMA user_version').getSingle();
      expect(version.data.values.first, v8.schemaVersion);
      await v8.close();
    });

    test('la base migrée est utilisable : une ligne s’y écrit', () async {
      final prepare = AppDatabase.surFichier(fichier);
      await semer(prepare);
      await ramenerSchemaA(prepare, 7);
      await prepare.close();

      final v8 = AppDatabase.surFichier(fichier);
      await ReservationDao(v8).enregistrer(
        reservation(
          lignes: [
            ligne(
              'l-1',
              ServiceReservation.vehicule,
              itemId: 'v-1',
              libelle: 'Berline AB-1234',
              prix: 25000,
              quantite: 3,
            ),
          ],
        ),
      );

      final relue = await ReservationDao(v8).parId('res-1');
      expect(relue!.lignes.single.service, ServiceReservation.vehicule);
      expect(relue.montantTotal, 75000);
      await v8.close();
    });
  });
}
