/// L'HISTORIQUE DES PRIX de la carte du bar et du restaurant — schéma v38, UNE
/// table neuve, migration additive.
///
/// ## Pourquoi elle existe (décision du PO, 26/10/2026)
///
/// « Le poste fait ce que le web fait + synchronisation. » Les écrans « Historique
/// des prix » (bar et restaurant) et « Prix » (restaurant) étaient refusés faute
/// de table de trace : le serveur écrit `historique_prix_carte` à chaque changement
/// de prix (`CarteBoissonObserver`, `PlatObserver`, par `TraceurHistoriquePrix`),
/// le poste n'écrivait rien. Rendre une liste vide aurait dit « aucun changement
/// de prix » — un fait, et un fait faux dès la première modification.
///
/// ## Un miroir de la table du serveur
///
/// Mêmes colonnes : `source` (`carte_boisson` | `plat`), `source_id` (SANS clé
/// étrangère : l'article peut descendre après sa trace, et la trace doit rester
/// lisible sans lui), `champ` (`prix_vente` | `prix_corrige_main`), ancien et
/// nouveau en chaîne `decimal:2` (« 1500.00 » ; la marque en « 0.00 »/« 1.00 »),
/// et `par` (le LOGIN, comme la colonne « Par » de la vue).
///
/// ## Deux origines pour une même trace
///
///  * **le poste** : `HistoriquePrixCarteDao.tracer` écrit une ligne dans la
///    transaction qui change le prix (`recu_du_serveur = false`) ;
///  * **le serveur** : la descente (`GET /referentiels`) rapporte les traces de
///    TOUS les postes et de la PWA. Quand le serveur a appliqué le changement que
///    ce poste lui a poussé, il a écrit SA trace : la descente la rapproche de la
///    trace locale équivalente (même article, même champ, mêmes valeurs) et la
///    ADOPTE (`recu_du_serveur = true`, date et auteur du serveur) au lieu de
///    l'ajouter — sans quoi chaque changement apparaîtrait deux fois.
///
/// La trace n'est pas POUSSÉE : le serveur est son unique auteur (les
/// observateurs), la lui envoyer en ferait un second auteur.
///
/// | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|
/// | `HistoriquePrixCarteDao` SEUL (`tracer` pour le poste, `inscrireDescendue` pour la descente — l'aligneur l'appelle, il n'écrit pas lui-même) | les modales « Historique des prix » du bar (`BoissonsApi`) et du restaurant (`RestaurantApi`) | `AligneurCatalogue` (table `historique_prix_carte`) |
library;

import 'package:drift/drift.dart';

@DataClassName('TracePrixLigne')
class HistoriquePrixCarteLocal extends Table {
  TextColumn get id => text()();

  /// `carte_boisson` ou `plat` (`HistoriquePrixCarte::SOURCE_*`).
  TextColumn get source => text()();

  /// Le prix de CET article — `cartes_boisson_local.id` ou `plats_local.id`. Pas
  /// une clé étrangère (voir l'entête).
  TextColumn get sourceId => text()();

  /// `prix_vente` ou `prix_corrige_main` (`HistoriquePrixCarte::CHAMP_*`).
  TextColumn get champ => text()();

  /// `decimal:2` en chaîne, `null` : « il n'y avait pas de valeur » (« — »).
  TextColumn get ancienPrix => text().nullable()();
  TextColumn get nouveauPrix => text().nullable()();

  /// Le login de qui a changé le prix ; `null` : « — », jamais un compte inventé.
  TextColumn get par => text().nullable()();

  /// L'instant du changement — celui du poste, puis celui du serveur une fois la
  /// trace adoptée.
  DateTimeColumn get creeLe => dateTime()();

  /// `false` : écrite par CE poste, que le serveur n'a pas (encore) confirmée ;
  /// `true` : reçue du serveur, ou adoptée.
  BoolColumn get recuDuServeur =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (source IN ('carte_boisson', 'plat'))",
    "CHECK (champ IN ('prix_vente', 'prix_corrige_main'))",
  ];
}
