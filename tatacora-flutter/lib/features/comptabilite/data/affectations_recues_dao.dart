import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Une affectation du résultat telle que le serveur l'a rendue au poste.
final class AffectationRecueDuServeur {
  const AffectationRecueDuServeur({
    required this.id,
    required this.annee,
    required this.resultatCentimes,
    required this.dateApprobation,
    required this.reserveLegaleCentimes,
    required this.autresReservesCentimes,
    required this.dividendesCentimes,
    required this.reportCrediteurCentimes,
    required this.reportDebiteurCentimes,
    required this.numeroPiece,
    required this.pieceOrigineId,
    required this.auteurLogin,
    required this.affecteeLe,
    required this.contrepasseeLe,
  });

  final String id;
  final int annee;
  final int resultatCentimes;
  final String dateApprobation;
  final int reserveLegaleCentimes;
  final int autresReservesCentimes;
  final int dividendesCentimes;
  final int reportCrediteurCentimes;
  final int reportDebiteurCentimes;
  final String numeroPiece;
  final String? pieceOrigineId;
  final String? auteurLogin;
  final DateTime affecteeLe;
  final DateTime? contrepasseeLe;

  bool get contrepassee => contrepasseeLe != null;
}

/// Le SEUL écrivain de `affectations_resultat_local` (v53), le miroir de LECTURE
/// des affectations du résultat connues du serveur — passées au web, ou par un
/// autre poste, ou par celui-ci.
///
/// Il ne fait que RECEVOIR : l'état du serveur remplace la ligne de même
/// identifiant (c'est ainsi qu'une contre-passation faite ailleurs arrive :
/// `contrepassee_le` se renseigne), jamais il n'enfile, jamais il ne touche aux
/// écritures du poste (`ecritures_local`) — la pièce d'une affectation que CE poste
/// a passée reste, jusqu'à sa reprise, dans son propre journal.
class AffectationsRecuesDao {
  AffectationsRecuesDao(this._db);

  final AppDatabase _db;

  /// Inscrit (ou met à jour) l'affectation du serveur [a].
  Future<void> inscrire(AffectationRecueDuServeur a) async {
    await _db
        .into(_db.affectationsResultatLocal)
        .insertOnConflictUpdate(
          AffectationsResultatLocalCompanion.insert(
            id: a.id,
            annee: a.annee,
            resultatCentimes: a.resultatCentimes,
            dateApprobation: a.dateApprobation,
            reserveLegaleCentimes: Value(a.reserveLegaleCentimes),
            autresReservesCentimes: Value(a.autresReservesCentimes),
            dividendesCentimes: Value(a.dividendesCentimes),
            reportCrediteurCentimes: Value(a.reportCrediteurCentimes),
            reportDebiteurCentimes: Value(a.reportDebiteurCentimes),
            numeroPiece: a.numeroPiece,
            pieceOrigineId: Value(a.pieceOrigineId),
            auteurLogin: Value(a.auteurLogin),
            affecteeLe: a.affecteeLe,
            contrepasseeLe: Value(a.contrepasseeLe),
          ),
        );
  }

  /// Les affectations de l'exercice [annee] (N-1), la plus récente d'abord.
  Future<List<AffectationRecueDuServeur>> deLAnnee(int annee) async {
    final lignes =
        await (_db.select(_db.affectationsResultatLocal)
              ..where((a) => a.annee.equals(annee))
              ..orderBy([
                (a) => OrderingTerm.desc(a.affecteeLe),
                (a) => OrderingTerm.desc(a.id),
              ]))
            .get();
    return [
      for (final l in lignes)
        AffectationRecueDuServeur(
          id: l.id,
          annee: l.annee,
          resultatCentimes: l.resultatCentimes,
          dateApprobation: l.dateApprobation,
          reserveLegaleCentimes: l.reserveLegaleCentimes,
          autresReservesCentimes: l.autresReservesCentimes,
          dividendesCentimes: l.dividendesCentimes,
          reportCrediteurCentimes: l.reportCrediteurCentimes,
          reportDebiteurCentimes: l.reportDebiteurCentimes,
          numeroPiece: l.numeroPiece,
          pieceOrigineId: l.pieceOrigineId,
          auteurLogin: l.auteurLogin,
          affecteeLe: l.affecteeLe,
          contrepasseeLe: l.contrepasseeLe,
        ),
    ];
  }
}
