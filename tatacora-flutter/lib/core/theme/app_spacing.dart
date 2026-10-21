// Vue Blade maîtresse (PA-183) : pwa/achats/approvisionnement.blade.php
// Vue Blade maîtresse (PA-183) : pwa/pos/comptant.blade.php
// Vue Blade maîtresse (PA-183) : pwa/pos/historique-ventes.blade.php
// Vue Blade maîtresse (PA-183) : pwa/stocks/stocks.blade.php
export 'app_radius.dart';

/// Espacements et gabarits — `DIRECTIVE_CONFORMITE_100.md` Article 2.
///
/// ## Ce que le comptage a appris, et qui corrige une idée reçue du dépôt
///
/// Recensé le 26/08/2026 sur les 50 pages du maître, `index.html` et les
/// scripts qui construisent du DOM : sur plus de 4 800 classes d'espacement,
/// **trois** seulement sont des valeurs entre crochets (`mx-[33px]` deux fois,
/// `py-[7px]` une fois).
///
/// C'est l'inverse exact des **tailles de police**, dont neuf des dix plus
/// employées sont entre crochets. La leçon souvent répétée ici — « le maître
/// n'emploie presque pas l'échelle nommée de Tailwind » — vaut pour la
/// typographie et **pas** pour l'espacement, qui suit l'échelle nommée à
/// 99,9 %. Les deux affirmations sont mesurées ; les confondre ferait chercher
/// des crochets là où il n'y en a pas, et manquer `py-2.5`.
///
/// ⚠ **`py-2.5` vaut 10 px, `py-[7px]` en vaut 7.** Le premier est de loin
/// l'espacement le plus employé du maître (672 emplois) et n'avait **aucun
/// jeton** avant cette date ; le second est l'entrée de la barre latérale, une
/// valeur arbitraire qui ne vient d'aucune échelle. L'échelle nommée n'est pas
/// la valeur entre crochets qu'elle approche.
///
/// | Rung | Valeur | Emplois relevés |
/// |---|---|---|
/// | `0.5` | 2 px | 119 `py-0.5`, 114 `mt-0.5` |
/// | `1` | 4 px | 84 `mt-1`, 65 `mb-1`, 60 `py-1` |
/// | `1.5` | 6 px | 150 `mb-1.5`, 134 `py-1.5`, 67 `mt-1.5` |
/// | `2` | 8 px | **509 `py-2`**, 173 `gap-2`, 152 `px-2` |
/// | `2.5` | 10 px | **672 `py-2.5`**, 86 `gap-2.5` |
/// | `3` | 12 px | **633 `px-3`**, 175 `py-3`, 139 `gap-3` |
/// | `3.5` | 14 px | 78 `px-3.5`, 36 `p-3.5` |
/// | `4` | 16 px | **528 `px-4`**, 87 `py-4` |
/// | `5` | 20 px | 151 `px-5`, 87 `p-5` |
/// | `6` | 24 px | 84 `px-6`, 44 `p-6` |
/// | `8` | 32 px | 53 `p-8` |
///
/// Les valeurs viennent de la table `spacing` du bundle Tailwind vendorisé,
/// relue par la garde — pas d'une conversion `rem` faite de tête.
abstract final class AppSpacing {
  /// Grille de base — `1` chez Tailwind, 0.25rem.
  static const double unit = 4;

  /// `0.5` — 0.125rem. L'écart d'une pastille à son texte.
  static const double demi = 2;

  /// `1.5` — 0.375rem. 150 emplois en marge basse d'étiquette.
  static const double xxs = 6;

  /// `2` — 0.5rem.
  static const double xs = 8;

  /// `2.5` — 0.625rem. **L'espacement le plus employé du maître** (672 `py-2.5`).
  /// Il ne se compose pas depuis [xs] : `py-2.5` n'est pas `py-2`, et l'écrire
  /// `xs + demi` serait une reconstruction, pas une lecture.
  static const double xsPlus = 10;

  /// `3` — 0.75rem. 633 emplois en marge horizontale.
  static const double sm = 12;

  /// `3.5` — 0.875rem. Le rembourrage horizontal des champs de connexion.
  static const double smPlus = 14;

  /// `4` — 1rem.
  static const double md = 16;

  /// `5` — 1.25rem. 151 `px-5`, 87 `p-5`. Il manquait à l'échelle, et le
  /// composer en `md + unit` serait une reconstruction.
  static const double mdPlus = 20;

  /// `6` — 1.5rem.
  static const double lg = 24;

  /// `7` — 1.75rem.
  static const double lgPlus = 28;

  /// `8` — 2rem.
  static const double xl = 32;

  /// `10` — 2.5rem. `py-10` de l'état vide de l'historique des prix (corps
  /// partagé des cartes, l.846) ; `xl + xs` serait une reconstruction.
  static const double xlPlus = 40;

  /// `py-[7px]` — l'entrée de la barre latérale (`shell.js` l.199).
  ///
  /// Valeur **entre crochets**, l'une des trois de tout le maître : elle ne
  /// vient d'aucune échelle. `py-2` (8 px) et `py-2.5` (10 px) l'encadrent sans
  /// la valoir, et prendre l'un des deux ferait grandir un menu de 23 entrées
  /// de 23 à 69 px.
  static const double entreeSidebar = 7;

  /// `mx-[33px]` — deux emplois, valeur entre crochets.
  static const double mx33 = 33;

  /// Les deux graphiques du pilotage consolidé — `style="height:260px"` du
  /// maître (`tableau-de-bord.html` l.208 et l.215). Valeur EN DUR dans le
  /// style du maître, mesurée et non déduite d'une échelle.
  static const double hauteurGraphePilotage = 260;
}

/// Gabarits fixes — `04_UIUX_DESIGN_SYSTEM.md` §2.3.
abstract final class AppLayout {
  static const double sidebarWidth = 264; // `w-[264px]` du maitre

  /* ------------------------------------------------------------------ */
  /* La COQUILLE — barre supérieure, barre latérale, menu de compte       */
  /*                                                                      */
  /* Relevés le 12/10/2026 sur les partiels de la vue (`menu-lateral`,    */
  /* `entree-menu`, `barre-superieure`, `lien-chassis`) — chemins écrits  */
  /* sans préfixe (PA-187). Les tailles d'icône sont les attributs        */
  /* `width`/`height` des `<svg>` de la vue, jamais une classe.           */
  /* ------------------------------------------------------------------ */

  /// `h-16` — la barre supérieure, 64 px.
  static const double hauteurBarreSuperieure = 64;

  /// `<svg width="17">` — l'icône d'une entrée de la barre latérale.
  static const double iconeLienSidebar = 17;

  /// `<svg width="22">` — le bouton de menu mobile et la bascule plein écran.
  static const double iconeBarreSuperieure = 22;

  /// `<svg width="15">` — l'icône du bouton « Vente ».
  static const double iconeVente = 15;

  /// `stroke-width="2.5"` — le trait du bouton « Vente », le seul de la
  /// coquille qui ne vaille pas 2.
  static const double epaisseurTraceVente = 2.5;

  /// `<svg width="14">` — les entrées du menu de compte et sa déconnexion
  /// (`'taille' => 14` passé à `lien-chassis`).
  static const double iconeMenuCompte = 14;

  /// `<svg width="14">` — la déconnexion du pied de la barre latérale.
  static const double iconeDeconnexionSidebar = 14;

  /// `<svg width="14">` — le chevron du bouton de compte.
  static const double iconeChevronCompte = 14;

  /// `h-10` — HAUTEUR du cadre du logo de la barre supérieure.
  static const double logoBarreSuperieure = 40;

  /// `w-[73px]` — LARGEUR du cadre du logo de la barre supérieure. PA-210
  /// tranchée par le PO le 14/10/2026, option (c) : cadre PAYSAGE au ratio
  /// du logo (735/403 × 40 ≈ 73), hauteur gardée à 40 pour ne pas faire
  /// grandir la barre (`partials/barre-superieure`).
  static const double logoBarreSuperieureLargeur = 73;

  /// `ring-2` — l'anneau doré du logo, posé HORS de la boîte : il ne prend
  /// aucune place. Tracé depuis le 14/10/2026 (D392) par une bordure
  /// `strokeAlignOutside`, plus par une ombre — l'ombre Flutter se peignait
  /// aussi SOUS le logo paysage, dans ses bandes libres.
  static const double anneauLogo = 2;

  /// `w-8 h-8` — l'avatar aux initiales (barre supérieure et pied de barre).
  static const double avatarCoquille = 32;

  /// `w-1.5 h-1.5` — la pastille d'état de l'indicateur de caisse.
  static const double pastilleCaisse = 6;

  /// `w-56` — le panneau du menu de compte.
  static const double menuCompte = 224;

  /// `top-12` — le panneau s'ouvre 48 px sous le haut de son bouton.
  static const double decalageMenuCompte = 48;

  /// Une ligne du menu de compte — `py-2.5` (2 × 10) autour d'une ligne de
  /// `text-xs` (interligne 1rem = 16 px).
  static const double ligneMenuCompte = 36;

  /// Un séparateur du menu de compte — `my-1 border-t` : 4 + 1 + 4.
  static const double separateurMenuCompte = 9;

  /// `border` / `border-t` / `border-l` — un filet de châssis, 1 px.
  static const double filetCoquille = 1;

  /// Le détail du bloc occupation du pilotage consolidé —
  /// `min-w-[240px]` (`tableau-de-bord.js`, `rendreOccupation`), valeur
  /// entre crochets, mesurée.
  static const double detailOccupation = 240;

  /// La boite de la fiche de reservation — `style="max-width:760px"` du
  /// maitre (`reservations.html` l.108). Valeur EN DUR dans le style du
  /// maitre, donc mesuree et non deduite d'une echelle.
  static const double ficheReservation = 760;

  /// Le panneau lateral glissant de l'historique — `max-w-5xl` du maitre
  /// (`reservations.html` l.63), soit 1024 px de l'echelle Tailwind. Mesure,
  /// pas suppose : `5xl` n'est pas une valeur entre crochets ici, c'est bien
  /// l'echelle nommee.
  static const double panneauLateral = 1024;

  /// Le champ de recherche de l'historique — `min-w-[180px]` (l.82), valeur
  /// ENTRE CROCHETS : elle ne vient d'aucune echelle.
  static const double champRechercheHistorique = 180;

  /// Le champ « Mot de passe SMTP » de Paramètres → Email (SMTP) : la vue le
  /// pose en `flex-1 min-w-0` à côté de ses boutons ; ici une largeur
  /// bornée, la ligne passant à la suivante (`Wrap`) quand la colonne est
  /// étroite.
  static const double champMotDePasseSmtp = 280;

  /// Une liste de filtre de l'historique. Le maitre les laisse a leur largeur
  /// naturelle (`<select>` sans classe de largeur) ; en Flutter un
  /// `DropdownButtonFormField` sans borne s'etire sur toute la ligne, ce qui
  /// casserait la rangee de filtres. Largeur retenue : celle qui contient
  /// « Tous les services » sans ellipse.
  static const double filtreHistorique = 190;

  /// Une carte d'indicateur du bandeau — `grid-cols-2 md:grid-cols-6` (l.78)
  /// sur un panneau de 1024 px moins ses marges, soit environ 160 px par
  /// carte.
  static const double carteKpi = 152;

  /// Le champ de recherche du registre clients — `min-w-[220px]`
  /// (`m3-clients-creances.html` l.51), valeur ENTRE CROCHETS. Mesuree, pas
  /// deduite d'une echelle : c'est 220, pas le `w-56` (224) le plus proche.
  static const double rechercheClients = 220;

  /// Le champ de recherche du registre des factures — `w-48`
  /// (`facturation.blade.php`, barre du registre) : 192 px.
  static const double rechercheFacture = 192;

  /// `max-w-3xl` — 768 px : la largeur maximale du sous-titre de l'historique
  /// des ventes (`historique-ventes.blade.php`).
  static const double largeur3xl = 768;

