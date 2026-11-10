<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa;

use App\Pwa\Support\MontantFcfa;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/** Un montant DÛ ne cache jamais un centime (PO, 10/11/2026 : « 30 000 » affiché pour un reste de 29 999,99). */
final class MontantFcfaExactTest extends TestCase
{
    #[Test]
    public function un_franc_entier_garde_la_forme_habituelle_et_un_centime_se_dit(): void
    {
        $nbsp = MontantFcfa::SEPARATEUR;

        $this->assertSame('30'.$nbsp.'000 FCFA', MontantFcfa::formatExact('30000.00'));
        $this->assertSame('29'.$nbsp.'999,99 FCFA', MontantFcfa::formatExact('29999.99'));
        $this->assertSame('1'.$nbsp.'005,50 FCFA', MontantFcfa::formatExact('1005.5'));
        $this->assertSame('-0,01 FCFA', MontantFcfa::formatExact('-0.01'));
        // `format()` garde son arrondi au franc : seuls les restes dus passent par `formatExact()`.
        $this->assertSame('30'.$nbsp.'000 FCFA', MontantFcfa::format('29999.99'));
    }
}
