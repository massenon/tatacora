<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Session\TokenMismatchException;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Lang;
use Illuminate\Support\Facades\Route;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * TOUTES les pages d'erreur (`resources/views/errors/`) : demande du PO
 * « il faut créer TOUTES les pages d'erreur, design web premium » — la 404
 * seule ne suffisait pas.
 *
 * ## Ce que ce fichier verrouille
 *
 *  - un cas par code : statut HTTP, titre, code affiché, au moins une action,
 *    rendu invité ET connecté ;
 *  - AUCUNE FUITE : ni trace, ni chemin du serveur, ni requête SQL, ni nom de
 *    table, ni variable d'environnement — même quand l'exception porte un
 *    message qui en contient ;
 *  - les exceptions courantes (419, 429 + `Retry-After`, 403, 404) ;
 *  - le JSON de l'API est INCHANGÉ ;
 *  - APP_DEBUG=true garde la page de débogage native de Laravel.
 *
 * Mutations éprouvées le 09/11/2026 (voir aussi `ErreursPwaVuesTest`) :
 *  - remplacer `{{ $titre }}` du gabarit par du texte en dur fait rougir
 *    `chaque_code_rend_son_statut_son_titre_et_une_action` ;
 *  - faire afficher `$exception->getMessage()` dans le gabarit fait rougir
 *    `une_exception_serveur_ne_fuit_ni_trace_ni_chemin_ni_sql` ;
 *  — restaurés ensuite.
 *
 * @see resources/views/errors/layout.blade.php
 * @see lang/fr/erreurs.php
 */
final class ErreursPwaTest extends TestCase
{
    use RefreshDatabase;

    /** Marqueurs qui ne doivent JAMAIS apparaître dans une page d'erreur servie. */
    private const FUITES = [
        'Stack trace', '#0 ', '/home/', 'vendor/laravel', 'vendor\\laravel', 'SQLSTATE',
        'select *', 'Illuminate\\', 'App\\', 'APP_KEY', 'DB_PASSWORD', '.env', 'Whoops',
        'secret-technique', 'ErreurInterne', 'base table', 'tatacora_',
    ];

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
        config(['app.debug' => false]);

