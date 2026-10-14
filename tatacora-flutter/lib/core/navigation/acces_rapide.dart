/// Le panneau « Accès rapides » de la vue — registre, libellés, tracés et
/// règles (lot 3 de `INSTRUCTION.txt`, 13/10/2026). Le widget qui le rend vit
/// dans `core/router/panneau_acces_rapide.dart`.
///
/// ## Ce que la vue fait, et que ce fichier traduit
///
/// Trois sources dans `tatacora-api` (chemins écrits sans leur préfixe : ce
/// fichier ne porte aucune vue de page, PA-187) :
///
/// - le partiel `partials/acces-rapide` : un bouton flottant (Alt+A), un voile,
///   un panneau à droite, DEUX sections — « Sur cette page » et « Aller à » —,
///   un état vide et un pied qui rappelle les raccourcis clavier ;
/// - la classe `App\Pwa\Support\AccesRapide` : le registre `ACTIONS_PAR_PAGE`
///   (clé = NOM DE ROUTE de la page courante), les huit
///   `RACCOURCIS_UNIVERSELS` (la page courante exclue), les tracés `ICONES`
///   et le sous-titre `libelleRoute()` ;
/// - la règle de masquage `MenuLateral::moduleAccessible()` : une entrée
///   disparaît quand le module vaut `-`, rien d'autre.
///
/// ## « Sur cette page » n'est PAS une liste d'ancres
///
/// La consigne du lot évoquait des « ancres de la page courante ». La vue n'en
/// construit aucune : « Sur cette page » est un REGISTRE STATIQUE d'actions,
/// indexé par la route de la page (`ACTIONS_PAR_PAGE[$routeActuelle]`), rendu
/// en liens vers d'autres écrans ou vers un état de la même page
/// (`?vue=historique`). La vue fait foi (PA-183) : ce fichier reproduit ce
/// registre, et `acces_rapide_contre_serveur_test.dart` le confronte au PHP à
/// chaque exécution — la copie n'est pas une source, elle est vérifiée.
///
/// ## Le panneau n'est PAS sur toutes les pages
///
/// Le gabarit de la PWA ne l'inclut pas : ONZE vues seulement font
/// `@include('pwa.partials.acces-rapide')` (relevé le 13/10/2026, tenu par le
/// test). Les entrées de `ACTIONS_PAR_PAGE` des autres pages (stocks,
/// approvisionnement, clients, POS…) sont donc écrites au registre du serveur
/// et JAMAIS rendues. Elles sont recopiées ici pour que la confrontation reste
/// totale ; [pagesAvecAccesRapide] dit où le bouton existe.
///
/// ## RBAC — la règle du serveur, pas celle de la barre latérale
///
/// `moduleAccessible()` seul : AUCUN masquage par rôle
/// (`ROUTES_MASQUEES_PAR_ROLE` ne s'applique qu'à la barre latérale). Le
/// gérant a `C` sur les quatorze modules (`RolePermissionSeeder::MATRICE`),
/// et la barre latérale lui cache onze routes, dont quatre que ce panneau
/// désigne : `pwa.clients`, `pwa.facturation`, `pwa.comptabilite.hub` et
/// `pwa.etats.studio`. Il voit donc dans « Aller à » « Clients »,
/// « Facturation », « Comptabilité » et « États & Rapports », et dans « Sur
/// cette page » « Générer un état » (accueil), « Ajouter un client » et
/// « Facturer le séjour » (réservations), « Facturation » (hébergement) —
/// toutes cachées par la barre latérale. C'est ce que la vue rend, et ce
/// poste le rend aussi. L'incohérence est celle du serveur ; elle est NOMMÉE
/// ici, pas corrigée seul (à remonter à l'Architecte, D346 complétée le
/// 13/10/2026).
library;

import '../rbac/garde_acces.dart';
import 'navigation_tatacora.dart';

/// Les chaînes du partiel, au mot — elles sont écrites EN DUR dans la vue
/// (aucune clé de langue, sauf la marque).
abstract final class LibellesAccesRapide {
  /// `<h2>` de l'en-tête du panneau.
  static const String titre = 'Accès rapides';

