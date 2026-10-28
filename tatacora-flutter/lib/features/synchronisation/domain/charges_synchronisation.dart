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

import '../../facturation/domain/entities/piece_facturation.dart'
    show StatutPiece;

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

/// `canaux_reservation` (création) — `GestionnaireCanauxReservation` : le NOM
/// (clé naturelle, insensible à la casse) et l'état. Le même nom saisi sur deux
/// postes fusionne au serveur.
Map<String, Object?> chargeCanalReservation({
  required String nom,
  required bool actif,
}) => {'nom': nom, 'actif': actif};

/// `canaux_reservation` (modification) — l'ÉTAT ENTIER (nom, actif), plus
/// l'ANCIEN nom quand le geste est un renommage : un canal aligné par son nom
/// à la descente garde ici un identifiant que le serveur ne connaît pas, et
/// l'ancien nom le lui fait retrouver (sinon « Physique » → « Comptoir » créerait
/// un second canal au lieu de renommer le premier).
Map<String, Object?> chargeCanalReservationModifie({
  required String nom,
  required bool actif,
  String? ancienNom,
}) => {'nom': nom, 'ancien_nom': ?ancienNom, 'actif': actif};

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
///
/// [unitesVendables] : le conditionnement du lien (`24` pour un casier de 24),
/// en TEXTE décimal. La clé n'est écrite que s'il est connu : un `null` serait
/// refusé par la règle `numeric` du serveur, et l'absence laisse le serveur
/// garder le sien. Le serveur le reçoit depuis le 26/10/2026
/// (`GestionnaireCartesBoisson`) — sans lui, « Lier au stock » au poste ne
/// changeait RIEN chez le serveur.
Map<String, Object?> chargeBoisson({
  required String libelle,
  required String? articleId,
  required String categorie,
  required int prixVenteFrancs,
  String? unitesVendables,
}) => {
  'libelle': libelle,
  'article_id': articleId,
  'categorie': categorie,
  'prix_vente': prixVenteFrancs,
  'unites_vendables_par_unite_stock': ?unitesVendables,
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
  String? articleId,
  String? unitesVendables,
  String? categorie,
}) => {
  'libelle': libelle,
  'menu_id': menuId,
  'recette_id': recetteId,
  'prix_vente': prixVenteFrancs,
  // Depuis la v41 : la catégorie du plat, l'une des dix clés de la carte (le
  // serveur l'accepte en synchronisation et la valide contre ce registre). Absente
  // d'un plat d'avant : jamais envoyée en `null`.
  'categorie': ?categorie,
  'prix_provisoire': prixProvisoire,
  'prix_corrige_main': prixCorrigeMain,
  // Le lien direct au stock (v36) : les DEUX champs vont ensemble, ou aucun
  // (`CartePlatMenuService`). Absents d'un plat sans lien ; le retrait du lien
  // part en `null` explicite (voir `RestaurantDao`).
  'article_id': ?articleId,
  if (articleId != null) 'unites_vendables_par_unite_stock': unitesVendables,
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

/// `clients`, ARCHIVAGE ou RESTAURATION (modification) —
/// `GestionnaireClients` : `actif` seul. Le serveur archive par
/// `ReferentielClientService` (quatre verrous) sous la règle d'archivage de la
/// directive du 03/09/2026 ; restaurer ne se refuse jamais.
Map<String, Object?> chargeArchivageClient({required bool actif}) => {
  'actif': actif,
};

/// `relances_clients` (création) — `GestionnaireRelancesClients` : un FAIT daté,
/// jamais modifié. Le montant réclamé voyage en CENTIMES -> chaîne décimale
/// exacte (`"15000.00"`, jamais un `double`) : c'est ce qui a été DIT au client
/// ce jour-là. Promesse et commentaire absents partent `null`.
Map<String, Object?> chargeRelanceClient({
  required String clientId,
  required DateTime dateRelance,
  required String canal,
  required int montantReclameCentimes,
  required DateTime? promesse,
  required String? commentaire,
}) => {
  'client_id': clientId,
  'date_relance': jourIso(dateRelance),
  'canal': canal,
  'montant_reclame': decimalExact(montantReclameCentimes, 2),
  'promesse': promesse == null ? null : jourIso(promesse),
  'commentaire': commentaire,
};

/* ==================================================================== */
/* Documents                                                             */
/* ==================================================================== */

/// `reservations` (création seule) — colonnes `fillable` de `Reservation`,
/// écrites par `ReservationService::creer`. Le canal part par son NOM (lot
/// 10f) : le serveur tient `canal_id` vers SES canaux, semés sous les mêmes
/// noms (`CanauxReservationSeeder::CANAUX_INITIAUX`) ; un nom inconnu y reste
/// sans canal. L'acompte et la remise en francs, à deux décimales.
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
  String? canal,
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
  'canal': canal,
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
/// l'écart avec son catalogue, il ne corrige pas). Avec une remise,
/// [montantCloture] est le NET (arrondi au franc : le poste compte en francs
/// entiers, le serveur garde les centimes de sa formule).
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
  String remiseType = 'aucune',
  int remiseValeurCentiemes = 0,
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
  // 21/10/2026 : la remise du panier, telle que saisie (type + valeur, jamais
  // un montant pré-calculé) ; `montant_cloture` est alors le NET. Absente
  // quand il n'y en a pas : le document d'avant reste le même.
  if (remiseType != 'aucune') ...{
    'remise_type': remiseType,
    'remise_valeur': decimalExact(remiseValeurCentiemes, 2),
  },
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

/// `guides` — `EnregistrerGuideRequest`. La certification et le tarif
/// journalier n'existent pas dans `guides_local` : quand l'exploitant les
/// saisit (modale « Ajouter un guide touristique »), ils partent au serveur
/// SANS être rangés ici. Absents, le serveur range un tarif de 0 et le signale.
Map<String, Object?> chargeGuide({
  required String nom,
  required String? zoneCompetence,
  String? certification,
  int? tarifJourFrancs,
}) => {
  'nom': nom,
  'zone_competence': zoneCompetence,
  'certification': ?certification,
  'tarif_jour': ?tarifJourFrancs,
};

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

/* ==================================================================== */
/* Factures et encaissements (lots F5c et F5d, 17/10/2026)                */
/* ==================================================================== */

/// `factures` (création) — `GestionnaireFactures`. Le poste envoie le PRIX
/// VENDU de chaque ligne en francs entiers ; le serveur calcule hors-taxe,
/// TVA et totaux, et rend son numéro continu (`F-AAAA-NNNNN`). Le numéro
/// provisoire du poste ne part pas : il n'a de sens qu'ici.
Map<String, Object?> chargeFacture({
  required String origine,
  required DateTime dateEmission,
  required String? clientId,
  required String? reservationId,
  required String? panierId,
  required List<
    ({String module, String libelle, int prixUnitaire, int quantite})
  >
  lignes,
}) => {
  'origine': origine,
  'date_emission': jourIso(dateEmission),
  'client_id': clientId,
  'reservation_id': reservationId,
  'panier_id': panierId,
  'lignes': [
    for (final l in lignes)
      {
        'module': l.module,
        'libelle': l.libelle,
        'prix_unitaire': l.prixUnitaire,
        'quantite': l.quantite,
      },
  ],
};

/// `factures`, ANNULATION (la seule modification) : le serveur émet l'avoir
/// du TTC entier et rend son numéro (`AV-AAAA-NNNNN`).
Map<String, Object?> chargeAnnulationFacture({required String motif}) => {
  // Le mot du serveur est celui du registre local (`StatutPiece`).
  'statut': StatutPiece.annulee.code,
  'motif': motif,
};

/// `factures`, AVOIR PARTIEL (modification, sans `statut`) —
/// `GestionnaireFactures` : `emettreAvoir($facture, $montant, $motif)` de la
/// PWA. Le montant en FRANCS entiers (le serveur le range à deux décimales) ;
/// [avoirId] est l'identifiant de l'avoir sur CE poste : l'avoir naît sous cet
/// UUID au serveur (rejeu sans doublon, reconnu à la descente), et le numéro
/// rendu est celui de CET avoir. Le plafond (TTC) est celui du service : un
/// montant plus grand est rejeté avec sa phrase.
Map<String, Object?> chargeAvoirPartielFacture({
  required int montantFrancs,
  required String motif,
  required String avoirId,
}) => {'montant': montantFrancs, 'motif': motif, 'avoir_id': avoirId};

/// `paiements` (création) — `GestionnairePaiements`. Montant en CENTIMES
/// (le serveur divise par 100), la caisse du poste qui a reçu l'argent,
/// l'instant local du geste.
Map<String, Object?> chargePaiementFacture({
  required String factureId,
  required String sessionId,
  required String modePaiement,
  required int montantCentimes,
  required DateTime datePaiement,
}) => {
  'facture_id': factureId,
  'session_id': sessionId,
  'mode_paiement': modePaiement,
  'montant': montantCentimes,
  'date_paiement': instantLocal(datePaiement),
};

/// `paiements`, ANNULATION (la seule modification) : contre-passation au
/// serveur.
Map<String, Object?> chargeAnnulationPaiement({required String motif}) => {
  'statut': 'annule',
  'motif': motif,
};

/* ==================================================================== */
/* Cycle de vie (lot F6, 17/10/2026)                                      */
/* ==================================================================== */

/// `reservations`, ANNULATION — `GestionnaireReservations` →
/// `AnnulationReservationService`. Le poste envoie le taux qu'il a appliqué
/// et le MONTANT qu'il a remboursé (mode `montant`) : les deux côtés
/// remboursent la même somme au centime, même quand la saisie était en
/// pourcentage (écart nommé : le serveur note alors le mode « montant »).
Map<String, Object?> chargeAnnulationReservation({
  required int tauxCentiemes,
  required int rembourseCentimes,
}) => {
  'statut': 'annulee',
  'taux': decimalExact(tauxCentiemes, 2),
  'mode_remboursement': 'montant',
  'valeur_remboursement': decimalExact(rembourseCentimes, 2),
};

/// `reservations`, DÉPLACEMENT — les seuls champs CHANGÉS parmi la chambre
/// et les dates (`ReservationService::modifier`, RG-01 au serveur).
Map<String, Object?> chargeDeplacementReservation({
  String? uniteId,
  DateTime? dateArrivee,
  DateTime? dateDepart,
}) => {
  'unite_id': ?uniteId,
  if (dateArrivee != null) 'date_arrivee': jourIso(dateArrivee),
  if (dateDepart != null) 'date_depart': jourIso(dateDepart),
};

/// `commandes_achat`, STATUT — `envoyee` ou `cloturee`, par leurs services.
Map<String, Object?> chargeStatutCommande(String statut) => {'statut': statut};

/* ==================================================================== */
/* Retraits de la carte du jour (21/10/2026)                              */
/* ==================================================================== */

/// `indisponibilites_carte` (création) — `GestionnaireIndisponibilitesCarte` :
/// EXACTEMENT un de [boissonId] / [platId] (le serveur refuse les deux, ou
/// aucun), le motif du registre fermé, l'instant du retrait au poste. Le
/// serveur fusionne si l'article est déjà retiré.
Map<String, Object?> chargeIndisponibiliteCarte({
  String? boissonId,
  String? platId,
  required String motif,
  String? commentaire,
  required DateTime date,
}) => {
  'boisson_id': ?boissonId,
  'plat_id': ?platId,
  'motif': motif,
  'commentaire': ?commentaire,
  'date_indisponibilite': instantLocal(date),
};

/// `indisponibilites_carte` (modification) : la REMISE à la carte, seule
/// modification admise.
Map<String, Object?> chargeRemiseALaCarte(DateTime date) => {
  'date_retour_disponibilite': instantLocal(date),
};

/* ==================================================================== */
/* Tables de salle (lot F6, 18/10/2026)                                   */
/* ==================================================================== */

/// `tables_salle` (création) — `GestionnaireTablesSalle` : la clé naturelle
/// (espace, numéro) fusionne au serveur.
Map<String, Object?> chargeTableSalle({
  required String espace,
  required int numero,
  required int places,
}) => {'espace': espace, 'numero': numero, 'places': places};

/// `paniers` (création) : l'OUVERTURE d'une addition sur une table — le
/// serveur l'arbitre (une table, un panier ouvert, tous postes confondus).
Map<String, Object?> chargeOuvertureTable({
  required String pointVente,
  required String tableId,
}) => {'point_vente': pointVente, 'table_id': tableId};

/// `paniers` (modification) : la FERMETURE de l'addition (vente ou abandon).
Map<String, Object?> chargeFermetureTable() => {'statut': 'cloture'};

/* ==================================================================== */
/* Règlements fournisseur (audit de couverture, 18/10/2026)               */
/* ==================================================================== */

/// `reglements_fournisseur` (création) — `GestionnaireReglementsFournisseur` :
/// montant en CENTIMES (le serveur divise par 100), la trésorerie du poste, le
/// jour du règlement.
Map<String, Object?> chargeReglementFournisseur({
  required String commandeId,
  required int montantCentimes,
  required String tresorerie,
  required String dateReglement,
}) => {
  'commande_id': commandeId,
  'montant': montantCentimes,
  'tresorerie': tresorerie,
  'date_reglement': dateReglement,
};

/* ==================================================================== */
/* Véhicules (audit de couverture, 18/10/2026)                            */
/* ==================================================================== */

/// `vehicules` (création) — `GestionnaireVehicules`. Depuis la v41 (27/10/2026) le
/// poste saisit l'année, les places (`capacite`) et la transmission comme le web ;
/// un véhicule d'avant n'en a pas et l'année absente est rangée à 0 par le
/// serveur, qui la SIGNALE. Les clés absentes ne sont pas envoyées (jamais un
/// `null` qui vaudrait « effacer »).
Map<String, Object?> chargeVehicule({
  required String immatriculation,
  required String categorie,
  required int tarifJour,
  int? annee,
  int? capacite,
  String? transmission,
}) => {
  'immatriculation': immatriculation,
  'categorie': categorie,
  'tarif_jour': tarifJour,
  'annee': ?annee,
  'capacite': ?capacite,
  'transmission': ?transmission,
};

/// `entretiens_vehicule` (création) — `GestionnaireEntretiensVehicule` : un fait
/// daté (jour, francs entiers), jamais modifié ; le chauffeur est facultatif.
Map<String, Object?> chargeEntretienVehicule({
  required String vehiculeId,
  required String type,
  required DateTime date,
  required int coutFrancs,
  String? chauffeurId,
}) => {
  'vehicule_id': vehiculeId,
  'type': type,
  'date': jourIso(date),
  'cout': coutFrancs,
  'chauffeur_id': ?chauffeurId,
};

/// `plannings` (création) — `GestionnairePlannings` : un créneau se crée, il ne
/// se modifie pas. Le jour en `AAAA-MM-JJ`, les heures en `HH:MM`. Le service
/// part par identifiant ET libellé : tant que le poste n'a rien reçu, son
/// identifiant lui est propre, et le serveur retombe sur le libellé.
Map<String, Object?> chargePlanning({
  required String employeId,
  required String serviceId,
  required String serviceLibelle,
  required DateTime date,
  required String heureDebut,
  required String heureFin,
}) => {
  'employe_id': employeId,
  'service_id': serviceId,
  'service_libelle': serviceLibelle,
  'date': jourIso(date),
  'heure_debut': heureDebut,
  'heure_fin': heureFin,
};

/// `conges` (création) — `GestionnaireConges` : la DEMANDE, toujours acceptée
/// par le serveur ; sa décision part ensuite en [chargeDecisionConge].
Map<String, Object?> chargeConge({
  required String employeId,
  required String type,
  required DateTime dateDebut,
  required DateTime dateFin,
}) => {
  'employe_id': employeId,
  'type': type,
  'date_debut': jourIso(dateDebut),
  'date_fin': jourIso(dateFin),
};

/// `conges` (modification) — la seule admise : la décision, `valide` ou
/// `refuse`. Le serveur la rejoue par `valider` / `refuser` (RG-14 sur le
/// préavis et la couverture, avec SES paramètres).
Map<String, Object?> chargeDecisionConge({required bool valide}) => {
  'statut_validation': valide ? 'valide' : 'refuse',
};

/// `contrats_location` (création) — `GestionnaireContratsLocation` : les
/// numéros de pièce et de permis SAISIS (le poste ne les garde pas en base).
Map<String, Object?> chargeContratLocation({
  required String vehiculeId,
  required String clientId,
  required String? guideId,
  required DateTime debut,
  required DateTime fin,
  required String pieceIdentite,
  required String? permisConduire,
  int? remiseFrancs,
  int? acompteFrancs,
}) => {
  'vehicule_id': vehiculeId,
  'client_id': clientId,
  'guide_id': guideId,
  'date_debut': jourIso(debut),
  'date_fin': jourIso(fin),
  'piece_identite': pieceIdentite,
  'permis_conduire': permisConduire,
  // Depuis la v41 : la remise et l'acompte (FCFA entiers) de la signature. Le
  // serveur juge `remise <= brut` puis `acompte <= net` avec les phrases de la
  // vue et range le montant NET ; absents (poste d'avant), il range le brut.
  'remise': ?remiseFrancs,
  'acompte': ?acompteFrancs,
};

/// `contrats_location` (modification) — l'ANNULATION, la seule admise
/// (`GestionnaireContratsLocation::modifier`, par `ContratLocationService::annuler`).
Map<String, Object?> chargeAnnulationContratLocation() => {'statut': 'annule'};

/* ==================================================================== */
/* RH et paie (audit de couverture, 18/10/2026)                           */
/* ==================================================================== */

/// `employes` (création, ou les champs d'une modification) —
/// `GestionnaireEmployes`. Le service part par identifiant ET libellé (le
/// référentiel est semé des deux côtés) ; le salaire en francs entiers ; le
/// matricule ne part pas (c'est celui du serveur qui revient).
Map<String, Object?> chargeEmploye({
  required String nom,
  required String prenom,
  required String poste,
  required String serviceId,
  required String serviceLibelle,
  required DateTime dateEmbauche,
  required int salaireBase,
  required DateTime? dateFinContrat,
  required String? numeroCnss,
  required String? typeContrat,
  required String statut,
}) => {
  'nom': nom,
  'prenom': prenom,
  'poste': poste,
  'service_id': serviceId,
  'service_libelle': serviceLibelle,
  'date_embauche': jourIso(dateEmbauche),
  'salaire_base': salaireBase,
  'numero_cnss': numeroCnss,
  'type_contrat': typeContrat,
  'date_fin_contrat': dateFinContrat == null ? null : jourIso(dateFinContrat),
  'statut': statut,
};

/// `bulletins_paie` (création) : le serveur RECALCULE avec son barème ; le
/// net du poste part pour la comparaison (un écart est signalé).
Map<String, Object?> chargeBulletinPaie({
  required String employeId,
  required String periode,
  required int netAPayer,
}) => {'employe_id': employeId, 'periode': periode, 'net_a_payer': netAPayer};

/// `bulletins_paie`, ANNULATION (la seule modification).
Map<String, Object?> chargeAnnulationBulletin({required String motif}) => {
  'statut': 'annulee',
  'motif': motif,
};

/// `ventes`, ANNULATION (la seule modification) — `GestionnaireVentes::
/// modifier` : `statut: annulee` et `motif`, par `VenteService::annuler`
/// (contre-passation de la pièce du serveur, retour des boissons au stock).
Map<String, Object?> chargeAnnulationVente({required String motif}) => {
  'statut': 'annulee',
  'motif': motif,
};

/// `parametres_systeme` (création seule, lot 10e) : UN enregistrement de
/// l'écran Paramètres — les clés réellement modifiées et leur valeur
/// normalisée (`null` = vidée). Le serveur juge la cohérence sur l'état
/// résultant du LOT, et arbitre clé par clé (dernier écrit gagnant).
Map<String, Object?> chargeEnregistrementParametres(
  Map<String, String?> valeurs,
) => {
  'valeurs': {for (final e in valeurs.entries) e.key: e.value},
};

/// `roles` (création ou modification, lot 10e) : TOUJOURS le libellé et la
/// matrice entière — un rôle du socle né sous un autre UUID au serveur s'y
/// retrouve par son libellé.
Map<String, Object?> chargeRole({
  required String libelle,
  required String? description,
  required Map<String, String> droits,
}) => {
  'libelle': libelle,
  'description': description,
  'droits': {for (final e in droits.entries) e.key: e.value},
};

/// `mouvements_stock` (création seule, lot 10f) : un mouvement SAISI sur ce
/// poste. Quantité en centièmes, coût en dix-millièmes (entrée seule) ; le
/// serveur l'écrit même si son stock ne le couvre pas (le mouvement a eu
/// lieu) et le signale si le poste ne l'avait pas forcé.
Map<String, Object?> chargeMouvementStock({
  required String articleId,
  required String pointId,
  required String type,
  required int centiemes,
  required String motif,
  required int? coutDixMilliemes,
  required bool ruptureForcee,
  required DateTime le,
}) => {
  'article_id': articleId,
  'point_id': pointId,
  'type_mouvement': type,
  'quantite': centiemes,
  'motif': motif,
  'cout_unitaire': coutDixMilliemes,
  'rupture_forcee': ruptureForcee,
  'date_mouvement': instantLocal(le),
};

/// `modeles_notification` (lot 10f) : l'état ENTIER du modèle — une
/// configuration, jamais un envoi.
Map<String, Object?> chargeModeleNotification({
  required String evenement,
  required String canal,
  required String? objet,
  required String contenuTemplate,
  required bool actif,
}) => {
  'evenement': evenement,
  'canal': canal,
  'objet': objet,
  'contenu_template': contenuTemplate,
  'actif': actif,
};

/// `plan_comptable` (création seule, 28/10/2026, D246 rouvert) —
/// `GestionnairePlanComptable` : le compte tel que `PlanComptableService::creerCompte`
/// le prend. La classe ne part pas : elle est DÉRIVÉE du numéro, des deux côtés.
Map<String, Object?> chargeCompte({
  required String numeroCompte,
  required String libelle,
  required String nature,
}) => {'numero_compte': numeroCompte, 'libelle': libelle, 'nature': nature};

/// `pieces_saisie` (création seule, 28/10/2026, D246 rouvert) —
/// `GestionnairePiecesSaisie` : la SOURCE d'une saisie manuelle, jamais une
/// écriture. Journal (code), date `AAAA-MM-JJ`, libellé, statut (`brouillon` ou
/// `validee`) et lignes : compte par son NUMÉRO, débit et crédit en CENTIMES
/// entiers, libellé de ligne et centre de coût seulement s'ils ont été saisis
/// (sinon le serveur applique RG-12 à SON plan). Le centre voyage par son
/// LIBELLÉ, jamais par l'identifiant du poste (le poste et le serveur ne
/// partagent pas leurs identifiants de centre). Le numéro de pièce ne part pas :
/// c'est celui du serveur.
Map<String, Object?> chargePieceSaisie({
  required String journal,
  required String date,
  required String libelle,
  required String statut,
  required List<
    ({
      String compte,
      int debitCentimes,
      int creditCentimes,
      String? libelle,
      String? centreLibelle,
    })
  >
  lignes,
}) => {
  'journal': journal,
  'date': date,
  'libelle': libelle,
  'statut': statut,
  'lignes': [
    for (final l in lignes)
      {
        'compte': l.compte,
        'debit': l.debitCentimes,
        'credit': l.creditCentimes,
        'libelle': ?l.libelle,
        'centre': ?l.centreLibelle,
      },
  ],
};

/// `immobilisations` (création seule, 21/10/2026) —
/// `GestionnaireImmobilisations` : le bien, sa valeur d'origine en CENTIMES
/// entiers (le serveur : `DECIMAL(15,2)`), sa mise en service en `AAAA-MM-JJ`
/// et sa durée d'utilité en années. Le code ne part pas : c'est celui de la
/// séquence du serveur qui revient. Le plan d'amortissement ne part pas non plus
/// (il se calcule).
Map<String, Object?> chargeImmobilisation({
  required String libelle,
  required String? compteImmobilisation,
  required int valeurOrigineCentimes,
  required String dateMiseService,
  required int dureeAnnees,
}) => {
  'libelle': libelle,
  'compte_immobilisation': compteImmobilisation,
  'valeur_origine': valeurOrigineCentimes,
  'date_mise_service': dateMiseService,
  'duree_annees': dureeAnnees,
};

/// `inventaires` (création seule, 21/10/2026) — `GestionnaireInventaires` : un
/// inventaire physique CLÔTURÉ, en UN document : le point, le jour
/// (`AAAA-MM-JJ`) et ses lignes comptées. Chaque ligne porte son théorique
/// FIGÉ au comptage, le constaté et l'écart, en CENTIÈMES entiers ; le serveur
/// les écrit tels quels (il ne les recalcule pas) et vérifie seulement
/// `écart = constaté − théorique`. La régularisation, elle, part à part en
/// mouvements de stock.
Map<String, Object?> chargeInventaire({
  required String pointId,
  required DateTime date,
  required List<
    ({
      String id,
      String articleId,
      int theoriqueCentiemes,
      int constateCentiemes,
      int ecartCentiemes,
    })
  >
  lignes,
}) => {
  'point_id': pointId,
  'date_inventaire': jourIso(date),
  'lignes': [
    for (final l in lignes)
      {
        'id': l.id,
        'article_id': l.articleId,
        'quantite_theorique': l.theoriqueCentiemes,
        'quantite_constatee': l.constateCentiemes,
        'ecart': l.ecartCentiemes,
      },
  ],
};

/// `demandes_cloture_exercice` (création seule, 26/10/2026) —
/// `GestionnaireDemandesCloture` : l'ANNÉE de l'exercice, l'ACTION
/// (`demarrer`, `reprendre_saisie`, `cloturer`, `rouvrir`) et, pour une
/// réouverture, le motif. Une demande, jamais une pièce (D246) : le serveur
/// rejoue `ClotureExerciceService` et passe ses propres pièces CL et AN.
Map<String, Object?> chargeDemandeCloture({
  required int annee,
  required String action,
  String? motif,
}) => {'annee': annee, 'action': action, 'motif': ?motif};

/// `articles` (modification) — l'archivage (`false`) ou la restauration
/// (`true`) : le serveur l'applique par `ReferentielArticleService`, sous ses
/// verrous (stock, commande en cours, carte, recette) et la règle de droits
/// d'archivage (`DroitArchivageService`, module M6).
Map<String, Object?> chargeArchivageArticle({required bool actif}) => {
  'actif': actif,
};
