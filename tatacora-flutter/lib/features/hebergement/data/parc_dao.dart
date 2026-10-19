import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
// Les classes de tables doivent etre dans la portee du fichier : `@DriftAccessor`
// les resout par leur type, et un import de `app_database.dart` seul ne les
// reexporte pas. Sans ces lignes, le mixin genere est VIDE — sans erreur de
// generation, ce qui rend le diagnostic trompeur (lecon `reservation_dao.dart`).
import '../../../core/database/tables/hebergement_tables.dart';
import '../domain/entities/categorie_hebergement.dart';
import '../domain/refus_parc.dart';

import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';

part 'parc_dao.g.dart';

/// Accès Drift au **parc d'hébergement** — catégories et unités.
///
/// Vue Blade maîtresse (PA-183) : pwa/hebergement/hebergement.blade.php
///
/// ## Pourquoi ce DAO existe (14/09/2026)
///
/// Le parc **descendait du serveur** : `ReservationDao.alignerParc` en était
/// l'unique auteur, alimenté par `GET /hebergement/parc` (PA-128). Le poste est
/// passé **zéro réseau** — le client HTTP a disparu, et avec lui le seul chemin
/// par lequel une catégorie ou une unité entrait en base. `parc_dto.dart` le
/// nomme sans détour : « PA-128 n'est pas refermée, elle est déplacée ». Sur un
/// poste neuf, aucune réservation n'était possible et le plan d'hébergement
/// restait vide.
///
/// Décision du Product Owner du 14/09/2026 : **le parc se saisit sur le poste**.
/// Ce DAO est ce chemin-là.
///
/// ## Deux auteurs, et ils ne se marchent pas dessus
///
/// `ReservationDao.alignerParc` **reste** l'auteur du parc venu d'ailleurs —
/// c'est lui qu'emprunte le jeu de démonstration (`core/dev/mode_demo.dart`), et
/// il écrit en `insertOnConflictUpdate` par identifiant. Ce DAO-ci est l'auteur
/// du parc **saisi au comptoir** : il alloue ses propres UUID et refuse les
/// doublons de libellé et de code. Les deux n'écrivent jamais la même ligne, et
/// aucun ne recopie la logique de l'autre — c'est la règle « UN SEUL AUTEUR »
/// appliquée par ORIGINE de la donnée, pas par table.
///
/// ## Le DAO ne parle qu'entités
///
/// Aucune méthode ne rend un `UnitesHebergementLocalData`. La forme des tables
/// ne franchit pas cette frontière : sans quoi renommer une colonne casserait un
/// widget, et la couche présentation saurait qu'une base existe.
///
/// ## Aucune entrée n'est mise en file de synchronisation
///
/// `unites_hebergement` n'a jamais été au registre `TABLES_SYNCHRONISABLES`
/// (PA-118), et il n'y a de toute façon plus ni file ni serveur à joindre.
/// Annoncer « en attente de synchronisation » sur une unité qui ne partira
/// jamais serait l'indicateur qui affirme un état qu'il n'a pas vérifié
/// (PA-59/60/61). L'écran dit « enregistré sur ce poste ».
///
/// ## Aucune suppression — on archive
///
/// `BasePolicy::delete()` rend `false` pour les vingt policies du serveur, et le
/// « D » de CRUD n'existe nulle part dans ce dépôt. [archiver] pose
/// `hors_service`, le seul état qui retire l'unité de la vente **sans rien
/// effacer**, et [restaurer] est son pendant — sans lui, « reste restaurable »
/// serait une promesse que rien ne tient (PA-59/60/61).
///
/// @see EF-M1-01 Référentiel des unités d'hébergement
/// @see RG-02 La disponibilité est CALCULÉE, jamais lue dans un statut
@DriftAccessor(
  tables: [
    CategoriesHebergementLocal,
    UnitesHebergementLocal,
    ReservationsLocal,
  ],
)
class ParcDao extends DatabaseAccessor<AppDatabase> with _$ParcDaoMixin {
  ParcDao(super.db, {Uuid? uuid, DateTime Function()? maintenant})
    : _uuid = uuid ?? const Uuid(),
      _maintenant = maintenant ?? DateTime.now;

  final Uuid _uuid;

