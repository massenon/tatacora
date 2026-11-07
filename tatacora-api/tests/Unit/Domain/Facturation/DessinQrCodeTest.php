<?php

declare(strict_types=1);

namespace Tests\Unit\Domain\Facturation;

use App\Domain\Facturation\Support\DessinQrCode;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class DessinQrCodeTest extends TestCase
{
    #[Test]
    public function un_contenu_vide_ne_dessine_rien(): void
    {
        $this->assertNull(DessinQrCode::enDataUri(null));
        $this->assertNull(DessinQrCode::enDataUri(''));
        $this->assertNull(DessinQrCode::enDataUri("  \n"));
    }

    #[Test]
    public function le_dessin_est_un_svg_en_data_uri_et_differe_selon_le_contenu(): void
    {
        $a = DessinQrCode::enDataUri('F;ED04000623;NW34NID6ZHANFNMZ2IU7LL3H;3201910768821;20200503135002');
        $b = DessinQrCode::enDataUri('F;ED04000623;AUTRE;3201910768821;20200503135002');

        $this->assertNotNull($a);
        $this->assertStringStartsWith('data:image/svg+xml;base64,', $a);
        $svg = base64_decode(substr($a, strlen('data:image/svg+xml;base64,')), true);
        $this->assertIsString($svg);
        $this->assertStringContainsString('<svg', $svg);
        $this->assertNotSame($a, $b);
    }
}
