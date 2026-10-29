<?php

declare(strict_types=1);

namespace App\Pwa\Support;

use App\Models\User;
use Illuminate\Support\Facades\Route;

final class MenuLateral
{
    public const ICONES = [
        'dashboard' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3 3v18h18M18 17V9M13 17V5M8 17v-3"/>',
        'reservation' => '<rect x="3" y="4" width="18" height="18" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M16 2v4M8 2v4M3 10h18"/><path stroke-linecap="round" d="M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01"/>',
        'hebergement' => '<path stroke-linecap="round" stroke-linejoin="round" d="M2 4v16M2 8h18a2 2 0 012 2v10M2 17h20M6 8v-1a2 2 0 012-2h2a2 2 0 012 2v1"/>',
        'restaurant' => '<path stroke-linecap="round" stroke-linejoin="round" d="M3 2v7c0 1.1.9 2 2 2h1a2 2 0 002-2V2M7 2v20M17 2a5 5 0 00-5 5v6h5m0-11v20"/>',
        'bar' => '<path stroke-linecap="round" stroke-linejoin="round" d="M8 21h8M12 15v6M19 3H5l7 9 7-9z"/>',
        'tourisme' => '<circle cx="12" cy="12" r="10"/><path stroke-linecap="round" stroke-linejoin="round" d="M16.24 7.76l-2.12 6.36-6.36 2.12 2.12-6.36 6.36-2.12z"/>',
        'vehicules' => '<path stroke-linecap="round" stroke-linejoin="round" d="M14 16H9m10 0h3v-3.15a1 1 0 00-.84-.99L16 11l-2.7-3.6a1 1 0 00-.8-.4H5.24a2 2 0 00-1.8 1.1l-1.14 2.28A2 2 0 002 11v4a1 1 0 001 1h1"/><circle cx="6.5" cy="16.5" r="2.5"/><circle cx="16.5" cy="16.5" r="2.5"/>',
        'crm' => '<path stroke-linecap="round" stroke-linejoin="round" d="M17 21v-2a4 4 0 00-4-4H5a4 4 0 00-4 4v2"/><circle cx="9" cy="7" r="4"/><path stroke-linecap="round" stroke-linejoin="round" d="M23 21v-2a4 4 0 00-3-3.87M16 3.13a4 4 0 010 7.75"/>',
        'facturation' => '<path stroke-linecap="round" stroke-linejoin="round" d="M6 2h9l5 5v13a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/><path stroke-linecap="round" d="M9 13h6M9 17h6M9 9h1"/>',
        'achats' => '<circle cx="9" cy="21" r="1"/><circle cx="20" cy="21" r="1"/><path stroke-linecap="round" stroke-linejoin="round" d="M1 1h4l2.68 13.39a2 2 0 002 1.61h9.72a2 2 0 002-1.61L23 6H6"/>',
        'stocks' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 8l-9-5-9 5 9 5 9-5zM3 8v8l9 5 9-5V8M12 13v8"/>',
        'comptabilite' => '<rect x="4" y="2" width="16" height="20" rx="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M8 6h8M8 10h.01M12 10h.01M16 10h.01M8 14h.01M12 14h.01M16 14h.01M8 18h.01M12 18h.01M16 18h.01"/>',
        'rh' => '<rect x="2" y="4" width="20" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path stroke-linecap="round" stroke-linejoin="round" d="M15 8h4M15 12h4M6 16h6"/>',
        'notifications' => '<path stroke-linecap="round" stroke-linejoin="round" d="M18 8a6 6 0 00-12 0c0 7-3 9-3 9h18s-3-2-3-9"/><path stroke-linecap="round" stroke-linejoin="round" d="M13.73 21a2 2 0 01-3.46 0"/>',
        'etats' => '<path stroke-linecap="round" stroke-linejoin="round" d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z"/><path stroke-linecap="round" stroke-linejoin="round" d="M14 2v6h6M9 13h6M9 17h6M9 9h1"/>',
        'roles' => '<path stroke-linecap="round" stroke-linejoin="round" d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
        'import' => '<path stroke-linecap="round" stroke-linejoin="round" d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>',
        'parametres' => '<circle cx="12" cy="12" r="3"/><path stroke-linecap="round" stroke-linejoin="round" d="M19.4 15a1.65 1.65 0 00.33 1.82l.06.06a2 2 0 11-2.83 2.83l-.06-.06a1.65 1.65 0 00-1.82-.33 1.65 1.65 0 00-1 1.51V21a2 2 0 01-4 0v-.09A1.65 1.65 0 009 19.4a1.65 1.65 0 00-1.82.33l-.06.06a2 2 0 11-2.83-2.83l.06-.06A1.65 1.65 0 004.6 15a1.65 1.65 0 00-1.51-1H3a2 2 0 010-4h.09A1.65 1.65 0 004.6 9a1.65 1.65 0 00-.33-1.82l-.06-.06a2 2 0 112.83-2.83l.06.06A1.65 1.65 0 009 4.6a1.65 1.65 0 001-1.51V3a2 2 0 014 0v.09a1.65 1.65 0 001 1.51 1.65 1.65 0 001.82-.33l.06-.06a2 2 0 112.83 2.83l-.06.06A1.65 1.65 0 0019.4 9c.14.31.22.65.22 1V10c.66 0 1 .34 1 1v2c0 .66-.34 1-1 1z"/>',
    ];

