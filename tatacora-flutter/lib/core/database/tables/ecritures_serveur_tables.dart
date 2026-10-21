/// Les ÉCRITURES VALIDÉES du serveur, en miroir de lecture seule — v34,
/// 21/10/2026 (« compte de résultat et bilan sur le poste »).
///
/// ## Ce que ce miroir est, et ce qu'il n'est PAS
///
/// Le serveur est le seul comptable (D246) : le poste n'en recopie pas la
/// comptabilité pour la TENIR, seulement pour LIRE les états financiers
/// (compte de résultat, bilan, N-1) sans réseau. Les écritures que le poste
/// passe lui-même (`ecritures_local`, `MoteurComptable`) restent ce qu'elles
/// étaient — son journal et sa balance —, et NE SONT PAS mélangées à celles-ci :
/// le serveur passe sa propre pièce pour chaque document que ce poste lui envoie,
/// et additionner les deux compterait chaque vente deux fois.
///
/// Les états financiers du poste se lisent donc ICI et nulle part ailleurs, et
/// disent jusqu'où ce poste a reçu (« écritures du serveur reçues jusqu'au… »)
/// et combien d'opérations il n'a pas encore envoyées.
///
/// ## Ne descendent que les VALIDÉES
///
/// Une écriture validée ne se modifie ni ne se supprime jamais (RG-11) : rien
/// ici ne peut devenir périmé. Un brouillon, lui, peut disparaître, et aucun
/// alignement ne supprime. Le miroir est donc IMMUABLE : l'aligneur n'écrit
/// une ligne que si elle manque, ne la réécrit jamais, et rien d'autre ne
/// l'écrit (une sonde de test le garde).
///
/// Aucune clé étrangère : chaque ligne porte déjà l'année de son exercice, le
/// code de son journal et le numéro, le libellé et la classe de son compte —
/// le serveur les résout, le poste n'a pas à posséder le plan du serveur.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `AligneurDocuments` (descente), seul | `EtatsFinanciersLocal` (compte de résultat, bilan) |
library;

import 'package:drift/drift.dart';

@DataClassName('EcritureServeurLigne')
class EcrituresServeurLocal extends Table {
  /// L'identifiant de la ligne AU SERVEUR.
  TextColumn get id => text()();

  /// L'année de l'exercice (`exercices_comptables.annee`).
  IntColumn get annee => integer()();

  /// Le code du journal (`VTE`, `ACH`, `BQ`, `CAI`, `OD`, `CL`, `AN`…).
  TextColumn get codeJournal => text()();

  TextColumn get numeroCompte => text()();

  TextColumn get libelleCompte => text()();

  /// La classe du compte (`1` à `8`), telle que le plan du serveur la porte.
  TextColumn get classe => text()();

  /// `AAAA-MM-JJ`.
  TextColumn get dateEcriture => text()();

  TextColumn get libelle => text()();

  /// CENTIMES entiers (le serveur : `DECIMAL(15,2)`). Une ligne est débit OU
  /// crédit : l'autre vaut zéro.
  IntColumn get debitCentimes => integer().withDefault(const Constant(0))();

  IntColumn get creditCentimes => integer().withDefault(const Constant(0))();

  /// `CODE-AAAA-NNNNN` ; `null` sur une contre-passation, comme au serveur.
  TextColumn get numeroPiece => text().nullable()();

  /// La ligne d'ORIGINE qu'une contre-passation inverse.
  TextColumn get ecritureContrepasseeId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
