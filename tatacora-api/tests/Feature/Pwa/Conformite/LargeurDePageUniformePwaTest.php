<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use PHPUnit\Framework\Attributes\Test;
use Symfony\Component\Finder\Finder;
use Tests\TestCase;

/**
 * Directive du Product Owner du 26/10/2026 : « toutes les écrans du WEB » ont le
 * même conteneur de page. Le premier `<div>` après la balise `<main>` porte
 * EXACTEMENT `max-w-[1440px] mx-auto p-5 lg:p-8` — et non 1100, 1200, 1500 ou
 * 1600 px, ni `p-4 sm:p-5`. Les classes qui suivent (`zone-impression`,
 * `wire:poll…`) sont des ajouts d'écran, pas une autre largeur.
 *
 * Le balayage lit le SOURCE des vues (la classe est une constante de la vue,
 * pas une donnée) ; le poste Flutter le relit dans
 * `test/core/qualite/largeur_page_unique_test.dart`.
 *
 * La feuille de style : la PWA charge le Play CDN de Tailwind (JIT dans le
 * navigateur), qui génère `max-w-[1440px]` et `lg:p-8`
 * (`@media (min-width:1024px){.lg\:p-8{padding:2rem}}`) à partir des classes
 * présentes dans la page — aucune feuille compilée n'est versionnée. Le test
 * prouve donc que le moteur est bien servi, et que la classe est dans la vue.
 */
final class LargeurDePageUniformePwaTest extends TestCase
{
    public const CONTENEUR = 'max-w-[1440px] mx-auto p-5 lg:p-8';

    /**
     * Les vues à `<main>` SANS conteneur de page, chacune avec sa raison.
     * Liste fermée : une vue qui y figure sans plus en avoir besoin échoue.
     *
     * @var array<string, string>
     */
    private const SANS_CONTENEUR = [
        'pwa/pos/comptant.blade.php' => 'caisse plein cadre : `<main>` flex-col sans marge, la salle et le panier occupent toute la page',
        'pwa/pos/heberges.blade.php' => 'caisse plein cadre : `<main>` flex-col sans marge',
        'pwa/etats/studio.blade.php' => 'studio d\'états plein cadre : `<main>` flex-col sans marge',
    ];

    /** Pages sans `<main>` de coquille : connexion, hors connexion, démarrage, ticket. */
    private const SANS_MAIN = [
        'pwa/livewire/connexion.blade.php',
        'pwa/hors-connexion.blade.php',
        'pwa/demarrage.blade.php',
        'pwa/pos/ticket-thermique.blade.php',
    ];

    /** @return array<string, array{0: string, 1: string}> chemin relatif => [classe du premier div, source] */
    private function premiersConteneurs(): array
    {
        $racine = resource_path('views');
        $trouves = [];

        foreach ((new Finder)->files()->in($racine.'/pwa')->name('*.blade.php') as $fichier) {
            $relatif = 'pwa/'.str_replace('\\', '/', $fichier->getRelativePathname());
            $source = $fichier->getContents();
            if (! preg_match('/^[ \t]*<main\b[^>]*>/m', $source, $m, PREG_OFFSET_CAPTURE)) {
                continue;
            }
            $suite = substr($source, $m[0][1] + strlen($m[0][0]));
            $classe = preg_match('/<div\b([^>]*)>/', $suite, $d) ? $d[1] : '';
            preg_match('/class="([^"]*)"/', $classe, $c);
            $trouves[$relatif] = [$c[1] ?? '', $source];
        }

        return $trouves;
    }

    #[Test]
    public function le_premier_div_apres_main_porte_le_conteneur_uniforme(): void
    {
        $vues = $this->premiersConteneurs();
        $this->assertGreaterThanOrEqual(30, count($vues), 'balayage vide : plancher de vues à <main> non atteint');

        $ecarts = [];
        foreach ($vues as $chemin => [$classe]) {
            if (isset(self::SANS_CONTENEUR[$chemin])) {
                continue;
            }
            $attendu = '/^'.preg_quote(self::CONTENEUR, '/').'( [^"]*)?$/';
            if (! preg_match($attendu, $classe)) {
                $ecarts[] = $chemin.' : « '.$classe.' »';
            }
        }

        $this->assertSame([], $ecarts, "Le premier div après <main> doit porter `".self::CONTENEUR."` :\n".implode("\n", $ecarts));
    }

    #[Test]
    public function la_liste_des_exclusions_est_fermee_et_sans_raison_perimee(): void
    {
        $vues = $this->premiersConteneurs();

        foreach (self::SANS_CONTENEUR as $chemin => $raison) {
            $this->assertArrayHasKey($chemin, $vues, "$chemin n'a plus de <main> : retirez-le des exclusions ($raison).");
            $this->assertStringNotContainsString(self::CONTENEUR, explode('>', $vues[$chemin][0].'>')[0] ?? '', "$chemin porte désormais le conteneur : retirez-le des exclusions.");
            $this->assertStringStartsNotWith('max-w-[1440px]', $vues[$chemin][0], "$chemin porte désormais le conteneur : retirez-le des exclusions.");
        }
        foreach (self::SANS_MAIN as $chemin) {
            $this->assertFileExists(resource_path('views/'.$chemin));
            $this->assertArrayNotHasKey($chemin, $vues, "$chemin a désormais un <main> : il doit porter le conteneur.");
        }
    }

    #[Test]
    public function aucune_autre_largeur_de_page_ne_subsiste_dans_les_conteneurs_de_page(): void
    {
        foreach ($this->premiersConteneurs() as $chemin => [$classe]) {
            if (isset(self::SANS_CONTENEUR[$chemin])) {
                continue;
            }
            $this->assertDoesNotMatchRegularExpression('/max-w-\[(?!1440px)\d+px\]/', $classe, $chemin);
            $this->assertStringNotContainsString('sm:p-5', $classe, $chemin);
        }
    }

    #[Test]
    public function preuve_par_mutation_une_autre_largeur_est_denoncee(): void
    {
        $attendu = '/^'.preg_quote(self::CONTENEUR, '/').'( [^"]*)?$/';
        $this->assertSame(1, preg_match($attendu, self::CONTENEUR));
        $this->assertSame(1, preg_match($attendu, self::CONTENEUR.' zone-impression'));
        foreach (['1100', '1500', '1600', '900'] as $autre) {
            $this->assertSame(0, preg_match($attendu, str_replace('1440', $autre, self::CONTENEUR)), $autre);
        }
        $this->assertSame(0, preg_match($attendu, 'max-w-[1440px] mx-auto p-4 sm:p-5 lg:p-8'));
    }

    #[Test]
    public function le_moteur_de_style_qui_genere_la_classe_est_servi_avec_la_pwa(): void
    {
        $tete = file_get_contents(resource_path('views/pwa/partials/tete.blade.php'));
        $this->assertStringContainsString("assets/js/vendor/tailwind-play-cdn.js", $tete);
        $this->assertFileExists(public_path('assets/js/vendor/tailwind-play-cdn.js'));
        $this->assertGreaterThan(100_000, filesize(public_path('assets/js/vendor/tailwind-play-cdn.js')));

        // La classe est bien présente dans une vue : le JIT la génère
        // (`.max-w-\[1440px\]{max-width:1440px}` et le `@media (min-width:1024px)`
        // de `.lg\:p-8{padding:2rem}`).
        $this->assertStringContainsString(self::CONTENEUR, file_get_contents(resource_path('views/pwa/achats/achats.blade.php')));
    }
}
