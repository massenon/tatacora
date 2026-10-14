<?php

declare(strict_types=1);

namespace App\Shared\Audit\Jobs;

use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Parametres\Services\ParametreSystemeService;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;

/**
 * Purge du journal d'audit — RG-15, mensuel.
 *
 * ## Ce job ne fait rien, et c'est voulu
 *
 * La durée de rétention contractuelle du `journal_audit` **n'est pas encore
 * définie** avec le Product Owner (PA-08). `LISTE_DES_CRON_JOBS_CPANEL.md` est
 * explicite : « job à paramétrer une fois tranchée, **pas à activer par défaut
 * avec une valeur arbitraire** ».
 *
 * Il refuse donc de purger tant que `duree_retention_audit_jours` n'est pas
 * renseigné. Une valeur par défaut — même « raisonnable » — détruirait des
 * traces d'audit dont la durée de conservation est une obligation
 * contractuelle, et la destruction est irréversible.
 *
 * Le job existe malgré tout, plutôt que d'être absent, pour deux raisons : la
 * tâche planifiée est déjà documentée, et le jour où le paramètre sera
 * renseigné, la purge démarrera sans déploiement.
 */
class PurgerJournalAuditJob implements ShouldQueue
{
    use Queueable;

    public const CLE_RETENTION = 'duree_retention_audit_jours';

    /**
     * @return array{purgees: int, actif: bool}
     */
    public function handle(ParametreSystemeService $parametres): array
    {
        $retention = $parametres->get(self::CLE_RETENTION);

        if (blank($retention) || (int) $retention <= 0) {
            Log::info(
                'Purge du journal d\'audit ignorée : durée de rétention non définie (PA-08). '
                . 'Aucune trace supprimée.',
            );

            return ['purgees' => 0, 'actif' => false];
        }

        $purgees = JournalAudit::where('date_heure', '<', now()->subDays((int) $retention))->delete();

        return ['purgees' => $purgees, 'actif' => true];
    }
}
