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
}