  /// `title="…"` du bouton flottant — l'infobulle.
  static const String titreBouton = 'Accès Rapides (Alt+A)';

  /// `aria-label="…"` du bouton flottant.
  static const String etiquetteBouton = 'Accès Rapides';

  /// `aria-label="Fermer"` du bouton de fermeture.
  static const String fermer = 'Fermer';

  /// L'état vide — aucune entrée dans aucune des deux sections.
  static const String aucun = 'Aucun accès rapide disponible pour votre rôle.';

  /// Les deux titres de section, écrits en minuscules par la vue et rendus en
  /// CAPITALES par sa classe `uppercase` — la transformation est faite au
  /// rendu, comme le navigateur.
  static const String surCettePage = 'Sur cette page';
  static const String allerA = 'Aller à';

  /// Le pied : `<kbd>Alt</kbd> + <kbd>A</kbd> pour ouvrir · <kbd>Échap</kbd>
  /// pour fermer`.
  static const String toucheAlt = 'Alt';
  static const String toucheA = 'A';
  static const String plus = '+';
  static const String pourOuvrir = 'pour ouvrir ·';
  static const String toucheEchap = 'Échap';
  static const String pourFermer = 'pour fermer';
}

/// Les tracés SVG du partiel lui-même (bouton flottant, fermeture, chevron
/// d'une entrée), au caractère près, avec les attributs de leur `<svg>`.
abstract final class TracesAccesRapide {
  /// L'éclair du bouton flottant — son `<svg>` porte
  /// `stroke-linecap="round"` et rien pour les jonctions : bouts ronds,
  /// jonctions en onglet.
  static const String eclair = '<path d="M13 2L3 14h9l-1 8 10-12h-9z"/>';

  /// La croix de fermeture — `stroke-linecap="round"` sur le `<svg>`.
  static const String fermer = '<path d="M18 6L6 18M6 6l12 12"/>';

  /// Le chevron d'une entrée — AUCUN attribut de trait : bouts plats.
  static const String chevron = '<path d="M9 18l6-6-6-6"/>';
}

/// `AccesRapide::ICONES` — les tracés des entrées, au caractère près. Le
/// `<svg>` qui les enveloppe porte `stroke-linecap="round"
/// stroke-linejoin="round"` : [heriterTraitsRacine] les reporte sur chaque
/// élément, parce que `IconeTrace` lit ces attributs élément par élément.
const Map<String, String> iconesAccesRapide = {
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'panier':
      '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>',
  'alerte':
      '<path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><path d="M12 9v4M12 17h.01"/>',
  'document':
      '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M14 2v6h6"/>',
  'horloge': '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  'hebergement':
      '<path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><path d="M9 22V12h6v10"/>',
  'facture':
      '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M16 13H8M16 17H8M10 9H8"/>',
  'stocks':
      '<path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/>',
  'achats':
      '<path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 01-8 0"/>',
  'inventaire':
      '<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/>',
  'entree': '<path d="M12 5v14M19 12l-7 7-7-7"/>',
  'balance': '<path d="M12 3v18M3 7h18M7 7l-3 7h6zM17 7l-3 7h6z"/>',
  'crm':
      '<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/>',
  'dashboard':
      '<rect x="3" y="3" width="7" height="9"/><rect x="14" y="3" width="7" height="5"/><rect x="14" y="12" width="7" height="9"/><rect x="3" y="16" width="7" height="5"/>',
  'comptabilite':
      '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 6h8M8 10h8M8 14h4"/>',
  'retour': '<path d="M19 12H5M12 19l-7-7 7-7"/>',
};

/// Reporte sur chaque élément d'un tracé les attributs de trait que la vue
/// pose sur son `<svg>` — l'héritage SVG, qu'un élément peut surcharger : un
/// attribut déjà présent sur l'élément est conservé.
String heriterTraitsRacine(String trace, {String? cap, String? join}) =>
    trace.replaceAllMapped(RegExp(r'<(path|rect|circle)\b([^>]*?)(/?)>'), (m) {
      final attributs = m[2]!;
      final ajout = StringBuffer();
      if (cap != null && !attributs.contains('stroke-linecap')) {
        ajout.write(' stroke-linecap="$cap"');
      }
      if (join != null && !attributs.contains('stroke-linejoin')) {
        ajout.write(' stroke-linejoin="$join"');
      }
      return '<${m[1]}$ajout$attributs${m[3]}>';
    });