        Route::middleware('web')->any('/essai-erreur/{code}', function (string $code) {
            abort((int) $code, 'secret-technique /home/user/app.php SQLSTATE select * from users');
        });
    }

    /** @return array<string, array{int}> */
    public static function codes(): array
    {
        $codes = [];
        foreach ([400, 401, 402, 403, 404, 405, 408, 409, 410, 413, 419, 422, 429, 500, 502, 503, 504, 418, 451, 507] as $code) {
            $codes[(string) $code] = [$code];
        }

        return $codes;
    }

    #[Test]
    #[DataProvider('codes')]
    public function chaque_code_rend_son_statut_son_titre_et_une_action(int $code): void
    {
        $cle = Lang::has("erreurs.{$code}") ? (string) $code : ($code >= 500 ? 'generique_5xx' : 'generique_4xx');

        foreach (['invite', 'connecte'] as $profil) {
            if ($profil === 'connecte') {
                $this->actingAs($this->creerUtilisateur());
            }

            $reponse = $this->get("/essai-erreur/{$code}", $this->entetes())->assertStatus($code);
            $html = (string) $reponse->getContent();

            $this->assertStringContainsString('<h1>' . e(__("erreurs.{$cle}.titre")) . '</h1>', $html, "{$code} {$profil} : titre");
            $this->assertStringContainsString('>' . $code . '</p>', $html, "{$code} {$profil} : code affiché");
            $this->assertStringContainsString(e(__("erreurs.{$cle}.message")), $html);
            $this->assertStringContainsString(e(__('erreurs.que_faire')), $html);
            $this->assertMatchesRegularExpression('#<a href="[^"]+" class="bouton#', $html, "{$code} {$profil} : aucune action");
            $this->assertLessThanOrEqual(2, substr_count($html, 'class="bouton'), 'Au plus deux actions.');
            $this->assertStringContainsString('<html lang="fr">', $html);
            $this->assertStringContainsString('<main', $html);
            $this->assertSame(1, substr_count($html, '<h1>'));
            $this->assertStringNotContainsString('<script', $html, 'Aucun script nécessaire.');
            $this->assertAucuneFuite($html, "{$code} {$profil}");
            $this->assertAucuneRessourceDistante($html);
        }
    }

    #[Test]
    public function les_actions_s_adaptent_a_l_invite_et_au_connecte(): void
    {
        $invite = (string) $this->get('/essai-erreur/403')->getContent();
        $this->assertStringContainsString(e(__('erreurs.actions.connexion')), $invite);
        $this->assertStringContainsString(route('pwa.connexion'), $invite);
        $this->assertStringContainsString(e(__('erreurs.actions.accueil_invite')), $invite);

        $this->actingAs($this->creerUtilisateur());
        $connecte = (string) $this->get('/essai-erreur/403')->getContent();
        $this->assertStringNotContainsString(e(__('erreurs.actions.connexion')), $connecte);
        $this->assertStringContainsString(e(__('erreurs.actions.accueil_connecte')), $connecte);
        $this->assertStringContainsString(route('pwa.accueil'), $connecte);
    }

    #[Test]
    public function la_page_de_session_expiree_propose_de_recharger_et_de_se_reconnecter(): void
    {
        $html = (string) $this->get('/essai-erreur/419', $this->entetes())->assertStatus(419)->getContent();

        $this->assertStringContainsString(e(__('erreurs.419.titre')), $html);
        $this->assertStringContainsString(e(__('erreurs.actions.recharger')), $html);
        $this->assertStringContainsString(e(__('erreurs.actions.reconnexion')), $html);
        $this->assertStringContainsString(route('pwa.connexion'), $html);
    }

    #[Test]
    public function le_lien_recharger_ne_reprend_jamais_une_adresse_externe(): void
    {
        $html = (string) $this->get('/essai-erreur/419', ['Referer' => 'https://pirate.example.org/piege', ...$this->entetes()])->getContent();

        $this->assertStringNotContainsString('pirate.example.org', $html);
    }

    #[Test]
    public function le_jeton_perime_hors_redirection_rend_la_page_419(): void
    {
        Route::middleware('web')->get('/essai-jeton', function () {
            throw new TokenMismatchException('CSRF token mismatch.');
        });

        $html = (string) $this->get('/essai-jeton', $this->entetes())->assertStatus(419)->getContent();
        $this->assertStringContainsString(e(__('erreurs.419.titre')), $html);
        $this->assertStringNotContainsString('CSRF token mismatch', $html);
    }

    #[Test]
    public function un_trop_grand_nombre_de_requetes_annonce_le_delai_de_retry_after(): void
    {
        Route::middleware('web')->get('/essai-429', function () {
            abort(429, 'Too Many Attempts.', ['Retry-After' => 42]);
        });

        $reponse = $this->get('/essai-429')->assertStatus(429)->assertHeader('Retry-After', '42');
        $html = (string) $reponse->getContent();

        $this->assertStringContainsString(e(__('erreurs.delai', ['secondes' => 42])), $html);
        $this->assertStringNotContainsString('Too Many Attempts', $html);

        // Sans en-tête : pas de phrase de délai.
        $sans = (string) $this->get('/essai-erreur/429')->getContent();
        $this->assertStringNotContainsString(e(__('erreurs.delai', ['secondes' => 0])), $sans);
        $this->assertStringNotContainsString('seconde(s)', $sans);
    }

    #[Test]
    public function le_limiteur_de_debit_de_laravel_rend_la_page_429_avec_son_delai(): void
    {
        Route::middleware(['web', 'throttle:1,1'])->get('/essai-limite', fn () => 'ok');

        $this->get('/essai-limite')->assertOk();
        $html = (string) $this->get('/essai-limite')->assertStatus(429)->assertHeader('Retry-After')->getContent();

        $this->assertStringContainsString(e(__('erreurs.429.titre')), $html);
        $this->assertStringContainsString('seconde(s)', e(__('erreurs.delai')));
        $this->assertMatchesRegularExpression('#dans \d+ seconde#', $html);
    }

    #[Test]
    public function les_exceptions_courantes_donnent_le_bon_code_sans_detail(): void
    {
        Route::middleware('web')->get('/essai-autorisation', function () {
            throw new AuthorizationException('secret-technique : policy App\\Policies\\X');
        });
        Route::middleware('web')->get('/essai-modele', function () {
            throw (new ModelNotFoundException())->setModel(User::class, [1]);
        });

        $html403 = (string) $this->get('/essai-autorisation')->assertForbidden()->getContent();
        $this->assertStringContainsString(e(__('erreurs.403.titre')), $html403);
        $this->assertAucuneFuite($html403, 'AuthorizationException');

        $html404 = (string) $this->get('/essai-modele')->assertNotFound()->getContent();
        $this->assertStringContainsString(e(__('erreurs.404.titre')), $html404);
        $this->assertAucuneFuite($html404, 'ModelNotFoundException');
    }

    #[Test]
    public function une_exception_serveur_ne_fuit_ni_trace_ni_chemin_ni_sql(): void
    {
        Route::middleware('web')->get('/essai-500', function () {
            throw new \RuntimeException(
                "SQLSTATE[42S02]: Base table or view not found: 1146 Table 'tatacora_test.users' doesn't exist "
                . "(select * from `users` where `login` = secret-technique) in /home/user/app/ErreurInterne.php:12",
            );
        });

        $html = (string) $this->get('/essai-500')->assertStatus(500)->getContent();

        $this->assertStringContainsString(e(__('erreurs.500.titre')), $html);
        $this->assertAucuneFuite($html, '500 RuntimeException');
        $this->assertStringNotContainsString('users', $html);
    }

    #[Test]
    public function l_identifiant_d_incident_est_court_stable_et_retrouvable_dans_le_journal(): void
    {
        Route::middleware('web')->get('/essai-incident', function () {
            throw new \RuntimeException('secret-technique');
        });

        $html = (string) $this->get('/essai-incident')->assertStatus(500)->getContent();
        $this->assertSame(1, preg_match('#<span class="incident">(INC-[0-9A-F]{8})</span>#', $html, $m), 'Identifiant d\'incident absent.');

        // Deuxième appel au même endroit : même identifiant (support).
        $this->assertStringContainsString($m[1], (string) $this->get('/essai-incident')->getContent());

        // Les pages sans incident technique n'en affichent pas.
        $this->assertStringNotContainsString('INC-', (string) $this->get('/essai-erreur/404')->getContent());
        $this->assertStringNotContainsString('INC-', (string) $this->get('/essai-erreur/503')->getContent());
    }

    #[Test]
    public function la_maintenance_se_rafraichit_toute_seule_et_reste_sobre(): void
    {
        $html = (string) $this->get('/essai-erreur/503')->assertStatus(503)->getContent();

        $this->assertStringContainsString('<meta http-equiv="refresh" content="60">', $html);
        $this->assertStringContainsString(e(__('erreurs.rafraichissement')), $html);
        $this->assertStringContainsString('role="status"', $html);

        // Les autres pages ne se rafraîchissent pas seules.
        $this->assertStringNotContainsString('http-equiv="refresh"', (string) $this->get('/essai-erreur/500')->getContent());
    }

    #[Test]
    public function la_page_de_maintenance_de_laravel_est_la_vue_503_du_projet(): void
    {
        $this->artisan('down', ['--retry' => 120])->assertExitCode(0);

        try {
            $reponse = $this->get('/pwa/connexion')->assertStatus(503)->assertHeader('Retry-After', '120');
            $html = (string) $reponse->getContent();
            $this->assertStringContainsString(e(__('erreurs.503.titre')), $html);
            $this->assertAucuneFuite($html, 'maintenance');
        } finally {
            $this->artisan('up');
        }
    }

    #[Test]
    public function le_json_de_l_api_reste_du_json(): void
    {
        $inconnu = $this->getJson('/api/v1/une-route-qui-n-existe-pas')->assertNotFound();
        $this->assertStringContainsString('json', (string) $inconnu->headers->get('Content-Type'));
        $this->assertStringNotContainsString('<html', (string) $inconnu->getContent());

        Route::middleware('api')->get('/api/essai-500', function () {
            throw new \RuntimeException('secret-technique /home/user');
        });
        $erreur = $this->getJson('/api/essai-500')->assertStatus(500);
        $this->assertStringContainsString('json', (string) $erreur->headers->get('Content-Type'));
        $this->assertAucuneFuite((string) $erreur->getContent(), 'API 500');

        // Une route web interrogée en JSON répond aussi en JSON.
        $web = $this->getJson('/essai-erreur/403')->assertForbidden();
        $this->assertStringNotContainsString('<html', (string) $web->getContent());

        // Non authentifié sur l'API : 401 JSON, jamais une redirection HTML.
        $this->getJson('/api/v1/utilisateur-inexistant-protege')->assertStatus(404);
    }

    #[Test]
    public function en_debogage_la_page_native_de_laravel_est_conservee(): void
    {
        config(['app.debug' => true]);
        Route::middleware('web')->get('/essai-debug', function () {
            throw new \RuntimeException('message-de-debogage-visible');
        });

        $this->get('/essai-debug', ['Accept' => 'text/html'])
            ->assertStatus(500)
            ->assertSee('message-de-debogage-visible', false)
            ->assertDontSee(e(__('erreurs.500.titre')), false);
    }

    /**
     * Le 419 d'une requête HTML ordinaire sert la page 419 (décision du PO,
     * 09/11/2026 ; `bootstrap/app.php`, garde `SessionExpireeTest`) : aucun
     * en-tête particulier n'est donc nécessaire pour la voir.
     */
    private function entetes(): array
    {
        return [];
    }

    private function assertAucuneFuite(string $contenu, string $contexte): void
    {
        foreach (self::FUITES as $marqueur) {
            $this->assertStringNotContainsString($marqueur, $contenu, "{$contexte} : fuite « {$marqueur} ».");
        }
    }

    private function assertAucuneRessourceDistante(string $html): void
    {
        $hoteLocal = (string) parse_url((string) config('app.url'), PHP_URL_HOST);
        preg_match_all('#https?://([^/"\'\s)<]+)#i', $html, $hotes);

        foreach (array_unique($hotes[1]) as $hote) {
            $this->assertContains($hote, [$hoteLocal, 'localhost', 'localhost:8000'], "Ressource distante : {$hote}.");
        }
    }

    private function creerUtilisateur(): User
    {
        return User::create([
            'login' => 'compte.erreurs',
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', 'administrateur')->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }
}
