import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
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
  Future<IssueMouvement> ajouterMouvement({
    required String articleId,
    required String pointId,
    required TypeMouvement type,
    required int centiemes,
    required String motif,
    required String? auteurId,
    int? coutDixMilliemes,
    bool forcage = false,
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

      final dernier =
          await (selectOnly(attachedDatabase.mouvementsStockLocal)..addColumns([
                attachedDatabase.mouvementsStockLocal.ordre.max(),
              ]))
              .map(
                (r) =>
                    r.read(attachedDatabase.mouvementsStockLocal.ordre.max()),
              )
              .getSingle();

      final id = _uuid.v4();
      final instant = _maintenant();
      await into(attachedDatabase.mouvementsStockLocal).insert(
        MouvementsStockLocalCompanion.insert(
          id: id,
          articleId: articleId,
          pointId: pointId,
          typeMouvement: type.code,
          quantite: centiemes / echelleQuantite,
          motif: motif.trim(),
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
}
