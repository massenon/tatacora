/// Panier et lignes de panier — **portage d'une PROPOSITION, pas d'une décision.**
///
/// ══════════════════════════════════════════════════════════════════════════
/// ⚠ AVERTISSEMENT — LIRE AVANT TOUTE REPRISE DE CE FICHIER
/// ══════════════════════════════════════════════════════════════════════════
///
/// Le modèle porté ici vient de `docs/PROPOSITION_MODELE_PANIER_POS.md`, qui
/// est **en attente de ratification par l'Architecte**. Trois questions y sont
/// ouvertes et **aucune n'est tranchée** :
///
///  - **Q1** — comment rattacher une ligne à son catalogue d'origine ? Le
///    document propose quatre clés étrangères nullables contraintes par un
///    `CHECK` (option A) et **exclut** l'identifiant polymorphe libre
///    (option C, le défaut de `commandes_restaurant.table_ou_chambre_id`).
///  - **Q2** — comment garantir « un seul panier ouvert par séjour » alors que
///    MySQL n'a pas d'index partiel ?
///  - **Q3** — l'hébergement est-il une ligne de panier ?
///
/// **Porter ce modèle dans un second client le rend plus difficile à amender.**
/// C'est pourquoi tout ce qui dépend de Q1, Q2 et Q3 est isolé derrière des
/// points **nommés**, plutôt que dispersé :
///
///  | Question | Où elle atterrit, et nulle part ailleurs |
///  |---|---|
///  | Q1 | `lib/features/pos/domain/entities/reference_catalogue.dart` + les deux colonnes `moduleSource` / `codeArticle` ci-dessous |
///  | Q2 | `lib/features/pos/domain/unicite_panier_ouvert.dart` |
///  | Q3 | `lib/features/pos/domain/place_hebergement.dart` |
///
/// ## Trois divergences assumées avec le document, et pourquoi
///
/// 1. **`reservationId`, pas `sejourId`.** Le client Flutter n'a aucune table
///    `sejours` — elle est hors du périmètre offline (`app_database.dart` §0).
///    Le prototype `panier-engine.js` rattache lui aussi au `reservation_id`.
///    Le jour où `sejours` sera répliquée, c'est **cette colonne** qui change,
///    pas la logique.
/// 2. **`quantite` est un entier**, là où le document écrit `DECIMAL(10,2)`.
///    Une consommation de bar ou de restaurant se compte, elle ne se pèse pas,
///    et le seul piège connu sur ce champ — une quantité saisie à zéro
///    facturée à une unité — se traite mieux sur un entier. À rouvrir si un
///    catalogue au poids entre au panier.
/// 3. **Aucune contrainte `CHECK`.** SQLite en accepte, mais la garantie est
///    portée par le domaine (`OuvrirPanier`) pour rester **la même des deux
///    côtés** : un refus qui n'existe qu'ici serait un refus que le serveur ne
///    ferait pas, et l'écart se découvrirait à la première synchronisation.
///
/// ## Ce panier ne part PAS au serveur, et ce n'est pas un oubli
///
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients`. Une opération sur `paniers` serait **rejetée à
/// chaque tentative**, indéfiniment. Inscrire un panier à `sync_queue`
/// produirait donc un badge « en attente de synchronisation » sur quelque
/// chose qui ne partira jamais — exactement l'indicateur qui affirme un état
/// qu'il n'a pas vérifié (PA-59 / PA-60 / PA-61).
///
/// La colonne `statutTransmission` dit donc la vérité : `non_transmissible`.
/// Elle changera le jour où le modèle sera ratifié **et** la table ajoutée au
/// registre du serveur — les deux, pas l'un des deux.
library;

import 'package:drift/drift.dart';

import 'caisse_tables.dart';
import 'hebergement_tables.dart';
import 'tables_pos_table.dart';

/// Un panier — la structure ; le point de vente n'en est qu'un écran.
///
/// La différence entre les deux POS demandés se réduit à deux attributs :
/// `typeVente` et `reservationId`. Deux flux séparés dupliqueraient la logique
/// de rattachement des consommations, et c'est cette duplication qui produit
/// ensuite les divergences de comportement entre le bar et la réception.
class PaniersLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// `comptant` | `sur_sejour`.
  TextColumn get typeVente => text()();

  /// Renseigné **si et seulement si** `typeVente = 'sur_sejour'`.
  ///
  /// La clé étrangère est réelle : un panier de séjour dont la réservation
  /// n'existe pas localement serait orphelin, et ses consommations
  /// n'atteindraient jamais la facture de départ. C'est la contrepartie
  /// acceptée d'un POS hébergés qui n'a de sens que pour un client présent —
  /// donc pour une réservation déjà en base locale.
  TextColumn get reservationId =>
      text().nullable().references(ReservationsLocal, #id)();

  /// Nom affiché du client. Copié, comme le libellé d'une ligne : un panier
  /// vit plusieurs jours et l'écran doit rester lisible sans jointure.
  TextColumn get clientNom => text().nullable()();

  /// **Où se trouve l'argent**, jamais ce qui est vendu.
  ///
  /// La confusion entre les deux a déjà coûté un défaut (PA-79) : tant que le
  /// poste était choisi par le filtre de catalogue, changer de filtre changeait
  /// de caisse — donc vidait le panier —, ce qui interdisait une addition
  /// mêlant bar et restaurant.
  TextColumn get pointVente => text().nullable()();

  /// La table de salle qui porte ce panier — **nul au comptoir**.
  ///
  /// C'est une vraie clé étrangère et non plus un texte libre : « T3 », « t3 »
  /// et « Table 3 » désignaient trois tables différentes pour le logiciel, et
  /// rien ne permettait de savoir lesquelles sont occupées.
  ///
  /// Nullable, et deux situations distinctes le justifient : une vente au
  /// **comptoir** n'a jamais de table, et les paniers antérieurs au schéma v6
  /// n'en portaient pas. Les distinguer demanderait une troisième valeur que
  /// personne ne lirait.
  TextColumn get tableId => text().nullable().references(TablesLocal, #id)();

  /// Le code de l'espace, **copié** de la table au moment de l'ouverture.
  ///
  /// Redondant avec `tableId`, et volontairement : un panier clôturé doit
  /// rester lisible même si la table a depuis été renumérotée ou désactivée —
  /// même raisonnement que le libellé figé d'une ligne.
  TextColumn get espace => text().nullable()();

  /// Date de départ prévue, pour la garde de clôture anticipée.
  DateTimeColumn get dateDepartPrevue => dateTime().nullable()();

  /// `ouvert` | `cloture` | `annule`.
  TextColumn get statut => text().withDefault(const Constant('ouvert'))();

  DateTimeColumn get ouvertLe => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get clotureLe => dateTime().nullable()();

  TextColumn get modePaiement => text().nullable()();

  /// Montant **figé à la clôture**, en francs CFA.
  ///
  /// Le total d'un panier ouvert se recalcule depuis ses lignes ; celui d'un
  /// panier clôturé ne doit plus bouger, même si une ligne était corrigée par
  /// une reprise de données. C'est le même raisonnement que `tarifNuit`.
  IntColumn get montantCloture => integer().nullable()();

  TextColumn get motifAnnulation => text().nullable()();

  /// La session de caisse qui a ENCAISSÉ ce panier — `ventes.session_id` du
  /// serveur (v18, 12/10/2026, D221 option a).
  ///
  /// ⚠ **Ce n'est PAS `paniers.session_id` du serveur.** Celui-là est la caisse
  /// d'OUVERTURE du panier (« le tiroir ouvert quand le panier est né », voir
  /// `2026_09_02_300000_create_paniers`), et le poste ne le répliquait pas. Cette
  /// colonne est le fait que le serveur appelle `ventes.session_id` : la session
  /// ouverte au moment où `PosComptant::encaissementReel` enregistre la vente.
  /// Elle porte un autre nom ici pour que personne ne confonde les deux faits.
  ///
  /// * **Qui l'écrit** : `PanierDao.cloturer`, SEUL auteur, pour un panier au
  ///   COMPTANT (la session OUVERTE du point `bar`, comme `POINT_CAISSE`), dans la
  ///   même transaction que la clôture. Un panier de séjour (note de chambre)
  ///   n'en porte jamais : le serveur n'écrit pas `session_id` dans
  ///   `PosHeberges`. Un panier clôturé AVANT la v18 non plus : le migrer en lui
  ///   attribuant une session serait deviner où l'argent est entré.
  /// * **Qui la lit** : `PanierDao.especesEncaisseesCentimes` — le seul chemin
  ///   vers « Espèces encaissées » et « Théorique en caisse » de la clôture.
  /// * **Qui la descend** : personne (zéro réseau).
  TextColumn get sessionEncaissementId =>
      text().nullable().references(SessionsCaisseLocal, #id)();

  /// Voir l'avertissement en tête de fichier : `non_transmissible` tant que le
  /// serveur n'a pas de table `paniers` au registre de synchronisation.
  TextColumn get statutTransmission =>
      text().withDefault(const Constant('non_transmissible'))();

  @override
  Set<Column> get primaryKey => {id};

  /// v35 (21/10/2026) : remise du panier — `aucune` | `pourcentage` | `montant`.
  TextColumn get remiseType => text().withDefault(const Constant('aucune'))();

  /// La valeur saisie en CENTIÈMES (12,5 % = 1250 ; 500 F = 50000).
  IntColumn get remiseValeurCentiemes =>
      integer().withDefault(const Constant(0))();
}

/// Une consommation portée au panier.
///
/// ## Prix ET libellé figés à l'ajout — la règle 3
///
/// Aucune de ces deux colonnes ne se joint au catalogue à la lecture. Un
/// panier de séjour vit plusieurs jours : si la carte du bar change entre
/// lundi et le départ, la bière de lundi doit rester au prix de lundi, et un
/// plat renommé ne doit pas réécrire une addition déjà présentée au client.
///
/// C'est le même raisonnement que `tarifNuit` figé à la réservation (PA-55).
class LignesPanierLocal extends Table {
  TextColumn get id => text()();

  TextColumn get panierId => text().references(PaniersLocal, #id)();

  /// ⚠ **POINT Q1.** Le rattachement au catalogue d'origine tient dans ces
  /// deux colonnes, et dans elles seules.
  ///
  /// Ce n'est **pas** l'option A du document (quatre clés étrangères nullables
  /// contraintes) : elle n'est pas portable ici, parce que `plats` (M4) n'est
  /// pas répliquée localement — le périmètre offline l'exclut délibérément.
  /// Une clé étrangère vers une table absente ne se déclare pas.
  ///
  /// Ce n'est pas non plus l'option C, exclue par le document : `moduleSource`
  /// est un **registre fermé** (`ModuleVendable`), et l'existence de
  /// `codeArticle` est vérifiée contre le catalogue local avant écriture pour
  /// les trois modules répliqués — voir `PanierDao.ajouterLigne`. Le seul
  /// module non vérifiable est M4, et il est nommé plutôt que dissimulé.
  ///
  /// Si l'Architecte ratifie l'option A, c'est ici que la migration v4
  /// atterrit, et nulle part ailleurs.
  TextColumn get moduleSource => text()();
  TextColumn get codeArticle => text()();

  /// Libellé **copié** au moment de l'ajout.
  TextColumn get libelle => text()();

  /// Prix unitaire **copié** au moment de l'ajout, en francs CFA (entier : le
  /// XOF n'a pas de sous-unité en circulation).
  IntColumn get prixUnitaire => integer()();

  IntColumn get quantite => integer()();

  /// Libellé de rayon, pour l'affichage. Sans valeur métier.
  TextColumn get categorie => text().nullable()();

  DateTimeColumn get ajouteeLe => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
