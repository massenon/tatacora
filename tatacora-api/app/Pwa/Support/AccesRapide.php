<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;
use Illuminate\Support\Facades\Route;

/**
 * Le panneau « Accès rapides » (Alt+A) — transcription de
 * `prototype_v2/assets/js/acces-rapide.js`.
 *
 * ## Ce que cette classe répare (01/09/2026, audit navigateur)
 *
 * `pwa.partials.acces-rapide` rendait SIX raccourcis fixes, identiques sur
 * les 39 écrans servis, et le bouton flottant était `lg:hidden` — invisible
 * au-delà de 1024 px. Le maître (`acces-rapide.js` l.256-264) ne masque
 * JAMAIS ce bouton : il répond à un besoin précisément desktop (« ne plus
 * dépendre de la sidebar pour naviguer », l.6-7). Le contenu du tiroir, lui,
 * a DEUX sections dérivées de la page où l'on se trouve — « Sur cette page »
 * (`ACTIONS_PAR_PAGE`, ce qu'on déclenche typiquement DEPUIS cet écran) et
 * « Aller à » (`RACCOURCIS_UNIVERSELS`, huit destinations, la page courante
 * exclue) — jamais une liste statique.
 *
 * ## Le mappage page → route
 *
 * Le maître clé son registre par NOM DE FICHIER (`reservations.html`) ; la
 * PWA route par NOM DE ROUTE (`pwa.reservations`). Cette classe reclé
 * `ACTIONS_PAR_PAGE` par route pour lire directement
 * `Route::currentRouteName()`, sans reconstruire un chemin de fichier que la
 * PWA n'a pas.
 *
 * ## RBAC — une seule règle, jamais réécrite
 *
 * Le maître filtre par `RBAC.acces(module) !== '-'` (l.187-193). Ici,
 * `MenuLateral::moduleAccessible()` — la RÈGLE UNIQUE que `MenuLateral::pour()`
 * applique déjà à la barre latérale, `peutVoirRoute()` à la barre supérieure
 * et au menu de compte. Une troisième copie de ce test aurait fini par
 * diverger des deux premières, comme les audits précédents (PA-59 à PA-67)
 * l'ont trouvé chaque fois qu'une garde était réécrite au lieu d'être
 * partagée.
 *
 * ## Trois écarts nommés, faute d'un équivalent PWA exact
 *
 * - `pwa.stocks.liste` filtre par `etat` (`rupture` OU `sous_seuil`,
 *   `ConsultationStockService::ETATS`) et par `point` (un UUID de
 *   `points_stockage`, jamais un libellé). Le maître navigue vers
 *   `m6-stocks.html?filtre=critique` (l'union des deux) ou `?point=Cuisine`
 *   (un libellé). Aucun des deux n'a d'équivalent direct : la « Stocks
 *   critiques » du tableau de bord et les « Stocks cuisine/bar » des pages
 *   Restaurant/Bar atterrissent donc sur la liste NON filtrée plutôt que sur
 *   un filtre qui se tromperait de moitié ou d'identifiant.
 * - « Nouvelle commande » et « Réceptionner » sur `m7-approvisionnement.html`
 *   ouvrent chez le maître un formulaire vierge. `Approvisionnement::
 *   ouvrirFormulaireCommande()` agit sur `$this->selection`, cochée sur
 *   l'onglet Besoins : l'appeler à froid depuis une autre page refuserait
 *   immédiatement (`aucune_selection`). Le raccourci mène donc à l'onglet
 *   qui porte le geste (`?onglet=besoins` / `?onglet=receptions`), pas à un
 *   formulaire qui se refuserait lui-même.
 * - Les cinq onglets de `m10-syscohada.html` (`?onglet=saisie|journal|
 *   balance|resultat|bilan`) sont CINQ ROUTES distinctes côté PWA
 *   (`pwa.comptabilite.{hub,journal,balance,compte-resultat,bilan}`) : le
 *   maître fusionnait un écran que la PWA a scindé (RG-11 et l'audit
 *   d'architecture l'imposent), donc le raccourci route au lieu de
 *   paramétrer.
 *
 * @see prototype_v2/assets/js/acces-rapide.js
 */
