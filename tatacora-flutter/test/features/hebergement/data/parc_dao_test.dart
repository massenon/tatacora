import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/hebergement/data/parc_dao.dart';
import 'package:tatacora_flutter/features/hebergement/domain/refus_parc.dart';

/// Le CRUD LOCAL du parc — sur une vraie base SQLite en mémoire.
///
/// ## Ce que ces cas protègent
///
/// Le parc descendait du serveur (PA-128) ; le poste est zéro réseau depuis le
/// 14/09/2026, et plus rien ne l'alimentait : un poste neuf ne pouvait prendre
/// aucune réservation. Ces cas éprouvent le chemin qui referme ce point, et
/// surtout le **verrou d'archivage** — le seul endroit où le parc peut détruire
/// une information qui n'existe plus nulle part ailleurs.
void main() {
  late AppDatabase db;
  late ParcDao dao;

  // Horloge FIGÉE : le verrou d'archivage compare au jour courant, et un test
  // qui dépend de `DateTime.now()` bascule à minuit.
  final aujourdHui = DateTime.utc(2026, 9, 14);
  DateTime horloge() => aujourdHui;

  setUp(() async {
    db = AppDatabase.enMemoire();
    dao = ParcDao(db, maintenant: horloge);

    await db
        .into(db.clientsLocal)
        .insert(
          ClientsLocalCompanion.insert(
            id: 'cli-1',
            nom: 'KORA',
            prenom: const Value('Jean'),
            telephone: '+229 01 00 00 00 01',
            typeClient: 'particulier',
          ),
        );
  });

  tearDown(() => db.close());

  /// Une réservation posée DIRECTEMENT en base : ces cas éprouvent le verrou du
  /// parc, pas le chemin de création d'une réservation — qui a ses propres
  /// tests et dont `ReservationDao` reste l'unique auteur.
  Future<void> reservation({
    required String uniteId,
    required DateTime arrivee,
    required DateTime depart,
    String statut = 'confirmee',
    int tarifNuit = 28000,
    String id = 'res-1',
  }) => db
      .into(db.reservationsLocal)
      .insert(
        ReservationsLocalCompanion.insert(
          id: id,
          reference: 'LOC-$id',
          clientId: 'cli-1',
          uniteId: uniteId,
          dateArrivee: arrivee,
          dateDepart: depart,
          statut: statut,
          tarifNuit: tarifNuit,
        ),
      );

  Future<String> parcMinimal() async {
    final categorie = await dao.creerCategorie(
      libelle: 'Bungalow',
      capaciteMax: 2,
      tarifBase: 28000,
    );
    return dao.creerUnite(numero: 'BNG-01', categorieId: categorie.id);
  }

  /* ================================================================== */
  group('Créer une catégorie', () {
    test('elle se relit avec son tarif et sa capacité', () async {
      final creee = await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 3,
        tarifBase: 28000,
      );

      final relue = await dao.categorieParId(creee.id);
      expect(relue, isNotNull);
      expect(relue!.libelle, 'Bungalow');
      expect(relue.capaciteMax, 3);
      // Le montant est un ENTIER côté domaine, un `REAL` au schéma : la
      // conversion vit au DAO, et elle ne doit rien perdre.
      expect(relue.tarifBase, 28000);
    });

    test('un tarif nul est REFUSÉ, jamais accepté en silence', () async {
      // « La catégorie naît AVEC son tarif réel — jamais un zéro d'attente qui
      // se lirait comme une nuit gratuite. »
      await expectLater(
        dao.creerCategorie(libelle: 'Tente', capaciteMax: 2, tarifBase: 0),
        throwsA(isA<TarifCategorieInvalide>()),
      );
      expect(await dao.categories(), isEmpty);
    });

    test('une capacité nulle est refusée', () async {
      await expectLater(
        dao.creerCategorie(libelle: 'Tente', capaciteMax: 0, tarifBase: 9000),
        throwsA(isA<CapaciteCategorieInvalide>()),
      );
    });

    test('un libellé vide est refusé', () async {
      await expectLater(
        dao.creerCategorie(libelle: '   ', capaciteMax: 2, tarifBase: 9000),
        throwsA(isA<LibelleCategorieRequis>()),
      );
    });

    test('deux libellés identiques sont refusés — CASSE comprise', () async {
      // Deux « Bungalow » porteraient deux tarifs, et la réservation prendrait
      // celui que la base rendrait en premier. C'est le défaut que PA-160/161
      // a coûté côté serveur, où deux seeders semaient le même référentiel.
      await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      );

      await expectLater(
        dao.creerCategorie(
          libelle: '  bungalow ',
          capaciteMax: 4,
          tarifBase: 31000,
        ),
        throwsA(isA<LibelleCategorieDejaPris>()),
      );
      expect(await dao.categories(), hasLength(1));
    });
  });

  /* ================================================================== */
  group('Créer une unité', () {
    test('elle entre au parc LIBRE — le statut ne se saisit pas', () async {
      final id = await parcMinimal();

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();

      // La vue le dit : « `statut` ne se SAISIT pas — il est écrit par les
      // gestes ». Le laisser choisir ferait dire à l'écran qu'une chambre est
      // occupée sans que personne y dorme.
      expect(unite.statut, 'libre');
      expect(unite.numero, 'BNG-01');
    });

    test('deux unités du même code sont refusées', () async {
      final categorie = await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      );
      await dao.creerUnite(numero: 'BNG-01', categorieId: categorie.id);

      // Le numéro est ce que le personnel prononce (« la BNG-01 ») : deux
      // homonymes rendraient toute conversation ambiguë.
      await expectLater(
        dao.creerUnite(numero: 'bng-01', categorieId: categorie.id),
        throwsA(isA<NumeroUniteDejaPris>()),
      );
    });

    test('une catégorie inconnue est refusée — vraie clé étrangère', () async {
      await expectLater(
        dao.creerUnite(numero: 'BNG-09', categorieId: 'cat-inexistante'),
        throwsA(isA<CategorieIntrouvable>()),
      );
      expect(await db.select(db.unitesHebergementLocal).get(), isEmpty);
    });

    test('un code vide est refusé', () async {
      final categorie = await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      );
      await expectLater(
        dao.creerUnite(numero: '  ', categorieId: categorie.id),
        throwsA(isA<NumeroUniteRequis>()),
      );
    });
  });

  /* ================================================================== */
  group('Modifier', () {
    test('le code et la catégorie d’une unité changent', () async {
      final id = await parcMinimal();
      final suite = await dao.creerCategorie(
        libelle: 'Suite',
        capaciteMax: 4,
        tarifBase: 45000,
      );

      await dao.modifierUnite(id, numero: 'BNG-02', categorieId: suite.id);

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.numero, 'BNG-02');
      expect(unite.categorieId, suite.id);
    });

    test('corriger un tarif ne réécrit AUCUN montant déjà réservé', () async {
      // `tarifNuit` est figé sur la réservation (PA-55) : le catalogue dit ce
      // qu'on vend aujourd'hui, la réservation dit ce qui a été vendu. Sans
      // cette garantie, corriger une grille réécrirait le prix d'un séjour
      // que le client a déjà accepté.
      final uniteId = await parcMinimal();
      await reservation(
        uniteId: uniteId,
        arrivee: DateTime.utc(2026, 9, 20),
        depart: DateTime.utc(2026, 9, 22),
        tarifNuit: 28000,
      );

      final categorie = (await dao.categories()).single;
      await dao.modifierCategorie(
        categorie.id,
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 35000,
      );

      final relue = await db.select(db.reservationsLocal).getSingle();
      expect(relue.tarifNuit, 28000, reason: 'tarif figé à la réservation');
      expect((await dao.categories()).single.tarifBase, 35000);
    });

    test('renommer vers un libellé déjà pris est refusé', () async {
      await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      );
      final suite = await dao.creerCategorie(
        libelle: 'Suite',
        capaciteMax: 4,
        tarifBase: 45000,
      );

      await expectLater(
        dao.modifierCategorie(
          suite.id,
          libelle: 'Bungalow',
          capaciteMax: 4,
          tarifBase: 45000,
        ),
        throwsA(isA<LibelleCategorieDejaPris>()),
      );
    });

    test('une catégorie peut garder SON propre libellé', () async {
      // Le cas qui casse une garde d'unicité mal écrite : sans exclusion de
      // soi-même, corriger le seul tarif d'une catégorie serait refusé — par
      // elle-même.
      final categorie = await dao.creerCategorie(
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 28000,
      );

      final modifiee = await dao.modifierCategorie(
        categorie.id,
        libelle: 'Bungalow',
        capaciteMax: 2,
        tarifBase: 31000,
      );
      expect(modifiee.tarifBase, 31000);
    });

    test('une unité peut garder SON propre code', () async {
      final id = await parcMinimal();
      final categorie = (await dao.categories()).single;

      await dao.modifierUnite(id, numero: 'BNG-01', categorieId: categorie.id);
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.numero, 'BNG-01');
    });
  });

  /* ================================================================== */
  group('Archiver — supprimer n’existe pas', () {
    test('une unité LIBRE est retirée du parc, et rien n’est effacé', () async {
      final id = await parcMinimal();

      await dao.archiver(id);

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingleOrNull();

      // La ligne EXISTE toujours : la supprimer rendrait illisibles toutes les
      // réservations qui la citent — et sur un poste sans serveur, elles
      // n'existent nulle part ailleurs.
      expect(unite, isNotNull, reason: 'archiver n’est pas supprimer');
      expect(unite!.statut, 'hors_service');
    });

    test(
      'une unité ENGAGÉE ne s’archive pas, et le refus NOMME la réservation',
      () async {
        final id = await parcMinimal();
        await reservation(
          uniteId: id,
          arrivee: DateTime.utc(2026, 9, 20),
          depart: DateTime.utc(2026, 9, 22),
        );

        await expectLater(
          dao.archiver(id),
          throwsA(
            isA<UniteEngagee>().having(
              (refus) => refus.message,
              'message',
              allOf(
                contains('Élément engagé dans 1 opération(s)'),
                // Un refus opaque enverrait chercher ailleurs : la phrase dit
                // QUELLE réservation tient la chambre.
                contains('réservation du 20/09/2026 au 22/09/2026'),
                contains('la ligne correspondante deviendrait illisible'),
              ),
            ),
          ),
        );

        // Et rien n'a bougé : un refus qui laisserait une trace serait pire
        // qu'inutile.
        final unite = await (db.select(
          db.unitesHebergementLocal,
        )..where((u) => u.id.equals(id))).getSingle();
        expect(unite.statut, 'libre');
      },
    );

    test('une réservation ANNULÉE n’engage plus rien', () async {
      // RG-02 : l'unité redevient disponible immédiatement, et c'est tout
      // l'intérêt de conserver la ligne plutôt que de la supprimer.
      final id = await parcMinimal();
      await reservation(
        uniteId: id,
        arrivee: DateTime.utc(2026, 9, 20),
        depart: DateTime.utc(2026, 9, 22),
        statut: 'annulee',
      );

      await dao.archiver(id);
      expect(await dao.engagements(id), isEmpty);
    });

    test('une réservation PASSÉE n’engage plus rien', () async {
      // Le prédicat du serveur : `date_depart >= aujourd'hui`. Un séjour
      // terminé reste lisible — l'archivage n'efface pas l'unité.
      final id = await parcMinimal();
      await reservation(
        uniteId: id,
        arrivee: DateTime.utc(2026, 9, 1),
        depart: DateTime.utc(2026, 9, 3),
      );

      await dao.archiver(id);
      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'hors_service');
    });

    test('une réservation qui s’achève AUJOURD’HUI engage encore', () async {
      // La borne est `>=`, et elle porte sur le JOUR : à 00 h 01, une
      // comparaison à l'instant courant ferait disparaître du verrou une
      // réservation qui s'achève aujourd'hui.
      final id = await parcMinimal();
      await reservation(
        uniteId: id,
        arrivee: DateTime.utc(2026, 9, 12),
        depart: aujourdHui,
      );

      expect(await dao.engagements(id), hasLength(1));
      await expectLater(dao.archiver(id), throwsA(isA<UniteEngagee>()));
    });

    test('une unité déjà archivée ne se réarchive pas', () async {
      final id = await parcMinimal();
      await dao.archiver(id);

      await expectLater(dao.archiver(id), throwsA(isA<UniteDejaArchivee>()));
    });

    test('restaurer la ramène au parc — la promesse est tenue', () async {
      // Sans ce geste, « reste restaurable — rien n'est effacé » serait une
      // promesse que rien ne tient (PA-59/60/61).
      final id = await parcMinimal();
      await dao.archiver(id);

      await dao.restaurer(id);

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre');
    });
  });

  /* ================================================================== */
  group('Le cycle que ce poste tient réellement', () {
    test('« Marquer Nettoyé & Prêt » ramène l’unité libre', () async {
      final id = await parcMinimal();
      await (db.update(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).write(
        const UnitesHebergementLocalCompanion(statut: Value('nettoyage')),
      );

      await dao.marquerNettoyee(id);

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'libre');
    });

    test('une unité HORS SERVICE n’est jamais touchée par le ménage', () async {
      // La maintenance prime sur l'exploitation — c'est l'exclusion que le
      // service de séjour pose lui-même côté serveur. Sans elle, le ménage
      // remettrait en vente une chambre condamnée.
      final id = await parcMinimal();
      await dao.archiver(id);

      await dao.marquerNettoyee(id);

      final unite = await (db.select(
        db.unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).getSingle();
      expect(unite.statut, 'hors_service');
    });

    test('une unité inconnue est refusée, jamais ignorée', () async {
      await expectLater(
        dao.marquerNettoyee('u-inexistante'),
        throwsA(isA<UniteIntrouvableAuParc>()),
      );
    });
  });
}
