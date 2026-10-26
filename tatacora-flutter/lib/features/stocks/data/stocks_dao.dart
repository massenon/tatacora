import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../achats/domain/entities/archivage_fournisseur.dart';
import '../../achats/domain/entities/commande_achat.dart' show StatutCommande;
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../domain/calcul_inventaire.dart';
import '../domain/calcul_stock.dart';
import '../domain/entities/etat_stock.dart';
import '../domain/entities/fiche_stock.dart';
import '../domain/entities/mouvement_stock.dart';
import '../domain/messages_stock.dart';

/// Un refus du DAO — une règle du référentiel que la base ne peut pas porter
/// seule (une clé inconnue, un article journalier…). Il porte une phrase écrite
/// pour l'exploitant, et le champ fautif quand il y en a un.
final class RefusStock implements Exception {
  const RefusStock(this.motif, {this.champ});

  final String motif;
  final String? champ;

  @override
  String toString() => 'RefusStock($motif)';
}

/// Ce qu'une tentative d'écriture de mouvement rend. La rupture n'est PAS un
/// refus (RG-06) : c'est une question posée à l'utilisateur.
sealed class IssueMouvement {
  const IssueMouvement();
}

final class MouvementPose extends IssueMouvement {
  const MouvementPose(this.mouvement);
  final MouvementStock mouvement;
}

final class RuptureConstatee extends IssueMouvement {
  const RuptureConstatee({required this.disponible, required this.demande});

  /// Centièmes : ce que le point détenait, et ce qui était demandé.
  final int disponible;
  final int demande;
}

/// Accès Drift à M6 — **local pur**, et UNIQUE point d'écriture des trois
/// tables de stock.
///
/// ## Aucun mixin généré
///
/// Comme `DepenseDao` : on passe par `attachedDatabase.<table>`, sans
/// `@DriftAccessor` ni `part`. Aucun mixin vide ne peut donc apparaître (le
/// piège nommé en tête de `panier_dao.dart`).
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend une classe de ligne Drift. Les `REAL` hérités de la
/// v1 (`quantite`, `seuil_alerte`) sont convertis en CENTIÈMES entiers ici,
/// UNE fois, et aucune somme ne se fait sur un `REAL`.
///
/// ## Rien ne part en file de synchronisation
///
/// `mouvements_stock` n'a jamais été au registre synchronisable, et le poste ne
/// parle plus à aucun serveur. Le défaut de `statutSync`
/// (`en_attente_synchronisation`) est un piège du schéma (PA-134) : ce DAO
/// écrit TOUJOURS `local`, et aucun écran ne lit la colonne.
///
/// ## Ce que l'écriture d'un mouvement garantit
///
///  * le contrôle de disponibilité (RG-06) et l'insertion se font dans la
///    MÊME transaction : deux sorties ne peuvent pas lire toutes deux un
///    disponible suffisant ;
///  * le mouvement porte son auteur (RG-15), son coût figé à l'ajout, et la
///    trace du forçage ;
///  * aucune écriture comptable : le poste tient une comptabilité depuis le
///    10/10/2026, mais un mouvement de stock n'est pas un mouvement d'argent
///    et sa valorisation comptable n'est pas portée (état du 12/10/2026).
class StocksDao extends DatabaseAccessor<AppDatabase> {
  StocksDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _maintenant;

  /// L'instant que ce DAO utilise — exposé pour que l'état et ses mouvements
  /// soient arrêtés au même moment.
  DateTime maintenant() => _maintenant();

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  Future<List<PointStockage>> points() async {
    final lignes =
        await (select(attachedDatabase.pointsStockageLocal)..orderBy([
              (p) => OrderingTerm.asc(p.libelle),
              (p) => OrderingTerm.asc(p.id),
            ]))
            .get();
    return [
      for (final p in lignes)
        PointStockage(id: p.id, libelle: p.libelle, type: p.type),
    ];
  }

  Future<Map<String, String>> libellesPoints() async => {
    for (final p in await points()) p.id: p.libelle,
  };

  Future<List<ArticleCalcul>> articles() async {
    final lignes = await select(attachedDatabase.articlesLocal).get();
    return [for (final a in lignes) _article(a)];
  }

  ArticleCalcul _article(ArticlesLocalData a) => ArticleCalcul(
    id: a.id,
    libelle: a.libelle,
    // `NOT NULL` au schéma v1 : « non renseignée » s'écrit chaîne vide.
    categorie: a.categorie.isEmpty ? null : a.categorie,
    uniteMesure: a.uniteMesure,
    seuilCentiemes: (a.seuilAlerte * echelleQuantite).round(),
    // Un code inconnu ne se replie JAMAIS sur `permanent` : il serait compté
    // dans les alarmes. La valeur est écrite par ce seul DAO, depuis le
    // registre fermé — un inconnu ne peut venir que d'un fichier corrompu.
    suivi: SuiviArticle.depuisCode(a.suivi) ?? SuiviArticle.permanent,
    pointStockageId: a.pointStockageId,
    // v35 : `null` (fichier ramené d'avant la colonne) ou `true` = actif ; seul
    // `false` archive. Jamais l'inverse : un `null` archiverait tout le parc.
    actif: a.actif != false,
  );

