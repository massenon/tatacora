/// Les trois catalogues vendables — boissons, circuits, véhicules.
///
/// ## D'où viennent ces classes (14/09/2026)
///
/// Elles vivaient dans `catalogue_api.dart`, aux côtés du client HTTP qui
/// descendait les trois rayons (PA-129). Le poste est passé **zéro réseau** :
/// le client a été retiré, ces classes sont restées.
///
/// Elles sont le **format d'entrée** de [CatalogueDao.alignerCatalogue],
/// l'auteur unique des trois tables — et le jeu de démonstration
/// (`core/dev/donnees_demonstration.dart`) l'emprunte déjà. C'est aujourd'hui
/// le seul chemin par lequel le point de vente reçoit quelque chose à vendre.
///
/// ⚠ **PA-129 n'est pas refermée, elle est déplacée** : sans descente réseau
/// et sans amorçage, `cartes_boisson_local`, `circuits_local` et
/// `vehicules_local` restent lues partout et écrites nulle part.
///
/// ## Les champs de stock restent NULLABLES, et ils resteront nuls
///
/// `stockVendable`, `stockDisponible`, `reserve`, `sousSeuil` et `rupture`
/// étaient calculés par le serveur sur des tables M6 que ce poste ne détient
/// pas. Ils ne sont plus alimentés par personne. **Ne leur donnez pas de
/// valeur par défaut** : `null` veut dire « aucun chiffre n'existe », et la
/// carte du bar le rend par « non consulté ». Un `0` s'y lirait « rupture » —
/// une bonne nouvelle affichée à la place d'une absence (PA-129, PA-199).
library;

final class BoissonDistante {
  const BoissonDistante({
    required this.id,
    required this.articleId,
    required this.libelle,
    required this.categorie,
    required this.prixVente,
    required this.stockDisponible,
    this.indisponibilite,
    this.stockVendable,
    this.reserve,
    this.sousSeuil,
    this.rupture,
    this.stockNonConsulte = false,
    this.pointDeVenteAbsent = false,
    this.prixProvisoire = false,
    this.prixCorrigeMain = false,
    this.lienLibelle,
    this.lienDetail,
  });

  /// La seconde marque de prix de la vue — posé à la main (PA-200).
  final bool prixCorrigeMain;

  /// La colonne « Article de stock » : le libellé de l'article et son
  /// conditionnement en clair (« 24 par casier »). `null` sans lien.
  final String? lienLibelle;
  final String? lienDetail;

  final String id;

  /// Le stock de la CARTE, en unités VENDABLES (bouteilles) — PA-199.
  /// ⚠ [stockDisponible], lui, est le solde BRUT en unités de STOCK
  /// (casiers) : pour un casier de 24, 2 là où celui-ci dit 48.
  final double? stockVendable;

  /// Le stock hors point de vente, en unités vendables, ou `null`.
  final double? reserve;

  /// Drapeaux de stock ; `null` quand aucun chiffre n'existe.
  final bool? sousSeuil;
  final bool? rupture;

  /// Lié, mais aucun solde n'a pu être lu — ou aucun point de vente n'est
  /// déclaré ([pointDeVenteAbsent] dit lequel). Jamais un zéro.
  final bool stockNonConsulte;
  final bool pointDeVenteAbsent;

  /// PA-161 (b) — un tarif posé faute de relevé, à confronter à la carte.
  final bool prixProvisoire;

  /// Le lien vers l'article de stock (M6). `null` = aucun lien.
  final String? articleId;

  final String libelle;
  final String categorie;
  final double prixVente;

  /// Le solde brut en unités de stock. Calculé par le serveur, jamais soumis
  /// (PA-24) — et plus alimenté par personne depuis le 14/09/2026.
  final double? stockDisponible;

  /// Le retrait de la carte du jour EN COURS, ou `null` : la boisson est à la
  /// carte.
  final IndisponibiliteDistante? indisponibilite;
}

/// Un retrait de la carte du jour.
final class IndisponibiliteDistante {
  const IndisponibiliteDistante({
    required this.motif,
    required this.libelle,
    required this.temporaire,
    this.commentaire,
  });

  /// Code du registre FERMÉ `IndisponibiliteCarte::MOTIFS` — `rupture`,
  /// `saison`, `retire`.
  final String motif;

  /// Le libellé du motif, affiché tel quel plutôt que retraduit d'une
  /// seconde liste — deux listes finissent par diverger.
  final String libelle;

  /// Une rupture revient au réapprovisionnement, un retrait est une décision
  /// commerciale.
  final bool temporaire;

  final String? commentaire;
}

final class CircuitDistant {
  const CircuitDistant({
    required this.id,
    required this.nom,
    required this.theme,
    required this.zone,
    required this.prix,
    required this.capaciteMax,
  });

  final String id;
  final String nom;
  final String theme;
  final String zone;
  final double prix;
  final int capaciteMax;
}

final class VehiculeDistant {
  const VehiculeDistant({
    required this.id,
    required this.categorie,
    required this.immatriculation,
    required this.tarifJour,
    required this.statut,
  });

  final String id;
  final String categorie;
  final String immatriculation;
  final double tarifJour;
  final String statut;
}
