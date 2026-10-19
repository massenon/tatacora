/// La DESCENTE du catalogue (lot F2b, 15/10/2026) — vocabulaire, éléments,
/// conversions d'unités et bilan. Pur, sans base. Depuis le lot F3
/// (16/10/2026), le même flux porte aussi les clients et les réservations
/// de tous les postes.
///
/// ## Le contrat (`GET /api/v1/referentiels`, `ReferentielsController`)
///
/// `{data: {elements: [{table, id, actif, modifie_le, donnees}],
/// correspondances: [{table, id_poste, id_serveur}]}, meta: {curseur,
/// complet, limite}}`. Les tables arrivent dans l'ordre de leurs dépendances
/// ([TableDescendue], relu du serveur par un test), des DÉFINITIONS
/// seulement : jamais un stock, un coût moyen, un coût matière (PA-129).
///
/// ## Les conversions (l'inverse de celles du lot F1)
///
/// | Serveur | Poste |
/// |---|---|
/// | `seuil_alerte` `"12.50"` | centièmes 1250 (colonne REAL `12.5`, comme `StocksDao`) |
/// | `quantite_unitaire` `"0.250"` | millièmes 250 |
/// | `prix_vente`, `tarif_base` `"1500.00"` | francs entiers 1500 — une fraction de franc est REFUSÉE, jamais arrondie |
///
/// Aucune conversion ne passe par un `double` : [entierDepuisDecimal] lit la
/// chaîne chiffre à chiffre.
library;

import 'dart:convert';

import '../../../core/format/cle_comparaison.dart';
import 'operation_sync.dart';

/// Les tables du catalogue descendu, DANS L'ORDRE du serveur
/// (`CatalogueDescendantService::COLONNES`) : un élément cité avant celui qui
/// le cite.
enum TableDescendue {
  pointsStockage('points_stockage', TableSynchronisee.pointsStockage),
  articles('articles', TableSynchronisee.articles),
  cartesBoisson('cartes_boisson', TableSynchronisee.cartesBoisson),
  menus('menus', TableSynchronisee.menus),
  recettes('recettes', TableSynchronisee.recettes),
  plats('plats', TableSynchronisee.plats),
  categoriesHebergement(
    'categories_hebergement',
    TableSynchronisee.categoriesHebergement,
  ),
  unitesHebergement('unites_hebergement', TableSynchronisee.unitesHebergement),

  /// Lot F6 (18/10/2026) : le plan de salle, pour l'arbitrage des tables.
  tablesSalle('tables_salle', TableSynchronisee.tablesSalle),
  fournisseurs('fournisseurs', TableSynchronisee.fournisseurs),

  /// Lot F3 (décision du PO du 16/10/2026) : les clients et les séjours de
  /// TOUS les postes descendent — le client AVANT la réservation qui le cite
  /// (PA-127), l'unité bien avant.
  clients('clients', TableSynchronisee.clients),
  reservations('reservations', TableSynchronisee.reservations),

  /// Lot F5 : l'arrivée et le départ réels, après la réservation.
  sejours('sejours', TableSynchronisee.sejours),

  /// Lot F4 (décision du PO du 17/10/2026, « NE PLUS LIMITER ») : TOUS les
  /// documents de TOUS les postes, sans pièce locale (Q1 : le journal du
  /// poste ne tient que ses propres pièces).
  sessionsCaisse('sessions_caisse', TableSynchronisee.sessionsCaisse),
  ventes('ventes', TableSynchronisee.ventes),
  depenses('depenses', TableSynchronisee.depenses),

  /// Lot F6 : l'OCCUPATION des tables par les autres postes (paniers ouverts).
  paniers('paniers', TableSynchronisee.paniers),

  /// Lots F5c et F5d (17/10/2026) : les factures (numéro du serveur), leurs
  /// avoirs, puis les encaissements — le reste dû d'une facture est le même
  /// sur tous les postes.
  factures('factures', TableSynchronisee.factures),
  avoirs('avoirs', null),
  paiements('paiements', TableSynchronisee.paiements),
  commandesAchat('commandes_achat', TableSynchronisee.commandesAchat),
  bonsReception('bons_reception', TableSynchronisee.bonsReception),
  reglementsFournisseur(
    'reglements_fournisseur',
    TableSynchronisee.reglementsFournisseur,
  ),
  mouvementsStock('mouvements_stock', TableSynchronisee.mouvementsStock),
  circuits('circuits', TableSynchronisee.circuits),
  guides('guides', TableSynchronisee.guides),
  reservationsTour('reservations_tour', TableSynchronisee.reservationsTour),

