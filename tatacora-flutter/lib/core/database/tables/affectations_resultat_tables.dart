/// Les AFFECTATIONS DU RÉSULTAT reçues du serveur — v53, 09/11/2026 (demande du
/// PO : « une affectation passée au web DOIT apparaître sur le poste »).
///
/// Une ligne par affectation connue du serveur (`affectations_resultat`), ACTIVE
/// ou CONTRE-PASSÉE : une contre-passée reste en historique (rien ne s'efface,
/// RG-11) et son `contrepassee_le` dit au poste que l'exercice peut être affecté
/// de nouveau. C'est un miroir de LECTURE : le poste y lit la carte
/// « Affectation du résultat » de l'onglet Clôtures, jamais il n'y écrit une
/// affectation de son cru (les siennes sont des pièces, `ecritures_local`).
///
/// ## Pourquoi une table, et pas le miroir des écritures
///
/// `ecritures_serveur_local` porte les lignes de la pièce, mais ni l'auteur, ni
/// la date de passation, ni la ventilation par poste, ni le statut « contre-passée »
/// de l'AFFECTATION (la contre-passation y est une pièce de plus, sans lien
/// explicite avec elle) : reconnaître une affectation à son libellé, dans une
/// langue, aurait pris pour affectation une pièce saisie à la main du même nom.
///
/// ## Reconnaître SA propre affectation, sans double
///
/// `piece_origine_id` est l'identifiant de la pièce que ce poste (ou un autre) a
/// envoyée (`pieces_saisie_local.id`) ; `NULL` pour une affectation passée au web.
/// Le poste qui reconnaît son identifiant dans cette colonne sait que la ligne et
/// sa propre pièce sont UNE affectation.
///
/// | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|
/// | `AffectationsRecuesDao`, SEUL, appelé par l'aligneur du catalogue | `AffectationResultatLocale` (la carte) | `CatalogueDescendantService` — table `affectations_resultat`, sous le droit de lecture M10 |
library;

import 'package:drift/drift.dart';

@DataClassName('AffectationRecue')
@TableIndex(name: 'idx_affectations_recues_annee', columns: {#annee})
class AffectationsResultatLocal extends Table {
  /// L'identifiant du SERVEUR : une affectation ne naît jamais ici.
  TextColumn get id => text()();

  /// L'année de l'exercice dont le résultat est affecté (N-1) : le poste garde
  /// ses propres identifiants d'exercice, l'année est la clé commune.
  IntColumn get annee => integer()();

  /// Signé : positif bénéfice, négatif perte (centimes).
  IntColumn get resultatCentimes => integer()();

  /// `AAAA-MM-JJ` — la date d'approbation des comptes, dans l'exercice N.
  TextColumn get dateApprobation => text()();

  IntColumn get reserveLegaleCentimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get autresReservesCentimes =>
      integer().withDefault(const Constant(0))();
  IntColumn get dividendesCentimes =>
      integer().withDefault(const Constant(0))();

  /// Bénéfice : le report à nouveau créditeur (121) ; perte : l'imputation sur le
  /// report à nouveau créditeur, comme au serveur.
  IntColumn get reportCrediteurCentimes =>
      integer().withDefault(const Constant(0))();

  /// Perte : le report à nouveau débiteur (129x).
  IntColumn get reportDebiteurCentimes =>
      integer().withDefault(const Constant(0))();

  /// Le numéro de la pièce d'affectation du SERVEUR.
  TextColumn get numeroPiece => text()();

  /// L'identifiant d'origine de la pièce du poste d'où elle vient, ou `NULL`.
  TextColumn get pieceOrigineId => text().nullable()();

  /// Le LOGIN de l'auteur (jamais l'identifiant du compte du serveur).
  TextColumn get auteurLogin => text().nullable()();

  DateTimeColumn get affecteeLe => dateTime()();

  /// Renseignée : l'affectation est contre-passée, l'exercice peut être affecté
  /// de nouveau.
  DateTimeColumn get contrepasseeLe => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