  /// Largeur de contenu à partir de laquelle l'en-tête Réservations tient en
  /// rangée : trois boutons (≈ 440 px) plus un titre qui ne se coupe pas au
  /// milieu d'un mot. La vue rétrécit son bloc de titre à `sm` (640 px) ; ici
  /// la rangée déborderait avant, d'où un seuil plus haut — écart de fenêtres
  /// étroites seulement, la mesure se fait à 1 040 px de contenu.
  static const double enTeteReservationsEnRangee = 900;

  /// La colonne de la case de sélection d'un tableau de la vue (`th px-4
  /// w-10 no-print`) : 16 + 16 de marge autour d'une case de 16 px.
  static const double colonneSelection = 48;

  /// Une liste de filtre du registre clients. Le maitre laisse ses `<select>`
  /// a leur largeur naturelle (l.55, l.57) ; un `DropdownButtonFormField` sans
  /// borne s'etire sur toute la ligne. Largeur retenue : celle qui contient
  /// « Debiteurs uniquement » sans ellipse.
  static const double filtreCreance = 210;

  /// Une carte de la bande d'indicateurs du registre clients —
  /// `grid-cols-2 lg:grid-cols-5` (l.40) sur les 1440 px de contenu moins ses
  /// marges, soit environ 265 px par carte. La bande n'en rend que trois : les
  /// deux autres dependent de la balance agee (PA-20) et des encaissements
  /// (PA-21).
  static const double carteKpiClients = 240;

  /// La modale « Nouveau client » du registre — `style="max-width:560px"`
  /// (`prototype_v2/pages/m3-clients-creances.js` l.611).
  ///
  /// Valeur **en dur dans le style du maitre**, mesuree : 560 ne vient
  /// d'aucune echelle: Tailwind passe de `max-w-lg` (512) a `max-w-xl` (576).
  /// Elle est aussi deliberement plus large que la modale « Ajouter un
  /// client » de la fiche de reservation : le registre porte deux champs de
  /// plus, sur une rangee a deux colonnes.
  static const double modaleClientCrm = 560;

  /// Largeur de la modale « Ajouter un recouvrement » de `clients-creances.blade.php`
  /// (`<x-pwa.modale … largeur="560px">`, l.634). Mesurée sur la vue, identique à
  /// « Nouveau client » — une constante à part, pour qu'un changement de l'une ne
  /// déplace pas l'autre.
  static const double modaleRecouvrementCrm = 560;

  static const double maxContentWidth = 1440;

  /// La hauteur maximale des modales de l'écran Stocks, en **fraction** de la
  /// hauteur d'écran — `max-h-[88vh]` (`prototype_v2/pages/m6-stocks.html`
  /// l.254, coquille commune aux modales « article » et « mouvement »).
  ///
  /// Mesurée, pas déduite : c'est une valeur **entre crochets**, elle ne vient
  /// d'aucune échelle Tailwind. Sans cette borne, la modale de mouvement — qui
  /// porte le journal de l'article sous son formulaire — déborde de l'écran et
  /// son pied disparaît, avec le bouton d'enregistrement.
  static const double fractionHauteurModaleStock = 0.88;

  /// La colonne d'une modale de l'écran Stocks — `max-w-lg`
  /// (`m6-stocks.html` l.254), soit 512 px de l'échelle nommée.
  ///
  /// En Flutter, un `AlertDialog` sans largeur imposée se rétracte sur son
  /// contenu : les champs d'un formulaire y deviennent illisibles, et la
  /// largeur varierait d'une modale à l'autre selon le libellé le plus long.
  static const double modaleStock = Largeurs.maxLg;

  /* ------------------------------------------------------------------ */
  /* M7 — Approvisionnement et Fournisseurs                               */
  /*                                                                      */
  /* Mesures relevees sur `prototype_v2/pages/m7-approvisionnement.html`  */
  /* et `m7-achats.html`. Les deux pages melangent l'echelle nommee de    */
  /* Tailwind (`w-56`, `max-w-2xl`) et des valeurs entre crochets         */
  /* (`max-h-[85vh]`) : chaque jeton dit laquelle, parce que les supposer */
  /* interchangeables est ce qui a fausse 900 occurrences ailleurs.       */
  /* ------------------------------------------------------------------ */

  /// Une carte de la bande d'indicateurs de l'approvisionnement —
  /// `grid-cols-2 lg:grid-cols-5` (`m7-approvisionnement.html` l.33) sur les
  /// 1440 px de contenu moins ses marges, soit environ 265 px par carte.
  ///
  /// Cinq cartes sont rendues, comme au maitre. Les deux dernieres se lisent des
  /// reglements du poste (D66, 12/10/2026) ; sans le droit de lecture, elles
  /// rendent un tiret, jamais zero (qui se lirait « aucune dette »).
  static const double carteKpiApprovisionnement = 240;

  /// Le champ de recherche de la barre d'outils — `w-56`
  /// (`m7-approvisionnement.html` l.122), soit 224 px de l'echelle NOMMEE de
  /// Tailwind. Ce n'est pas une valeur entre crochets ici : mesure, pas
  /// suppose.
  static const double rechercheAchats = 224;

  /// Le champ de recherche de l'onglet « Besoins » — `w-52` (l.192), soit
  /// 208 px. Le maitre lui donne deliberement une largeur differente de celle
  /// des trois autres onglets ; les uniformiser serait un redesign.
  static const double rechercheBesoins = 208;

  /// Une liste de filtre de M7. Le maitre laisse ses `<select>` a leur largeur
  /// naturelle (l.124) ; un `DropdownButtonFormField` sans borne s'etire sur
  /// toute la ligne et casse la rangee. Largeur retenue : celle qui contient
  /// « Receptionnee partiellement », le plus long libelle du registre, sans
  /// ellipse.
  static const double filtreAchats = 250;

  /// Le champ de quantite d'une ligne de besoin ou de reception — `w-24`
  /// (l.232 et l.651), soit 96 px de l'echelle nommee.
  static const double champQuantiteAchats = 96;

  /// La hauteur maximale des modales de M7, en **fraction** de la hauteur
  /// d'ecran — `max-h-[85vh]` (l.562 et l.625).
  ///
  /// Valeur **entre crochets**, mesuree : elle ne vient d'aucune echelle, et
  /// elle differe de celle des modales de M6 (`max-h-[88vh]`). Les aligner
  /// serait choisir a la place du maitre. Sans cette borne, la modale de
  /// commande — qui porte autant de lignes que d'articles selectionnes —
  /// deborde de l'ecran et son pied disparait avec le bouton de validation.
  static const double fractionHauteurModaleAchats = 0.85;

  /// La colonne d'une modale de M7 — `max-w-2xl` (l.562), soit 672 px de
  /// l'echelle nommee.
  static const double modaleAchats = Largeurs.max2xl;

  /// Le rembourrage VERTICAL d'un champ bordé de la vue — `py-2.5` (10 px)
  /// plus le filet de 1 px que le navigateur compte DANS la boîte : un
  /// `OutlineInputBorder` n'ajoute rien à `contentPadding`, il faut donc le
  /// poser soi-même pour retrouver les 42,25 px de la recherche et de la liste
  /// de filtre (`pwa/achats/achats.blade.php` l.94 et l.98, mesurés dans le
  /// navigateur). Ajouté le 09/10/2026.
  static const double champBordeVertical = 11;

  /// La modale « Nouveau fournisseur » / « Modifier le fournisseur » —
  /// `largeur="560px"` (`pwa/achats/achats.blade.php` l.429). Valeur en dur de
  /// la vue : ni `max-w-lg` (512) ni `max-w-xl` (576). Ajouté le 09/10/2026.
  static const double modaleFournisseurAchats = 560;

  /// La modale « Détail — [fournisseur] » — `largeur="480px"`
  /// (`pwa/achats/achats.blade.php` l.398). Valeur en dur de la vue : ni
  /// `max-w-md` (448) ni `max-w-lg` (512). Ajouté le 09/10/2026.
  static const double modaleDetailAchats = 480;

  /// La confirmation d'archivage d'un fournisseur — `max-width:420px`
  /// (composant `modale-archivage` de la PWA, l.67), la même ligne que
  /// [modaleArchivageUnite] : les deux écrans ne partagent pas un réglage, et
  /// si l'arbitrage tranchait l'inverse c'est ici qu'il s'appliquerait.
  /// Ajouté le 09/10/2026.
  static const double modaleArchivageAchats = 420;

  /// La modale « Régler » de l'Approvisionnement — `largeur="420px"`
  /// (`approvisionnement.blade.php` l.579). Valeur en dur de la vue,
  /// la même ligne que [modaleArchivageAchats] sans en partager le réglage.
  /// Ajouté le 12/10/2026.
  static const double modaleReglementAchats = 420;

  /* ------------------------------------------------------------------ */
  /* Journal des ventes — `prototype_v2/pages/historique-ventes.html`     */
  /*                                                                      */
  /* Cette page melange, elle aussi, l'echelle nommee de Tailwind (`w-56`)*/
  /* et des valeurs entre crochets (`max-w-[1500px]`, `max-width:520px`). */
  /* Chaque jeton dit laquelle des deux il porte.                         */
  /* ------------------------------------------------------------------ */

  /// La colonne de contenu du journal des ventes — `max-w-[1500px]` (l.22).
  ///
  /// Valeur **entre crochets**, mesuree : elle ne vient d'aucune echelle, et
  /// elle differe des 1440 px employes ailleurs dans le maitre
  /// ([maxContentWidth]). Les aligner serait choisir a la place du maitre.
  static const double pageHistoriqueVentes = 1500;

  /// Une carte de la bande d'indicateurs du journal — `grid-cols-2
  /// sm:grid-cols-3 xl:grid-cols-5 gap-3` (l.32) sur les 1500 px de contenu
  /// moins ses marges, soit environ 285 px par carte.
  ///
  /// Cinq cartes sont rendues, comme au maitre. **La cinquieme ne porte aucun
  /// chiffre** : ce client n'ecrit aucun mouvement de stock (PA-134), et
  /// afficher `0` dirait « toutes les ventes ont decremente ».
  static const double carteKpiVentes = 272;

  /// Le champ de recherche du journal — `w-56` (l.37), soit 224 px de
  /// l'echelle **nommee** de Tailwind. Ce n'est pas une valeur entre crochets
  /// ici : mesure, pas suppose.
  static const double rechercheVentes = 224;

  /// Une liste de filtre du journal. Le maitre laisse ses `<select>` a leur
  /// largeur naturelle (l.38-46) ; un `DropdownButtonFormField` sans borne
  /// s'etire sur toute la ligne et casse la rangee. Largeur retenue : celle
  /// qui contient « Porte sur la note de chambre », le plus long libelle du
  /// registre des reglements, sans ellipse.
  static const double filtreVentes = 250;

  /// Un champ de date du journal — `<input type="date">` (l.47-48), rendu par
  /// le navigateur a une largeur qui depend de la locale. Largeur retenue :
  /// celle qui contient « 26/08/2026 » et son bouton d'effacement.
  static const double champDateVentes = 150;

  /// La boite de la modale « Detail » — `style="max-width:520px"` (l.272).
  /// Valeur EN DUR dans le style du maitre, donc mesuree et non deduite d'une
  /// echelle.
  static const double modaleVente = 520;

  /* ------------------------------------------------------------------ */
  /* M4 — Restaurant & Cuisine                                            */
  /*                                                                      */
  /* Deux pages, deux largeurs de contenu DIFFERENTES, et l'ecart est du  */
  /* maitre : `m4-restaurant-carte.html` l.24 pose `max-w-[1500px]`,      */
  /* `m4-restauration.html` l.22 pose `max-w-[1440px]`. Les aligner       */
  /* serait « harmoniser silencieusement une incoherence du prototype »   */
  /* (Article 1, interdit 10). Chacune garde la sienne.                   */
  /* ------------------------------------------------------------------ */

  /// La colonne de contenu de la carte du restaurant — `max-w-[1500px]`
  /// (`m4-restaurant-carte.html` l.24). Valeur entre crochets, mesuree.
  ///
  /// Elle vaut le meme nombre que [pageHistoriqueVentes] et reste un jeton
  /// distinct : deux ecrans qui portent aujourd'hui la meme largeur ne sont
  /// pas le meme reglage, et le jour ou le maitre en bougerait un, un jeton
  /// partage deplacerait l'autre sans que personne ne l'ait demande.
  static const double pageCarteRestaurant = 1500;