  /// Les mouvements, avec leur auteur lisible, dans l'ordre d'écriture.
  Future<List<MouvementCalcul>> mouvementsCalcul({String? articleId}) async {
    final m = attachedDatabase.mouvementsStockLocal;
    final u = attachedDatabase.utilisateursLocal;

    final requete = select(
      m,
    ).join([leftOuterJoin(u, u.id.equalsExp(m.utilisateurId))]);
    if (articleId != null) requete.where(m.articleId.equals(articleId));
    requete.orderBy([OrderingTerm.asc(m.ordre), OrderingTerm.asc(m.id)]);

    final lignes = await requete.get();
    final resultat = <MouvementCalcul>[];
    for (final l in lignes) {
      final r = l.readTable(m);
      final type = TypeMouvement.depuisCode(r.typeMouvement);
      // Un type inconnu n'est pas converti en `entree` : il fausserait le
      // stock sans rien dire. On refuse de calculer sur un fichier dont le
      // registre ne correspond plus.
      if (type == null) {
        throw StateError(
          'Type de mouvement inconnu en base : « ${r.typeMouvement} » '
          '(mouvement ${r.id}). Le stock ne peut pas être calculé.',
        );
      }
      resultat.add(
        MouvementCalcul(
          id: r.id,
          articleId: r.articleId,
          pointId: r.pointId,
          type: type,
          centiemes: (r.quantite * echelleQuantite).round(),
          ordre: r.ordre,
          date: r.dateMouvement,
          motif: r.motif,
          auteur: l.readTableOrNull(u)?.nom,
          coutDixMilliemes: r.coutUnitaireDixMilliemes,
          ruptureForcee: r.ruptureForcee,
        ),
      );
    }
    return resultat;
  }

  /// L'état consolidé, arrêté à l'instant du DAO.
  Future<EtatStock> etat({
    String? pointId,
    EtatStockFiltre filtre = EtatStockFiltre.tous,
  }) async {
    return calculerEtat(
      articles: await articles(),
      mouvements: await mouvementsCalcul(),
      maintenant: _maintenant(),
      libellesPoints: await libellesPoints(),
      pointId: pointId,
      filtre: filtre,
    );
  }

  /// Les articles du sélecteur de la fiche. `suivi` restreint le registre
  /// (`null` : tous). Le stock ne s'y calcule que si un point est demandé.
  Future<List<ArticleFiche>> articlesFiche({
    SuiviArticle? suivi,
    String? pointId,
  }) async {
    final tous = await articles();
    final mouvements = await mouvementsCalcul();
    final parArticle = <String, List<MouvementCalcul>>{};
    for (final m in mouvements) {
      parArticle.putIfAbsent(m.articleId, () => []).add(m);
    }

    final retenus =
        tous.where((a) => suivi == null || a.suivi == suivi).toList()..sort(
          (a, b) => a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase()),
        );

