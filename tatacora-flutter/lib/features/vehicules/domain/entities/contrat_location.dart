// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
/// Les contrats de location — onglet « Contrats ».
library;

/// Le statut d'un contrat ANNULÉ — `ContratLocationService::STATUT_ANNULE`.
const String statutContratAnnule = 'annule';

/// Le statut d'un contrat en cours — celui que le serveur pose à la création.
const String statutContratActif = 'actif';

/// Un contrat, tel que `contrats_location_local` le porte.
///
/// ## Ce que la table LOCALE ne porte pas, et qui reste affiché « — »
///
/// La vue pose les colonnes `N°`, `Véhicule`, `Client`, `Période`, `Jours`,
/// `Montant`, `Acompte`, `Reste dû`, `État`, actions. Confrontées à
/// `contrats_location_local` (`core/database/tables/vehicules_tables.dart`) :
///
/// | Colonne | Source locale |
/// |---|---|
/// | N° | **aucune colonne** — le contrat n'a qu'un UUID |
/// | Véhicule | résolu sur `vehicules_local` (l'immatriculation) |
/// | Client | résolu sur `clients_local` |
/// | Période | `dateDebut` / `dateFin` |
/// | Jours | calculé, bornes demi-ouvertes |
/// | Montant | **calculé** au tarif COURANT — voir [montant] |
/// | Acompte | **aucune colonne** |
/// | Reste dû | **aucune colonne** — il se déduirait de l'acompte |
/// | État | `statut` (v38, 26/10/2026) : `actif` ou `annule` ; `null` = actif |
///
/// ⚠ La vue Blade, elle, rend `$c->numero`, `$c->acompte` et
/// `$c->reste_a_payer` : le schéma **serveur** a gagné ces colonnes, la table
/// **locale** ne les a pas. C'est un écart de schéma, pas un choix de portage,
/// et il est consigné tel quel — l'inventer localement produirait des montants
/// qu'aucune saisie n'a posés. Le STATUT, lui, est porté depuis la v38 : le
/// poste annule un contrat comme la PWA, et reçoit l'annulation du serveur.
final class ContratLocation {
  const ContratLocation({
    required this.id,
    required this.immatriculation,
    required this.clientId,
    required this.debut,
    required this.fin,
    required this.nombreJours,
    required this.montant,
    required this.packageAvecGuide,
    this.clientNom,
    this.statut,
  });

  final String id;

  /// L'immatriculation du véhicule — le seul identifiant lisible qu'il ait :
  /// la table `vehicules` n'a aucune colonne de nom.
  final String immatriculation;

  final String clientId;

  /// `Y-m-d`.
  final String debut;

  /// `Y-m-d`. Borne **exclue** : le schéma impose `date_fin > date_debut`, et
  /// le nombre de jours est une différence.
  final String fin;

  final int nombreJours;

  /// Montant décimal en chaîne (« 75000.00 »).
  ///
  /// ⚠ **Il est RECALCULÉ au tarif courant du véhicule, jamais figé.**
  /// `contrats_location_local` n'a aucune colonne de montant ni de tarif : il
  /// n'y a rien à figer à la signature. Un changement de grille réécrit donc le
  /// montant d'un contrat déjà signé — c'est le défaut exact que PA-55 a
  /// corrigé sur `tarifNuit`, et il ne peut pas l'être ici sans colonne.
  final String montant;

  /// EF-M8-04 — package véhicule + guide. `guideId != null`.
  final bool packageAvecGuide;

  /// Résolu sur `clients_local`. `null` = ce poste ne connaît pas ce client :
  /// l'écran rend « — », il n'affiche pas l'UUID, qui ne dit rien au comptoir.
  final String? clientNom;

  /// `actif` ou `annule` (`contrats_location.statut`). `null` : un contrat
  /// d'avant la v38, qui n'a jamais pu être annulé — donc actif.
  final String? statut;

  /// Annulé : `$c->statut === 'annule'` de la vue. Un contrat annulé reste
  /// LISIBLE (rien n'est supprimé), ne compte plus dans les chiffres et ne
  /// bloque plus son véhicule (RG-08).
  bool get annule => statut == statutContratAnnule;

  ContratLocation avecClient(String? nom) => ContratLocation(
    id: id,
    immatriculation: immatriculation,
    clientId: clientId,
    debut: debut,
    fin: fin,
    nombreJours: nombreJours,
    montant: montant,
    packageAvecGuide: packageAvecGuide,
    clientNom: nom,
    statut: statut,
  );

