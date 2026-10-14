<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Architecture;

use Illuminate\Support\Facades\Route;
use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Finder\Finder;
use Tests\TestCase;

/**
 * Tout `route('…')` littéral du dépôt désigne une route qui EXISTE.
 *
 * ## Le défaut que cette garde épingle (31/08/2026)
 *
 * `Accueil.php` appelait `route('pwa.stocks')` — la route s'appelle
 * `pwa.stocks.liste`. `route()` LÈVE sur un nom inconnu, et le 500 a atteint
 * le navigateur du Product Owner sur `/pwa`.
 *
 * Aucune garde ne l'avait vu, et la raison est la leçon : l'appel vivait dans
 * une alerte qui ne se REND que s'il existe un article de stock critique. La
 * base de test n'en avait pas — la branche n'était jamais exécutée, et
 * `ChargementDesEcransPwaTest` était vert à côté du défaut. Un contrôle par
 * rendu ne voit que les branches que ses données déclenchent ; un nom de
 * route, lui, se vérifie STATIQUEMENT, sur toutes les branches à la fois.
 *
 * ## Ce qu'elle couvre, et ce qu'elle ne couvre pas
 *
 * Couvre : tout appel `route('nom-literal'…)` dans `app/` et
 * `resources/views/` — y compris les branches conditionnelles, les modales
 * jamais ouvertes en test, les exports.
 *
 * Ne couvre PAS un nom construit (`route('pwa.'.$x)`) : il n'y a rien à lire
 * statiquement. Le dépôt n'en compte aucun à ce jour (mesuré le 31/08/2026),
 * et la règle des clés i18n vaut ici aussi — un nom concaténé est invisible à
 * toute garde, écrire les branches en littéraux.
 *
 * ## Mutation prouvée
 *
 * `route('pwa.stocks.liste')` remis en `route('pwa.stocks')` dans
 * `Accueil.php` → ROUGE, le message citant fichier et ligne. Rejouée le
 * 31/08/2026, code restauré ensuite.
 */
final class RoutesNommeesExistentTest extends TestCase
{
    /**
     * Plancher d'appels réellement relus. Mesuré le 31/08/2026 : 25 noms
     * distincts sur ~60 appels. Sans plancher, un répertoire renommé rendrait
     * le balayage vide, donc vert — le défaut même que ce dépôt pourchasse.
     */
    private const PLANCHER_APPELS = 20;

    #[Test]
    public function tout_appel_route_litteral_designe_une_route_definie(): void
    {
        $finder = (new Finder())
            ->files()
            ->in([app_path(), resource_path('views')])
            ->name('*.php');

        $defauts = [];
        $appels = 0;

        foreach ($finder as $fichier) {
            $source = $fichier->getContents();

            // ⚠ Le motif exclut `->route(` et `::route(` — resserré avant
            // livraison, le 31/08/2026, après 15 faux positifs : dans un
            // FormRequest, `$this->route('fournisseur')` est l'ACCESSEUR DE
            // PARAMÈTRE de la route courante, pas le générateur d'URL — le
            // nom qu'il reçoit est un paramètre (`{fournisseur}`), jamais un
            // nom de route. Un motif large ici aurait produit la garde qui
            // crie à tort, celle qu'on finit par désactiver.
            if (preg_match_all(
                "/(?:^|[^>\\w:\$])route\\(\\s*'([a-z0-9._-]+)'/im",
                $source,
                $captures,
                PREG_OFFSET_CAPTURE,
            ) < 1) {
                continue;
            }

            foreach ($captures[1] as [$nom, $position]) {
                $appels++;

                if (Route::has($nom)) {
                    continue;
                }

                $ligne = substr_count(substr($source, 0, $position), "\n") + 1;
                $defauts[] = sprintf(
                    '%s:%d → route(\'%s\') — aucune route de ce nom.',
                    $fichier->getRelativePathname(),
                    $ligne,
                    $nom,
                );
            }
        }

        $this->assertSame(
            [],
            $defauts,
            "Des appels route() désignent des routes inexistantes — chacun est un 500\n"
            ."qui attend la branche qui le rend :\n  ".implode("\n  ", $defauts),
        );

        $this->assertGreaterThanOrEqual(
            self::PLANCHER_APPELS,
            $appels,
            "Seuls {$appels} appels route() relus, contre ~60 mesurés. Un répertoire "
            .'a bougé : le balayage est devenu creux, donc vert.',
        );
    }
}
