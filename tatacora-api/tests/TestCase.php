<?php

declare(strict_types=1);

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    /**
     * ⚠ GARDE ABSOLUE — la suite ne touche JAMAIS une base qui n'est pas de
     * test (03/09/2026, incident reel) : un `php artisan config:cache` lance
     * en local (etape §5 de la procedure de deploiement, jouee sur le poste)
     * FIGE la configuration — `DB_DATABASE=tatacora_test php artisan test`
     * lit alors le cache, pas l'environnement, et `RefreshDatabase` a
     * reellement VIDE `tatacora_dev` : donnees de demonstration et saisies
     * manuelles du Product Owner, perdues (recuperees du binlog MySQL).
     *
     * Le nom doit CONTENIR « test » : c'est la convention des bases de ce
     * depot (`tatacora_test`, `tatacora_agent_*` etant posees par les agents
     * qui les creent eux-memes en dehors de cette suite).
     */
    protected function setUp(): void
    {
        // AVANT tout boot de l'application : le controle lit le fichier de
        // cache lui-meme, parce que c'est LUI le vecteur — et qu'apres
        // `parent::setUp()`, RefreshDatabase aurait deja agi.
        $cache = dirname(__DIR__).'/bootstrap/cache/config.php';

        if (is_file($cache)) {
            $config = require $cache;
            $base = (string) ($config['database']['connections']['mysql']['database'] ?? '');

            if (! str_contains($base, 'test') && ! str_contains($base, 'agent')) {
                self::fail(
                    'REFUS : un cache de configuration fige la base « '.$base.' », qui n\'est pas une base de test — '
                    .'DB_DATABASE est ignore et RefreshDatabase detruirait des donnees reelles (incident du 02/09/2026). '
                    .'Lancez `php artisan config:clear` puis relancez la suite.',
                );
            }
        }

        parent::setUp();
    }

    /**
     * Après tout semis des rôles, pose le rôle d'ESSAI « lecteur » : l'ANCIENNE matrice du
     * comptable (lecture seule partout, écriture sur M10 et M14). Décision du PO du 10/11/2026 :
     * le comptable a désormais les droits du gérant — il n'est donc plus le représentant d'un
     * « rôle en lecture seule » ; les tests qui prouvent un refus d'écriture lui substituent
     * ce rôle d'essai, sans toucher au socle livré (jamais semé hors des tests).
     *
     * @param  class-string|string  $class
     */
    public function seed($class = 'Database\\Seeders\\DatabaseSeeder')
    {
        parent::seed($class);
        $this->poserLeRoleLecteurDEssai();

        return $this;
    }

    protected function poserLeRoleLecteurDEssai(): void
    {
        if (! class_exists(\App\Shared\Rbac\Models\Role::class)
            || \App\Shared\Rbac\Models\Role::query()->where('libelle', 'lecteur')->exists()
            || ! \App\Shared\Rbac\Models\Role::query()->where('libelle', 'comptable')->exists()) {
            return;
        }

        $matrice = [
            'M1' => 'L', 'M2' => 'L', 'M3' => 'L', 'M4' => 'L', 'M5' => 'L', 'M6' => 'L', 'M7' => 'L', 'M8' => 'L',
            'M9' => 'L', 'M10' => 'C', 'M11' => 'L', 'M12' => '-', 'M13' => 'L', 'M14' => 'C', 'ROLES' => '-',
            'PARAM' => '-', 'ANNULATIONS' => 'L', 'PROFIL_NOM' => 'C', 'PROFIL_TELEPHONE' => 'C',
            'PROFIL_INTITULE' => '-', 'SYNCHRO' => 'L', 'APPAIRAGE' => 'L', 'IMPORT_EXPORT' => 'L',
        ];
        $role = \App\Shared\Rbac\Models\Role::create(['id' => (string) \Illuminate\Support\Str::uuid(), 'libelle' => 'lecteur']);
        foreach ($matrice as $module => $niveau) {
            if ($niveau === '-') {
                continue;
            }
            $actions = $niveau === 'C' ? ['lire', 'creer', 'modifier', 'supprimer', 'valider'] : ['lire'];
            foreach ($actions as $action) {
                $permission = \App\Shared\Rbac\Models\Permission::query()->where('module', $module)->where('action', $action)->first();
                if ($permission !== null) {
                    $role->permissions()->syncWithoutDetaching([$permission->id]);
                }
            }
        }
    }
}
