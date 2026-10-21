<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le formulaire de connexion ne doit JAMAIS envoyer l'identifiant ni le mot de
 * passe dans l'adresse : si Livewire ne démarre pas (script introuvable, cache
 * de routes périmé), le navigateur soumet le formulaire de lui-même, et sans
 * `method="post"` c'est un GET (constaté le 21/10/2026).
 */
final class ConnexionSansScriptTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function le_formulaire_de_repli_ne_part_jamais_en_get(): void
    {
        $html = (string) $this->get(route('pwa.connexion'))->assertOk()->getContent();

        $this->assertMatchesRegularExpression('#<form id="formulaire-connexion"[^>]*method="post"#', $html);
        $this->assertMatchesRegularExpression('#<form id="formulaire-connexion"[^>]*onsubmit="return false"#', $html);
        $this->assertStringContainsString('wire:submit="seConnecter"', $html);
    }

    #[Test]
    public function des_identifiants_dans_l_adresse_ne_connectent_personne_et_ne_remplissent_rien(): void
    {
        $html = (string) $this->get('/pwa/connexion?identifiant=quelquun&motdepasse=secret-de-test')->assertOk()->getContent();

        $this->assertStringNotContainsString('secret-de-test', $html);
        $this->assertGuest();
    }
}
