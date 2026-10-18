<?php

declare(strict_types=1);

use App\Domain\Achats\Http\Controllers\AchatController;
use App\Domain\Achats\Http\Controllers\FournisseurController;
use App\Domain\Bar\Http\Controllers\BoissonController;
use App\Domain\Comptabilite\Http\Controllers\EtatsComptablesController;
use App\Domain\Comptabilite\Http\Controllers\EtatsFinanciersController;
use App\Domain\Comptabilite\Http\Controllers\ReferentielComptableController;
use App\Domain\Crm\Http\Controllers\ClientController;
use App\Domain\Etats\Http\Controllers\EtatController;
use App\Domain\Hebergement\Http\Controllers\ParcHebergementController;
use App\Domain\Hebergement\Http\Controllers\ReservationController;
use App\Domain\Restaurant\Http\Controllers\CarteRestaurantController;
use App\Domain\Restaurant\Http\Controllers\CommandeRestaurantController;
use App\Domain\Restaurant\Http\Controllers\RecetteController;
use App\Domain\Stocks\Http\Controllers\StockController;
use App\Domain\TableauxDeBord\Http\Controllers\SerieTableauDeBordController;
use App\Domain\TableauxDeBord\Http\Controllers\TableauDeBordController;
use App\Domain\Tourisme\Http\Controllers\TourismeController;
use App\Domain\Vehicules\Http\Controllers\VehiculeController;
use App\Shared\Auth\Http\Controllers\AuthController;
use App\Shared\Parametres\Http\Controllers\ParametreController;
use App\Shared\Sync\Http\Controllers\CoherenceController;
use App\Shared\Sync\Http\Controllers\DemandeSynchronisationController;
use App\Shared\Sync\Http\Controllers\ReferentielsController;
use App\Shared\Sync\Http\Controllers\SuiviPostesController;
use App\Shared\Sync\Http\Controllers\SyncController;
use Illuminate\Support\Facades\Route;

/*
|---------------------------------------------------------------------------
| API consommee par le client Flutter
|---------------------------------------------------------------------------
| Versionnee des le depart : un client Flutter peut rester hors connexion
| plusieurs jours (guide en circuit) et synchroniser contre une version d'API
| plus recente que celle qu'il connait. Un changement cassant non versionne
| casserait silencieusement sa file de synchronisation
| (02_SOFTWARE_ARCHITECTURE.md §3.1).
|
| Authentification par jetons Sanctum, jamais par session cookie — la session
| est reservee a la PWA de consultation (routes/web.php).
|
| Chaque route porte son controle RBAC de 2e niveau via le middleware `module`.
| Le masquage d'interface cote Flutter ne protege rien : un appel direct doit
| etre refuse ici.
*/

/*
| Connexion — SEULE route publique de l'API.
|
| Elle etait absente : les 32 routes protegees exigeaient un jeton Sanctum
| qu'aucun code n'emettait. L'API entiere etait donc inaccessible au client
| Flutter. Constat fait a la Definition of Ready du Sprint 1
| (SDLC_FLUTTER.md §6.1).
|
| Aucun middleware `module:` : on ne connait pas encore le role de l'appelant,
| c'est precisement ce que cette route etablit. La limitation de debit est
| portee par le controleur, sur le couple (login + IP).
*/
Route::post('v1/login', [AuthController::class, 'connexion'])->name('api.connexion');

