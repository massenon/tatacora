import '../rbac/garde_acces.dart';
import '../rbac/regle_archivage.dart';

/// Le menu du maître de mise en page, transcrit.
///
/// **Source : `prototype_v2/assets/js/shell.js` l.29-90**, constante
/// `NAVIGATION`. Ce fichier en est la traduction exacte : quatre entrées
/// épinglées, puis **huit groupes** portant **dix-neuf entrées** — vingt-trois
/// destinations au total.
///
/// `DOCTRINE_PORTAGE_FIDELE_FLUTTER.md` §3.4 : « Coquille — mêmes groupes,
/// mêmes libellés, même ordre, mêmes icônes. » L'ordre de ce fichier **est**
/// celui du maître, du haut vers le bas. Ne pas le réordonner : le maître a
/// fusionné des entrées et documenté chaque fusion, un réagencement effacerait
/// ces décisions.
///
/// ## Registre FERMÉ, jamais un balayage
///
/// Même discipline que `CatalogueEtatsService` côté serveur et que
/// `TABLES_SYNCHRONISABLES` : on ne peut pas ajouter une destination sans
/// déclarer son module, donc sans dire qui a le droit de la voir.
///
/// ## Ce que le maître fait des entrées sans droit
///
/// `construireSidebar` (l.187) : `if (droit === '-') return ''`. L'entrée
/// **disparaît**, elle n'est pas grisée. C'est le premier des trois niveaux
/// RBAC (`RG-16`) — masquage à l'interface, garde au serveur, filtrage en base.
///
/// ## Ce qu'on fait des entrées sans écran Flutter
///
/// ⚠ **Ce paragraphe disait trois choses fausses jusqu'au 14/09/2026, et les
/// trois sont corrigées ici.** Il annonçait « dix-sept des vingt-trois
/// destinations n'ont aucun écran » : le compte était INVERSÉ (dix-sept en
/// avaient un) et le total faux (vingt-quatre). Il affirmait surtout que les
/// entrées sans route « mènent à [EcranModuleVide], qui dit pourquoi » —
/// **`_LienLateral.onTap` ne navigue pas du tout quand `route` est `null`** :
/// le clic ne fait RIEN. La bonne réponse décrite n'était pas celle du code.
///
/// **État réel au 14/10/2026 (lot D, D424) : les 24 destinations ont un
/// écran.** Comptabilité, Import & Export et Rôles & Permissions, les trois
/// dernières sans route (PA-204), mènent à leur écran. La branche « sans
/// écran » de `_LienLateral` (infobulle de la vue, message au clic) reste le
/// repli d'une entrée qui perdrait sa route — jamais un clic muet.
///
/// Lot J2 (14/10/2026) : une VINGT-CINQUIÈME destination, « Comptes
/// utilisateurs », AJOUT du poste sans équivalent dans la vue (voir son
/// entrée), réservée aux rôles d'administration ([DestinationMenu.rolesExiges]).
///
/// Les retirer n'est pas la réponse : cela trahirait la coquille de la vue,
/// que le client a validée avec ses huit groupes.
enum IconeModule {
  dashboard,
  bar,
  hebergement,
  facturation,
  reservation,
  crm,
  stocks,
  achats,
  restaurant,
  tourisme,
  vehicules,
  comptabilite,
  rh,
  etats,
  notifications,
  importExport,
  roles,
  parametres;

  /// La clé de `MenuLateral::ICONES` (`app/Pwa/Support/MenuLateral.php`) dont
  /// cette icône est le tracé. `coquille_conformite_test.dart` relit le registre
  /// PHP par cette clé et exige l'égalité des chaînes.
  String get cleVue => switch (this) {
    IconeModule.importExport => 'import',
    _ => name,
  };