    /**
     * Routes MASQUEES de la barre laterale pour un role donne — directive du
     * Product Owner du 03/09/2026 : le gerant ne doit pas VOIR Tourisme,
     * Vehicules, Comptabilite, Personnel & Paie, le groupe Pilotage &
     * administration ni Clients & facturation.
     *
     * ⚠ C'est un masquage d'INTERFACE (niveau 1 du RBAC), pas un retrait de
     * droits — la matrice du gerant reste inchangee, DELIBEREMENT : M10
     * porte a la fois « Comptabilite » (a masquer) et « Depense courante »
     * (que le gerant garde, c'est son geste quotidien) — passer par la
     * matrice masquerait les deux ou aucun. Retirer un DROIT passe par
     * l'ecran Roles & Permissions, jamais par ce registre. Les routes
     * restent servies a qui les connait, sous leurs gardes normales.
     *
     * @var array<string, list<string>>
     */
    public const ROUTES_MASQUEES_PAR_ROLE = [
        'gerant' => [
            'pwa.tourisme',
            'pwa.vehicules',
            'pwa.comptabilite.hub',
            'pwa.paie',
            'pwa.etats.studio',
            'pwa.notifications',
            'pwa.import-export',
            'pwa.roles-permissions',
            'pwa.comptes-utilisateurs',
            'pwa.parametres',
            'pwa.synchronisation-postes',
            'pwa.clients',
            'pwa.facturation',
        ],
    ];

    private static function routeMasqueePourRole(?\App\Models\User $utilisateur, string $route): bool
    {
        $role = $utilisateur?->role?->libelle;

        return $role !== null
            && in_array($route, self::ROUTES_MASQUEES_PAR_ROLE[$role] ?? [], true);
    }

