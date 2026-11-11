/// M5 Bar — offline-first complet, POS prioritaire.
///
/// Extrait de `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — toute divergence
/// se corrige cote document ET cote code, jamais d'un seul cote.
library;

import 'package:drift/drift.dart';

/// `cartes_boisson_local` : écrite par `CatalogueDao` (saisie, enfilée) et,
/// depuis le lot F2b, par `AligneurCatalogue` (descente du catalogue, jamais
/// enfilée).
class CartesBoissonLocal extends Table {
  TextColumn get id => text()();
  TextColumn get articleId =>
      text()(); // référence articles_local (§8), pas de FK stricte Drift ici
  // car les deux tables peuvent être synchronisées à des
  // instants légèrement différents — cohérence vérifiée
  // applicativement, pas bloquée par une contrainte SQLite
  TextColumn get libelle => text()();
  TextColumn get categorie => text()(); // 'locale' | 'maison' | 'importee'
  RealColumn get prixVente => real()();

  /// `unites_vendables_par_unite_stock` du serveur (v30, 21/10/2026) : combien
  /// d'unités VENDUES font une unité de STOCK (un casier de 24 = `24.0000`).
  /// Texte décimal tel que le serveur l'envoie, jamais un `double`. `null` :
  /// pas encore reçu — le stock estimé ignore alors la ligne et le DIT.
  TextColumn get unitesVendables => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class VentesBarLocal extends Table {
  TextColumn get id =>
      text()(); // UUID client — POS doit fonctionner sans réseau (05_MODULE_SPECIFICATIONS.md §M5)
  TextColumn get clientId =>
      text().nullable()(); // EF-M5-06, imputation chambre optionnelle
  DateTimeColumn get dateVente => dateTime()();
  RealColumn get montant => real()();
  TextColumn get statutSync =>
      text().withDefault(const Constant('en_attente_synchronisation'))();
  // Valeur par défaut DIFFÉRENTE des autres tables : une vente bar est très
  // majoritairement créée hors ligne en pratique (comptoir, connectivité
  // variable) — le statut par défaut reflète ce cas d'usage dominant plutôt
  // que de supposer une connexion présente par défaut.

  @override
  Set<Column> get primaryKey => {id};
}

class LignesVenteBarLocal extends Table {
  TextColumn get id => text()();
  TextColumn get venteId => text().references(VentesBarLocal, #id)();
  TextColumn get boissonId => text().references(CartesBoissonLocal, #id)();
  IntColumn get quantite => integer()();
  RealColumn get prixUnitaire => real()();

  @override
  Set<Column> get primaryKey => {id};
}