  /// Le TRACÉ SVG de la vue — `MenuLateral::ICONES[cleVue]`, recopié au
  /// caractère près et dessiné par `IconeTrace` (`trace_svg.dart`).
  ///
  /// ⚠ Jusqu'au 12/10/2026, ce registre rendait une icône MATERIAL « de même
  /// sens » (`Icons.dashboard_outlined`…) : un autre dessin, un autre trait.
  /// La substitution était consignée ici même comme un écart ; elle est
  /// levée (lot 1 « coquille », `INSTRUCTION.txt` du PO). La copie n'est pas
  /// une source : le test la confronte au registre PHP à chaque exécution.
  String get trace => switch (this) {
    IconeModule.dashboard =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 3v18h18M18 17V9M13 17V5M8 17v-3"/>',
    IconeModule.reservation =>
      r'<rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/><path stroke-linecap="round" d="M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/>',
    IconeModule.hebergement =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20M6 8v-1a2 2 0 012-2h2a2 2 0 012 2v1"/>',
    IconeModule.restaurant =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M3 2v7c0 1.1.9 2 2 2h1a2 2 0 002-2V2M7 2v20M17 2a5 5 0 00-5 5v6h5m0-11v20"/>',
    IconeModule.bar =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M8 21h8M12 15v6M19 3H5l7 9 7-9z"/>',
    IconeModule.tourisme =>
      r'<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z"/>',
    IconeModule.vehicules =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M14 16H9m10 0h3v-3.15a1 1 0 00-.84-.99L16 11l-2.7-3.6a1 1 0 00-.8-.4H5.24a2 2 0 00-1.8 1.1l-1.14 2.28A2 2 0 002 11v4a1 1 0 001 1h1"/><circle cx="6.5" cy="16.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/>',
    IconeModule.crm =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/>',
    IconeModule.facturation =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/><path stroke-linecap="round" d="M9 13h6M9 17h6M9 9h1"/>',
    IconeModule.achats =>
      r'<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path stroke-linecap="round" stroke-linejoin="round" d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>',
    IconeModule.stocks =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8M12 13v8"/>',
    IconeModule.comptabilite =>
      r'<rect x="4" y="2" width="16" height="20" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M8 6h8M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01"/>',
    IconeModule.rh =>
      r'<rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 8h4M15 12h4M6 16h6"/>',
    IconeModule.notifications =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path stroke-linecap="round" stroke-linejoin="round" d="M13.73 21a2 2 0 01-3.46 0"/>',
    IconeModule.etats =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6M9 13h6M9 17h6M9 9h1"/>',
    IconeModule.roles =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
    IconeModule.importExport =>
      r'<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
    IconeModule.parametres =>
      r'<circle cx="12" cy="12" r="3"/><path stroke-linecap="round" stroke-linejoin="round" d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 004.6 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0019.4 9c.14.31.22.65.22 1V10c.66 0 1 .34 1 1v2c0 .66-.34 1-1 1z"/>',
  };
}

/// Une destination du menu.
final class DestinationMenu {
  const DestinationMenu({
    required this.nom,
    required this.icone,
    required this.module,
    required this.page,
    this.route,
    this.badge,
    this.rolesExiges,
  });

  /// Le libellé, **au caractère près** — doctrine §2 : un synonyme est
  /// interdit, le manuel et la formation s'appuient sur le mot exact.
  final String nom;

  final IconeModule icone;

  /// Le module dont dépend le droit de voir cette entrée.
  final ModuleTatacora module;

  /// La page du maître dont cette destination est la traduction. Conservée
  /// pour que la confrontation écran par écran reste possible sans relire
  /// `shell.js` — doctrine §3.6.
  final String page;

  /// La route Flutter, `null` tant qu'aucun écran n'existe : l'entrée porte
  /// alors l'infobulle de la vue et son clic affiche un message qui le dit
  /// (`coquille_application.dart`, `_LienLateral`).
  final String? route;

  /// `<span class="text-[8px] … bg-succes">` du maître. Décoratif au sens
  /// strict, mais **porteur de sens métier** : « Comptant » et « Panier
  /// ouvert » distinguent les deux points de vente, ce que l'atelier du
  /// 19/08/2026 a explicitement demandé.
  final String? badge;

  /// Les rôles SEULS admis, en plus du droit sur [module] — `null` : aucun
  /// rôle exigé (toutes les entrées de la vue). Sert à l'ajout du poste
  /// « Comptes utilisateurs » (Lot J2, 14/10/2026), réservé à
  /// l'administration comme `User::ROLES_ADMINISTRATION` au serveur.
  final Set<String>? rolesExiges;

