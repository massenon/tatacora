<?php

declare(strict_types=1);

namespace App\Shared\Backup\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Log;
use RuntimeException;
use Symfony\Component\Process\Process;

/**
 * Sauvegarde quotidienne de la base — NFR « Sauvegarde et restauration ».
 *
 * `mysqldump`, rétention 30 jours glissants (`08_MIGRATION_DEPLOYMENT.md` §3.3).
 *
 * ## Le point qui compte plus que le dump lui-même
 *
 * Un échec de sauvegarde doit être **bruyant**. Une sauvegarde qui échoue en
 * silence pendant trois mois donne exactement la même impression qu'une
 * sauvegarde qui fonctionne — jusqu'au jour de la restauration, où l'on
 * découvre qu'il n'y a rien à restaurer. Le job lève donc une exception sur
 * échec, ce qui fait apparaître la tâche en `failed_jobs` plutôt que de
 * passer inaperçu.
 *
 * ## Ce qui n'est pas fait ici
 *
 * La **copie hors-site hebdomadaire** exigée par `08_MIGRATION_DEPLOYMENT.md`
 * §3.3 n'est pas implémentée : elle suppose un stockage tiers dont le
 * fournisseur n'est pas choisi. Une sauvegarde restée sur le même hébergement
 * ne protège d'aucun incident affectant l'hébergeur lui-même — le point est
 * ouvert, pas résolu (PA-45).
 *
 * La procédure de restauration doit être **testée avant la mise en
 * production** : un plan de sauvegarde jamais restauré n'est pas un plan de
 * sauvegarde.
 */
class SauvegardeBaseQuotidienneJob implements ShouldQueue
{
    use Queueable;

    public const RETENTION_JOURS = 30;

    /** Une sauvegarde qui traîne plus de 10 minutes signale déjà un problème. */
    private const TIMEOUT_SECONDES = 600;

    /**
     * @return array{fichier: string, octets: int, purgees: int}
     */
    public function handle(): array
    {
        $repertoire = storage_path('app/sauvegardes');

        if (! is_dir($repertoire) && ! mkdir($repertoire, 0755, true) && ! is_dir($repertoire)) {
            throw new RuntimeException(__('sauvegarde.repertoire_inaccessible', ['repertoire' => $repertoire]));
        }

        $fichier = $repertoire . '/tatacora-' . now()->format('Y-m-d_His') . '.sql';

        $processus = new Process($this->commande($fichier));
        $processus->setTimeout(self::TIMEOUT_SECONDES);
        $processus->run();

        if (! $processus->isSuccessful() || ! is_file($fichier) || filesize($fichier) === 0) {
            // Le fichier incomplet est RETIRÉ avant de lever.
            //
            // `mysqldump` écrit son en-tête avant d'échouer : un dump interrompu
            // laisse donc un fichier de plusieurs centaines d'octets, au nom
            // conforme, que la rétention conserverait trente jours comme
            // n'importe quelle sauvegarde. Un exploitant listant le répertoire y
            // verrait un fichier daté de la nuit et en conclurait que la
            // sauvegarde a eu lieu.
            //
            // C'est le seul état pire que l'absence de sauvegarde : il retire la
            // vigilance. Constaté le 18/08/2026 en exécutant `handle()` pour la
            // première fois — 802 octets laissés après un échec sur base
            // inexistante.
            if (is_file($fichier)) {
                @unlink($fichier);
            }

            // Échec bruyant : le job part en `failed_jobs`.
            throw new RuntimeException(__('sauvegarde.echec', [
                'raison' => trim($processus->getErrorOutput()) ?: __('sauvegarde.echec_raison_absente'),
            ]));
        }

        $purgees = $this->purgerAnciennes($repertoire);

        Log::info('Sauvegarde de base réalisée', [
            'fichier' => basename($fichier),
            'octets' => filesize($fichier),
            'anciennes_purgees' => $purgees,
        ]);

        return ['fichier' => $fichier, 'octets' => (int) filesize($fichier), 'purgees' => $purgees];
    }

    /**
     * Commande de dump, exposée pour être vérifiable sans exécuter mysqldump.
     *
     * Le mot de passe passe par `--password=` et non par la ligne de commande
     * en clair d'un shell : `Process` reçoit un tableau d'arguments, jamais une
     * chaîne interprétée — pas d'injection possible via un mot de passe
     * contenant des métacaractères.
     *
     * @return list<string>
     */
    public function commande(string $fichier): array
    {
        $connexion = config('database.default');
        $config = config("database.connections.{$connexion}");

        return array_values(array_filter([
            config('backup.mysqldump', 'mysqldump'),
            '--host=' . $config['host'],
            '--port=' . $config['port'],
            '--user=' . $config['username'],
            filled($config['password']) ? '--password=' . $config['password'] : null,
            '--single-transaction',   // dump coherent sans verrouiller les tables
            '--routines',
            '--result-file=' . $fichier,
            $config['database'],
        ]));
    }

    private function purgerAnciennes(string $repertoire): int
    {
        $limite = now()->subDays(self::RETENTION_JOURS)->getTimestamp();
        $purgees = 0;

        foreach (glob($repertoire . '/tatacora-*.sql') ?: [] as $ancien) {
            if (filemtime($ancien) < $limite && unlink($ancien)) {
                $purgees++;
            }
        }

        return $purgees;
    }
}
