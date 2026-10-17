/// Les DOCUMENTS que le poste dépose dans sa file d'envoi, au CONTRAT du
/// serveur (lot F1, 15/10/2026) — une fonction par table, pure, sans base.
///
/// ## La source de chaque contrat
///
/// Les gestionnaires `tatacora-api/app/Shared/Sync/Gestionnaires/*` et les
/// `FormRequest` qu'ils réutilisent : noms en snake_case, unités du serveur.
/// `tool/sync/valider_charge.php` rejoue les règles du serveur sur ces
/// documents (ancrage EXTÉRIEUR, piège 12) — un test le lance.
///
/// ## Les conversions d'unités (le poste compte en entiers)
///
/// | Poste | Serveur | Ici |
/// |---|---|---|
/// | francs entiers (prix, montants de vente, de dépense, tarif) | entier (francs) ou `numeric` | l'entier tel quel |
/// | centimes de franc (fond, constaté, théorique de caisse ; prix d'achat) | `*_centimes` entiers, que le serveur divise par 100 | l'entier tel quel |
/// | centièmes (quantités d'achat et de réception) | `quantite_centiemes` entier | l'entier tel quel |
/// | centièmes (seuil d'alerte d'un article) | `seuil_alerte` `numeric`, `decimal:0,2` | chaîne décimale exacte : 1250 → `"12.50"` |
/// | millièmes (quantité unitaire d'une fiche technique) | `quantite_unitaire` `numeric` | chaîne décimale exacte : 250 → `"0.250"` |
/// | francs (acompte, remise d'une réservation) | `decimal(15,2)` | chaîne `"15000.00"` |
///
/// Aucune conversion ne passe par un `double` : une somme d'argent ne
/// s'arrondit pas en route.
///
/// ## Les dates
///
/// Les champs DATE (`AAAA-MM-JJ`) partent tels quels. Les instants d'un
/// document (ouverture et clôture de caisse, clôture d'une vente) partent en
/// heure LOCALE du poste, sans fuseau (`AAAA-MM-JJ HH:MM:SS`) : le serveur les
/// lit dans son fuseau d'application (`Africa/Porto-Novo`, celui du Gîte), et
/// le rappel de l'ouverture à la clôture doit être comparé à la seconde près
/// à ce qu'il a enregistré (`GestionnaireSessionsCaisse::sansRappelsConformes`).
/// `horodatage_client`, lui, est un instant UTC (posé par `OperationsSyncDao`).
library;

import 'dart:convert';

/* ==================================================================== */
/* Formats                                                               */
/* ==================================================================== */

String _deux(int n) => n.toString().padLeft(2, '0');

/// `AAAA-MM-JJ` d'un instant, en heure locale.
String jourIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_deux(d.month)}-${_deux(d.day)}';

/// `AAAA-MM-JJ HH:MM:SS` en heure LOCALE, sans fuseau (voir l'en-tête).
String instantLocal(DateTime d) {
  final l = d.toLocal();
  return '${jourIso(l)} ${_deux(l.hour)}:${_deux(l.minute)}:${_deux(l.second)}';
}

/// Un entier d'une unité 10^-[decimales] en chaîne décimale exacte :
/// `decimalExact(1250, 2)` → `"12.50"`, `decimalExact(-5, 3)` → `"-0.005"`.
String decimalExact(int valeur, int decimales) {
  final negatif = valeur < 0;
  final absolu = valeur.abs().toString().padLeft(decimales + 1, '0');
  final coupure = absolu.length - decimales;
  final texte = decimales == 0
      ? absolu
      : '${absolu.substring(0, coupure)}.${absolu.substring(coupure)}';
  return negatif ? '-$texte' : texte;
}

/// La catégorie envoyée pour un article SANS catégorie.
///
/// `articles.categorie` est `required` au serveur
/// (`EnregistrerArticleRequest`), et le poste admet de la laisser vide (la
/// colonne locale porte alors une chaîne vide). Plutôt qu'un rejet certain de
/// la synchronisation, le poste envoie cette valeur, lisible et triable, que
/// le gérant corrigera au catalogue. Écart DOCUMENTÉ (lot F1).
const categorieArticleNonRenseignee = 'Non classé';

/* ==================================================================== */
/* Modification : les seuls champs changés                               */
/* ==================================================================== */

/// Les champs de [apres] dont la valeur diffère de [avant] — le payload d'une
/// `modification` (décision du PO du 15/10/2026 : seuls les champs PRÉSENTS
/// changent au serveur). La comparaison porte sur la forme JSON : une liste
/// (composition d'une fiche) est comparée en entier.
Map<String, Object?> champsModifies(
  Map<String, Object?> avant,
  Map<String, Object?> apres,
) => {
  for (final e in apres.entries)
    if (!avant.containsKey(e.key) ||
        jsonEncode(avant[e.key]) != jsonEncode(e.value))
      e.key: e.value,
};