    public const NAVIGATION = [
        ['epingle' => true, 'nom' => 'Tableau de bord', 'icone' => 'dashboard', 'module' => 'M11', 'badge' => 'Tous modules', 'route' => 'pwa.accueil'],
        ['epingle' => true, 'nom' => 'Point de vente', 'icone' => 'bar', 'module' => 'M5', 'badge' => 'Comptant', 'route' => 'pwa.pos.comptant'],
        ['epingle' => true, 'nom' => 'POS clients hébergés', 'icone' => 'hebergement', 'module' => 'M1', 'badge' => 'Panier ouvert', 'route' => 'pwa.pos.heberges'],
        ['epingle' => true, 'nom' => 'Historique des ventes', 'icone' => 'facturation', 'module' => 'M5', 'badge' => 'Journal', 'route' => 'pwa.historique-ventes'],
        ['epingle' => true, 'nom' => 'Dépense courante', 'icone' => 'comptabilite', 'module' => 'M10', 'badge' => 'Trésorerie', 'route' => 'pwa.depenses'],

        ['groupe' => 'Réservations & séjours', 'items' => [
            ['nom' => 'Réservations', 'icone' => 'reservation', 'module' => 'M1', 'route' => 'pwa.reservations'],
            ['nom' => 'Hébergement', 'icone' => 'hebergement', 'module' => 'M1', 'route' => 'pwa.hebergement'],
        ]],
        ['groupe' => 'Clients & facturation', 'items' => [
            ['nom' => 'Clients & Créances', 'icone' => 'crm', 'module' => 'M3', 'route' => 'pwa.clients'],
            ['nom' => 'Facturation', 'icone' => 'facturation', 'module' => 'M2', 'badge' => 'MECeF', 'route' => 'pwa.facturation'],
        ]],
        ['groupe' => 'Stocks & achats', 'items' => [
            ['nom' => 'Stocks', 'icone' => 'stocks', 'module' => 'M6', 'route' => 'pwa.stocks.liste'],
            ['nom' => 'Inventaires & Fiches', 'icone' => 'stocks', 'module' => 'M6', 'route' => 'pwa.stocks.inventaires'],
            ['nom' => 'Approvisionnement', 'icone' => 'achats', 'module' => 'M7', 'route' => 'pwa.achats.approvisionnement'],
            ['nom' => 'Fournisseurs', 'icone' => 'achats', 'module' => 'M7', 'route' => 'pwa.achats.liste'],
        ]],
        ['groupe' => 'Restauration & bar', 'items' => [
            ['nom' => 'Restaurant', 'icone' => 'restaurant', 'module' => 'M4', 'route' => 'pwa.restaurant.carte'],
            ['nom' => 'Bar', 'icone' => 'bar', 'module' => 'M5', 'badge' => 'Stock', 'route' => 'pwa.bar.carte'],
        ]],
        ['groupe' => 'Tourisme & véhicules', 'items' => [
            // ⚠ « Tourisme », jamais « Tourisme et Réservations » (31/08/2026) :
            // le maître écrit `nom: 'Tourisme'` (`shell.js` l.53). Le libellé
            // rallongé était une reformulation — l'interdit n° 05 de l'Article 1.
            // Le titre H1 de la PAGE, lui, est un autre libellé et reste celui
            // de `m9-tourisme.html` : une entrée de menu et un en-tête d'écran
            // ne sont pas la même chaîne.
            ['nom' => 'Tourisme', 'icone' => 'tourisme', 'module' => 'M9', 'route' => 'pwa.tourisme'],
            ['nom' => 'Véhicules & Locations', 'icone' => 'vehicules', 'module' => 'M8', 'route' => 'pwa.vehicules'],
        ]],
        ['groupe' => 'Finance', 'items' => [
            ['nom' => 'Comptabilité', 'icone' => 'comptabilite', 'module' => 'M10', 'badge' => 'SYSCOHADA', 'route' => 'pwa.comptabilite.hub'],
        ]],
        ['groupe' => 'Ressources humaines', 'items' => [
            ['nom' => 'Personnel & Paie', 'icone' => 'rh', 'module' => 'M13', 'route' => 'pwa.paie'],
            ['nom' => 'Congés & Plannings', 'icone' => 'rh', 'module' => 'M13', 'route' => 'pwa.conges-plannings'],
        ]],
        ['groupe' => 'Pilotage & administration', 'items' => [
            ['nom' => 'États & Rapports', 'icone' => 'etats', 'module' => 'M14', 'route' => 'pwa.etats.studio'],
            ['nom' => 'Notifications', 'icone' => 'notifications', 'module' => 'M12', 'route' => 'pwa.notifications'],
            // ⚠ « Journal Audit » A ÉTÉ RETIRÉ DE LA BARRE LATÉRALE (31/08/2026).
            //
            // Le maître n'a PAS cette entrée : `shell.js` enchaîne
            // « Notifications », « Import & Export », « Rôles & Permissions »,
            // « Paramètres ». Une entrée ajoutée au menu sans que la maquette
            // bouge est une divergence, et celle-ci décalait l'ordre de tout
            // ce qui la suivait.
            //
            // L'écran reste ATTEIGNABLE, et par les deux chemins du maître :
            // le bouton « Journal d'Audit » de la barre supérieure
            // (`shell.js` l.124) et le pied du panneau de notifications
            // (l.144). Sa garde de droit vit dans
            // `liensChassis()['journal_audit']`, qui déclare son module M14 —
            // retirer l'entrée du menu ne retire donc aucun contrôle.
            ['nom' => 'Import & Export', 'icone' => 'import', 'module' => 'PARAM', 'route' => 'pwa.import-export'],
            ['nom' => 'Rôles & Permissions', 'icone' => 'roles', 'module' => 'ROLES', 'route' => 'pwa.roles-permissions'],
            // 29/10/2026 (PO, option A du « mot de passe perdu ») : la liste des comptes et
            // « Réinitialiser le mot de passe ». Même entrée, même icône (les
            // personnes) que sur le poste Windows.
            ['nom' => 'Comptes utilisateurs', 'icone' => 'crm', 'module' => 'ROLES', 'route' => 'pwa.comptes-utilisateurs'],
            ['nom' => 'Paramètres', 'icone' => 'parametres', 'module' => 'PARAM', 'route' => 'pwa.parametres'],
            // 21/10/2026 (demande du PO) : « Postes & Appairage » a son entrée de menu,
            // en plus de celle du menu de compte (qui reste, ouverte à tout
            // compte). L'entrée de menu suit le droit sur Paramètres ; la route
            // elle-même n'exige aucun module.
            ['nom' => 'Synchronisation', 'icone' => 'import', 'module' => 'PARAM', 'route' => 'pwa.synchronisation-postes'],
        ]],
    ];

