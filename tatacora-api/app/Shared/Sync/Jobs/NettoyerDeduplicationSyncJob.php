<?php

declare(strict_types=1);

namespace App\Shared\Sync\Jobs;

use App\Shared\Sync\Services\SynchronisationService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

/**
 * Purge de la memoire d'idempotence — LARAVEL_SYNC_FLUTTER.md §5, TTL de
 * `SynchronisationService::TTL_DEDUPLICATION_JOURS` (30 jours depuis la
 * decision PO du 15/10/2026 ; 7 auparavant — les postes Windows des sites
 * isoles peuvent rester des semaines sans serveur).
 *
 * Le TTL n'est pas un reglage de confort : il doit couvrir la plus longue
 * periode hors connexion realiste. Un guide en circuit de plusieurs jours
 * rejoue sa file au retour ; si la memoire avait ete purgee entre-temps, ses
 * operations seraient re-executees et creeraient des doublons.
 */
class NettoyerDeduplicationSyncJob implements ShouldQueue
{
    use Queueable;

    public function handle(SynchronisationService $synchronisation): int
    {
        return $synchronisation->purgerDeduplication();
    }
}