final class AccesRapide
{
    /** Icônes du maître (`acces-rapide.js` l.119-136) — un registre distinct
     *  de `MenuLateral::ICONES` : les deux panneaux ne partagent pas tous
     *  leurs tracés (« facture » ici, « facturation » là-bas, tracés
     *  différents). */
    public const ICONES = [
        'plus' => '<path d="M12 5v14M5 12h14"/>',
        'panier' => '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>',
        'alerte' => '<path d="M10.29 3.86L1.82 18a2 2 0 001.71 3h16.94a2 2 0 001.71-3L13.71 3.86a2 2 0 00-3.42 0z"/><path d="M12 9v4M12 17h.01"/>',
        'document' => '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M14 2v6h6"/>',
        'horloge' => '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
        'hebergement' => '<path d="M3 9l9-7 9 7v11a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><path d="M9 22V12h6v10"/>',
        'facture' => '<path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path d="M16 13H8M16 17H8M10 9H8"/>',
        'stocks' => '<path d="M21 16V8a2 2 0 00-1-1.73l-7-4a2 2 0 00-2 0l-7 4A2 2 0 003 8v8a2 2 0 001 1.73l7 4a2 2 0 002 0l7-4A2 2 0 0021 16z"/>',
        'achats' => '<path d="M6 2L3 6v14a2 2 0 002 2h14a2 2 0 002-2V6l-3-4z"/><path d="M3 6h18M16 10a4 4 0 01-8 0"/>',
        'inventaire' => '<path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 01-2 2H5a2 2 0 01-2-2V5a2 2 0 012-2h11"/>',
        'entree' => '<path d="M12 5v14M19 12l-7 7-7-7"/>',
        'balance' => '<path d="M12 3v18M3 7h18M7 7l-3 7h6zM17 7l-3 7h6z"/>',
        'crm' => '<path d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/>',
        'dashboard' => '<rect x="3" y="3" width="7" height="9"/><rect x="14" y="3" width="7" height="5"/><rect x="14" y="12" width="7" height="9"/><rect x="3" y="16" width="7" height="5"/>',
        'comptabilite' => '<rect x="4" y="2" width="16" height="20" rx="2"/><path d="M8 6h8M8 10h8M8 14h4"/>',
        'retour' => '<path d="M19 12H5M12 19l-7-7 7-7"/>',
    ];