  /// Injectable : le verrou d'archivage compare au JOUR COURANT, et un test qui
  /// dépend de l'horloge réelle bascule à minuit.
  final DateTime Function() _maintenant;

  /* ================================================================== */
  /* Lectures                                                            */
  /* ================================================================== */

  /// Les catégories, triées par libellé — l'ordre de la vue (`orderBy('libelle')`).
  ///
  /// Le tri se départage par identifiant : deux libellés identiques ne peuvent
  /// pas exister ([creerCategorie] les refuse), mais un référentiel descendu
  /// avant cette garde pourrait en porter, et la liste changerait alors d'ordre
  /// à chaque rafraîchissement sans qu'aucune donnée n'ait bougé.
  Future<List<CategorieHebergement>> categories() async {
    final lignes =
        await (select(categoriesHebergementLocal)..orderBy([
              (c) => OrderingTerm.asc(c.libelle),
              (c) => OrderingTerm.asc(c.id),
            ]))
            .get();

    return lignes.map(_versCategorie).toList(growable: false);
  }

  Future<CategorieHebergement?> categorieParId(String id) async {
    final ligne = await (select(
      categoriesHebergementLocal,
    )..where((c) => c.id.equals(id))).getSingleOrNull();

    return ligne == null ? null : _versCategorie(ligne);
  }

