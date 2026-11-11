<?php

declare(strict_types=1);

namespace Tests\Unit\Facturation;

use App\Domain\Facturation\Support\MontantEnLettres;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class MontantEnLettresTest extends TestCase
{
    public const TABLE = __DIR__.'/../../../../tatacora-flutter/tool/proforma/cas_montant_en_lettres.json';

    #[Test]
    public function la_table_de_cas_du_po_est_respectee(): void
    {
        $cas = json_decode((string) file_get_contents(self::TABLE), true, 512, JSON_THROW_ON_ERROR);

        // Plancher : une table vidée ne doit pas rendre le test vert à vide.
        $this->assertGreaterThanOrEqual(30, count($cas));

        foreach ($cas as $ligne) {
            $this->assertSame($ligne['lettres'], MontantEnLettres::francsCfa($ligne['montant']), (string) $ligne['montant']);
        }
    }

    #[Test]
    public function les_montants_demandes_par_le_po_figurent_dans_la_table(): void
    {
        $montants = array_column(json_decode((string) file_get_contents(self::TABLE), true), 'montant');

        foreach ([0, 1, 21, 71, 80, 81, 91, 100, 101, 200, 201, 1000, 1001, 21000, 80000, 100000, 400000, 1000000, 2500000, 1234567] as $demande) {
            $this->assertContains($demande, $montants);
        }
    }

    #[Test]
    public function les_bornes_sont_refusees(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        MontantEnLettres::francsCfa(-1);
    }
}