  bool get aUnEcran => route != null;
}

/// Un groupe du menu — `{ groupe: '…', items: [...] }`.
final class GroupeMenu {
  const GroupeMenu({required this.titre, required this.destinations});

  /// Rendu en CAPITALES par le maître (`${entree.groupe.toUpperCase()}`), à
  /// `text-[10.5px] font-bold tracking-wider text-white/45`.
  final String titre;

  final List<DestinationMenu> destinations;
}

/// Les cinq entrées **épinglées**, avant tout groupe — `epingle: true`.
///
/// Le maître les commente une par une, et ces raisons ne doivent pas se perdre :
///
///  - **Tableau de bord** — fusion de deux entrées qui pointaient toutes deux
///    sur M11 et « laissaient croire à deux lectures différentes de la même
///    exploitation » ;
///  - **Point de vente** et **POS clients hébergés** — deux entrées distinctes,
///    « comme demandé en atelier (§4.5) : ils ne servent pas la même clientèle
///    et ne se clôturent pas de la même façon. Les fondre obligerait à choisir
///    le type de vente APRÈS avoir ouvert l'écran, c'est-à-dire au moment où
///    l'on a déjà un client devant soi » ;
///  - **Historique des ventes** — « le JOURNAL des ventes, distinct du registre
///    des factures : une vente peut exister sans facture, et une vente annulée
///    reste une vente là où une facture annulée produit un avoir. On y cherche
///    un `V-`, pas un `F-` » ;
///  - **Dépense courante** — « les charges DÉCAISSÉES directement — le marché
///    du matin, un transport, un dépannage. Distinctes de l'Approvisionnement,
///    qui suit un fournisseur et une dette : confondre les deux ferait
///    apparaître en dettes fournisseurs des sommes déjà sorties de la caisse ».
const List<DestinationMenu> destinationsEpinglees = [
  DestinationMenu(
    nom: 'Tableau de bord',
    icone: IconeModule.dashboard,
    module: ModuleTatacora.m11TableauxDeBord,
    page: 'tableau-de-bord.html',
    route: '/tableau-de-bord',
    badge: 'Tous modules',
  ),
  DestinationMenu(
    nom: 'Point de vente',
    icone: IconeModule.bar,
    module: ModuleTatacora.m5Bar,
    page: 'pos.html',
    route: '/pos',
    badge: 'Comptant',
  ),
  DestinationMenu(
    nom: 'POS clients hébergés',
    icone: IconeModule.hebergement,
    module: ModuleTatacora.m1Hebergement,
    page: 'pos-heberges.html',
    route: '/pos/heberges',
    badge: 'Panier ouvert',
  ),
  DestinationMenu(
    nom: 'Historique des ventes',
    icone: IconeModule.facturation,
    module: ModuleTatacora.m5Bar,
    page: 'historique-ventes.html',
    route: '/historique-ventes',
    badge: 'Journal',
  ),
  DestinationMenu(
    nom: 'Dépense courante',
    icone: IconeModule.comptabilite,
    module: ModuleTatacora.m10Comptabilite,
    page: 'depenses.html',
    route: '/depenses',
    badge: 'Trésorerie',
  ),
];