/// Une entrée du panneau — un élément de `ACTIONS_PAR_PAGE` ou de
/// `RACCOURCIS_UNIVERSELS`.
final class EntreeAccesRapide {
  const EntreeAccesRapide(
    this.libelle,
    this.routePwa,
    this.module,
    this.icone, {
    this.params = const {},
  });

  /// Le libellé, au mot.
  final String libelle;

  /// Le NOM de route de la PWA (`pwa.reservations`) — la clé du serveur.
  final String routePwa;

  /// Le paramètre d'URL que la vue ajoute (`['vue' => 'historique']`).
  final Map<String, String> params;

  /// Le module dont le droit décide de la visibilité (`moduleAccessible`).
  final ModuleTatacora module;

  /// La clé de [iconesAccesRapide].
  final String icone;
}

const _m1 = ModuleTatacora.m1Hebergement;
const _m2 = ModuleTatacora.m2Facturation;
const _m3 = ModuleTatacora.m3Crm;
const _m4 = ModuleTatacora.m4Restaurant;
const _m5 = ModuleTatacora.m5Bar;
const _m6 = ModuleTatacora.m6Stocks;
const _m7 = ModuleTatacora.m7Achats;
const _m10 = ModuleTatacora.m10Comptabilite;
const _m11 = ModuleTatacora.m11TableauxDeBord;
const _m14 = ModuleTatacora.m14Etats;

