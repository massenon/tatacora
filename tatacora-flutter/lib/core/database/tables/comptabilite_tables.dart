/// M10 Comptabilité — MOTEUR LOCAL, réplique du serveur (10/10/2026, lot 1).
/// Schéma v15, SIX tables neuves, migration additive.
///
/// Règle du PO (10/10/2026) : le serveur est la RÉFÉRENCE, ce poste le
/// réplique en local (zéro réseau, bureau seulement). Les colonnes, les types
/// énumérés et les contraintes sont ceux des migrations du serveur
/// (`create_comptabilite`, `ajouter_numero_piece_aux_ecritures`) ; l'écart de
/// représentation est unique et nommé : les montants sont des CENTIMES
/// ENTIERS (le serveur écrit `DECIMAL(15,2)`), jamais un flottant.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Table | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `centres_cout_local` | `installerReferentielComptable`, seul auteur (les 7 centres du serveur) | le moteur (centre explicite, centre par défaut d'un compte), les états analytiques à venir | personne : zéro réseau |
/// | `journaux_local` | `installerReferentielComptable`, seul auteur (VTE, ACH, BQ, CAI, OD) | le moteur (résolution d'un code de journal), la séquence des pièces | personne |
/// | `plan_comptable_local` | `installerReferentielComptable` (import du fichier du PO, 1 332 comptes) et `MoteurComptable.creerCompte` (ajout d'un compte) | le moteur (compte inconnu, division, centre par défaut), `comptesDeCharge` | personne |
/// | `exercices_local` | `installerReferentielComptable` (exercice de l'année COURANTE, ouvert à chaque démarrage s'il manque ; écart assumé avec le serveur, D197 option (b)), `MoteurComptable.ouvrirExercice` et `cloturerExercice` | le moteur (exercice ouvert couvrant une date), le trigger RG-11 | personne |
/// | `ecritures_local` | `MoteurComptable` UNIQUEMENT (passer, valider, contrepasser) — jamais un module métier directement | le grand livre, la balance, les états (lots suivants) ; aujourd'hui : le moteur et ses tests | personne |
/// | `sequences_piece_local` | `ComptabiliteDao.numeroSuivant`, dans la transaction de la pièce | lui-même | personne |
///
/// Aucune ligne n'est semée par la migration : le référentiel est installé par
/// `installerReferentielComptable`, appelé au démarrage de l'application
/// (`referentielComptableProvider`), idempotent — jamais recopié à la main.
///
/// ## Ce qui n'est PAS une colonne — jamais
///
/// * **`evenements_posterieurs`** (exercice) : note libre saisie par le
///   Comptable au serveur ; aucun geste de ce lot ne l'écrit (piège 9). Elle
///   s'ajoute avec son écrivain.
/// * **Le résultat reporté, les soldes, les totaux de pièce** : calculés des
///   écritures validées, jamais stockés (PA-151).
/// * **`statut_sync`** : zéro réseau, annoncer une attente serait mentir.
///
/// ## Les contraintes sont celles du serveur
///
/// `CHECK (debit >= 0 AND credit >= 0)`, `CHECK (NOT (debit > 0 AND credit >
/// 0))` (une ligne est débit OU crédit), `CHECK (date_fin > date_debut)`, les
/// registres fermés de statuts. L'équilibre d'une PIÈCE ne s'exprime pas en
/// contrainte (il porte sur plusieurs lignes, PA-52) : il est tenu par le
/// moteur, qui le re-vérifie dans la transaction avant de rendre la main. Les
/// triggers de RG-11 sont dans `declencheurs_comptables.dart`.
library;

import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

class CentresCoutLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  /// `exploitation` ou `support` (nullable comme au serveur).
  TextColumn get type => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class JournauxLocal extends Table {
  TextColumn get id => text()();
  TextColumn get code => text().unique()();
  TextColumn get libelle => text()();

  @override
  Set<Column> get primaryKey => {id};
}

class PlanComptableLocal extends Table {
  TextColumn get id => text()();

  /// Le numéro du compte, tel qu'au fichier du PO (1 à 4 chiffres).
  TextColumn get numeroCompte => text().unique()();
  TextColumn get libelle => text()();

  /// Le PREMIER chiffre du numéro, dérivé et jamais saisi.
  TextColumn get classe => text()();

  /// `actif`/`passif`/`charge`/`produit`, ou `null` : dérivée là où une règle
  /// écrite la donne (6 = charge, 7 = produit), jamais devinée ailleurs.
  TextColumn get nature => text().nullable()();