    /**
     * @return list<array{epingle: bool, groupe: string|null, items: list<array<string, mixed>>}>|list<mixed>
     */
    public static function pour(?User $utilisateur): array
    {
        $sections = [];
        foreach (self::NAVIGATION as $entree) {
            $brut = isset($entree['items']) ? $entree['items'] : [$entree];
            $items = [];

            foreach ($brut as $item) {
                // Niveau 1 du RBAC : le MASQUAGE D'INTERFACE.
                //
                // ## Ce qui manquait, et pourquoi ce n'est pas cosmetique
                //
                // Cette methode construisait la barre entiere pour tout le
                // monde. Un `barman` (`M10 = '-'`) voyait « Comptabilité »
                // avec son badge « SYSCOHADA », « Personnel & Paie »,
                // « Rôles & Permissions »… Cliquer renvoyait bien un 403 —
                // le middleware `module:` tenait — mais le menu lui-meme
                // enumerait la structure de l'ERP a qui n'y a pas droit.
                //
                // `02_SOFTWARE_ARCHITECTURE.md` impose un RBAC a TROIS
                // niveaux, « jamais un seul » : masquage d'interface,
                // middleware + Policy, filtrage en base. Le premier etait
                // absent de la PWA. Un 403 au clic est le deuxieme rempart,
                // pas le premier — et une entree qui mene systematiquement a
                // un refus est, du point de vue de l'utilisateur, une entree
                // inerte, ce que l'Article 3.3 refuse par ailleurs.
                //
                // ⚠ On masque sur `'-'` seulement. Un niveau `L` garde son
                // entree : il a le droit de consulter, et c'est precisement
                // ce que la route `module:M#,L` autorise.
                if (! self::moduleAccessible($utilisateur, $item['module'])) {
                    continue;
                }

                // Masquage PAR ROLE, en plus du masquage par module — voir le
                // registre ROUTES_MASQUEES_PAR_ROLE et sa raison datee.
                if (self::routeMasqueePourRole($utilisateur, $item['route'])) {
                    continue;
                }

                $route = $item['route'];
                $url = Route::has($route) ? route($route) : url('/pwa/' . $route);

                $items[] = [
                    'nom' => $item['nom'],
                    // Aucun repli sur une icône par défaut : une clé absente
                    // doit lever, pas dessiner autre chose. Le repli qui
                    // vivait ici avait un jumeau dans `entree-menu.blade.php`,
                    // et celui-là s'appliquait à TOUTES les entrées (31/08/2026).
                    'icone' => self::ICONES[$item['icone']],
                    'module' => $item['module'],
                    'badge' => $item['badge'] ?? null,
                    'route' => $route,
                    'url' => $url,
                ];
            }

            // Un groupe dont tous les items sont masques ne rend pas son
            // intitule : sans cela, « Finance » ou « Ressources humaines »
            // resterait affiche au-dessus du vide, ce qui revient a dire au
            // lecteur qu'il existe la des ecrans qu'on lui cache.
            if ($items === []) {
                continue;
            }

            $sections[] = [
                'groupe' => $entree['groupe'] ?? null,
                'epingle' => (bool) ($entree['epingle'] ?? false),
                'items' => $items,
            ];
        }

        return $sections;
    }

