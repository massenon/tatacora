/// Le panier — portage Dart de `prototype_v2/assets/js/panier-engine.js`.
///
/// ⚠ **Portage d'une PROPOSITION, pas d'une décision.** Le modèle vient de
/// `docs/PROPOSITION_MODELE_PANIER_POS.md`, non ratifié : Q1 (rattachement des
/// lignes), Q2 (unicité du panier ouvert) et Q3 (place de l'hébergement)
/// restent ouvertes. Les trois sont isolées derrière des points nommés —
/// `entities/reference_catalogue.dart`, `unicite_panier_ouvert.dart`,
/// `place_hebergement.dart` — pour qu'un arbitrage contraire coûte peu.
///
/// ## Le panier est la structure ; le POS est un écran
///
/// La différence entre les deux points de vente demandés se réduit à deux
/// attributs : [typeVente] et [reservationId]. Tout le reste — ajout de
/// lignes, total, clôture — est commun. Deux flux séparés dupliqueraient la
/// logique de rattachement des consommations, et c'est cette duplication qui
/// produit ensuite les divergences de comportement entre le bar et la
/// réception.
///
/// ## Les cinq règles, et la panne que chacune évite
///
/// 1. **Un seul panier ouvert par séjour.** Deux paniers scindent les
///    consommations : la facture de départ en oublie la moitié, et l'écart
///    n'apparaît qu'à la réclamation du client. → `unicite_panier_ouvert.dart`
///    et `PanierDao.ouvrir`.
/// 2. **Un panier clôturé est immuable.** Sinon le panier devient le chemin
///    par lequel on modifie une facture déjà remise. → [estModifiable].
/// 3. **Prix ET libellé figés à l'ajout.** Un panier de séjour vit plusieurs
///    jours ; une bière consommée lundi reste au prix de lundi. → les colonnes
///    `libelle` et `prixUnitaire` de `LignesPanierLocal`, jamais jointes au
///    catalogue à la lecture.
/// 4. **Bar et restaurant dans le même panier** — exigence explicite du client
///    au compte rendu d'atelier du 19/08/2026. → aucun filtre de module sur
///    l'ajout ; [ventilation] restitue la répartition sans jamais la séparer.
/// 5. **Clôture anticipée possible, jamais silencieuse.** La règle 1
///    interdisant d'en rouvrir un second, clôturer avant le départ empêche
///    toute consommation d'ici là : on pose la question, on ne bloque pas.
///    → [clotureEstAnticipee].
library;

import 'reference_catalogue.dart';

/// Ce que le panier dit du **rattachement de la vente**, jamais du lieu.
///
/// Le lieu — où se trouve l'argent — est `pointVente`, et les deux axes sont
/// indépendants : on encaisse au comptant depuis la réception, on alimente un
/// panier de séjour depuis le bar.
enum TypeVente {
  /// Client de passage : encaissement immédiat, aucun séjour.
  comptant('comptant'),

  /// Client hébergé : le panier reste ouvert de l'arrivée au départ.
  surSejour('sur_sejour');

  const TypeVente(this.code);
  final String code;

  /// Un code inconnu **lève**, il ne retombe pas sur `comptant`.
  ///
  /// Retomber sur `comptant` détacherait le panier de son séjour : ses
  /// consommations n'atteindraient jamais la facture de départ, et rien ne
  /// l'annoncerait.
  static TypeVente depuisCode(String code) => values.firstWhere(
    (t) => t.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Type de vente inconnu'),
  );
}

enum StatutPanier {
  ouvert('ouvert'),
  cloture('cloture'),
  annule('annule');

  const StatutPanier(this.code);
  final String code;

  static StatutPanier depuisCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Statut de panier inconnu'),
  );
}

/// Où le panier a-t-il, ou non, vocation à rejoindre le serveur.
///
/// Une seule valeur aujourd'hui, et c'est le fait qui compte :
/// `SynchronisationService::TABLES_SYNCHRONISABLES` ne connaît que
/// `reservations` et `clients`. Un panier poussé serait rejeté à chaque
/// tentative. Annoncer « en attente de synchronisation » serait un indicateur
/// affirmant un état qu'il n'a pas vérifié — la famille PA-59/60/61.
enum StatutTransmissionPanier {
  /// Le serveur n'a pas de table `paniers` au registre. Le panier vit sur ce
  /// poste, et l'écran doit le dire ainsi.
  nonTransmissible('non_transmissible');

  const StatutTransmissionPanier(this.code);
  final String code;

  static StatutTransmissionPanier depuisCode(String code) => values.firstWhere(
    (s) => s.code == code,
    orElse: () => StatutTransmissionPanier.nonTransmissible,
  );
}

/// Une consommation portée au panier.
final class LignePanier {
  const LignePanier({
    required this.id,
    required this.reference,
    required this.libelle,
    required this.prixUnitaire,
    required this.quantite,
    required this.ajouteeLe,
    this.categorie,
  });

  final String id;

  /// ⚠ Q1 — voir `reference_catalogue.dart`.
  final ReferenceCatalogue reference;

  /// Libellé **figé à l'ajout** (règle 3).
  final String libelle;

  /// Prix unitaire **figé à l'ajout** (règle 3), en francs CFA.
  final int prixUnitaire;

  final int quantite;
  final String? categorie;
  final DateTime ajouteeLe;

