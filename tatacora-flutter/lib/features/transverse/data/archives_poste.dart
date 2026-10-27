import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../hebergement/data/parc_dao.dart';
import '../../hebergement/domain/refus_parc.dart' show RefusParc;
import '../../synchronisation/data/operations_sync_dao.dart';
import '../../synchronisation/domain/operation_sync.dart';
import '../../vehicules/data/vehicule_dao.dart';
import '../../vehicules/domain/entities/vehicule.dart' show StatutVehicule;
import '../../vehicules/domain/regles_vehicules.dart' show RefusVehicule;
import '../domain/registre_archives.dart';

/// Un « Restaurer » refusé : rien n'est modifié. [message] est la phrase du
/// service qui a refusé (élément introuvable).
final class RefusArchive implements Exception {
  const RefusArchive(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Le registre des archives du poste et son seul geste, « Restaurer »
/// (`ImportExport::restaurerArchive`) — voir `registre_archives.dart`.
///
/// ## Aucun écrivain de plus
///
/// La restauration passe par les DEUX écrivains uniques de ces tables, comme le
/// serveur passe par ses services de parc : `ParcDao.restaurer` (unité,
/// `libre`, jamais l'état d'avant) et `VehiculeDao.changerStatut(disponible)`
/// (`ParcVehiculeService::remettreEnService`). Chacun enfile sa modification
/// dans sa transaction ; ce fichier n'écrit rien lui-même.
class ArchivesPoste {
  ArchivesPoste(this._base, {required this.parc, required this.vehicules});

  final AppDatabase _base;

  /// L'écrivain unique des unités (`ParcDao.restaurer`).
  final ParcDao parc;

  /// L'écrivain unique des véhicules (`VehiculeDao.changerStatut`).
  final VehiculeDao vehicules;

  /// `RegistreArchivesService::archives()` + `restaurees()`.
  Future<RegistreArchives> registre() async {
    final listeUnites = [
      for (final u in await _base.select(_base.unitesHebergementLocal).get())
        (id: u.id, libelle: u.numero, statut: u.statut),
    ];
    final listeVehicules = [
      for (final v in await _base.select(_base.vehiculesLocal).get())
        (id: v.id, libelle: v.immatriculation, statut: v.statut),
    ];

    // La file est lue par SON écrivain unique, dans l'ordre d'écriture.
    final file = OperationsSyncDao(_base);
    final operations = <OperationArchive>[];
    for (final (table, type) in [
      (TableSynchronisee.unitesHebergement, TypeArchive.uniteHebergement),
      (TableSynchronisee.vehicules, TypeArchive.vehicule),
    ]) {
      for (final o in await file.operations(table: table)) {
        final charge = _charge(o.payload);
        if (charge == null) continue;
        operations.add((
          type: type,
          entiteId: o.entiteId,
          charge: charge,
          instant: o.creeLe,
          auteur: o.auteurLogin,
        ));
      }
    }
    return composerRegistreArchives(
      unites: listeUnites,
      vehicules: listeVehicules,
      operations: operations,
    );
  }

  static Map<String, Object?>? _charge(String json) {
    try {
      final decode = jsonDecode(json);
      return decode is Map<String, dynamic> ? decode : null;
    } on FormatException {
      return null;
    }
  }

  /// `RegistreArchivesService::restaurer()` : remet en place et rend le
  /// libellé de l'élément (le « :element » de « :element remis en place. »).
  ///
  /// @throws RefusArchive l'élément n'existe pas sur ce poste
  Future<String> restaurer(TypeArchive type, String id) async {
    switch (type) {
      case TypeArchive.uniteHebergement:
        final unite = await (_base.select(
          _base.unitesHebergementLocal,
        )..where((u) => u.id.equals(id))).getSingleOrNull();
        if (unite == null) {
          throw const RefusArchive(MessagesArchives.elementIntrouvable);
        }
        try {
          await parc.restaurer(id);
        } on RefusParc catch (refus) {
          throw RefusArchive(refus.message);
        }
        return unite.numero;
      case TypeArchive.vehicule:
        try {
          final v = await vehicules.changerStatut(
            id,
            StatutVehicule.disponible,
          );
          return v.immatriculation;
        } on RefusVehicule catch (refus) {
          throw RefusArchive(refus.message);
        }
    }
  }
}

/// Les phrases de l'onglet « Restaurer » (`pwa.import_export.*`, au mot).
abstract final class MessagesArchives {
  /// `pwa.import_export.archive_restauree`.
  static String restauree(String element) => '$element remis en place.';

  /// Le serveur répond 403 sans phrase (`exigerEcriture`) ; le poste le dit.
  static const String droitManquant =
      'Accès refusé : ce geste exige le droit d’écrire dans ce module. Rien n’a '
      'été modifié.';

  /// Ce que le serveur dit en 404 (`findOrFail`) ; le poste le dit en français.
  static const String elementIntrouvable =
      'Cet élément n’existe plus sur ce poste : rien n’a été modifié.';
}
