/// M6 Stocks — LOCAL PUR depuis le 09/10/2026 (décision du PO : la source de
/// données de M6 est locale).
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Table | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `points_stockage_local` | `StocksDao.creerPoint`, seul auteur (modale « Mouvement » et « Nouvel article ») | l'écran Stocks (filtre de point), les deux modales, la fiche de stock | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `articles_local` | `StocksDao.creerArticle` / `modifierArticle`, seul auteur (modale « Nouvel article ») | l'écran Stocks, la fiche, M7 (besoins), M11 (indicateurs) — tous par `StocksApi.etat` | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `mouvements_stock_local` | `StocksDao.ajouterMouvement`, seul auteur — appelé par la modale « Mouvement » ET, depuis la v13, par `AchatsDao.enregistrerReception` (entrée NON valorisée depuis le 12/10/2026, D132 — comme le serveur —, dans la transaction de la réception) | l'état (solde, coût moyen pondéré), le journal, la fiche | personne |
///
/// Aucun seeder, aucune migration ne sème de ligne : un point, un article ou
/// un mouvement posé « d'usine » serait plausible, donc invisible.
///
/// ## Ce que le stock n'est PAS : une colonne
///
/// Ni le stock, ni le coût moyen pondéré, ni le dernier prix d'achat ne sont
/// stockés. Le stock est la somme signée des mouvements ; le coût moyen
/// pondéré est REJOUÉ depuis les entrées valorisées, dans l'ordre où elles
/// ont été écrites ; le dernier prix d'achat est le coût de la dernière entrée
/// valorisée. Une colonne les porterait deux fois, et la seconde finirait par
/// diverger de la première (le défaut qui a fait écrire PA-126 pour
/// `clients_local.solde`).
///
/// ## Quantités et coûts : des entiers, convertis une seule fois
///
/// `quantite` et `seuil_alerte` sont des `REAL` hérités de la v1, qu'une
/// migration additive ne peut pas changer de type. Ils ne portent JAMAIS que
/// des centièmes exacts, et le DAO les convertit en entiers (centièmes) à la
/// lecture, une fois — aucune somme ne se fait sur un `REAL`. Les coûts
/// unitaires, eux, sont stockés en entiers de dix-millièmes de franc
/// (`cout_unitaire_dix_milliemes`) : la précision du coût moyen pondéré du
/// serveur (`DECIMAL(15,4)`).
///
/// ## Aucune écriture comptable
///
/// Le poste tient une comptabilité depuis le 10/10/2026 (`MoteurComptable`,
/// `ecritures_local`), mais AUCUN mouvement de stock n'y est comptabilisé, état
/// du 12/10/2026. Un mouvement de stock, même valorisé, n'est pas un mouvement
/// d'argent — la dépense ou le règlement fournisseur qui le justifie est
/// ailleurs — et aucune valorisation comptable (variation de stock, comptes
/// 603x) n'est produite ici. L'écran le dit.
library;

import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

class PointsStockageLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  /// v12 — le type du point (`magasin`, `cuisine`, `bar`, `garage`), registre
  /// fermé côté domaine. Nullable comme au serveur : un point sans type reste
  /// un point valide.
  TextColumn get type => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class ArticlesLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  /// `NOT NULL` hérité de la v1 : une catégorie « non renseignée » s'écrit
  /// chaîne vide, que le domaine lit comme `null`.
  TextColumn get categorie => text()();
  TextColumn get uniteMesure => text()();

  /// Centièmes exacts (voir l'en-tête).
  RealColumn get seuilAlerte => real()();

  /// v12 — le mode de suivi, registre fermé (`permanent` / `journalier`).
  /// Défaut `permanent` : tout article existant est suivi en stock, comme au
  /// serveur (`Article::estSuiviEnStock`).
  TextColumn get suivi => text().withDefault(const Constant('permanent'))();

  /// v12 — le point de RATTACHEMENT de l'article. ⚠ Ce n'est PAS la portée de
  /// son stock : le stock se raisonne par couple (article, point), dans les
  /// mouvements. Nul = « jamais rattaché ».
  TextColumn get pointStockageId =>
      text().nullable().references(PointsStockageLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class MouvementsStockLocal extends Table {
  TextColumn get id => text()();
  TextColumn get articleId => text().references(ArticlesLocal, #id)();
  TextColumn get pointId => text().references(PointsStockageLocal, #id)();
  TextColumn get typeMouvement =>
      text()(); // 'entree' | 'sortie' | 'perte' | 'inventaire'

  /// Centièmes exacts, TOUJOURS positifs pour `entree` / `sortie` / `perte` ;
  /// signée pour `inventaire` (l'écart constaté), comme au serveur.
  RealColumn get quantite => real()();
  TextColumn get motif => text()();
  DateTimeColumn get dateMouvement => dateTime()();

  /// ⚠ PIÈGE DU SCHÉMA (PA-134). Le défaut `en_attente_synchronisation`
  /// décrirait une attente sans fin : le poste ne parle à aucun serveur. Il ne
  /// peut pas être changé sans recréer la table (migration interdite), donc
  /// `StocksDao` écrit TOUJOURS `local` — un test l'impose — et aucun écran ne
  /// lit cette colonne.
  TextColumn get statutSync =>
      text().withDefault(const Constant('en_attente_synchronisation'))();

  /// v12 — le coût d'achat unitaire de CETTE entrée, en dix-millièmes de
  /// franc. Nul pour une sortie, une perte, une régularisation, et pour un
  /// simple transfert entre points (qui ne revalorise rien). Figé à l'ajout :
  /// il ne se corrige pas, un mouvement est en ajout seul.
  IntColumn get coutUnitaireDixMilliemes => integer().nullable()();

  /// v12 — qui (RG-15). Vraie clé étrangère ; le DAO refuse d'écrire sans
  /// auteur, la colonne n'est nullable que parce qu'`ALTER TABLE` l'exige.
  TextColumn get utilisateurId =>
      text().nullable().references(UtilisateursLocal, #id)();

  /// v12 — RG-06 : la sortie a été forcée alors que le disponible ne la
  /// couvrait pas. C'est la trace nominative de la décision (avec
  /// [utilisateurId] et [dateMouvement]) : ce poste n'a pas de journal d'audit.
  BoolColumn get ruptureForcee =>
      boolean().withDefault(const Constant(false))();

  /// v12 — le rang d'écriture, strictement croissant. Le coût moyen pondéré
  /// dépend de l'ORDRE des entrées : il se rejoue par ce rang, jamais par la
  /// date (une horloge qui recule ne doit pas réordonner l'histoire).
  IntColumn get ordre => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
