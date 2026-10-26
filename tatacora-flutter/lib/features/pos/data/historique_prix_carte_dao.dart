import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../bar/domain/entities/trace_prix.dart';
import '../domain/changement_prix_carte.dart';

/// L'HISTORIQUE DES PRIX de la carte, tenu par ce poste (schéma v38,
/// 26/10/2026) — le SEUL écrivain de `historique_prix_carte_local`.
///
/// Deux moitiés, comme toute table répliquée (piège 11) :
///
///  * **qui l'écrit** : [tracer], appelé DANS la transaction qui change le prix
///    (`CatalogueDao.enregistrerBoisson` pour une boisson, `RestaurantDao` pour un
///    plat) — une trace sans le changement qui l'a causée, ou l'inverse, serait
///    le défaut que le serveur refuse (son observateur est l'unique auteur). Et
///    [inscrireDescendue], appelée par `AligneurCatalogue` pour les traces que le
///    serveur rapporte (autres postes, PWA, et les siennes une fois appliquées) ;
///  * **qui la lit** : [deLArticle], pour la modale « Historique des prix » du
///    bar et du restaurant.
///
/// La trace n'est JAMAIS enfilée : le serveur l'écrit lui-même en appliquant le
/// changement de prix que le poste lui pousse. L'envoyer ferait un second auteur.
///
/// ## Une trace du poste, puis la même du serveur : une seule ligne
///
/// Quand le serveur a appliqué le changement, sa trace redescend avec un autre
/// identifiant. [inscrireDescendue] cherche la trace locale équivalente (même
/// article, même champ, mêmes valeurs, pas encore confirmée) et l'ADOPTE — date
/// et auteur du serveur — au lieu d'en ajouter une seconde. Sans cette
/// adoption, chaque changement fait ici s'afficherait deux fois.
class HistoriquePrixCarteDao {
  HistoriquePrixCarteDao(this._db, {Uuid? uuid, DateTime Function()? horloge})
    : _uuid = uuid ?? const Uuid(),
      _horloge = horloge ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _horloge;

  $HistoriquePrixCarteLocalTable get _table => _db.historiquePrixCarteLocal;

  /// Sommes-nous DANS une transaction Drift ? (même sonde que
  /// `OperationsSyncDao`.)
  bool get _dansUneTransaction =>
      // ignore: invalid_use_of_internal_member
      !identical(_db.resolvedEngine, _db);

  /* ================================================================== */
  /* Écriture                                                            */
  /* ================================================================== */

  /// Trace [changements] pour l'article [sourceId] du rayon [source]. À appeler
  /// DANS la transaction du changement de prix. Rend le nombre de lignes
  /// écrites (zéro : rien n'a changé du côté du prix).
  ///
  /// L'auteur est le compte connecté (`AppDatabase.auteurEcriture`) : « — » à
  /// l'écran quand personne ne l'est, jamais un compte inventé.
  ///
  /// @throws StateError appelé hors d'une transaction Drift
  Future<int> tracer({
    required SourceCarte source,
    required String sourceId,
    required List<ChangementPrix> changements,
  }) async {
    if (!_dansUneTransaction) {
      throw StateError(
        'HistoriquePrixCarteDao.tracer doit être appelé DANS la transaction du '
        'changement de prix : hors d’elle, une coupure laisserait un prix '
        'changé sans trace, ou une trace sans prix changé.',
      );
    }
    if (sourceId.isEmpty) {
      throw ArgumentError.value(sourceId, 'sourceId', 'identifiant vide');
    }
    if (changements.isEmpty) return 0;

    final maintenant = _horloge();
    final par = _db.auteurEcriture().login;
    for (final c in changements) {
      await _db
          .into(_table)
          .insert(
            HistoriquePrixCarteLocalCompanion.insert(
              id: _uuid.v4(),
              source: source.code,
              sourceId: sourceId,
              champ: c.champ,
              ancienPrix: Value(c.ancien),
              nouveauPrix: Value(c.nouveau),
              par: Value(par),
              creeLe: maintenant,
            ),
          );
    }
    return changements.length;
  }

  /// Inscrit une trace RAPPORTÉE par le serveur. Rend l'identifiant de la trace
  /// LOCALE adoptée quand elle en remplace une (l'appelant retient alors la
  /// correspondance `id serveur -> id local`), `null` quand elle est inscrite
  /// telle quelle ou déjà détenue.
  ///
  /// Idempotente : rejouer le même élément met la ligne à jour, n'en crée pas.
  Future<String?> inscrireDescendue({
    required String id,
    required SourceCarte source,
    required String sourceId,
    required String champ,
    required String? ancien,
    required String? nouveau,
    required String? par,
    required DateTime creeLe,
  }) async {
    final connue = await (_db.select(
      _table,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (connue != null) {
      await (_db.update(_table)..where((t) => t.id.equals(id))).write(
        HistoriquePrixCarteLocalCompanion(
          par: Value(par ?? connue.par),
          creeLe: Value(creeLe),
          recuDuServeur: const Value(true),
        ),
      );
      return null;
    }

    // La trace du poste équivalente, la plus ancienne d'abord : deux
    // changements identiques successifs s'adoptent dans l'ordre où ils ont été
    // faits.
    final candidates =
        await (_db.select(_table)
              ..where(
                (t) =>
                    t.recuDuServeur.equals(false) &
                    t.source.equals(source.code) &
                    t.sourceId.equals(sourceId) &
                    t.champ.equals(champ),
              )
              ..orderBy([
                (t) => OrderingTerm.asc(t.creeLe),
                (t) => OrderingTerm.asc(t.id),
              ]))
            .get();
    for (final c in candidates) {
      if (c.ancienPrix != ancien || c.nouveauPrix != nouveau) continue;
      await (_db.update(_table)..where((t) => t.id.equals(c.id))).write(
        HistoriquePrixCarteLocalCompanion(
          par: Value(par ?? c.par),
          creeLe: Value(creeLe),
          recuDuServeur: const Value(true),
        ),
      );
      return c.id;
    }

    await _db
        .into(_table)
        .insert(
          HistoriquePrixCarteLocalCompanion.insert(
            id: id,
            source: source.code,
            sourceId: sourceId,
            champ: champ,
            ancienPrix: Value(ancien),
            nouveauPrix: Value(nouveau),
            par: Value(par),
            creeLe: creeLe,
            recuDuServeur: const Value(true),
          ),
        );
    return null;
  }

  /* ================================================================== */
  /* Lecture                                                             */
  /* ================================================================== */

  /// L'historique de CET article, du plus récent au plus ancien — comme la vue
  /// (`orderByDesc('created_at')`), départagé par l'identifiant pour un ordre
  /// stable.
  Future<List<TracePrix>> deLArticle(
    SourceCarte source,
    String sourceId,
  ) async {
    final lignes =
        await (_db.select(_table)
              ..where(
                (t) =>
                    t.source.equals(source.code) & t.sourceId.equals(sourceId),
              )
              ..orderBy([
                (t) => OrderingTerm.desc(t.creeLe),
                (t) => OrderingTerm.desc(t.id),
              ]))
            .get();
    return [
      for (final l in lignes)
        TracePrix(
          id: l.id,
          date: l.creeLe,
          champ: l.champ,
          ancien: l.ancienPrix,
          nouveau: l.nouveauPrix,
          par: l.par,
        ),
    ];
  }
}
