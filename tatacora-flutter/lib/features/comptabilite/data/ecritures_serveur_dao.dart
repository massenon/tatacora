import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

/// Une ligne d'écriture VALIDÉE du serveur, telle que les états financiers la
/// lisent : centimes entiers, compte et journal déjà résolus.
final class EcritureServeur {
  const EcritureServeur({
    required this.annee,
    required this.codeJournal,
    required this.numeroCompte,
    required this.libelleCompte,
    required this.classe,
    required this.debitCentimes,
    required this.creditCentimes,
  });

  final int annee;
  final String codeJournal;
  final String numeroCompte;
  final String libelleCompte;
  final String classe;
  final int debitCentimes;
  final int creditCentimes;
}

/// Ce que ce poste a reçu du serveur, pour le dire sous les états.
final class ReceptionEcrituresServeur {
  const ReceptionEcrituresServeur({
    required this.nombre,
    required this.derniereDate,
  });

  /// Les écritures reçues, toutes années confondues.
  final int nombre;

  /// `AAAA-MM-JJ` de la plus récente, `null` si aucune.
  final String? derniereDate;
}

/// Le SEUL écrivain de `ecritures_serveur_local`, et un écrivain qui ne fait
/// qu'AJOUTER : une écriture validée ne change jamais (RG-11), donc une ligne
/// déjà reçue n'est jamais réécrite. Aucune écriture comptable du poste
/// (`ecritures_local`) n'est touchée, et aucune opération n'est enfilée : ce
/// miroir ne remonte rien.
class EcrituresServeurDao {
  EcrituresServeurDao(this._db);

  final AppDatabase _db;

  /// Ajoute la ligne si elle manque ; rend `true` quand elle est neuve.
  Future<bool> ajouterSiAbsente({
    required String id,
    required int annee,
    required String codeJournal,
    required String numeroCompte,
    required String libelleCompte,
    required String classe,
    required String dateEcriture,
    required String libelle,
    required int debitCentimes,
    required int creditCentimes,
    String? numeroPiece,
    String? ecritureContrepasseeId,
  }) async {
    final ajoutees = await _db
        .into(_db.ecrituresServeurLocal)
        .insert(
          EcrituresServeurLocalCompanion.insert(
            id: id,
            annee: annee,
            codeJournal: codeJournal,
            numeroCompte: numeroCompte,
            libelleCompte: libelleCompte,
            classe: classe,
            dateEcriture: dateEcriture,
            libelle: libelle,
            debitCentimes: Value(debitCentimes),
            creditCentimes: Value(creditCentimes),
            numeroPiece: Value(numeroPiece),
            ecritureContrepasseeId: Value(ecritureContrepasseeId),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return ajoutees > 0;
  }

  /// Les lignes d'UNE année d'exercice, pour calculer ses états.
  Future<List<EcritureServeur>> deLAnnee(int annee) async {
    final lignes = await (_db.select(
      _db.ecrituresServeurLocal,
    )..where((e) => e.annee.equals(annee))).get();
    return [
      for (final l in lignes)
        EcritureServeur(
          annee: l.annee,
          codeJournal: l.codeJournal,
          numeroCompte: l.numeroCompte,
          libelleCompte: l.libelleCompte,
          classe: l.classe,
          debitCentimes: l.debitCentimes,
          creditCentimes: l.creditCentimes,
        ),
    ];
  }

  Future<ReceptionEcrituresServeur> reception() async {
    final r = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, MAX(date_ecriture) AS derniere '
          'FROM ecritures_serveur_local',
        )
        .getSingle();
    return ReceptionEcrituresServeur(
      nombre: r.data['n'] as int,
      derniereDate: r.data['derniere'] as String?,
    );
  }
}
