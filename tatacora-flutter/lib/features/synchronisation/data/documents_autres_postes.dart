import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/operation_sync.dart';

/// Les documents saisis AILLEURS (lot F6, 17/10/2026) — la question que les écrivains posent
/// avant de déplacer ou d'annuler : **le serveur connaît-il le document ?**
///
/// Un geste (annulation, déplacement, statut) ne part que si oui : le document a été descendu, ou
/// sa création est dans la file sans y avoir été refusée. Une saisie d'avant la synchronisation
/// (v26) serait « introuvable » à chaque tentative.
///
/// **09/11/2026 (décision du PO : « le serveur ne juge plus les droits du compte d'appairage »,
/// « aucune opération ne doit bloquer ») : la seconde question de ce lot, « qui peut annuler le
/// document d'un autre poste » (règle Q3 : administration ou comptable, `peutAnnuler`,
/// `AnnulationAutrePosteRefusee`), N'EXISTE PLUS** — ni au poste ni au serveur
/// (`DocumentsDesAutresPostes` supprimée). Qui peut annuler est jugé par l'ÉCRAN, sur
/// l'utilisateur connecté : le droit local `ANNULATIONS` ET le droit du module. Seule la PHRASE de
/// l'ancien refus survit ([ancienRefus]), pour reconnaître les refus déjà dans « À traiter » et les
/// renvoyer d'eux-mêmes (`RelanceDesAnciensRefus`).
final class DocumentsAutresPostes {
  DocumentsAutresPostes(this._db);

  final AppDatabase _db;

  /// La phrase de l'ANCIEN refus du serveur (`sync.annulation_autre_poste`, retirée le
  /// 09/11/2026) : elle ne sert plus qu'à reconnaître les refus d'avant la décision.
  static const ancienRefus =
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
