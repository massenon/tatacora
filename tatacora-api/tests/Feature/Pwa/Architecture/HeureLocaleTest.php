<?php

declare(strict_types=1);

namespace Tests\Feature\Pwa\Architecture;

use App\Shared\Support\HeureLocale;
use Carbon\CarbonImmutable;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Le web affiche l'heure LOCALE du Bénin (UTC+1), la base reste en UTC (décision du PO du
 * 09/11/2026 : « le web doit afficher l'heure locale »). Un seul passage : `HeureLocale`.
 */
final class HeureLocaleTest extends TestCase
{
    #[Test]
    public function vingt_trois_heures_trente_utc_est_minuit_trente_le_lendemain_au_benin(): void
    {
        $instant = CarbonImmutable::parse('2026-11-09 23:30:00', 'UTC');

        $this->assertSame('10/11/2026 00:30', HeureLocale::formater($instant, 'd/m/Y H:i'));
        $this->assertSame('10/11/2026 00:30', HeureLocale::formater('2026-11-09 23:30:00', 'd/m/Y H:i'));
        // L'instant d'origine n'est jamais modifié (immuable) : l'UTC reste l'UTC.
        $this->assertSame('09/11/2026 23:30', $instant->format('d/m/Y H:i'));
    }

    #[Test]
    public function une_absence_d_horodatage_reste_une_absence(): void
    {
        $this->assertNull(HeureLocale::formater(null));
        $this->assertNull(HeureLocale::convertir(''));
        $this->assertSame('—', HeureLocale::formater(null) ?? '—');
    }

    #[Test]
    public function le_fuseau_d_affichage_se_regle_sans_toucher_au_fuseau_de_l_application(): void
    {
        $this->assertSame('UTC', config('app.timezone'));
        $this->assertSame('Africa/Porto-Novo', HeureLocale::fuseau());
    }

    #[Test]
    public function aucun_horodatage_n_est_affiche_sans_passer_par_l_heure_locale(): void
    {
        $racine = dirname(__DIR__, 4);
        $fichiers = [];
        foreach (['app', 'resources/views'] as $dossier) {
            $it = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine.'/'.$dossier, \FilesystemIterator::SKIP_DOTS));
            foreach ($it as $f) {
                if ($f->isFile() && str_ends_with($f->getFilename(), '.php')) {
                    $fichiers[] = $f->getPathname();
                }
            }
        }
        $this->assertGreaterThan(300, count($fichiers), 'Balayage vide : plancher de fichiers.');

        // Affichage direct d'une HEURE (H:i) depuis un instant : interdit hors HeureLocale.
        // Exceptions nommées : formats de TRANSPORT, jamais affichés (clé SQL, validation).
        $motif = '/(?:->|::)(?:format)\(\s*\'[^\'\n]*H:i[^\'\n]*\'/';
        $exceptions = [
            'app/Shared/Support/HeureLocale.php',
            'app/Shared/Sync/Gestionnaires/GestionnaireSessionsCaisse.php',
            'app/Shared/Sync/Services/CatalogueDescendantService.php',
        ];
        $fautes = [];
        foreach ($fichiers as $fichier) {
            $relatif = ltrim(str_replace($racine, '', $fichier), '/');
            if (in_array($relatif, $exceptions, true)) {
                continue;
            }
            foreach (file($fichier) as $n => $ligne) {
                if (preg_match($motif, $ligne) === 1 && str_contains($ligne, "'Y-m-d H:i") === false) {
                    $fautes[] = $relatif.':'.($n + 1);
                }
            }
        }

        $this->assertSame([], $fautes, "Horodatage affiché sans HeureLocale::formater().\n".implode("\n", $fautes));
    }
}
