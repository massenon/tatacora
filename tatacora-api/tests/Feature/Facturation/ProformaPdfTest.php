<?php

declare(strict_types=1);

namespace Tests\Feature\Facturation;

use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Services\DocumentProforma;
use App\Domain\Facturation\Services\ModeFacturation;
use App\Domain\Facturation\Services\ProformaService;
use App\Domain\Facturation\Services\ReglagesDocuments;
use App\Domain\Facturation\Support\MiseEnPageProforma;
use App\Shared\Parametres\Models\ParametreSysteme;
use App\Shared\Parametres\Services\ApparenceEtablissementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Storage;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/** Le PDF A4 de la proforma (PO, 07/11/2026) : contenu fidèle au modèle, jamais de mention fiscale. */
final class ProformaPdfTest extends TestCase
{
    use RefreshDatabase;

    private function regler(string $cle, string $valeur): void
    {
        ParametreSysteme::updateOrCreate(['cle' => $cle], ['valeur' => $valeur]);
    }

    private function emise(int $prix = 100000): Proforma
    {
        $this->regler('entreprise_ifu', '0202011344660');
        $this->regler('entreprise_rccm', 'RB/NAT/12 B 345');
        $this->regler(ReglagesDocuments::CLE_ACTIVITES, 'Tourisme, Hébergement, Restauration, Formation, Location, Transport');
        $this->regler(ReglagesDocuments::CLE_VILLE_EMISSION, 'Natitingou');
        $service = app(ProformaService::class);

        return $service->emettre($service->creer([
            'client_nom' => 'SOCIÉTÉ KORA', 'client_telephone' => '0190123456',
            'objet' => 'Séjour de groupe',
            'lignes' => [['designation' => 'Forfait groupe', 'quantite' => 4, 'prix_unitaire' => $prix]],
        ]), '2026-11-02');
    }

    private function html(Proforma $p): string
    {
        return app(DocumentProforma::class)->vue($p)->render();
    }

    #[Test]
    public function le_document_reproduit_la_structure_du_modele(): void
    {
        $html = $this->html($this->emise());

        foreach ([
            'FACTURE PROFORMA', 'N°0001 FP-GCN/2026', 'SOCIÉTÉ KORA', 'Séjour de groupe',
            'Natitingou, le 02 Novembre 2026', 'Tourisme, Hébergement, Restauration, Formation, Location, Transport',
            'N°RCCM : RB/NAT/12 B 345', 'N°IFU : 0202011344660',
            'DÉSIGNATION', 'Quantité', 'Prix unitaire (FCFA)', 'Montant (FCFA)', 'TOTAL',
            "100\u{00A0}000", "400\u{00A0}000",
            'Arrêté la présente FACTURE PROFORMA à la somme de', 'QUATRE CENT MILLE FRANCS CFA',
        ] as $attendu) {
            $this->assertStringContainsString($attendu, $html, $attendu);
        }

        // L'en-tête du tableau porte le jeton vert du thème, posé par le code (pas en dur dans la vue).
        $this->assertStringContainsString('background: '.MiseEnPageProforma::JETON_VERT_ENTETE, $html);
        $this->assertStringNotContainsString('#15803D', (string) file_get_contents(resource_path('views/pdf/proforma.blade.php')));
    }

    /** @return array<string, array{0: string}> */
    public static function modes(): array
    {
        return ['desactive' => ['desactive'], 'emecef' => ['emecef'], 'boitier' => ['boitier']];
    }

    #[Test]
    #[DataProvider('modes')]
    public function jamais_de_mention_fiscale_quel_que_soit_le_mode(string $mode): void
    {
        $this->regler(ModeFacturation::CLE, $mode);
        $html = $this->html($this->emise());

        foreach (['MECeF', 'MECEF', 'NIM', 'QR', 'DEMO', 'normalis', 'certifi', 'data:image/svg'] as $interdit) {
            $this->assertStringNotContainsStringIgnoringCase($interdit, $html, $interdit);
        }
        $this->assertStringNotContainsString('<svg', $html);
    }

    #[Test]
    public function la_validite_n_apparait_que_si_elle_a_ete_enregistree(): void
    {
        $this->assertStringNotContainsString('Valable jusqu', $this->html($this->emise()));

        $this->regler(ReglagesDocuments::CLE_VALIDITE_AFFICHEE, 'true');
        $this->assertStringContainsString('Valable jusqu’au 02 Décembre 2026', $this->html($this->emise()));
    }

    #[Test]
    public function la_signature_suit_l_interrupteur_pour_les_proformas_aussi(): void
    {
        Storage::fake('public');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_NOM, 'NABOGOU Winribassé Noël');
        $this->regler(ReglagesDocuments::CLE_SIGNATAIRE_FONCTION, 'Directeur Général');
        $image = imagecreatetruecolor(30, 30);
        ob_start();
        imagepng($image);
        app(ApparenceEtablissementService::class)->enregistrerImageDocument('signature', (string) ob_get_clean());
        $p = $this->emise();

        $non = $this->html($p);
        $this->assertStringNotContainsString('NABOGOU', $non);
        $this->assertStringNotContainsString('Pour ', $non);

        $this->regler(ReglagesDocuments::CLE_SIGNATURE_AFFICHEE, 'true');
        $oui = $this->html($p);
        $this->assertStringContainsString('NABOGOU Winribassé Noël', $oui);
        $this->assertStringContainsString('Directeur Général', $oui);
        $this->assertStringContainsString('Pour ', $oui);
        $this->assertStringContainsString('data:image/png;base64,', $oui);
    }

    #[Test]
    public function dompdf_produit_un_vrai_pdf(): void
    {
        $document = app(DocumentProforma::class);
        $p = $this->emise();
        $pdf = $document->pdf($p);

        $this->assertStringStartsWith('%PDF-', $pdf);
        $this->assertGreaterThan(2500, strlen($pdf));
        $this->assertSame('proforma_N_0001_FP_GCN_2026.pdf', $document->nomFichier($p));
    }

    #[Test]
    public function le_vert_est_le_jeton_du_theme_du_poste(): void
    {
        $dart = (string) file_get_contents(__DIR__.'/../../../../tatacora-flutter/lib/core/theme/app_colors.dart');
        $this->assertSame(1, preg_match('/vert700\s*=\s*Color\(0xFF([0-9A-Fa-f]{6})\)/', $dart, $m));
        $this->assertSame(strtoupper('#'.$m[1]), strtoupper(MiseEnPageProforma::JETON_VERT_ENTETE));
    }

    #[Test]
    public function la_date_longue_et_les_milliers_suivent_le_modele(): void
    {
        $this->assertSame('02 Novembre 2026', MiseEnPageProforma::dateLongue(Carbon::parse('2026-11-02')));
        $this->assertSame('01 Août 2027', MiseEnPageProforma::dateLongue(Carbon::parse('2027-08-01')));
        $this->assertSame("1\u{00A0}234\u{00A0}567", MiseEnPageProforma::montant(1234567));
    }
}
