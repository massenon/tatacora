<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Concerns;

use Illuminate\Routing\Route as RouteLaravel;
use Illuminate\Support\Facades\Route;

/**
 * Le SOCLE des gardes de la PWA : « quels écrans la PWA sert-elle, par quel
 * composant et avec quelle vue ? »
 *
 * ## Pourquoi ce trait existe plutôt qu'une liste
 *
 * Trois inventaires écrits à la main ont vieilli dans ce dépôt — dont un qui
 * décrivait, numéros de ligne à l'appui, les fichiers d'un répertoire absent.
 * Une liste de pages recopiée dans un test dit l'état du jour où elle a été
 * tapée ; `Route::getRoutes()` dit celui d'aujourd'hui. Toute garde qui
 * s'appuie sur ce trait balaie donc les routes RÉELLES, y compris celles
 * livrées après l'écriture de la garde.
 *
 * ## Il n'y a plus de « page maître » à localiser (PA-183, 10/09/2026)
 *
 * Ce trait s'appelait `LocaliseLeMaitre` : il rattachait chaque écran à une
 * page de `prototype_v2/`, par citation ou par convention de nommage, pour que
 * les gardes comparent la vue à la maquette. Depuis la décision du Product
 * Owner du 10/09/2026, la VUE BLADE est le maître et `prototype_v2/` une
 * ancienne version : ce rattachement n'a plus d'objet, et une garde qui
 * re-ciblerait la comparaison sur la vue la comparerait à elle-même — elle ne
 * prouverait rien. Il ne reste que l'inventaire des écrans réellement servis,
 * sur lequel les gardes posent des INVARIANTS qui ne demandent aucune
 * référence extérieure (un seul `<h1>`, un `<title>` qui nomme le `<h1>`, un
 * menu rendu dans l'ordre de son registre…).
 *
 * @see docs/DIRECTIVE_CONFORMITE_100.md Article 0
 */
trait InventaireDesEcransPwa
{
    /**
     * Les écrans servis par la PWA, dérivés des routes enregistrées.
     *
     * @return list<array{
     *     uri: string,
     *     url: string,
     *     nom: string,
     *     composant: string|null,
     *     fichierComposant: string|null,
     *     vue: string|null,
     *     fichierVue: string|null,
     *     invite: bool
     * }>
     */
    protected function ecransPwa(): array
    {
        $ecrans = [];

        /** @var RouteLaravel $route */
        foreach (Route::getRoutes()->getRoutes() as $route) {
            if (! in_array('GET', $route->methods(), true)) {
                continue;
            }

            $uri = $route->uri();
            if ($uri !== 'pwa' && ! str_starts_with($uri, 'pwa/')) {
                continue;
            }

            // Une route PARAMÉTRÉE (`{vente}`…) n'est pas un ÉCRAN : la
            // demander à cru rend 404 par construction, et elle est couverte
            // par le test de son propre document (le ticket thermique,
            // 01/09/2026 — première occurrence). Le balayage porte sur les
            // pages, pas sur les ressources adressées.
            if (str_contains($uri, '{')) {
                continue;
            }

            $action = $route->getActionName();
            $composant = str_starts_with($action, 'App\\Pwa\\Livewire') ? $action : null;
            $fichierComposant = $composant !== null ? $this->fichierDeClasse($composant) : null;

            $vue = $composant !== null
                ? $this->vueDuComposant($fichierComposant)
                : ($route->defaults['view'] ?? null);

            $ecrans[] = [
                'uri' => $uri,
                'url' => '/'.$uri,
                'nom' => (string) ($route->getName() ?? $uri),
                'composant' => $composant,
                'fichierComposant' => $fichierComposant,
                'vue' => is_string($vue) ? $vue : null,
                'fichierVue' => is_string($vue) ? $this->fichierDeVue($vue) : null,
                // ⚠ `gatherMiddleware()` rend la classe RESOLUE, pas l'alias :
                // chercher « guest » seul rendait `false` sur /pwa/connexion,
                // qui etait alors demande avec une session et repondait 302.
                'invite' => (bool) array_intersect(
                    ['guest', \Illuminate\Auth\Middleware\RedirectIfAuthenticated::class],
                    $route->gatherMiddleware(),
                ),
            ];
        }

        usort($ecrans, static fn (array $a, array $b): int => strcmp($a['uri'], $b['uri']));

        return $ecrans;
    }

    // ------------------------------------------------------------------ outils

    protected function fichierDeClasse(string $classe): ?string
    {
        $relatif = str_replace('\\', DIRECTORY_SEPARATOR, substr($classe, strlen('App\\')));
        $chemin = app_path($relatif.'.php');

        return is_file($chemin) ? $chemin : null;
    }

    protected function fichierDeVue(string $vue): ?string
    {
        $chemin = resource_path('views'.DIRECTORY_SEPARATOR.str_replace('.', DIRECTORY_SEPARATOR, $vue).'.blade.php');

        return is_file($chemin) ? $chemin : null;
    }

    /**
     * La vue Blade que le `render()` du composant retourne. Lue dans le SOURCE
     * du composant : Livewire ne l'expose pas sans instancier le composant, et
     * l'instancier exigerait la session, la base et le RBAC.
     */
    protected function vueDuComposant(?string $fichierComposant): ?string
    {
        if ($fichierComposant === null || ! is_file($fichierComposant)) {
            return null;
        }

        $source = (string) file_get_contents($fichierComposant);

        if (preg_match_all("#view\(\s*'(pwa\.[A-Za-z0-9._-]+)'#", $source, $trouves) >= 1) {
            return $trouves[1][0];
        }

        return null;
    }

    /**
     * Le texte visible d'un fragment HTML, entités décodées et espaces
     * normalisés — la seule forme dans laquelle deux libellés se comparent.
     */
    protected function texteVisible(string $html): string
    {
        $sansBalise = preg_replace('#<[^>]*>#', ' ', $html) ?? '';
        $decode = html_entity_decode($sansBalise, ENT_QUOTES | ENT_HTML5, 'UTF-8');
        $normalise = preg_replace('#\s+#u', ' ', $decode) ?? '';

        return trim($normalise);
    }
}
