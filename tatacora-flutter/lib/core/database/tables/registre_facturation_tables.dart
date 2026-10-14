/// Registre de facturation — **un seul registre, trois origines** (D3).
///
/// Portage Dart de `prototype_v2/assets/js/facture-engine.js`. Les quatre
/// propriétés que le moteur fige tiennent, pour trois d'entre elles, dans la
/// forme de ces tables :
///
///  1. **Un seul registre** — `origine` est une **colonne**, jamais trois
///     tables. Trois entrepôts obligeraient à réécrire trois fois la
///     numérotation, l'archivage et l'export, et c'est la troisième copie qui
///     divergerait — celle que personne ne relit.
///  2. **Les lignes sont copiées**, jamais jointes : `libelle` et
///     `prixUnitaire` vivent dans `LignesPieceFacturationLocal` et ne sont
///     **jamais** relus depuis un catalogue. Même règle que `prixUnitaire` figé
///     au panier (D2) et `tarifNuit` figé à la réservation (PA-55). *Une
///     facture qui change est une facture fausse.*
///  3. **Une seule séquence de numéros, à compteur persisté SÉPARÉMENT** de la
///     liste — d'où [SequencesFactureLocal], une table à part. Déduire le
///     numéro suivant du nombre de pièces réattribuerait un numéro déjà utilisé
///     dès qu'une pièce serait archivée ou purgée, et un numéro de pièce ne se
///     réemploie jamais, même si la pièce disparaît.
///
/// La quatrième — **annulation par avoir, jamais par effacement** — est portée
/// par le domaine et le dépôt : aucune méthode de suppression n'est exposée.
///
/// ══════════════════════════════════════════════════════════════════════════
/// ⚠ CE REGISTRE N'EST PAS `FacturesLocal`, ET C'EST UN POINT À TRANCHER
/// ══════════════════════════════════════════════════════════════════════════
///
/// `tables/facturation_tables.dart` déclare déjà `FacturesLocal`,
/// `LignesFactureLocal` et `PaiementsLocal`, transcrites de
/// `FULL_MIGRATIONS_DATABASE_FLUTTER.md` — c'est-à-dire du **schéma serveur**.
/// Constat du 20/08/2026 : ces trois tables **n'ont aucun appelant** dans tout
/// le client (ni DAO, ni dépôt, ni écran, ni test). Elles sont *déclarées et
/// jamais branchées*, exactement le balayage n°2 de `A1_MASTER_PROMPT.md`
/// §2.10.
///
/// Elles ne sont pas réutilisées ici, et ce n'est pas une préférence de style —
/// trois de leurs colonnes rendent l'opération impossible sans inventer une
/// donnée :
///
///  - `clientId` est **NOT NULL** avec clé étrangère vers `clients_local`. Une
///    vente au comptant n'a pas de client : il faudrait fabriquer une ligne
///    « Client de passage » dans le fichier clients, qui apparaîtrait ensuite
///    au CRM comme un vrai tiers.
///  - `montantHt`, `montantTva`, `montantTtc` sont **NOT NULL**. Le taux de TVA
///    n'est pas configuré (PA-62 : `CalculTvaService` refuse d'émettre plutôt
///    que d'appliquer 0 %). Écrire `montantTva = 0` pour satisfaire la colonne
///    serait affirmer un fait fiscal que rien n'a vérifié — la famille
///    PA-59/60/61, sur une matière fiscale.
///  - elles sont en `REAL`, quand tout le reste du client compte le franc CFA
///    en entier (`prixUnitaire`, `tarifNuit`, `montantCloture`).
///
/// SQLite ne sait pas retirer une contrainte `NOT NULL` sans **recréer** la
/// table, et recréer une table est précisément ce que la règle de migration de
/// ce dépôt interdit. Les deux registres coexistent donc, et **la question est
/// posée plutôt que tranchée** : le jour où M2 entrera au registre de
/// synchronisation du serveur, il faudra dire lequel des deux fait foi. Voir
/// `docs/PLAN_ACTION_SEQUENCE_POST_AUDIT.md`, PA-99.
///
/// ## Ce registre ne part PAS au serveur, et ce n'est pas un oubli
///
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients` ; `routes/api.php` n'expose aucune route de
/// facturation. Une facture poussée serait rejetée à chaque tentative,
/// indéfiniment. Afficher « en attente de synchronisation » sur une pièce qui
/// ne partira jamais serait l'indicateur qui affirme un état qu'il n'a pas
/// vérifié — PA-59 / PA-60 / PA-61. La colonne [statutTransmission] dit donc
/// `non_transmissible`, et l'écran le dit en toutes lettres.
library;

import 'package:drift/drift.dart';

import 'clients_table.dart';
import 'hebergement_tables.dart';
import 'panier_tables.dart';

/// Une **pièce** du registre : une facture, ou l'avoir qui la neutralise.
///
/// Les deux vivent dans la même table, et c'est voulu : un avoir porte son
/// propre numéro dans la même séquence, il s'exporte et s'archive comme une
/// facture, et un auditeur doit pouvoir les lire dans un seul flux. Les
/// distinguer se fait par [avoirDe], pas par un entrepôt séparé.
class PiecesFacturationLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// `F-2026-00042` — identité **comptable**, unique toutes origines
  /// confondues.
  ///
  /// `unique()` n'est pas décoratif : la garantie doit tenir en base et pas
  /// seulement dans le code. Deux pièces au même numéro rendraient impossible
  /// de désigner une pièce sans ambiguïté, ce qui est exactement ce qu'un
  /// contrôle fiscal demande de faire.
  TextColumn get numero => text().unique()();

  /// `pos_comptant` | `pos_sejour` | `facture_directe`.
  ///
  /// **Une colonne, pas trois tables.** C'est le filtre de l'écran, rien de
  /// plus. Le registre fermé qui la borne est `OrigineFacture`.
  TextColumn get origine => text()();

  DateTimeColumn get dateEmission => dateTime()();

  /// Nom affiché du client, **copié** à l'émission — comme le libellé d'une
  /// ligne. Une facture rouverte dans trois mois doit porter le nom qu'elle
  /// portait le jour où elle a été remise, même si la fiche client a changé.
  TextColumn get clientNom => text()();

  /// Clé étrangère **réelle mais nullable** : `null` signifie « client de
  /// passage », cas majoritaire au comptoir.
  ///
  /// La rendre NOT NULL obligerait à fabriquer un tiers fictif dans
  /// `clients_local`, qui remonterait ensuite au CRM comme un vrai client.
  TextColumn get clientId => text().nullable().references(ClientsLocal, #id)();

  /* ------------------------------------------------------ provenance ----- */
  /// Provenance : permet de **remonter à la source**, jamais d'en recalculer.
  ///
  /// Aucune lecture de facture ne joint ces tables pour reconstituer un
  /// montant. Elles servent à répondre à « d'où vient cette pièce ? ».
  TextColumn get reservationId =>
      text().nullable().references(ReservationsLocal, #id)();

  TextColumn get panierId => text().nullable().references(PaniersLocal, #id)();

  /* ---------------------------------------------------------- règlement -- */
  TextColumn get modePaiement => text().nullable()();

  TextColumn get pointVente => text().nullable()();

  /* ------------------------------------------------------------- MECeF -- */
  /// Identité **fiscale**, distincte de l'identité comptable ([numero]).
  ///
  /// **Nulle à l'émission, toujours**, et c'est délibéré : MECeF est factice
  /// (`MecefClientFake`), l'inscription DGI (PA-17) n'est pas lancée. La
  /// certification se dérive de la présence d'un **vrai** numéro — voir
  /// `domain/certification_mecef.dart` —, jamais d'une intention ni d'une clé
  /// de configuration présente. C'est PA-61 mot pour mot.
  TextColumn get numeroMecef => text().nullable()();

  /* -------------------------------------------------------------- état -- */
  /// `emise` | `annulee`.
  ///
  /// À ne pas confondre avec `FacturesLocal.statut`, qui est le **cycle
  /// MECeF** (`brouillon` / `en_attente_certification` / `certifiee` /
  /// `echec_certification`). Ce sont deux axes différents — c'est déjà le
  /// constat de PA-49 côté serveur.
  TextColumn get statut => text().withDefault(const Constant('emise'))();

  /// Le **numéro** de la pièce que cet avoir neutralise, `null` si la pièce
  /// est une facture.
  ///
  /// La clé étrangère vise `numero` et non `id` : c'est le numéro qui désigne
  /// une pièce dans un document comptable, et il est unique et immuable. La
  /// contrainte est réelle — un avoir qui désignerait une pièce inexistante
  /// serait refusé par la base, pas seulement par le code.
  TextColumn get avoirDe =>
      text().nullable().references(PiecesFacturationLocal, #numero)();

  /// Motif porté par l'**avoir**. Un avoir sans raison est indistinguable
  /// d'une erreur de manipulation.
  TextColumn get motifAvoir => text().nullable()();

  /// Motif porté par la **facture annulée**, et sa date.
  TextColumn get motifAnnulation => text().nullable()();
  DateTimeColumn get dateAnnulation => dateTime().nullable()();

  /// Voir l'en-tête : `non_transmissible` tant que le serveur n'a ni table
  /// `factures` au registre de synchronisation, ni route d'API.
  TextColumn get statutTransmission =>
      text().withDefault(const Constant('non_transmissible'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Une ligne de pièce — **une copie**, jamais une référence.
///
/// Aucune de ces colonnes ne se joint à un catalogue à la lecture. Si la carte
/// du bar change demain, cette ligne ne bouge pas : c'est la propriété n°2 du
/// moteur, et c'est elle qui fait qu'une facture rouverte dans trois mois
/// affiche encore le montant remis au client.
class LignesPieceFacturationLocal extends Table {
  TextColumn get id => text()();

  TextColumn get pieceId => text().references(PiecesFacturationLocal, #id)();

  /// Le module d'activité, **copié avec la ligne**.
  ///
  /// Registre fermé `ModuleFacturable`. Ce n'est **pas** `ModuleVendable` du
  /// panier : celui-ci exclut M1 par construction, parce que Q3 n'est pas
  /// tranchée sur la place de l'hébergement **au panier**. Une facture de
  /// départ, elle, porte la nuitée — la question n'est pas la même, et
  /// confondre les deux registres ferait dépendre la facture d'un arbitrage
  /// qui ne la concerne pas. Voir `domain/entities/piece_facturation.dart`.
  TextColumn get moduleSource => text()();

  /// Code de l'article au catalogue de son module, **à titre de provenance**.
  ///
  /// `null` pour une ligne qui ne vient d'aucun catalogue — la nuitée, par
  /// exemple, vient de la réservation. Il n'est jamais relu pour recalculer
  /// quoi que ce soit : le prix et le libellé de la ligne font foi.
  TextColumn get codeArticle => text().nullable()();

  /// Libellé **copié** à l'émission.
  TextColumn get libelle => text()();

  /// Prix unitaire **copié** à l'émission, en francs CFA (entier : le XOF n'a
  /// pas de sous-unité en circulation).
  IntColumn get prixUnitaire => integer()();

  /// Quantité — **négative sur un avoir**.
  ///
  /// Divergence assumée avec le prototype, expliquée dans
  /// `domain/entities/piece_facturation.dart` : elle conserve l'invariant
  /// `montant = prixUnitaire × quantite` sur **toutes** les lignes du registre,
  /// avoirs compris, là où le prototype stocke un montant négatif à côté d'une
  /// quantité positive.
  IntColumn get quantite => integer()();

  /// Rang d'affichage. Sans lui, l'ordre des lignes d'une facture dépendrait
  /// du plan d'exécution de SQLite : deux impressions de la même pièce
  /// pourraient sortir dans un ordre différent, ce qu'un client remarque.
  IntColumn get ordre => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le compteur de la séquence de numéros — **une table à part**.
///
/// C'est la propriété n°3, et elle tient entièrement dans le fait que cette
/// table existe. Le prototype persiste le compteur sous une clé distincte de la
/// liste (`tatacora_factures_sequence`), pour la raison écrite dans son
/// commentaire : *« le déduire de `factures().length` ferait réattribuer un
/// numéro déjà utilisé dès qu'une facture serait archivée ou purgée »*.
///
/// Le registre est par **année** : `F-2026-00042` repart à 1 le 1er janvier,
/// et l'année fait partie du numéro.
class SequencesFactureLocal extends Table {
  IntColumn get annee => integer()();

  /// Dernier numéro **attribué**, pas le prochain. La distinction évite de se
  /// demander, en lisant la base, si 42 signifie « 42 pièces émises » ou
  /// « la prochaine sera la 42ᵉ ».
  IntColumn get dernierNumero => integer()();

  @override
  Set<Column> get primaryKey => {annee};
}