  /// Le contrat est-il RETENU sur la fenêtre [d]..[f] ? **Bornes incluses**,
  /// comme le serveur (14/10/2026) : `ParcVehiculeService::contratsSurFenetre`
  /// retient `date_fin >= début ET date_debut <= fin` pour la liste des
  /// contrats et les indicateurs de l'écran. Ce poste retenait par un
  /// chevauchement STRICT : un contrat rendu le jour où la fenêtre commence
  /// (ou commençant le jour où elle finit) disparaissait de la liste et des
  /// chiffres alors que la vue le compte.
  ///
  /// ⚠ Ce n'est PAS le contrôle RG-08 : la création et la disponibilité
  /// gardent les bornes demi-ouvertes (`chevauchement`, regles_vehicules.dart,
  /// réplique de `VerificationChevauchementService`) — « un véhicule rendu le
  /// 13 est relouable dès le 13 ».
  bool chevauche(String? d, String? f) {
    if (d != null && fin.compareTo(d) < 0) return false;
    if (f != null && debut.compareTo(f) > 0) return false;
    return true;
  }
}

/// Ce qu'il faut pour établir un contrat — **et rien d'autre**.
///
/// ## Trois champs de la vue ne sont ni acceptés ni refusés : ils n'existent pas
///
/// La modale demande « Remise (FCFA) », « Acompte reçu (FCFA) » et
/// « Téléphone ». Aucun des trois n'a de colonne dans
/// `contrats_location_local`. Ils ne figurent donc pas ici : un champ qu'on
/// collecte pour le jeter produit « Contrat établi » sur un contrat au montant
/// plein, et l'utilisateur serait relancé pour une somme qu'il a versée. Un
/// refus se voit ; un silence non.
///
/// ## « Client » est une clé étrangère, jamais du texte libre
///
/// `clientId` est vérifié à l'écriture contre `clients_local` : le nom tapé au
/// clavier n'a nulle part où aller, et le téléphone est un attribut du client,
/// pas du contrat.
///
/// ## Les deux NUMÉROS ne sont conservés nulle part
///
/// [pieceIdentite] et [permisConduire] sont exigés par RG-09 **à la saisie** —
/// sans eux, le contrat est refusé — mais `contrats_location_local` ne porte
/// que des chemins de fichier (`cheminPieceIdentiteLocal`), pas des numéros.
/// Ils ne sont donc pas écrits, et aucune de ces colonnes n'est détournée pour
/// les y ranger. La vérification protège le comptoir ; la trace manque au
/// schéma.
final class SaisieContrat {
  const SaisieContrat({
    required this.vehiculeId,
    required this.clientId,
    required this.debut,
    required this.fin,
    required this.pieceIdentite,
    this.permisConduire,
    this.guideId,
  });

  final String vehiculeId;
  final String clientId;

  final DateTime debut;

  /// **Strictement** après [debut] : une location d'un jour se saisit du 12 au
  /// 13, jamais du 12 au 12.
  final DateTime fin;

  /// RG-09 — exigé quelle que soit la catégorie.
  final String pieceIdentite;

  /// RG-09 — exigé dès que la catégorie le requiert. La condition n'est pas
  /// réécrite ici : elle est lue sur `exigePermisPour`, unique auteur.
  final String? permisConduire;

  /// EF-M8-04, optionnel.
  final String? guideId;
}

/// Les deux motifs d'immobilisation du schéma de référence
/// (`entretiens_vehicule.type`).
///
/// ## Aucune table locale ne les porte, et ce registre sert quand même
///
/// La vue propose « Entretien » et « Carburation ». `entretiens_vehicule`
/// **n'a aucune table locale** : ni motif, ni date, ni coût n'ont où
/// s'écrire. Le registre reste déclaré pour que la modale affiche la liste
/// **fermée** du schéma plutôt qu'un champ libre — un motif inventé y serait
/// refusé le jour où la table existera. Ce que l'immobilisation change
/// réellement sur ce poste est le **statut du véhicule**, et rien d'autre.
enum TypeEntretien {
  entretien('entretien', 'Entretien'),
  carburation('carburation', 'Carburation');

  const TypeEntretien(this.code, this.libelle);

  final String code;
  final String libelle;
}

/// Une immobilisation du parc — un entretien ou une carburation DATÉ (ligne de
/// `entretiens_vehicule_local`).
final class EntretienVehicule {
  const EntretienVehicule({
    required this.id,
    required this.vehiculeId,
    required this.immatriculation,
    required this.type,
    required this.date,
    required this.coutFrancs,
    this.auteur,
  });

  final String id;
  final String vehiculeId;

  /// « — » quand le véhicule n'est pas (encore) détenu ici.
  final String immatriculation;
  final TypeEntretien type;

  /// `AAAA-MM-JJ`.
  final String date;
  final int coutFrancs;

  /// Le login de qui l'a saisi, ou `null` (ligne descendue du serveur).
  final String? auteur;
}
