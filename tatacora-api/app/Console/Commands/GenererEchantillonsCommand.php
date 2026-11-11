<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Domain\Facturation\Support\GenerateurEchantillons;
use Illuminate\Console\Command;

/**
 * Écrit les documents ÉCHANTILLONS du serveur dans `presentation/` (facture simple et normalisée
 * en A4, tickets web 80 mm) : vrais gabarits, données FICTIVES, filigrane « ÉCHANTILLON — SANS
 * VALEUR FISCALE ». Refusé en production ; aucune base n'est lue.
 */
final class GenererEchantillonsCommand extends Command
{
    protected $signature = 'tatacora:generer-echantillons {dossier? : dossier de sortie (défaut : ../presentation)}';

    protected $description = 'Génère les PDF/HTML échantillons (fictifs, filigranés) du dossier presentation/';

    public function handle(GenerateurEchantillons $generateur): int
    {
        if (app()->isProduction()) {
            $this->error('Commande interdite en production : ces documents sont des échantillons.');

            return self::FAILURE;
        }

        $dossier = (string) ($this->argument('dossier') ?? base_path('../presentation'));

        foreach ($generateur->generer($dossier) as $nom => $chemin) {
            $this->info($nom.' — '.filesize($chemin).' octets');
        }

        return self::SUCCESS;
    }
}
