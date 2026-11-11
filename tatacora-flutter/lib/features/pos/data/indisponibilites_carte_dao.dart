import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../bar/domain/motif_indisponibilite.dart';
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/charges_synchronisation.dart';
import '../../synchronisation/domain/operation_sync.dart';
import 'dto/catalogue_dto.dart';

/// Les RETRAITS de la carte du jour d'un poste — boisson (M5) ou plat (M4).
///
/// Seul écrivain de `indisponibilites_carte_local` avec l'aligneur de la
/// descente. Le serveur écrivait une ligne `indisponibilites_carte` (motif,
/// commentaire, instants) : ce poste en écrit la même, la pousse, et reçoit
/// celles des autres postes et de la PWA.
///
/// ## Un retrait en cours par article
///
/// Retirer un article déjà retiré ne double rien : [retirer] rend `null`, comme
/// le serveur fusionne. [remettre] ferme le retrait en cours (`date_retour`) ;
/// la ligne reste, c'est l'historique du serveur aussi.
///
/// @see EF-M5-02 Carte des boissons
class IndisponibilitesCarteDao {
  IndisponibilitesCarteDao(this._db, {Uuid? uuid, DateTime Function()? horloge})
    : _uuid = uuid ?? const Uuid(),
      _horloge = horloge ?? DateTime.now;

  final AppDatabase _db;
  final Uuid _uuid;
  final DateTime Function() _horloge;

  $IndisponibilitesCarteLocalTable get _table => _db.indisponibilitesCarteLocal;

  /// Les retraits EN COURS, par identifiant de boisson.
  Future<Map<String, IndisponibiliteDistante>> boissonsRetirees() async =>
      _enCours((l) => l.boissonId);

  /// Les retraits EN COURS, par identifiant de plat.
  Future<Map<String, IndisponibiliteDistante>> platsRetires() async =>
      _enCours((l) => l.platId);

  Future<Map<String, IndisponibiliteDistante>> _enCours(
    String? Function(IndisponibiliteCarteLigne) cle,
  ) async {
    final lignes = await (_db.select(
      _table,
    )..where((l) => l.dateRetourDisponibilite.isNull())).get();
    return {for (final l in lignes) ?cle(l): _versRetrait(l)};
  }

  /// Rend l'article indisponible. Exactement un de [boissonId] / [platId].
  /// Rend l'identifiant de la ligne écrite, ou `null` si l'article est DÉJÀ
  /// retiré (rien n'est écrit, rien ne part).
  Future<String?> retirer({
    String? boissonId,
    String? platId,
    required MotifIndisponibilite motif,
    String? commentaire,
  }) {
    if ((boissonId == null) == (platId == null)) {
      throw ArgumentError(
        'un retrait porte sur une boisson OU sur un plat, jamais les deux',
      );
    }
    return _db.transaction(() async {
      if (await _enCoursDe(boissonId: boissonId, platId: platId) != null) {
        return null;
      }
      final id = _uuid.v4();
      final maintenant = _horloge();
      final note = commentaire?.trim();
      final propre = note == null || note.isEmpty ? null : note;
      await _db
          .into(_table)
          .insert(
            IndisponibilitesCarteLocalCompanion.insert(
              id: id,
              boissonId: Value(boissonId),
              platId: Value(platId),
              motif: motif.code,
              commentaire: Value(propre),
              dateIndisponibilite: maintenant,
            ),
          );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.indisponibilitesCarte,
        entiteId: id,
        type: TypeOperationSync.creation,
        payload: chargeIndisponibiliteCarte(
          boissonId: boissonId,
          platId: platId,
          motif: motif.code,
          commentaire: propre,
          date: maintenant,
        ),
        horodatage: maintenant,
      );
      return id;
    });
  }

  /// Remet l'article à la carte. `false` : aucun retrait en cours (déjà remis,
  /// ici ou ailleurs) — rien n'est écrit.
  Future<bool> remettre({String? boissonId, String? platId}) {
    if ((boissonId == null) == (platId == null)) {
      throw ArgumentError(
        'une remise porte sur une boisson OU sur un plat, jamais les deux',
      );
    }
    return _db.transaction(() async {
      final ligne = await _enCoursDe(boissonId: boissonId, platId: platId);
      if (ligne == null) return false;
      final maintenant = _horloge();
      await (_db.update(_table)..where((l) => l.id.equals(ligne.id))).write(
        IndisponibilitesCarteLocalCompanion(
          dateRetourDisponibilite: Value(maintenant),
        ),
      );
      await OperationsSyncDao(_db).enfiler(
        table: TableSynchronisee.indisponibilitesCarte,
        entiteId: ligne.id,
        type: TypeOperationSync.modification,
        payload: chargeRemiseALaCarte(maintenant),
        horodatage: maintenant,
      );
      return true;
    });
  }

  Future<IndisponibiliteCarteLigne?> _enCoursDe({
    String? boissonId,
    String? platId,
  }) =>
      (_db.select(_table)..where(
            (l) =>
                l.dateRetourDisponibilite.isNull() &
                (boissonId != null
                    ? l.boissonId.equals(boissonId)
                    : l.platId.equals(platId!)),
          ))
          .getSingleOrNull();

  static IndisponibiliteDistante _versRetrait(IndisponibiliteCarteLigne l) {
    final m = MotifIndisponibilite.values
        .where((x) => x.code == l.motif)
        .firstOrNull;
    return IndisponibiliteDistante(
      motif: l.motif,
      // Un motif inconnu de ce poste (registre élargi au serveur) s'affiche
      // tel que reçu plutôt que de disparaître.
      libelle: m?.libelle ?? l.motif,
      temporaire: m?.temporaire ?? false,
      commentaire: l.commentaire,
    );
  }
}