  /// La colonne de contenu de la carte du bar — `max-w-[1500px]`
  /// (`pwa/carte/corps.blade.php` l.73, corps partage des deux cartes). Valeur
  /// entre crochets, mesuree. Jeton distinct de [pageCarteRestaurant] pour la
  /// meme raison que celui-ci l'est de [pageHistoriqueVentes] : le corps est
  /// commun aujourd'hui, rien ne dit qu'il le restera.
  static const double pageCarteBar = 1500;

  /// La liste « categorie » de la barre de filtres de la carte du bar. La vue
  /// laisse ses `<select>` a leur largeur naturelle (`corps.blade.php`
  /// l.239, l.246). ⚠ DEDUITE, non mesuree : le releve du navigateur ne porte
  /// que le champ de recherche (664,4 px a 1383 px de fenetre), d'ou la somme
  /// des deux listes (≈ 340 px, gaps de 10 px compris) ; la repartition entre
  /// elles est une estimation (« Toutes les categories » contre
  /// « En rupture de stock »). A remesurer si le releve est refait.
  static const double filtreCategorieCarteBar = 150;

  /// La liste « etat » de la barre de filtres de la carte du bar — voir
  /// [filtreCategorieCarteBar] (meme deduction, meme reserve).
  static const double filtreEtatCarteBar = 190;

  /// La liste « categorie » de la barre de filtres de la carte du RESTAURANT.
  /// Meme corps partage (`corps.blade.php` l.239) et memes mots que celle du
  /// bar (« Toutes les categories ») : meme largeur. ⚠ DEDUITE, non mesuree —
  /// le releve du navigateur ne porte que le champ de recherche (657,6 px a
  /// 1383 px de fenetre, soit 6,8 px de moins qu'au bar), d'ou une somme des
  /// deux listes voisine de 340 px. Jeton distinct de
  /// [filtreCategorieCarteBar] : deux ecrans qui portent aujourd'hui le meme
  /// nombre ne sont pas le meme reglage (09/10/2026).
  static const double filtreCategorieCarteRestaurant = 150;

  /// La liste « etat » de la barre de filtres de la carte du RESTAURANT — voir
  /// [filtreCategorieCarteRestaurant] (meme deduction, meme reserve). Elle
  /// contient « Sans lien de stock » et « En rupture de stock ».
  static const double filtreEtatCarteRestaurant = 190;

  /// La liste « statut » du panneau « Ventes » des cartes
  /// (`pwa/carte/corps.blade.php` l.576-580) : « Tous les statuts », « Validée »,
  /// « Annulée ». ⚠ DEDUITE, non mesuree (09/10/2026) : le releve du navigateur
  /// (`geometrie/restaurant__carte.json`) est pris sur l'onglet « Carte du jour »
  /// et ne contient aucun element de ce panneau. Meme largeur que
  /// [filtreCategorieCarteRestaurant], dont le plus long libelle est du meme
  /// ordre (« Tous les statuts » contre « Toutes les categories »). A remesurer
  /// si le releve est refait sur l'onglet « Ventes ».
  static const double filtreStatutVentesCarte = 150;

  /// Un champ « date » du panneau « Ventes » (`corps.blade.php` l.582-592) :
  /// `<input type="date">` en `text-[13px] px-3 py-2`, qui affiche « jj/mm/aaaa »
  /// et son icone de calendrier. ⚠ DEDUITE, non mesuree — meme reserve que
  /// [filtreStatutVentesCarte].
  static const double champDateVentesCarte = 150;

  /// La largeur MINIMALE du champ de recherche de la carte —
  /// `min-w-[200px]` sur un conteneur `flex-1` (`m4-restaurant-carte.html`
  /// l.58). Le champ s'etire, mais ne descend jamais sous cette borne.
  static const double rechercheMinCarteRestaurant = 200;

  /// Une liste de filtre de la carte du restaurant. Le maitre laisse ses
  /// `<select>` a leur largeur naturelle (l.63-71) ; un
  /// `DropdownButtonFormField` sans borne s'etire sur toute la ligne.
  /// Largeur retenue : celle qui contient « En rupture de stock », le plus
  /// long libelle du registre d'etat, sans ellipse.
  static const double filtreCarteRestaurant = 230;

  /// La barre de couverture de l'onglet « Couverture du stock » — `w-24 h-2`
  /// (`carte-module.js` l.170), soit 96 px de l'echelle **nommee** de
  /// Tailwind. Sa hauteur, elle, vaut [AppSpacing.xs].
  static const double barreCouverture = 96;

  /// La cellule qui porte le pourcentage a cote de la barre — `w-11`
  /// (`carte-module.js` l.172), soit 44 px, echelle nommee.
  ///
  /// Largeur FIXE et alignee a droite au maitre : sans elle, les barres de
  /// deux lignes voisines ne commencent pas au meme x des que l'un des taux
  /// passe de « 9 % » a « 100 % ».
  static const double tauxCouverture = 44;

  /// Le champ de recherche du catalogue de plats — le maitre le pose en
  /// `flex-1` sur toute la premiere colonne de sa barre d'outils
  /// (`crud-ui.js` l.19-22), sans borne minimale.
  ///
  /// Largeur retenue : celle qui contient l'invite du maitre, « Rechercher un
  /// plat... », sans ellipse.
  static const double rechercheRestauration = 260;

  /// La boite de la modale de formulaire du moteur CRUD —
  /// `style="max-width:560px"` (`assets/js/crud-ui.js` l.88,
  /// `champModaleFormulaireHtml`).
  ///
  /// Valeur EN DUR dans le style du maitre : Tailwind passe de `max-w-lg`
  /// (512) a `max-w-xl` (576), et 560 n'est ni l'un ni l'autre. Meme nombre
  /// que [modaleClientCrm], autre origine — deux ecrans ne partagent pas un
  /// reglage.
  static const double modalePlat = 560;

  /// Le formulaire d'un menu — `largeur="560px"` (la modale du formulaire de
  /// menu, vue du catalogue de M4). Même nombre que [modalePlat], autre ligne de
  /// la vue : deux écrans ne partagent pas un réglage.
  static const double modaleMenu = 560;

  /// Le formulaire d'une fiche technique — `largeur="680px"` (même vue, plus
  /// large parce qu'elle porte des lignes de composition).
  static const double modaleFiche = 680;

  /// Le sélecteur d'article d'une ligne de composition — `flex-1
  /// min-w-[200px]` : il prend ce qui reste de la ligne et ne descend pas sous
  /// 200 px. Rendu à 280 px fixes (le reste d'une ligne de 632 px une fois la
  /// quantité et le bouton posés, arrondi) : DÉDUIT, non relevé.
  static const double articleLigneFiche = 280;

  /// La quantité par portion — `w-[150px]`.
  static const double quantiteLigneFiche = 150;

  /// La case « prix provisoire » du formulaire de plat — `h-3.5 w-3.5` (14 px)
  /// dans la vue ; 24 px ici, la zone de toucher minimale de Material. Écart
  /// daté du 09/10/2026 : une case de 14 px est inatteignable à la souris sur
  /// un poste tactile.
  static const double casePrixProvisoire = 24;

  /// La modale de DETAIL du moteur CRUD — `style="max-width:480px"`
  /// (`crud-ui.js` l.109, `modaleDetailHtml`).
  ///
  /// Le maitre la veut plus etroite que son formulaire (560) : elle n'affiche
  /// que des paires etiquette/valeur. 480 n'est aucune borne nommee
  /// (`max-w-md` = 448, `max-w-lg` = 512).
  static const double modaleDetailPlat = 480;

  /// La modale d'export du moteur CRUD — `style="max-width:440px"`
  /// (`crud-ui.js` l.145, `modaleExportHtml`).
  ///
  /// ⚠ Le jeton jumeau des achats (`modaleExportAchats`, même ligne du maitre)
  /// a été retiré le 09/10/2026 : l'export des achats passe par la modale
  /// partagée de la PWA ([modaleExportPwa]).
  static const double modaleExportPlats = 440;

  /// La modale « Nouvelle boisson » de la Carte du bar (M5) —
  /// `largeur="520px"` (`pwa/carte/corps.blade.php` l.725). Valeur en dur de
  /// la vue, pas `max-w-lg` (512).
  static const double modaleNouvelleBoisson = 520;

  /// Hauteur d'une ligne de la liste d'articles de cette modale. La vue pose
  /// `<select size="5">` (l.757) : cinq options visibles, a une hauteur que le
  /// navigateur choisit. Ce n'est donc PAS une lecture de la vue mais une
  /// decision — `text-[13px]` plus un espacement serre — a verifier a l'ecran.
  static const double ligneArticleNouvelleBoisson = 30;

  /// Les cinq options visibles de `size="5"` (l.757).
  static const int lignesArticlesNouvelleBoisson = 5;

  /// La modale « Modifier le prix — » de la Carte du bar —
  /// `largeur="420px"` (`pwa/carte/corps.blade.php` l.803). Valeur en dur de
  /// la vue : ni `max-w-md` (448) ni `max-w-sm` (384).
  static const double modalePrixBoisson = 420;

  /// La modale « Lier au stock » — `largeur="560px"` (composant Blade
  /// `modal-lieraustock`, l.52), la mesure du maître que la vue a rétablie
  /// après une dérive à 540. Chemin écrit sans son préfixe : cité en entier,
  /// le comparateur y lirait une vue servie, et la dirait morte.
  static const double modaleLienStock = 560;

  /// La modale « Retirer de la carte du jour » — `largeur="480px"` (composant
  /// Blade `modal-retirerdelacartedujour`, l.58). Ni `max-w-md` (448) ni
  /// `max-w-lg` (512).
  static const double modaleRetraitCarte = 480;

  /// La modale d'export PARTAGÉE de la PWA — `largeur="448px"`
  /// (`pwa/partials/modale-export.blade.php` l.51), soit `max-w-md`. À ne pas
  /// confondre avec [modaleExportPlats] (440, l'ancien moteur CRUD).
  static const double modaleExportPwa = 448;

  /// La modale « Importer des articles » — `largeur="560px"` (vue des
  /// stocks, `etatFormulaire === 'import'`).
  static const double modaleImportArticles = 560;

  /// `max-h-40` — la liste des lignes refusées d'un import (160 px).
  static const double listeRefusImport = 160;

  /// La modale « Historique des prix » de la carte — `largeur="640px"`
  /// (corps partagé des cartes, l.844). Ni `max-w-xl` (576) ni `max-w-2xl`
  /// (672) : un tableau de cinq colonnes.
  static const double modaleHistoriquePrix = 640;

  /// `opacity-55` — une ligne de carte RETIRÉE du jour (corps partagé des
  /// cartes, l.336) : elle reste lisible, mais ne se confond pas avec ce qui
  /// se vend.
  static const double opaciteLigneRetiree = 0.55;

  /// L'icone posee DANS un champ — `<svg width="16" height="16">`
  /// (`crud-ui.js` l.20, la loupe du champ de recherche ; confirme par
  /// `m8-locations.html` l.57 et `m4-restaurant-carte.html` l.58).
  ///
  /// Le maitre distingue TROIS tailles d'icone : 16 dans un champ, 15 sur un
  /// bouton (`crud-ui.js` l.29 et l.33), 13 pour la corbeille d'une ligne
  /// (l.44). Les confondre est une approximation, pas une simplification.
  static const double iconeChamp = 16;

  /// L'icone d'en-tete d'une page pleine — `<svg width="24" height="24">`
  /// (`m4-restauration.html` l.25 ; idem `m4-restaurant-carte.html` l.29,
  /// `m5-bar.html` l.32, `m8-locations.html` l.30).
  ///
  /// Pas 20 : `m14-etats-studio.html` l.48 ecrit 20 pour sa barre compacte, et
  /// ce gabarit-la reste distinct.
  static const double iconeTitrePage = 24;

