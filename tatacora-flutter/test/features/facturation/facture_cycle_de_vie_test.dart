import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import '../comptabilite/support/outils_comptabilite.dart' show moteurSur;
import '../pos/support/outils_ventes.dart' show avecComptabilite;
import 'support/outils_encaissement.dart'
    show caissierEssai, ouvrirLaCaisseDuComptoir;
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_dao.dart';
import 'package:tatacora_flutter/features/facturation/data/facture_repository_local.dart';
import 'package:tatacora_flutter/features/facturation/domain/entities/piece_facturation.dart';
import 'package:tatacora_flutter/features/facturation/domain/repositories/facture_repository.dart';
import 'package:tatacora_flutter/features/facturation/domain/usecases/facturer.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_dao.dart';
import 'package:tatacora_flutter/features/hebergement/data/reservation_repository_local.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_repository_local.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/place_hebergement.dart';
import '../../core/database/retour_arriere_schema.dart';

/// **Le critère d'acceptation de D3, et les deux chemins que la base en mémoire
/// ne peut pas éprouver.**
///
/// > *Une facture survit à la fermeture de l'application* — constaté par le
/// > cycle écrire → fermer → rouvrir → relire, **sur fichier réel**, comme D0.3
/// > et D2.
///
/// Une facture vérifiée seulement en mémoire ne prouve rien de ce qui compte
/// ici : une pièce comptable se relit des mois plus tard, et le **compteur de
/// séquence** doit lui aussi survivre — sans quoi la première pièce du
/// lendemain reprendrait un numéro déjà remis à un client.
///
/// C'est aussi la leçon PA-59 : les tests Drift en mémoire passent toujours par
/// `onCreate` et n'empruntent **jamais** `onUpgrade`, qui était faux.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late Directory dossier;
  late File fichier;

  const annee = 2026;
  DateTime maintenant() => DateTime(annee, 8, 20, 14, 30);

  const biere = ArticleVendable(
    reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
    libelle: 'Béninoise 33cl',
    prix: 1000,
    categorie: 'locale',
  );

  setUp(() async {
    dossier = await Directory.systemTemp.createTemp('tatacora_facture_');
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
    // Clôturer un panier passe la pièce de la vente : le référentiel comptable
    // et un auteur doivent exister (l'exercice de l'année du test).
    await avecComptabilite(db, maintenant: maintenant());
  }

  /// Un PanierDao branché sur le moteur comptable de [db] — le chemin de
  /// production d'une clôture.
  PanierDao paniersSur(AppDatabase db) => PanierDao(
    db,
    maintenant: maintenant,
    moteur: () async => moteurSur(db, maintenant: maintenant),
  );

  /// Un panier de séjour clôturé, prêt à facturer.
  Future<Panier> panierCloture(AppDatabase db) async {
    final depot = PanierRepositoryLocal(paniersSur(db));
    final p = await depot.ouvrir(
      typeVente: TypeVente.surSejour,
      reservationId: 'res-1',
      clientNom: 'KORA',
      pointVente: 'Bar',
      dateDepartPrevue: DateTime.utc(2026, 8, 24),
    );
    await depot.ajouterLigne(p.id, biere, quantite: 2);
    return depot.cloturer(
      p.id,
      anticipe: true,
      modePaiement: 'especes',
      auteurId: caissierEssai,
    );
  }

  Facturer facturerSur(AppDatabase db) =>
      Facturer(FactureRepositoryLocal(FactureDao(db, maintenant: maintenant)));

  /* ================================================================== */
  group('Critère D3 — la facture survit à la fermeture', () {
    test('pièce, lignes et numéro sont relus après réouverture', () async {
      // Session 1 : le réceptionniste clôture le séjour et facture.
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      final panier = await panierCloture(premiere);
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(premiere),
      ).parId('res-1'))!;

      final emise = await facturerSur(
        premiere,
      ).emettrePourSejour(panier: panier, reservation: reservation);
      expect(emise.numero, 'F-$annee-00001');
      await premiere.close();

      // Le fichier existe sur le disque, indépendamment du processus.
      expect(fichier.existsSync(), isTrue);
      expect(fichier.lengthSync(), greaterThan(0));

      // Session 2 : l'application est relancée.
      final seconde = AppDatabase.surFichier(fichier);
      final depot = FactureRepositoryLocal(FactureDao(seconde));
      final relue = await depot.parNumero('F-$annee-00001');

      expect(relue, isNotNull, reason: 'la pièce a survécu');
      expect(relue!.id, emise.id);
      expect(relue.origine, OrigineFacture.posSejour);
      expect(relue.clientNom, 'KORA');
      expect(relue.statut, StatutPiece.emise);

      // ⚠ Q3 — hébergement et consommations restent NOMMÉS séparément, jamais
      // fondus en un total opaque.
      expect(relue.lignes, hasLength(2));
      expect(relue.lignes.first.module, ModuleFacturable.m1Hebergement);
      expect(relue.lignes.first.prixUnitaire, 28000);
      expect(relue.lignes.first.quantite, 6);
      expect(relue.lignes.last.module, ModuleFacturable.m5Bar);
      expect(relue.lignes.last.prixUnitaire, 1000);
      expect(relue.montantTotal, 168000 + 2000);

      // Et elle ne se déclare toujours pas certifiée.
      expect(relue.estCertifiee, isFalse);
      await seconde.close();
    });

    test(
      'le COMPTEUR survit lui aussi — sans quoi le numéro se réemploierait',
      () async {
        // Le point que la base en mémoire ne peut pas montrer. Si le compteur
        // repartait de zéro au redémarrage, la première pièce du lendemain
        // porterait un numéro déjà remis à un client — et rien ne le
        // signalerait, sauf la contrainte d'unicité, au comptoir.
        final premiere = AppDatabase.surFichier(fichier);
        await semer(premiere);
        final panier = await panierCloture(premiere);
        await facturerSur(premiere).emettreDirecte(
          clientNom: 'MAIRIE',
          lignes: const [
            LigneBrouillon(
              module: ModuleFacturable.m9Tourisme,
              libelle: 'Circuit groupe',
              prixUnitaire: 4500,
              quantite: 12,
            ),
          ],
        );
        expect(panier.statut, StatutPanier.cloture);
        await premiere.close();

        final seconde = AppDatabase.surFichier(fichier);
        final suivante = await facturerSur(seconde).emettreDirecte(
          clientNom: 'MAIRIE',
          lignes: const [
            LigneBrouillon(
              module: ModuleFacturable.m9Tourisme,
              libelle: 'Circuit groupe',
              prixUnitaire: 4500,
              quantite: 4,
            ),
          ],
        );

        expect(suivante.numero, 'F-$annee-00002');
        await seconde.close();
      },
    );

    test('l’avoir survit, et la facture annulée avec lui', () async {
      final premiere = AppDatabase.surFichier(fichier);
      await semer(premiere);
      final panier = await panierCloture(premiere);
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(premiere),
      ).parId('res-1'))!;
      final f = await facturerSur(
        premiere,
      ).emettrePourSejour(panier: panier, reservation: reservation);
      final r = await facturerSur(premiere).annuler(f.id, 'Erreur de saisie');
      await premiere.close();

      final seconde = AppDatabase.surFichier(fichier);
      final depot = FactureRepositoryLocal(FactureDao(seconde));

      final originale = (await depot.parId(f.id))!;
      expect(originale.statut, StatutPiece.annulee);
      expect(originale.montantTotal, 170000, reason: 'rien n’a été effacé');

      final avoir = (await depot.parId(r.avoir.id))!;
      expect(avoir.avoirDe, f.numero);
      expect(avoir.montantTotal, -170000);

      // ⚠ Le piège : l'avoir porte le même séjour et le statut `emise`. Sans
      // son exclusion, on proposerait au client un document à montant négatif.
      expect(await depot.facturePourReservation('res-1'), isNull);
      await seconde.close();
    });

    test('aucune écriture en file de synchronisation', () async {
      // `factures` n'est pas au registre `TABLES_SYNCHRONISABLES` du serveur,
      // et aucune route d'API de facturation n'existe. Un badge « en attente »
      // sur ce qui ne partira jamais serait PA-59/60/61 sous un autre jour.
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      final panier = await panierCloture(db);
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(db),
      ).parId('res-1'))!;
      await facturerSur(
        db,
      ).emettrePourSejour(panier: panier, reservation: reservation);

      // ⚠ Ce cas comptait les entrées de FILE : ni `factures` ni `paniers`
      // n'étaient au registre `TABLES_SYNCHRONISABLES`, donc une opération y
      // aurait été rejetée à chaque tentative pendant que l'écran annonçait
      // « en attente de synchronisation » sur une pièce qui ne partirait
      // jamais. Zéro réseau (14/09/2026) : il n'y a plus de file, et la
      // garantie est devenue structurelle.
      //
      // Ce qui reste vérifiable, et qui porte la même vérité : la facture
      // émise existe bien sur ce poste, et c'est tout ce qu'elle prétend être.
      expect(await db.select(db.piecesFacturationLocal).get(), isNotEmpty);
      await db.close();
    });
  });

  /* ================================================================== */
  group('⚠ Q3 — le refus traverse jusqu’à l’émission', () {
    test('l’autre branche REFUSE d’émettre, elle n’improvise pas', () async {
      // `CompositionFactureSejour.composer` lève sous
      // `PlaceHebergement.ligneDePanier`, et ce refus remonte jusqu'ici.
      // Personne ne peut émettre une facture de séjour sur une hypothèse que
      // l'arbitrage n'a pas rendue — un total fondu paraîtrait juste dans les
      // deux cas et serait faux dans l'un des deux.
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      final panier = await panierCloture(db);
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(db),
      ).parId('res-1'))!;

      await expectLater(
        facturerSur(db).emettrePourSejour(
          panier: panier,
          reservation: reservation,
          place: PlaceHebergement.ligneDePanier,
        ),
        throwsA(isA<UnimplementedError>()),
      );

      // Et rien n'a été écrit : ni pièce, ni numéro consommé.
      expect(await db.select(db.piecesFacturationLocal).get(), isEmpty);
      expect(await db.select(db.sequencesFactureLocal).get(), isEmpty);
      await db.close();
    });

    test('la position retenue nomme les deux montants séparément', () async {
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      final panier = await panierCloture(db);
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(db),
      ).parId('res-1'))!;

      final f = await facturerSur(
        db,
      ).emettrePourSejour(panier: panier, reservation: reservation);

      // « Votre chambre, vos consommations » est une phrase qu'on prononce ;
      // « 170 000 F » n'en est pas une.
      expect(f.ventilation, {
        ModuleFacturable.m1Hebergement: 168000,
        ModuleFacturable.m5Bar: 2000,
      });
      await db.close();
    });
  });

  /* ================================================================== */
  group('L’émission refuse ce qu’elle ne peut pas justifier', () {
    test('un panier encore OUVERT ne se facture pas', () async {
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      final depot = PanierRepositoryLocal(PanierDao(db));
      final p = await depot.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar',
      );
      final ouvert = await depot.ajouterLigne(p.id, biere, quantite: 2);

      await expectLater(
        facturerSur(db).emettreAuComptant(ouvert),
        throwsA(isA<PanierNonFacturable>()),
      );
      await db.close();
    });

    test('un même panier ne se facture pas DEUX fois', () async {
      // Au comptoir, un bouton qui ne réagit pas tout de suite se presse deux
      // fois. Sans cette garde, la seconde pression émettrait une seconde pièce
      // numérotée : un montant de plus au registre que personne n'a encaissé.
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      await ouvrirLaCaisseDuComptoir(db);
      final depot = PanierRepositoryLocal(paniersSur(db));
      final p = await depot.ouvrir(
        typeVente: TypeVente.comptant,
        pointVente: 'Bar',
      );
      await depot.ajouterLigne(p.id, biere, quantite: 2);
      final cloture = await depot.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierEssai,
      );

      final premiere = await facturerSur(db).emettreAuComptant(cloture);
      await expectLater(
        facturerSur(db).emettreAuComptant(cloture),
        throwsA(isA<FactureDejaEmise>()),
      );

      final registre = await FactureRepositoryLocal(FactureDao(db)).pieces();
      expect(registre, hasLength(1));
      expect(registre.single.id, premiere.id);
      await db.close();
    });

    test('un panier de séjour ne se facture pas au comptant', () async {
      final db = AppDatabase.surFichier(fichier);
      await semer(db);
      final panier = await panierCloture(db);

      await expectLater(
        facturerSur(db).emettreAuComptant(panier),
        throwsA(isA<PanierIncompatible>()),
      );
      await db.close();
    });
  });

  /* ================================================================== */
  group('Migration v3 → v4 — le chemin de la mise à jour', () {
    /// Ramène un fichier v4 à l'état v3 : les trois tables neuves sont retirées
    /// et `user_version` remis à 3.
    ///
    /// C'est plus fidèle que de recréer une v3 à la main — le reste du schéma
    /// est celui que Drift produit réellement, pas une transcription.
    ///
    /// [avecDonnees] sème **après** le retrait : l'ordre compte, car rouvrir
    /// `AppDatabase` déclenche `onUpgrade` aussitôt. C'est exactement la mise en
    /// scène qui avait révélé le défaut de la migration v1 → v2 (PA-59).
    Future<void> ramenerEnV3(File f, {bool avecDonnees = false}) async {
      final db = AppDatabase.surFichier(f);
      await db.customStatement('SELECT 1'); // force l'ouverture et `onCreate`

      if (avecDonnees) {
        await semer(db);
        // Un panier CLÔTURÉ : la donnée v3 la plus proche de ce que la v4
        // ajoute, et donc celle qu'une migration bâclée effacerait.
        await panierCloture(db);
      }

      // Le retrait vient APRES le semis : les DAO courants ecrivent les
      // colonnes des versions posterieures, qu'un schema deja ramene en
      // arriere n'a plus.
      await ramenerSchemaA(db, 3);
      await db.close();
    }

    test('les trois tables sont créées à l’ouverture', () async {
      await ramenerEnV3(fichier);

      final db = AppDatabase.surFichier(fichier);
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
          'pieces_facturation_local',
          'lignes_piece_facturation_local',
          'sequences_facture_local',
        ]),
      );
      await db.close();
    });

    test('la version du schéma passe bien à la version COURANTE', () async {
      await ramenerEnV3(fichier);

      final db = AppDatabase.surFichier(fichier);
      await db.customStatement('SELECT 1');
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      // Comparee a la version COURANTE, jamais a un literal : un
      // literal se perime a chaque migration, et il l'a fait — ecrit 4, il
      // a rougi le jour de la v5 sans qu'aucune regression n'existe.
      expect(version.data.values.first, db.schemaVersion);
      await db.close();
    });

    test('les données v3 SURVIVENT à la migration', () async {
      // Le point qui compte. Recréer le schéma aurait été plus court à écrire
      // et aurait effacé les saisies hors ligne — la seule donnée qui n'existe
      // nulle part ailleurs.
      await ramenerEnV3(fichier, avecDonnees: true);

      final v4 = AppDatabase.surFichier(fichier);

      final reservations = await v4.select(v4.reservationsLocal).get();
      expect(reservations, hasLength(1));
      expect(reservations.single.tarifNuit, 28000);

      final paniers = await v4.select(v4.paniersLocal).get();
      expect(paniers, hasLength(1), reason: 'le panier v3 n’a pas été perdu');
      expect(paniers.single.montantCloture, 2000);

      final lignes = await v4.select(v4.lignesPanierLocal).get();
      expect(lignes, hasLength(1));
      expect(lignes.single.prixUnitaire, 1000);
      await v4.close();
    });

    test('la migration n’invente AUCUNE facture', () async {
      // Émettre rétroactivement des pièces numérotées pour les paniers déjà
      // clôturés créerait des documents fiscaux que personne n'a émis, et leur
      // donnerait des numéros de l'année courante pour des ventes d'une autre.
      await ramenerEnV3(fichier, avecDonnees: true);

      final v4 = AppDatabase.surFichier(fichier);
      expect(await v4.select(v4.piecesFacturationLocal).get(), isEmpty);
      expect(await v4.select(v4.lignesPieceFacturationLocal).get(), isEmpty);
      expect(
        await v4.select(v4.sequencesFactureLocal).get(),
        isEmpty,
        reason: 'et la séquence ne démarre pas non plus toute seule',
      );
      await v4.close();
    });

    // ⚠ UN CAS RETIRÉ le 14/09/2026 : « la migration ne met RIEN en file de
    // synchronisation ». Aucune route de facturation n'a jamais existé au
    // serveur, et `factures` n'était pas au registre synchronisable : émettre
    // rétroactivement des pièces numérotées pour des ventes passées aurait
    // créé des documents fiscaux que personne n'a émis. Zéro réseau : la file
    // a disparu, le risque avec elle.

    test('la base migrée est utilisable : une facture s’y émet', () async {
      // Une migration qui crée les tables mais laisse le schéma inutilisable
      // passerait les cinq tests précédents.
      await ramenerEnV3(fichier, avecDonnees: true);

      final v4 = AppDatabase.surFichier(fichier);
      final panier = (await PanierRepositoryLocal(
        PanierDao(v4),
      ).paniers()).single;
      final reservation = (await ReservationRepositoryLocal(
        ReservationDao(v4),
      ).parId('res-1'))!;

      final f = await facturerSur(
        v4,
      ).emettrePourSejour(panier: panier, reservation: reservation);
      expect(f.numero, 'F-$annee-00001');
      expect(f.montantTotal, 170000);
      await v4.close();
    });
  });
}
