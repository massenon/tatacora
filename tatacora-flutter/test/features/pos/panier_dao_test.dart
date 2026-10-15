import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import '../facturation/support/outils_encaissement.dart'
    show ouvrirLaCaisseDuComptoir;
import 'support/outils_ventes.dart';
import 'package:tatacora_flutter/core/database/app_database.dart';
import 'package:tatacora_flutter/features/pos/data/catalogue_dao.dart';
import 'package:tatacora_flutter/features/pos/data/panier_dao.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/article_vendable.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/panier.dart';
import 'package:tatacora_flutter/features/pos/domain/entities/reference_catalogue.dart';
import 'package:tatacora_flutter/features/pos/domain/repositories/panier_repository.dart';

/// Ce que le DAO garantit, et que le domaine seul ne peut pas garantir.
///
/// Trois sujets y vivent, et chacun a sa raison d'être ici plutôt qu'ailleurs :
///
///  - **⚠ Q1** — la vérification du code d'article contre le catalogue local,
///    qui remplace sur ce client la clé étrangère de l'option A ;
///  - **la file de synchronisation** — un panier ne doit RIEN y écrire ;
///  - **le catalogue** — ce qu'il offre hors ligne, et ce qu'il ne peut pas
///    offrir.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase base;
  late PanierDao dao;

  Future<void> semer() async {
    await base
        .into(base.cartesBoissonLocal)
        .insert(
          CartesBoissonLocalCompanion.insert(
            id: 'bsn-33',
            articleId: 'art-bsn',
            libelle: 'Béninoise 33cl',
            categorie: 'locale',
            prixVente: 1000,
          ),
        );
    await base
        .into(base.vehiculesLocal)
        .insert(
          VehiculesLocalCompanion.insert(
            id: 'veh-1',
            categorie: 'Berline',
            immatriculation: 'AB-123-BJ',
            tarifJour: 25000,
            statut: 'disponible',
          ),
        );
    await base
        .into(base.circuitsLocal)
        .insert(
          CircuitsLocalCompanion.insert(
            id: 'cir-1',
            nom: 'Cascades de Tanougou',
            theme: 'Nature',
            zone: 'Atacora',
            prix: 4500,
            capaciteMax: 12,
          ),
        );
  }

  setUp(() async {
    base = AppDatabase.enMemoire();
    // Clôturer passe la pièce de la vente : référentiel comptable et auteur.
    await avecComptabilite(base);
    await semer();
    await ouvrirLaCaisseDuComptoir(base);
    dao = panierDaoSur(base);
  });

  tearDown(() => base.close());

  /* ================================================================== */
  group('⚠ Q1 — la ligne désigne un article qui EXISTE', () {
    test('un code de boisson inconnu est refusé', () async {
      final p = await dao.ouvrir(typeVente: TypeVente.comptant);

      // C'est exactement ce que `commandes_restaurant.table_ou_chambre_id`
      // ne fait pas (PA-76) : un champ qui peut viser une cible inexistante.
      await expectLater(
        dao.ajouterLigne(
          p.id,
          const ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m5Bar,
              code: 'bsn-fantome',
            ),
            libelle: 'Boisson qui n’existe pas',
            prix: 1000,
          ),
        ),
        throwsA(isA<ArticleHorsCatalogue>()),
      );
      expect((await dao.parId(p.id))!.lignes, isEmpty);
    });

    test('un véhicule et un circuit inconnus sont refusés eux aussi', () async {
      final p = await dao.ouvrir(typeVente: TypeVente.comptant);

      for (final ref in const [
        ReferenceCatalogue(module: ModuleVendable.m8Vehicules, code: 'veh-x'),
        ReferenceCatalogue(module: ModuleVendable.m9Tourisme, code: 'cir-x'),
      ]) {
        await expectLater(
          dao.ajouterLigne(
            p.id,
            ArticleVendable(reference: ref, libelle: 'Inconnu', prix: 500),
          ),
          throwsA(isA<ArticleHorsCatalogue>()),
        );
      }
    });

    test(
      'les trois modules répliqués sont acceptés quand le code existe',
      () async {
        final p = await dao.ouvrir(typeVente: TypeVente.comptant);

        await dao.ajouterLigne(
          p.id,
          const ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m5Bar,
              code: 'bsn-33',
            ),
            libelle: 'Béninoise 33cl',
            prix: 1000,
          ),
        );
        await dao.ajouterLigne(
          p.id,
          const ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m8Vehicules,
              code: 'veh-1',
            ),
            libelle: 'Berline AB-123-BJ',
            prix: 25000,
          ),
        );
        final apres = await dao.ajouterLigne(
          p.id,
          const ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m9Tourisme,
              code: 'cir-1',
            ),
            libelle: 'Cascades de Tanougou',
            prix: 4500,
          ),
        );

        expect(apres.lignes, hasLength(3));
        expect(apres.total, 30500);
      },
    );

    test(
      'M4 est VÉRIFIÉ comme les autres : un plat inconnu est refusé',
      () async {
        // `plats_local` existe depuis la v14 (09/10/2026). Jusqu'à cette date la
        // ligne M4 était acceptée sans rien vérifier — la limite était nommée,
        // pas cachée ; elle est refermée, et ce cas FIGE la fermeture.
        final p = await dao.ouvrir(typeVente: TypeVente.comptant);

        await expectLater(
          dao.ajouterLigne(
            p.id,
            const ArticleVendable(
              reference: ReferenceCatalogue(
                module: ModuleVendable.m4Restaurant,
                code: 'plat-inexistant',
              ),
              libelle: 'Poulet braisé',
              prix: 4500,
            ),
          ),
          throwsA(isA<ArticleHorsCatalogue>()),
        );
        expect((await dao.parId(p.id))!.lignes, isEmpty);
      },
    );

    test('M4 : un plat qui existe est accepté, et la ligne FIGE son prix et '
        'son libellé', () async {
      await base
          .into(base.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-chef',
              login: 'chef',
              nom: 'Chef',
              role: 'cuisinier',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
      await base
          .into(base.menusLocal)
          .insert(
            MenusLocalCompanion.insert(
              id: 'm-1',
              libelle: 'Carte',
              type: 'local',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      await base
          .into(base.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: 'r-1',
              libelle: 'Fiche',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      await base
          .into(base.platsLocal)
          .insert(
            PlatsLocalCompanion.insert(
              id: 'p-dg',
              menuId: 'm-1',
              recetteId: 'r-1',
              libelle: 'Poulet DG',
              prixVente: 4500,
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );

      final article = (await CatalogueDao(base).rayons())
          .firstWhere((r) => r.module == ModuleVendable.m4Restaurant)
          .articles
          .single;
      final p = await dao.ouvrir(typeVente: TypeVente.comptant);
      final apres = await dao.ajouterLigne(p.id, article);

      expect(apres.lignes.single.reference.module, ModuleVendable.m4Restaurant);
      expect(apres.lignes.single.reference.code, 'p-dg');
      expect(apres.lignes.single.libelle, 'Poulet DG');
      expect(apres.lignes.single.prixUnitaire, 4500);

      // Le catalogue change : la ligne déjà saisie, non.
      await (base.update(
        base.platsLocal,
      )..where((t) => t.id.equals('p-dg'))).write(
        const PlatsLocalCompanion(
          libelle: Value('Poulet DG royal'),
          prixVente: Value(6000),
        ),
      );
      final relu = (await dao.parId(p.id))!.lignes.single;
      expect(relu.libelle, 'Poulet DG');
      expect(relu.prixUnitaire, 4500);
    });
  });

  /* ================================================================== */
  group('Le panier n’écrit RIEN en file de synchronisation', () {
    test('ouvrir, ajouter, clôturer : la file reste vide', () async {
      final p = await dao.ouvrir(typeVente: TypeVente.comptant);
      await dao.ajouterLigne(
        p.id,
        const ArticleVendable(
          reference: ReferenceCatalogue(
            module: ModuleVendable.m5Bar,
            code: 'bsn-33',
          ),
          libelle: 'Béninoise 33cl',
          prix: 1000,
        ),
      );
      await dao.cloturer(
        p.id,
        modePaiement: 'especes',
        auteurId: caissierDeVente,
      );

      // ⚠ Ce cas comptait les entrées de file : `paniers` n'était pas au
      // registre `TABLES_SYNCHRONISABLES`, donc une opération y aurait été
      // rejetée à chaque tentative pendant que le poste affichait « en attente
      // de synchronisation ». Depuis le 14/09/2026 il n'y a plus de file du
      // tout — la garantie est devenue structurelle.
      //
      // Ce qui reste vérifiable, et qui porte la même vérité : un panier
      // clôturé ne se déclare transmissible à personne. C'est le cas suivant
      // (« le statut de transmission dit la vérité ») qui l'énonce.
      expect(
        (await dao.parId(p.id))!.statutTransmission,
        StatutTransmissionPanier.nonTransmissible,
      );
    });

    test('le statut de transmission dit la vérité', () async {
      final p = await dao.ouvrir(typeVente: TypeVente.comptant);

      expect(
        p.statutTransmission,
        StatutTransmissionPanier.nonTransmissible,
        reason:
            'annoncer « en attente » serait un indicateur affirmant un état '
            'qu’il n’a pas vérifié (PA-59/60/61)',
      );
    });
  });

  /* ================================================================== */
  group('Catalogue hors ligne — ce qu’il offre, et ce qu’il ne peut pas', () {
    test('les trois catalogues répliqués remontent', () async {
      final rayons = await CatalogueDao(base).rayons();
      final parModule = {for (final r in rayons) r.module: r};

      expect(parModule[ModuleVendable.m5Bar]!.articles, hasLength(1));
      expect(parModule[ModuleVendable.m9Tourisme]!.articles, hasLength(1));
      expect(parModule[ModuleVendable.m8Vehicules]!.articles, hasLength(1));
    });

    test(
      'le rayon Restaurant est VIDE sur un poste neuf, et il dit quoi faire',
      () async {
        final rayons = await CatalogueDao(base).rayons();
        final restaurant = rayons.firstWhere(
          (r) => r.module == ModuleVendable.m4Restaurant,
        );

        // Un onglet absent laisserait croire que le restaurant n'est pas
        // vendable ici ; un onglet vide sans explication passerait pour cassé
        // (leçon PA-90). La raison n'accuse plus une panne ni une absence de
        // réplication : le catalogue est vide, et le geste qui le remplit existe.
        expect(restaurant.articles, isEmpty);
        expect(
          restaurant.indisponibiliteLocale,
          CatalogueDao.motifRestaurantVide,
        );
        expect(restaurant.indisponibiliteLocale, contains('Aucun plat'));
        expect(restaurant.indisponibiliteLocale, isNot(contains('connexion')));
      },
    );

    test('le rayon Restaurant offre les plats : prix du jour en francs, '
        'ordre sans accent, fiche vide DITE, aucune raison', () async {
      await base
          .into(base.utilisateursLocal)
          .insert(
            UtilisateursLocalCompanion.insert(
              id: 'u-chef',
              login: 'chef',
              nom: 'Chef',
              role: 'cuisinier',
              droitsJson: '{}',
              sel: 's',
              empreinte: 'e',
              iterations: 1,
              dateCreation: DateTime(2026, 10, 1),
              dateMotDePasse: DateTime(2026, 10, 1),
            ),
          );
      Future<void> menu(String id, String type) => base
          .into(base.menusLocal)
          .insert(
            MenusLocalCompanion.insert(
              id: id,
              libelle: 'Carte $id',
              type: type,
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      Future<void> fiche(String id) => base
          .into(base.recettesLocal)
          .insert(
            RecettesLocalCompanion.insert(
              id: id,
              libelle: 'Fiche $id',
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      Future<void> plat(
        String id,
        String libelle,
        int prix,
        String m,
        String r,
      ) => base
          .into(base.platsLocal)
          .insert(
            PlatsLocalCompanion.insert(
              id: id,
              menuId: m,
              recetteId: r,
              libelle: libelle,
              prixVente: prix,
              creeLe: DateTime(2026, 10, 1),
              creePar: 'u-chef',
            ),
          );
      await menu('m-l', 'local');
      await menu('m-e', 'europeen');
      await fiche('r-vide');
      await fiche('r-pleine');
      await base
          .into(base.articlesLocal)
          .insert(
            ArticlesLocalCompanion.insert(
              id: 'a-1',
              libelle: 'Riz',
              categorie: '',
              uniteMesure: 'kg',
              seuilAlerte: 0,
            ),
          );
      await base
          .into(base.ingredientsRecetteLocal)
          .insert(
            IngredientsRecetteLocalCompanion.insert(
              recetteId: 'r-pleine',
              articleId: 'a-1',
              quantiteMilliemes: 150,
            ),
          );
      await plat('p-z', 'Zèbre grillé', 12000, 'm-e', 'r-pleine');
      await plat('p-e', 'Épinards', 1500, 'm-l', 'r-vide');
      await plat('p-a', 'Alloco', 1000, 'm-l', 'r-pleine');

      final restaurant = (await CatalogueDao(
        base,
      ).rayons()).firstWhere((r) => r.module == ModuleVendable.m4Restaurant);

      // Aucune raison quand le rayon est garni.
      expect(restaurant.indisponibiliteLocale, isNull);
      expect(
        [for (final a in restaurant.articles) a.libelle],
        ['Alloco', 'Épinards', 'Zèbre grillé'],
      );
      expect(
        [for (final a in restaurant.articles) a.prix],
        [1000, 1500, 12000],
      );
      expect(
        [for (final a in restaurant.articles) a.reference.code],
        ['p-a', 'p-e', 'p-z'],
      );
      expect(
        [for (final a in restaurant.articles) a.categorie],
        ['local', 'local', 'europeen'],
      );
      // Seul le plat à fiche VIDE le dit.
      expect(
        [for (final a in restaurant.articles) a.detail],
        [null, CatalogueDao.detailFicheVide, null],
      );
      expect(restaurant.articles.every((a) => a.estVendable), isTrue);
    });

    test('le prix REAL du catalogue devient un entier de francs CFA', () async {
      // La conversion est faite une fois, au catalogue. La laisser au panier
      // produirait un arrondi sur l'addition, où il coûte de l'argent.
      final rayons = await CatalogueDao(base).rayons();
      final biere = rayons
          .firstWhere((r) => r.module == ModuleVendable.m5Bar)
          .articles
          .single;

      expect(biere.prix, 1000);
      expect(biere.estVendable, isTrue);
    });
  });
}
