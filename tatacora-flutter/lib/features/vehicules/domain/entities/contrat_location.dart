// Vue Blade maîtresse (PA-183) : pwa/vehicules/locations.blade.php
/// Les contrats de location — onglet « Contrats ».
library;

/// Le statut d'un contrat ANNULÉ — `ContratLocationService::STATUT_ANNULE`.
const String statutContratAnnule = 'annule';

/// Le statut d'un contrat en cours — celui que le serveur pose à la création.
const String statutContratActif = 'actif';

/// Un contrat, tel que `contrats_location_local` le porte.
///
/// ## Les dix colonnes de la vue (v41, 27/10/2026)
///
/// `N°`, `Véhicule`, `Client`, `Période`, `Jours`, `Montant`, `Acompte`,
/// `Reste dû`, `État`, actions. Depuis la v41 le contrat porte son [numero]
/// (`LOC-…`, rendu par le serveur), sa [remise], son [acompte] et son [montant]
/// NET FIGÉ à la signature (tarif du jour × jours − remise) ; le [resteDu] en est
/// la différence avec l'acompte, jamais une colonne. Chacun est `null` pour un
/// contrat d'avant la v41 (ou pas encore envoyé, pour le N°) : la migration n'en
/// déduit AUCUN, et l'écran rend « — » — jamais le tarif courant, jamais « Soldé »
/// sur un reste inconnu.
final class ContratLocation {
  const ContratLocation({
    required this.id,
    required this.immatriculation,
    required this.clientId,
    required this.debut,
    required this.fin,
    required this.nombreJours,
    required this.packageAvecGuide,
    this.montant,
    this.numero,
    this.remise,
    this.acompte,
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

  /// Le montant NET, FIGÉ à la signature (« 70000.00 »), ou `null`.
  ///
  /// Avant la v41 il était RECALCULÉ au tarif courant du véhicule : modifier la
  /// grille réécrivait un contrat déjà signé. Il est désormais une colonne
  /// (`contrats_location_local.montant`), écrite une fois par
  /// `VehiculeDao.creerContrat` (ou reçue du serveur), jamais recalculée. `null` :
  /// contrat d'avant, non encore rempli par la descente — « — ».
  final String? montant;

  /// Le N° `LOC-…` du serveur, ou `null` (contrat d'avant, ou pas encore
  /// envoyé : le poste n'invente aucun numéro).
  final String? numero;

  /// La remise accordée à la signature (« 5000.00 »), ou `null`. Le serveur ne la
  /// garde pas : un contrat reçu d'ailleurs n'en a pas.
  final String? remise;

  /// L'acompte reçu (« 20000.00 »), ou `null` (contrat d'avant).
  final String? acompte;

  /// Le reste dû : [montant] − [acompte], en chaîne décimale, ou `null` quand l'un
  /// des deux est inconnu. `contrats_location.reste_a_payer` du serveur vaut
  /// toujours cette différence (aucun geste ne la modifie).
  String? get resteDu {
    final m = montant;
    final a = acompte;
    if (m == null || a == null) return null;
    final montantCentimes = _centimes(m);
    final acompteCentimes = _centimes(a);
    if (montantCentimes == null || acompteCentimes == null) return null;
    final reste = montantCentimes - acompteCentimes;
    final negatif = reste < 0;
    final absolu = reste.abs();
    return '${negatif ? '-' : ''}${absolu ~/ 100}.'
        '${(absolu % 100).toString().padLeft(2, '0')}';
  }

  static int? _centimes(String brut) {
    final point = brut.indexOf('.');
    final entier = int.tryParse(point < 0 ? brut : brut.substring(0, point));
    final decimale = point < 0
        ? 0
        : int.tryParse(brut.substring(point + 1).padRight(2, '0'));
    if (entier == null || decimale == null) return null;
    return entier * 100 + decimale;
  }

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
    numero: numero,
    remise: remise,
    acompte: acompte,
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
/// ## Remise et acompte : portés depuis la v41 (27/10/2026)
///
/// La modale demande « Remise (FCFA) » et « Acompte reçu (FCFA) » comme la vue :
/// [remiseFrancs] et [acompteFrancs] (zéro par défaut, comme la vue) servent à
/// figer le montant NET à la signature (`VehiculeDao.creerContrat`). Une remise
/// supérieure au brut, puis un acompte supérieur au net, sont refusés avec les
/// phrases du serveur.
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
/// les y ranger. Ils partent, eux, dans la charge du serveur. La vérification
/// protège le comptoir ; la trace manque au schéma local.
final class SaisieContrat {
  const SaisieContrat({
    required this.vehiculeId,
    required this.clientId,
    required this.debut,
    required this.fin,
    required this.pieceIdentite,
    this.permisConduire,
    this.guideId,
    this.remiseFrancs = 0,
    this.acompteFrancs = 0,
  });

  /// La remise de la signature, en francs entiers (>= 0).
  final int remiseFrancs;

  /// L'acompte reçu, en francs entiers (>= 0).
  final int acompteFrancs;

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
/// ## Ils s'écrivent dans `entretiens_vehicule_local` (v32, relu le 27/10/2026)
///
/// La vue propose « Entretien » et « Carburation ». Le texte précédent (« aucune
/// table locale, ni motif, ni date, ni coût ») était périmé : la table existe
/// depuis la v32 et `VehiculeDao.enregistrerEntretien` y écrit le type, le jour,
/// le coût et le chauffeur (liste FERMÉE du schéma, jamais un champ libre).
/// L'immobilisation ne change PAS le statut du véhicule, comme la PWA.
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
