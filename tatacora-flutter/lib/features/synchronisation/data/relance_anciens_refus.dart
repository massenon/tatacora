import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../domain/operation_sync.dart';
import 'documents_autres_postes.dart';
import 'operations_sync_dao.dart';

/// Les annulations REFUSÉES avant le 09/11/2026 par l'ancienne règle « le document d'un autre
/// poste ne s'annule que par l'administration ou le comptable » (`DocumentsAutresPostes.ancienRefus`)
/// sont RENVOYÉES d'elles-mêmes, UNE fois (décision du PO du 09/11/2026 : « aucune opération ne
/// doit bloquer la synchronisation »). Le serveur ne juge plus cette règle (`8c1b16b`, réservations
/// `b7554a1`) : il accepte désormais ces annulations, et personne n'a à cliquer « Relancer ».
///
/// Les tables concernées sont celles qui portaient la règle : réservations, ventes, factures
/// (avoir d'annulation), paiements de facture et règlements fournisseur. Le refus reste à
/// l'historique de la file, marqué remplacé ; un refus d'une AUTRE cause n'est jamais renvoyé.
///
/// N'écrit rien lui-même : le renvoi passe par l'écrivain unique de la file (`OperationsSyncDao`).
final class RelanceDesAnciensRefus {
  RelanceDesAnciensRefus(this._db);

  final AppDatabase _db;

  /// Les tables dont une annulation a pu être refusée par l'ancienne règle, et le mot de statut
  /// que porte leur charge d'annulation (`chargeAnnulation*`).
  static const Map<TableSynchronisee, String> statutsDAnnulation = {
    TableSynchronisee.reservations: 'annulee',
    TableSynchronisee.ventes: 'annulee',
    TableSynchronisee.factures: 'annulee',
    TableSynchronisee.paiements: 'annule',
    TableSynchronisee.reglementsFournisseur: 'annule',
  };

  /// Les premiers mots de la phrase retirée, assez longs pour ne pas se tromper de refus.
  static final String debutDuRefus = DocumentsAutresPostes.ancienRefus
      .substring(0, DocumentsAutresPostes.ancienRefus.indexOf(' ('));

  /// Renvoie les annulations refusées par l'ancienne règle ; [tables] et [entiteId] restreignent.
  /// Rend le nombre d'opérations renvoyées.
  Future<int> relancer({
    Set<TableSynchronisee>? tables,
    String? entiteId,
  }) async {
    final file = OperationsSyncDao(_db);
    final remplacees = await file.remplacees();
    var renvoyees = 0;
    for (final entree in statutsDAnnulation.entries) {
      if (tables != null && !tables.contains(entree.key)) continue;
      for (final o in await file.operations(
        statut: StatutOperationSync.rejete,
        table: entree.key,
        entiteId: entiteId,
      )) {
        if (remplacees.containsKey(o.uuidOperation)) continue;
        final motif = _motifDuRefus(o.resultatJson);
        if (motif == null || !motif.startsWith(debutDuRefus)) continue;
        final charge = jsonDecode(o.payload);
        if (charge is! Map<String, Object?> ||
            charge['statut'] != entree.value) {
          continue;
        }
        // La réservation porte, en plus, l'auteur LOCAL (login de l'opération) que l'ancienne
        // charge ne portait pas ; les autres tables n'en ont pas besoin.
        final login = o.auteurLogin;
        final avecAuteur =
            entree.key == TableSynchronisee.reservations &&
            login != null &&
            login.isNotEmpty &&
            charge['auteur'] == null;
        await file.renvoyer(
          o.uuidOperation,
          chargeCorrigee: avecAuteur ? {...charge, 'auteur': login} : null,
        );
        renvoyees++;
      }
    }
    return renvoyees;
  }

  static String? _motifDuRefus(String? resultatJson) {
    if (resultatJson == null) return null;
    try {
      final r = jsonDecode(resultatJson);
      final m = r is Map ? r['motif'] : null;
      return m is String ? m : null;
    } on FormatException {
      return null;
    }
  }
}
