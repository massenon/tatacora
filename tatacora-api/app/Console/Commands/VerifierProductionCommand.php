<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Shared\Exploitation\Services\VerificationProductionService;
use Illuminate\Console\Command;

/**
 * `php artisan tatacora:verifier-production` — la partie AUTOMATIQUE des
 * vérifications après chaque mise en production
 * (`docs/VERIFICATIONS_APRES_MISE_EN_PRODUCTION.md`). Code de sortie 1 dès
 * qu'un contrôle est en échec : un script de déploiement peut s'y arrêter.
 */
class VerifierProductionCommand extends Command
{
    protected $signature = 'tatacora:verifier-production';

    protected $description = 'Contrôle l\'installation après une mise en production (configuration, cron, sauvegarde, courriel, réinitialisation)';

    public function handle(VerificationProductionService $verification): int
    {
        $resultats = $verification->executer();
        $libelles = [
            VerificationProductionService::OK => 'OK',
            VerificationProductionService::ATTENTION => 'ATTENTION',
            VerificationProductionService::ECHEC => 'ÉCHEC',
        ];

        $this->table(['Contrôle', 'Issue', 'Détail'], array_map(
            static fn (array $r): array => [$r['controle'], $libelles[$r['issue']], $r['detail']],
            $resultats,
        ));

        $echecs = count(array_filter($resultats, static fn (array $r): bool => $r['issue'] === VerificationProductionService::ECHEC));
        $attentions = count(array_filter($resultats, static fn (array $r): bool => $r['issue'] === VerificationProductionService::ATTENTION));

        if ($echecs > 0) {
            $this->error("{$echecs} échec(s), {$attentions} point(s) d'attention : à corriger avant d'ouvrir.");

            return self::FAILURE;
        }

        $this->info("Aucun échec ; {$attentions} point(s) d'attention.");

        return self::SUCCESS;
    }
}