  /// Audit de couverture (18/10/2026) : le parc M8 et ses contrats.
  vehicules('vehicules', TableSynchronisee.vehicules),
  contratsLocation('contrats_location', TableSynchronisee.contratsLocation),

  /// Audit de couverture (18/10/2026) : M13.
  servicesRh('services', null),
  employes('employes', TableSynchronisee.employes),
  bulletinsPaie('bulletins_paie', TableSynchronisee.bulletinsPaie),

  /// Descendue sans être synchronisable : le poste ne pousse pas ses centres.
  centresCout('centres_cout', null),

  /// Lot 10e (18/10/2026) : le paramétrage (clé par clé) et les rôles avec
  /// leur matrice — reçus par tout compte qui synchronise.
  parametresSysteme('parametres_systeme', TableSynchronisee.parametresSysteme),
  roles('roles', TableSynchronisee.roles),

  /// Lot 10f : les modèles de notification (M12).
  modelesNotification(
    'modeles_notification',
    TableSynchronisee.modelesNotification,
  );

  const TableDescendue(this.nomServeur, this.tableSynchronisee);

  final String nomServeur;

  /// La table de la FILE d'envoi correspondante — `null` si le poste ne la
  /// pousse pas (aucune modification locale en attente n'est alors possible).
  final TableSynchronisee? tableSynchronisee;

  static TableDescendue? depuisNom(String nom) {
    for (final t in values) {
      if (t.nomServeur == nom) return t;
    }
    return null;
  }
}

/// Le libellé FRANÇAIS d'une table du serveur, pour l'écran de
/// synchronisation. Registre fermé sur les tables connues ; une table
/// inconnue est rendue telle quelle, jamais devinée.
String libelleTableServeur(String nom) => switch (nom) {
  'reservations' => 'Réservations',
  'clients' => 'Clients',
  'fournisseurs' => 'Fournisseurs',
  'points_stockage' => 'Points de stockage',
  'articles' => 'Articles de stock',
  'cartes_boisson' => 'Boissons (carte du bar)',
  'menus' => 'Menus',
  'recettes' => 'Fiches techniques',
  'plats' => 'Plats',
  'categories_hebergement' => 'Catégories d\'hébergement',
  'unites_hebergement' => 'Unités d\'hébergement',
  'commandes_achat' => 'Commandes d\'achat',
  'bons_reception' => 'Bons de réception',
  'sessions_caisse' => 'Sessions de caisse',
  'ventes' => 'Ventes',
  'depenses' => 'Dépenses',
  'tables_salle' => 'Tables de salle',
  'paniers' => 'Tables occupées (additions ouvertes)',
  'factures' => 'Factures',
  'avoirs' => 'Avoirs',
  'paiements' => 'Encaissements de factures',
  'centres_cout' => 'Centres de coût',
  'reglements_fournisseur' => 'Règlements fournisseurs',
  'mouvements_stock' => 'Mouvements de stock',
  'circuits' => 'Circuits touristiques',
  'guides' => 'Guides',
  'reservations_tour' => 'Réservations de circuits',
  'sejours' => 'Séjours (arrivées et départs)',
  'vehicules' => 'Véhicules',
  'contrats_location' => 'Contrats de location',
  'services' => 'Services (RH)',
  'employes' => 'Employés',
  'bulletins_paie' => 'Bulletins de paie',
  'parametres_systeme' => 'Paramètres',
  'roles' => 'Rôles et permissions',
  'modeles_notification' => 'Modèles de notification',
  _ => nom,
};

/// Un élément du catalogue tel que le serveur le rend.
final class ElementCatalogue {
  const ElementCatalogue({
    required this.table,
    required this.id,
    required this.actif,
    required this.modifieLe,
    required this.donnees,
    this.posteOrigine,
  });

  final TableDescendue table;

  /// Le poste qui a saisi le document (lot F4) ; `null` : saisi au serveur.
  final String? posteOrigine;
  final String id;

  /// `false` : archivé au serveur (article, fournisseur, client, unité hors
  /// service).
  final bool actif;
  final String modifieLe;
  final Map<String, Object?> donnees;

