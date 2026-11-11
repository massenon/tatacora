<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Crm\Models\Client;
use App\Domain\Facturation\Models\Facture;
use App\Domain\Facturation\Models\LigneFacture;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Pwa\Livewire\Facturation\Facturation;
use App\Shared\Parametres\Data\RegistreParametres;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Lot 1 de la facture proforma (PO, 07/11/2026) : réglages des documents, images signature/cachet,
 * interrupteur de signature APPLIQUÉ AUX FACTURES existantes (PDF A4).
 */
final class ReglagesDocumentsTest extends TestCase
{
    use RefreshDatabase;

    private function regler(string $cle, string $valeur): void
    {
        ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
        app()->forgetInstance(ReglagesDocuments::class);
    }

    /** Une image PNG bruitée, donc incompressible : sa taille dépasse largement 400 Ko. */
    private function grosseImage(): string
    {
        $image = imagecreatetruecolor(1400, 1400);
        for ($y = 0; $y < 1400; $y++) {
            for ($x = 0; $x < 1400; $x++) {
                imagesetpixel($image, $x, $y, imagecolorallocate($image, random_int(0, 255), random_int(0, 255), random_int(0, 255)));
            }
        }
        ob_start();
        imagepng($image, null, 0);

        return (string) ob_get_clean();
    }

    private function petiteImage(): string
    {
        $image = imagecreatetruecolor(40, 20);
        ob_start();
        imagepng($image);

        return (string) ob_get_clean();
    }

    private function documentFacture(): string
    {
        $client = Client::create(['nom' => 'KORA', 'prenom' => 'Jean', 'telephone' => '0190123456', 'type_client' => 'particulier']);
        $facture = Facture::create([
            'client_id' => $client->id, 'date_emission' => now()->toDateString(),
            'montant_ht' => '50000.00', 'montant_tva' => '0.00', 'montant_ttc' => '50000.00', 'statut' => 'certifiee',
        ]);
        LigneFacture::create([
            'facture_id' => $facture->id, 'source_module' => 'M1', 'source_id' => $client->id,
            'libelle' => 'Hébergement', 'quantite' => '2.00', 'prix_unitaire' => '25000.00', 'montant' => '50000.00',
        ]);
        $facture->loadMissing(['lignes', 'avoirs', 'paiements']);

        return view('pdf.facture-mecef', [
            'facture' => $facture, 'client' => $client, 'activites' => Facturation::ACTIVITES,
            'modesPaiement' => [], 'totalAvoirs' => '0.00', 'net' => '50000.00', 'resteDu' => $facture->resteDu(),
            'auteur' => 'compte.test',
            'entete' => app(ReportHeaderService::class)->genererEnTete(typeRapport: 'Facture', periode: '', auteur: null),
        ])->render();
    }

    #[Test]
    public function les_neuf_reglages_existent_au_registre_avec_leurs_defauts(): void
    {
        foreach ([
            ReglagesDocuments::CLE_ACTIVITES, ReglagesDocuments::CLE_FACEBOOK, ReglagesDocuments::CLE_VILLE_EMISSION,
            ReglagesDocuments::CLE_REFERENCE_FACTURE, ReglagesDocuments::CLE_SIGNATAIRE_NOM, ReglagesDocuments::CLE_SIGNATAIRE_FONCTION,
            ReglagesDocuments::CLE_SIGNATURE_AFFICHEE, ReglagesDocuments::CLE_VALIDITE_AFFICHEE, ReglagesDocuments::CLE_VALIDITE_JOURS,
        ] as $cle) {
            $this->assertTrue(RegistreParametres::existe($cle), $cle);
        }

        $reglages = app(ReglagesDocuments::class);
        $this->assertSame('GCN', $reglages->referenceFacture());
        $this->assertFalse($reglages->validiteAffichee());
        $this->assertSame(30, $reglages->validiteJours());
        $this->assertFalse($reglages->signatureAffichee());

        $this->regler(ReglagesDocuments::CLE_REFERENCE_FACTURE, 'abc');
        $this->assertSame('ABC', app(ReglagesDocuments::class)->referenceFacture());
    }

    #[Test]
    public function une_image_de_plus_de_400_ko_est_reduite_pas_refusee(): void
    {
        Storage::fake('public');
        $gros = $this->grosseImage();
        $this->assertGreaterThan(400 * 1024, strlen($gros));

        $apparence = app(ApparenceEtablissementService::class);
        $apparence->enregistrerImageDocument('signature', $gros);

        $stocke = $apparence->octetsImageDocument('signature');
        $this->assertNotNull($stocke);
        $this->assertLessThanOrEqual(400 * 1024, strlen($stocke));
        $this->assertNotNull($apparence->empreinteImageDocument('signature'));
        $this->assertNull($apparence->octetsImageDocument('cachet'));
    }

    #[Test]
    public function une_signature_qui_n_est_pas_une_image_est_refusee(): void
    {
        Storage::fake('public');
        $this->expectException(\App\Domain\Depenses\Exceptions\RefusRecuDepense::class);

        app(ApparenceEtablissementService::class)->enregistrerImageDocument('signature', 'ceci n est pas une image');
    }

    #[Test]
    public function l_interrupteur_non_retire_tout_le_bloc_signature_d_une_facture(): void
    {
        Storage::fake('public');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_NOM, 'NABOGOU Winribassé Noël');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_FONCTION, 'Directeur Général');
        app(ApparenceEtablissementService::class)->enregistrerImageDocument('signature', $this->petiteImage());

        // Non (défaut) : ni nom, ni fonction, ni image.
        $html = $this->documentFacture();
        $this->assertStringNotContainsString('NABOGOU', $html);
        $this->assertStringNotContainsString('Directeur Général', $html);
        $this->assertStringNotContainsString('data:image', $html);

        // Oui : nom, fonction, signature (le cachet n'est pas déposé : pas d'image vide).
        $this->regler(ReglagesDocuments::CLE_SIGNATURE_AFFICHEE, 'true');
        $html = $this->documentFacture();
        $this->assertStringContainsString('NABOGOU Winribassé Noël', $html);
        $this->assertStringContainsString('Directeur Général', $html);
        $this->assertSame(1, substr_count($html, 'data:image/png;base64,'));
    }

    #[Test]
    public function oui_sans_image_deposee_ne_porte_que_le_nom_et_la_fonction(): void
    {
        Storage::fake('public');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_NOM, 'NABOGOU Winribassé Noël');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_FONCTION, 'Directeur Général');
        $this->regler(ReglagesDocuments::CLE_SIGNATURE_AFFICHEE, 'true');

        $html = $this->documentFacture();
        $this->assertStringContainsString('Directeur Général', $html);
        $this->assertStringNotContainsString('data:image', $html);
    }
}
