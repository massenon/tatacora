/// FACTURE PROFORMA — document commercial NON FISCAL du poste (PO, 07/11/2026,
/// schéma v52). Voir `docs/SPEC_FACTURE_PROFORMA.md`.
///
/// Trois tables NEUVES, locales, créées HORS LIGNE comme tout le poste ; aucune
/// colonne MECeF, QR ou normalisation (une proforma n'en a jamais). Le numéro
/// définitif `N°0045 FP-GCN/2026` est attribué par le SERVEUR ; au poste, le
/// numéro est PROVISOIRE (`PROV-FP-AAAA-NNNNN`) jusqu'à l'accusé.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';

class ProformasLocal extends Table {
  /// UUID né ICI : c'est lui qui rend le rejeu idempotent.
  TextColumn get id => text()();

  /// `null` pour un brouillon (le numéro naît à l'ÉMISSION) ; `PROV-FP-…` après
  /// l'émission hors ligne ; `N°0045 FP-GCN/2026` après l'accusé du serveur.
  /// `unique()` : jamais deux numéros identiques (les NULL ne se comparent pas).
  TextColumn get numero => text().nullable().unique()();

  /// La RÉFÉRENCE FACTURE du réglage, copiée à l'émission (la rendre au serveur
  /// ne change rien : lui seul numérote).
  TextColumn get reference => text().nullable()();

  /// `brouillon` | `emise` | `convertie` | `annulee` (« expirée » est DÉRIVÉ).
  TextColumn get statut => text()();

  TextColumn get clientId => text().nullable().references(ClientsLocal, #id)();

  /// Nom, téléphone et IFU COPIÉS : le document porte ce qu'il portait le jour
  /// de l'émission, même si la fiche change.
  TextColumn get clientNom => text()();
  TextColumn get clientTelephone => text().nullable()();
  TextColumn get clientIfu => text().nullable()();
  TextColumn get objet => text().nullable()();

  /// `null` tant que brouillon.
  DateTimeColumn get dateEmission => dateTime().nullable()();

  /// La ville du lieu d'émission (réglage descendu), copiée à l'émission.
  TextColumn get ville => text().nullable()();

  /// La validité, calculée à l'ÉMISSION et ENREGISTRÉE : un changement ultérieur
  /// du réglage ne touche pas une proforma déjà émise.
  DateTimeColumn get valideJusquAu => dateTime().nullable()();

  /// Le total en FCFA entiers (somme des montants des lignes).
  IntColumn get total => integer().withDefault(const Constant(0))();

  /// La facture issue de la conversion (pièce locale), `null` sinon.
  TextColumn get factureId => text().nullable()();

  TextColumn get motifAnnulation => text().nullable()();

  /// `libre` | `location` | `tourisme` | `hebergement` | `evenement`.
  TextColumn get sourceModule => text().withDefault(const Constant('libre'))();
  TextColumn get sourceId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class LignesProformaLocal extends Table {
  TextColumn get id => text()();
  TextColumn get proformaId => text().references(ProformasLocal, #id)();
  IntColumn get position => integer()();
  TextColumn get designation => text()();
  IntColumn get quantite => integer()();

  /// Prix unitaire TTC, FCFA entiers.
  IntColumn get prixUnitaire => integer()();
  IntColumn get montant => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le compteur des numéros PROVISOIRES du poste, par année — jamais déduit du
/// nombre de lignes (un numéro ne se réemploie pas, même si la proforma disparaît).
class SequencesProformaLocal extends Table {
  IntColumn get annee => integer()();
  IntColumn get dernierNumero => integer()();

  @override
  Set<Column> get primaryKey => {annee};
}
