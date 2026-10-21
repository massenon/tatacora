/// M4 Restaurant — LOCAL PUR depuis le 09/10/2026 (décision du PO : la source de
/// données de M4 est locale, après Paramètres, M6 et M7). Schéma v14, QUATRE
/// tables neuves, migration additive.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Table | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `menus_local` | `RestaurantDao.enregistrerMenu`, seul auteur (modale de saisie d'un menu) | l'onglet des menus, le sélecteur de la modale de plat, la carte du restaurant (type du menu = catégorie) | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `recettes_local` | `RestaurantDao.enregistrerRecette`, seul auteur (modale de saisie d'une fiche) | l'onglet des fiches, le sélecteur de la modale de plat, la carte (libellé de la fiche) | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `ingredients_recette_local` | `RestaurantDao.remplacerComposition`, seul auteur, dans UNE transaction avec la fiche (remplacement intégral, jamais fusion) | le coût matière, les portions vendables, la carte, la fiche détail d'un plat | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
/// | `plats_local` | `RestaurantDao.enregistrerPlat`, seul auteur (modale de saisie d'un plat) | l'onglet du catalogue, la carte, le rayon Restaurant du point de vente (`CatalogueDao`), la vérification d'existence d'une ligne de panier (`PanierDao`) | `AligneurCatalogue` (descente du catalogue, lot F2b, 15/10/2026 — jamais enfilé) |
///
/// Aucun seeder, aucune migration ne sème de ligne : un menu, une fiche ou un
/// plat « d'usine » serait plausible, donc invisible — et un plat posé par le
/// code se vendrait au comptoir à un prix que personne n'a décidé.
///
/// ## Ce qui n'est PAS une colonne — jamais
///
/// * **Le coût matière, la marge, les portions vendables, le taux de
///   couverture** : calculés des fiches, des mouvements de stock et du coût
///   moyen pondéré (`calcul_restaurant.dart`). Une colonne les porterait deux
///   fois, et la seconde finirait par diverger de la première
///   (`recettes.cout_matiere_calcule` valait zéro pour tout le monde au
///   serveur : c'est le défaut PA-126).
/// * **La catégorie du plat** : elle est celle de son menu (`menus.type`), comme
///   l'API. La vue Blade, elle, porte une colonne `plats.categorie` de dix
///   valeurs — arbitrage OUVERT (D100), non tranché ici.
/// * **Le lien direct à un article** (`article_id` + conditionnement) : le geste
///   de rattachement direct n'est pas porté sur ce poste. Une colonne que rien
///   n'écrirait vaudrait `null` pour tout le monde et alimenterait un badge qui
///   ne s'afficherait jamais (piège 9). Elle s'ajoute (v15) avec son écrivain.
/// * **La marque « composition provisoire » d'une fiche** : aucun référentiel de
///   démonstration ne pose de grammage sur ce poste ; elle ne vaudrait jamais
///   `true`.
/// * **La disponibilité du jour** (plat retiré de la carte) : aucune colonne,
///   et le geste est refusé avec sa raison (D15).
/// * **Aucun `statut_sync`** : annoncer une attente sans fin serait mentir.
///
/// ## Unités
///
/// * `prix_vente` : des FRANCS ENTIERS. Le franc CFA n'a pas de sous-unité en
///   circulation, et le point de vente manipule des entiers (`ArticleVendable`).
///   Le serveur accepte deux décimales : un prix à fraction de franc est
///   REFUSÉ ici, pas arrondi.
/// * `quantite_milliemes` : la quantité d'un ingrédient PAR PORTION, en
///   millièmes de l'unité de l'article (`DECIMAL(10,3)` au serveur, qui
///   exprime les recettes en grammes et centilitres).
///
/// ## Prix et libellé figés à l'ajout
///
/// Ces tables sont des RÉFÉRENTIELS : modifier un prix ne réécrit pas une ligne
/// de panier déjà saisie, qui porte son prix et son libellé figés (règle du
/// panier). Les deux marques de prix sont des faits du plat, pas de la vente.
library;