    /**
     * Les entrees du MENU DE COMPTE, filtrees par droit — comme la barre.
     *
     * ## Le defaut corrige le 31/08/2026
     *
     * Cette methode recevait l'utilisateur et ne s'en servait pas : elle
     * rendait les six liens a tout le monde, `raison` vide. Un `guide`
     * (`PARAM = '-'`, `M14 = '-'`) obtenait donc « Parametres », « Journal
     * d'audit » et « Import & Export » dans son menu de compte — cliquer
     * menait a un 403.
     *
     * C'etait la TROISIEME fuite de la meme famille dans la meme vague :
     * `pour()` ne filtrait pas la barre laterale, la barre superieure et
     * l'acces rapide rendaient un raccourci « Point de vente » sans garde, et
     * celle-ci. Le masquage d'interface — niveau 1 des trois RBAC exiges par
     * `02_SOFTWARE_ARCHITECTURE.md` — etait absent de toute la coquille, et
     * chaque endroit a ete trouve separement.
     *
     * ## Une seule regle, appelee trois fois
     *
     * D'ou `moduleAccessible()`, partagee avec `pour()`. Deux filtres RBAC
     * ecrits cote a cote finissent par diverger, et c'est celui qu'on oublie
     * de mettre a jour qui laisse passer.
     *
     * ## Un lien refuse porte sa RAISON, il ne disparait pas
     *
     * Contrairement a la barre laterale, l'entree reste presente avec
     * `url = null` : le menu de compte est court et stable, en retirer des
     * lignes selon le role rendrait sa lecture instable d'un poste a
     * l'autre. La vue rend la raison plutot que le lien — ce qui n'est pas
     * une entree inerte au sens de l'Article 3.3, puisqu'elle DIT pourquoi
     * elle ne mene nulle part.
     *
     * @return array<string, array{url: string|null, raison: string}>
     */
    /**
     * Le module qui commande une route de la coquille — DÉRIVÉ de
     * `NAVIGATION`, jamais redéclaré.
     *
     * ## Pourquoi cette méthode existe (31/08/2026)
     *
     * `pour()` filtre la barre latérale. Elle ne filtrait rien d'autre : la
     * barre supérieure rendait le raccourci doré « Point de vente » et le
     * panneau d'accès rapide six raccourcis de plus, **sans aucune garde de
     * droit**. Un `guide` (`M5 = '-'`) voyait le bouton, cliquait, et tombait
     * sur un 403 — le premier des trois niveaux de RBAC exigés par
     * `02_SOFTWARE_ARCHITECTURE.md` manquait sur ces chemins-là.
     *
     * ⚠ **La correction ne devait surtout pas être un second filtre.** Deux
     * règles RBAC finissent par diverger, et c'est celle qu'on oublie de
     * mettre à jour qui laisse passer. Le module d'une route est donc LU dans
     * `NAVIGATION`, la table que `pour()` utilise déjà : ajouter une entrée au
     * menu suffit à couvrir ses raccourcis, et retirer un raccourci ne peut
     * pas oublier son droit.
     *
     * Une route absente de `NAVIGATION` lève, au lieu de rendre `false` : un
     * raccourci silencieusement masqué pour tout le monde serait exactement la
     * forme PA-59/60/61 de ce filtre — une garde qui « protège » en faisant
     * disparaître la fonction sans que personne ne le sache.
     *
     * @throws \InvalidArgumentException si la route n'est pas au registre
     */
    /**
     * L'entrée de menu à surligner pour la route servie — exacte d'abord,
     * FAMILLE ensuite (audit du 01/09/2026 : naviguer d'un onglet-route à
     * l'autre — Journal M10, Plats M4, Bibliothèque M14 — éteignait la
     * surbrillance de la page active dans la barre latérale).
     *
     * La famille est `pwa.<segment>` (les deux premiers segments). Le repli ne
     * joue que si (1) AUCUNE entrée du menu ne porte exactement la route
     * servie — sinon deux entrées s'allumeraient — et (2) UNE SEULE entrée
     * partage la famille — sinon le choix serait arbitraire (les deux POS
     * partagent `pwa.pos`, aucun ne doit s'allumer pour le ticket thermique).
     */
    public static function estActif(string $routeItem, string $routeCourante): bool
    {
        if ($routeItem === $routeCourante) {
            return true;
        }

        $routesDuMenu = self::routesDuMenu();

        if (in_array($routeCourante, $routesDuMenu, true)) {
            return false; // une entrée exacte existe, elle seule s'allume.
        }

        $famille = static fn (string $r): string => implode('.', array_slice(explode('.', $r), 0, 2));

        if ($famille($routeItem) !== $famille($routeCourante)) {
            return false;
        }

        $entreesDeLaFamille = array_filter(
            $routesDuMenu,
            static fn (string $r): bool => $famille($r) === $famille($routeCourante),
        );

        return count($entreesDeLaFamille) === 1;
    }