Route::middleware(['auth:sanctum'])->prefix('v1')->group(function () {
    // Session courante — revalidation du jeton et rafraichissement des droits
    // au demarrage du client. Pas de middleware `module:` : tout utilisateur
    // authentifie a le droit de connaitre son propre profil.
    Route::post('/logout', [AuthController::class, 'deconnexion'])->name('api.deconnexion');
    Route::get('/utilisateur', [AuthController::class, 'utilisateur'])->name('api.utilisateur');

    // Synchronisation differee du client Flutter — LARAVEL_SYNC_FLUTTER.md.
    // Pas de middleware `module:` : un lot traverse plusieurs domaines, et le
    // controle d'acces se fait par table dans le registre du service.
    Route::post('/sync', SyncController::class);

    // Le bouton « Synchroniser » du serveur (décision PO du 18/10/2026) : le
    // poste lit ici, toutes les 30 s, la dernière demande faite à la PWA.
    Route::get('/sync/demande', DemandeSynchronisationController::class);
    // Le même bouton, et l'état des postes, depuis l'écran du poste.
    Route::post('/sync/demande', [SuiviPostesController::class, 'demander']);
    Route::get('/sync/postes', [SuiviPostesController::class, 'etats']);
    // Le contrôle de cohérence du poste (P1-1) : les comptes du serveur.
    Route::get('/sync/coherence', CoherenceController::class);

    // Le CATALOGUE descendant des postes — décision PO du 15/10/2026 (le
    // serveur est maître, les postes téléchargent ; contrat dans le docblock
    // de `ReferentielsController`). Pas de middleware `module:` : le flux
    // traverse M1/M4/M5/M6/M7/M10, et chaque table n'y entre que si
    // l'utilisateur LIT son module (filtrage dans le service).
    Route::get('/referentiels', ReferentielsController::class);

    Route::prefix('hebergement')->group(function () {
        // Le PARC entier — referentiel descendant du client Flutter (PA-128).
        // `/disponibilites` repond a une question de VENTE (les unites libres
        // sur une periode) ; le client, lui, calcule la disponibilite en local
        // et a besoin du parc complet, categories et tarifs compris. Sans
        // cette route, ses tables de parc n'etaient jamais ecrites et un poste
        // neuf ne pouvait prendre aucune reservation.
        //
        // Lecture seule. Depuis le 15/10/2026 (décision PO), une unité ou une
        // catégorie créée HORS CONNEXION remonte par `/sync` et le serveur la
        // fusionne sur sa clé naturelle ; le parc complet descend aussi par
        // `/referentiels`, avec curseur.
        Route::get('/parc', ParcHebergementController::class)
            ->middleware('module:M1,L');

        Route::get('/disponibilites', [ReservationController::class, 'disponibilites'])
            ->middleware('module:M1,L');

        Route::get('/reservations', [ReservationController::class, 'index'])
            ->middleware('module:M1,L');

        Route::get('/reservations/{reservation}', [ReservationController::class, 'show'])
            ->middleware('module:M1,L');

        Route::post('/reservations', [ReservationController::class, 'store'])
            ->middleware('module:M1,C');

        // Annulation et non suppression : une reservation annulee conserve sa
        // trace, necessaire aux litiges sur acompte (RG-02).
        Route::patch('/reservations/{reservation}/annulation', [ReservationController::class, 'annuler'])
            ->middleware('module:M1,C');
    });

    // M3 — referentiel client
    Route::prefix('crm')->group(function () {
        Route::get('/clients', [ClientController::class, 'index'])
            ->middleware('module:M3,L');

        // Pre-verification RG-18 : consultative, donc niveau lecture suffisant.
        Route::get('/clients/doublons', [ClientController::class, 'verifierDoublons'])
            ->middleware('module:M3,L');

        Route::get('/clients/{client}', [ClientController::class, 'show'])
            ->middleware('module:M3,L');

        Route::post('/clients', [ClientController::class, 'store'])
            ->middleware('module:M3,C');

        Route::put('/clients/{client}', [ClientController::class, 'update'])
            ->middleware('module:M3,C');
    });

    // M8 — parc de vehicules et contrats de location
    Route::prefix('vehicules')->group(function () {
        Route::get('/', [VehiculeController::class, 'index'])
            ->middleware('module:M8,L');

        // Consultative : le niveau lecture suffit pour afficher un planning.
        Route::get('/disponibilite', [VehiculeController::class, 'disponibilite'])
            ->middleware('module:M8,L');

        Route::get('/contrats', [VehiculeController::class, 'contrats'])
            ->middleware('module:M8,L');

        // Pas de route de suppression ni d'annulation : `contrats_location`
        // n'a aucune colonne `statut` (PA-50) et aucune suppression physique
        // n'est autorisee sur une table transactionnelle.
        Route::post('/contrats', [VehiculeController::class, 'creerContrat'])
            ->middleware('module:M8,C');

        Route::post('/entretiens', [VehiculeController::class, 'enregistrerEntretien'])
            ->middleware('module:M8,C');
    });

    // M9 — circuits, guides et prestations touristiques
    Route::prefix('tourisme')->group(function () {
        Route::get('/circuits', [TourismeController::class, 'circuits'])
            ->middleware('module:M9,L');

        // EF-M9-02 : premier acces au referentiel guides, absent du prototype.
        Route::get('/guides', [TourismeController::class, 'guides'])
            ->middleware('module:M9,L');

        Route::get('/reservations', [TourismeController::class, 'reservations'])
            ->middleware('module:M9,L');

        Route::post('/reservations', [TourismeController::class, 'reserver'])
            ->middleware('module:M9,C');

        // UC-39 — affectation d'un guide a une prestation existante.
        Route::patch('/reservations/{reservation}/guide', [TourismeController::class, 'affecterGuide'])
            ->middleware('module:M9,C');

        // UC-40 — cloture de prestation.
        Route::patch('/reservations/{reservation}/cloture', [TourismeController::class, 'cloturer'])
            ->middleware('module:M9,C');

        // Annulation et non suppression : la reservation conserve sa trace,
        // et libere aussitot sa place au depart.
        Route::patch('/reservations/{reservation}/annulation', [TourismeController::class, 'annuler'])
            ->middleware('module:M9,C');
    });

    // M11 — tableau de bord consolide (EF-M11-01/03/04)
    Route::get('/tableau-de-bord', TableauDeBordController::class)
        ->middleware('module:M11,L');

    // Les SERIES des graphiques, sur leur propre route : le selecteur
    // 3/6/12 mois du prototype est independant du filtre de periode, et les
    // servir ensemble recalculerait les huit KPI a chaque bascule.
    Route::get('/tableau-de-bord/series', SerieTableauDeBordController::class)
        ->middleware('module:M11,L');

    // M14 — Hub Etats & Rapports (RG-19)
    Route::prefix('etats')->group(function () {
        // Catalogue : filtre par les droits reels du role (EF-M14-02). Pas de
        // middleware `module:M14` — le catalogue expose des etats d'AUTRES
        // modules, et son filtrage se fait etat par etat sur le module source.
        Route::get('/', [EtatController::class, 'index']);

        // Le controle RBAC porte sur le module SOURCE de l'etat demande, pas
        // sur M14 : editer l'etat des stocks exige un droit sur M6. Il est donc
        // dans GenerateurEtatService, avant tout calcul.
        Route::post('/generer', [EtatController::class, 'generer']);

        // Le journal d'edition est une donnee d'audit : il reste sur M14.
        Route::get('/archives', [EtatController::class, 'archives'])
            ->middleware('module:M14,L');
    });

    // Parametres systeme — module RBAC `PARAM`, distinct des 14 modules
    // metier : administrateur en ecriture, gerant en lecture (matrice du
    // RolePermissionSeeder). Aucun autre role n'y a acces.
    //
    // Le chemin d'ECRITURE n'existait pas : `ParametreSystemeService` etait en
    // lecture seule, et les deux garde-fous laisses ouverts par l'audit
    // (PA-61, PA-62) n'avaient donc aucun endroit ou vivre.
    Route::prefix('parametres')->group(function () {
        Route::get('/', [ParametreController::class, 'index'])
            ->middleware('module:PARAM,L');

        // PUT et non PATCH : l'ecran soumet un LOT, et sa coherence
        // s'apprecie sur l'etat resultant. Une ecriture cle par cle rendrait
        // impossible d'activer la TVA et de poser son taux du meme geste.
        Route::put('/', [ParametreController::class, 'update'])
            ->middleware('module:PARAM,C');
    });

    // M5 — carte des boissons et point de vente bar
    Route::prefix('bar')->group(function () {
        Route::get('/boissons', [BoissonController::class, 'index'])
            ->middleware('module:M5,L');

        Route::get('/boissons/{boisson}', [BoissonController::class, 'show'])
            ->middleware('module:M5,L');

        Route::post('/boissons', [BoissonController::class, 'store'])
            ->middleware('module:M5,C');

        Route::put('/boissons/{boisson}', [BoissonController::class, 'update'])
            ->middleware('module:M5,C');

        // « Lier au stock » (11/09/2026) : l'article ET son conditionnement,
        // que `PUT /boissons/{boisson}` ne sait pas porter. Sans elle, le
        // client Flutter n'aurait pu changer le lien qu'en laissant le
        // conditionnement de l'ancien article.
        Route::put('/boissons/{boisson}/lien-stock', [BoissonController::class, 'lierAuStock'])
            ->middleware('module:M5,C');

        // « Retirer de la carte du jour » et « Remettre » (11/09/2026) : les
        // deux gestes de `DisponibiliteCarteService`, que l'API n'exposait
        // pas. POST et non DELETE : remettre LÈVE l'indisponibilité, elle ne
        // l'efface pas — le « D » de CRUD n'existe nulle part dans ce dépôt.
        Route::post('/boissons/{boisson}/retrait', [BoissonController::class, 'retirer'])
            ->middleware('module:M5,C');

        Route::post('/boissons/{boisson}/remise', [BoissonController::class, 'remettre'])
            ->middleware('module:M5,C');

        // « Historique des prix » (11/09/2026) — LECTURE : `L` suffit, comme
        // dans la PWA. La trace existait (`historique_prix_carte`, écrite par
        // l'Observer) ; seule la PWA pouvait la lire.
        Route::get('/boissons/{boisson}/historique-prix', [BoissonController::class, 'historiquePrix'])
            ->middleware('module:M5,L');

        // « Ventes du Bar » (11/09/2026, PA-197) — LECTURE des lignes du
        // rayon, la même requête que l'onglet de la PWA
        // (`LignesVenteDuRayonService`, auteur unique). `L` suffit.
        Route::get('/ventes', [BoissonController::class, 'ventes'])
            ->middleware('module:M5,L');

        Route::post('/ventes', [BoissonController::class, 'vendre'])
            ->middleware('module:M5,C');
    });

    /*
    | M4 — Restaurant & Cuisine
    |
    | M4 n'avait AUCUN controleur et AUCUNE route, alors que son domaine —
    | cinq modeles, deux Services testes, un evenement — existait deja. Meme
    | racine que PA-128, PA-132 et PA-65 : une donnee absente de l'API est une
    | donnee absente du client, et le manque ne se voit d'aucun des deux cotes.
    | L'entree « Restaurant » de la barre laterale (`shell.js` l.68) ne pouvait
    | naviguer nulle part — ce que l'Article 3.3 de la directive de conformite
    | interdit desormais.
    |
    | Plus grave : `CommandeRestaurantService` et `DeductionStockCuisineService`
    | n'etaient appeles par AUCUN code de production, seulement par des tests.
    | RG-05 et RG-06 ne pouvaient donc pas s'executer une seule fois en
    | production — la deduction automatique du stock cuisine, raison d'etre du
    | module, restait du code mort. C'est la forme exacte de PA-63.
    |
    | `m4-restaurant.html` n'est PAS servie : le maitre porte lui-meme en tete
    | de cette page « Ecran remplace [...] elle n'est plus au menu », et sa
    | configuration est identique a celle de `m4-restauration.html`. Meme cas
    | que `m3-crm.html`, ecarte pour la meme raison (PA-126).
    |
    | Les routes de ce groupe exigent le reseau. Depuis le 15/10/2026
    | (decision PO, lot S2), la CREATION hors connexion d'un menu, d'une fiche
    | ou d'un plat remonte par `/sync` (fusion sur cle naturelle), et depuis
    | la decision PO du 15/10/2026 (offline-first total) sa MODIFICATION aussi
    | (dernier ecrit gagnant) — mais `commandes_restaurant` n'est toujours pas
    | au registre `TABLES_SYNCHRONISABLES` : le client n'annonce aucune mise
    | en attente sur ce qui ne partira jamais (PA-59/60/61).
    */
    Route::prefix('restaurant')->group(function () {
        // --- Carte du restaurant — EF-M4-01 ---
        //
        // L'ECRAN entier : bande d'indicateurs, onglet « Carte du jour » et
        // onglet « Couverture du stock », d'un seul parcours. Trois calculs
        // separes finiraient par se contredire a l'ecran — un total qui ne fait
        // pas la somme des lignes affichees juste en dessous (PA-121).
        //
        // Non paginee, comme `/stocks/etat` et pour la meme raison : un total
        // pose au-dessus d'une seule page se lirait comme le total de ce qu'on
        // voit.
        Route::get('/carte', [CarteRestaurantController::class, 'carte'])
            ->middleware('module:M4,L');

        // --- Catalogue des plats — EF-M4-01 ---
        //
        // Paginee, elle : c'est une liste qu'on parcourt et qu'on recherche, et
        // aucun total n'est rendu au-dessus d'une page. C'est aussi la source
        // du selecteur de plats du point de vente et du rayon « Restauration »
        // de la fiche de reservation (`reservations-services.js` l.50), rendu
        // vide faute de cette route (PA-110).
        Route::get('/plats', [CarteRestaurantController::class, 'plats'])
            ->middleware('module:M4,L');

        Route::post('/plats', [CarteRestaurantController::class, 'creerPlat'])
            ->middleware('module:M4,C');

        // Declaree APRES `/plats` et sans ambiguite : les deux prefixes sont
        // distincts.
        Route::get('/plats/{plat}', [CarteRestaurantController::class, 'plat'])
            ->middleware('module:M4,L');

        Route::put('/plats/{plat}', [CarteRestaurantController::class, 'modifierPlat'])
            ->middleware('module:M4,C');

        // --- Menus — EF-M4-01 (saison), EF-M4-06 (menus speciaux) ---
        //
        // `plats.menu_id` est NOT NULL : sans ces routes, aucun plat ne peut
        // etre cree sur une base neuve, et l'ecran de carte n'aurait jamais
        // rien a afficher. C'est le cas PA-128 applique a M4.
        Route::get('/menus', [CarteRestaurantController::class, 'menus'])
            ->middleware('module:M4,L');

        Route::post('/menus', [CarteRestaurantController::class, 'creerMenu'])
            ->middleware('module:M4,C');

        Route::put('/menus/{menu}', [CarteRestaurantController::class, 'modifierMenu'])
            ->middleware('module:M4,C');

        // --- Fiches techniques — EF-M4-02 ---
        //
        // Ces routes ferment PA-23 : le prototype porte la composition d'un
        // plat dans un textarea libre, que la specification interdit
        // explicitement de porter tel quel. Une chaine de caracteres ne se
        // rattache a aucun article, donc ne decremente aucun stock.
        Route::get('/recettes', [RecetteController::class, 'index'])
            ->middleware('module:M4,L');

        Route::post('/recettes', [RecetteController::class, 'store'])
            ->middleware('module:M4,C');

        Route::get('/recettes/{recette}', [RecetteController::class, 'show'])
            ->middleware('module:M4,L');

        // Le SOUS-FORMULAIRE de composition reclame par PA-23 : de vraies cles
        // etrangeres vers `articles`, avec leurs quantites. PUT et non PATCH —
        // la composition se remplace en entier, `ingredients_recette` n'ayant
        // aucune identite de ligne propre (cle primaire composite). Un
        // enregistrement ligne a ligne laisserait en place tout ingredient
        // retire du formulaire.
        Route::put('/recettes/{recette}/composition', [RecetteController::class, 'composition'])
            ->middleware('module:M4,C');

        // --- Commandes — EF-M4-03, EF-M4-05 ---
        Route::get('/commandes', [CommandeRestaurantController::class, 'index'])
            ->middleware('module:M4,L');

        Route::post('/commandes', [CommandeRestaurantController::class, 'store'])
            ->middleware('module:M4,C');

        // Le BON DE CUISINE — EF-M4-05.
        Route::get('/commandes/{commande}', [CommandeRestaurantController::class, 'show'])
            ->middleware('module:M4,L');

        // Transition d'etat, pas un remplacement : PATCH. C'est ICI que RG-05
        // s'applique — la deduction de stock et le changement de statut sont
        // dans la meme transaction.
        Route::patch('/commandes/{commande}/transmission', [CommandeRestaurantController::class, 'transmettre'])
            ->middleware('module:M4,C');

        Route::patch('/commandes/{commande}/service', [CommandeRestaurantController::class, 'servir'])
            ->middleware('module:M4,C');

        // Annulation et non suppression : la commande conserve sa trace. Elle
        // est refusee APRES transmission, les denrees etant engagees — ce refus
        // est le livrable, l'autoriser ferait disparaitre de la comptabilite
        // matiere des ingredients reellement sortis.
        Route::patch('/commandes/{commande}/annulation', [CommandeRestaurantController::class, 'annuler'])
            ->middleware('module:M4,C');

        // Aucune route de CLOTURE : EF-M4-07 (transfert vers la facturation)
        // exigerait un prix par ligne que `lignes_commande_restaurant` ne porte
        // pas. Router une cloture qui ne facturerait rien serait un bouton qui
        // confirme sans enregistrer (Article 6 de la directive de conformite).
    });

    /*
    | M6 — Stocks (transverse)
    |
    | M6 etait le SEUL des quatorze modules sans aucune route API, alors que
    | son domaine — modeles, six Services, Policy, etat M14 — existait deja
    | cote serveur. C'est la meme racine que PA-128 : une donnee absente de
    | l'API est une donnee absente du client, et le manque ne se voit d'aucun
    | des deux cotes. Aucun ecran Stocks, aucune couverture de stock a la
    | carte du bar, aucun rapprochement d'inventaire n'etaient portables.
    |
    | Deux Services restaient d'ailleurs SANS AUCUN APPELANT, pas meme un
    | test : `FicheStockService` et `InventaireService`. Le premier est
    | branche ici (`/articles/{article}/fiche`). Le second ne l'est pas : un
    | cycle d'inventaire est un parcours a plusieurs etapes (ouvrir, compter,
    | cloturer) qui merite son propre lot et son propre arbitrage sur le
    | comptage partiel — le livrer a la va-vite exposerait une cloture capable
    | de regulariser du stock sur un comptage incomplet.
    |
    | Aucune ecriture de ce groupe ne passe par la file de synchronisation :
    | `mouvements_stock` n'est pas au registre `TABLES_SYNCHRONISABLES`. Ces
    | routes exigent donc le reseau, et le client ne doit annoncer aucune mise
    | en attente sur ce qui ne partira jamais (PA-59/60/61).
    */
    Route::prefix('stocks')->group(function () {
        // Le referentiel des POINTS, entier et non pagine : il remplit le
        // selecteur de tout formulaire de mouvement. Un point manquant ferait
        // imputer une marchandise au mauvais endroit.
        Route::get('/points', [StockController::class, 'points'])
            ->middleware('module:M6,L');

        // L'ETAT consolide — memes filtres et memes compteurs que l'etat
        // PDF/CSV `EtatStocks` (RG-19), pour que l'ecran et le document remis
        // au Gerant ne disent jamais deux chiffres differents.
        Route::get('/etat', [StockController::class, 'etat'])
            ->middleware('module:M6,L');

        // Le JOURNAL des mouvements — EF-M6-06, « qui, quoi, quand,
        // pourquoi ». Declare avant `/articles/{article}` sans ambiguite
        // possible, les deux prefixes etant distincts.
        Route::get('/mouvements', [StockController::class, 'mouvements'])
            ->middleware('module:M6,L');

        // La seule ecriture sur `mouvements_stock`, et elle delegue
        // integralement a `MouvementStockService` : RG-06 (disponible),
        // le verrou pessimiste, et RG-07 (seuil) y vivent.
        //
        // Aucune route de modification ni de suppression n'existe : la table
        // est en ajout seul, une erreur se corrige par un mouvement inverse.
        Route::post('/mouvements', [StockController::class, 'enregistrerMouvement'])
            ->middleware('module:M6,C');

        Route::get('/articles', [StockController::class, 'articles'])
            ->middleware('module:M6,L');

        Route::post('/articles', [StockController::class, 'creerArticle'])
            ->middleware('module:M6,C');

        Route::get('/articles/{article}', [StockController::class, 'article'])
            ->middleware('module:M6,L');

        Route::put('/articles/{article}', [StockController::class, 'modifierArticle'])
            ->middleware('module:M6,C');

        // La FICHE de stock d'un article sur une periode — EF-M6-04. Le seul
        // document qui justifie un solde, et le seul qui porte un drapeau de
        // coherence : `coherent = false` signale qu'un mouvement a ete ecrit
        // hors du service dedie.
        Route::get('/articles/{article}/fiche', [StockController::class, 'fiche'])
            ->middleware('module:M6,L');
    });

    /*
    | M7 — Achats & Fournisseurs
    |
    | M7 portait deux Services testes (`ReceptionService`,
    | `ControleTroisVoiesService`) et AUCUN controleur : deux pages du maitre
    | restaient donc inaccessibles, `m7-achats.html` (referentiel fournisseurs
    | + commandes) et `m7-approvisionnement.html` (le cycle complet). Meme
    | racine que PA-128 et PA-132 : une donnee absente de l'API est une donnee
    | absente du client, et le manque ne se voit d'aucun des deux cotes.
    |
    | L'onglet « Besoins » de l'ecran d'approvisionnement n'a PAS de route
    | ici : il liste les articles sous leur seuil, ce que `GET /stocks/etat`
    | rend deja avec `sous_seuil` (M6). Le dupliquer sous M7 ferait deux
    | chemins de calcul pour le meme chiffre — exactement ce que PA-121
    | interdit. Le role `achats` porte `M6 = 'L'` a la matrice : il y accede.
    |
    | L'onglet « Dettes fournisseurs » n'a pas de route non plus, et pour une
    | raison inverse : aucune table du schema ne porte de facture ni de
    | reglement fournisseur. Le detail du refus est en tete d'`AchatController`.
    |
    | Aucune ecriture de ce groupe ne passe par la file de synchronisation :
    | ni `commandes_achat` ni `bons_reception` ne sont au registre
    | `TABLES_SYNCHRONISABLES`. Ces routes exigent donc le reseau, et le client
    | ne doit annoncer aucune mise en attente sur ce qui ne partira jamais
    | (PA-59/60/61).
    */
    Route::prefix('achats')->group(function () {
        // --- Referentiel fournisseurs — EF-M7-01 ---
        //
        // C'est aussi la source du selecteur « Fournisseur » de la modale de
        // commande. Le prototype y ecrit une liste en dur dans son JavaScript ;
        // `commandes_achat.fournisseur_id` est une VRAIE cle etrangere, et le
        // texte libre casserait silencieusement le rapprochement a trois voies.
        Route::get('/fournisseurs', [FournisseurController::class, 'index'])
            ->middleware('module:M7,L');

        Route::get('/fournisseurs/{fournisseur}', [FournisseurController::class, 'show'])
            ->middleware('module:M7,L');

        Route::post('/fournisseurs', [FournisseurController::class, 'store'])
            ->middleware('module:M7,C');

        Route::put('/fournisseurs/{fournisseur}', [FournisseurController::class, 'update'])
            ->middleware('module:M7,C');

        // --- Commandes d'achat — EF-M7-02 ---
        //
        // Aucune route de suppression ni de modification : la commande et ses
        // lignes sont transactionnelles, et le rapprochement a trois voies
        // deviendrait faux retroactivement si on les reecrivait. L'enum
        // `statut` ne porte pas non plus de valeur `annulee` — manque de
        // schema assume, signale en tete d'`AchatController`.
        Route::get('/commandes', [AchatController::class, 'commandes'])
            ->middleware('module:M7,L');

        Route::post('/commandes', [AchatController::class, 'creerCommande'])
            ->middleware('module:M7,C');

        // Le REGISTRE des receptions, declare avant `/commandes/{commande}`
        // sans ambiguite possible, les deux prefixes etant distincts.
        Route::get('/receptions', [AchatController::class, 'receptions'])
            ->middleware('module:M7,L');

        Route::get('/commandes/{commande}', [AchatController::class, 'commande'])
            ->middleware('module:M7,L');

        // Transition d'etat, pas un remplacement : PATCH.
        Route::patch('/commandes/{commande}/envoi', [AchatController::class, 'envoyerCommande'])
            ->middleware('module:M7,C');

        // La SEULE ecriture sur `bons_reception`, et elle delegue integralement
        // a `ReceptionService` : RG-10 (tolerance parametrable) et la
        // generation des entrees de stock y vivent. Une insertion directe
        // ferait un bon de reception sans marchandise en stock, et quelqu'un la
        // saisirait a la main — la double-saisie que §M7 interdit.
        Route::post('/commandes/{commande}/receptions', [AchatController::class, 'receptionner'])
            ->middleware('module:M7,C');

        // RG-10 — une commande ne se cloture que si sa reception est dans la
        // tolerance. Le refus est le livrable : forcer la cloture ferait perdre
        // la creance sur le fournisseur.
        Route::patch('/commandes/{commande}/cloture', [AchatController::class, 'cloturerCommande'])
            ->middleware('module:M7,C');

        // --- Rapprochement a trois voies — EF-M7-04 ---
        //
        // Consultatif : il constate, il n'ecrit rien, donc le niveau lecture
        // suffit. Il rend TOUJOURS `facture_verifiable: false` — aucune table
        // ne porte de facture fournisseur, et le service ne compare aucun
        // montant meme quand on lui en passe (voir `RapprochementResource`).
        Route::get('/commandes/{commande}/rapprochement', [AchatController::class, 'rapprocher'])
            ->middleware('module:M7,L');
    });

    /*
    | M10 — Comptabilite SYSCOHADA revise
    |
    | M10 etait le plus gros bloc sans aucune route API : TREIZE pages du maitre
    | en dependent, alors que son domaine — deux modeles, trois Services, un
    | Observer portant RG-11 — existait deja. Meme racine que PA-128, PA-146 et
    | PA-65 : une donnee absente de l'API est une donnee absente du client, et le
    | manque ne se voit d'aucun des deux cotes.
    |
    | Ce groupe livre le SOCLE : les quatre pages fondatrices dont les neuf
    | autres derivent — `m10-plan-comptable.html`, `m10-journal.html`,
    | `m10-grand-livre.html`, `m10-balance.html`. Bilan, Compte de resultat,
    | TAFIRE, notes annexes, analytique et cloture se calculent TOUS a partir de
    | la Balance ; les router avant elle aurait fait recalculer sept fois la meme
    | agregation (PA-121).
    |
    | ## Ces sept routes sont TOUTES en LECTURE, et c'est un constat, pas un
    | raccourci
    |
    | Les quatre pages fondatrices n'ont ni bouton d'ajout, ni action de ligne,
    | ni modale : elles consultent. Router une ecriture que rien n'appelle serait
    | le defaut PA-63, et ouvrirait une porte sur `ecritures_comptables` sans
    | qu'aucun ecran l'ait demandee. La saisie d'ecritures et la contre-passation
    | ont leur propre ecran, hors du perimetre de ce lot.
    |
    | ## AUCUNE route DELETE, et c'est plus strict qu'ailleurs
    |
    | RG-11 rend une ecriture validee immuable, et `EcritureComptableObserver`
    | refuse TOUTE suppression, meme en brouillon : un trou dans la sequence des
    | ecritures est precisement ce qu'un controle fiscal recherche. La correction
    | passe exclusivement par contre-passation. Le verbe non route (405) est la
    | preuve la plus solide qu'il n'existe pas.
    |
    | ## Trois routes de referentiel n'ont aucun controle a l'ecran
    |
    | `exercices`, `journaux` et `comptes-mouvementes` ne correspondent a aucun
    | bouton du maitre. Elles sont pourtant indispensables :
    | `MODULE_COMPTABILITE_COMPLET.md` §1 impose a TOUT ecran de M10 de filtrer
    | par `exercice_id` — sans la premiere, aucun client ne connaitrait un seul
    | identifiant d'exercice et les trois etats seraient inatteignables. Voir
    | `ReferentielComptableController` pour les deux autres.
    |
    | ## Aucune ecriture de ce groupe ne passe par la file de synchronisation
    |
    | `ecritures_comptables` n'est pas au registre `TABLES_SYNCHRONISABLES`. Ces
    | routes exigent donc le reseau, et le client ne doit annoncer aucune mise en
    | attente sur ce qui ne partira jamais (PA-59/60/61).
    */
    Route::prefix('comptabilite')->group(function () {
        // --- Referentiels ---

        // Le selecteur d'exercice, exige par §1. Non paginee : une page
        // manquante ferait disparaitre un exercice du selecteur, donc rendrait
        // ses etats inatteignables sans que rien ne le signale.
        Route::get('/exercices', [ReferentielComptableController::class, 'exercices'])
            ->middleware('module:M10,L');

        // Le referentiel des journaux — la barre de filtres de
        // `m10-journal.html`, qui ecrit ses trois codes EN DUR (l.73) la ou le
        // schema en prevoit cinq. Deux listes finiraient par diverger.
        Route::get('/journaux', [ReferentielComptableController::class, 'journaux'])
            ->middleware('module:M10,L');

        // --- Plan comptable — EF-M10-01 ---
        //
        // L'ECRAN entier d'un seul parcours : effectif du referentiel, decompte
        // par classe et lignes du tableau. Non paginee, comme
        // `GET /stocks/points` : un referentiel qui remplit un selecteur se sert
        // entier, et le sous-titre du maitre annonce l'effectif du plan.
        //
        // Aucune route d'ecriture : EF-M10-01 dit « parametrable », mais le
        // maitre ne pose sur cet ecran ni bouton d'ajout, ni action de ligne.
        Route::get('/plan-comptable', [ReferentielComptableController::class, 'planComptable'])
            ->middleware('module:M10,L');

        // --- Journal General — EF-M10-06 ---
        //
        // Totaux et bandeau d'equilibre voyagent AVEC les lignes : §2 exige un
        // controle « calcule et affiche en permanence, jamais une verification
        // ponctuelle a la demande ». Deux appels distincts finiraient par
        // afficher un bandeau qui ne correspond plus aux lignes en dessous.
        //
        // Non paginee pour la meme raison que `GET /stocks/etat` — un total pose
        // au-dessus d'une seule page se lirait comme le total de ce qu'on voit.
        // Au-dela du plafond, la route REFUSE en nommant le filtre qui debloque,
        // plutot que de tronquer : des totaux tronques annonceraient un
        // desequilibre qui n'existe pas.
        Route::get('/journal', [EtatsComptablesController::class, 'journal'])
            ->middleware('module:M10,L');

        // --- Grand Livre — EF-M10-06 ---
        //
        // Le `<select>` de l'ecran ne liste que les comptes REELLEMENT
        // mouvementes (§3) : le deriver du plan comptable complet proposerait
        // des comptes vides.
        Route::get('/comptes-mouvementes', [ReferentielComptableController::class, 'comptesMouvementes'])
            ->middleware('module:M10,L');

        // Un compte sans aucun mouvement rend 200 avec une liste vide, jamais
        // 404 : le compte existe, c'est son activite qui est nulle, et le maitre
        // a un message pour ce cas precis (l.29).
        //
        // Les soldes d'OUVERTURE et de CLOTURE descendent NULS avec leur motif :
        // le report a nouveau n'existe nulle part dans ce depot (Partie 4).
        // Rendre 0 affirmerait que le compte partait de zero au premier jour de
        // l'exercice, sur l'ecran meme ou un comptable lit un solde (Article 7).
        Route::get('/grand-livre', [EtatsComptablesController::class, 'grandLivre'])
            ->middleware('module:M10,L');

        // --- Balance Generale — EF-M10-06 ---
        //
        // Non plafonnee : une ligne par compte MOUVEMENTE, donc au plus la
        // taille du plan comptable quel que soit le nombre d'ecritures.
        //
        // `equilibree` porte sur DEUX egalites (§4), en `bccomp`. Elle n'affirme
        // rien sur l'equilibre par piece : `ecritures_comptables` n'a aucun
        // identifiant de piece (PA-52), et deux pieces fausses en sens contraire
        // rendraient `true`.
        Route::get('/balance', [EtatsComptablesController::class, 'balance'])
            ->middleware('module:M10,L');

        /*
        | --- ETATS DERIVES DE LA BALANCE ---
        |
        | ⚠ Le commentaire qui occupait cette place jusqu'au 26/08/2026 affirmait
        | qu'aucune de ces routes ne pouvait exister, « le resultat net exigeant
        | le taux d'Impot sur les Societes ». Ce motif etait FAUX, et c'est la
        | quatrieme occurrence du defaut PA-144 (apres PA-107, PA-120 et la vue
        | d'accueil de la PWA) : un motif de refus qui a cesse d'etre vrai — ou
        | qui ne l'a jamais ete — transforme une decision en oubli, et personne
        | ne rouvre la question puisque le code dit que c'est impossible.
        |
        | Deux choses etaient inexactes. D'abord, `CompteResultatService`
        | N'EXISTAIT PAS : il n'etait ecrit que dans
        | `MODULE_COMPTABILITE_COMPLET_PART3.md` §1.3. Ensuite et surtout, le
        | maitre — qui fait foi — ne calcule AUCUN impot : il additionne ce qui
        | est reellement comptabilise en classe 89 et signale que le resultat est
        | alors un resultat AVANT impot. Aucun de ces etats n'a donc besoin du
        | taux, et PA-19 n'en bloque aucun.
        |
        | La cle `taux_impot_societes` n'existe d'ailleurs ni au schema ni au
        | `RegistreParametres` : la branche de calcul du document n'aurait jamais
        | pu s'executer autrement qu'en levant.
        */

        // --- Compte de Resultat — EF-M10-06 ---
        //
        // Cascade complete des Soldes Intermediaires de Gestion. Sert
        // `m10-resultat.html` ET l'onglet du hub : les trois resultats
        // successifs du document (§1.1) sont les codes XE, XF, XG et XH de
        // cette cascade, pas un second modele.
        Route::get('/compte-resultat', [EtatsFinanciersController::class, 'compteResultat'])
            ->middleware('module:M10,L');

        // --- Bilan — EF-M10-06 ---
        //
        // Le poste de resultat au passif est la grandeur qui equilibre le
        // bilan, par la partie double : aucun taux n'y intervient. Tant que
        // rien n'est comptabilise en classe 89, c'est un resultat AVANT impot,
        // et `impot_non_comptabilise` le dit plutot que de le taire (PA-49).
        //
        // `comptes_hors_rubrique` nomme les comptes mouvementes qu'aucune
        // rubrique ne capte : la repartition par prefixe n'est pas exhaustive
        // par construction, et sans cette liste un compte hors nomenclature
        // produirait un desequilibre inexplicable.
        Route::get('/bilan', [EtatsFinanciersController::class, 'bilan'])
            ->middleware('module:M10,L');

        // --- TAFIRE — EF-M10-06 ---
        //
        // `coherent` n'est pas optionnel : §2.2 en fait le controle qui valide
        // le tableau, tout ecart signalant une erreur de methode et non une
        // « difference normale ». L'egalite se demontre par la partie double,
        // ce qui autorise a traiter un ecart comme une anomalie.
        Route::get('/tafire', [EtatsFinanciersController::class, 'tafire'])
            ->middleware('module:M10,L');

        // --- Notes Annexes — EF-M10-06 ---
        //
        // Les SEPT notes descendent toujours, avec leur etat : sans elles les
        // etats financiers sont incomplets au sens SYSCOHADA (Partie 4 §1), et
        // une note omise se lirait comme une note sans objet. Trois portent un
        // motif d'indisponibilite plutot qu'un zero.
        Route::get('/notes-annexes', [EtatsFinanciersController::class, 'notesAnnexes'])
            ->middleware('module:M10,L');

        // --- Etats Financiers consolides — EF-M10-06 ---
        //
        // Les quatre documents en UNE lecture. Ils ne sont pas recalcules — le
        // maitre l'exige (l.42) — mais quatre appels successifs pourraient
        // encadrer une ecriture et remettre au Comptable un bilan d'avant avec
        // un compte de resultat d'apres.
        Route::get('/etats-financiers', [EtatsFinanciersController::class, 'etatsFinanciers'])
            ->middleware('module:M10,L');

        // --- Analytique — EF-M10-03 ---
        //
        // Des MARGES SUR COUTS DIRECTS, jamais des resultats nets par filiere :
        // aucune cle de repartition des charges de structure n'existe dans ce
        // depot, et `repartition_structure_effectuee` le dit.
        Route::get('/analytique', [EtatsFinanciersController::class, 'analytique'])
            ->middleware('module:M10,L');

        // Le selecteur « Tous les centres » de la barre de filtres du hub, et
        // l'axe de EF-M10-03. Le maitre ecrit six centres en dur la ou
        // `ATELIER_PLAN_COMPTABLE.md` en pose sept.
        Route::get('/centres-cout', [ReferentielComptableController::class, 'centresCout'])
            ->middleware('module:M10,L');

        // --- Indicateurs du hub — EF-M10-06 ---
        //
        // Les six chiffres du bandeau de `m10-syscohada.html`. Aucun n'est
        // calcule ici : tous sont LUS du Compte de Resultat, du Bilan ou de la
        // Balance, pour que le bandeau et les onglets qu'il surplombe disent la
        // meme chose (PA-121).
        Route::get('/indicateurs', [EtatsFinanciersController::class, 'indicateurs'])
            ->middleware('module:M10,L');

        // --- Etat de cloture — EF-M10-07, en LECTURE ---
        //
        // `m10-cloture.html` n'a AUCUN bouton — pas un `addEventListener` dans
        // tout le fichier. Cette route en est la transcription fidele, pas une
        // livraison partielle : elle rend la checklist de diagnostic.
        //
        // Aucune route d'ECRITURE de cloture, et `action_exposee` descend a
        // `false` avec ses motifs. Une cloture est IRREVERSIBLE et verrouille
        // definitivement des ecritures ; or le report a nouveau n'existe nulle
        // part (Partie 4 §2.1 etape 6), aucun journal d'a-nouveaux n'existe au
        // referentiel, et le perimetre meme de la cloture n'est pas arbitre
        // (PA-28). Un bouton qui confirmerait sans ecrire est interdit par
        // l'Article 6 ; un bouton qui ecrirait sans report a nouveau produirait
        // un exercice suivant faux, sans retour possible.
        Route::get('/cloture', [EtatsFinanciersController::class, 'cloture'])
            ->middleware('module:M10,L');
    });
});