  /// L'élément d'un JSON du serveur, ou `null` s'il est illisible (table
  /// inconnue, identifiant absent) — un élément illisible est COMPTÉ refusé
  /// par l'appelant, jamais avalé.
  static ElementCatalogue? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final table = brut['table'];
    final id = brut['id'];
    final donnees = brut['donnees'];
    if (table is! String || id is! String || id.isEmpty) return null;
    final t = TableDescendue.depuisNom(table);
    if (t == null || donnees is! Map) return null;
    return ElementCatalogue(
      table: t,
      id: id,
      actif: brut['actif'] != false,
      modifieLe: brut['modifie_le'] is String
          ? brut['modifie_le']! as String
          : '',
      donnees: Map<String, Object?>.from(donnees),
      posteOrigine: brut['poste_origine'] is String
          ? brut['poste_origine']! as String
          : null,
    );
  }

  Map<String, Object?> versJson() => {
    'table': table.nomServeur,
    'id': id,
    'actif': actif,
    'modifie_le': modifieLe,
    'poste_origine': posteOrigine,
    'donnees': donnees,
  };

  String encoder() => jsonEncode(versJson());
}

/// Une correspondance rendue par le serveur : l'UUID [idPoste] de CE poste
/// désigne l'élément serveur [idServeur].
typedef CorrespondanceServeur = ({
  String table,
  String idPoste,
  String idServeur,
});

/* ==================================================================== */
/* Conversions                                                           */
/* ==================================================================== */

/// Une chaîne décimale du serveur en entier de l'unité 10^-[decimales] :
/// `entierDepuisDecimal("12.50", 2)` → 1250, `("0.250", 3)` → 250,
/// `("1500.00", 0)` → 1500. `null` si la chaîne n'est pas un décimal, ou si
/// elle porte une précision que l'unité locale ne sait pas tenir
/// (`"1500.50"` en francs entiers) : une valeur d'argent ne s'arrondit pas.
int? entierDepuisDecimal(Object? brut, int decimales) {
  final texte = switch (brut) {
    final String s => s.trim(),
    final int n => '$n',
    _ => null,
  };
  if (texte == null) return null;
  final m = RegExp(r'^(-?)(\d+)(?:\.(\d+))?$').firstMatch(texte);
  if (m == null) return null;
  final fraction = m.group(3) ?? '';
  if (fraction.length > decimales) {
    final surplus = fraction.substring(decimales);
    if (surplus.replaceAll('0', '').isNotEmpty) return null;
  }
  final garde = fraction.length > decimales
      ? fraction.substring(0, decimales)
      : fraction.padRight(decimales, '0');
  final valeur = int.parse('${m.group(2)}$garde');
  return m.group(1) == '-' ? -valeur : valeur;
}

/// La clé naturelle d'un libellé — la normalisation de `CleNaturelle` au
/// serveur : sans casse, sans accents, blancs de bord retirés, blancs
/// internes resserrés.
String cleNaturelle(String? texte) =>
    cleDeComparaison((texte ?? '').trim()).replaceAll(RegExp(r'\s+'), ' ');

/* ==================================================================== */
/* L'issue d'un élément, et le bilan                                     */
/* ==================================================================== */

/// Ce qu'est devenu UN élément descendu. Registre fermé.
sealed class IssueAlignement {
  const IssueAlignement();
}

/// Écrit sur le poste (inséré ou mis à jour).
final class Aligne extends IssueAlignement {
  const Aligne({this.archiveNonPortee = false});

  /// L'élément est ARCHIVÉ au serveur, mais la table locale n'a pas
  /// d'archive (articles, clients) : il reste proposé ici, et le bilan le
  /// dit.
  final bool archiveNonPortee;
}

/// Non écrit : la ligne locale porte une modification ENCORE NON POUSSÉE
/// (opération en attente, en cours ou bloquée). Elle partira, et le dernier
/// écrit gagnant du serveur tranchera ; l'élément est gardé pour la reprise.
final class ConserveLocalement extends IssueAlignement {
  const ConserveLocalement(this.raison);
  final String raison;
}

/// Non écrit : il cite un élément que le poste n'a pas encore (un plat dont
/// le menu n'est pas descendu). Gardé, rejoué en fin de descente et à la
/// suivante — jamais une clé étrangère violée.
final class EnAttenteDeDependance extends IssueAlignement {
  const EnAttenteDeDependance(this.motif);
  final String motif;
}

/// Non écrit, définitivement pour cette version de l'élément : le poste ne
/// sait pas le tenir (prix à fraction de franc, type inconnu…). Il repassera
/// le jour où le serveur le modifiera.
final class RefuseParLePoste extends IssueAlignement {
  const RefuseParLePoste(this.motif);
  final String motif;
}

/// Comment s'est terminée une descente. Registre FERMÉ.
enum EtatDescente {
  /// Le catalogue est à jour (`meta.complet`).
  aJour('Catalogue du serveur à jour sur ce poste.'),

