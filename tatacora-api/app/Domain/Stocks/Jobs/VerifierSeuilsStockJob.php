<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Jobs;

use App\Domain\Stocks\Events\SeuilStockAtteint;
use App\Domain\Stocks\Services\VerificationSeuilService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/**
 * Filet de securite des alertes de stock — RG-07, toutes les 15 minutes.
 *
 * **Ce n'est pas une redondance de la verification synchrone.** Celle-ci ne se
 * declenche qu'apres un MOUVEMENT. Un seuil releve par un gestionnaire a midi
 * ne produirait donc aucune alerte avant la prochaine sortie de stock —
 * c'est-a-dire potentiellement jamais sur un article a rotation lente
 * (ALERTES_CRITIQUES_DE_STOCK.md §3).
 */
class VerifierSeuilsStockJob implements ShouldQueue
{
    use Queueable;

    public function handle(VerificationSeuilService $seuils): int
    {
        $critiques = $seuils->articlesCritiques();

        foreach ($critiques as $critique) {
            SeuilStockAtteint::dispatch(
                $critique['article_id'],
                $critique['point_id'],
                $critique['stock'],
                $critique['seuil'],
            );
        }

        return $critiques->count();
    }
}
