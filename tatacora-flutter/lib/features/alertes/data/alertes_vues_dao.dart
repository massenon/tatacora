/// Le SEUL écrivain de `alertes_vues_local` (schéma v22) — l'état « vu » des
/// alertes de la cloche, compte par compte.
///
/// Réplique des deux gestes de `ClocheNotifications` du serveur
/// (`marquerToutLu`, `marquerLu`) : un `insertOrIgnore` par clé, sur l'unicité
/// `(utilisateur_id, cle_alerte)`. Une clé déjà vue ne s'écrit pas deux fois ;
/// rien ne se supprime (une alerte dont la cause a disparu ne s'affiche plus,
/// sa ligne « vue » reste — comme au serveur, qui ne purge pas non plus).
///
/// La garde « la clé doit désigner une alerte RÉELLEMENT dérivée pour ce
/// compte » du serveur (`marquerLu`) est tenue par l'appelant
/// (`providers_alertes.dart`) : il ne passe que des clés de la liste qu'il vient
/// de dériver.
library;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';

class AlertesVuesDao {
  AlertesVuesDao(this._base, {DateTime Function()? maintenant, Uuid? uuid})
    : _maintenant = maintenant ?? DateTime.now,
      _uuid = uuid ?? const Uuid();

  final AppDatabase _base;
  final DateTime Function() _maintenant;
  final Uuid _uuid;

  /// Les clés d'alerte que [utilisateurId] a vues.
  Future<Set<String>> clesVues(String utilisateurId) async {
    final t = _base.alertesVuesLocal;
    final lignes = await (_base.select(
      t,
    )..where((v) => v.utilisateurId.equals(utilisateurId))).get();
    return {for (final l in lignes) l.cleAlerte};
  }

  /// Marque [cles] vues pour [utilisateurId], dans UNE transaction. Une clé
  /// déjà vue est ignorée (`insertOrIgnore`, l'unicité fait foi).
  Future<void> marquerVues(String utilisateurId, Iterable<String> cles) async {
    final t = _base.alertesVuesLocal;
    final date = _maintenant();
    await _base.transaction(() async {
      for (final cle in cles) {
        await _base
            .into(t)
            .insert(
              AlertesVuesLocalCompanion.insert(
                id: _uuid.v4(),
                utilisateurId: utilisateurId,
                cleAlerte: cle,
                dateVue: date,
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
    });
  }
}