  /// Le repli d'un échec précédent n'est pas échu : aucune requête.
  enRepli(
    'Descente du catalogue en repli : nouvel essai automatique plus tard.',
  ),

  /// Pas de réponse, 408, 429, 5xx : repli PROPRE à la descente.
  serveurIndisponible(
    'Catalogue non reçu : serveur injoignable ou indisponible, nouvel essai '
    'automatique plus tard.',
  ),

  /// 401 / 403 : refus consigné, plus rien avant réappairage.
  refusee('Catalogue refusé par le serveur — réappairer le poste.'),

  /// 409 `generation_perimee` : le serveur a été réinitialisé (19/10/2026).
  serveurReinitialise(
    'Catalogue refusé : le serveur a été réinitialisé — réinitialiser ce '
    'poste.',
  ),

  /// Réponse illisible ou 4xx inattendu.
  alerte('Descente du catalogue interrompue : réponse inattendue du serveur.');

  const EtatDescente(this.libelle);

  /// La phrase de l'état, telle que l'écran la dit.
  final String libelle;

  static EtatDescente? depuisNom(String? nom) {
    for (final e in values) {
      if (e.name == nom) return e;
    }
    return null;
  }
}

/// Ce qu'a fait UNE descente.
final class BilanDescente {
  const BilanDescente({
    required this.etat,
    this.pages = 0,
    this.recus = 0,
    this.appliques = 0,
    this.conservesLocalement = 0,
    this.enAttenteDeDependance = 0,
    this.refuses = 0,
    this.archivesNonPortees = 0,
    this.motifsRefus = const [],
    this.codeHttp,
    this.prochaineTentative,
    this.termineeLe,
  });

  final EtatDescente etat;

  /// Pages `GET /referentiels` APPLIQUÉES (curseur avancé).
  final int pages;

  /// Éléments reçus dans les pages de cette descente.
  final int recus;

  /// Éléments écrits sur le poste (pages et reprises).
  final int appliques;

  /// Éléments gardés de côté à la fin : modification locale non poussée.
  final int conservesLocalement;

  /// Éléments gardés de côté à la fin : dépendance encore absente.
  final int enAttenteDeDependance;

  /// Éléments que le poste ne sait pas tenir, pendant cette descente.
  final int refuses;

  /// Articles et clients archivés au serveur, sans archive locale (restent
  /// proposés).
  final int archivesNonPortees;

  /// Les motifs des refus (les vingt premiers), pour l'écran.
  final List<String> motifsRefus;
  final int? codeHttp;
  final DateTime? prochaineTentative;
  final DateTime? termineeLe;

  Map<String, Object?> versJson() => {
    'etat': etat.name,
    'pages': pages,
    'recus': recus,
    'appliques': appliques,
    'conserves_localement': conservesLocalement,
    'en_attente_de_dependance': enAttenteDeDependance,
    'refuses': refuses,
    'archives_non_portees': archivesNonPortees,
    'motifs_refus': motifsRefus,
    'code_http': codeHttp,
    'prochaine_tentative': prochaineTentative?.toUtc().toIso8601String(),
    'terminee_le': termineeLe?.toUtc().toIso8601String(),
  };

  /// Le bilan relu de `etat_synchronisation_local`, ou `null` s'il est
  /// illisible.
  static BilanDescente? depuisJson(Object? brut) {
    if (brut is! Map) return null;
    final etat = EtatDescente.depuisNom(brut['etat'] as String?);
    if (etat == null) return null;
    int n(String c) => brut[c] is int ? brut[c]! as int : 0;
    DateTime? d(String c) =>
        brut[c] is String ? DateTime.tryParse(brut[c]! as String) : null;
    return BilanDescente(
      etat: etat,
      pages: n('pages'),
      recus: n('recus'),
      appliques: n('appliques'),
      conservesLocalement: n('conserves_localement'),
      enAttenteDeDependance: n('en_attente_de_dependance'),
      refuses: n('refuses'),
      archivesNonPortees: n('archives_non_portees'),
      motifsRefus: [
        for (final m in (brut['motifs_refus'] as List? ?? const []))
          if (m is String) m,
      ],
      codeHttp: brut['code_http'] is int ? brut['code_http']! as int : null,
      prochaineTentative: d('prochaine_tentative'),
      termineeLe: d('terminee_le'),
    );
  }

  @override
  String toString() =>
      'BilanDescente(${etat.name}, pages $pages, reçus $recus, appliqués '
      '$appliques, conservés $conservesLocalement, dépendance '
      '$enAttenteDeDependance, refusés $refuses)';
}
