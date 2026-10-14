/// Sessions de caisse — RÉPLIQUE LOCALE du serveur (12/10/2026, lot 4).
/// Schéma v17, UNE table neuve, migration additive.
///
/// Règle du PO (10/10/2026) : le serveur est la RÉFÉRENCE, ce poste le
/// réplique (zéro réseau, bureau seulement). Les colonnes sont celles de
/// `sessions_caisse` (`create_facturation`, l.59-69) ; l'écart de représentation
/// est unique et nommé : les montants sont des CENTIMES ENTIERS (le serveur
/// écrit `DECIMAL(15,2)`), jamais un flottant.
///
/// Maître de comportement : le composant `PosComptant` du serveur
/// (`ouvrirCaisse`, `cloturerCaisse`) — l'ouverture et la clôture n'ont AUCUN
/// service de domaine côté serveur. Chaque écart nommé est dans
/// `docs/conversations/2026-10-08_decisions-lead-engineer.md` (D219 et suivants).
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `id`, `point_vente`, `date_ouverture`, `montant_fond_centimes` | `SessionsCaisseDao.ouvrir`, SEUL auteur, appelé par la barre de session de l'écran POS comptant (point `bar`, comme `PosComptant::POINT_CAISSE`) | la barre de session (« Caisse bar ouverte », « depuis 07:00 », « · 12 min », « Fond »), la modale de clôture (« Fond de caisse »), `sessionOuverte` | personne : zéro réseau |
/// | `utilisateur_ouverture_id` | idem (l'identifiant du compte connecté, RG-15) | **aucun écran** : comme au serveur, elle est écrite pour la TRACE et lue par personne | personne |
/// | `date_cloture` | `SessionsCaisseDao.cloturer`, SEUL auteur, dans la même transaction que le calcul (rien n'est écrit si la saisie est refusée) | la barre (une session close n'est plus « ouverte »), les refus « déjà ouverte » et « Aucune caisse n'est ouverte… », `sessionOuverteLaPlusRecente` (appelée en production depuis le lot 5 : l'encaissement de facture, `PaiementsFactureDao.encaisser`) | personne |
/// | `montant_theorique_centimes`, `montant_constate_centimes` | `SessionsCaisseDao.cloturer` | **AUCUN lecteur de production** — comme au serveur, où seul `cloturerCaisse()` les écrit et où le KPI « Trésorerie de caisse » lit le FOND, pas ces colonnes. `sessions()` les rend ; son SEUL appelant de production (depuis le lot 5) est le KPI « Trésorerie (caisse) » de M11 (`tableauDeBordLocalProvider`), qui n'en lit que le fond et l'état ouvert/clos — jamais ces deux colonnes (épinglé par `ecrivains_caisse_test.dart`, revu le 12/10/2026) | personne |
///
/// ## Trois colonnes du serveur qui ne sont PAS ici
///
/// * **`created_at`, `updated_at`** : horodatages techniques du framework ; la
///   date d'ouverture et la date de clôture portent déjà les deux instants
///   métier. (Les trois colonnes ci-dessus sans lecteur d'écran SONT répliquées :
///   elles sont le contenu même de la pièce d'exploitation — la trace de qui a
///   ouvert, ce qui a été compté — et le serveur les écrit pour la même raison.)
/// * **`utilisateur_cloture_id`** : le MODÈLE serveur la déclare (`$fillable`,
///   `@property`) mais AUCUNE migration ne la crée et `cloturerCaisse()` ne
///   l'écrit pas. Elle n'existe donc pas au schéma de référence : la répliquer
///   serait inventer un champ que le serveur n'a jamais eu. Conséquence assumée,
///   écrite ici plutôt que découverte : une session close ne dit pas qui l'a
///   close (RG-15 n'est tenue qu'à l'ouverture).
///
/// ## Ce que la table ne porte pas : l'ÉCART
///
/// Le serveur ne stocke pas l'écart de caisse. Il le calcule à la clôture
/// (`constaté - théorique`), l'annonce dans le message, et le laisse se perdre.
/// Ce poste fait de même — le recalcul est possible depuis les deux colonnes
/// (`regles_caisse.dart`), mais aucune colonne dénormalisée n'est ajoutée.
///
/// ## Aucune colonne de synchronisation
///
/// Pas de `statutSync`. `sessions_caisse` est listée dans
/// `ClassificationConflitService`, mais jamais poussée par ce poste (zéro
/// réseau) : une session ouverte ici ne partira nulle part, l'écran dit
/// « enregistré sur ce poste » et n'affiche aucun « en attente de
/// synchronisation » (PA-59/60/61).
///
/// ## Ce que le schéma NE garantit PAS, comme le serveur
///
/// Aucune unicité d'une session ouverte par point : le serveur la contrôle dans
/// le composant (lecture puis création, sans verrou), jamais dans la base. Ce
/// poste la contrôle dans le DAO, dans une transaction (SQLite sérialise les
/// écritures : la fenêtre de concurrence du serveur n'existe pas ici — écart
/// nommé, à l'avantage du poste). Un index unique partiel porterait une règle
/// que le serveur n'a pas.
library;

import 'package:drift/drift.dart';

import 'utilisateurs_table.dart';

/// Une session de caisse : l'ouverture d'un tiroir, sa clôture, et ce que
/// l'exploitant y a compté.
class SessionsCaisseLocal extends Table {
  /// UUID posé **côté client**, comme partout ailleurs dans ce dépôt.
  TextColumn get id => text()();

  /// `reception` | `restaurant` | `bar` — l'`enum` du serveur. Seul `bar` est
  /// écrit par l'écran POS comptant (`PosComptant::POINT_CAISSE`) ; les deux
  /// autres valeurs sont celles que le serveur autorise et que ses lecteurs
  /// (indicateur de la barre supérieure, encaissement de facture) savent lire.
  TextColumn get pointVente => text()();

  /// Qui a ouvert la caisse (RG-15). Vraie clé étrangère ; `restrictOnDelete`
  /// côté serveur, `NO ACTION` ici : un compte désactivé n'est jamais supprimé.
  TextColumn get utilisateurOuvertureId =>
      text().references(UtilisateursLocal, #id)();

  DateTimeColumn get dateOuverture => dateTime()();

  /// Le fond de caisse, en CENTIMES (`montant_fond DECIMAL(15,2)`).
  IntColumn get montantFondCentimes => integer()();

  /// `NULL` tant que la caisse est ouverte — c'est CE qui dit « ouverte ».
  DateTimeColumn get dateCloture => dateTime().nullable()();

  /// Le théorique à la clôture (fond + espèces encaissées), en centimes. `NULL`
  /// tant que la caisse est ouverte — et `NULL` aussi sur une session close sur
  /// ce poste tant que les espèces encaissées n'ont aucune source (voir
  /// `SessionsCaisseDao.cloturer`) : un théorique calculé sans elles serait
  /// un chiffre plausible et faux.
  IntColumn get montantTheoriqueCentimes => integer().nullable()();

  /// Le montant réellement compté, en centimes.
  IntColumn get montantConstateCentimes => integer().nullable()();

  @override
  List<String> get customConstraints => [
    "CHECK (point_vente IN ('reception', 'restaurant', 'bar'))",
  ];

  @override
  Set<Column> get primaryKey => {id};
}
