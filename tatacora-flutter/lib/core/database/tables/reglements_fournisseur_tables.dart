/// Règlements fournisseur — RÉPLIQUE LOCALE du serveur (12/10/2026, lot 7,
/// D66). Schéma v20, UNE table neuve, migration additive.
///
/// Règle du PO : le serveur Laravel fait foi, ce poste le réplique à
/// l'identique. Les colonnes sont celles de `reglements_fournisseur`
/// (`create_reglements_fournisseur` + `ajouter_statut_annulation_aux_encaissements`) ;
/// les écarts sont ceux de représentation, et chacun est nommé :
///
/// * `montant` (`DECIMAL(15,2)`) devient [montantCentimes] : des centimes
///   ENTIERS, jamais un flottant — le serveur accepte une saisie décimale
///   (« 1500.5 »), un entier de francs la perdrait.
/// * `date_reglement` (`DATE`) devient [dateReglement], un TEXTE `AAAA-MM-JJ`
///   comme `commandes_achat_local.date_commande` : un règlement n'a pas d'heure,
///   et un fuseau ne doit pas le déplacer d'un jour.
/// * `utilisateur_creation_id` (colonne du trait `Auditable`, nullable au
///   serveur) est ici NOT NULL : le moteur comptable exige un auteur (RG-15),
///   et un règlement sans nom de qui l'a décaissé n'a pas de sens.
/// * `date_creation`, `created_at`, `updated_at` ne sont PAS recopiées : aucune
///   ligne de code ne les lirait (piège 9). Le serveur ne les affiche pas non
///   plus ; l'ordre d'une liste est `date_reglement`, puis l'identifiant.
///
/// ## Qui écrit, qui lit, qui descend (pièges 9 et 11)
///
/// | Colonne | Qui l'écrit | Qui la lit | Qui la descend |
/// |---|---|---|---|
/// | `id`, `commande_id`, `montant_centimes`, `tresorerie`, `date_reglement`, `utilisateur_creation_id` | `ReglementsFournisseurDao.regler`, SEUL auteur, dans la même transaction que la pièce comptable (Dr 4011 / Cr trésorerie) | `montant_centimes` + `statut` : le « Réglé » et le « Reste dû » de chaque commande (onglets Commandes et Dettes fournisseurs), les deux cartes « Fournisseurs à payer » et « Total dû », le contrôle du sur-règlement. `tresorerie`, `date_reglement` et `utilisateur_creation_id` : AUCUN écran — comme au serveur, où ils servent à la pièce et à la trace (RG-15), pas à l'affichage | personne : zéro réseau |
/// | `statut`, `motif_annulation`, `annule_par_id`, `date_annulation` | `ReglementsFournisseurDao.annuler` (SEUL auteur), qui contre-passe la pièce ENTIÈRE dans la même transaction | `statut` : le reste dû (un annulé n'est plus déduit) ; les trois autres : AUCUN écran — le serveur expose le service (`ReglementFournisseurService::annuler`, PA-168) mais ni la vue Approvisionnement ni aucune route ne l'appelle ; le poste fait de même (D257) | personne |
///
/// ## Aucune colonne de synchronisation
///
/// Pas de `statutSync` : ce poste ne parle à aucun serveur. Un badge « en
/// attente de synchronisation » sur un règlement qui ne partira jamais serait
/// l'indicateur qui affirme un état qu'il n'a pas vérifié (PA-59/60/61).
///
/// ## Ce que le schéma NE garantit PAS, comme le serveur
///
/// Ni l'égalité `somme des règlements ≤ montant de la commande` (le service la
/// contrôle, la base ne sait pas additionner plusieurs lignes), ni que la
/// commande soit dans un statut donné : le serveur n'exige AUCUN statut pour
/// régler (une commande en brouillon se règle), et le poste fait de même.
///
/// ## Un règlement écrit AVEC sa pièce comptable
///
/// Règle du PO du 31/08/2026 : le DAO passe la pièce (Dr 4011 / Cr trésorerie du
/// mode) dans la même transaction. Cette table ne porte pas de colonne
/// `ecriture_id` — le serveur n'en a pas non plus (PA-52) : le lien est le
/// libellé « Règlement fournisseur `raison sociale` — `id du règlement` »,
/// unique par l'identifiant.
///
/// ## `montant_regle` n'est PAS une colonne de la commande
///
/// Le serveur la porte (`commandes_achat.montant_regle`) et la RECALCULE depuis
/// ces lignes. Sur ce poste, aucun écran ne la lirait autrement que par la somme
/// des règlements actifs : la copier dans `commandes_achat_local` serait écrire
/// deux fois le même chiffre, et la seconde finirait par diverger.
///
/// @see EF-M7-04 Dettes fournisseurs
library;

import 'package:drift/drift.dart';

import 'achats_tables.dart';
import 'utilisateurs_table.dart';

class ReglementsFournisseurLocal extends Table {
  TextColumn get id => text()();

  /// La commande réglée. Vraie clé étrangère : un règlement orphelin n'a pas de
  /// dette à diminuer.
  TextColumn get commandeId => text().references(CommandesAchatLocal, #id)();

  /// Centimes entiers, strictement positifs.
  IntColumn get montantCentimes => integer()();

  /// `caisse` | `momo` | `banque` (`DepenseService::TRESORERIES`).
  TextColumn get tresorerie => text()();

  /// `AAAA-MM-JJ`.
  TextColumn get dateReglement => text()();

  /// `actif` | `annule` (`reglements_fournisseur.statut`).
  TextColumn get statut => text().withDefault(const Constant('actif'))();

  TextColumn get motifAnnulation => text().nullable()();

  // Deux clés étrangères vers `utilisateurs_local` (qui a réglé, qui a annulé) :
  // sans nom distinct, le générateur de Drift refuse de produire les filtres de
  // la seconde.
  @ReferenceName('reglementsFournisseurAnnules')
  TextColumn get annuleParId =>
      text().nullable().references(UtilisateursLocal, #id)();

  DateTimeColumn get dateAnnulation => dateTime().nullable()();

  /// Qui a réglé (RG-15).
  TextColumn get utilisateurCreationId =>
      text().references(UtilisateursLocal, #id)();

  @override
  List<String> get customConstraints => [
    "CHECK (tresorerie IN ('caisse', 'momo', 'banque'))",
    "CHECK (statut IN ('actif', 'annule'))",
    'CHECK (montant_centimes > 0)',
    // Un « annulé » porte OBLIGATOIREMENT son motif et sa date, et
    // réciproquement (`chk_reglements_fournisseur_annulation_coherente`).
    "CHECK ((statut = 'annule') = (motif_annulation IS NOT NULL AND date_annulation IS NOT NULL))",
  ];

  @override
  Set<Column> get primaryKey => {id};
}