  /// L'icone d'une note informative de ce client (09/10/2026) : la pastille
  /// « i » des bandeaux `_Note` et des infobulles de l'ecran Parametres.
  /// Valeur du client, pas du maitre : la vue n'a pas de note de ce genre.
  static const double iconeNote = 18;

  /// L'icone d'un etat vide du moteur CRUD — `<svg width="40" height="40"
  /// stroke="#CBD5E1">` (`crud-ui.js` l.56 et l.76).
  static const double iconeEtatVide = 40;

  /* ------------------------------------------------------------------ */
  /* M8 — Vehicules & Locations                                          */
  /*                                                                      */
  /* `m8-locations.html` et `m8-locations.js` melangent les deux formes : */
  /* des crochets (`max-w-[1600px]`, `min-w-[200px]`) et des largeurs en  */
  /* dur dans l'attribut `style` (`max-width:620px`). Chaque jeton dit    */
  /* laquelle, parce que les supposer interchangeables est ce qui a       */
  /* fausse 900 occurrences ailleurs.                                     */
  /* ------------------------------------------------------------------ */

  /// La largeur de page de M8 — `max-w-[1600px]` (`m8-locations.html` l.25).
  ///
  /// Valeur ENTRE CROCHETS, propre a cette page : son planning porte 62
  /// colonnes, et le maitre lui donne 160 px de plus qu'au [maxContentWidth]
  /// des autres ecrans.
  static const double pageVehicules = 1600;

  /// La page « Congés & Plannings » — `max-w-[1600px] mx-auto p-5 lg:p-8`
  /// (`rh/conges-plannings.blade.php`). Valeur ENTRE CROCHETS, la même que
  /// [pageVehicules] : les deux vues posent la même classe.
  static const double pageCongesPlannings = 1600;

  /// Les deux `<select>` de filtre de « Congés & Plannings » (service, statut)
  /// n'ont AUCUNE largeur à la vue : le navigateur les dimensionne sur leur
  /// plus long libellé (`px-3 py-2`, 13 px). Un champ Flutter n'a pas de
  /// largeur intrinsèque : ces valeurs sont celles que le plus long libellé
  /// (« Tous les services », « Tous les statuts ») occupe. À vérifier à
  /// l'écran.
  static const double filtreServiceCongesPlannings = 200;
  static const double filtreStatutCongesPlannings = 180;

  /// Le champ de recherche du parc — `min-w-[200px]` sur un conteneur
  /// `flex-1` (`m8-locations.html` l.56). Meme motif exact que
  /// `rechercheMinCarteRestaurant`. Pas `w-52` (208) ni `w-48` (192).
  static const double rechercheMinVehicules = 200;

  /// La pastille d'un jour du planning — `h-4` (`m8-locations.js` l.171 et
  /// l.173), soit 16 px dans la table du bundle vendorise.
  ///
  /// Pas 12 : `h-3` est la puce de LEGENDE (l.180-183), un autre objet.
  static const double pastilleJourPlanning = 16;

  /// La modale « Nouveau contrat de location » — `style="max-width:620px"`
  /// (`m8-locations.js` l.220, titre l.223).
  ///
  /// Valeur en dur : 620 n'est aucune borne nommee (`max-w-xl` = 576,
  /// `max-w-2xl` = 672). Le maitre l'elargit deliberement — le contrat porte
  /// des rangees a deux colonnes.
  static const double modaleContrat = 620;

  /// La modale « Immobiliser un vehicule » — `style="max-width:520px"`
  /// (`m8-locations.js` l.334, titre l.337).
  ///
  /// 520 n'est PAS `max-w-lg` (512) : huit pixels d'ecart, exactement
  /// l'approximation que l'Article 1 interdit au n° 09.
  static const double modaleImmobilisation = 520;

  /// Les modales « Planifier un créneau » et « Demander un congé » —
  /// `largeur="520px"` (`rh/conges-plannings.blade.php`).
  static const double modaleCongesPlannings = 520;

  /// La modale « Véhicule » — `largeur="560px"` (`vehicules/locations.blade.php`
  /// l.782). Chemin écrit sans son préfixe : ce fichier ne porte pas la vue
  /// (PA-187).
  ///
  /// Elle n'existe PAS chez l'ancien maître, qui déclarait son parc en lecture
  /// seule ; c'est la vue Blade qui l'ajoute, et c'est elle qui fait foi depuis
  /// PA-183. Largeur EN DUR dans l'attribut de la vue : ni `max-w-lg` (512) ni
  /// `max-w-xl` (576). Même nombre que [modaleClientCrm] et [modalePlat], autre
  /// origine — deux écrans ne partagent pas un réglage.
  static const double modaleVehicule = 560;

  /* ------------------------------------------------------------------ */
  /* ⚠ RETABLIS LE 27/08/2026 APRES UNE PERTE ACCIDENTELLE               */
  /*                                                                      */
  /* Un script de retrait de jeton a fait une lecture-modification-       */
  /* ecriture sur ce fichier pendant qu'il etait modifie par ailleurs, et */
  /* a emporte la fin de cette classe. Les quinze jetons ci-dessus ont pu */
  /* etre RELUS dans le maitre, valeur et ligne. Les cinq qui suivent, et */
  /* `mentionPeriodeEtats` plus bas, ne le pouvaient pas : le maitre y    */
  /* laisse l'element a sa largeur naturelle, ce que Flutter ne sait pas  */
  /* faire. Ce sont donc des DECISIONS, prises a l'ecran par l'auteur du  */
  /* module — et elles ont ete perdues avec le reste.                     */
  /*                                                                      */
  /* Chacune est reprise sur un JUMEAU deja present, cite. Aucune n'est   */
  /* devinee, mais aucune n'est une lecture du maitre non plus : elles    */
  /* demandent une verification A L'ECRAN avant d'etre tenues pour        */
  /* acquises. C'est ecrit ici plutot que dans un rapport, parce qu'un    */
  /* rapport ne se relit pas au moment ou l'on touche la valeur.          */
  /* ------------------------------------------------------------------ */

  /// La liste « Toutes catégories » du parc — `vehicules/locations.blade.php`
  /// l.183 (un `<select>` sans classe de largeur).
  ///
  /// DÉRIVÉE du relevé navigateur à 1 383 px (`geometrie/vehicules__locations`),
  /// pas mesurée : les `<select>` n'y figurent pas, mais la recherche (201,8) et
  /// les trois boutons d'action (x = 1 052,7 ; 1 154,6 ; 1 263,5) le sont. La
  /// recherche tient son `min-w-[200px]`, l'espace `flex-1` prend le reste, et
  /// les deux listes occupent donc ~282 px à elles deux. Réparties selon leur
  /// libellé le plus long (« Toutes catégories » > « Contrats actifs »). À
  /// vérifier au prochain relevé qui capture les `<select>`. 09/10/2026.
  static const double filtreCategorieVehicules = 150;

  /// La liste « Contrats actifs » du parc — l.190. Voir
  /// [filtreCategorieVehicules] : même dérivation, 282 - 150.
  static const double filtreStatutVehicules = 132;

  /// Le champ de date du parc — `vehicules/locations.blade.php` l.98 et l.100
  /// (`<input type="date">` sans largeur, rendu par le navigateur).
  ///
  /// DÉRIVÉE du relevé à 1 383 px : le bouton « Exporter » commence à
  /// x = 641,3 ; avant lui, « du », « au » et deux champs de date espacés de 8.
  /// Le Flutter rend un `OutlinedButton` et non un champ. 136 recale « Exporter »
  /// à ±1 px (150 le décalait de 34,6 px à deux champs). 09/10/2026.
  static const double champDateVehicules = 136;

  /// La hauteur d'un champ de l'en-tête et de la barre de filtres du parc —
  /// MESURÉE : le champ de recherche rend 36,4 px de haut
  /// (`geometrie/vehicules__locations`, `py-2` + bordure + une ligne de 13 px).
  /// Les contrôles Material en font 40 à 48 : la rangée gagnait ~8 px que la
  /// vue n'a pas, et tout ce qui suit descendait d'autant.
  static const double hauteurChampVehicules = 36.4;

  /// Largeur à partir de laquelle la barre de filtres du parc tient sur UNE
  /// ligne — `flex flex-wrap gap-2.5` (`vehicules/locations.blade.php` l.176).
  ///
  /// Somme du minimum que la vue pose et de ce que ce client rend : recherche
  /// [rechercheMinVehicules] (200) + [filtreCategorieVehicules] (150) +
  /// [filtreStatutVehicules] (132) + les trois boutons d'action (~295 :
  /// « + Véhicule », « Immobiliser », « + Contrat ») + cinq écarts de 10 = 827,
  /// arrondie à 830. En dessous, la barre passe à la ligne comme la vue
  /// (`Wrap`). Valeur DÉRIVÉE de ces jetons : à recalculer si l'un change.
  static const double barreFiltresRangeeVehicules = 830;

  /// La premiere colonne du planning, celle du vehicule — `m8-locations.js`
  /// l.156 (`<th ... sticky left-0>`) et l.165-167.
  ///
  /// Le maitre ne borne pas cette colonne : il TRONQUE son contenu, a
  /// `v.nom.slice(0, 26)` (l.166). C'est la seule mesure exploitable, et elle
  /// porte sur des caracteres, pas sur des pixels. En Flutter la colonne doit
  /// etre fixe, sans quoi l'en-tete et les lignes cessent de s'aligner.
  /// Largeur retenue : celle qui rend 26 caracteres sans ellipse.
  /// ⚠ Valeur retablie, a verifier a l'ecran.
  static const double colonnePlanningVehicule = 200;

  /// La case d'un jour du planning — `m8-locations.js` l.158-160 et l.171.
  ///
  /// Le maitre laisse sa table en `w-full` sous `overflow-x-auto` : la
  /// largeur de case est calculee par le moteur de rendu sur 62 colonnes, et
  /// n'existe nulle part comme valeur. Plancher lisible : `px-1` de part et
  /// d'autre (8 px) plus deux chiffres a 10 px. Retenu 20, ce qui laisse
  /// 62 x 20 = 1240 px de planning a cote de la colonne vehicule, sous les
  /// [pageVehicules]. ⚠ Valeur retablie, a verifier a l'ecran.
  static const double caseJourPlanning = 20;

  /// La hauteur de la rangée d'en-tête du planning — `px-2 py-2` et
  /// `text-[11px]` (vue des locations, onglet Planning) : 8 + 16 + 8. Fixée
  /// parce que la colonne « Véhicule » est FIGÉE à gauche (`sticky left-0`)
  /// pendant que les jours défilent : deux blocs séparés qui doivent garder la
  /// même rangée (demande du PO du 14/10/2026).
  static const double hauteurEntetePlanning = 32;

  /// La hauteur d'une rangée de véhicule du planning — `py-1.5` autour de deux
  /// lignes (`text-[12px]` nom, `text-[10px]` « 5 000 FCFA/j ») : 6 + 18 + 15
  /// + 6 ≈ 45. Même raison que [hauteurEntetePlanning].
  static const double hauteurLignePlanning = 45;

  /* ------------------------------------------------------------------ */
  /* M14 — Etats & Rapports                                              */
  /*                                                                      */
  /* Contrairement a M8, trois des jetons de cette page sont des RUNGS    */
  /* NOMMES de Tailwind (`w-px`, `border-l-2`, `pl-9`) et non des valeurs */
  /* entre crochets. Seul `catalogueEtats` en est une.                    */
  /* ------------------------------------------------------------------ */

  /// La colonne du catalogue d'etats — `lg:w-[330px] shrink-0`
  /// (`m14-etats-studio.html` l.71).
  ///
  /// Valeur ENTRE CROCHETS : ni `w-80` (320) ni `w-96` (384).
  static const double catalogueEtats = 330;

  /// Le filet vertical de la barre d'outils — `w-px`
  /// (`m14-etats-studio.html` l.52), soit 1 px exactement.
  ///
  /// `px` est le seul rung Tailwind qui ne suive pas la grille de 4. La
  /// hauteur associee (`h-5` = 20 px) est deja [AppSpacing.mdPlus].
  static const double filetVertical = 1;