  /// Suggestion de saisie UNIQUEMENT, jamais contraignante (RG-12) : sans elle
  /// et sans centre explicite, l'écriture est refusée.
  TextColumn get centreCoutDefautId =>
      text().nullable().references(CentresCoutLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class ExercicesLocal extends Table {
  TextColumn get id => text()();
  IntColumn get annee => integer().unique()();

  /// `AAAA-MM-JJ`. Un texte et non un instant : un exercice n'a pas d'heure et
  /// un fuseau ne doit pas le décaler d'un jour.
  TextColumn get dateDebut => text()();
  TextColumn get dateFin => text()();

  /// `ouvert`, `en_cloture` ou `cloture` (registre fermé du serveur).
  TextColumn get statut => text().withDefault(const Constant('ouvert'))();
  DateTimeColumn get dateCloture => dateTime().nullable()();

  /// Qui a clôturé (RG-15). Écrite par `MoteurComptable.cloturerExercice`.
  TextColumn get utilisateurClotureId =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK (date_fin > date_debut)',
    "CHECK (statut IN ('ouvert', 'en_cloture', 'cloture'))",
  ];

  @override
  Set<Column> get primaryKey => {id};
}

class EcrituresLocal extends Table {
  TextColumn get id => text()();
  TextColumn get exerciceId => text().references(ExercicesLocal, #id)();
  TextColumn get journalId => text().references(JournauxLocal, #id)();
  TextColumn get compteId => text().references(PlanComptableLocal, #id)();

  /// NOT NULL : une écriture sans centre de coût est impossible, pas seulement
  /// déconseillée (RG-12).
  TextColumn get centreId => text().references(CentresCoutLocal, #id)();

  /// `AAAA-MM-JJ`.
  TextColumn get dateEcriture => text()();
  TextColumn get libelle => text()();

  /// CENTIMES entiers (le serveur : `DECIMAL(15,2)`). Une ligne est débit OU
  /// crédit : l'autre vaut zéro.
  IntColumn get debitCentimes => integer().withDefault(const Constant(0))();
  IntColumn get creditCentimes => integer().withDefault(const Constant(0))();

  /// `brouillon` ou `validee`. `validee` est le point de non-retour de RG-11.
  TextColumn get statut => text().withDefault(const Constant('brouillon'))();

  /// Contre-passation (RG-11) : la ligne d'ORIGINE que celle-ci inverse. Jamais
  /// un UPDATE de l'originale.
  TextColumn get ecritureContrepasseeId =>
      text().nullable().references(EcrituresLocal, #id)();

  /// `CODE-AAAA-NNNNN`, partagé par toutes les lignes d'une pièce. `null` sur
  /// une contre-passation, comme au serveur (une pièce sans numéro alloué reste
  /// sans numéro, jamais un numéro inventé après coup).
  TextColumn get numeroPiece => text().withLength(max: 20).nullable()();

  DateTimeColumn get creeLe => dateTime()();

  /// Qui l'a écrite (RG-15). Vraie clé étrangère ; le moteur refuse d'écrire
  /// sans auteur.
  TextColumn get creePar => text().references(UtilisateursLocal, #id)();

  /// Écrites par la validation (brouillon -> validée) et par rien d'autre :
  /// une ligne validée ne se modifie plus.
  DateTimeColumn get modifieLe => dateTime().nullable()();
  @ReferenceName('ecrituresModifiees')
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  List<String> get customConstraints => [
    'CHECK (debit_centimes >= 0 AND credit_centimes >= 0)',
    'CHECK (NOT (debit_centimes > 0 AND credit_centimes > 0))',
    "CHECK (statut IN ('brouillon', 'validee'))",
  ];

  @override
  Set<Column> get primaryKey => {id};
}

/// Le compteur des numéros de pièce, par journal ET par année.
///
/// ## Compteur PERSISTÉ, jamais recalculé
///
/// Le serveur lit le maximum des numéros existants sous verrou. Ici, le
/// compteur est une ligne : incrémentée DANS la transaction de la pièce, donc
/// rendue par un rollback (aucun trou quand une pièce est refusée), et jamais
/// déduite d'un `MAX()` qu'une ligne purgée ou un import ferait reculer.
class SequencesPieceLocal extends Table {
  TextColumn get journalId => text().references(JournauxLocal, #id)();
  IntColumn get annee => integer()();

  /// Le dernier rang alloué (0 avant la première pièce de l'année).
  IntColumn get dernierRang => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {journalId, annee};
}
