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
 * Livewire. Depuis le 09/11/2026 (« OUI » du PO), un 419 hors Livewire sert la
 * page 419 du projet (statut 419, « Recharger la page » / « Retour à la
 * connexion ») au lieu de la redirection silencieuse vers la connexion ; le
 * JSON et Livewire sont inchangés.
 *
 * Mutation éprouvée le 09/11/2026 : remettre
 * `return redirect()->route('pwa.connexion')->with('session_expiree', true)`
 * dans le rendu de `bootstrap/app.php` fait rougir
 * `un_formulaire_html_au_jeton_perime_rend_la_page_419` et
 * `la_connexion_au_jeton_perime_propose_d_abord_de_revenir_a_la_connexion`
 * — restauré ensuite.
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
    public function un_formulaire_html_au_jeton_perime_rend_la_page_419(): void
    {
        config(['app.debug' => false]);
        Route::middleware('web')->post('/essai-jeton-perime', function () {
            throw new TokenMismatchException('CSRF token mismatch secret-technique /home/user/x.php');
        });

        $reponse = $this->post('/essai-jeton-perime', ['mot_de_passe' => 'Sensible!123'])->assertStatus(419);
        $html = (string) $reponse->getContent();

        $this->assertStringContainsString('<h1>' . e(__('erreurs.419.titre')) . '</h1>', $html);
        $this->assertStringContainsString(e(__('erreurs.actions.recharger')), $html);
        $this->assertStringContainsString(e(__('erreurs.actions.reconnexion')), $html);
        $this->assertStringContainsString(route('pwa.connexion'), $html);
        // Pas de redirection, pas de drapeau : la page s'explique d'elle-même.
        $this->assertFalse($reponse->isRedirect());
        $reponse->assertSessionMissing('session_expiree');
        // Aucun détail interne, aucune saisie renvoyée.
        foreach (['CSRF token mismatch', 'secret-technique', '/home/user', 'Sensible!123', 'Stack trace', 'TokenMismatch'] as $m) {
            $this->assertStringNotContainsString($m, $html);
        }
        // Le bouton principal (premier) est « Recharger la page ».
        $this->assertSame(
            [__('erreurs.actions.recharger'), __('erreurs.actions.reconnexion')],
            $this->boutons($html),
        );
    }

    #[Test]
    public function la_connexion_au_jeton_perime_propose_d_abord_de_revenir_a_la_connexion(): void
    {
        config(['app.debug' => false]);
        Route::middleware('web')->post('/essai-jeton-perime', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $html = (string) $this->post('/essai-jeton-perime', ['login' => 'x', 'mot_de_passe' => 'Sensible!123'], [
            'Referer' => route('pwa.connexion'),
        ])->assertStatus(419)->getContent();

        $this->assertSame(
            [__('erreurs.actions.reconnexion'), __('erreurs.actions.recharger')],
            $this->boutons($html),
            '« Retour à la connexion » doit être le bouton principal.',
        );
        $this->assertStringContainsString('href="' . route('pwa.connexion') . '" class="bouton"', $html);
        $this->assertStringNotContainsString('Sensible!123', $html);

        // Un Referer d'un autre site ne change rien.
        $autre = (string) $this->post('/essai-jeton-perime', [], ['Referer' => 'https://pirate.example.org/pwa/connexion'])
            ->assertStatus(419)->getContent();
        $this->assertSame(
            [__('erreurs.actions.recharger'), __('erreurs.actions.reconnexion')],
            $this->boutons($autre),
        );
        $this->assertStringNotContainsString('pirate.example.org', $autre);
    }

    #[Test]
    public function une_requete_json_au_jeton_perime_reste_du_json(): void
    {
        Route::middleware('web')->post('/essai-jeton-perime-json', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });
        Route::middleware('api')->post('/api/essai-jeton-perime', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $web = $this->postJson('/essai-jeton-perime-json')->assertStatus(419);
        $this->assertStringContainsString('json', (string) $web->headers->get('Content-Type'));
        $this->assertStringNotContainsString('<html', (string) $web->getContent());

        $api = $this->postJson('/api/essai-jeton-perime')->assertStatus(419);
        $this->assertStringNotContainsString('<html', (string) $api->getContent());
    }

    #[Test]
    public function une_requete_livewire_garde_son_419_pour_le_script(): void
    {
        Route::middleware('web')->post('/essai-jeton-perime-livewire', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $reponse = $this->post('/essai-jeton-perime-livewire', [], ['X-Livewire' => '1'])->assertStatus(419);
        $this->assertFalse($reponse->isRedirect());
    }

    /** @return list<string> libellés des boutons de la page d'erreur, dans l'ordre (le premier est le principal) */
    private function boutons(string $html): array
    {
        preg_match_all('#<a href="[^"]+" class="bouton[^"]*">.*?</svg>\s*([^<]+?)\s*</a>#s', $html, $m);

        return array_map(html_entity_decode(...), $m[1]);
    }
}