/// `AccesRapide::ACTIONS_PAR_PAGE`, page par page, dans l'ordre du serveur.
const Map<String, List<EntreeAccesRapide>> actionsParPage = {
  'pwa.accueil': [
    EntreeAccesRapide('Nouvelle réservation', 'pwa.reservations', _m1, 'plus'),
    EntreeAccesRapide('Encaisser au bar', 'pwa.pos.comptant', _m5, 'panier'),
    EntreeAccesRapide('Stocks critiques', 'pwa.stocks.liste', _m6, 'alerte'),
    EntreeAccesRapide('Générer un état', 'pwa.etats.studio', _m14, 'document'),
  ],
  'pwa.reservations': [
    EntreeAccesRapide(
      'Historique des réservations',
      'pwa.reservations',
      _m1,
      'horloge',
      params: {'vue': 'historique'},
    ),
    EntreeAccesRapide(
      'Plan des chambres',
      'pwa.hebergement',
      _m1,
      'hebergement',
    ),
    EntreeAccesRapide('Ajouter un client', 'pwa.clients', _m3, 'plus'),
    EntreeAccesRapide('Facturer le séjour', 'pwa.facturation', _m2, 'facture'),
  ],
  'pwa.hebergement': [
    EntreeAccesRapide('Nouvelle réservation', 'pwa.reservations', _m1, 'plus'),
    EntreeAccesRapide(
      'Historique des réservations',
      'pwa.reservations',
      _m1,
      'horloge',
      params: {'vue': 'historique'},
    ),
    EntreeAccesRapide('Facturation', 'pwa.facturation', _m2, 'facture'),
  ],
  'pwa.clients': [
    EntreeAccesRapide(
      'Créances & relances',
      'pwa.clients',
      _m3,
      'alerte',
      params: {'vue': 'creances'},
    ),
    EntreeAccesRapide('Nouvelle réservation', 'pwa.reservations', _m1, 'plus'),
    EntreeAccesRapide('Facturation', 'pwa.facturation', _m2, 'facture'),
  ],
  'pwa.restaurant.carte': [
    EntreeAccesRapide('Point de vente', 'pwa.pos.comptant', _m4, 'panier'),
    EntreeAccesRapide('Stocks cuisine', 'pwa.stocks.liste', _m6, 'stocks'),
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
  ],
  'pwa.bar.carte': [
    EntreeAccesRapide('Point de vente', 'pwa.pos.comptant', _m5, 'panier'),
    EntreeAccesRapide('Stocks bar', 'pwa.stocks.liste', _m6, 'stocks'),
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
  ],
  'pwa.stocks.liste': [
    EntreeAccesRapide(
      'Inventaire physique',
      'pwa.stocks.inventaires',
      _m6,
      'inventaire',
    ),
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
    EntreeAccesRapide(
      'Articles sous seuil',
      'pwa.stocks.liste',
      _m6,
      'alerte',
      params: {'etat': 'sous_seuil'},
    ),
    EntreeAccesRapide(
      'Fiche de stock',
      'pwa.stocks.inventaires',
      _m6,
      'document',
    ),
  ],
  'pwa.achats.liste': [
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
    EntreeAccesRapide(
      'Dettes fournisseurs',
      'pwa.achats.approvisionnement',
      _m7,
      'alerte',
      params: {'onglet': 'dettes'},
    ),
    EntreeAccesRapide('Stocks', 'pwa.stocks.liste', _m6, 'stocks'),
  ],
  'pwa.achats.approvisionnement': [
    EntreeAccesRapide(
      'Nouvelle commande',
      'pwa.achats.approvisionnement',
      _m7,
      'plus',
      params: {'onglet': 'besoins'},
    ),
    EntreeAccesRapide(
      'Réceptionner',
      'pwa.achats.approvisionnement',
      _m7,
      'entree',
      params: {'onglet': 'receptions'},
    ),
    EntreeAccesRapide('Fournisseurs', 'pwa.achats.liste', _m7, 'achats'),
    EntreeAccesRapide('Stocks', 'pwa.stocks.liste', _m6, 'stocks'),
  ],
  'pwa.stocks.inventaires': [
    EntreeAccesRapide('Stocks', 'pwa.stocks.liste', _m6, 'stocks'),
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
  ],
  'pwa.pos.comptant': [
    EntreeAccesRapide(
      'Stocks du point de vente',
      'pwa.stocks.liste',
      _m6,
      'stocks',
    ),
    EntreeAccesRapide(
      'Approvisionnement',
      'pwa.achats.approvisionnement',
      _m7,
      'achats',
    ),
    EntreeAccesRapide('Facturation', 'pwa.facturation', _m2, 'facture'),
  ],
  'pwa.comptabilite.hub': [
    EntreeAccesRapide(
      'Passer une écriture',
      'pwa.comptabilite.hub',
      _m10,
      'plus',
    ),
    EntreeAccesRapide(
      'Journal comptable',
      'pwa.comptabilite.journal',
      _m10,
      'document',
    ),
    EntreeAccesRapide(
      'Balance générale',
      'pwa.comptabilite.balance',
      _m10,
      'balance',
    ),
    EntreeAccesRapide(
      'Compte de résultat',
      'pwa.comptabilite.compte-resultat',
      _m10,
      'document',
    ),
    EntreeAccesRapide('Bilan', 'pwa.comptabilite.bilan', _m10, 'balance'),
  ],
};

/// `AccesRapide::RACCOURCIS_UNIVERSELS` — les huit destinations de « Aller à ».
const List<EntreeAccesRapide> raccourcisUniversels = [
  EntreeAccesRapide('Tableau de bord', 'pwa.accueil', _m11, 'dashboard'),
  EntreeAccesRapide('Nouvelle réservation', 'pwa.reservations', _m1, 'plus'),
  EntreeAccesRapide('Clients', 'pwa.clients', _m3, 'crm'),
  EntreeAccesRapide('Point de vente', 'pwa.pos.comptant', _m5, 'panier'),
  EntreeAccesRapide('Facturation', 'pwa.facturation', _m2, 'facture'),
  EntreeAccesRapide('Stocks', 'pwa.stocks.liste', _m6, 'stocks'),
  EntreeAccesRapide(
    'Comptabilité',
    'pwa.comptabilite.hub',
    _m10,
    'comptabilite',
  ),
  EntreeAccesRapide('États & Rapports', 'pwa.etats.studio', _m14, 'document'),
];

