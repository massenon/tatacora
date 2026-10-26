import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/format/cle_comparaison.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/entities/article_vendable.dart';
import '../domain/entities/reference_catalogue.dart';
import '../domain/repositories/panier_repository.dart';
import 'dto/catalogue_dto.dart';

/// Le catalogue vendable, lu **dans la base locale**.
///
/// ## Le rayon Restaurant lit `plats_local` depuis le 09/10/2026 (schéma v14)
///
/// Jusqu'à cette date le rayon Restaurant était rendu VIDE avec sa raison : la
/// table `plats` n'était pas répliquée sur le poste. M4 est LOCAL (décision du
/// PO), et le rayon vend ce que le catalogue du restaurant de CE poste porte —
/// au prix et sous le libellé du jour. La ligne de panier, elle, FIGE les deux à
/// l'ajout : modifier le catalogue ne réécrit jamais une vente déjà saisie.
///
/// Un plat dont la fiche technique est vide se vend (le serveur lui-même ne
/// refuse qu'au moment de décrémenter), mais le rayon le DIT : « fiche vide »,
/// c'est-à-dire que sa vente ne décrémenterait rien. Ce poste, lui, ne
/// décrémente encore rien à aucune vente (RG-05 non portée) — la phrase vaut
/// pour tous les plats, et la carte du restaurant le dit.
///
/// Un rayon vide reste visible avec sa raison, jamais omis : un onglet absent
/// laisserait croire que le restaurant n'est pas vendable ici, un onglet vide
/// sans explication passerait pour cassé (leçon PA-90).
class CatalogueDao extends DatabaseAccessor<AppDatabase>
    implements CatalogueRepository {
  CatalogueDao(super.db);

  /// Le libellé affiché quand le rayon Restaurant est vide.
  ///
  /// Constante nommée : c'est la vérité d'un poste neuf, elle doit se retrouver
  /// par recherche. Elle n'accuse pas une panne — le catalogue est vide, et le
  /// geste qui le remplit existe.
  static const String motifRestaurantVide =
      "Aucun plat n'est encore au catalogue du restaurant de ce poste. Créez-en "
      'dans Restaurant et Cuisine : un plat appartient à un menu et porte une '
      'fiche technique. Les consommations du bar, du tourisme et de la '
      'location restent disponibles.';

  /// Ce que le rayon dit d'un plat dont la fiche technique est vide.
  static const String detailFicheVide = 'Fiche vide : ne décrémente rien';

  @override
  Future<List<RayonCatalogue>> rayons() async {
    return [
      RayonCatalogue(module: ModuleVendable.m5Bar, articles: await _boissons()),
      await _rayonRestaurant(),
      RayonCatalogue(
        module: ModuleVendable.m9Tourisme,
        articles: await _circuits(),
      ),
      RayonCatalogue(
        module: ModuleVendable.m8Vehicules,
        articles: await _vehicules(),
      ),
    ];
  }

  /// Écrit les catalogues — descente serveur d'hier (PA-129), amorçage de
  /// démonstration et, depuis le 14/09/2026, **saisie sur le poste**.
  ///
  /// ## Ce qui est écrit, et ce qui ne l'est surtout pas
  ///
  /// `stock_disponible` descend avec chaque boisson, et **n'est pas stocké** :
  /// c'est une valeur calculée par le serveur sur des tables M6 que ce poste ne
  /// détient pas. La figer localement la rendrait fausse à la première vente,
  /// sans que rien ne le signale — même refus que le solde client (PA-126) et
  /// que le total dénormalisé des réservations (PA-112). L'écran la lit en
  /// direct, et dit qu'elle manque quand le serveur est injoignable.
  ///
  /// ## Aucune suppression, aucune entrée de file
  ///
  /// Une boisson retirée de la carte au serveur reste ici : elle est peut-être
  /// citée par une ligne de panier locale, et sa suppression rendrait cette
  /// ligne illisible. Et aucune de ces tables n'est au registre
  /// `TABLES_SYNCHRONISABLES` : une opération y serait rejetée à chaque
  /// tentative, donc rien ne remonte.
  ///
  /// Un rayon `null` — serveur muet — laisse le rayon local **intact** : ce
  /// n'est pas « la carte est vide », c'est « on ne sait pas ».
  Future<int> alignerCatalogue({
    List<BoissonDistante>? boissons,
    List<CircuitDistant>? circuits,
    List<VehiculeDistant>? vehicules,
  }) async {
    var ecrits = 0;

    await transaction(() async {
      for (final b in boissons ?? const <BoissonDistante>[]) {
        await _ecrireBoisson(b);
        ecrits++;
      }

      for (final c in circuits ?? const <CircuitDistant>[]) {
        await attachedDatabase
            .into(attachedDatabase.circuitsLocal)
            .insertOnConflictUpdate(
              CircuitsLocalCompanion.insert(
                id: c.id,
                nom: c.nom,
                theme: c.theme,
                zone: c.zone,
                prix: c.prix,
                capaciteMax: c.capaciteMax,
              ),
            );
        ecrits++;
      }

      for (final v in vehicules ?? const <VehiculeDistant>[]) {
        await attachedDatabase
            .into(attachedDatabase.vehiculesLocal)
            .insertOnConflictUpdate(
              VehiculesLocalCompanion.insert(
                id: v.id,
                categorie: v.categorie,
                immatriculation: v.immatriculation,
                tarifJour: v.tarifJour,
                statut: v.statut,
              ),
            );
        ecrits++;
      }
    });

    return ecrits;
  }

  /// `cartes_boisson_local.article_id`, par boisson — id → article (PA-199).
  ///
  /// Répliqué (voir [alignerCatalogue]) mais absent de [ArticleVendable], qui
  /// n'en a pas l'usage. L'écran de carte en a besoin sans réseau : sans lui,
  /// il compterait toutes les boissons comme non rattachées. Une chaîne vide
  /// n'est pas un identifiant : elle est écartée.
  //
  // ⚠ Texte volontairement technique : ce fichier est lu par le comparateur
  // Blade × Flutter pour la page du point de vente, et une phrase d'écran
  // citée ici y « satisfaisait » un libellé non porté (mesuré le 11/09/2026).
  @override
  Future<Map<String, String>> liensDeStockDesBoissons() async {
    final lignes = await select(attachedDatabase.cartesBoissonLocal).get();
    return {
      for (final b in lignes)
        if (b.articleId.isNotEmpty) b.id: b.articleId,
    };
  }

  /// Les articles de stock auxquels une boisson peut se lier — ceux de
  /// `articles_local` en **suivi permanent** et non archivés, triés par libellé
  /// (`articlesDeStock()` de la PWA : un article en achat journalier n'est pas
  /// suivi, le rattacher ne décrémenterait rien). [terme] filtre sur le libellé,
  /// sans casse ni accents (la recherche du maître).
  Future<List<ArticleDeStock>> articlesDeStockLiables({
    String terme = '',
  }) async {
    final cherche = cleDeComparaison(terme);
    final lignes = await select(attachedDatabase.articlesLocal).get();
    final retenus =
        [
          for (final a in lignes)
            if (a.suivi == 'permanent' &&
                a.actif != false &&
                (cherche.isEmpty ||
                    cleDeComparaison(a.libelle).contains(cherche)))
              a,
        ]..sort(
          (a, b) => cleDeComparaison(
            a.libelle,
          ).compareTo(cleDeComparaison(b.libelle)),
        );
    return [
      for (final a in retenus)
        ArticleDeStock(
          id: a.id,
          libelle: a.libelle,
          uniteMesure: a.uniteMesure,
        ),
    ];
  }

  /// Un article de stock par identifiant, quel que soit son suivi — sert à
  /// NOMMER un lien déjà posé (colonne « Article de stock » de la carte).
  Future<ArticleDeStock?> articleDeStock(String id) async {
    final a = await (select(
      attachedDatabase.articlesLocal,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return a == null
        ? null
        : ArticleDeStock(
            id: a.id,
            libelle: a.libelle,
            uniteMesure: a.uniteMesure,
          );
  }

  /// Les références du catalogue dont la vente ne sortirait AUCUN stock — la
  /// lecture qui rend `stock_non_impacte` (« Articles sans lien au stock »,
  /// journal des ventes et ticket) : une boisson sans article de stock, un plat
  /// dont la fiche technique n'a aucun ingrédient. Clés de la forme `M5:<id>` /
  /// `M4:<id>` ([ReferenceCatalogue.toString]).
  ///
  /// ⚠ Écart nommé : le serveur écrit cette liste sur la vente AU MOMENT de la
  /// vente (`ventes.stock_non_impacte`) ; ce poste la relit du catalogue
  /// d'AUJOURD'HUI. Un lien posé après la vente la ferait disparaître d'ici.
  Future<Set<String>> referencesSansLienDeStock() async {
    final sans = <String>{};
    for (final b in await select(attachedDatabase.cartesBoissonLocal).get()) {
      if (b.articleId.isEmpty) sans.add('${ModuleVendable.m5Bar.code}:${b.id}');
    }
    final composees = {
      for (final i in await select(
        attachedDatabase.ingredientsRecetteLocal,
      ).get())
        i.recetteId,
    };
    for (final p in await select(attachedDatabase.platsLocal).get()) {
      if (!composees.contains(p.recetteId)) {
        sans.add('${ModuleVendable.m4Restaurant.code}:${p.id}');
      }
    }
    return sans;
  }

  /* ================================================================== */
  /* La SAISIE locale des boissons — 14/09/2026                          */
  /* ================================================================== */

  /// Écrit UNE boisson dans `cartes_boisson_local`.
  ///
  /// **Le même auteur, la même table, le même UPSERT** que [alignerCatalogue].
  /// C'est délibéré et c'est la moitié du livrable : PA-129 s'était refermée
  /// sur une descente serveur qui n'existe plus, et le poste doit désormais
  /// saisir son catalogue lui-même. Écrire la saisie ailleurs aurait fait un
  /// **second auteur** du référentiel — le défaut que `database/seeders/` a
  /// produit cinq fois, chaque auteur se croyant idempotent sans voir l'autre.
  ///
  /// L'identifiant fait foi : réenregistrer la même boisson la remplace, il
  /// n'en naît jamais une seconde.
  ///
  /// Depuis le lot F1 (15/10/2026), la saisie part aussi dans la file d'envoi,
  /// dans la MÊME transaction : `creation` (document complet) si la boisson
  /// n'existait pas, `modification` (les seuls champs changés) sinon.
  /// [alignerCatalogue] n'enfile RIEN : ce qu'il écrit vient du serveur (ou du
  /// jeu de démonstration), le renvoyer serait une boucle.
  Future<void> enregistrerBoisson(BoissonDistante boisson) {
    return transaction(() async {
      final avant = await (select(
        attachedDatabase.cartesBoissonLocal,
      )..where((c) => c.id.equals(boisson.id))).getSingleOrNull();
      await _ecrireBoisson(boisson);
      final apres = await (select(
        attachedDatabase.cartesBoissonLocal,
      )..where((c) => c.id.equals(boisson.id))).getSingle();
      await OperationsSyncDao(attachedDatabase).enfiler(
        table: TableSynchronisee.cartesBoisson,
        entiteId: boisson.id,
        type: avant == null
            ? TypeOperationSync.creation
            : TypeOperationSync.modification,
        payload: avant == null
            ? _chargeBoisson(apres)
            : champsModifies(_chargeBoisson(avant), _chargeBoisson(apres)),
      );
    });
  }

  /// Le document `cartes_boisson` du serveur, depuis la ligne locale (la
  /// chaîne vide « sans lien de stock » redevient `null`).
  static Map<String, Object?> _chargeBoisson(CartesBoissonLocalData b) =>
      chargeBoisson(
        libelle: b.libelle,
        articleId: b.articleId.isEmpty ? null : b.articleId,
        categorie: b.categorie,
        prixVenteFrancs: b.prixVente.round(),
        unitesVendables: b.unitesVendables,
      );

  /// Les boissons du catalogue local, triées par libellé.
  ///
  /// ⚠ **Le stock n'en fait pas partie, et n'en fera jamais partie.**
  /// `stockDisponible` et `stockVendable` repartent à `null` : ils étaient
  /// calculés par le serveur sur les tables M6, que ce poste ne détient pas
  /// (PA-134). `null` veut dire « aucun chiffre n'existe », et la carte le
  /// rend par « non consulté » ; un `0` s'y lirait « rupture », c'est-à-dire
  /// une bonne nouvelle affichée à la place d'une absence, sur l'écran même
  /// qui sert à commander (PA-129, PA-199).
  Future<List<BoissonDistante>> boissonsDuCatalogue() async {
    final lignes = await (select(
      attachedDatabase.cartesBoissonLocal,
    )..orderBy([(c) => OrderingTerm.asc(c.libelle)])).get();

    return lignes.map(_versBoisson).toList(growable: false);
  }

  /// Une boisson par identifiant, ou `null` si elle ne figure pas au catalogue.
  Future<BoissonDistante?> boissonDuCatalogue(String id) async {
    final ligne = await (select(
      attachedDatabase.cartesBoissonLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();

    return ligne == null ? null : _versBoisson(ligne);
  }

  /// Ce libellé est-il DÉJÀ porté par une autre boisson ?
  ///
  /// Un référentiel n'a qu'un seul auteur — et sur un poste où il se saisit à
  /// la main, il n'a pas non plus deux fois la même ligne. Deux « Béninoise
  /// 33 cl » au catalogue mettent deux entrées au point de vente, et le barman
  /// ne peut pas savoir laquelle décrémente quoi. Le maître nomme lui-même la
  /// règle voisine : « deux contenances = deux articles » — donc un libellé,
  /// un article.
  ///
  /// La comparaison ignore la casse et les espaces de bord : « Béninoise 33cl »
  /// et « béninoise 33cl  » désignent la même bouteille pour qui lit la carte.
  /// [sauf] exclut la boisson qu'on est en train de modifier, sans quoi elle se
  /// refuserait elle-même.
  Future<bool> libelleBoissonExiste(String libelle, {String? sauf}) async {
    final cherche = libelle.trim().toLowerCase();
    final lignes = await select(attachedDatabase.cartesBoissonLocal).get();

    return lignes.any(
      (b) => b.id != sauf && b.libelle.trim().toLowerCase() == cherche,
    );
  }

  Future<void> _ecrireBoisson(BoissonDistante b) => attachedDatabase
      .into(attachedDatabase.cartesBoissonLocal)
      .insertOnConflictUpdate(
        CartesBoissonLocalCompanion.insert(
          id: b.id,
          // La colonne est NOT NULL au schéma local ; une boisson sans
          // lien de stock porte une chaîne vide, qui se distingue d'un
          // identifiant et ne prétend pas en être un.
          articleId: b.articleId ?? '',
          libelle: b.libelle,
          categorie: b.categorie,
          prixVente: b.prixVente,
          // `absentIfNull` : une écriture qui ne connaît pas le
          // conditionnement (l'amorçage, une descente sans lui) ne EFFACE
          // jamais celui que le poste a saisi.
          unitesVendables: Value.absentIfNull(b.unitesVendables),
        ),
      );

  BoissonDistante _versBoisson(CartesBoissonLocalData b) => BoissonDistante(
    id: b.id,
    // La chaîne vide n'est pas un identifiant : elle redevient « aucun lien ».
    articleId: b.articleId.isEmpty ? null : b.articleId,
    libelle: b.libelle,
    categorie: b.categorie,
    prixVente: b.prixVente,
    // Jamais stocké, donc jamais relu — voir [boissonsDuCatalogue].
    stockDisponible: null,
    unitesVendables: b.unitesVendables,
  );

  /// Le rayon du restaurant : les plats de `plats_local`, au prix du jour.
  Future<RayonCatalogue> _rayonRestaurant() async {
    final plats = await _plats();
    return RayonCatalogue(
      module: ModuleVendable.m4Restaurant,
      articles: plats,
      // La raison n'accompagne que l'ABSENCE : un rayon garni n'a rien à
      // justifier.
      indisponibiliteLocale: plats.isEmpty ? motifRestaurantVide : null,
    );
  }

  Future<List<ArticleVendable>> _plats() async {
    final p = attachedDatabase.platsLocal;
    final m = attachedDatabase.menusLocal;
    final lignes = await select(
      p,
    ).join([innerJoin(m, m.id.equalsExp(p.menuId))]).get();

    // Les fiches qui portent au moins un ingrédient : celles dont la vente
    // ferait bouger un stock.
    final composees = {
      for (final i in await select(
        attachedDatabase.ingredientsRecetteLocal,
      ).get())
        i.recetteId,
    };

    // La marque « P » de la vue : la fiche du plat est PROVISOIRE (quantités
    // posées, jamais pesées) — lue de `recettes_local.composition_provisoire`.
    final provisoires = {
      for (final r in await select(attachedDatabase.recettesLocal).get())
        if (r.compositionProvisoire == true) r.id,
    };

    final articles = [
      for (final l in lignes)
        ArticleVendable(
          reference: ReferenceCatalogue(
            module: ModuleVendable.m4Restaurant,
            code: l.readTable(p).id,
          ),
          libelle: l.readTable(p).libelle,
          // Des francs entiers dans la colonne : aucune conversion, aucun
          // arrondi — le prix du catalogue est celui de la ligne.
          prix: l.readTable(p).prixVente,
          categorie: l.readTable(m).type,
          detail: composees.contains(l.readTable(p).recetteId)
              ? null
              : detailFicheVide,
          // Le point orange de la vue : un plat sans ingrédient ne décrémente
          // rien (`lien_stock` faux).
          sansLienStock: !composees.contains(l.readTable(p).recetteId),
          compositionProvisoire: provisoires.contains(l.readTable(p).recetteId),
        ),
    ];
    // Le même ordre que la carte : libellé sans accent, puis identifiant.
    articles.sort((a, b) {
      final c = cleDeComparaison(
        a.libelle,
      ).compareTo(cleDeComparaison(b.libelle));
      return c != 0 ? c : a.reference.code.compareTo(b.reference.code);
    });
    return articles;
  }

  Future<List<ArticleVendable>> _boissons() async {
    final lignes = await (select(
      attachedDatabase.cartesBoissonLocal,
    )..orderBy([(c) => OrderingTerm.asc(c.libelle)])).get();

    return lignes
        .map(
          (b) => ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m5Bar,
              code: b.id,
            ),
            libelle: b.libelle,
            // Le catalogue stocke le prix en `REAL` ; le domaine le manipule en
            // entier — le XOF n'a pas de sous-unité en circulation. La
            // conversion est faite ici, une fois, plutôt que d'imposer un
            // `double` au panier où il produirait un arrondi sur l'addition.
            prix: b.prixVente.round(),
            categorie: b.categorie,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ArticleVendable>> _circuits() async {
    final lignes = await (select(
      attachedDatabase.circuitsLocal,
    )..orderBy([(c) => OrderingTerm.asc(c.nom)])).get();

    return lignes
        .map(
          (c) => ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m9Tourisme,
              code: c.id,
            ),
            libelle: c.nom,
            prix: c.prix.round(),
            categorie: c.theme,
            detail: c.zone,
          ),
        )
        .toList(growable: false);
  }

  Future<List<ArticleVendable>> _vehicules() async {
    final lignes = await (select(
      attachedDatabase.vehiculesLocal,
    )..orderBy([(v) => OrderingTerm.asc(v.immatriculation)])).get();

    return lignes
        .map(
          (v) => ArticleVendable(
            reference: ReferenceCatalogue(
              module: ModuleVendable.m8Vehicules,
              code: v.id,
            ),
            libelle: '${v.categorie} ${v.immatriculation}',
            prix: v.tarifJour.round(),
            categorie: v.categorie,
            detail: 'par jour',
          ),
        )
        .toList(growable: false);
  }
}