    /**
     * Reclé par nom de ROUTE PWA (voir docblock de classe pour le pourquoi).
     * Chaque entrée reprend `ACTIONS_PAR_PAGE` du maître, page par page.
     */
    public const ACTIONS_PAR_PAGE = [
        'pwa.accueil' => [
            ['libelle' => 'Nouvelle réservation', 'route' => 'pwa.reservations', 'module' => 'M1', 'icone' => 'plus'],
            ['libelle' => 'Encaisser au bar', 'route' => 'pwa.pos.comptant', 'module' => 'M5', 'icone' => 'panier'],
            ['libelle' => 'Stocks critiques', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'alerte'],
            ['libelle' => 'Générer un état', 'route' => 'pwa.etats.studio', 'module' => 'M14', 'icone' => 'document'],
        ],
        'pwa.reservations' => [
            ['libelle' => 'Historique des réservations', 'route' => 'pwa.reservations', 'params' => ['vue' => 'historique'], 'module' => 'M1', 'icone' => 'horloge'],
            ['libelle' => 'Plan des chambres', 'route' => 'pwa.hebergement', 'module' => 'M1', 'icone' => 'hebergement'],
            ['libelle' => 'Ajouter un client', 'route' => 'pwa.clients', 'module' => 'M3', 'icone' => 'plus'],
            ['libelle' => 'Facturer le séjour', 'route' => 'pwa.facturation', 'module' => 'M2', 'icone' => 'facture'],
        ],
        'pwa.hebergement' => [
            ['libelle' => 'Nouvelle réservation', 'route' => 'pwa.reservations', 'module' => 'M1', 'icone' => 'plus'],
            ['libelle' => 'Historique des réservations', 'route' => 'pwa.reservations', 'params' => ['vue' => 'historique'], 'module' => 'M1', 'icone' => 'horloge'],
            ['libelle' => 'Facturation', 'route' => 'pwa.facturation', 'module' => 'M2', 'icone' => 'facture'],
        ],
        'pwa.clients' => [
            ['libelle' => 'Créances & relances', 'route' => 'pwa.clients', 'params' => ['vue' => 'creances'], 'module' => 'M3', 'icone' => 'alerte'],
            ['libelle' => 'Nouvelle réservation', 'route' => 'pwa.reservations', 'module' => 'M1', 'icone' => 'plus'],
            ['libelle' => 'Facturation', 'route' => 'pwa.facturation', 'module' => 'M2', 'icone' => 'facture'],
        ],
        'pwa.restaurant.carte' => [
            ['libelle' => 'Point de vente', 'route' => 'pwa.pos.comptant', 'module' => 'M4', 'icone' => 'panier'],
            ['libelle' => 'Stocks cuisine', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
        ],
        'pwa.bar.carte' => [
            ['libelle' => 'Point de vente', 'route' => 'pwa.pos.comptant', 'module' => 'M5', 'icone' => 'panier'],
            ['libelle' => 'Stocks bar', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
        ],
        'pwa.stocks.liste' => [
            ['libelle' => 'Inventaire physique', 'route' => 'pwa.stocks.inventaires', 'module' => 'M6', 'icone' => 'inventaire'],
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
            ['libelle' => 'Articles sous seuil', 'route' => 'pwa.stocks.liste', 'params' => ['etat' => 'sous_seuil'], 'module' => 'M6', 'icone' => 'alerte'],
            ['libelle' => 'Fiche de stock', 'route' => 'pwa.stocks.inventaires', 'module' => 'M6', 'icone' => 'document'],
        ],
        'pwa.achats.liste' => [
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
            ['libelle' => 'Dettes fournisseurs', 'route' => 'pwa.achats.approvisionnement', 'params' => ['onglet' => 'dettes'], 'module' => 'M7', 'icone' => 'alerte'],
            ['libelle' => 'Stocks', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
        ],
        'pwa.achats.approvisionnement' => [
            ['libelle' => 'Nouvelle commande', 'route' => 'pwa.achats.approvisionnement', 'params' => ['onglet' => 'besoins'], 'module' => 'M7', 'icone' => 'plus'],
            ['libelle' => 'Réceptionner', 'route' => 'pwa.achats.approvisionnement', 'params' => ['onglet' => 'receptions'], 'module' => 'M7', 'icone' => 'entree'],
            ['libelle' => 'Fournisseurs', 'route' => 'pwa.achats.liste', 'module' => 'M7', 'icone' => 'achats'],
            ['libelle' => 'Stocks', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
        ],
        'pwa.stocks.inventaires' => [
            ['libelle' => 'Stocks', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
        ],
        'pwa.pos.comptant' => [
            ['libelle' => 'Stocks du point de vente', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
            ['libelle' => 'Approvisionnement', 'route' => 'pwa.achats.approvisionnement', 'module' => 'M7', 'icone' => 'achats'],
            ['libelle' => 'Facturation', 'route' => 'pwa.facturation', 'module' => 'M2', 'icone' => 'facture'],
        ],
        'pwa.comptabilite.hub' => [
            ['libelle' => 'Passer une écriture', 'route' => 'pwa.comptabilite.hub', 'module' => 'M10', 'icone' => 'plus'],
            ['libelle' => 'Journal comptable', 'route' => 'pwa.comptabilite.journal', 'module' => 'M10', 'icone' => 'document'],
            ['libelle' => 'Balance générale', 'route' => 'pwa.comptabilite.balance', 'module' => 'M10', 'icone' => 'balance'],
            ['libelle' => 'Compte de résultat', 'route' => 'pwa.comptabilite.compte-resultat', 'module' => 'M10', 'icone' => 'document'],
            ['libelle' => 'Bilan', 'route' => 'pwa.comptabilite.bilan', 'module' => 'M10', 'icone' => 'balance'],
        ],
    ];

    /** `RACCOURCIS_UNIVERSELS` du maître (`acces-rapide.js` l.108-117). */
    public const RACCOURCIS_UNIVERSELS = [
        ['libelle' => 'Tableau de bord', 'route' => 'pwa.accueil', 'module' => 'M11', 'icone' => 'dashboard'],
        ['libelle' => 'Nouvelle réservation', 'route' => 'pwa.reservations', 'module' => 'M1', 'icone' => 'plus'],
        ['libelle' => 'Clients', 'route' => 'pwa.clients', 'module' => 'M3', 'icone' => 'crm'],
        ['libelle' => 'Point de vente', 'route' => 'pwa.pos.comptant', 'module' => 'M5', 'icone' => 'panier'],
        ['libelle' => 'Facturation', 'route' => 'pwa.facturation', 'module' => 'M2', 'icone' => 'facture'],
        ['libelle' => 'Stocks', 'route' => 'pwa.stocks.liste', 'module' => 'M6', 'icone' => 'stocks'],
        ['libelle' => 'Comptabilité', 'route' => 'pwa.comptabilite.hub', 'module' => 'M10', 'icone' => 'comptabilite'],
        ['libelle' => 'États & Rapports', 'route' => 'pwa.etats.studio', 'module' => 'M14', 'icone' => 'document'],
    ];

    /**
     * « Sur cette page » — filtrée par la règle unique de masquage
     * d'interface, jamais une seconde copie du RBAC.
     *
     * @return list<array{libelle: string, route: string, params?: array<string,string>, module: string, icone: string}>
     */
    public static function actionsContextuelles(?User $utilisateur, ?string $routeActuelle): array
    {
        $entrees = self::ACTIONS_PAR_PAGE[$routeActuelle] ?? [];

        return array_values(array_filter(
            $entrees,
            static fn (array $entree): bool => MenuLateral::moduleAccessible($utilisateur, $entree['module']),
        ));
    }

    /**
     * « Aller à » — les huit destinations universelles, la page courante
     * exclue (`acces-rapide.js` l.253 : `RACCOURCIS_UNIVERSELS.filter((r) =>
     * r.page !== pageActuelle())`).
     *
     * @return list<array{libelle: string, route: string, module: string, icone: string}>
     */
    public static function raccourcisUniversels(?User $utilisateur, ?string $routeActuelle): array
    {
        return array_values(array_filter(
            self::RACCOURCIS_UNIVERSELS,
            static fn (array $entree): bool => $entree['route'] !== $routeActuelle
                && MenuLateral::moduleAccessible($utilisateur, $entree['module']),
        ));
    }

    /**
     * @param  array{route: string, params?: array<string,string>}  $entree
     */
    public static function url(array $entree): string
    {
        $route = $entree['route'];
        $params = $entree['params'] ?? [];

        return Route::has($route) ? route($route, $params) : url('/pwa');
    }

    /**
     * Le libellé de la page courante, affiché en sous-titre du panneau —
     * `libellePage(pageActuelle())` du maître (l.146-156). Dérivé de
     * `MenuLateral::NAVIGATION`, jamais une seconde table de libellés.
     */
    /**
     * ⚠ Le sous-titre suit la MÊME règle de masquage que tout le reste
     * (01/09/2026). Sans le contrôle, un rôle sans M11 atterrissant sur
     * `/pwa` — donc sur la consultation de secours — voyait « Tableau de
     * bord » en sous-titre du panneau : un libellé de module interdit, fuité
     * par le seul endroit qui ne passait pas par `moduleAccessible()`. Et il
     * était FAUX en plus d'être fuité : la page servie à ce rôle n'est pas
     * le tableau de bord.
     */
    public static function libelleRoute(?User $utilisateur, ?string $routeActuelle): string
    {
        if ($routeActuelle === null) {
            return '';
        }

        foreach (MenuLateral::NAVIGATION as $entree) {
            $items = isset($entree['items']) ? $entree['items'] : [$entree];

            foreach ($items as $item) {
                if ($item['route'] === $routeActuelle) {
                    return MenuLateral::moduleAccessible($utilisateur, (string) $item['module'])
                        ? (string) $item['nom']
                        : '';
                }
            }
        }

        return '';
    }
}
