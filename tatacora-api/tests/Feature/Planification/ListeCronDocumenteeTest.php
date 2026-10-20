<?php

declare(strict_types=1);

namespace Tests\Feature\Planification;

use Illuminate\Console\Scheduling\Schedule;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * La règle de revue de `routes/console.php` — « toute tâche ajoutée ici
 * DOIT être ajoutée au document » — rendue EXÉCUTABLE (19/10/2026) : le
 * document cité depuis l'origine n'existait pas dans le dépôt.
 */
final class ListeCronDocumenteeTest extends TestCase
{
    #[Test]
    public function chaque_tache_planifiee_figure_dans_la_liste_des_cron(): void
    {
        $chemin = base_path('../docs/LISTE_DES_CRON_JOBS_CPANEL.md');
        $this->assertFileExists($chemin);
        $document = (string) file_get_contents($chemin);

        $evenements = app(Schedule::class)->events();
        // Plancher : un planning vide rendrait le balayage vert à vide.
        $this->assertGreaterThanOrEqual(8, count($evenements));

        foreach ($evenements as $evenement) {
            $resume = $evenement->getSummaryForDisplay();
            $nom = preg_match("/artisan'?\s+(\S+)/", $resume, $m) === 1
                ? $m[1]
                : class_basename($resume);

            $this->assertStringContainsString("`{$nom}", $document, "« {$nom} » est planifiée mais absente de docs/LISTE_DES_CRON_JOBS_CPANEL.md.");
        }

        // La ligne cron unique, telle qu'à poser dans cPanel.
        $this->assertStringContainsString('artisan schedule:run', $document);
    }
}
