/// Les PIÈCES SAISIES À LA MAIN sur le poste — v44, 28/10/2026 (D246 rouvert par
/// décision du PO : « les écritures saisies à la main sur un poste sont
/// partagées »).
///
/// Une ligne par pièce que le hub comptable a enregistrée par « Nouvelle
/// écriture » (brouillon, ou validée d'un geste). Son `id` est l'IDENTIFIANT
/// D'ORIGINE de la pièce : c'est lui que le poste envoie (`pieces_saisie`, file
/// d'envoi), que le serveur pose sur chaque ligne de SA pièce
/// (`ecritures_comptables.piece_origine_id`) et qui revient avec elle dans le
/// miroir `ecritures_serveur_local` — c'est ainsi que le poste reconnaît sa
/// propre pièce redescendue, sans jamais la compter deux fois.
///
/// ## Ce que cette table n'est PAS
///
/// Elle ne porte aucun montant : les lignes de la pièce sont dans
/// `ecritures_local` (le journal du poste), sous `numero_piece`. Elle ne marque
/// QUE les pièces de saisie manuelle — jamais celles d'un module (vente,
/// dépense, règlement, clôture), que le serveur recrée de leur document source.
/// Une pièce descendue du serveur n'y entre jamais : le poste ne renvoie pas ce
/// qu'il a reçu.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `MoteurComptable.saisirPiece`, seul | le hub (provenance), la reprise par le serveur |
library;

import 'package:drift/drift.dart';

@DataClassName('PieceSaisieLigne')
class PiecesSaisieLocal extends Table {
  /// L'identifiant d'origine — celui de l'opération `pieces_saisie`.
  TextColumn get id => text()();

  /// `CODE-AAAA-NNNNN` de la pièce du POSTE (`ecritures_local.numero_piece`).
  TextColumn get numeroPiece => text()();

  TextColumn get codeJournal => text()();

  /// `AAAA-MM-JJ`.
  TextColumn get datePiece => text()();

  TextColumn get libelle => text()();

  /// `brouillon` | `validee` — le statut donné à la saisie.
  TextColumn get statut => text()();

  DateTimeColumn get creeLe => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
