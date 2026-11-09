<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Domain\Restaurant\Models\Plat;
use App\Domain\Restaurant\Services\RapprochementPlatsStockService;
use Illuminate\Console\Command;

/**
 * RATTRAPAGE des installations déjà importées (PO, 09/11/2026) : relie chaque
 * plat sans lien à l'article de stock de même nom au point Cuisine, crée les
 * articles manquants, laisse tout le reste intact. IDEMPOTENT.
 *
 * `--simuler` ne montre que les plats concernés, sans rien écrire.
 */
final class RapprocherPlatsStockCommand extends Command
{
    protected $signature = 'restaurant:rapprocher-plats-stock {--simuler : liste les plats concernés sans rien écrire}';

    protected $description = 'Relie les plats sans lien à l\'article de stock de même nom (point Cuisine), sans rien écraser';

    public function handle(RapprochementPlatsStockService $service): int
    {
        if ($this->option('simuler')) {
            $sansLien = Plat::query()->whereNull('article_id')->orderBy('libelle')->pluck('libelle');
            $this->info($sansLien->count().' plat(s) sans lien au stock (rien n\'a été écrit).');

            foreach ($sansLien as $libelle) {
                $this->line(' - '.$libelle);
            }

            return self::SUCCESS;
        }

        $bilan = $service->rapprocher();

        $this->info($bilan['rapproches'].' plat(s) rapproché(s) du stock, '.$bilan['articles_crees'].' article(s) créé(s) au point Cuisine'.($bilan['point_cree'] ? ' (point créé)' : '').'.');
        $this->line('Déjà reliés : '.$bilan['deja_lies'].' ; décomposés en ingrédients (laissés à leur fiche) : '.$bilan['avec_fiche'].'.');

        return self::SUCCESS;
    }
}