    /**
     * Toutes les routes portées par NAVIGATION — dérivées, jamais recopiées.
     *
     * @return list<string>
     */
    public static function routesDuMenu(): array
    {
        static $routes = null;

        if ($routes !== null) {
            return $routes;
        }

        $routes = [];
        foreach (self::NAVIGATION as $section) {
            // Deux formes au registre : l'entrée épinglée (une route à la
            // racine) et le groupe (`items`). Toute entrée porte sa route.
            foreach (array_key_exists('items', $section) ? $section['items'] : [$section] as $item) {
                $routes[] = $item['route'];
            }
        }

        return $routes;
    }

    public static function moduleDeRoute(string $route): string
    {
        // Une entree du registre est soit un GROUPE (qui porte `items`), soit
        // une entree epinglee qui EST son propre item. On aplatit d'abord, en
        // passant par `array_merge` : l'analyse statique deduit la forme exacte
        // de la constante, et un `$item['route'] ?? null` ecrit en ligne lui
        // fait signaler un `??` « toujours defini » sur la branche epinglee.
        $items = [];

        foreach (self::NAVIGATION as $entree) {
            $items = array_merge($items, isset($entree['items']) ? $entree['items'] : [$entree]);
        }

        // Aucun `?? null` : APRES l'aplatissement, toute entree du registre
        // porte `route` et `module` — c'est ce que `NAVIGATION` garantit, et
        // l'analyse statique le sait. Un repli defensif ici serait du code
        // mort qui masquerait une entree mal formee au lieu de la signaler.
        foreach ($items as $item) {
            if ($item['route'] === $route) {
                return (string) $item['module'];
            }
        }

        throw new \InvalidArgumentException(
            "La route « {$route} » n'est declaree dans aucune entree de MenuLateral::NAVIGATION : "
            ."impossible de savoir quel module commande son acces. L'y ajouter, ou retirer le "
            .'raccourci qui la vise — un raccourci dont le droit ne se derive de rien est un '
            .'raccourci sans garde.',
        );
    }

