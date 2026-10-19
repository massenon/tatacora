import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import '../../core/database/retour_arriere_schema.dart';
import 'support/outils_ventes.dart';

/// **Le critère d'acceptation de D2, et les deux chemins que la base en
/// mémoire ne peut pas éprouver.**
///
/// > *Un panier de séjour survit à la fermeture de l'application* — constaté
/// > par le cycle écrire → fermer → rouvrir → relire, **sur fichier réel**,
/// > comme en D0.3.
///
/// Un panier vérifié seulement en mémoire ne prouve rien de ce qui compte ici :
/// le panier d'un séjour vit plusieurs jours et plusieurs redémarrages. C'est
/// aussi la leçon PA-59 — les tests Drift en mémoire passent toujours par
/// `onCreate` et n'empruntent **jamais** `onUpgrade`, qui était faux.
///
/// ⚠ **Portage d'une PROPOSITION non ratifiée** (Q1/Q2/Q3), voir
/// `docs/PROPOSITION_MODELE_PANIER_POS.md`.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_panier_');
    fichier = File('${dossier.path}/tatacora.sqlite');
  });

  tearDown(() async {
    // Sous Windows, le fichier reste verrouillé un court instant après la
    // fermeture. Un échec de ménage ne doit pas faire rougir un test dont
    // l'assertion a réussi.
    try {
      if (dossier.existsSync()) await dossier.delete(recursive: true);
    } on FileSystemException {
      // sans conséquence
    }
  });

  Future<void> semer(AppDatabase db) async {
    await db
        .into(db.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
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
    await db
        .into(db.reservationsLocal)
        .insert(
          ReservationsLocalCompanion.insert(
            id: 'res-1',
            reference: 'LOC-RES1',
            clientId: 'cli-1',
            uniteId: 'u-1',
            dateArrivee: DateTime.utc(2026, 8, 18),
            dateDepart: DateTime.utc(2026, 8, 24),
            statut: 'confirmee',
            tarifNuit: 28000,
          ),
        );
  }

  /* ================================================================== */
  group('Critère D2 — un panier de séjour survit à la fermeture', () {
    test('panier, lignes et total sont relus après réouverture', () async {
      // Session 1 : le barman porte deux consommations sur la note de chambre.
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      final depot1 = PanierRepositoryLocal(PanierDao(premiere));
      final p = await depot1.ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: 'res-1',
        clientNom: 'KORA',
        pointVente: 'Bar',
        dateDepartPrevue: DateTime(2026, 8, 24),
      );
      await depot1.ajouterLigne(p.id, biere, quantite: 3);
      await premiere.close();

      // Le fichier existe sur le disque, indépendamment du processus.
      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));

      // Session 2 : l'application est relancée le lendemain.
      final seconde = AppDatabase.surFichier(fichier);
      final relu = await PanierRepositoryLocal(
        PanierDao(seconde),
      ).panierOuvertPour('res-1');

      expect(relu, isNotNull, reason: 'le panier du séjour a survécu');
      expect(relu!.id, p.id);
      expect(relu.statut, StatutPanier.ouvert);
      expect(relu.clientNom, 'KORA');
      expect(relu.pointVente, 'Bar');
      expect(relu.lignes, hasLength(1));
      expect(relu.lignes.single.quantite, 3);
      // Le prix figé a survécu lui aussi : c'est ce qui fait qu'une bière de
      // lundi reste au prix de lundi après trois redémarrages.
      expect(relu.lignes.single.prixUnitaire, 1000);
      expect(relu.total, 3000);
      await seconde.close();
    });

    test(
      'le panier se complète sur PLUSIEURS sessions, comme un vrai séjour',
      () async {
        // Le cas que la mémoire ne peut pas éprouver : trois jours, trois
        // démarrages, une seule addition.
        final jour1 = AppDatabase.surFichier(fichier);
        await semer(jour1);
        // La clôture du troisième jour passe la pièce de la vente : le
        // référentiel comptable est installé le premier jour, et il survit aux
        // démarrages comme le reste (c'est un fichier réel).
        await avecComptabilite(jour1, maintenant: DateTime(2026, 8, 24, 10));
        final p = await PanierRepositoryLocal(PanierDao(jour1)).ouvrir(
          typeVente: TypeVente.surSejour,
          reservationId: 'res-1',
          dateDepartPrevue: DateTime(2026, 8, 24),
        );
        await PanierRepositoryLocal(PanierDao(jour1)).ajouterLigne(p.id, biere);
        await jour1.close();

        final jour2 = AppDatabase.surFichier(fichier);
        await PanierRepositoryLocal(PanierDao(jour2)).ajouterLigne(p.id, biere);
        await jour2.close();

        final jour3 = AppDatabase.surFichier(fichier);
        final depot3 = PanierRepositoryLocal(
          panierDaoSur(jour3, horloge: DateTime(2026, 8, 24, 10)),
        );
        final avantCloture = (await depot3.parId(p.id))!;
        expect(
          avantCloture.lignes,
          hasLength(1),
          reason: 'le regroupement traverse les sessions',
        );
        expect(avantCloture.lignes.single.quantite, 2);

        final cloture = await depot3.cloturer(
          p.id,
          anticipe: true,
          modePaiement: 'especes',
          auteurId: caissierDeVente,
        );
        expect(cloture.montantCloture, 2000);
        await jour3.close();

        // Session 4 : le montant figé n'a pas bougé, et le séjour n'a plus de
        // panier ouvert.
        final jour4 = AppDatabase.surFichier(fichier);
        final depot4 = PanierRepositoryLocal(PanierDao(jour4));
        expect((await depot4.parId(p.id))!.montantCloture, 2000);
        expect(await depot4.panierOuvertPour('res-1'), isNull);
        await jour4.close();
      },
    );

    test('⚠ Q2 — l’unicité tient d’une session à l’autre', () async {
      // La garantie n'est pas en mémoire : si elle l'était, redémarrer
      // l'application suffirait à ouvrir un second panier et à scinder les
      // consommations.
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      await PanierRepositoryLocal(PanierDao(premiere)).ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: 'res-1',
        dateDepartPrevue: DateTime(2026, 8, 24),
      );
      await premiere.close();

      final seconde = AppDatabase.surFichier(fichier);
      await expectLater(
        PanierRepositoryLocal(PanierDao(seconde)).ouvrir(
          typeVente: TypeVente.surSejour,
          reservationId: 'res-1',
          dateDepartPrevue: DateTime(2026, 8, 24),
        ),
        throwsA(isA<Exception>()),
      );
      await seconde.close();
    });

    test(
      'un panier de séjour EXIGE une réservation qui existe en base',
      () async {
        // La clé étrangère est réelle : un panier orphelin verrait ses
        // consommations n'atteindre jamais la facture de départ.
        final db = AppDatabase.surFichier(fichier);
        await semer(db);

        await expectLater(
          PanierRepositoryLocal(PanierDao(db)).ouvrir(
            typeVente: TypeVente.surSejour,
            reservationId: 'res-qui-n-existe-pas',
            dateDepartPrevue: DateTime(2026, 8, 24),
          ),
          throwsA(anything),
        );
        await db.close();
      },
    );
  });

  /* ================================================================== */
  group('Migration v2 → v3 — le chemin de la mise à jour', () {
    /// Ramène un fichier v3 à l'état v2 : les deux tables neuves sont retirées
    /// et `user_version` remis à 2.
    ///
    /// C'est plus fidèle que de recréer une v2 à la main — le reste du schéma
    /// est celui que Drift produit réellement, pas une transcription.
    ///
    /// [avecReservation] insère une réservation **après** le retrait : l'ordre
    /// compte, car rouvrir `AppDatabase` déclenche `onUpgrade` aussitôt. C'est
    /// exactement la mise en scène qui avait révélé le défaut de la migration
    /// v1 → v2 (PA-59).
    Future<void> ramenerEnV2(File f, {bool avecReservation = false}) async {
      final db = AppDatabase.surFichier(f);
      await db.customStatement('SELECT 1'); // force l'ouverture et `onCreate`

      if (avecReservation) {
        await semer(db);
      }

      // Le retrait vient APRES le semis : `semer` passe par les DAO courants,
      // qui ecrivent les colonnes des versions posterieures. Sur un schema
      // deja ramene en arriere, l'insertion echouerait sur une colonne absente.
      await ramenerSchemaA(db, 2);
      await db.close();
    }

    test('les deux tables sont créées à l’ouverture', () async {
      await ramenerEnV2(fichier);

      final db = AppDatabase.surFichier(fichier);
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final noms = tables.map((l) => l.data['name'] as String).toSet();

      expect(noms, containsAll(const ['paniers_local', 'lignes_panier_local']));
      await db.close();
    });

    test(
      'la version du schéma passe à la version COURANTE, en chaîne',
      () async {
        // Depuis D3 le schéma est en v4, et ce fichier part d'une v2 : les deux
        // branches `from < 3` et `from < 4` s'enchaînent dans la même ouverture.
        //
        // Ce n'est pas un cas de laboratoire — c'est le poste qui a sauté une
        // livraison. Le vérifier ici évite qu'un jour on ne teste plus que le
        // dernier saut, celui d'un utilisateur toujours à jour, c'est-à-dire le
        // seul dont on n'a rien à craindre.
        await ramenerEnV2(fichier);

        final db = AppDatabase.surFichier(fichier);
        await db.customStatement('SELECT 1');
        final version = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        // Comparee a la version COURANTE, jamais a un literal : un
        // literal se perime a chaque migration, et il l'a fait — ecrit 4, il
        // a rougi le jour de la v5 sans qu'aucune regression n'existe.
        expect(version.data.values.first, db.schemaVersion);

        // Et le saut intermédiaire n'a pas été escamoté : les tables de la v3
        // sont bien là, avec celles de la v4.
        final tables = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name NOT LIKE 'sqlite_%'",
            )
            .get();
        final noms = tables.map((l) => l.data['name'] as String).toSet();
        expect(
          noms,
          containsAll(const [
            'paniers_local',
            'lignes_panier_local',
            'pieces_facturation_local',
            'sequences_facture_local',
          ]),
        );
        await db.close();
      },
    );

    test('les données v2 SURVIVENT à la migration', () async {
      // Le point qui compte. Recréer le schéma aurait été plus court à écrire
      // et aurait effacé les saisies hors ligne — la seule donnée qui n'existe
      // nulle part ailleurs.
      await ramenerEnV2(fichier, avecReservation: true);

      final v3 = AppDatabase.surFichier(fichier);
      final reservations = await v3.select(v3.reservationsLocal).get();

      expect(
        reservations,
        hasLength(1),
        reason: 'la ligne v2 n’a pas été perdue',
      );
      expect(reservations.single.id, 'res-1');
      expect(reservations.single.tarifNuit, 28000);
      await v3.close();
    });

    test('la migration n’invente AUCUN panier', () async {
      // Y déduire des paniers depuis les ventes bar existantes créerait des
      // consommations que personne n'a saisies.
      await ramenerEnV2(fichier, avecReservation: true);

      final v3 = AppDatabase.surFichier(fichier);
      expect(await v3.select(v3.paniersLocal).get(), isEmpty);
      expect(await v3.select(v3.lignesPanierLocal).get(), isEmpty);
      await v3.close();
    });

    test(
      'la migration n’invente AUCUN panier pour les séjours repris',
      () async {
        // ⚠ Ce cas vérifiait que la migration n'écrit rien en file de
        // synchronisation. La file a disparu le 14/09/2026 (zéro réseau) : la
        // question n'a plus d'objet, mais son INTENTION en garde une — une
        // migration ne doit pas fabriquer de travail que personne n'a saisi.
        //
        // Déduire un panier des réservations reprises créerait des
        // consommations que personne n'a servies, et elles se présenteraient au
        // départ du client comme une addition à payer.
        await ramenerEnV2(fichier, avecReservation: true);

        final v3 = AppDatabase.surFichier(fichier);
        expect(await v3.select(v3.paniersLocal).get(), isEmpty);
        expect(await v3.select(v3.lignesPanierLocal).get(), isEmpty);
        await v3.close();
      },
    );

    test('la base migrée est utilisable : un panier s’y ouvre', () async {
      // Une migration qui crée les tables mais laisse le schéma inutilisable
      // passerait les quatre tests précédents.
      await ramenerEnV2(fichier, avecReservation: true);

      final v3 = AppDatabase.surFichier(fichier);
      final depot = PanierRepositoryLocal(PanierDao(v3));
      final p = await depot.ouvrir(
        typeVente: TypeVente.surSejour,
        reservationId: 'res-1',
        dateDepartPrevue: DateTime(2026, 8, 24),
      );
      final avec = await depot.ajouterLigne(p.id, biere);

      expect(avec.total, 1000);
      await v3.close();
    });
  });
}
