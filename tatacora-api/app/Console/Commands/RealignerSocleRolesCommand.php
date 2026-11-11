<?php

declare(strict_types=1);

namespace App\Console\Commands;

use App\Shared\Audit\Models\JournalAudit;
use App\Shared\Rbac\Models\Role;
use App\Shared\Rbac\Services\RolePermissionService;
use Database\Seeders\RolePermissionSeeder;
use Illuminate\Console\Command;
use Illuminate\Support\Str;

/**
 * RAMÈNE des rôles du SOCLE du CdCF (`RolePermissionSeeder::MATRICE`) à leur
 * matrice par défaut, sur une base déjà semée (PO, 10/11/2026 : « le Barman
 * doit être conforme au socle ; le Comptable a les mêmes droits que le
 * Gérant »). Le seeder, lui, ne réécrit JAMAIS un rôle existant.
 *
 * - `--role=barman` (répétable) borne l'opération à des rôles nommés ; sans
 *   `--role`, tous les rôles du socle sont concernés.
 * - `--dry-run` montre l'écart par rôle et n'écrit RIEN : aucune écriture.
 * - Un rôle créé à l'écran (hors socle) n'est JAMAIS touché ; le nommer est
 *   refusé. IDEMPOTENT : un rôle déjà conforme n'est pas réécrit.
 * - Chaque rôle réellement réécrit est TRACÉ au journal d'audit ; la
 *   modification du rôle (`touch`) le fait redescendre aux postes
 *   (`roles` → `roles_local`) à la synchronisation suivante.
 */
final class RealignerSocleRolesCommand extends Command
{
    protected $signature = 'roles:realigner-socle {--role=* : libellé d\'un rôle du socle (répétable) ; sans option, tous} {--dry-run : affiche l\'écart sans rien écrire}';

    protected $description = 'Ramène des rôles du socle du CdCF à leur matrice par défaut (jamais un rôle créé à l\'écran)';

    public function handle(RolePermissionService $service): int
    {
        $demandes = array_values(array_unique(array_map('strval', (array) $this->option('role'))));
        $socle = array_keys(RolePermissionSeeder::MATRICE);

        $hors = array_diff($demandes, $socle);
        if ($hors !== []) {
            $this->error('Rôle(s) hors du socle, jamais touché(s) : '.implode(', ', $hors).'. Rôles du socle : '.implode(', ', $socle).'.');

            return self::FAILURE;
        }

        $cibles = $demandes === [] ? $socle : $demandes;
        $aRealigner = [];

        foreach ($cibles as $libelle) {
            $role = Role::query()->where('libelle', $libelle)->first();

            if ($role === null) {
                $this->warn($libelle.' : rôle absent de cette base (rien à ramener).');

                continue;
            }

            $ecart = $service->ecartAuSocle($role) ?? [];

            if ($ecart === []) {
                $this->line($libelle.' : conforme au socle.');

                continue;
            }

            $this->info($libelle.' : '.count($ecart).' écart(s) au socle');
            foreach ($ecart as $module => [$actuel, $socleNiveau]) {
                $this->line(sprintf('   %-16s %s  →  %s', $module, $actuel, $socleNiveau));
            }

            $aRealigner[$libelle] = $ecart;
        }

        if ($aRealigner === []) {
            $this->info('Rien à ramener.');

            return self::SUCCESS;
        }

        if ($this->option('dry-run')) {
            $this->comment('Simulation : rien n\'a été écrit. Relancez sans --dry-run pour appliquer.');

            return self::SUCCESS;
        }

        $service->retablirSocle(array_keys($aRealigner));

        foreach ($aRealigner as $libelle => $ecart) {
            $role = Role::query()->where('libelle', $libelle)->first();

            JournalAudit::create([
                'id' => (string) Str::uuid(),
                'utilisateur_id' => null,
                'action' => 'roles:realigner-socle',
                'entite_concernee' => 'roles',
                'entite_id' => (string) ($role?->id ?? Str::uuid()),
                'valeur_avant' => array_map(static fn (array $e): string => $e[0], $ecart),
                'valeur_apres' => array_map(static fn (array $e): string => $e[1], $ecart),
                'adresse_poste' => 'artisan',
            ]);
        }

        $this->info(count($aRealigner).' rôle(s) ramené(s) au socle : '.implode(', ', array_keys($aRealigner)).'.');

        return self::SUCCESS;
    }
}