/* ==================================================================== */
/* Catalogue                                                             */
/* ==================================================================== */

/// `points_stockage` — `EnregistrerPointStockageRequest`.
Map<String, Object?> chargePointStockage({
  required String libelle,
  required String? type,
}) => {'libelle': libelle, 'type': type};

/// `articles` — `EnregistrerArticleRequest` (sans les champs calculés,
/// interdits). Le stock d'ouverture n'en fait PAS partie : c'est un mouvement,
/// et le serveur interdit `stock_initial`.
Map<String, Object?> chargeArticle({
  required String libelle,
  required String categorie,
  required String uniteMesure,
  required int seuilCentiemes,
  required String suivi,
  required String? pointStockageId,
}) => {
  'libelle': libelle,
  'categorie': categorie.trim().isEmpty
      ? categorieArticleNonRenseignee
      : categorie,
  'unite_mesure': uniteMesure,
  'seuil_alerte': decimalExact(seuilCentiemes, 2),
  'suivi': suivi,
  'point_stockage_id': pointStockageId,
};

/// `cartes_boisson` — `EnregistrerBoissonRequest`. [articleId] nul : le
/// serveur l'exige (`required`) et REJETTERA l'opération avec sa phrase — une
/// boisson sans article ne peut rien décrémenter (point ouvert, F2).
Map<String, Object?> chargeBoisson({
  required String libelle,
  required String? articleId,
  required String categorie,
  required int prixVenteFrancs,
}) => {
  'libelle': libelle,
  'article_id': articleId,
  'categorie': categorie,
  'prix_vente': prixVenteFrancs,
};

/// `menus` — `EnregistrerMenuRequest`.
Map<String, Object?> chargeMenu({
  required String libelle,
  required String type,
  required String? dateDebut,
  required String? dateFin,
}) => {
  'libelle': libelle,
  'type': type,
  'date_debut': dateDebut,
  'date_fin': dateFin,
};

/// `recettes` — `EnregistrerRecetteRequest` + `EnregistrerCompositionRequest`
/// : la composition entière, quantité unitaire en DÉCIMAL (millièmes → 3
/// décimales). La composition est REMPLACÉE au serveur, jamais fusionnée.
Map<String, Object?> chargeRecette({
  required String libelle,
  required List<({String articleId, int milliemes})> lignes,
}) => {
  'libelle': libelle,
  'lignes': [
    for (final l in lignes)
      {
        'article_id': l.articleId,
        'quantite_unitaire': decimalExact(l.milliemes, 3),
      },
  ],
};

/// `plats` — `EnregistrerPlatRequest`.
Map<String, Object?> chargePlat({
  required String libelle,
  required String menuId,
  required String recetteId,
  required int prixVenteFrancs,
  required bool prixProvisoire,
  required bool prixCorrigeMain,
}) => {
  'libelle': libelle,
  'menu_id': menuId,
  'recette_id': recetteId,
  'prix_vente': prixVenteFrancs,
  'prix_provisoire': prixProvisoire,
  'prix_corrige_main': prixCorrigeMain,
};

/// `categories_hebergement` — `EnregistrerCategorieHebergementRequest`.
Map<String, Object?> chargeCategorieHebergement({
  required String libelle,
  required int tarifBaseFrancs,
  required int capaciteMax,
}) => {
  'libelle': libelle,
  'tarif_base': tarifBaseFrancs,
  'capacite_max': capaciteMax,
};

/// `unites_hebergement` — `EnregistrerUniteHebergementRequest`. Le statut ne
/// part jamais : le cycle appartient à `SejourService` au serveur, qui
/// l'ignore. L'archivage part en `{'actif': false|true}`.
Map<String, Object?> chargeUniteHebergement({
  required String numero,
  required String categorieId,
}) => {'numero': numero, 'categorie_id': categorieId};

/// `fournisseurs` — `EnregistrerFournisseurRequest`. L'archivage part en
/// `{'actif': false|true}`.
Map<String, Object?> chargeFournisseur({
  required String raisonSociale,
  required String? contact,
  required String? categorie,
  required String? conditionsPaiement,
  required String? evaluation,
}) => {
  'raison_sociale': raisonSociale,
  'contact': contact,
  'categorie': categorie,
  'conditions_paiement': conditionsPaiement,
  'evaluation': evaluation,
};

