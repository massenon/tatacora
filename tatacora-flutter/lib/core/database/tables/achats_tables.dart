/// M7 Achats — LOCAL PUR depuis le 09/10/2026 (décision du PO : la source de
/// données de M7 est locale, après Paramètres et M6). Schéma v13, cinq tables
/// NEUVES, migration additive.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Table | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `fournisseurs_local` | `AchatsDao.creerFournisseur` / `modifierFournisseur`, seul auteur (modale « Fournisseur ») | l'écran Fournisseurs (liste, détail, export), le sélecteur de la commande, `AchatsDao.creerCommande` (clé étrangère) | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `commandes_achat_local` | `AchatsDao.creerCommande` (naissance), `envoyerCommande` / `cloturerCommande` (statut) et `AchatsDao.enregistrerReception` (statut déduit du verdict), seul auteur | l'écran Approvisionnement (commandes, dettes), l'écran Fournisseurs (commandes), la modale de réception, le rapprochement, les indicateurs | personne |
/// | `lignes_commande_achat_local` | `AchatsDao.creerCommande`, dans la même transaction que la commande — jamais modifiées ensuite | le montant (calculé), la modale de réception, le rapprochement, les besoins déjà commandés | personne |
/// | `bons_reception_local` | `AchatsDao.enregistrerReception`, seul auteur | l'onglet Réceptions, le détail d'une commande (« déjà reçu »), le rapprochement | personne |
/// | `lignes_bon_reception_local` | `AchatsDao.enregistrerReception`, dans la même transaction que le bon ET que les entrées de stock | la quantité « déjà reçue » (somme), le rapprochement | personne |
///
/// Aucun seeder, aucune migration ne sème de ligne : un fournisseur, une
/// commande ou une réception « d'usine » serait plausible, donc invisible.
///
/// ## `fournisseurs_local.actif` — l'archivage (v21, 12/10/2026, D63)
///
/// Le fournisseur « supprimé » est ARCHIVÉ (`actif = false`), jamais effacé :
/// `commandes_achat_local.fournisseur_id` est une clé étrangère, et effacer la
/// fiche rendrait illisible chaque commande qui la cite. Le geste est réversible
/// (« Restaurer »).
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `actif` | `AchatsDao.archiverFournisseur` / `restaurerFournisseur`, seul auteur (le défaut `true` est celui de la création) | la liste des fournisseurs (pastille « Archivé », bouton « Restaurer » ou « Supprimer »), le sélecteur de la modale de commande (actifs seulement), le lot d'archivage (un archivé n'est pas re-archivé) | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
///
/// Les fournisseurs d'AVANT la v21 naissent `actif = true` : c'est un FAIT, pas
/// une déduction — le geste d'archivage était refusé, aucun n'a donc été
/// archivé. Aucune date ni auteur d'archivage n'est ajouté : le serveur n'en
/// porte pas (`modifieLe` / `modifiePar` suivent l'`Auditable` du modèle).
///
/// ## Ce qui n'est PAS une colonne — jamais
///
/// * **Le montant d'une commande ni celui d'une ligne** : `quantité × prix`
///   se calcule des lignes (`calcul_achats.dart`). Une colonne le porterait
///   deux fois, et la seconde finirait par diverger.
/// * **La quantité « déjà reçue »** : somme des lignes de bons, jamais un
///   compteur incrémenté.
/// * **Le règlement d'un fournisseur ni sa dette** : le règlement est une
///   table à part (`reglements_fournisseur_local`, v20, D66), écrite par le seul
///   `ReglementsFournisseurDao` avec sa pièce comptable dans la même
///   transaction (règle du PO du 31/08/2026). La DETTE, elle, n'est jamais une
///   colonne : « Réglé » est la somme des règlements actifs, « Reste dû » le
///   montant moins ce réglé (`regles_reglement.dart`). Une commande n'a pas de
///   `montant_regle` ici — le serveur le recalcule de ses règlements, ce poste
///   ne le copie pas.
///
/// ## Unités
///
/// Les quantités sont des CENTIÈMES entiers (`quantite_centiemes`), les prix
/// unitaires des CENTIÈMES de franc entiers (`prix_unitaire_centimes`) : la
/// précision `DECIMAL(15,2)` du serveur, en entiers — aucune somme sur un
/// flottant. Le coût d'une entrée de stock, lui, est en dix-millièmes
/// (`mouvements_stock_local`) : la conversion est ×100, exacte.
///
/// ## Prix et libellé figés à l'ajout
///
/// Une ligne de commande porte le libellé et l'unité de l'article TELS QU'ILS
/// ÉTAIENT à la commande : renommer l'article au catalogue ne réécrit pas un
/// bon de commande remis au fournisseur. Même règle que le panier.
library;

