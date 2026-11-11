<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Conformite;

use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Directive du Product Owner du 26/10/2026 : l'historique des ventes, les
 * dépenses et le tableau de bord n'avaient pas d'icône devant leur titre, à
 * l'inverse des autres écrans. Le `<h1>` est précédé d'un `<svg width="24"
 * height="24" … stroke="var(--navy)">` dans un bloc `flex items-center gap-2.5`.
 * Le poste reprend le même tracé (`TraceIconesTitre`, `TracesAccueil.titre`).
 */
final class IconeDeTitrePwaTest extends TestCase
{
    private const MOTIF = '#<div class="flex items-center gap-2\.5">\s*<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="var\(--navy\)" stroke-width="2">(.+?)</svg>\s*<h1\b#s';

    /** @return array<string, array{0: string}> */
    public static function ecrans(): array
    {
        return [
            'historique des ventes' => ['pwa/pos/historique-ventes.blade.php'],
            'depenses' => ['pwa/depenses/depenses.blade.php'],
            'tableau de bord' => ['pwa/livewire/accueil.blade.php'],
            'temoin : factures' => ['pwa/facturation/facturation.blade.php'],
        ];
    }

    #[Test]
    #[DataProvider('ecrans')]
    public function le_titre_est_precede_de_son_icone(string $vue): void
    {
        $source = file_get_contents(resource_path('views/'.$vue));
        $this->assertSame(1, preg_match(self::MOTIF, $source, $m), "$vue : pas d'icône SVG devant le <h1>");
        $this->assertNotSame('', trim($m[1]), "$vue : icône vide");
    }

    #[Test]
    public function preuve_par_mutation_un_titre_sans_icone_est_denonce(): void
    {
        $source = file_get_contents(resource_path('views/pwa/depenses/depenses.blade.php'));
        $mute = preg_replace('#<svg width="24" height="24".+?</svg>#s', '', $source, 1);
        $this->assertNotSame($source, $mute);
        $this->assertSame(0, preg_match(self::MOTIF, $mute));
    }
}