/// Les ONZE pages dont la vue inclut le panneau : route Flutter → nom de
/// route PWA. Le bouton flottant n'existe que là (le test relit les
/// `@include` de la vue et le routeur Flutter).
const Map<String, String> pagesAvecAccesRapide = {
  '/tableau-de-bord': 'pwa.accueil',
  '/hebergement/reservations': 'pwa.reservations',
  '/hebergement': 'pwa.hebergement',
  '/bar': 'pwa.bar.carte',
  '/restaurant': 'pwa.restaurant.carte',
  '/restaurant/plats': 'pwa.restaurant.plats',
  '/vehicules': 'pwa.vehicules',
  '/tourisme': 'pwa.tourisme',
  '/parametres': 'pwa.parametres',
  '/depenses': 'pwa.depenses',
  '/historique-ventes': 'pwa.historique-ventes',
};

/// L'écran Flutter de chaque route PWA que le registre désigne — `null` quand
/// ce poste n'a pas l'écran.
///
/// Depuis le 14/10/2026 (lot D, D424) la comptabilité générale a son hub :
/// les pages séparées de la vue (journal, balance, compte de résultat, bilan)
/// ouvrent l'ONGLET correspondant du hub (`?onglet=`), qui DIT ce qu'il ne
/// calcule pas sur ce poste.
const Map<String, String?> routesFlutterParRoutePwa = {
  'pwa.accueil': '/tableau-de-bord',
  'pwa.reservations': '/hebergement/reservations',
  'pwa.hebergement': '/hebergement',
  'pwa.clients': '/crm',
  'pwa.facturation': '/facturation',
  'pwa.pos.comptant': '/pos',
  'pwa.stocks.liste': '/stocks',
  'pwa.stocks.inventaires': '/stocks/inventaires',
  'pwa.achats.liste': '/fournisseurs',
  'pwa.achats.approvisionnement': '/approvisionnement',
  'pwa.etats.studio': '/etats',
  'pwa.comptabilite.hub': '/comptabilite',
  'pwa.comptabilite.journal': '/comptabilite?onglet=journal',
  'pwa.comptabilite.balance': '/comptabilite?onglet=balance',
  'pwa.comptabilite.compte-resultat': '/comptabilite?onglet=resultat',
  'pwa.comptabilite.bilan': '/comptabilite?onglet=bilan',
};

/// La règle UNIQUE du serveur — `MenuLateral::moduleAccessible()` : masqué sur
/// `-` seulement.
bool _accessible(GardeAcces droits, EntreeAccesRapide e) =>
    droits.peutLire(e.module);

/// « Sur cette page » — `AccesRapide::actionsContextuelles()`.
List<EntreeAccesRapide> actionsContextuelles(
  GardeAcces droits,
  String? routePwa,
) => [
  for (final e in actionsParPage[routePwa] ?? const <EntreeAccesRapide>[])
    if (_accessible(droits, e)) e,
];

/// « Aller à » — `AccesRapide::raccourcisUniversels()` : la page courante
/// EXCLUE (comparaison des noms de route, paramètres ignorés comme au
/// serveur), puis la règle de masquage.
List<EntreeAccesRapide> raccourcisAllerA(GardeAcces droits, String? routePwa) =>
    [
      for (final e in raccourcisUniversels)
        if (e.routePwa != routePwa && _accessible(droits, e)) e,
    ];

/// Le sous-titre du panneau — `AccesRapide::libelleRoute()` : le nom de
/// l'entrée de `NAVIGATION` qui porte la route courante, si son module est
/// accessible ; sinon la marque (`__('pwa.marque')`, repli de la vue). La
/// route est cherchée par son écran Flutter dans le même registre de menu que
/// la barre latérale ([toutesLesDestinations]), jamais une seconde table de
/// libellés.
String sousTitreAccesRapide(
  GardeAcces droits,
  String routeFlutter, {
  required String marque,
}) {
  for (final d in toutesLesDestinations) {
    if (d.route == routeFlutter) {
      return droits.peutLire(d.module) ? d.nom : marque;
    }
  }
  return marque;
}