    return [
      for (final a in retenus)
        ArticleFiche(
          id: a.id,
          libelle: a.libelle,
          unite: a.uniteMesure,
          cmp: ecrireCout(coutMoyenPondereDe(parArticle[a.id] ?? const [])),
          stock: pointId == null
              ? null
              : ecrireCentiemes(
                  stockDe(parArticle[a.id] ?? const [], pointId: pointId),
                ),
        ),
    ];
  }

  /// La fiche d'un article, ou `null` si l'article n'existe pas.
  Future<FicheStock?> fiche({
    required String articleId,
    required DateTime debut,
    required DateTime fin,
    String? pointId,
  }) async {
    final article = (await articles())
        .where((a) => a.id == articleId)
        .firstOrNull;
    if (article == null) return null;

    final siens = await mouvementsCalcul(articleId: articleId);
    return calculerFiche(
      article: ArticleFiche(
        id: article.id,
        libelle: article.libelle,
        unite: article.uniteMesure,
        cmp: '',
      ),
      cmp: coutMoyenPondereDe(siens),
      mouvements: siens,
      debut: debut,
      fin: fin,
      pointId: pointId,
    );
  }

  /// La fiche de TOUS les articles (`FicheStockService::pourTousLesArticles`) :
  /// la fiche de chacun, par [calculerFiche], puis [consoliderFiches]. Les
  /// articles sont pris dans l'ordre alphabétique de leur libellé, comme le
  /// serveur (`orderBy('libelle')`).
  Future<FicheConsolidee> ficheConsolidee({
    required DateTime debut,
    required DateTime fin,
    String? pointId,
  }) async {
    final tous = [...await articles()]
      ..sort(
        (a, b) => a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase()),
      );
    final parArticle = <String, List<MouvementCalcul>>{};
    for (final m in await mouvementsCalcul()) {
      parArticle.putIfAbsent(m.articleId, () => []).add(m);
    }

    return consoliderFiches(
      [
        for (final a in tous)
          calculerFiche(
            article: ArticleFiche(
              id: a.id,
              libelle: a.libelle,
              unite: a.uniteMesure,
              cmp: '',
            ),
            cmp: coutMoyenPondereDe(parArticle[a.id] ?? const []),
            mouvements: parArticle[a.id] ?? const [],
            debut: debut,
            fin: fin,
            pointId: pointId,
          ),
      ],
      debut: debut,
      fin: fin,
      pointId: pointId,
    );
  }

  /// Le journal, du plus récent au plus ancien. [total] compte TOUT ce que le
  /// filtre retient, pas la page : une page pleine se lirait « c'est tout ».
  Future<({List<MouvementStock> mouvements, int total})> journal({
    String? articleId,
    String? pointId,
    TypeMouvement? type,
    int limite = 20,
  }) async {
    final m = attachedDatabase.mouvementsStockLocal;
    final a = attachedDatabase.articlesLocal;
    final p = attachedDatabase.pointsStockageLocal;
    final u = attachedDatabase.utilisateursLocal;

    final requete = select(m).join([
      innerJoin(a, a.id.equalsExp(m.articleId)),
      innerJoin(p, p.id.equalsExp(m.pointId)),
      leftOuterJoin(u, u.id.equalsExp(m.utilisateurId)),
    ]);
    if (articleId != null) requete.where(m.articleId.equals(articleId));
    if (pointId != null) requete.where(m.pointId.equals(pointId));
    if (type != null) requete.where(m.typeMouvement.equals(type.code));
    requete.orderBy([OrderingTerm.desc(m.ordre), OrderingTerm.desc(m.id)]);

    final toutes = await requete.get();
    final retenues = toutes.take(limite);

    return (
      mouvements: [
        for (final l in retenues)
          _mouvement(
            l.readTable(m),
            article: l.readTable(a),
            point: l.readTable(p),
            auteur: l.readTableOrNull(u)?.nom,
          ),
      ],
      total: toutes.length,
    );
  }

  MouvementStock _mouvement(
    MouvementsStockLocalData r, {
    required ArticlesLocalData article,
    required PointsStockageLocalData point,
    required String? auteur,
  }) {
    final type = TypeMouvement.depuisCode(r.typeMouvement);
    final centiemes = (r.quantite * echelleQuantite).round();
    return MouvementStock(
      id: r.id,
      articleId: r.articleId,
      articleLibelle: article.libelle,
      uniteMesure: article.uniteMesure,
      pointId: r.pointId,
      pointLibelle: point.libelle,
      typeCode: r.typeMouvement,
      quantite: ecrireCentiemes(centiemes),
      sens: (type?.ajouteAuStock ?? true) ? 'entree' : 'sortie',
      motif: r.motif,
      utilisateur: auteur,
      dateMouvement: r.dateMouvement.toIso8601String(),
      ruptureForcee: r.ruptureForcee,
      coutUnitaire: r.coutUnitaireDixMilliemes == null
          ? null
          : ecrireCout(r.coutUnitaireDixMilliemes!),
    );
  }

  /* ================================================================== */
  /* Écriture — seul auteur des trois tables                             */
  /* ================================================================== */

  Future<PointStockage> creerPoint({
    required String libelle,
    TypePoint? type,
    String? id,
  }) async {
    final nom = libelle.trim();
    if (nom.isEmpty) {
      throw const RefusStock(
        'Le libellé du point de stockage est obligatoire.',
        champ: 'libelle',
      );
    }

    return transaction(() async {
      final existants = await points();
      if (existants.any((p) => p.libelle.toLowerCase() == nom.toLowerCase())) {
        // Deux points homonymes se choisiraient au hasard dans un sélecteur, et
        // un mouvement serait imputé à l'autre sans que rien ne le dise.
        throw RefusStock(
          'Un point de stockage « $nom » existe déjà.',
          champ: 'libelle',
        );
      }
      final identifiant = id ?? _uuid.v4();
      await into(attachedDatabase.pointsStockageLocal).insert(
        PointsStockageLocalCompanion.insert(
          id: identifiant,
          libelle: nom,
          type: Value(type?.code),
        ),
      );
      // Lot F1 : la création part au serveur, dans CETTE transaction.
      await _file.enfiler(
        table: TableSynchronisee.pointsStockage,
        entiteId: identifiant,
        type: TypeOperationSync.creation,
        payload: chargePointStockage(libelle: nom, type: type?.code),
        horodatage: _maintenant(),
      );
      return PointStockage(id: identifiant, libelle: nom, type: type?.code);
    });
  }

  Future<void> _exigerPoint(String? pointId, {required String champ}) async {
    if (pointId == null) return;
    final trouve = await (select(
      attachedDatabase.pointsStockageLocal,
    )..where((p) => p.id.equals(pointId))).getSingleOrNull();
    if (trouve == null) {
      throw RefusStock(MessagesStock.pointInexistant, champ: champ);
    }
  }

  /// Crée l'article. Il naît SANS stock : la seule façon d'en poser est un
  /// mouvement `entree`. Le seuil d'un article journalier retombe à zéro.
  ///
  /// [ouverture] pose le stock d'ouverture comme un MOUVEMENT d'entrée, dans la
  /// MÊME transaction : si l'entrée est refusée, l'article n'est pas créé — un
  /// article sans son stock d'ouverture, alors que l'exploitant en a saisi un,
  /// serait un stock faux que rien ne signale.
  Future<void> creerArticle({
    required String id,
    required String libelle,
    required String? categorie,
    required String uniteMesure,
    required int seuilCentiemes,
    required SuiviArticle suivi,
    required String? pointStockageId,
    String? auteurId,
    ({int centiemes, int? coutDixMilliemes})? ouverture,
  }) async {
    await transaction(() async {
      final deja = await (select(
        attachedDatabase.articlesLocal,
      )..where((a) => a.id.equals(id))).getSingleOrNull();
      if (deja != null) {
        // Un second envoi du même identifiant est une anomalie qui doit se
        // voir, pas une mise à jour déguisée.
        throw const RefusStock(MessagesStock.identifiantDejaPris);
      }
      await _exigerPoint(pointStockageId, champ: 'point_stockage_id');

      await into(attachedDatabase.articlesLocal).insert(
        ArticlesLocalCompanion.insert(
          id: id,
          libelle: libelle.trim(),
          categorie: categorie ?? '',
          uniteMesure: uniteMesure.trim(),
          seuilAlerte: _seuil(seuilCentiemes, suivi),
          suivi: Value(suivi.code),
          pointStockageId: Value(pointStockageId),
        ),
      );
      // Lot F1 : la fiche part au serveur, dans CETTE transaction. Le stock
      // d'ouverture, lui, est un MOUVEMENT : il ne part pas (le serveur
      // interdit `stock_initial`, et `mouvements_stock` n'est pas au registre
      // synchronisable — point ouvert).
      await _file.enfiler(
        table: TableSynchronisee.articles,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: _chargeArticle(
          (await (select(
            attachedDatabase.articlesLocal,
          )..where((a) => a.id.equals(id))).getSingle()),
        ),
        horodatage: _maintenant(),
      );

      if (ouverture != null && suivi == SuiviArticle.permanent) {
        if (pointStockageId == null) {
          throw const RefusStock(
            'Choisissez le point de stockage qui reçoit le stock '
            'd’ouverture : une quantité sans destination n’est pas une '
            'entrée.',
            champ: 'point_stockage_id',
          );
        }
        await ajouterMouvement(
          articleId: id,
          pointId: pointStockageId,
          type: TypeMouvement.entree,
          centiemes: ouverture.centiemes,
          motif: MessagesStock.motifOuverture,
          auteurId: auteurId,
          coutDixMilliemes: ouverture.coutDixMilliemes,
        );
      }
    });
  }

  double _seuil(int centiemes, SuiviArticle suivi) =>
      suivi == SuiviArticle.journalier ? 0 : centiemes / echelleQuantite;

  /// Modifie le référentiel — jamais le stock. L'unité de mesure ne change
  /// plus dès qu'un mouvement existe : l'historique serait relu dans une autre
  /// unité (des « sacs » devenus des « kg »), et le stock changerait de sens
  /// sans qu'une seule ligne soit touchée.
  Future<void> modifierArticle({
    required String id,
    required String libelle,
    required String? categorie,
    required String uniteMesure,
    required int seuilCentiemes,
    required SuiviArticle suivi,
    required String? pointStockageId,
  }) async {
    await transaction(() async {
      final existant = await (select(
        attachedDatabase.articlesLocal,
      )..where((a) => a.id.equals(id))).getSingleOrNull();
      if (existant == null) {
        throw const RefusStock('Article introuvable.');
      }

      if (existant.uniteMesure != uniteMesure.trim()) {
        final nombre =
            await (selectOnly(attachedDatabase.mouvementsStockLocal)
                  ..addColumns([
                    attachedDatabase.mouvementsStockLocal.id.count(),
                  ])
                  ..where(
                    attachedDatabase.mouvementsStockLocal.articleId.equals(id),
                  ))
                .map(
                  (r) =>
                      r.read(attachedDatabase.mouvementsStockLocal.id.count()),
                )
                .getSingle();
        if ((nombre ?? 0) > 0) {
          throw RefusStock(
            'L’unité de mesure d’un article qui a des mouvements ne se '
            'modifie pas : l’historique serait relu dans une autre unité, et '
            'le stock changerait de sens sans qu’aucune ligne soit touchée '
            '($nombre mouvement(s) existent).',
            champ: 'unite_mesure',
          );
        }
      }

      await _exigerPoint(pointStockageId, champ: 'point_stockage_id');

      await (update(
        attachedDatabase.articlesLocal,
      )..where((a) => a.id.equals(id))).write(
        ArticlesLocalCompanion(
          libelle: Value(libelle.trim()),
          categorie: Value(categorie ?? ''),
          uniteMesure: Value(uniteMesure.trim()),
          seuilAlerte: Value(_seuil(seuilCentiemes, suivi)),
          suivi: Value(suivi.code),
          pointStockageId: Value(pointStockageId),
        ),
      );
      // Lot F1 : seuls les champs CHANGÉS partent (modification partielle du
      // serveur), relus de la base avant et après l'écriture.
      final apres = await (select(
        attachedDatabase.articlesLocal,
      )..where((a) => a.id.equals(id))).getSingle();
      await _file.enfiler(
        table: TableSynchronisee.articles,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: champsModifies(
          _chargeArticle(existant),
          _chargeArticle(apres),
        ),
        horodatage: _maintenant(),
      );
    });
  }

  /// Le document `articles` du serveur, depuis la ligne locale.
  Map<String, Object?> _chargeArticle(ArticlesLocalData a) => chargeArticle(
    libelle: a.libelle,
    categorie: a.categorie,
    uniteMesure: a.uniteMesure,
    seuilCentiemes: (a.seuilAlerte * echelleQuantite).round(),
    suivi: a.suivi,
    pointStockageId: a.pointStockageId,
  );

  /// La file d'envoi (lot F1). Son propre générateur d'UUID : celui de ce DAO
  /// est injecté par des tests qui en comptent les tirages.
  OperationsSyncDao get _file => OperationsSyncDao(attachedDatabase);

  /// Écrit UN mouvement — le seul chemin d'écriture de `mouvements_stock_local`.
  ///
  /// Dans une seule transaction : lecture du disponible, contrôle RG-06,
  /// insertion. Une rupture non confirmée n'écrit RIEN.
  ///
  /// [coutDixMilliemes] n'a de sens que pour une `entree` (le DAO le refuse
  /// ailleurs) : une sortie est valorisée au coût moyen pondéré du moment et ne
  /// le modifie pas. `null` sur une entrée = un transfert entre points, qui ne
  /// revalorise rien.
  ///
  /// [envoyer] (lot 10f) : le mouvement SAISI part au serveur, dans cette
  /// transaction. Faux pour celui qu'un DOCUMENT produit (l'entrée d'une
  /// réception) : le serveur l'écrit lui-même en appliquant le document.
  Future<IssueMouvement> ajouterMouvement({
    required String articleId,
    required String pointId,
    required TypeMouvement type,
    required int centiemes,
    required String motif,
    required String? auteurId,
    int? coutDixMilliemes,
    bool forcage = false,
    bool envoyer = true,
  }) async {
    if (auteurId == null) {
      // RG-15 : un mouvement sans auteur rend l'historique inopposable.
      throw const RefusStock(
        'L’auteur du mouvement est inconnu : aucune session n’est ouverte, '
        'et un mouvement sans « qui » ne peut pas être opposé à un inventaire.',
      );
    }
    if (!type.saisissable) {
      throw const RefusStock(
        MessagesStock.typeInconnu,
        champ: 'type_mouvement',
      );
    }
    if (centiemes <= 0) {
      throw const RefusStock(MessagesStock.quantitePositive, champ: 'quantite');
    }
    if (motif.trim().isEmpty) {
      throw const RefusStock(MessagesStock.motifObligatoire, champ: 'motif');
    }
    if (coutDixMilliemes != null && type != TypeMouvement.entree) {
      throw const RefusStock(
        MessagesStock.coutReserveEntree,
        champ: 'cout_unitaire',
      );
    }
    if (forcage && type == TypeMouvement.entree) {
      throw const RefusStock(MessagesStock.ruptureSurSortie);
    }
    if (coutDixMilliemes != null && coutDixMilliemes < 0) {
      throw const RefusStock(MessagesStock.coutNegatif, champ: 'cout_unitaire');
    }

    return transaction(() async {
      final article = await (select(
        attachedDatabase.articlesLocal,
      )..where((a) => a.id.equals(articleId))).getSingleOrNull();
      if (article == null) {
        throw const RefusStock(
          MessagesStock.articleInexistant,
          champ: 'article_id',
        );
      }
      // Le refus du maître (l.380-383) : un article journalier n'a pas de stock
      // à mouvementer. Il est porté ICI, geste manuel, et non dans un contrôle
      // d'écran seul : l'ouverture d'une fenêtre ne protège rien.
      if (SuiviArticle.depuisCode(article.suivi) == SuiviArticle.journalier) {
        throw RefusStock(
          MessagesStock.refusJournalier(article.libelle),
          champ: 'article_id',
        );
      }
      await _exigerPoint(pointId, champ: 'point_id');

      final siens = await mouvementsCalcul(articleId: articleId);

      var ruptureForcee = false;
      if (!type.ajouteAuStock) {
        final disponible = stockDe(siens, pointId: pointId);
        switch (controlerSortie(
          disponible: disponible,
          demande: centiemes,
          forcage: forcage,
        )) {
          case IssueSortie.couverte:
            break;
          case IssueSortie.ruptureAConfirmer:
            return RuptureConstatee(disponible: disponible, demande: centiemes);
          case IssueSortie.ruptureForcee:
            ruptureForcee = true;
        }
      }

      final ecrit = await _inserer(
        articleId: articleId,
        pointId: pointId,
        typeCode: type.code,
        centiemes: centiemes,
        motif: motif.trim(),
        auteurId: auteurId,
        coutDixMilliemes: coutDixMilliemes,
        ruptureForcee: ruptureForcee,
        envoyer: envoyer,
      );
      final id = ecrit.id;
      final instant = ecrit.instant;

      final point = await (select(
        attachedDatabase.pointsStockageLocal,
      )..where((p) => p.id.equals(pointId))).getSingle();
      final auteur = await (select(
        attachedDatabase.utilisateursLocal,
      )..where((u) => u.id.equals(auteurId))).getSingleOrNull();

      return MouvementPose(
        MouvementStock(
          id: id,
          articleId: articleId,
          articleLibelle: article.libelle,
          uniteMesure: article.uniteMesure,
          pointId: pointId,
          pointLibelle: point.libelle,
          typeCode: type.code,
          quantite: ecrireCentiemes(centiemes),
          sens: type.ajouteAuStock ? 'entree' : 'sortie',
          motif: motif.trim(),
          utilisateur: auteur?.nom,
          dateMouvement: instant.toIso8601String(),
          ruptureForcee: ruptureForcee,
          coutUnitaire: coutDixMilliemes == null
              ? null
              : ecrireCout(coutDixMilliemes),
        ),
      );
    });
  }

  /* ================================================================== */
  /* L'unique INSERT de mouvement                                        */
  /* ================================================================== */

  /// Écrit la ligne d'UN mouvement et l'enfile (si [envoyer]) — le SEUL
  /// `INSERT` de `mouvements_stock_local` : [ajouterMouvement] (geste saisi) et
  /// [cloturerInventaire] (régularisation) y passent, aucun ne recopie l'autre.
  /// À appeler DANS une transaction (la file l'exige).
  ///
  /// [ruptureForcee] n'est vrai que pour une sortie ou une perte qui dépasse le
  /// disponible et que quelqu'un a assumée — ou, pour une régularisation, que
  /// le constaté impose : un inventaire constate le réel, il ne le discute pas.
  Future<({String id, DateTime instant})> _inserer({
    required String articleId,
    required String pointId,
    required String typeCode,
    required int centiemes,
    required String motif,
    required String auteurId,
    required int? coutDixMilliemes,
    required bool ruptureForcee,
    required bool envoyer,
  }) async {
    final dernier =
        await (selectOnly(attachedDatabase.mouvementsStockLocal)
              ..addColumns([attachedDatabase.mouvementsStockLocal.ordre.max()]))
            .map(
              (r) => r.read(attachedDatabase.mouvementsStockLocal.ordre.max()),
            )
            .getSingle();

    final id = _uuid.v4();
    final instant = _maintenant();
    await into(attachedDatabase.mouvementsStockLocal).insert(
      MouvementsStockLocalCompanion.insert(
        id: id,
        articleId: articleId,
        pointId: pointId,
        typeMouvement: typeCode,
        quantite: centiemes / echelleQuantite,
        motif: motif,
        dateMouvement: instant,
        // ⚠ Jamais le défaut du schéma (`en_attente_synchronisation`) : il
        // décrirait une attente sans fin (PA-134).
        statutSync: const Value('local'),
        coutUnitaireDixMilliemes: Value(coutDixMilliemes),
        utilisateurId: Value(auteurId),
        ruptureForcee: Value(ruptureForcee),
        ordre: Value((dernier ?? 0) + 1),
      ),
    );
    if (envoyer) {
      await _file.enfiler(
        table: TableSynchronisee.mouvementsStock,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeMouvementStock(
          articleId: articleId,
          pointId: pointId,
          type: typeCode,
          centiemes: centiemes,
          motif: motif,
          coutDixMilliemes: coutDixMilliemes,
          ruptureForcee: ruptureForcee,
          le: instant,
        ),
        horodatage: instant,
      );
    }
    return (id: id, instant: instant);
  }

  /* ================================================================== */
  /* L'INVENTAIRE physique (EF-M6-05)                                    */
  /* ================================================================== */

  /// La feuille de comptage d'un inventaire sur [pointId] : tous les articles,
  /// comptés (théorique figé) ou non.
  Future<FeuilleComptage> feuilleDeComptage({
    required String pointId,
    required Map<String, ComptageBrouillon> comptages,
  }) async => composerFeuille(
    articles: await articles(),
    mouvements: await mouvementsCalcul(),
    pointId: pointId,
    comptages: comptages,
  );

  /// Le nombre d'articles à compter pour un inventaire sur [pointId] : tout le
  /// référentiel (`articlesNonComptes` du serveur, qui ne filtre rien).
  Future<int> nombreArticlesACompter() async => (await articles()).length;

  /// Fige le comptage d'UN article : son théorique AU POINT à cet instant, et
  /// ce qui a été trouvé en rayon (`InventaireService::compter`). Une quantité
  /// négative est refusée, avec la phrase du serveur.
  Future<ComptageBrouillon> figerComptage({
    required String articleId,
    required String pointId,
    required int constateCentiemes,
  }) async {
    if (constateCentiemes < 0) {
      throw const RefusStock(MessagesStock.quantiteNegative, champ: 'quantite');
    }
    final article = await (select(
      attachedDatabase.articlesLocal,
    )..where((a) => a.id.equals(articleId))).getSingleOrNull();
    if (article == null) {
      throw const RefusStock(
        MessagesStock.articleInexistant,
        champ: 'article_id',
      );
    }
    await _exigerPoint(pointId, champ: 'point_id');
    final siens = await mouvementsCalcul(articleId: articleId);
    return ComptageBrouillon(
      theoriqueCentiemes: stockDe(siens, pointId: pointId),
      constateCentiemes: constateCentiemes,
    );
  }

  /// CLÔTURE l'inventaire : l'en-tête, ses lignes comptées et les mouvements
  /// de régularisation s'écrivent ENSEMBLE, dans UNE transaction, et sont
  /// enfilés dans cet ordre (l'inventaire d'abord, puis ses mouvements). Un
  /// refus n'écrit RIEN.
  ///
  /// Comme `InventaireService::cloturer` : l'excédent est une entrée
  /// `inventaire` NON valorisée, le manquant une `perte` ; une ligne sans écart
  /// ne produit rien. Un inventaire qui laisse des articles non comptés est
  /// refusé SAUF [partielAutorise] — la clôture partielle se demande
  /// explicitement (la modale « Inventaire incomplet »).
  Future<BilanCloture> cloturerInventaire({
    required String pointId,
    required DateTime date,
    required Map<String, ComptageBrouillon> comptages,
    required String? auteurId,
    bool partielAutorise = false,
  }) async {
    if (auteurId == null) {
      // RG-15 : un inventaire sans auteur ne peut pas être opposé.
      throw const RefusStock(
        'L’auteur de l’inventaire est inconnu : aucune session n’est '
        'ouverte, et un inventaire sans « qui » ne peut pas être opposé.',
      );
    }

    return transaction(() async {
      await _exigerPoint(pointId, champ: 'point_id');

      final tous = await articles();
      final connus = {for (final a in tous) a.id: a};
      for (final id in comptages.keys) {
        if (!connus.containsKey(id)) {
          throw const RefusStock(
            MessagesStock.articleInexistant,
            champ: 'article_id',
          );
        }
      }
      if (comptages.values.any((c) => c.constateCentiemes < 0)) {
        throw const RefusStock(MessagesStock.quantiteNegative);
      }
      final nonComptes = tous.length - comptages.length;
      if (!partielAutorise && nonComptes > 0) {
        throw RefusStock(MessagesStock.inventaireIncomplet(nonComptes));
      }

      // L'ordre de la feuille : par libellé (le serveur lit `lignes()` par
      // article du point) — stable, donc les mouvements partent toujours dans
      // le même ordre.
      final lignes = comptages.entries.toList()
        ..sort((a, b) {
          final x = connus[a.key]!;
          final y = connus[b.key]!;
          final c = x.libelle.toLowerCase().compareTo(y.libelle.toLowerCase());
          return c != 0 ? c : x.id.compareTo(y.id);
        });

      final inventaireId = _uuid.v4();
      final jour = DateTime(date.year, date.month, date.day);
      final instant = _maintenant();
      final enregistrees = [
        for (final e in lignes) (id: _uuid.v4(), articleId: e.key, c: e.value),
      ];

      await into(attachedDatabase.inventairesLocal).insert(
        InventairesLocalCompanion.insert(
          id: inventaireId,
          pointId: pointId,
          dateInventaire: jourIso(jour),
          utilisateurId: Value(auteurId),
        ),
      );
      for (final l in enregistrees) {
        await into(attachedDatabase.lignesInventaireLocal).insert(
          LignesInventaireLocalCompanion.insert(
            id: l.id,
            inventaireId: inventaireId,
            articleId: l.articleId,
            quantiteTheoriqueCentiemes: l.c.theoriqueCentiemes,
            quantiteConstateeCentiemes: l.c.constateCentiemes,
            ecartCentiemes: l.c.ecartCentiemes,
          ),
        );
      }
      // L'inventaire PUIS ses mouvements : le serveur reçoit le document avant
      // la régularisation qui le cite.
      await _file.enfiler(
        table: TableSynchronisee.inventaires,
        entiteId: inventaireId,
        type: TypeOperationSync.creation,
        payload: chargeInventaire(
          pointId: pointId,
          date: jour,
          lignes: [
            for (final l in enregistrees)
              (
                id: l.id,
                articleId: l.articleId,
                theoriqueCentiemes: l.c.theoriqueCentiemes,
                constateCentiemes: l.c.constateCentiemes,
                ecartCentiemes: l.c.ecartCentiemes,
              ),
          ],
        ),
        horodatage: instant,
      );

      final parArticle = <String, List<MouvementCalcul>>{};
      for (final m in await mouvementsCalcul()) {
        parArticle.putIfAbsent(m.articleId, () => []).add(m);
      }

      var regularisations = 0;
      var manquants = 0;
      var excedents = 0;
      var sansCout = 0;
      for (final r in regularisationsDe([
        for (final l in enregistrees)
          (articleId: l.articleId, ecartCentiemes: l.c.ecartCentiemes),
      ])) {
        final siens = parArticle[r.articleId] ?? const <MouvementCalcul>[];
        final excedent = r.type == TypeMouvementRegularisation.excedent;
        await _inserer(
          articleId: r.articleId,
          pointId: pointId,
          typeCode: excedent
              ? TypeMouvement.inventaire.code
              : TypeMouvement.perte.code,
          centiemes: r.centiemes,
          motif: MessagesStock.motifRegularisation(
            inventaire: inventaireId,
            ecart: ecrireCentiemes(r.ecartCentiemes),
          ),
          auteurId: auteurId,
          coutDixMilliemes: null,
          // Un inventaire constate le réel : un manquant qui dépasse le
          // disponible d'aujourd'hui (une vente est passée depuis le
          // comptage) est écrit quand même, et tracé comme forcé.
          ruptureForcee:
              !excedent && stockDe(siens, pointId: pointId) < r.centiemes,
          envoyer: true,
        );
        regularisations++;
        final valeur = valoriserEcart(siens, r.ecartCentiemes);
        if (valeur == null) {
          sansCout++;
        } else if (excedent) {
          excedents += valeur;
        } else {
          manquants += valeur;
        }
      }

      return BilanCloture(
        inventaireId: inventaireId,
        regularisations: regularisations,
        manquantsFrancs: manquants,
        excedentsFrancs: excedents,
        ecartsSansCout: sansCout,
      );
    });
  }

  /// L'historique : les inventaires enregistrés sur ce poste (clôturés ici, ou
  /// descendus d'un autre poste), du plus récent au plus ancien — la limite est
  /// celle de la vue (`PLAFOND_HISTORIQUE`, 50).
  Future<List<InventaireClos>> inventairesClos({int limite = 50}) async {
    final i = attachedDatabase.inventairesLocal;
    final p = attachedDatabase.pointsStockageLocal;
    final u = attachedDatabase.utilisateursLocal;

    final requete = select(i).join([
      leftOuterJoin(p, p.id.equalsExp(i.pointId)),
      leftOuterJoin(u, u.id.equalsExp(i.utilisateurId)),
    ]);
    requete.orderBy([
      OrderingTerm.desc(i.dateInventaire),
      OrderingTerm.desc(i.id),
    ]);
    requete.limit(limite);
    final lignes = await requete.get();

    final resultat = <InventaireClos>[];
    for (final l in lignes) {
      final inv = l.readTable(i);
      final siennes = await (select(
        attachedDatabase.lignesInventaireLocal,
      )..where((x) => x.inventaireId.equals(inv.id))).get();
      resultat.add(
        InventaireClos(
          id: inv.id,
          date: inv.dateInventaire,
          pointId: inv.pointId,
          pointLibelle: l.readTableOrNull(p)?.libelle,
          articles: siennes.length,
          regularises: siennes.where((x) => x.ecartCentiemes != 0).length,
          par: l.readTableOrNull(u)?.login,
        ),
      );
    }
    return resultat;
  }

  /// La date du DERNIER inventaire enregistré de chaque point (`AAAA-MM-JJ`).
  /// Le serveur dit « dernier inventaire », tous statuts confondus (PA-150) :
  /// ici, ce sont les inventaires CLÔTURÉS — un comptage en cours n'est pas en
  /// base.
  Future<Map<String, String>> dernierInventaireParPoint() async {
    final i = attachedDatabase.inventairesLocal;
    final lignes =
        await (select(i)..orderBy([
              (x) => OrderingTerm.desc(x.dateInventaire),
              (x) => OrderingTerm.desc(x.id),
            ]))
            .get();
    final parPoint = <String, String>{};
    for (final l in lignes) {
      parPoint.putIfAbsent(l.pointId, () => l.dateInventaire);
    }
    return parPoint;
  }

  /* ================================================================== */
  /* L'ARCHIVAGE d'un article — « supprimer = archiver » (03/09/2026)     */
  /* ================================================================== */

  /// Les VERROUS de l'article — `ReferentielArticleService::verrous` : les
  /// raisons, lisibles, de refuser l'archivage. Vide : archivable.
  ///
  ///  1. du stock reste au magasin (tous points confondus, strictement positif) ;
  ///  2. une commande d'achat EN COURS le porte (les lignes de commande dont la
  ///     commande n'est ni réceptionnée ni clôturée — un statut inconnu
  ///     engage) ;
  ///  3. il est vendu à la carte (les boissons du bar) ;
  ///  4. il entre dans une recette.
  ///
  /// ⚠ Écart nommé : le serveur compte aussi `plats.article_id` (le plat « lié
  /// au stock »). Ce lien n'existe pas sur ce poste — « Lier au stock » n'y est
  /// pas porté, `plats_local` n'a pas de colonne d'article — : le verrou ne
  /// peut donc pas être rejoué ici. S'il tombe au serveur, l'archivage y est
  /// REFUSÉ avec sa phrase (écran « À traiter »), et l'article y reste actif.
  Future<List<String>> verrousArticle(String articleId) async {
    final motifs = <String>[];

    final stock = stockDe(await mouvementsCalcul(articleId: articleId));
    if (stock > 0) {
      motifs.add(MessagesStock.verrouStock(ecrireCentiemes(stock)));
    }

    final l = attachedDatabase.lignesCommandeAchatLocal;
    final c = attachedDatabase.commandesAchatLocal;
    final lignesEnCours =
        await (select(l).join([innerJoin(c, c.id.equalsExp(l.commandeId))])
              ..where(
                l.articleId.equals(articleId) &
                    c.statut.isNotIn([
                      StatutCommande.receptionnee.code,
                      StatutCommande.cloturee.code,
                    ]),
              ))
            .get();
    if (lignesEnCours.isNotEmpty) {
      motifs.add(MessagesStock.verrouCommande(lignesEnCours.length));
    }

    final boissons = await (select(
      attachedDatabase.cartesBoissonLocal,
    )..where((b) => b.articleId.equals(articleId))).get();
    if (boissons.isNotEmpty) {
      motifs.add(MessagesStock.verrouCarte(boissons.length));
    }

    final recettes = await (select(
      attachedDatabase.ingredientsRecetteLocal,
    )..where((r) => r.articleId.equals(articleId))).get();
    if (recettes.isNotEmpty) {
      motifs.add(MessagesStock.verrouRecette(recettes.length));
    }

    return motifs;
  }

  /// `Stocks::confirmerArchivageArticle` : compose le lot que la modale
  /// présente, pour les [ids] visés. Seuls les articles ACTIFS entrent dans le
  /// lot, triés par libellé ; chacun engagé porte son motif « [libellé] —
  /// [verrous] ». Un lot vide est BLOQUÉ (sans motif si la sélection ne portait
  /// que des articles déjà archivés).
  Future<LotArchivage> composerLotArchivage(List<String> ids) async {
    final actifs =
        [
          for (final a in await (select(
            attachedDatabase.articlesLocal,
          )..where((x) => x.id.isIn(ids))).get())
            if (a.actif != false) a,
        ]..sort(
          (a, b) => a.libelle.toLowerCase().compareTo(b.libelle.toLowerCase()),
        );

    final retenus = <String>[];
    final motifs = <String>[];
    final noms = <String>[];
    var conserves = 0;
    for (final a in actifs) {
      noms.add(a.libelle);
      final verrous = await verrousArticle(a.id);
      if (verrous.isEmpty) {
        retenus.add(a.id);
        continue;
      }
      conserves++;
      motifs.add('${a.libelle} — ${verrous.join(' ')}');
    }

    return LotArchivage(
      ids: retenus,
      motifs: motifs,
      conserves: conserves,
      bloque: retenus.isEmpty,
      libelle: noms.length == 1 ? noms.first : '',
    );
  }

  /// `ReferentielArticleService::archiver` : `actif = false`, jamais un
  /// `delete()` (chaque mouvement cite l'article). Les verrous sont RECONTRÔLÉS
  /// au moment d'agir — entre l'ouverture de la modale et le clic, une entrée
  /// de stock ou une commande a pu naître —, dans la MÊME transaction que
  /// l'écriture. Le refus porte les motifs, joints par une espace, comme le
  /// serveur. Déjà archivé : rien ne change.
  Future<void> archiverArticle(String id) async {
    await transaction(() async {
      final a = await (select(
        attachedDatabase.articlesLocal,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (a == null) {
        throw const RefusStock(MessagesStock.articleInexistant);
      }
      if (a.actif == false) return;
      final verrous = await verrousArticle(id);
      if (verrous.isNotEmpty) throw RefusStock(verrous.join(' '));

      await (update(attachedDatabase.articlesLocal)
            ..where((x) => x.id.equals(id)))
          .write(const ArticlesLocalCompanion(actif: Value(false)));
      // Le serveur l'applique sous SES verrous et la règle de droits
      // d'archivage (`DroitArchivageService`, M6).
      await _file.enfiler(
        table: TableSynchronisee.articles,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: chargeArchivageArticle(actif: false),
        horodatage: _maintenant(),
      );
    });
  }

  /// `Stocks::archiverArticles` : archive chaque article du lot par
  /// [archiverArticle], et rend le nombre archivé ET le DERNIER refus. Un refus
  /// d'un article devenu engagé n'empêche PAS les autres archivages du lot.
  Future<ResultatArchivage> archiverLot(List<String> ids) async {
    final fiches = await (select(
      attachedDatabase.articlesLocal,
    )..where((a) => a.id.isIn(ids))).get();

    var archives = 0;
    String? refus;
    for (final a in fiches) {
      try {
        await archiverArticle(a.id);
        archives++;
      } on RefusStock catch (e) {
        refus = e.motif;
      }
    }
    return ResultatArchivage(archives: archives, refus: refus);
  }

  /// `ReferentielArticleService::restaurer` : `actif = true`. Déjà actif : rien
  /// ne change et rien ne part. Restaurer n'est PAS derrière la bascule :
  /// fermer la bascule pendant qu'un article est aux archives ne doit jamais
  /// l'y enfermer (« reste restaurable » serait une promesse que rien ne
  /// tient). Rend le libellé de l'article restauré.
  Future<String> restaurerArticle(String id) async {
    return transaction(() async {
      final a = await (select(
        attachedDatabase.articlesLocal,
      )..where((x) => x.id.equals(id))).getSingleOrNull();
      if (a == null) {
        throw const RefusStock(MessagesStock.articleInexistant);
      }
      if (a.actif == false) {
        await (update(attachedDatabase.articlesLocal)
              ..where((x) => x.id.equals(id)))
            .write(const ArticlesLocalCompanion(actif: Value(true)));
        await _file.enfiler(
          table: TableSynchronisee.articles,
          entiteId: id,
          type: TypeOperationSync.modification,
          payload: chargeArchivageArticle(actif: true),
          horodatage: _maintenant(),
        );
      }
      return a.libelle;
    });
  }
}
