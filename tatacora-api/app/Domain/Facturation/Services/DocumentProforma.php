<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Services;

use App\Domain\Facturation\Models\Proforma;
use App\Domain\Facturation\Support\MiseEnPageProforma;
use App\Shared\ReportEngine\Services\ReportHeaderService;
use Barryvdh\DomPDF\Facade\Pdf;
use Illuminate\Contracts\View\View;

/** Le document A4 de la proforma — UNE vue (`pdf.proforma`), rendue en HTML (tests) ou en PDF (dompdf). */
class DocumentProforma
{
    public function __construct(
        private readonly ReportHeaderService $entetes,
        private readonly ReglagesDocuments $reglages,
    ) {
    }

    public function vue(Proforma $proforma): View
    {
        $proforma->loadMissing('lignes');

        return view('pdf.proforma', [
            'proforma' => $proforma,
            'entete' => $this->entetes->genererEnTete(typeRapport: __('proforma.titre'), periode: '', auteur: null),
            'activites' => $this->reglages->texte(ReglagesDocuments::CLE_ACTIVITES),
            'facebook' => $this->reglages->texte(ReglagesDocuments::CLE_FACEBOOK),
            'vert' => MiseEnPageProforma::JETON_VERT_ENTETE,
        ]);
    }

    public function pdf(Proforma $proforma): string
    {
        return Pdf::loadHTML($this->vue($proforma)->render())->setPaper('a4', 'portrait')->output();
    }

    public function nomFichier(Proforma $proforma): string
    {
        return 'proforma_'.preg_replace('/[^A-Za-z0-9]+/', '_', (string) ($proforma->numero ?? substr((string) $proforma->id, 0, 8))).'.pdf';
    }
}