  /// Montant de ligne — **calculé, jamais stocké**.
  ///
  /// Règle non négociable du projet : toute valeur calculable est en lecture
  /// seule. Un montant de ligne stocké finirait par contredire le produit de
  /// ses deux facteurs, et c'est le montant stocké qui l'emporterait.
  int get montant => prixUnitaire * quantite;

  LignePanier copyAvecQuantite(int nouvelle) => LignePanier(
    id: id,
    reference: reference,
    libelle: libelle,
    prixUnitaire: prixUnitaire,
    quantite: nouvelle,
    categorie: categorie,
    ajouteeLe: ajouteeLe,
  );

  @override
  bool operator ==(Object other) => other is LignePanier && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Un panier — au comptant ou sur séjour, la même structure.
final class Panier {
  const Panier({
    required this.id,
    required this.typeVente,
    required this.statut,
    required this.ouvertLe,
    required this.lignes,
    this.reservationId,
    this.clientNom,
    this.pointVente,
    this.tableId,
    this.espace,
    this.dateDepartPrevue,
    this.clotureLe,
    this.modePaiement,
    this.montantCloture,
    this.motifAnnulation,
    this.sessionEncaissementId,
    this.statutTransmission = StatutTransmissionPanier.nonTransmissible,
  });

  final String id;
  final TypeVente typeVente;
  final StatutPanier statut;
  final DateTime ouvertLe;
  final List<LignePanier> lignes;

  /// Renseigné si et seulement si [typeVente] vaut [TypeVente.surSejour].
  final String? reservationId;

  final String? clientNom;

  /// Où se trouve l'argent — jamais ce qui est vendu (PA-79).
  final String? pointVente;

  /// La table de salle qui porte ce panier — **nul au comptoir**.
  ///
  /// Une vente de passage n'a aucune table ; lui en inventer une creerait une
  /// table a ouvrir et fermer qui ne correspond a rien dans la salle.
  final String? tableId;

  /// Le code de l'espace, copie a l'ouverture — un panier cloture reste
  /// lisible meme si la table a depuis ete renumerotee ou desactivee.
  final String? espace;

  final DateTime? dateDepartPrevue;
  final DateTime? clotureLe;
  final String? modePaiement;

  /// Montant figé à la clôture. `null` tant que le panier est ouvert.
  final int? montantCloture;

  final String? motifAnnulation;

  /// La session de caisse qui a encaissé ce panier (`ventes.session_id` du
  /// serveur, schéma v18). `null` : panier ouvert, panier de séjour (note de
  /// chambre, jamais encaissée en caisse), ou clôturé avant la v18.
  final String? sessionEncaissementId;
  final StatutTransmissionPanier statutTransmission;

  /// Total du panier, en francs CFA — **calculé depuis les lignes**.
  ///
  /// Jamais joint au catalogue : c'est la somme des prix figés, pas des prix
  /// du jour. Le panier clôturé garde en plus [montantCloture], qui ne bouge
  /// plus quoi qu'il arrive aux lignes.
  int get total => lignes.fold(0, (t, l) => t + l.montant);

  /// Répartition par module — ce que le séjour a consommé, et où.
  ///
  /// Elle **restitue** la mixité bar/restaurant/tourisme/location ; elle ne la
  /// sépare jamais en plusieurs paniers (règle 4).
  Map<ModuleVendable, int> get ventilation {
    final parModule = <ModuleVendable, int>{};
    for (final l in lignes) {
      parModule[l.reference.module] =
          (parModule[l.reference.module] ?? 0) + l.montant;
    }
    return parModule;
  }

  bool get estOuvert => statut == StatutPanier.ouvert;

  /// Règle 2 — un panier clôturé ou annulé ne reçoit plus rien.
  bool get estModifiable => estOuvert;

  int get nombreArticles => lignes.fold(0, (t, l) => t + l.quantite);

  /// Règle 5 — clôturer maintenant serait-il anticipé ?
  ///
  /// Vrai **uniquement** pour un panier de séjour dont la date de départ est
  /// connue et postérieure au jour de [maintenant]. La comparaison porte sur
  /// le **jour**, pas sur l'instant : clôturer à 9 h le matin du départ n'est
  /// pas une clôture anticipée, et demander confirmation ce jour-là ferait du
  /// garde-fou une formalité qu'on apprend à valider sans lire.
  bool clotureEstAnticipee(DateTime maintenant) {
    if (typeVente != TypeVente.surSejour) return false;
    final depart = dateDepartPrevue;
    if (depart == null) return false;
    final jourDepart = DateTime(depart.year, depart.month, depart.day);
    final jourCourant = DateTime(
      maintenant.year,
      maintenant.month,
      maintenant.day,
    );
    return jourCourant.isBefore(jourDepart);
  }

  Panier copyAvecLignes(List<LignePanier> nouvelles) => Panier(
    id: id,
    typeVente: typeVente,
    statut: statut,
    ouvertLe: ouvertLe,
    lignes: nouvelles,
    reservationId: reservationId,
    clientNom: clientNom,
    pointVente: pointVente,
    dateDepartPrevue: dateDepartPrevue,
    clotureLe: clotureLe,
    modePaiement: modePaiement,
    montantCloture: montantCloture,
    motifAnnulation: motifAnnulation,
    statutTransmission: statutTransmission,
  );

  @override
  bool operator ==(Object other) => other is Panier && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Panier($id, ${typeVente.code}, ${statut.code}, ${lignes.length} ligne(s), $total FCFA)';
}
