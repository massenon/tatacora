<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Session\TokenMismatchException;
use Illuminate\Support\Facades\Route;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * « This page has expired. Would you like to refresh the page? » ne doit plus
 * jamais s'afficher (PO, 30/10/2026) : le gabarit intercepte le 419 de
 * Livewire, et un 419 hors Livewire renvoie vers la connexion.
 */
final class SessionExpireeTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function les_deux_gabarits_portent_le_gestionnaire_de_419(): void
    {
        // Gabarit invite (connexion) : le script ET le bandeau francais.
        $html = (string) $this->get(route('pwa.connexion'))->assertOk()->getContent();
        $this->assertStringContainsString('pwa-session-expiree', $html);
        $this->assertStringContainsString('interceptRequest', $html);
        $this->assertStringContainsString('preventDefault', $html);
        $this->assertStringContainsString('window.location.reload()', $html);
        $this->assertStringContainsString('Votre session a expiré, reconnectez-vous.', $html);

        // Gabarit authentifie : meme partiel, sans CDN.
        $source = (string) file_get_contents(resource_path('views/layouts/pwa.blade.php'));
        $this->assertStringContainsString("@include('pwa.partials.session-expiree')", $source);
        $partiel = (string) file_get_contents(resource_path('views/pwa/partials/session-expiree.blade.php'));
        $this->assertDoesNotMatchRegularExpression('#src="https?://#', $partiel);
    }

    #[Test]
    public function un_jeton_invalide_sur_une_route_web_redirige_vers_la_connexion(): void
    {
        Route::middleware('web')->post('/essai-jeton-perime', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $this->post('/essai-jeton-perime')
            ->assertRedirect(route('pwa.connexion'))
            ->assertSessionHas('session_expiree', true);

        $this->get(route('pwa.connexion'))
            ->assertOk()
            ->assertDontSee('id="bandeau-session-expiree" role="alert" hidden', false);
    }

    #[Test]
    public function une_requete_livewire_garde_son_419_pour_le_script(): void
    {
        Route::middleware('web')->post('/essai-jeton-perime-livewire', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $this->post('/essai-jeton-perime-livewire', [], ['X-Livewire' => '1'])->assertStatus(419);
    }
}