/// `clients` — `EnregistrerClientRequest`.
Map<String, Object?> chargeClient({
  required String nom,
  required String? prenom,
  required String telephone,
  required String? email,
  required String typeClient,
}) => {
  'nom': nom,
  'prenom': prenom,
  'telephone': telephone,
  'email': email,
  'type_client': typeClient,
};

/* ==================================================================== */
/* Documents                                                             */
/* ==================================================================== */

/// `reservations` (création seule) — colonnes `fillable` de `Reservation`,
/// écrites par `ReservationService::creer`. Le canal ne part pas : le serveur
/// attend un `canal_id` (clé étrangère vers SES canaux), le poste ne détient
/// qu'un code. L'acompte et la remise en francs, à deux décimales.
Map<String, Object?> chargeReservation({
  required String clientId,
  required String uniteId,
  required DateTime dateArrivee,
  required DateTime dateDepart,
  required String statut,
  required int acompteFrancs,
  required int tarifNuitFrancs,
  required String remiseType,
  required num? remiseValeur,
  required String? modePaiement,
}) => {
  'client_id': clientId,
  'unite_id': uniteId,
  'date_arrivee': jourIso(dateArrivee),
  'date_depart': jourIso(dateDepart),
  'statut': statut,
  'acompte': decimalExact(acompteFrancs * 100, 2),
  'tarif_nuit': decimalExact(tarifNuitFrancs * 100, 2),
  'remise_type': remiseType,
  'remise_valeur': remiseType == 'aucune' || remiseValeur == null
      ? '0.00'
      : decimalExact((remiseValeur * 100).round(), 2),
  'mode_paiement': modePaiement,
};

/// `commandes_achat` (création seule) — `GestionnaireCommandesAchat` : les
/// lignes en CENTIÈMES et en CENTIMES entiers, comme le poste les stocke.
Map<String, Object?> chargeCommandeAchat({
  required String fournisseurId,
  required String dateCommande,
  required String statut,
  required List<
    ({
      String articleId,
      String articleLibelle,
      String uniteMesure,
      int quantiteCentiemes,
      int prixUnitaireCentimes,
      int rang,
    })
  >
  lignes,
}) => {
  'fournisseur_id': fournisseurId,
  'date_commande': dateCommande,
  'statut': statut,
  'lignes': [
    for (final l in lignes)
      {
        'article_id': l.articleId,
        'article_libelle': l.articleLibelle,
        'unite_mesure': l.uniteMesure,
        'quantite_centiemes': l.quantiteCentiemes,
        'prix_unitaire_centimes': l.prixUnitaireCentimes,
        'rang': l.rang,
      },
  ],
};

/// `bons_reception` (création seule) — `GestionnaireBonsReception`. Le
/// verdict du poste part pour comparaison : le serveur recalcule le sien et
/// SIGNALE l'écart.
Map<String, Object?> chargeBonReception({
  required String commandeId,
  required String dateReception,
  required String pointStockageId,
  required String conformite,
  required List<({String articleId, int quantiteCentiemes})> lignes,
}) => {
  'commande_id': commandeId,
  'date_reception': dateReception,
  'point_stockage_id': pointStockageId,
  'conformite': conformite,
  'lignes': [
    for (final l in lignes)
      {'article_id': l.articleId, 'quantite_centiemes': l.quantiteCentiemes},
  ],
};

/// `sessions_caisse`, OUVERTURE (création) — `GestionnaireSessionsCaisse`.
Map<String, Object?> chargeOuvertureCaisse({
  required String pointVente,
  required DateTime dateOuverture,
  required int fondCentimes,
}) => {
  'point_vente': pointVente,
  'date_ouverture': instantLocal(dateOuverture),
  'montant_fond_centimes': fondCentimes,
};

/// `sessions_caisse`, CLÔTURE (la seule modification admise). Elle porte, en
/// plus de ses trois champs, le RAPPEL de l'ouverture (fond, date, point) :
/// une clôture d'une caisse que le serveur ne connaît pas (ouverture refusée
/// ou perdue) est alors ENREGISTRÉE avec les chiffres du poste, jamais
/// refusée (`modificationSurInconnu`) ; sur une caisse connue, un rappel
/// conforme est ignoré par le serveur.
Map<String, Object?> chargeClotureCaisse({
  required DateTime dateCloture,
  required int constateCentimes,
  required int theoriqueCentimes,
  required int fondCentimes,
  required DateTime dateOuverture,
  required String pointVente,
}) => {
  'date_cloture': instantLocal(dateCloture),
  'montant_constate_centimes': constateCentimes,
  'montant_theorique_centimes': theoriqueCentimes,
  'montant_fond_centimes': fondCentimes,
  'date_ouverture': instantLocal(dateOuverture),
  'point_vente': pointVente,
};