  /// Une bordure de controle — `border` : 1 px. La boite du navigateur la
  /// COMPTE dans la taille du controle, celle de Flutter non : on l'ajoute au
  /// remplissage pour que la hauteur mesuree coincide.
  static const double bordureControle = 1;

  /// La hauteur FIXE du bouton d'action standard (`BoutonStandard`),
  /// bordure comprise — décision du Product Owner du 14/10/2026 (40 px,
  /// rayon `AppRadius.roundedMd`), en écart assumé des ~37 px de la vue.
  static const double hauteurBoutonStandard = 40;

  /// La fenêtre « Modifier » d'un paramètre — compacte (PO, 14/10/2026) :
  /// l'`AlertDialog` d'avant sortait trop haute (« Raison sociale »).
  static const double modaleParametre = 440;

  /// La hauteur maximale de la fenêtre « Modifier » d'un paramètre.
  static const double hauteurMaxModaleParametre = 420;

  /// La modale « Passer une écriture » de la comptabilité (PO, 14/10/2026) :
  /// assez large pour la grille Compte / Libellé / Débit / Crédit.
  static const double modaleEcriture = 900;

  /// La hauteur maximale de la modale « Passer une écriture » — les lignes
  /// défilent au-delà.
  static const double hauteurMaxModaleEcriture = 640;

  /// La hauteur maximale de la liste des comptes proposés à la frappe dans
  /// cette modale — elle défile au-delà.
  static const double hauteurMaxPropositionsCompte = 240;

  /// L'icone de l'ecran d'accueil de l'apercu — `<svg width="48"
  /// height="48" stroke="#CBD5E1">` (`m14-etats-studio.js` l.120).
  ///
  /// Plus grande que l'etat vide du moteur CRUD ([iconeEtatVide], 40) :
  /// autre page, autre gabarit. Les confondre retrecirait l'accueil.
  static const double iconeAccueilEtats = 48;

  /// Le lisere d'une entree du catalogue — `border-l-2 border-transparent`
  /// (`m14-etats-studio.js` l.80), soit 2 px.
  ///
  /// Il existe MEME transparent : sans lui, l'entree selectionnee se
  /// decalerait de deux pixels au clic. Pas `border-l` (1) ni `border-l-4`.
  static const double lisereEntreeEtat = 2;

  /// La place reservee a l'icone du champ de recherche — `pl-9`
  /// (`m14-etats-studio.html` l.76), soit 2.25rem = 36 px.
  ///
  /// En HTML l'icone est en `absolute left-3` et c'est `pl-9` qui lui reserve
  /// la place ; en Flutter, `prefixIconConstraints.minWidth` est le seul
  /// levier equivalent. Pas 32 (`pl-8`) ni 40 (`pl-10`). ⚠ Le rembourrage
  /// horizontal voisin traduit le `pr-3` : il ne double pas ce jeton.
  static const double prefixeRechercheEtats = 36;

  /// La largeur de la barre de défilement — `app.css` l.79 :
  /// `::-webkit-scrollbar { width: 8px; height: 8px; }`.
  ///
  /// Une barre de navigateur CLASSIQUE occupe sa place dans la mise en page :
  /// le catalogue de `etats/studio` (`overflow-y-auto`, l.83) perd ces 8 px à
  /// droite dès qu'il déborde, et sa pastille de module en est décalée d'autant
  /// (mesuré : 8,8 px sur le relevé navigateur). Un `Scrollbar` Flutter se pose
  /// PAR-DESSUS son contenu ; le réserver est donc à l'écran de le faire.
  static const double gouttiereDefilement = 8;

  /// L'espace réservé SOUS le contenu de chaque écran de la coquille —
  /// demande du PO du 14/10/2026 : le dernier bouton ne doit jamais tomber
  /// sous la barre des tâches Windows. La vraie correction est côté fenêtre
  /// (`windows/runner/win32_window.cpp`, taille agrandie posée sur la zone de
  /// travail) ; ce jeton est la marge de sûreté, posée UNE fois par la
  /// coquille (`coquille_application.dart`) plutôt qu'écran par écran. La vue
  /// n'a pas d'équivalent (le navigateur borne la page à sa fenêtre).
  static const double margeBasseEcran = 24;

  /// Retrait des toasts (`SnackBar` flottants) par rapport aux bords de la
  /// fenêtre — demande du PO du 14/10/2026 (toasts cachés par la barre des
  /// tâches). Bas : la marge basse de l'écran plus 8 px, pour qu'un toast ne
  /// touche jamais le bord. Côtés et haut : le défaut de Flutter (15 / 5).
  static const double retraitBasToast = margeBasseEcran + 8;
  static const double retraitCoteToast = 15;
  static const double retraitHautToast = 5;

  // `mentionPeriodeEtats` (260) RETIRE le 09/10/2026 (D48) : la phrase de
  // refus de la « Periode » qu'il bornait n'est plus rendue — la vue
  // `pwa/etats/studio.blade.php` l.50-56 n'affiche plus rien a cet endroit.

  /* ------------------------------------------------------------------ */
  /* M12 — Notifications                                                 */
  /*                                                                      */
  /* Mesures relevees sur la vue maitresse `notifications/hub.blade.php`  */
  /* (chemin ecrit sans son prefixe : ce fichier ne porte pas la vue,     */
  /* PA-187). Elle melange la valeur ENTRE CROCHETS (`max-w-[1500px]`,    */
  /* `max-w-[520px]`) et la largeur EN DUR de l'attribut `largeur` du     */
  /* composant de modale (« 620px », « 480px »). Chaque jeton dit         */
  /* laquelle des deux il porte.                                          */
  /* ------------------------------------------------------------------ */

  /// La colonne de contenu du hub — `max-w-[1500px]` (l.90).
  ///
  /// Valeur ENTRE CROCHETS. Elle vaut le meme nombre que
  /// [pageHistoriqueVentes] et reste un jeton DISTINCT : deux ecrans qui
  /// portent aujourd'hui la meme largeur ne sont pas le meme reglage.
  static const double pageNotifications = 1500;

  /// L'icone d'avertissement du bandeau — `<svg width="20" height="20">`
  /// (`hub.blade.php` l.129). Valeur en dur du SVG, pas une classe Tailwind.
  static const double iconeBandeauNotifications = 20;

  /// Le detail de l'etat vide du journal — `max-w-[560px] mx-auto` (l.484).
  /// Valeur ENTRE CROCHETS : borne la phrase pour qu'elle reste lisible.
  static const double videNotifications = 560;

  /// Le plancher du champ de recherche — `flex-1 min-w-[200px]` (l.203).
  /// Valeur ENTRE CROCHETS : en dessous, le champ passe a la ligne au lieu de
  /// se comprimer.
  static const double rechercheMinNotifications = 200;

  /// Le retrait gauche du champ de recherche — `pl-9` (l.210), soit 36 px : la
  /// loupe, posee en `absolute left-3`, tient dans ce retrait.
  static const double prefixeRechercheNotifications = 36;

  /// La fleche d'un `<select>` natif — largeur ajoutee a son texte le plus
  /// long pour poser la largeur d'un filtre (l.213-231). ESTIMEE, pas mesuree :
  /// le releve navigateur ne contient pas les `<select>`, et la seule mesure
  /// qui en depend (la largeur du champ de recherche, `flex-1`) est verifiee
  /// par la garde de geometrie.
  static const double flecheSelectNotifications = 20;

  /// La bulle d'un message compose — `max-w-[520px]` (l.300 et l.351).
  ///
  /// Valeur ENTRE CROCHETS. Elle borne le texte pour qu'il reste lisible :
  /// sans elle, un message court sur toute la largeur de la page et devient
  /// illisible au-dela de 1000 px.
  static const double bulleMessageNotification = 520;

  /// La modale « Nouveau modele » / « Modifier le modele » —
  /// `largeur="620px"` (l.566).
  ///
  /// Largeur EN DUR de la vue : 620 n'est aucune borne nommee de Tailwind
  /// (`max-w-xl` = 576, `max-w-2xl` = 672). La vue l'elargit deliberement, sa
  /// premiere rangee portant deux colonnes.
  static const double modaleModeleNotification = 620;

  /// La modale d'annulation d'une réservation (titre de la vue :
  /// `reservations.annulation_titre`) — `largeur="480px"`
  /// (`hebergement/reservations.blade.php` l.793, EF-M1-06). Ni `max-w-md`
  /// (448) ni `max-w-lg` (512).
  static const double modaleAnnulationReservation = 480;

  /// Les modales « Transmis a la main » et « Abandonner » —
  /// `largeur="480px"` (l.630 et l.650).
  ///
  /// Ni `max-w-md` (448) ni `max-w-lg` (512). Les deux modales partagent cette
  /// largeur AU MAITRE : un seul jeton est donc une LECTURE, pas une
  /// factorisation.
  static const double modaleGesteNotification = 480;

  /* ------------------------------------------------------------------ */
  /* M9 — Tourisme (departs, circuits, guides)                           */
  /*                                                                      */
  /* Mesures relevees sur la vue maitresse `tourisme/departs.blade.php`   */
  /* (chemin ecrit sans son prefixe : ce fichier ne porte pas la vue,     */
  /* PA-187). Elle melange, comme M8, des valeurs ENTRE CROCHETS          */
  /* (`max-w-[1600px]`, `min-w-[200px]`), l'echelle NOMMEE de Tailwind    */
  /* (`w-20`, `h-2`) et des largeurs EN DUR dans l'attribut `largeur`     */
  /* des composants de modale (« 520px », « 560px »). Chaque jeton dit    */
  /* laquelle des trois il porte : les supposer interchangeables est ce   */
  /* qui a fausse 900 occurrences ailleurs.                               */
  /* ------------------------------------------------------------------ */

  /// La largeur de page de M9 — `max-w-[1600px]` (l.85).
  ///
  /// Valeur ENTRE CROCHETS. Elle vaut le meme nombre que [pageVehicules] et
  /// reste un jeton DISTINCT : le jour ou l'une des deux pages changera de
  /// gabarit, l'autre ne doit pas suivre par effet de bord.
  static const double pageTourisme = 1600;

  /// Le champ de recherche de la barre de filtres — `min-w-[200px]` sur un
  /// conteneur `flex-1` (l.178).
  ///
  /// Valeur ENTRE CROCHETS : ni `w-52` (208) ni `w-48` (192).
  static const double rechercheMinTourisme = 200;

  /// La première liste de filtre (la prestation) — l.191, un `<select>` sans
  /// classe de largeur.
  ///
  /// DÉDUITE, pas mesurée (09/10/2026) : le relevé à 1 383 px
  /// (`geometrie/tourisme__departs`) ne contient que des textes, jamais les
  /// boîtes natives des `<select>`. Ce qui EST mesuré : la recherche (215,1 de
  /// large, `flex-1`), le bouton principal de la barre (x = 1 236,7, texte de
  /// 83,7) et le départ de la barre (x = 310,8). La rangée de 1 025 px porte
  /// deux `flex-1` égaux (recherche et espace), un bouton de 115,7 et cinq
  /// écarts de 10 : il reste 429 px pour les TROIS listes, réparties au
  /// prorata de leur option la plus longue (22, 18 et 9 caractères) sur la
  /// base de 6,1 px par caractère + 46 px de bordure, remplissage et flèche —
  /// la même base qui retombe sur les listes de Véhicules
  /// ([filtreCategorieVehicules] 150, [filtreStatutVehicules] 132). À vérifier
  /// au prochain relevé qui capture les `<select>`.
  static const double filtrePrestationTourisme = 177;

  /// La deuxième liste (le remplissage) — l.198. Voir
  /// [filtrePrestationTourisme] : même dérivation, option la plus longue de 18
  /// caractères.
  static const double filtreRemplissageTourisme = 153;

  /// La troisième liste (le statut) — l.205. Voir [filtrePrestationTourisme] :
  /// même dérivation, option la plus longue de 9 caractères. Les trois listes
  /// font 429 px à elles trois (177 + 153 + 99).
  static const double filtreStatutTourisme = 99;

