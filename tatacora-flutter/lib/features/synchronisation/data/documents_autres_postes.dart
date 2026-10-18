import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/operation_sync.dart';

/// Les documents saisis AILLEURS (lot F6, 17/10/2026) — deux questions que
/// les écrivains posent avant d'annuler ou de déplacer.
///
/// 1. **Qui peut annuler** (décision Q3 du PO : « l'administration et le
///    comptable ») : un document DESCENDU (inscrit dans
///    `origines_documents_local`, d'un autre poste ou du serveur) ne
///    s'annule ici que par un compte `administrateur`, `super_admin` ou
///    `comptable` — la règle du serveur (`DocumentsDesAutresPostes`), qui la
///    tient aussi : refuser ici évite qu'une annulation locale diverge d'un
///    refus du serveur.
/// 2. **Le serveur connaît-il le document ?** Un geste (annulation,
///    déplacement, statut) ne part que si oui : le document a été descendu,
///    ou sa création est dans la file sans y avoir été refusée. Une saisie
///    d'avant la synchronisation (v26) serait « introuvable » à chaque
///    tentative.
final class DocumentsAutresPostes {
  DocumentsAutresPostes(this._db);

  final AppDatabase _db;

  /// Les rôles admis à annuler le document d'un autre poste.
  static const rolesAdmis = {'administrateur', 'super_admin', 'comptable'};

  /// La phrase du serveur (`sync.annulation_autre_poste`).
  static const refus =
      'Annulation refusée : ce document a été saisi sur un autre poste (ou au '
      'serveur). Seuls l\'administration et le comptable peuvent l\'annuler.';

  Future<bool> descendu(String tableServeur, String id) async =>
      (await _db
              .customSelect(
                'SELECT 1 FROM origines_documents_local '
                'WHERE table_serveur = ? AND entite_id = ? LIMIT 1',
                variables: [
                  Variable.withString(tableServeur),
                  Variable.withString(id),
                ],
              )
              .get())
          .isNotEmpty;

  /// `true` si [auteurId] peut annuler le document : il est de ce poste, ou
  /// le compte est d'administration ou comptable.
  Future<bool> peutAnnuler(
    String tableServeur,
    String id,
    String? auteurId,
  ) async {
    if (!await descendu(tableServeur, id)) return true;
    if (auteurId == null) return false;
    final compte = await (_db.select(
      _db.utilisateursLocal,
    )..where((u) => u.id.equals(auteurId))).getSingleOrNull();
    return compte != null && rolesAdmis.contains(compte.role);
  }

  /// Le serveur détient-il (ou recevra-t-il) le document ?
  Future<bool> connuDuServeur(TableSynchronisee table, String id) async {
    if (await descendu(table.nomServeur, id)) return true;
    return (await _db
            .customSelect(
              'SELECT 1 FROM operations_sync_local WHERE table_serveur = ? '
              "AND entite_id = ? AND type = 'creation' AND statut <> 'rejete' "
              'LIMIT 1',
              variables: [
                Variable.withString(table.nomServeur),
                Variable.withString(id),
              ],
            )
            .get())
        .isNotEmpty;
  }
}

/// Le refus d'annuler le document d'un autre poste (Q3).
final class AnnulationAutrePosteRefusee implements Exception {
  const AnnulationAutrePosteRefusee();

  String get message => DocumentsAutresPostes.refus;

  @override
  String toString() => message;
}
