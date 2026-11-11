/// Le JOURNAL DE RÉCEPTION du poste — schéma v37, UNE table neuve, migration
/// additive.
///
/// ## Pourquoi elle existe (demande du PO, 26/10/2026)
///
/// « Le poste doit avoir dans sa page de synchronisation une partie de
/// RÉCEPTION avec toutes les informations reçues, les ÉCHECS, les RELANCES, les
/// CORRECTIONS : identifier la CAUSE des échecs, CORRIGER et RELANCER. » Avant
/// elle, la descente ne gardait que son bilan (des compteurs et vingt motifs)
/// et, pour les éléments à reprendre, des clés `element_differe:*` : ni
/// l'historique de ce qui était arrivé, ni la cause d'un refus.
///
/// ## Une ligne par élément reçu
///
/// Clé : (table du serveur, identifiant de l'élément). Chaque tentative
/// d'alignement met la ligne à jour (issue, cause, nombre de tentatives) ; une
/// nouvelle version de l'élément (autre `modifie_le`) repart à une tentative.
/// `element_json` garde l'élément reçu TANT QU'IL RESTE À TRAITER (en attente,
/// conservé, refusé) : c'est ce que « Relancer » rejoue ; il est vidé dès que
/// l'élément est aligné.
///
/// ## Rétention bornée
///
/// 30 jours pour les éléments alignés, 5 000 lignes au plus (les alignés les
/// plus anciens partent d'abord) : `JournalReceptionDao.purger`, appelé en fin
/// de descente. Un élément encore à traiter n'est jamais purgé par l'âge.
///
/// | Qui l'écrit | Qui la lit |
/// |---|---|
/// | `JournalReceptionDao`, appelé par `DescenteCatalogue` SEULE (jamais l'aligneur, jamais la file d'envoi) | l'écran de synchronisation, partie « Réception » |
///
/// Le journal n'enfile RIEN : ce qui descend du serveur n'y remonte jamais.
library;

import 'package:drift/drift.dart';

@DataClassName('JournalReceptionLigne')
class JournalReceptionLocal extends Table {
  /// Le nom au registre du serveur (`articles`, `clients`…) ; `inconnue` pour
  /// un élément dont la table est illisible.
  TextColumn get tableServeur => text()();
  TextColumn get elementId => text()();

  /// `aligne`, `conserve`, `attente` ou `refuse`.
  TextColumn get issue => text()();

  /// Le code de la cause (`CauseReception.code`).
  TextColumn get cause => text()();

  /// La phrase de l'aligneur ; vide pour un élément aligné.
  TextColumn get motif => text().withDefault(const Constant(''))();

  /// Le champ fautif, en français, quand la cause le nomme.
  TextColumn get champ => text().nullable()();

  /// La table (nom serveur) de l'élément lié qui manque.
  TextColumn get dependance => text().nullable()();

  /// Un nom lisible de l'élément (libellé, raison sociale…).
  TextColumn get etiquette => text().nullable()();

  /// Le poste qui a saisi le document (documents des autres postes).
  TextColumn get posteOrigine => text().nullable()();

  /// Le `modifie_le` de la version reçue (texte du serveur).
  TextColumn get modifieLeServeur => text().withDefault(const Constant(''))();
  IntColumn get tentatives => integer().withDefault(const Constant(1))();
  DateTimeColumn get recuLe => dateTime()();
  DateTimeColumn get derniereTentativeLe => dateTime()();

  /// L'élément reçu, tant qu'il reste à traiter.
  TextColumn get elementJson => text().nullable()();

  @override
  Set<Column> get primaryKey => {tableServeur, elementId};

  @override
  List<String> get customConstraints => [
    "CHECK (issue IN ('aligne', 'conserve', 'attente', 'refuse'))",
    'CHECK (tentatives >= 1)',
  ];
}