/// `ventes` (création seule, AU COMPTANT) — `GestionnaireVentes`. Prix et
/// total en francs entiers ; le prix du poste fait foi (le serveur signale
/// l'écart avec son catalogue, il ne corrige pas).
Map<String, Object?> chargeVente({
  String typeVente = 'comptant',
  String? reservationId,
  required String modePaiement,
  required String? sessionEncaissementId,
  required DateTime clotureLe,
  required String? pointVente,
  required String? tableId,
  required String? clientNom,
  required int montantCloture,
  required List<
    ({
      String moduleSource,
      String codeArticle,
      String libelle,
      int prixUnitaire,
      int quantite,
    })
  >
  lignes,
}) => {
  'type_vente': typeVente,
  // Lot F5 : la note de chambre cite SA réservation (le serveur en prend le
  // client et l'unité).
  'reservation_id': ?reservationId,
  'mode_paiement': modePaiement,
  'session_encaissement_id': sessionEncaissementId,
  'cloture_le': instantLocal(clotureLe),
  'point_vente': pointVente,
  'table_id': tableId,
  'client_nom': clientNom,
  'montant_cloture': montantCloture,
  'lignes': [
    for (final l in lignes)
      {
        'module_source': l.moduleSource,
        'code_article': l.codeArticle,
        'libelle': l.libelle,
        'prix_unitaire': l.prixUnitaire,
        'quantite': l.quantite,
      },
  ],
};

/// `depenses` (création seule) — `GestionnaireDepenses`. Montants en francs
/// ENTIERS ; le centre de coût est celui de la PIÈCE passée sur le poste
/// (`depenses_local` n'a pas de colonne centre), par identifiant ET libellé :
/// le serveur le résout par l'un puis l'autre.
Map<String, Object?> chargeDepense({
  required DateTime dateTransaction,
  required String tresorerie,
  required String libelle,
  required String? centreId,
  required String? centreLibelle,
  required List<
    ({
      String libelle,
      String compteCharge,
      String nature,
      String famille,
      int montant,
    })
  >
  lignes,
}) => {
  'date_transaction': jourIso(dateTransaction),
  'tresorerie': tresorerie,
  'libelle': libelle,
  'centre_id': centreId,
  'centre_libelle': centreLibelle,
  'lignes': [
    for (final l in lignes)
      {
        'libelle': l.libelle,
        'compte_charge': l.compteCharge,
        'nature': l.nature,
        'famille': l.famille,
        'montant': l.montant,
      },
  ],
};

/* ==================================================================== */
/* Tourisme (lot F4, 17/10/2026)                                          */
/* ==================================================================== */

/// `circuits` — `EnregistrerCircuitRequest`. Le prix en francs, à deux
/// décimales ; une durée absente part `null` (le serveur la range vide).
Map<String, Object?> chargeCircuit({
  required String nom,
  required String theme,
  required String zone,
  required int prixFrancs,
  required int capaciteMax,
  required String? duree,
}) => {
  'nom': nom,
  'theme': theme,
  'zone': zone,
  'prix': decimalExact(prixFrancs * 100, 2),
  'capacite_max': capaciteMax,
  'duree': duree,
};

/// `guides` — `EnregistrerGuideRequest`. Pas de tarif : le poste ne le
/// saisit pas (le serveur range 0 et le signale).
Map<String, Object?> chargeGuide({
  required String nom,
  required String? zoneCompetence,
}) => {'nom': nom, 'zone_competence': zoneCompetence};

/// `reservations_tour` (création) — `ReserverCircuitRequest`.
Map<String, Object?> chargeReservationTour({
  required String circuitId,
  required String clientId,
  required String guideId,
  required DateTime dateCircuit,
  required int nbParticipants,
}) => {
  'circuit_id': circuitId,
  'client_id': clientId,
  'guide_id': guideId,
  'date_circuit': jourIso(dateCircuit),
  'nb_participants': nbParticipants,
};

/* ==================================================================== */
/* Séjours (lot F5, 17/10/2026)                                           */
/* ==================================================================== */

/// `sejours`, ARRIVÉE (création) — `GestionnaireSejours`. L'heure réelle du
/// poste ; les occupants relevés (aucun sur ce poste : liste vide).
Map<String, Object?> chargeArrivee({
  required String reservationId,
  required DateTime arrivee,
}) => {
  'reservation_id': reservationId,
  'date_checkin_reel': instantLocal(arrivee),
  'occupants': const <Object?>[],
};

/// `sejours`, DÉPART (modification).
Map<String, Object?> chargeDepart({required DateTime depart}) => {
  'date_checkout_reel': instantLocal(depart),
};
