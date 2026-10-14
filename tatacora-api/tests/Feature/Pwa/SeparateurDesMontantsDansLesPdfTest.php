<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Pwa\Support\MontantFcfa;
use Barryvdh\DomPDF\Facade\Pdf;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le separateur de milliers DOIT exister dans les polices des PDF —
 * directive nee d'un defaut constate par le Product Owner (02/09/2026) :
 * la fiche des prix imprimait « 1?500 ».
 *
 * La cause : `MontantFcfa::SEPARATEUR` valait U+202F (l'espace fine
 * insecable, mesuree sur `Intl.NumberFormat('fr-FR')` du maitre — juste
 * pour l'ECRAN), et l'encodage WinAnsi de Helvetica, la police de treize
 * gabarits PDF, n'a aucun glyphe pour la fine : dompdf la rendait « ? »
 * sur chaque montant du document remis.
 *
 * Ces cas EXECUTENT dompdf et LISENT le flux du PDF produit — pas le HTML
 * intermediaire, ou le defaut est invisible : il nait au moment ou la
 * police encode le caractere. La contre-epreuve regenere le defaut avec
 * la fine, pour que ce test ne puisse pas passer a vide.
 */
final class SeparateurDesMontantsDansLesPdfTest extends TestCase
{
    private const GABARIT = '<html><body style="font-family: Helvetica">%s</body></html>';

    /**
     * Les segments de texte des flux du PDF, decompresses.
     *
     * @return list<string>
     */
    private function segmentsDuPdf(string $pdf): array
    {
        $segments = [];
        preg_match_all('/stream'.chr(13).'?'.chr(10).'(.*?)endstream/s', $pdf, $flux);

        foreach ($flux[1] as $brut) {
            $texte = @gzuncompress($brut);
            $texte = $texte === false ? $brut : $texte;
            preg_match_all('/'.preg_quote('[(', '/').'(.*?)'.preg_quote(')]', '/').'/s', $texte, $morceaux);
            $segments = array_merge($segments, $morceaux[1]);
        }

        return $segments;
    }

    #[Test]
    public function le_separateur_est_l_insecable_classique_et_helvetica_le_rend(): void
    {
        $this->assertSame("\u{00A0}", MontantFcfa::SEPARATEUR);

        $pdf = Pdf::loadHTML(sprintf(self::GABARIT, MontantFcfa::format('1500.00')))->output();
        $segments = $this->segmentsDuPdf($pdf);

        $this->assertNotContains('?', $segments, 'Un montant du PDF rend un « ? » : le separateur n'.chr(39).'a pas de glyphe dans la police.');
        $this->assertTrue(
            (bool) array_filter($segments, static fn (string $s): bool => str_contains($s, chr(0xA0))),
            'L'.chr(39).'insecable U+00A0 n'.chr(39).'apparait pas dans le flux : le groupement des milliers a disparu du document.',
        );
    }

    /**
     * CONTRE-EPREUVE : la fine U+202F reproduit le defaut. Si dompdf ou sa
     * police apprenait un jour a la rendre, ce cas rougirait — et la
     * decision du 02/09/2026 meriterait d'etre rouverte, pas reconduite.
     */
    #[Test]
    public function la_fine_u202f_reproduit_le_defaut_dans_helvetica(): void
    {
        $pdf = Pdf::loadHTML(sprintf(self::GABARIT, '1'."\u{202F}".'500 F'))->output();

        $this->assertContains('?', $this->segmentsDuPdf($pdf), 'La fine est desormais rendue par la police : rouvrir la decision du 02/09/2026.');
    }
}
