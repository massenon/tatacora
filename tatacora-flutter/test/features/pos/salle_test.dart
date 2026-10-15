import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import 'support/outils_ventes.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/data/tables_pos_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/espace_pos.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/unicite_panier_ouvert.dart';
import '../../core/database/retour_arriere_schema.dart';

/// Le panneau **Salle** — référentiel des tables et occupation déduite.
///
/// Porté à l'origine du moteur de tables de l'ancien prototype (archivé depuis
/// PA-183). La même règle vit aujourd'hui côté serveur dans
/// `app/Domain/Ventes/Services/TableSalleService.php`.
void main() {
  late AppDatabase base;
  late TablesPosDao tables;
  late PanierDao paniers;

  /// Le DAO verifie qu'un article ajoute EXISTE reellement au catalogue local
  /// (garde Q1) : sans ce semis, la ligne designerait un article inexistant.
  Future<void> semerCarte(AppDatabase db) => db
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

  setUp(() async {
    base = AppDatabase.enMemoire();
    // Clôturer passe la pièce de la vente : référentiel comptable et auteur.
    await avecComptabilite(base);
    tables = TablesPosDao(base);
    paniers = panierDaoSur(base);
    await semerCarte(base);
    await ouvrirLaCaisseDuComptoir(base);
  });

  tearDown(() => base.close());

  group('Le référentiel', () {
    test('le jeu initial est semé au premier accès : 6 + 4 + 3', () async {
      final t = await tables.toutes();

      expect(t.length, 13);
      expect(t.where((x) => x.espace == EspacePos.restaurant).length, 6);
      expect(t.where((x) => x.espace == EspacePos.jardin).length, 4);
      expect(t.where((x) => x.espace == EspacePos.plage).length, 3);
    });

    test('les libellés suivent le préfixe de leur espace', () async {
      final t = await tables.toutes();

      expect(
        t.where((x) => x.espace == EspacePos.restaurant).map((x) => x.libelle),
        containsAll(['R1', 'R6']),
      );
      expect(t.map((x) => x.libelle), contains('J4'));
      expect(t.map((x) => x.libelle), contains('P3'));
    });

    test('le semis ne se rejoue PAS au second accès', () async {
      await tables.toutes();
      final deuxieme = await tables.toutes();

      // Sans ce contrôle, chaque ouverture de l'écran ajouterait treize
      // tables, et la salle deviendrait illisible en une journée.
      expect(deuxieme.length, 13);
    });

    test('le comptoir ne comporte AUCUNE table', () async {
      expect(EspacePos.comptoir.avecTables, isFalse);
      expect(
        () => tables.creer(espace: EspacePos.comptoir, numero: 1),
        throwsArgumentError,
      );
      // Et il n'apparaît pas dans la salle : lui inventer une table créerait
      // un objet à ouvrir et fermer qui ne correspond à rien.
      final rayons = await tables.salle();
      expect(rayons.map((r) => r.espace), isNot(contains(EspacePos.comptoir)));
    });

    test('deux tables ne portent pas le même numéro dans un espace', () async {
      await tables.toutes();
      // « T3 » désignerait deux endroits, et l'addition partirait au mauvais.
      expect(
        () => tables.creer(espace: EspacePos.restaurant, numero: 3),
        throwsA(anything),
      );
    });
  });

  group('L’occupation se DÉDUIT des paniers', () {
    test('une table sans panier est libre', () async {
      final t = (await tables.toutes()).first;

      expect(await tables.estOccupee(t.id), isFalse);
      final rayons = await tables.salle();
      final cas = rayons
          .expand((r) => r.cases)
          .firstWhere((c) => c.table.id == t.id);
      expect(cas.libre, isTrue);
      expect(cas.occupee, isFalse);
    });

    test('ouvrir un panier sur la table l’occupe', () async {
      final t = (await tables.toutes()).first;
      await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );

      expect(await tables.estOccupee(t.id), isTrue);
    });

    test('CLÔTURER suffit à la libérer — aucun drapeau à remettre', () async {
      final t = (await tables.toutes()).first;
      final p = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );
      await paniers.ajouterLigne(p.id, _biere);
      await paniers.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierDeVente,
      );

      // La propriété qui compte : l'occupation n'étant PAS une colonne, il n'y
      // a aucun drapeau à remettre à zéro, donc aucun à oublier. Un champ
      // `occupee` se serait désynchronisé au premier panier clôturé depuis un
      // autre écran, et la salle aurait affiché occupée une table libre depuis
      // une heure (PA-59/60/61).
      expect(await tables.estOccupee(t.id), isFalse);
    });

    test('annuler la libère aussi', () async {
      final t = (await tables.toutes()).first;
      final p = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );
      await paniers.annuler(p.id, 'Table ouverte par erreur');

      expect(await tables.estOccupee(t.id), isFalse);
    });

    test('aucune colonne « occupee » n’existe au schéma', () async {
      // La garde structurelle : si quelqu'un ajoutait ce champ, la déduction
      // ci-dessus deviendrait un doublon qui divergerait.
      final colonnes = await base
          .customSelect('PRAGMA table_info(tables_local)')
          .get();
      final noms = colonnes.map((l) => l.data['name'] as String).toSet();
      expect(noms, isNot(contains('occupee')));
      expect(noms, containsAll(['id', 'espace', 'numero', 'libelle', 'actif']));
    });
  });

  group('Un seul panier ouvert par table', () {
    test('une seconde ouverture sur la même table est REFUSÉE', () async {
      final t = (await tables.toutes()).first;
      await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );

      // Deux paniers sur une table scinderaient l'addition, et la moitié
      // manquerait au moment de l'encaisser.
      expect(
        () => paniers.ouvrir(
          typeVente: TypeVente.comptant,
          tableId: t.id,
          espace: t.espace.code,
        ),
        throwsA(isA<TableDejaServie>()),
      );
    });

    test('rouvrir une table RETROUVE son panier', () async {
      final t = (await tables.toutes()).first;
      final p = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );

      expect(await tables.panierOuvertDe(t.id), p.id);
    });

    test('deux tables se servent EN MÊME TEMPS', () async {
      final t = await tables.toutes();
      final a = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t[0].id,
        espace: t[0].espace.code,
      );
      final b = await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t[7].id,
        espace: t[7].espace.code,
      );

      expect(a.id, isNot(b.id));
      expect(await tables.estOccupee(t[0].id), isTrue);
      expect(await tables.estOccupee(t[7].id), isTrue);
    });

    test('le COMPTOIR n’occupe aucune table, et n’est jamais unique', () async {
      // Deux ventes au comptoir en parallèle sont normales : elles n'ont
      // aucune table, donc rien à partager.
      final a = await paniers.ouvrir(typeVente: TypeVente.comptant);
      final b = await paniers.ouvrir(typeVente: TypeVente.comptant);

      expect(a.tableId, isNull);
      expect(b.tableId, isNull);
      final rayons = await tables.salle();
      expect(rayons.expand((r) => r.cases).every((c) => !c.occupee), isTrue);
    });
  });

  group('Activation — jamais de suppression', () {
    test('une table servie ne se désactive PAS', () async {
      final t = (await tables.toutes()).first;
      await paniers.ouvrir(
        typeVente: TypeVente.comptant,
        tableId: t.id,
        espace: t.espace.code,
      );

      expect(() => tables.basculer(t.id), throwsA(isA<TableOccupee>()));
    });

    test('une table libre se désactive, et reste VISIBLE', () async {
      final t = (await tables.toutes()).first;
      final apres = await tables.basculer(t.id);

      expect(apres.actif, isFalse);

      // Barrée, pas masquée : une table absente de l'écran laisse croire
      // qu'elle n'existe pas, et un serveur la cherche.
      final avecFermees = await tables.salle(inclureFermees: true);
      expect(
        avecFermees.expand((r) => r.cases).map((c) => c.table.id),
        contains(t.id),
      );

      final sansFermees = await tables.salle();
      expect(
        sansFermees.expand((r) => r.cases).map((c) => c.table.id),
        isNot(contains(t.id)),
      );
    });

    test('aucune méthode de suppression n’est exposée', () async {
      // Une table supprimée laisserait les ventes passées pointer vers un
      // identifiant inexistant, et l'analyse par table perdrait son historique.
      final source = File(
        'lib/features/pos/data/tables_pos_dao.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('Future<void> supprimer')));
      expect(source, isNot(contains('delete(tablesLocal)')));
    });
  });

  group('Migration v5 → v6 — le chemin de la mise à jour', () {
    late Directory dossier;
    late File fichier;

    setUp(() {
      dossier = Directory.systemTemp.createTempSync('tatacora_v6_');
      fichier = File('${dossier.path}/base.sqlite');
    });

    tearDown(() => dossier.deleteSync(recursive: true));

    /// Ramène un fichier v6 à l'état v5 : la table neuve est retirée, les deux
    /// colonnes du panier aussi, et `user_version` remis à 5.
    ///
    /// Plus fidèle que de recréer une v5 à la main — le reste du schéma est
    /// celui que Drift produit réellement.
    Future<void> ramenerEnV5(File f, {bool avecPanier = false}) async {
      final db = AppDatabase.surFichier(f);
      await db.customStatement('SELECT 1'); // force `onCreate`

      if (avecPanier) {
        await semerCarte(db);
        // Un panier OUVERT : la donnée que la v6 touche, et donc celle
        // qu'une migration bâclée effacerait. C'est aussi la seule copie
        // existante — le panier ne part pas au serveur.
        final dao = PanierDao(db);
        final p = await dao.ouvrir(
          typeVente: TypeVente.comptant,
          pointVente: 'Réception',
        );
        await dao.ajouterLigne(p.id, _biere);
      }

      // Le retrait vient APRES le semis : le panier ci-dessus est ecrit par
      // le DAO courant, qui connait les colonnes de la v6. Le semer sur un
      // schema deja ramene en arriere echouerait.
      await ramenerSchemaA(db, 5);
      await db.close();
    }

    test('la table et les deux colonnes apparaissent à l’ouverture', () async {
      await ramenerEnV5(fichier);

      final db = AppDatabase.surFichier(fichier);
      final tablesSql = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(
        tablesSql.map((l) => l.data['name'] as String),
        contains('tables_local'),
      );

      final colonnes = await db
          .customSelect('PRAGMA table_info(paniers_local)')
          .get();
      final noms = colonnes.map((l) => l.data['name'] as String).toSet();
      expect(noms, containsAll(['table_id', 'espace']));
      await db.close();
    });

    test('le panier existant SURVIT, et sa table reste nulle', () async {
      await ramenerEnV5(fichier, avecPanier: true);

      final db = AppDatabase.surFichier(fichier);
      final dao = PanierDao(db);
      final tous = await dao.paniers();

      expect(tous, hasLength(1));
      expect(tous.first.lignes, hasLength(1));
      expect(tous.first.estOuvert, isTrue);

      // NULLE, et c'est l'état réel : ce panier a été saisi quand la notion de
      // table n'existait pas. Lui en attribuer une par défaut inventerait une
      // table où le client ne s'est jamais assis.
      expect(tous.first.tableId, isNull);
      expect(tous.first.espace, isNull);
      await db.close();
    });

    test('AUCUNE table de salle n’est semée par la migration', () async {
      await ramenerEnV5(fichier);

      final db = AppDatabase.surFichier(fichier);
      final n = await db
          .customSelect('SELECT COUNT(*) c FROM tables_local')
          .getSingle();

      // Le semis appartient au DAO, au premier accès, là où l'exploitant peut
      // le voir et le corriger. Le poser dans la migration le rendrait
      // invisible et non rejouable : un poste dont l'exploitant a supprimé ses
      // tables les verrait revenir à la mise à jour suivante.
      expect(n.data['c'], 0);
      await db.close();
    });
  });
}

const _biere = ArticleVendable(
  reference: ReferenceCatalogue(module: ModuleVendable.m5Bar, code: 'bsn-33'),
  libelle: 'Béninoise 33cl',
  prix: 1000,
  categorie: 'Bières',
);