    /**
     * L'utilisateur a-t-il le droit de VOIR un raccourci vers cette route ?
     *
     * Même seuil que `pour()` : on masque sur `'-'` seulement. Un niveau `L`
     * garde son raccourci — il a le droit de consulter, et c'est ce que la
     * route `module:M#,L` autorise.
     */
    public static function peutVoirRoute(?User $utilisateur, string $route): bool
    {
        return self::moduleAccessible($utilisateur, self::moduleDeRoute($route));
    }

    /**
     * @return array<string, array{url: string|null, raison: string}>
     */
    public static function liensChassis(?User $utilisateur): array
    {
        // Le module exige par chaque entree — le meme que le middleware
        // `module:` de sa route. `null` : aucun droit particulier, tout
        // compte authentifie y accede (son profil, l'aide, le contact).
        $exigences = [
            'journal_audit' => ['pwa.journal-audit', 'M14'],
            // Décision PO du 18/10/2026 : tout compte qui enregistre au
            // serveur peut faire passer les postes tout de suite.
            'synchronisation_postes' => ['pwa.synchronisation-postes', null],
            'mon_profil' => ['pwa.mon-profil', null],
            'parametres_compte' => ['pwa.parametres', 'PARAM'],
            'import_export' => ['pwa.import-export', 'PARAM'],
            'aide_a_propos' => ['pwa.aide-a-propos', null],
            'contact_editeur' => ['pwa.contact-editeur', null],
        ];

        $liens = [];

        foreach ($exigences as $cle => [$route, $module]) {
            if ($module !== null && ! self::moduleAccessible($utilisateur, $module)) {
                $liens[$cle] = ['url' => null, 'raison' => 'pwa.coquille.sans_droit'];

                continue;
            }

            $liens[$cle] = [
                'url' => Route::has($route) ? route($route) : url('/pwa/'.str_replace('pwa.', '', $route)),
                'raison' => '',
            ];
        }

        return $liens;
    }

    /**
     * La regle de masquage d'interface, ecrite UNE fois.
     *
     * On masque sur `'-'` seulement : un niveau `L` garde son entree, il a le
     * droit de consulter et c'est exactement ce que `module:M#,L` autorise.
     *
     * Publique depuis le 01/09/2026 : le panneau « Accès rapides »
     * (`pwa.partials.acces-rapide`) transcrit `AccesRapide.autorise()` du
     * maître (`acces-rapide.js` l.187-193), qui filtre par CODE MODULE brut —
     * certaines entrées contextuelles n'ont pas de route déclarée dans
     * `NAVIGATION` (elles ouvrent une modale sur place, comme
     * `historique-reservations`). `peutVoirRoute()` exige une route au
     * registre et lèverait sur ces entrées-là ; le panneau a donc besoin de
     * la règle nue, jamais d'une seconde règle réécrite à côté.
     */
    public static function moduleAccessible(?User $utilisateur, string $module): bool
    {
        return $utilisateur !== null && $utilisateur->niveauSurModule($module) !== '-';
    }

    public static function initiales(?User $utilisateur): string
    {
        $nom = $utilisateur->login ?? 'OP';
        return strtoupper(substr($nom, 0, 2));
    }
}
