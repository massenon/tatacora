/// Encaissements de factures — RÉPLIQUE LOCALE du serveur (12/10/2026, lot 5).
/// Schéma v18, UNE table neuve (plus une colonne sur `paniers_local`, voir
/// `panier_tables.dart`), migration additive.
///
/// Règle du PO : le serveur Laravel fait foi, ce poste le réplique à
/// l'identique. Les colonnes sont celles de `paiements` (`create_facturation`
/// l.67-77 + `ajouter_statut_annulation_aux_encaissements`) ; les écarts sont
/// ceux de représentation, et chacun est nommé :
///
/// * `facture_id` devient [pieceId] : la « facture » locale est une PIÈCE du
///   registre unique (`pieces_facturation_local`) ; la clé étrangère est réelle.
/// * `montant` (`DECIMAL(15,2)`) devient [montantCentimes] : des centimes
///   ENTIERS, jamais un flottant — le serveur accepte une saisie décimale
///   (« 100.5 »), un entier de francs la perdrait.
/// * `utilisateur_creation_id` (colonne du trait `Auditable`, nullable au
///   serveur) est ici NOT NULL : le moteur comptable exige un auteur (RG-15),
///   et un encaissement sans nom de qui l'a reçu n'a pas de sens.
/// * le serveur n'a PAS de CHECK sur le montant ; le poste en pose un
///   (`> 0`) : le service le refuse déjà, la base le redit.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `id`, `piece_id`, `session_id`, `mode_paiement`, `montant_centimes`, `date_paiement`, `utilisateur_creation_id` | `PaiementsFactureDao.encaisser`, SEUL auteur, dans la même transaction que la pièce comptable | le reste dû (`resteDuBrutCentimes`) qui alimente le solde des clients, le bouton « Recouvrement », M11 (3 indicateurs) et M14 (état créances) ; l'onglet « Historique & avances » (tableau « Recouvrements encaissés ») ; le théorique de caisse NE LIT PAS cette table (incohérence serveur répliquée, D227) | personne : zéro réseau |
/// | `statut`, `motif_annulation`, `annule_par_id`, `date_annulation` | `PaiementsFactureDao.annuler` (SEUL auteur), qui contre-passe la pièce ENTIÈRE dans la même transaction | `statut` : le reste dû (un annulé n'est plus déduit) ; `motif_annulation`, `annule_par_id`, `date_annulation` : AUCUN écran — comme au serveur, où `ClientsCreances` n'expose aucun geste d'annulation (le service existe, la vue ne l'appelle pas) | personne |
///
/// ## Aucune colonne de synchronisation
///
/// Pas de `statutSync` : ce poste ne parle à aucun serveur. Un badge « en
/// attente de synchronisation » sur un encaissement qui ne partira jamais
/// serait l'indicateur qui affirme un état qu'il n'a pas vérifié (PA-59/60/61).
///
/// ## Ce que le schéma NE garantit PAS, comme le serveur
///
/// Ni l'égalité `somme des paiements ≤ montant de la pièce` (le service la
/// contrôle, la base ne sait pas additionner plusieurs lignes), ni qu'une
/// session soit OUVERTE à l'insertion (le service la choisit ouverte ; elle
/// peut être close après coup, ce qui est le cas normal).
///
/// ## Un encaissement écrit AVEC sa pièce comptable
///
/// Règle du PO du 31/08/2026 : le DAO passe la pièce (Dr trésorerie du mode /
/// Cr 4111) dans la même transaction. Cette table ne porte pas de colonne
/// `ecriture_id` — le serveur n'en a pas non plus (PA-52) : le lien est le
/// libellé « Encaissement `n°` — `id du paiement` », unique par l'identifiant.
///
/// @see EF-M2-03 Encaissement des factures
library;

import 'package:drift/drift.dart';

import 'caisse_tables.dart';
import 'registre_facturation_tables.dart';
import 'utilisateurs_table.dart';

class PaiementsFactureLocal extends Table {
  TextColumn get id => text()();

  /// La pièce réglée — une FACTURE, jamais un avoir.
  TextColumn get pieceId => text().references(PiecesFacturationLocal, #id)();

  /// Le tiroir qui a reçu l'argent : la session OUVERTE au moment du geste.
  TextColumn get sessionId => text().references(SessionsCaisseLocal, #id)();

  /// `especes` | `mobile_money` | `carte` | `virement` (`Paiement::MODES`).
  TextColumn get modePaiement => text()();

  /// Centimes entiers, strictement positifs.
  IntColumn get montantCentimes => integer()();

  DateTimeColumn get datePaiement => dateTime()();

  /// `actif` | `annule` (`paiements.statut`).
  TextColumn get statut => text().withDefault(const Constant('actif'))();

  TextColumn get motifAnnulation => text().nullable()();

  // Deux clés étrangères vers `utilisateurs_local` (qui a encaissé, qui a
  // annulé) : sans nom distinct, le générateur de Drift refuse de produire les
  // filtres de la seconde.
  @ReferenceName('paiementsAnnules')
  TextColumn get annuleParId =>
      text().nullable().references(UtilisateursLocal, #id)();

  DateTimeColumn get dateAnnulation => dateTime().nullable()();

  /// Qui a encaissé (RG-15).
  TextColumn get utilisateurCreationId =>
      text().references(UtilisateursLocal, #id)();

  @override
  List<String> get customConstraints => [
    "CHECK (mode_paiement IN ('especes', 'mobile_money', 'carte', 'virement'))",
    "CHECK (statut IN ('actif', 'annule'))",
    'CHECK (montant_centimes > 0)',
    // Un « annulé » porte OBLIGATOIREMENT son motif et sa date, et
    // réciproquement (`chk_paiements_annulation_coherente` du serveur).
    "CHECK ((statut = 'annule') = (motif_annulation IS NOT NULL AND date_annulation IS NOT NULL))",
  ];

  @override
  Set<Column> get primaryKey => {id};
}
