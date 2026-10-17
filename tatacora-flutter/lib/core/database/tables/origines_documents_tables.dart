/// L'ORIGINE des documents descendus d'autres postes (lot F4, décision du
/// Product Owner du 17/10/2026, « NE PLUS LIMITER »).
///
/// Une ligne par document REÇU du serveur : son identifiant, sa table, le
/// poste qui l'a saisi (`null` = saisi au serveur, PWA). Un document SANS
/// ligne ici a été saisi sur CE poste.
///
/// ## Pourquoi c'est une donnée de sécurité, et pas un affichage
///
/// Un document descendu ne porte AUCUNE pièce comptable locale (décision Q1 :
/// le journal du poste ne tient que ses propres pièces ; le serveur a passé
/// celle du document). Les gestes qui passent une pièce sur un document sans
/// pièce — le rattrapage d'une dépense — doivent donc savoir qu'il est
/// descendu, sans quoi ils le compteraient une seconde fois.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `AligneurCatalogue` (descente), SEUL auteur | le rattrapage des dépenses (refus), les listes (poste d'origine) |
library;

import 'package:drift/drift.dart';

@DataClassName('OrigineDocumentLigne')
class OriginesDocumentsLocal extends Table {
  /// Le nom au registre du serveur (`ventes`, `depenses`…).
  TextColumn get tableServeur => text()();

  /// L'identifiant LOCAL du document.
  TextColumn get entiteId => text()();

  /// Le poste qui l'a saisi, ou `null` (saisi au serveur).
  TextColumn get posteOrigine => text().nullable()();
  DateTimeColumn get recuLe => dateTime()();

  @override
  Set<Column> get primaryKey => {tableServeur, entiteId};
}