/// Les huit groupes, dans l'ordre du maître.
const List<GroupeMenu> groupesMenu = [
  GroupeMenu(
    titre: 'Réservations & séjours',
    destinations: [
      DestinationMenu(
        nom: 'Réservations',
        icone: IconeModule.reservation,
        module: ModuleTatacora.m1Hebergement,
        page: 'reservations.html',
        route: '/hebergement/reservations',
      ),
      DestinationMenu(
        nom: 'Hébergement',
        icone: IconeModule.hebergement,
        module: ModuleTatacora.m1Hebergement,
        page: 'm1-hebergement.html',
        route: '/hebergement',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Clients & facturation',
    destinations: [
      // Fusion du maître : une seule fiche client, avec ses créances. Deux
      // entrées laissaient croire à deux référentiels distincts.
      DestinationMenu(
        nom: 'Clients & Créances',
        icone: IconeModule.crm,
        module: ModuleTatacora.m3Crm,
        page: 'm3-clients-creances.html',
        route: '/crm',
      ),
      DestinationMenu(
        nom: 'Facturation',
        icone: IconeModule.facturation,
        module: ModuleTatacora.m2Facturation,
        page: 'm2-facturation.html',
        route: '/facturation',
        badge: 'MECeF',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Stocks & achats',
    destinations: [
      DestinationMenu(
        nom: 'Stocks',
        icone: IconeModule.stocks,
        module: ModuleTatacora.m6Stocks,
        page: 'm6-stocks.html',
        route: '/stocks',
      ),
      DestinationMenu(
        nom: 'Inventaires & Fiches',
        icone: IconeModule.stocks,
        module: ModuleTatacora.m6Stocks,
        page: 'm6-inventaires.html',
        route: '/stocks/inventaires',
      ),
      DestinationMenu(
        nom: 'Approvisionnement',
        icone: IconeModule.achats,
        module: ModuleTatacora.m7Achats,
        page: 'm7-approvisionnement.html',
        route: '/approvisionnement',
      ),
      DestinationMenu(
        nom: 'Fournisseurs',
        icone: IconeModule.achats,
        module: ModuleTatacora.m7Achats,
        page: 'm7-achats.html',
        route: '/fournisseurs',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Restauration & bar',
    destinations: [
      DestinationMenu(
        nom: 'Restaurant',
        icone: IconeModule.restaurant,
        module: ModuleTatacora.m4Restaurant,
        page: 'm4-restaurant-carte.html',
        route: '/restaurant',
      ),
      DestinationMenu(
        nom: 'Bar',
        icone: IconeModule.bar,
        module: ModuleTatacora.m5Bar,
        page: 'm5-bar-carte.html',
        route: '/bar',
        badge: 'Stock',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Tourisme & véhicules',
    destinations: [
      // Fusion du maître : quatre entrées ramenées à deux. Le catalogue des
      // circuits et le parc de véhicules sont des RÉFÉRENTIELS — on les
      // corrige, on ne les pilote pas. Ils sont devenus le second onglet de
      // l'écran qui les exploite.
      // Inerte jusqu'au 14/09/2026, alors que son écran EXISTAIT : le clic ne
      // faisait rien, et la route `/tourisme` servie par le routeur ouvrait
      // `EcranModuleVide`. Article 3.3 — « l'entrée doit naviguer vers l'écran
      // réel ».
      DestinationMenu(
        nom: 'Tourisme',
        icone: IconeModule.tourisme,
        module: ModuleTatacora.m9Tourisme,
        page: 'm9-tourisme-departs.html',
        route: '/tourisme',
      ),
      // L'entrée navigue vers l'écran RÉEL depuis le 27/08/2026 : elle était
      // inerte faute d'écran, ce que l'Article 3.3 de la directive de
      // conformité interdit désormais — « l'entrée doit naviguer vers l'écran
      // réel ». Les cinq routes de `Route::prefix('vehicules')` existaient et
      // n'avaient aucun client.
      DestinationMenu(
        nom: 'Véhicules & Locations',
        icone: IconeModule.vehicules,
        module: ModuleTatacora.m8Vehicules,
        page: 'm8-locations.html',
        route: '/vehicules',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Finance',
    destinations: [
      DestinationMenu(
        nom: 'Comptabilité',
        icone: IconeModule.comptabilite,
        module: ModuleTatacora.m10Comptabilite,
        page: 'm10-syscohada.html',
        route: '/comptabilite',
        badge: 'SYSCOHADA',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Ressources humaines',
    destinations: [
      DestinationMenu(
        nom: 'Personnel & Paie',
        icone: IconeModule.rh,
        module: ModuleTatacora.m13Rh,
        page: 'm13-paie.html',
        route: '/paie',
      ),
    ],
  ),
  GroupeMenu(
    titre: 'Pilotage & administration',
    destinations: [
      DestinationMenu(
        nom: 'États & Rapports',
        icone: IconeModule.etats,
        module: ModuleTatacora.m14Etats,
        page: 'm14-etats-studio.html',
        route: '/etats',
      ),
      DestinationMenu(
        nom: 'Notifications',
        icone: IconeModule.notifications,
        module: ModuleTatacora.m12Notifications,
        page: 'm12-notifications-hub.html',
        route: '/notifications',
      ),
      DestinationMenu(
        nom: 'Import & Export',
        icone: IconeModule.importExport,
        module: ModuleTatacora.parametres,
        page: 'import-export.html',
        route: '/import-export',
      ),
      DestinationMenu(
        nom: 'Rôles & Permissions',
        icone: IconeModule.roles,
        module: ModuleTatacora.roles,
        page: 'roles-permissions.html',
        route: '/roles-permissions',
      ),
      // AJOUT DU POSTE (Lot J2, directive du PO du 14/10/2026) — la PWA n'a
      // AUCUN écran de gestion des comptes (relu : ni composant `app/Pwa`, ni
      // vue, ni route `pwa.*`) ; sur ce poste sans serveur, c'est le seul
      // endroit où un administrateur crée un compte. Réservé aux deux rôles
      // d'administration ([rolesAdministration]), en plus du droit sur ROLES.
      // L'icône est celle des personnes (`crm`) : aucune clé de
      // `MenuLateral::ICONES` ne nomme les comptes, et en inventer une
      // romprait la confrontation des tracés au registre PHP.
      DestinationMenu(
        nom: 'Comptes utilisateurs',
        icone: IconeModule.crm,
        module: ModuleTatacora.roles,
        page: '(ajout du poste, sans page de la vue)',
        // Littéral, comme toutes les entrées (= [routeComptesUtilisateurs]).
        route: '/comptes-utilisateurs',
        rolesExiges: rolesAdministration,
      ),
      DestinationMenu(
        nom: 'Paramètres',
        icone: IconeModule.parametres,
        module: ModuleTatacora.parametres,
        page: 'parametres.html',
        route: '/parametres',
      ),
    ],
  ),
];

/// La route de l'écran « Comptes utilisateurs » (Lot J2).
const String routeComptesUtilisateurs = '/comptes-utilisateurs';

/// Toutes les destinations, épinglées comprises — pour les contrôles.
List<DestinationMenu> get toutesLesDestinations => [
  ...destinationsEpinglees,
  for (final g in groupesMenu) ...g.destinations,
];

/// Les entrées que la vue MASQUE à un rôle, en plus du masquage par module —
/// `MenuLateral::ROUTES_MASQUEES_PAR_ROLE` (`tatacora-api/app/Pwa/Support/
/// MenuLateral.php`), traduit en NOMS d'entrée.
///
/// ## Pourquoi (Phase 1B, 08/10/2026)
///
/// Le Flutter ne filtrait que par module : un `gerant` voyait onze entrées
/// que la vue lui cache. C'est le premier des trois niveaux du RBAC
/// (masquage d'interface) ; une entrée qui mène à un refus est de plus une
/// entrée inerte aux yeux de l'utilisateur (Article 3.3). La liste est celle
/// du serveur, vérifiée par `barre_laterale_blade_test.dart` contre la barre
/// que la vue rend à chaque rôle : si le serveur change, ce test rougit.
const Map<String, Set<String>> nomsMasquesParRole = {
  'gerant': {
    'Tourisme',
    'Véhicules & Locations',
    'Comptabilité',
    'Personnel & Paie',
    'États & Rapports',
    'Notifications',
    'Import & Export',
    'Rôles & Permissions',
    'Paramètres',
    'Clients & Créances',
    'Facturation',
  },
};

/// Vrai si [role] ne doit pas voir l'entrée [nom] — insensible à la casse et
/// aux accents (« Gérant », « gerant »).
bool entreeMasqueePourRole(String role, String nom) {
  final cle = role
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e');
  return nomsMasquesParRole[cle]?.contains(nom) ?? false;
}

/// L'ACCÈS à une destination — UNE règle, lue par la barre latérale, la
/// recherche globale ET la garde du routeur ([accesRoute]) : le droit de
/// lecture sur son module (masquée sur `-` seulement, comme
/// `MenuLateral::moduleAccessible`), puis le rôle quand l'entrée en exige un.
bool destinationAccessible(
  DestinationMenu d, {
  required GardeAcces droits,
  required String? role,
}) {
  if (!droits.peutLire(d.module)) return false;
  final roles = d.rolesExiges;
  return roles == null || roles.contains(roleNormalise(role));
}

/// La VISIBILITÉ au menu : l'accès, puis le masquage d'interface par rôle
/// ([nomsMasquesParRole]). Le masquage par rôle ne garde AUCUNE route — au
/// serveur, `ROUTES_MASQUEES_PAR_ROLE` ne touche que la barre ; le middleware
/// `module:` ne lit que le niveau du module. Le gérant atteint donc encore
/// « Paramètres » par son menu de compte, comme dans la vue.
bool destinationVisible(
  DestinationMenu d, {
  required GardeAcces droits,
  required String? role,
}) =>
    destinationAccessible(d, droits: droits, role: role) &&
    !entreeMasqueePourRole(role ?? '', d.nom);

/// Les routes ouvertes à TOUT compte connecté — celles que la vue sert sans
/// middleware `module:` (`routes/web.php` : `pwa.accueil`, `pwa.mon-profil`,
/// `pwa.aide-a-propos`, `pwa.contact-editeur`). Le tableau de bord est aussi
/// la destination de repli de la garde : le fermer ferait boucler la
/// redirection pour un compte sans M11 (le guide).
const Set<String> routesOuvertesATousLesComptes = {
  '/tableau-de-bord',
  '/mon-profil',
  '/aide-a-propos',
  '/contact-editeur',
};

/// Les routes servies HORS de la barre latérale, et leur module — le
/// `module:` de leur route au serveur (`liensChassis()` pour le menu de
/// compte). Les sous-routes d'une entrée (`/bar/boissons`,
/// `/restaurant/plats`, `/hebergement/nouvelle-reservation`) n'ont pas besoin
/// d'y figurer : elles héritent du module de leur entrée par préfixe.
const Map<String, ModuleTatacora> modulesDesRoutesHorsMenu = {
  // `pwa.journal-audit` : `module:M14,L`.
  '/journal-audit': ModuleTatacora.m14Etats,
  // Les réservations en suspens : l'écran des réservations (M1).
  '/synchronisation': ModuleTatacora.m1Hebergement,
};

/// Le verdict de la garde du routeur sur un chemin.
enum AccesRoute {
  /// Le compte peut ouvrir l'écran.
  autorise,

  /// Le chemin relève d'un module (ou d'un rôle) que le compte n'a pas.
  refuse,

  /// Le chemin n'est connu d'aucun registre — registre FERMÉ : il n'obtient
  /// pas un accès par omission.
  inconnu,
}

/// La garde d'une route — dérivée du MÊME registre que la barre latérale
/// ([toutesLesDestinations], [destinationAccessible]) : une entrée masquée au
/// menu est aussi une route refusée quand on la tape. Ordre : route ouverte ;
/// route d'une entrée du menu (égalité, sinon la plus longue entrée dont le
/// chemin est un préfixe) ; route hors menu ; sinon inconnue.
AccesRoute accesRoute(
  String chemin, {
  required GardeAcces droits,
  required String? role,
}) {
  if (routesOuvertesATousLesComptes.contains(chemin)) {
    return AccesRoute.autorise;
  }
  DestinationMenu? porteuse;
  for (final d in toutesLesDestinations) {
    final route = d.route;
    if (route == null) continue;
    if (route == chemin) {
      porteuse = d;
      break;
    }
    if (chemin.startsWith('$route/') &&
        (porteuse == null || route.length > porteuse.route!.length)) {
      porteuse = d;
    }
  }
  if (porteuse != null) {
    return destinationAccessible(porteuse, droits: droits, role: role)
        ? AccesRoute.autorise
        : AccesRoute.refuse;
  }
  final module = modulesDesRoutesHorsMenu[chemin];
  if (module != null) {
    return droits.peutLire(module) ? AccesRoute.autorise : AccesRoute.refuse;
  }
  return AccesRoute.inconnu;
}