  /// Largeur à partir de laquelle la barre de filtres tient sur UNE ligne —
  /// `flex flex-wrap gap-2.5` (l.177).
  ///
  /// Somme du minimum que la vue pose et de ce que ce client rend, onglet du
  /// catalogue compris (le plus large : deux boutons d'action) : recherche
  /// [rechercheMinTourisme] (200) + les trois listes (429) + les deux boutons
  /// (~114 et ~116) + six écarts de 10 = 919, arrondie à 920. En dessous la
  /// barre passe à la ligne comme la vue (`Wrap`). DÉRIVÉE de ces jetons : à
  /// recalculer si l'un change.
  static const double barreFiltresRangeeTourisme = 920;

  /// Le champ de date de l'en-tete — l.99 et l.101 (`<input type="date">`
  /// sans largeur, rendu par le navigateur).
  ///
  /// DÉRIVÉE du relevé à 1 383 px : le bouton d'export commence à x = 641,3,
  /// comme sur Véhicules ([champDateVehicules], 136) dont l'en-tête est la même
  /// rangée (étiquette, champ, étiquette, champ, bouton). 150 le décalait de
  /// 28 px. Flutter rend un `OutlinedButton` et non un champ. 09/10/2026.
  static const double champDateTourisme = 136;

  /// La hauteur d'un champ de l'en-tête et de la barre de filtres — MESURÉE :
  /// le champ de recherche rend 36,4 px de haut au relevé
  /// (`geometrie/tourisme__departs`, `py-2` + bordure + une ligne de 13 px),
  /// la même valeur que [hauteurChampVehicules]. Les contrôles Material en
  /// font 40 à 48. 09/10/2026.
  static const double hauteurChampTourisme = 36.4;

  /// Le remplissage vertical d'une LISTE de filtre pour qu'elle mesure
  /// [hauteurChampTourisme] : (36,4 - 24) / 2. L'option affichée d'un
  /// `DropdownButton` fait 24 px de haut au minimum (mesuré le 09/10/2026 :
  /// 24 + 2 x 8 = 40 avec le remplissage d'un champ de texte), si bien que les
  /// 8 px de `py-2` portaient la liste 3,6 px au-dessus de la vue et
  /// l'ensemble de la barre avec elle. DÉRIVÉ, pas lu : la vue n'a pas de
  /// remplissage à ce niveau, seulement la hauteur finale du `<select>`.
  static const double remplissageVerticalListeTourisme = 6.2;

  /// Les modales « Reserver des places » et « Reaffecter le guide » —
  /// `largeur="520px"` (l.651 et l.755).
  ///
  /// Valeur EN DUR dans l'attribut de la vue, mesuree et non deduite d'une
  /// echelle.
  static const double modaleReservationTourisme = 520;

  /// La modale « Prestation » — `largeur="560px"` (l.793).
  ///
  /// Plus large que les deux autres, et ce n'est pas un hasard : son
  /// formulaire porte une rangee de TROIS champs (duree, prix, capacite,
  /// l.817). L'aligner sur 520 serrerait cette rangee.
  static const double modalePrestationTourisme = 560;

  /// La jauge de remplissage d'un depart — `w-20` (l.308), soit 80 px de
  /// l'echelle NOMMEE de Tailwind, pas une valeur entre crochets.
  static const double jaugeRemplissage = 80;

  /// La hauteur de cette meme jauge — `h-2` (l.308), soit 8 px.
  ///
  /// Pas `h-2.5` (10) ni `h-1.5` (6) : la vue ecrit `h-2`. [AppSpacing.xs]
  /// vaut le meme nombre, mais un espacement et une hauteur de jauge ne sont
  /// pas le meme objet — les confondre ferait suivre la jauge le jour ou
  /// l'echelle d'espacement bougerait.
  static const double hauteurJaugeRemplissage = 8;

  /* ------------------------------------------------------------------ */
  /* M10 — Depense courante                                              */
  /*                                                                      */
  /* Mesures relevees sur la vue `depenses/depenses.blade.php` (chemin    */
  /* ecrit sans son prefixe : ce fichier ne porte pas la vue, PA-187).    */
  /* Elle melange, comme les autres, une valeur ENTRE CROCHETS pour la    */
  /* largeur de page, l'echelle NOMMEE pour le champ de recherche, et une */
  /* largeur EN DUR dans l'attribut du composant de modale. Chaque jeton  */
  /* dit laquelle des trois il porte.                                     */
  /* ------------------------------------------------------------------ */

  /// La colonne de contenu de la depense courante — `max-w-[1500px]` (l.77).
  ///
  /// Valeur ENTRE CROCHETS, mesuree : elle ne vient d'aucune echelle, et elle
  /// differe des 1440 px de [maxContentWidth]. Elle vaut le meme nombre que
  /// [pageHistoriqueVentes] et reste un jeton DISTINCT : deux ecrans qui
  /// portent aujourd'hui la meme largeur ne sont pas le meme reglage, et le
  /// jour ou la vue en bougerait un, un jeton partage deplacerait l'autre.
  static const double pageDepenses = 1500;

  /// La modale « Nouvelle Depense » — `largeur="760px"` (l.326).
  ///
  /// Valeur EN DUR dans l'attribut de la vue : ni `max-w-2xl` (672) ni
  /// `max-w-3xl` (768). La vue explique elle-meme pourquoi elle s'ecarte des
  /// 560 px de la maquette — un tableau a quatre colonnes dont un selecteur de
  /// compte, dont les libelles font jusqu'a cinquante caracteres.
  ///
  /// Meme nombre que [ficheReservation], autre origine : deux ecrans ne
  /// partagent pas un reglage.
  static const double modaleDepense = 760;

  /// La hauteur maximale de la modale, en **fraction** de la hauteur d'ecran —
  /// `.boite-modale { max-height: 90vh }`, cite par l'entete de la vue
  /// (l.51-52) comme ce qui la fait defiler.
  ///
  /// Sans cette borne, une depense a dix lignes deborde de l'ecran et son pied
  /// disparait **avec le bouton d'enregistrement** : la saisie devient
  /// impossible a valider sans qu'aucune erreur ne s'affiche. C'est le defaut
  /// deja rencontre sur les modales de M6 et de M7 (piege 7).
  static const double fractionHauteurModaleDepense = 0.9;

  /// `leading-relaxed` — interligne 1.625 de l'echelle nommee de Tailwind. La
  /// bulle d'un message de notification le pose (`hub.blade.php` l.300 et
  /// l.351) ; le contenu courant, lui, est a [interligneContenu].
  static const double interligneDetendu = 1.625;

  /// Le champ de recherche de la barre de filtres — `w-56` (l.208), soit
  /// 224 px de l'echelle **nommee** de Tailwind. Mesure, pas suppose.
  static const double rechercheDepenses = 224;

  /// Un champ de date de la barre — `<input type="date">` (l.209-210), rendu
  /// par le navigateur a une largeur qui depend de la locale.
  ///
  /// DEDUIT, pas lu (D23, 09/10/2026) : le releve ne mesure que des textes, pas
  /// la boite native d'un `<input type="date">`. La SOMME des quatre controles
  /// (547,4 px entre la recherche et « Reinitialiser ») est mesuree, la
  /// repartition 131 / 145 / 141 / 131 est deduite. A remesurer dans le
  /// navigateur si l'un des quatre est resserre.
  static const double champDateDepenses = 131;

  /// Un champ de date de la période du tableau de bord — les deux
  /// `<input type="date">` de la vue d'accueil (en-tête, « Période
  /// personnalisée », et barre du pilotage). Même contrôle natif que
  /// [champDateDepenses] (`text-[13px]`, `px-2.5`) : même largeur, DÉDUITE
  /// (12/10/2026, D296) — à remesurer dans le navigateur si elle s'en écarte.
  static const double champDatePeriode = champDateDepenses;

  /// Le `<select>` de tresorerie (l.212) — voir [champDateDepenses].
  static const double filtreTresorerieDepenses = 145;

  /// Le `<select>` de categorie (l.219) — voir [champDateDepenses].
  static const double filtreCategorieDepenses = 141;

  /// L'interligne du contenu de page — `height: 1.5`, celui que `app.css`
  /// impose dans `<main>` (`TaillesContenu` en porte les tailles). C'est aussi
  /// le `line-height` du corps dont héritent les entrées et les titres de
  /// groupe de la barre latérale (hors `<main>`, 12/10/2026).
  static const double interligneContenu = 1.5;

  /// La colonne du « × » de la modale de depense : le pied du tableau la porte
  /// aussi pour que ses parts s'alignent sur celles des lignes (D24). CALCULE,
  /// pas lu : 42 px, l'ecart mesure entre le total et la colonne « Prix ».
  static const double colonneRetraitDepense = 42;

  /// La largeur MAXIMALE de la cellule « Pièces » du tableau des dépenses
  /// (10/10/2026). La vue la pose en `whitespace-nowrap` (`depenses.blade.php`
  /// l.268) et laisse le navigateur écraser les AUTRES colonnes en renvoyant
  /// leur texte à la ligne ; un `Table` Flutter ne rétrécit pas une colonne sous
  /// sa largeur de contenu. Sans plafond, les quatre pastilles de la colonne
  /// (reçu, numéro de pièce, « non comptabilisée », « Comptabiliser ») la
  /// portent à ~330 px et le bouton sort de la fenêtre. CALCULE : la plus large
  /// des deux lignes de pastilles mesure ~211 px, plafond arrondi à 232.
  static const double largeurMaxPiecesDepense = 232;

  /// La largeur du `<select>` « Centre de coût de la pièce » du bandeau de
  /// rattrapage — `block w-full sm:w-72` (`depenses.blade.php` l.127) : 288 px à
  /// partir de 640 px, toute la largeur en dessous.
  static const double choixCentreRattrapage = 288;

  /// L'icone du bouton « Nouvelle Depense » — `<svg width="15" height="15">`
  /// (`depenses.blade.php` l.97).
  static const double iconeBoutonNouvelleDepense = 15;

  /* ------------------------------------------------------------------ */
  /* M1 — Plan d'Hebergement (CRUD du parc, 14/09/2026)                  */
  /*                                                                      */
  /* Mesures relevees sur la vue `hebergement/hebergement.blade.php`      */
  /* (chemin ecrit sans son prefixe : ce fichier ne porte pas la vue,     */
  /* PA-187) et sur le composant de modale qu'elle invoque. Elle melange  */
  /* la largeur EN DUR de l'attribut `largeur` et l'echelle NOMMEE de     */
  /* Tailwind ; chaque jeton dit laquelle des deux il porte.              */
  /* ------------------------------------------------------------------ */

  /// La modale « Ajouter hebergement » / « Modifier l'hebergement » —
  /// `largeur="560px"` (l.555).
  ///
  /// Largeur EN DUR de l'attribut de la vue : Tailwind passe de `max-w-lg`
  /// (512) a `max-w-xl` (576), et 560 n'est ni l'un ni l'autre. Meme nombre
  /// que [modaleClientCrm] et [modalePlat], autre origine : deux ecrans ne
  /// partagent pas un reglage, et le jour ou la vue en bougerait un, un jeton
  /// partage deplacerait les autres.
  static const double modaleUniteHebergement = 560;

  /// La modale d'archivage — `style="max-width:420px"` (composant Blade
  /// `modale-archivage`, l.126 du moteur qu'il transcrit).
  ///
  /// La vue la veut DELIBEREMENT plus etroite que ses autres modales : elle ne
  /// porte qu'une question et son rappel. 420 n'est aucune borne nommee
  /// (`max-w-sm` = 384, `max-w-md` = 448).
  static const double modaleArchivageUnite = 420;

  /// La colonne de contenu d'Hebergement — `max-w-[1440px]` (l.56). Valeur
  /// ENTRE CROCHETS, distincte des 1500 px des cartes et des 1600 px de la
  /// paie : un reglage par ecran, jamais partage.
  static const double pageHebergement = 1440;