import 'package:drift/drift.dart';

import 'stocks_tables.dart';
import 'utilisateurs_table.dart';

class FournisseursLocal extends Table {
  TextColumn get id => text()();
  TextColumn get raisonSociale => text()();

  /// Nullable au serveur : `null` n'est pas la chaîne vide. L'écran affiche
  /// « — », jamais un contact nommé « ».
  TextColumn get contact => text().nullable()();
  TextColumn get categorie => text().nullable()();
  TextColumn get conditionsPaiement => text().nullable()();

  /// Registre fermé (`excellent`, `bon`, `moyen`, `a_revoir`). `null` = « pas
  /// encore évalué », ce qui n'est PAS « À revoir ».
  TextColumn get evaluation => text().nullable()();

  DateTimeColumn get creeLe => dateTime()();

  /// Qui l'a créé (RG-15). Vraie clé étrangère ; le DAO refuse d'écrire sans
  /// auteur.
  TextColumn get creePar => text().references(UtilisateursLocal, #id)();
  DateTimeColumn get modifieLe => dateTime().nullable()();
  @ReferenceName('fournisseursModifies')
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  /// `fournisseurs.actif` : faux = ARCHIVÉ (voir l'en-tête). `true` à la
  /// création, comme le défaut du serveur. DÉCLARÉE EN DERNIER (v21) : une
  /// colonne ajoutée par `ALTER TABLE` se range en fin de table, et une base
  /// neuve doit avoir le même ordre qu'une base migrée.
  BoolColumn get actif => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class CommandesAchatLocal extends Table {
  TextColumn get id => text()();
  TextColumn get fournisseurId => text().references(FournisseursLocal, #id)();

  /// `AAAA-MM-JJ`. Un texte et non un instant : une date de commande n'a pas
  /// d'heure, et un fuseau ne doit pas la déplacer d'un jour.
  TextColumn get dateCommande => text()();

  /// Registre fermé de cinq valeurs (`StatutCommande`). Seuls `brouillon` et
  /// `envoyee` se posent à la création ; les trois autres sont PRODUITS par
  /// une réception (ou la clôture) réellement enregistrée.
  TextColumn get statut => text()();

  DateTimeColumn get creeLe => dateTime()();
  TextColumn get utilisateurId => text().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class LignesCommandeAchatLocal extends Table {
  TextColumn get id => text()();
  TextColumn get commandeId => text().references(CommandesAchatLocal, #id)();
  TextColumn get articleId => text().references(ArticlesLocal, #id)();

  /// FIGÉS à l'ajout (voir l'en-tête).
  TextColumn get articleLibelle => text()();
  TextColumn get uniteMesure => text()();

  IntColumn get quantiteCentiemes => integer()();
  IntColumn get prixUnitaireCentimes => integer()();

  /// Le rang de saisie : l'ordre d'une commande est celui de son auteur.
  IntColumn get rang => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class BonsReceptionLocal extends Table {
  TextColumn get id => text()();
  TextColumn get commandeId => text().references(CommandesAchatLocal, #id)();

  /// `AAAA-MM-JJ`.
  TextColumn get dateReception => text()();

  /// Le verdict RG-10 : `totale`, `partielle` ou `non_conforme`.
  TextColumn get conformite => text()();

  /// Le point qui a reçu l'entrée de stock. Le serveur ne le conserve pas
  /// (PA-39) ; ici il est écrit parce qu'il est LU : l'onglet Réceptions
  /// l'affiche (colonne « Point » de la vue).
  TextColumn get pointStockageId =>
      text().references(PointsStockageLocal, #id)();

  DateTimeColumn get creeLe => dateTime()();
  TextColumn get utilisateurId => text().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class LignesBonReceptionLocal extends Table {
  TextColumn get id => text()();
  TextColumn get bonId => text().references(BonsReceptionLocal, #id)();
  TextColumn get articleId => text().references(ArticlesLocal, #id)();
  IntColumn get quantiteCentiemes => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
