<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Support\GenerateurEchantillons;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * Les échantillons du dossier `presentation/` : régénérés dans un dossier TEMPORAIRE (jamais dans
 * `presentation/`), ouverts, non vides, filigranés, avec le QR sur le normalisé et PAS sur le simple.
 */
final class EchantillonsPresentationTest extends TestCase
{
    private string $dossier;

    protected function setUp(): void
    {
        parent::setUp();
        $this->dossier = sys_get_temp_dir().'/tatacora_echantillons_'.bin2hex(random_bytes(4));
    }

    protected function tearDown(): void
    {
        foreach (glob($this->dossier.'/*') ?: [] as $fichier) {
            @unlink($fichier);
        }
        @rmdir($this->dossier);
        parent::tearDown();
    }

    private function texteDuPdf(string $chemin): ?string
    {
        if (trim((string) shell_exec('command -v pdftotext')) === '') {
            return null;
        }

        return (string) shell_exec('pdftotext -layout '.escapeshellarg($chemin).' - 2>/dev/null');
    }

    #[Test]
    public function les_echantillons_serveur_sont_des_pdf_filtres_avec_qr_seulement_sur_le_normalise(): void
    {
        $generateur = new GenerateurEchantillons();
        $ecrits = $generateur->generer($this->dossier);

        $this->assertCount(4, $ecrits);

        foreach ([GenerateurEchantillons::FICHIER_SIMPLE, GenerateurEchantillons::FICHIER_NORMALISEE] as $nom) {
            $octets = (string) file_get_contents($ecrits[$nom]);
            $this->assertStringStartsWith('%PDF', $octets, $nom);
            $this->assertGreaterThan(5000, strlen($octets), $nom.' ne doit pas être vide');
        }

        // Le HTML RENDU : QR dessiné (SVG) sur le normalisé seulement, mention d'échantillon sur les deux.
        $htmlSimple = $generateur->htmlFactureA4(normalisee: false);
        $htmlNormalisee = $generateur->htmlFactureA4(normalisee: true);

        $this->assertStringNotContainsString('data:image/svg+xml', $htmlSimple, 'jamais de QR sur la facture simple');
        $this->assertStringContainsString('data:image/svg+xml;base64,', $htmlNormalisee);
        $this->assertStringContainsString(GenerateurEchantillons::MENTION, $htmlSimple);
        $this->assertStringContainsString(GenerateurEchantillons::MENTION, $htmlNormalisee);

        foreach ([$htmlSimple, $htmlNormalisee] as $html) {
            $this->assertStringContainsString('Client Exemple', $html);
            $this->assertStringContainsString('0000000000000', $html, 'IFU factice');
            $this->assertStringNotContainsString('MECEF-DEMO-', $html);
        }
        $this->assertStringNotContainsString('Facture normalisée MECeF', $htmlSimple);
        $this->assertStringNotContainsString('NIM-TC', $htmlSimple);
        $this->assertStringNotContainsString('N° MECeF', $htmlSimple);
        $this->assertStringNotContainsString('en attente de normalisation', $htmlSimple);
        $this->assertStringContainsString('F;ECHANTILLON;', $htmlNormalisee);

        // Le texte réellement présent dans les PDF (si pdftotext existe).
        $simple = $this->texteDuPdf($ecrits[GenerateurEchantillons::FICHIER_SIMPLE]);
        $normalisee = $this->texteDuPdf($ecrits[GenerateurEchantillons::FICHIER_NORMALISEE]);
        if ($simple !== null && $normalisee !== null) {
            foreach ([$simple, $normalisee] as $texte) {
                $this->assertStringContainsString('ÉCHANTILLON — SANS VALEUR FISCALE', $texte);
                $this->assertStringContainsString('Chambre ventilée', $texte);
                $this->assertStringContainsString('Taxe de séjour', $texte);
                $this->assertStringContainsString('33 500 FCFA', str_replace("\u{00A0}", ' ', $texte));
            }
            $this->assertStringNotContainsString('NIM-TC', $simple);
            $this->assertStringNotContainsString('Contenu du code QR', $simple);
            $this->assertStringContainsString('Facture normalisée MECeF', $normalisee);
            $this->assertStringContainsString('F;ECHANTILLON;', $normalisee);
        }
    }

    #[Test]
    public function les_tickets_web_portent_la_mention_et_le_pied_mecef_seulement_hors_mode_desactive(): void
    {
        $generateur = new GenerateurEchantillons();
        $simple = $generateur->htmlTicketWeb(ModeFacturation::Desactive);
        $mecef = $generateur->htmlTicketWeb(ModeFacturation::Boitier);

        foreach ([$simple, $mecef] as $html) {
            $this->assertStringContainsString(GenerateurEchantillons::MENTION, $html);
            $this->assertStringNotContainsString('window.print()', str_replace('onclick="window.print()"', '', $html), 'pas de script d\'impression');
            $this->assertStringContainsString('TICKET DE VENTE', $html);
        }
        $this->assertStringNotContainsString('class="pied-mecef"', $simple);
        $this->assertStringContainsString('class="pied-mecef"', $mecef);
    }

    #[Test]
    public function le_filigrane_n_existe_que_dans_le_generateur_jamais_dans_les_gabarits_de_production(): void
    {
        foreach (['pdf/facture-mecef', 'pwa/pos/ticket-thermique'] as $vue) {
            $source = (string) file_get_contents(resource_path('views/'.$vue.'.blade.php'));
            $this->assertStringNotContainsString('ÉCHANTILLON', $source, $vue);
            $this->assertStringNotContainsString('ECHANTILLON', $source, $vue);
        }
    }

    #[Test]
    public function la_generation_est_refusee_en_production(): void
    {
        $this->app->detectEnvironment(static fn (): string => 'production');

        $this->expectException(RuntimeException::class);

        try {
            (new GenerateurEchantillons())->generer($this->dossier);
        } finally {
            $this->assertDirectoryDoesNotExist($this->dossier);
        }
    }
}
