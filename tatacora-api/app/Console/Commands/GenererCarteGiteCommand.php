<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Shared\ImportExport\Services\CarteGiteChezNoelService;
use Illuminate\Console\Command;

/**
 * Écrit les trois classeurs `.xlsx` préremplis de la carte du Gîte Chez Noël
 * (`modele_import_m6-stocks.xlsx`, `…m5-bar.xlsx`, `…m4-restaurant.xlsx`) —
 * ceux que l'écran Import & Export propose en « Carte du Gîte Chez Noël
 * (exemple) » et que `docs/data/` conserve pour le PO.
 */
final class GenererCarteGiteCommand extends Command
{
    protected $signature = 'import:generer-carte-gite {dossier? : dossier de sortie (défaut : ../docs/data)}';

    protected $description = 'Écrit les modèles d\'import .xlsx préremplis avec la carte du Gîte Chez Noël';

    public function handle(CarteGiteChezNoelService $carte): int
    {
        $dossier = rtrim((string) ($this->argument('dossier') ?? base_path('../docs/data')), '/');

        if (! is_dir($dossier)) {
            $this->error('Dossier introuvable : '.$dossier);

            return self::FAILURE;
        }

        foreach (CarteGiteChezNoelService::MODULES as $cle) {
            $chemin = $dossier.'/modele_import_'.$cle.'.xlsx';
            file_put_contents($chemin, $carte->classeur($cle));
            $this->info($chemin.' — '.count($carte->lignes($cle)).' ligne(s)');
        }

        foreach ($carte->doublonsEcartes() as $d) {
            $this->line('Doublon écarté : « '.$d['nom'].' » ('.$d['rubrique'].') — retenu : « '.$d['retenu'].' »');
        }

        return self::SUCCESS;
    }
}