  /// Les réservations qui ENGAGENT l'unité — le verrou de la vue.
  ///
  /// Le prédicat est celui de `ParcHebergementService::engagements()`, au
  /// caractère près : réservation **non annulée** dont le **départ n'est pas
  /// passé**, triée par arrivée. Une réservation terminée n'engage plus rien —
  /// elle reste lisible puisque l'archivage n'efface pas l'unité.
  ///
  /// ⚠ La comparaison porte sur le JOUR, pas sur l'instant : `date_depart` est
  /// stockée à minuit UTC (`PeriodeSejour`), et comparer à `DateTime.now()`
  /// ferait disparaître du verrou, dès 00 h 01, une réservation qui s'achève
  /// aujourd'hui.
  Future<List<EngagementUnite>> engagements(String uniteId) async {
    final aujourdHui = _jour(_maintenant());

    final lignes =
        await (select(reservationsLocal)
              ..where(
                (r) =>
                    r.uniteId.equals(uniteId) &
                    r.statut.equals('annulee').not() &
                    r.dateDepart.isBiggerOrEqualValue(aujourdHui),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.dateArrivee)]))
            .get();

    return lignes
        .map(
          (r) => EngagementUnite(arrivee: r.dateArrivee, depart: r.dateDepart),
        )
        .toList(growable: false);
  }

  /* ================================================================== */
  /* Écritures — catégories                                              */
  /* ================================================================== */

  /// Crée une catégorie, avec son tarif RÉEL et sa capacité.
  ///
  /// La vue refuse explicitement un tarif d'attente : « la catégorie naît AVEC
  /// son tarif réel et sa capacité — jamais un zéro d'attente qui se lirait
  /// comme une nuit gratuite ».
  Future<CategorieHebergement> creerCategorie({
    required String libelle,
    required int capaciteMax,
    required int tarifBase,
  }) async {
    final propre = libelle.trim();
    _exigerCategorieValide(
      libelle: propre,
      capaciteMax: capaciteMax,
      tarifBase: tarifBase,
    );

    final id = _uuid.v4();

    await transaction(() async {
      await _exigerLibelleLibre(propre);

      await into(categoriesHebergementLocal).insert(
        CategoriesHebergementLocalCompanion.insert(
          id: id,
          libelle: propre,
          capaciteMax: capaciteMax,
          // Le domaine compte en entiers, le schéma stocke un `REAL` : la
          // conversion vit ICI, au même endroit que celle du sens inverse.
          tarifBase: tarifBase.toDouble(),
        ),
      );
      // Lot F1 : la création part au serveur, dans CETTE transaction.
      await _file.enfiler(
        table: TableSynchronisee.categoriesHebergement,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeCategorieHebergement(
          libelle: propre,
          tarifBaseFrancs: tarifBase,
          capaciteMax: capaciteMax,
        ),
      );
    });

    return (await categorieParId(id))!;
  }

  /// Met à jour une catégorie.
  ///
  /// ⚠ **Le tarif d'une réservation déjà prise ne bouge pas.** `tarif_nuit` est
  /// figé sur la réservation (PA-55) : changer la grille ici ne réécrit aucun
  /// montant passé, et c'est exactement ce qu'on attend — le catalogue dit ce
  /// qu'on vend aujourd'hui, la réservation dit ce qui a été vendu.
  Future<CategorieHebergement> modifierCategorie(
    String id, {
    required String libelle,
    required int capaciteMax,
    required int tarifBase,
  }) async {
    final propre = libelle.trim();
    _exigerCategorieValide(
      libelle: propre,
      capaciteMax: capaciteMax,
      tarifBase: tarifBase,
    );

    await transaction(() async {
      final existante = await categorieParId(id);
      if (existante == null) throw const CategorieIntrouvable();

      await _exigerLibelleLibre(propre, exclureId: id);

      await (update(
        categoriesHebergementLocal,
      )..where((c) => c.id.equals(id))).write(
        CategoriesHebergementLocalCompanion(
          libelle: Value(propre),
          capaciteMax: Value(capaciteMax),
          tarifBase: Value(tarifBase.toDouble()),
        ),
      );
      // Lot F1 : seuls les champs changés partent.
      await _file.enfiler(
        table: TableSynchronisee.categoriesHebergement,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: champsModifies(
          chargeCategorieHebergement(
            libelle: existante.libelle,
            tarifBaseFrancs: existante.tarifBase,
            capaciteMax: existante.capaciteMax,
          ),
          chargeCategorieHebergement(
            libelle: propre,
            tarifBaseFrancs: tarifBase,
            capaciteMax: capaciteMax,
          ),
        ),
      );
    });

    return (await categorieParId(id))!;
  }

  /* ================================================================== */
  /* Écritures — unités                                                  */
  /* ================================================================== */

  /// Crée une unité au parc.
  ///
  /// ⚠ `statut` n'est **PAS** un paramètre, et la vue en donne la raison
  /// (`formulaire-unite`, l.596-601) : « `statut` ne se SAISIT pas — il est
  /// écrit par les gestes » du cycle. Une unité entre au parc `libre` ; la
  /// laisser choisir ferait dire à l'écran qu'une chambre est occupée sans que
  /// personne y dorme.
  Future<String> creerUnite({
    required String numero,
    required String categorieId,
  }) async {
    final propre = numero.trim();
    if (propre.isEmpty) throw const NumeroUniteRequis();

    final id = _uuid.v4();

    await transaction(() async {
      await _exigerCategorie(categorieId);
      await _exigerNumeroLibre(propre);

      await into(unitesHebergementLocal).insert(
        UnitesHebergementLocalCompanion.insert(
          id: id,
          categorieId: categorieId,
          numero: propre,
          statut: StatutUniteLocal.libre,
        ),
      );
      // Lot F1 : la création part au serveur (le statut ne part jamais : le
      // cycle appartient au serveur, qui l'ignore).
      await _file.enfiler(
        table: TableSynchronisee.unitesHebergement,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeUniteHebergement(
          numero: propre,
          categorieId: categorieId,
        ),
      );
    });

    return id;
  }

  /// Met à jour le code et la catégorie d'une unité.
  ///
  /// `statut` n'y figure pas, pour la même raison qu'à la création : il
  /// appartient au cycle, pas au formulaire.
  Future<void> modifierUnite(
    String id, {
    required String numero,
    required String categorieId,
  }) async {
    final propre = numero.trim();
    if (propre.isEmpty) throw const NumeroUniteRequis();

    await transaction(() async {
      final avant = await _exigerUnite(id);
      await _exigerCategorie(categorieId);
      await _exigerNumeroLibre(propre, exclureId: id);

      await (update(
        unitesHebergementLocal,
      )..where((u) => u.id.equals(id))).write(
        UnitesHebergementLocalCompanion(
          numero: Value(propre),
          categorieId: Value(categorieId),
        ),
      );
      // Lot F1 : seuls les champs changés partent.
      await _file.enfiler(
        table: TableSynchronisee.unitesHebergement,
        entiteId: id,
        type: TypeOperationSync.modification,
        payload: champsModifies(
          chargeUniteHebergement(
            numero: avant.numero,
            categorieId: avant.categorieId,
          ),
          chargeUniteHebergement(numero: propre, categorieId: categorieId),
        ),
      );
    });
  }

  /* ================================================================== */
  /* Le cycle — les gestes de parc, et EUX SEULS                         */
  /* ================================================================== */

  /// « Marquer Nettoyé & Prêt » — le troisième geste du cycle de la vue.
  ///
  /// C'est le seul mouvement du cycle que ce poste peut tenir honnêtement : il
  /// ne dépend d'aucun séjour, exactement comme `SejourService::marquerNettoyee()`
  /// côté serveur, qui ne reçoit que l'unité. Sans lui, toute unité libérée
  /// resterait en nettoyage indéfiniment, et le cycle s'arrêterait à son
  /// avant-dernier état.
  ///
  /// Une unité **hors service n'est jamais touchée** : la maintenance prime sur
  /// l'exploitation, et c'est l'exclusion que `SejourService` pose lui-même.
  Future<void> marquerNettoyee(String uniteId) async {
    final unite = await _exigerUnite(uniteId);
    if (unite.statut == StatutUniteLocal.horsService) return;

    await (update(
      unitesHebergementLocal,
    )..where((u) => u.id.equals(uniteId))).write(
      const UnitesHebergementLocalCompanion(
        statut: Value(StatutUniteLocal.libre),
      ),
    );
  }

  /// ARCHIVER, JAMAIS SUPPRIMER — et le mot compte autant que le geste.
  ///
  /// `hors_service` est l'archive de ce schéma : aucune table d'archives
  /// n'existe, et c'est le seul état qui retire l'unité de ce qui est vendable
  /// sans rien effacer. Supprimer la ligne rendrait illisibles **toutes les
  /// réservations qui la citent** — y compris celles qui n'existent nulle part
  /// ailleurs, ce poste n'ayant plus de serveur.
  ///
  /// Le verrou est **recontrôlé au moment d'AGIR**, pas seulement à
  /// l'affichage : entre l'ouverture de la modale et le clic, une réservation a
  /// pu naître. C'est le même raisonnement, et le même code, que
  /// `ParcHebergementService::archiver()`.
  ///
  /// @throws UniteEngagee l'unité est retenue par une réservation à venir
  Future<void> archiver(String uniteId) async {
    await transaction(() async {
      final unite = await _exigerUnite(uniteId);
      if (unite.statut == StatutUniteLocal.horsService) {
        throw UniteDejaArchivee(unite.numero);
      }

      final retenues = await engagements(uniteId);
      if (retenues.isNotEmpty) throw UniteEngagee(retenues);

      await (update(
        unitesHebergementLocal,
      )..where((u) => u.id.equals(uniteId))).write(
        const UnitesHebergementLocalCompanion(
          statut: Value(StatutUniteLocal.horsService),
        ),
      );
      // Lot F1 : l'archivage part en `actif: false` — le serveur l'applique
      // par son service, sous SA règle de droits.
      await _file.enfiler(
        table: TableSynchronisee.unitesHebergement,
        entiteId: uniteId,
        type: TypeOperationSync.modification,
        payload: const {'actif': false},
      );
    });
  }

  /// « Réintégrer au parc » — le pendant de l'archivage.
  ///
  /// Sans lui, « reste restaurable — rien n'est effacé » serait une promesse
  /// que rien ne tient (PA-59/60/61). L'unité revient `libre`, jamais dans
  /// l'état qu'elle portait avant : cet état n'est stocké nulle part, et le
  /// deviner afficherait une occupation que personne n'a constatée.
  ///
  /// Depuis le lot F1, la restauration part au serveur (`actif: true`), dans
  /// la même transaction que l'écriture.
  Future<void> restaurer(String uniteId) async {
    await transaction(() async {
      final unite = await _exigerUnite(uniteId);
      if (unite.statut != StatutUniteLocal.horsService) return;

      await (update(
        unitesHebergementLocal,
      )..where((u) => u.id.equals(uniteId))).write(
        const UnitesHebergementLocalCompanion(
          statut: Value(StatutUniteLocal.libre),
        ),
      );
      await _file.enfiler(
        table: TableSynchronisee.unitesHebergement,
        entiteId: uniteId,
        type: TypeOperationSync.modification,
        payload: const {'actif': true},
      );
    });
  }

  /// La file d'envoi (lot F1). Son propre générateur d'UUID : celui de ce DAO
  /// est injectable.
  OperationsSyncDao get _file => OperationsSyncDao(attachedDatabase);

  /* ================================================================== */
  /* Gardes et correspondances                                           */
  /* ================================================================== */

  void _exigerCategorieValide({
    required String libelle,
    required int capaciteMax,
    required int tarifBase,
  }) {
    if (libelle.isEmpty) throw const LibelleCategorieRequis();
    if (tarifBase <= 0) throw TarifCategorieInvalide(tarifBase);
    if (capaciteMax < 1) throw CapaciteCategorieInvalide(capaciteMax);
  }

  /// Unicité du libellé, **insensible à la casse et aux espaces de bord**.
  ///
  /// Une comparaison stricte laisserait entrer « Bungalow » et « bungalow » :
  /// deux catégories pour le logiciel, deux tarifs, et la réservation
  /// prendrait celle que la base rendrait en premier — le défaut exact que
  /// PA-160/161 a coûté côté serveur.
  Future<void> _exigerLibelleLibre(String libelle, {String? exclureId}) async {
    final existantes = await categories();
    final cherche = libelle.toLowerCase();

    for (final categorie in existantes) {
      if (categorie.id == exclureId) continue;
      if (categorie.libelle.trim().toLowerCase() == cherche) {
        throw LibelleCategorieDejaPris(categorie.libelle);
      }
    }
  }

  Future<void> _exigerNumeroLibre(String numero, {String? exclureId}) async {
    final cherche = numero.toLowerCase();

    final unites = await select(unitesHebergementLocal).get();
    for (final unite in unites) {
      if (unite.id == exclureId) continue;
      if (unite.numero.trim().toLowerCase() == cherche) {
        throw NumeroUniteDejaPris(unite.numero);
      }
    }
  }

  Future<void> _exigerCategorie(String categorieId) async {
    final categorie = await (select(
      categoriesHebergementLocal,
    )..where((c) => c.id.equals(categorieId))).getSingleOrNull();

    if (categorie == null) throw const CategorieIntrouvable();
  }

  Future<UnitesHebergementLocalData> _exigerUnite(String id) async {
    final unite = await (select(
      unitesHebergementLocal,
    )..where((u) => u.id.equals(id))).getSingleOrNull();

    if (unite == null) throw UniteIntrouvableAuParc(id);
    return unite;
  }

  /// Minuit UTC du jour — la même normalisation que `PeriodeSejour`.
  static DateTime _jour(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  CategorieHebergement _versCategorie(CategoriesHebergementLocalData d) =>
      CategorieHebergement(
        id: d.id,
        libelle: d.libelle,
        capaciteMax: d.capaciteMax,
        // Le schéma documenté stocke un `REAL`, le domaine compte en entiers :
        // le XOF n'a pas de sous-unité en circulation. La conversion est faite
        // ici plutôt que d'imposer un `double` au domaine, où il finirait par
        // produire un arrondi sur une addition de lignes.
        tarifBase: d.tarifBase.round(),
      );
}

/// Les valeurs de `unites_hebergement_local.statut` que CE DAO écrit — et,
/// depuis le 14/10/2026, celles que `SejourDao` écrit (`occupee`, `nettoyage`).
///
/// ⚠ Ce n'est **pas** la disponibilité, et ce n'est pas non plus l'enum du
/// domaine [StatutUnite] : ce sont les chaînes persistées. Elles vivent ici
/// pour qu'aucune écriture ne pose un littéral — une faute de frappe dans
/// `'hors_service'` produirait un statut inconnu, que `StatutUnite.depuisCode`
/// lirait comme `horsService` sans qu'aucune erreur ne le signale.
abstract final class StatutUniteLocal {
  static const String libre = 'libre';

  /// Écrit par `SejourDao.checkin` (lot C, 14/10/2026), seul auteur de ce
  /// statut — comme `SejourService::checkin` au serveur.
  static const String occupee = 'occupee';
  static const String nettoyage = 'nettoyage';
  static const String horsService = 'hors_service';
}