import 'package:drift/drift.dart';

import 'stocks_tables.dart';
import 'utilisateurs_table.dart';

class MenusLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  /// Registre fermé (`local`, `europeen`, `special`) — celui de l'`enum` du
  /// serveur (`Menu::TYPES`), vérifié par le DAO et relu du serveur par un
  /// test.
  TextColumn get type => text()();

  /// `AAAA-MM-JJ`, ou `null` pour un menu permanent. Un texte et non un
  /// instant : une saison n'a pas d'heure, et un fuseau ne doit pas la
  /// déplacer d'un jour. Les dates ENCADRENT la saison, elles ne la déclarent
  /// pas — et `null` n'est jamais remplacé par une borne arbitraire.
  TextColumn get dateDebut => text().nullable()();
  TextColumn get dateFin => text().nullable()();

  DateTimeColumn get creeLe => dateTime()();

  /// Qui l'a créé (RG-15). Vraie clé étrangère ; le DAO refuse d'écrire sans
  /// auteur.
  TextColumn get creePar => text().references(UtilisateursLocal, #id)();
  DateTimeColumn get modifieLe => dateTime().nullable()();
  @ReferenceName('menusModifies')
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}

class RecettesLocal extends Table {
  TextColumn get id => text()();
  TextColumn get libelle => text()();

  DateTimeColumn get creeLe => dateTime()();
  TextColumn get creePar => text().references(UtilisateursLocal, #id)();
  DateTimeColumn get modifieLe => dateTime().nullable()();
  @ReferenceName('recettesModifiees')
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};

  /// v35 (21/10/2026) : la composition a été posée, jamais pesée.
  /// `null` ou `false` = composition pesée (nullable à dessein).
  BoolColumn get compositionProvisoire =>
      boolean().nullable().withDefault(const Constant(false))();
}

/// La composition d'une fiche technique : de VRAIES clés étrangères vers les
/// articles de stock, jamais du texte libre (PA-23). C'est ce lien — et lui
/// seul — qui rend un plat décrémentable.
class IngredientsRecetteLocal extends Table {
  TextColumn get recetteId => text().references(RecettesLocal, #id)();
  TextColumn get articleId => text().references(ArticlesLocal, #id)();

  /// Millièmes de l'unité de l'article, STRICTEMENT positifs : un ingrédient à
  /// zéro n'est pas un ingrédient, c'est une ligne à retirer.
  IntColumn get quantiteMilliemes => integer()();

  /// Clé primaire composite, comme `ingredients_recette` : un article ne figure
  /// qu'une fois dans une fiche.
  @override
  Set<Column> get primaryKey => {recetteId, articleId};
}

class PlatsLocal extends Table {
  TextColumn get id => text()();

  /// Vraies clés étrangères, toutes deux obligatoires : le menu porte la
  /// catégorie et la saison, la fiche porte la composition.
  TextColumn get menuId => text().references(MenusLocal, #id)();
  TextColumn get recetteId => text().references(RecettesLocal, #id)();

  TextColumn get libelle => text()();

  /// Francs entiers (voir l'en-tête).
  IntColumn get prixVente => integer()();

  /// PA-161 (b) — le tarif a été POSÉ faute de relevé. C'est une DÉCISION, elle
  /// se coche à la saisie du plat.
  BoolColumn get prixProvisoire =>
      boolean().withDefault(const Constant(false))();

  /// PA-161 (b) — le tarif imprimé a été corrigé à la main. C'est un FAIT, il
  /// se DÉDUIT (`marquesDePrix` dans `calcul_restaurant.dart`) quand le prix
  /// d'un plat marqué provisoire change : jamais une case à cocher.
  BoolColumn get prixCorrigeMain =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get creeLe => dateTime()();
  TextColumn get creePar => text().references(UtilisateursLocal, #id)();
  DateTimeColumn get modifieLe => dateTime().nullable()();
  @ReferenceName('platsModifies')
  TextColumn get modifiePar =>
      text().nullable().references(UtilisateursLocal, #id)();

  @override
  Set<Column> get primaryKey => {id};
}