  /// Le `<select>` de categorie de la barre d'outils du plan (l.168). La vue le
  /// laisse a sa largeur NATURELLE, que le releve ne mesure pas (il ne releve
  /// que des textes). DEDUIT, pas lu : a 1 383 px, le releve place le champ de
  /// recherche de x = 296 a 717,3 et le bouton d'actualisation a x = 912,3 ; les
  /// deux ecarts de `gap-3` (12 px) laissent 171 px au `<select>`. A remesurer
  /// dans le navigateur si la liste des categories change de libelle le plus
  /// long (D23 : la somme est mesuree, la repartition est deduite).
  static const double filtreCategorieParc = 171;

  /// Le champ de dates de l'onglet Disponibilites — `grid grid-cols-2 gap-3
  /// max-w-md` (l.486) : le conteneur des deux dates mesure 448 px au plus
  /// (`max-w-md`), l'ecart de 12 px laisse 218 px a chacune.
  static const double largeurDatesDisponibilites = 448;

  /// L'icone d'un bouton de carte d'unite — `<svg width="14" height="14">`
  /// (l.256, 263, 270, 277, 288, 303, 314).
  static const double iconeCarteUnite = 14;

  /// L'icone des deux boutons « Nouvelle reservation » / « Ajouter
  /// hebergement » — `<svg width="15" height="15">` (l.101, 111, 193).
  static const double iconeBoutonHebergement = 15;

  /// Le carre de couleur de la legende du calendrier — `w-2.5 h-2.5` (l.436-438),
  /// soit 10 px de l'echelle nommee.
  static const double pastilleLegendeCalendrier = 10;

  /// Le cote des cases du calendrier d'occupation n'est PAS un jeton : la vue
  /// les pose en `aspect-square` dans une grille `grid-cols-7 gap-1.5`
  /// (l.463), elles se deduisent de la largeur du cadre.

  /* ------------------------------------------------------------------ */
  /* M13 — Personnel & Paie (09/10/2026)                                  */
  /*                                                                      */
  /* Mesures relevees sur `rh/paie.blade.php` (chemin ecrit sans son      */
  /* prefixe : ce fichier ne porte pas la vue, PA-187) et sur le releve   */
  /* `geometrie/rh__paie.json`. Chaque jeton dit s'il est LU ou DEDUIT.   */
  /* ------------------------------------------------------------------ */

  /// La colonne de contenu de la paie — `max-w-[1600px]` (l.102). Valeur
  /// ENTRE CROCHETS, distincte des 1500 px des autres ecrans : un reglage par
  /// ecran, jamais partage.
  static const double pagePaie = 1600;

  /// Le `<input type="month">` de l'en-tete (l.116). La vue ne lui pose
  /// aucune largeur : le navigateur le dimensionne a son contenu (texte
  /// « octobre 2026 » + pictogramme). Largeur DEDUITE du releve : le texte
  /// du bouton d'export commence a x = 525,2, donc son bouton (`px-4`) a x = 509,2 ;
  /// « Periode » occupe x = 296 a 337,9 ; `gap-2` (8 px) separe chaque
  /// element, soit 509,2 - 8 - (337,9 + 8) = 155,3 px pour le champ. Si le
  /// releve est repris, remesurer cette boite plutot que de l'ajuster a l'oeil.
  static const double champMoisPaie = 155;

  /// Les trois `<select>` de la barre de filtres (l.228, l.235, l.242). Comme
  /// pour la depense courante, la vue ne leur pose AUCUNE largeur et le releve
  /// ne mesure que des textes. Ce qui est MESURE est leur SOMME : la recherche
  /// (`flex-1`) mesure 223,9 px, autant que le `<div class="flex-1">` qui la
  /// suit, et le bouton « + Employe » finit a x = 1328,4 ; il reste 424,2 px
  /// pour trois controles. ⚠ REPARTITION DEDUITE (un `<select>` = son option
  /// la plus longue + 24 px de `px-3` + la fleche + 2 px de bordure), SOMME
  /// MESUREE : « Tous les services » ~ 150, « Tous les contrats » ~ 148,
  /// « Sans n° CNSS » ~ 126.
  static const double filtreServicePaie = 150;

  /// Le `<select>` de contrat — voir [filtreServicePaie].
  static const double filtreContratPaie = 148;

  /// Le `<select>` de statut — voir [filtreServicePaie].
  static const double filtreStatutPaie = 126;

  /// Le bouton « + Employe » (l.252) : texte de 63,4 px releve, `px-4` de part
  /// et d'autre, soit 95,4 px. Sert de seuil au passage de la barre de filtres
  /// en lignes multiples (`flex-wrap`).
  static const double boutonNouvelEmployePaie = 95.4;

  /// La case a cocher du tableau de l'effectif — `w-4 h-4` (l.306, l.333).
  static const double casePaie = 16;

  /// Le champ du brut du simulateur — `w-40` (l.628), soit 160 px de l'échelle
  /// NOMMÉE de Tailwind.
  static const double champBrutSimulePaie = 160;

  /// La largeur du texte d'explication de l'état vide de l'écriture comptable —
  /// `max-w-[640px] mx-auto` (l.556). Valeur ENTRE CROCHETS.
  static const double largeurTexteEtatVidePaie = 640;

  /// Les modales de la paie — attribut `largeur` du composant `x-pwa.modale`,
  /// valeurs EN DUR de la vue : fiche employe 620 (l.863), etablissement 600
  /// (l.978), annulation 480 (l.1013), archivage 520 (l.1037), bulletin 760
  /// (l.1075). Chacune est un reglage distinct, meme quand un autre ecran porte
  /// le meme nombre.
  static const double modalePaieEmploye = 620;

  /// Voir [modalePaieEmploye].
  static const double modalePaieEtablir = 600;

  /// Voir [modalePaieEmploye].
  static const double modalePaieAnnulation = 480;

  /// Voir [modalePaieEmploye].
  static const double modalePaieArchivage = 520;

  /// Voir [modalePaieEmploye].
  static const double modalePaieBulletin = 760;
}

/// Un palier d'espacement que l'échelle courte ne couvre pas.
///
/// `p-12` vaut 48 px chez Tailwind, et le maître l'emploie sur la colonne
/// image de la connexion. Il ne se compose pas proprement à partir de
/// [AppSpacing] — l'écrire `xl + md` serait une reconstruction, pas une
/// lecture.
/// Les largeurs maximales de l'échelle nommée de Tailwind, telles que le
/// maître les emploie.
///
/// ⚠ **Restaurée le 27/08/2026 après une perte.** Un script de retrait de
/// jeton a fait une lecture-modification-écriture sur ce fichier pendant qu'il
/// était modifié par ailleurs, et a emporté la classe entière. Les cinq
/// membres sont ceux que `lib/` référence réellement, relevés par balayage —
/// pas de mémoire.
abstract final class Largeurs {
  /// `max-w-xs` — la barre de progression de l'écran de démarrage.
  static const double maxXs = 320;

  /// `max-w-sm` — la colonne de formulaire de l'écran de connexion.
  static const double maxSm = 384;

  /// `max-w-md` — l'accroche de la colonne image.
  static const double maxMd = 448;

  /// `max-w-lg`.
  static const double maxLg = 512;

  /// `max-w-2xl` — largeur courante d'une modale du maître.
  static const double max2xl = 672;
}

abstract final class AppSpacingLarge {
  /// `p-10`.
  static const double p10 = 40;

  /// `p-12` — la colonne image de l'écran de connexion.
  static const double p12 = 48;

  /// `py-14` — l'etat vide des tableaux de M8 et M9
  /// (`m8-locations.js` l.44, `m9-tourisme-departs.js` l.45).
  static const double p14 = 56;

  /// `p-16`.
  static const double p16 = 64;
}

/// Les largeurs des panneaux du point de vente, **mesurées sur le maître**.
///
/// `prototype_v2/pages/pos.html` pose trois panneaux : la salle en
/// `xl:w-[320px]`, le catalogue en `flex-1`, le panier en `xl:w-[380px]`.
///
/// Ce sont des valeurs **arbitraires entre crochets**, pas l'échelle nommée de
/// Tailwind — les supposer en `w-80` (320) et `w-96` (384) donnerait 384 au
/// lieu de 380 sur le panier, un écart de 4 px sur la colonne qui porte les
/// montants. C'est la leçon du maître : mesurer, ne pas supposer.
///
/// Le POS clients hébergés emploie **la même ossature** : les deux écrans font
/// le même geste, ils ne doivent pas s'apprendre deux fois.
abstract final class LargeursPos {
  /// `xl:w-[320px]` — le panneau Salle.
  static const double salle = 320;

  /// `xl:w-[380px]` — le panneau Panier.
  static const double panier = 380;

  /// `xl:w-[320px]` — la colonne « Séjours en cours » du point de vente
  /// clients hébergés (`heberges.blade.php` l.80). Même valeur que [salle],
  /// nommée pour ce qu'elle porte.
  static const double sejours = 320;

  /// `w-6 h-6` — les boutons « − » / « + » d'une ligne de panier, et la
  /// largeur de la quantité entre eux (`heberges.blade.php` l.209-213).
  static const double controleQuantite = 24;

  /// `w-20` — la colonne du montant d'une ligne de panier (l.215).
  static const double montantLigne = 80;

  /// `style="max-width:520px"` de la modale « Clôturer avant le départ ? »
  /// (`heberges.blade.php` l.294, `largeur="520px"`).
  static const double modaleCloture = 520;

  /// `largeur="448px"` des modales d'ouverture et de clôture de caisse
  /// (`pos/comptant.blade.php` l.641 et l.663).
  static const double modaleCaisse = 448;

  /// `w-2 h-2` — la pastille d'état de la barre de session de caisse
  /// (`pos/comptant.blade.php` l.79 et l.143).
  static const double pastilleCaisse = 8;

  /// Hauteur de la liste des séjours EMPILÉE (sous le palier `xl`). La vue
  /// n'en pose aucune (`shrink-0 overflow-y-auto`, hauteur naturelle) ; la
  /// valeur est celle de l'ancien écran Flutter, conservée pour ne pas
  /// changer la disposition étroite (09/10/2026).
  static const double sejoursEmpiles = 200;

  /// Hauteur du panier EMPILÉ sous le palier `xl` — même remarque que
  /// [sejoursEmpiles] : valeur de l'ancien écran, pas du maître.
  static const double panierEmpile = 260;

  // --- Point de vente comptant (`pos/comptant.blade.php`), 14/10/2026 -------

  /// Hauteur du panneau Salle EMPILÉ (sous le palier `xl`) : valeur de
  /// l'ancien écran (200, littéral jusqu'au 14/10/2026), la vue n'en pose
  /// aucune.
  static const double salleEmpilee = 200;

  /// Hauteur du panier comptant EMPILÉ : valeur de l'ancien écran (280,
  /// littéral jusqu'au 14/10/2026), la vue n'en pose aucune.
  static const double panierComptantEmpile = 280;

  /// `w-8 h-8` — le carré « C » de « Vendre au comptoir » (l.172).
  static const double initialeComptoir = 32;

  /// `border-2` — la bordure de la carte « Vendre au comptoir » (l.171).
  static const double bordureComptoir = 2;

  /// `border-dashed` de la même carte : longueur d'un tiret et d'un espace.
  /// Le navigateur (Chromium) trace des tirets de TROIS fois l'épaisseur du
  /// trait, séparés d'autant — 6 px pour `border-2` ; il les ajuste ensuite
  /// côté par côté pour que les coins tombent sur un tiret (`CadreTirete` ne
  /// rejoue pas cet ajustement, écart nommé dans son en-tête, 14/10/2026).
  static const double tiretComptoir = 3 * bordureComptoir;
  static const double espaceTiretComptoir = 3 * bordureComptoir;

  /// `ring-2` — l'anneau navy de la table sélectionnée (l.199).
  static const double anneauTable = 2;

  /// `grid-cols-3` — les tables d'un espace (l.185).
  static const int colonnesTables = 3;

  /// `w-7 h-7` — les boutons « − » / « + » et la quantité d'une ligne du
  /// panier comptant (l.367-370).
  static const double controleQuantiteComptant = 28;

  /// `w-1.5 h-1.5` — le point orange d'un article sans lien de stock (l.268).
  static const double pointOrange = 6;
}

