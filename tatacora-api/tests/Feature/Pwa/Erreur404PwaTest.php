<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La page 404 (`resources/views/errors/404.blade.php`) — écran d'erreur
 * relevé par l'audit navigateur du Product Owner (01/09/2026) : Laravel
 * servait sa page blanche par défaut, sans les couleurs de la coquille PWA.
 *
 * @see resources/views/errors/404.blade.php
 * @see lang/fr/pwa.php section `erreur_404`
 */
final class Erreur404PwaTest extends TestCase
{
    /**
     * Une route inexistante rend bien un 404, habillé — pas la page blanche
     * de Laravel, et pas un statut différent qui ferait échouer une
     * intégration en silence.
     *
     * Éprouvé par mutation le 02/09/2026 : réduire
     * `resources/views/errors/404.blade.php` à `<h1>404</h1>` fait rougir ce
     * cas sur « Page introuvable » absent — restauré ensuite.
     */
    #[Test]
    public function une_route_inexistante_rend_un_404_aux_couleurs_de_la_coquille(): void
    {
        $html = (string) $this->get('/pwa/une-page-qui-n-existe-pas-du-tout')
            ->assertNotFound()
            ->getContent();

        $this->assertStringContainsString(__('pwa.erreur_404.titre'), $html);
        $this->assertStringContainsString(__('pwa.erreur_404.explication'), $html);
        $this->assertStringContainsString('var(--navy)', $html);
        $this->assertStringContainsString(route('pwa.accueil'), $html);
    }

    /**
     * LÉGÈRE, SANS DÉPENDANCE DISTANTE (exigence explicite du brief) : même
     * garantie que `ConformiteMaquettePwaTest::aucune_page_de_la_pwa_ne_charge_de_ressource_distante()`,
     * rejouée ici parce que cette page est servie AVANT toute authentification
     * — un `assertOk()` ne s'y applique pas, elle exige son propre cas.
     */
    #[Test]
    public function la_page_404_ne_charge_aucune_ressource_distante(): void
    {
        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        $autorises = [$hoteLocal, 'localhost', 'localhost:8000'];

        $html = (string) $this->get('/pwa/une-page-qui-n-existe-pas-du-tout')
            ->assertNotFound()
            ->getContent();

        preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

        foreach (array_unique($hotes[1]) as $hote) {
            $this->assertContains(
                $hote,
                $autorises,
                "La page 404 charge une ressource distante : {$hote}.",
            );
        }
    }
}