/// Les mesures de la « Vue d'exploitation » de l'accueil, relevées sur la vue
/// d'accueil (`livewire/accueil.blade.php` et son partiel des cartes
/// d'indicateur) le 12/10/2026 — lot 2 de `INSTRUCTION.txt`. Les espacements
/// passent par [AppSpacing] (échelle nommée de Tailwind : `gap-2.5` = 10,
/// `mb-5` = 20…) ; ne vivent ici que les tailles propres à cet écran.
abstract final class MesuresAccueil {
  /// `max-w-[1500px]` du conteneur de page (l.220). Même nombre que
  /// [AppLayout.pageHistoriqueVentes], jeton DISTINCT : deux écrans qui
  /// partagent une largeur par hasard ne doivent pas changer ensemble.
  static const double page = 1500;

  /// Largeur du `<select wire:model.live="filtrePeriode">` de l'en-tête. La
  /// vue n'en pose aucune : c'est la largeur naturelle du contrôle natif, celle
  /// de son option la plus longue (« Période personnalisée »), et le relevé du
  /// navigateur ne la donne pas (un `<select>` n'est pas relevé). Elle se
  /// BORNE par le relevé : le libellé de période finit à 961,7 px (`mr-3`
  /// compris), « Actualiser » commence à 1 190 px — avec les deux `gap`, le
  /// sélecteur tient en 208 px au plus. 220 (l'ancienne valeur, D296) faisait
  /// déborder la rangée d'un pixel et passer « Tableau croisé dynamique » à la
  /// ligne (mesuré le 12/10/2026). 196 = 12 + texte + 24 (flèche) + 12.
  static const double selecteurPeriode = 196;

  /// `<svg width="15">` du bouton « Actualiser » (l.290).
  static const double iconeActualiser = 15;

  /// `<svg width="14">` du bouton « Exporter » (l.301).
  static const double iconeExporter = 14;

  /// `grid-cols-2 sm:grid-cols-3 lg:grid-cols-5` de la grille des raccourcis
  /// (l.325).
  static const int colonnesAccesRapideLg = 5;
  static const int colonnesAccesRapideSm = 3;
  static const int colonnesAccesRapide = 2;

  /// `w-9 h-9` — la pastille ronde d'un accès rapide (l.328) et la pastille
  /// carrée d'une carte d'indicateur (partiel, l.59).
  static const double pastille = 36;

  /// `<svg width="16">` d'un accès rapide (l.329).
  static const double iconeAccesRapide = 16;

  /// `<svg width="17">` d'une carte d'indicateur (partiel, l.60).
  static const double iconeIndicateur = 17;

  /// `grid-cols-2 lg:grid-cols-4` de la bande d'indicateurs (l.420).
  static const int colonnesIndicateursLg = 4;
  static const int colonnesIndicateurs = 2;

  /// `<svg width="18">` du bandeau « Alertes critiques de stock » (l.568).
  static const double iconeAlerteStock = 18;

  /// `grid-cols-2 sm:grid-cols-4` du récapitulatif de la journée (l.594).
  static const int colonnesRecapSm = 4;
  static const int colonnesRecap = 2;

  /// `style="height:280px"` du graphique « Chiffre d'affaires vs Dépenses »
  /// (l.655).
  static const double hauteurGraphiqueCa = 280;

  /// Le haut de l'axe des ordonnées de « Chiffre d'affaires vs Dépenses »,
  /// en multiple de la plus haute barre. La vue ne fixe aucun maximum (l.1905 :
  /// seul le format des graduations) : Chart.js arrondit l'axe à la graduation
  /// « ronde » qui suit la plus haute barre, si bien que celle-ci ne touche
  /// jamais le cadre. `fl_chart` n'a pas cet arrondi ; 15 % de marge en tient
  /// lieu (le dépassement de Chart.js varie de 0 à ~25 % selon la valeur) —
  /// approximation nommée (13/10/2026). L'axe part toujours de ZÉRO.
  static const double margeHautAxeCa = 1.15;

  /// `style="height:220px"` de l'anneau « Réservations par activité » (l.693)
  /// et des barres « Statistiques de ventes par activité » (l.714).
  static const double hauteurGraphiqueActivites = 220;

  /// Les proportions des cinq colonnes de « Chambres disponibles » (l.739-744),
  /// lues sur le relevé du navigateur
  /// (`tool/conformite_blade/geometrie/livewire__accueil.json`) : en-têtes à
  /// 316,8 / 483,6 / 656,2 / 897,1 px, « Actions » calé à droite (1 342 px).
  /// Débuts de colonne (texte − `px-5`) : 296,8 / 463,6 / 636,2 / 877,1 —
  /// d'où 167, 173, 241 ; les 465 px restants partagent « Tarif / nuit » et
  /// « Actions » (290 / 175, la vue ne fixant que la fin de la dernière). La
  /// table de la vue est en largeur automatique ; ce poste n'a pas de moteur
  /// de table, il garde ses proportions.
  static const List<int> colonnesChambres = [167, 173, 241, 290, 175];

  /// `grid-cols-1 md:grid-cols-2 xl:grid-cols-3` de la « Consultation de
  /// secours » (l.801).
  static const int colonnesSecoursXl = 3;
  static const int colonnesSecoursMd = 2;
  static const int colonnesSecours = 1;

  /// `largeur="520px"` de la modale « Articles sous le seuil d'alerte »
  /// (l.1690).
  static const double modaleStocksCritiques = 520;

  /// `largeur="420px"` des modales client, check-in, check-out, check-in
  /// depuis une chambre, « Payer » et « Générer un rapport » (l.1421-1722).
  static const double modaleRapide = 420;

  /// `largeur="460px"` de la modale « Réservation rapide » (l.1450).
  static const double modaleReservationRapide = 460;

  /// Les proportions des SEPT colonnes de « Réservations du jour »
  /// (l.447-453 : Client, Services, Arrivée, Départ, Canal, Acompte, Actions).
  /// La table de la vue est en largeur automatique ; ce poste n'a pas de
  /// moteur de table : proportions posées sur la longueur attendue des
  /// contenus (le nom du client et les pastilles de services les plus
  /// larges, « Actions » assez large pour « Payer » + « Check-out ») —
  /// approximation nommée (14/10/2026), aucun relevé du navigateur pour ce
  /// tableau.
  static const List<int> colonnesReservationsJour = [
    200,
    200,
    110,
    110,
    130,
    130,
    190,
  ];

  /// Le poids de la première colonne (le libellé de l'article) de la table de
  /// cette modale, contre 1 pour chacune des deux colonnes de quantité. La vue
  /// pose une `<table class="w-full">` en largeur AUTOMATIQUE (l.1694) : le
  /// navigateur donne au libellé la place que les quantités, courtes, lui
  /// laissent. `Table` n'a pas ce moteur ; une moitié de la largeur pour le
  /// libellé (2 / 4) en tient lieu — approximation nommée (13/10/2026).
  static const double poidsColonneArticleCritique = 2;

  /// Les deux colonnes de texte des barres « Statistiques de ventes par
  /// activité » : le nom de l'activité à gauche, le montant à droite. La vue
  /// trace un canevas Chart.js (axe des noms, montants au survol) ; ce poste
  /// dessine ses barres et écrit le montant — largeurs de l'écran précédent,
  /// conservées (« Hébergement », « 1 250 000 FCFA » y tiennent).
  static const double colonneLibelleActivite = 96;
  static const double colonneMontantActivite = 104;
}

/// Les mesures du panneau « Accès rapides » et de son bouton flottant,
/// relevées le 13/10/2026 sur le partiel de la vue (`partials/acces-rapide`,
/// chemin sans préfixe : PA-187) — lot 3 de `INSTRUCTION.txt`. Le partiel est
/// inclus APRÈS `</main>` : aucun remappage typographique de `app.css` ne s'y
/// applique (les tailles sont celles de [Tailles], pas de [TaillesContenu]).
/// Les espacements passent par [AppSpacing] (`px-4` = 16, `py-3.5` = 14,
/// `py-2.5` = 10…) ; ne vivent ici que les tailles propres au panneau.
///
/// Aucun relevé du navigateur n'existe pour ce panneau (il est fermé, donc
/// `display: none`, au moment des captures) : ces valeurs sont LUES sur les
/// classes et les attributs `width` des `<svg>`, à l'échelle du Tailwind
/// vendorisé — pas mesurées en pixels rendus.
abstract final class MesuresAccesRapide {
  /// `w-14 h-14` — le bouton flottant rond, 56 px.
  static const double boutonFlottant = 56;

  /// `bottom-6 right-6` — sa marge au coin bas-droit de la fenêtre (24 px,
  /// l'échelle nommée `6`).
  static const double margeBoutonFlottant = AppSpacing.lg;

  /// `<svg width="24">` — l'éclair du bouton flottant.
  static const double iconeBoutonFlottant = 24;

  /// `hover:scale-105` et `active:scale-95` du bouton flottant.
  static const double echelleSurvolBouton = 1.05;
  static const double echellePressionBouton = 0.95;

  /// `w-[320px]` — la largeur du panneau, valeur ENTRE CROCHETS.
  static const double largeurPanneau = 320;

  /// `max-w-[88vw]` — sa borne, en fraction de la largeur de la fenêtre.
  static const double largeurMaxPanneau = 0.88;

  /// `<svg width="20">` — la croix de fermeture de l'en-tête.
  static const double iconeFermer = 20;

  /// `<svg width="18">` — l'icône d'une entrée.
  static const double iconeEntree = 18;

  /// `<svg width="14">` — le chevron d'une entrée.
  static const double iconeChevron = 14;
}

/// Les mesures de la RECHERCHE GLOBALE et de la CLOCHE de la barre supérieure —
/// composants `transverse/recherche-globale` et `transverse/cloche-notifications`
/// de la vue (chemins sans préfixe, PA-187), lot B du plan du PO (14/10/2026).
///
/// Les deux composants sont HORS `<main>` : aucune taille n'est remappée par
/// `app.css` ([Tailles], jamais [TaillesContenu]). Le champ de recherche est
/// mesuré dans le relevé du châssis (`chassis__administrateur.json` : texte du
/// champ à 208,4 × 16 px, la boîte `w-64` commençant 35 px plus à gauche) ;
/// les panneaux, fermés lors des captures, sont LUS sur les classes.
abstract final class MesuresBarreSuperieure {
  /// `w-64` — la boîte du champ de recherche, 256 px.
  static const double champRecherche = 256;

  /// `<svg width="14">` — la loupe du champ.
  static const double iconeRecherche = 14;

  /// `top-11` — le panneau des résultats, 44 px sous le haut du champ.
  static const double decalagePanneauRecherche = 44;

  /// `w-[420px]` — la largeur du panneau des résultats, ENTRE CROCHETS.
  static const double panneauRecherche = 420;

  /// `max-w-[90vw]` — sa borne, en fraction de la largeur de la fenêtre.
  static const double fractionMaxPanneauRecherche = 0.90;

  /// `max-h-96` — la hauteur maximale de la liste des résultats, 384 px.
  static const double hauteurMaxResultats = 384;

  /// `<svg width="13">` — la flèche d'un résultat « Pages ».
  static const double iconePageRecherche = 13;

  /// `<svg width="20">` — la cloche.
  static const double iconeCloche = 20;

  /// `min-w-[14px] h-3.5` — le badge des non-lues : 14 px de haut, 14 px de
  /// large au moins.
  static const double badgeCloche = 14;

  /// `top-1 right-1` — le décalage du badge dans le bouton, 4 px.
  static const double decalageBadgeCloche = AppSpacing.unit;

  /// `top-12` — le panneau des notifications, 48 px sous le haut du bouton.
  static const double decalagePanneauCloche = 48;

  /// `w-80` — la largeur du panneau des notifications, 320 px.
  static const double panneauCloche = 320;

  /// `max-h-80` — la hauteur maximale de sa liste, 320 px.
  static const double hauteurMaxListeCloche = 320;

  /// `w-1.5 h-1.5` — la pastille dorée d'une alerte non lue, et son
  /// `mt-1.5` (6 px) qui l'aligne sur la première ligne du titre.
  static const double pastilleNonLue = 6;
  static const double margeHautPastilleNonLue = 6;
}
