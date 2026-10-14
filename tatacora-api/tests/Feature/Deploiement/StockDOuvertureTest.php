<?php

declare(strict_types=1);

namespace Tests\Feature\Deploiement;

use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\StocksSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use PHPUnit\Framework\Attributes\Test;
use Tests\TestCase;

/**
 * Aucun stock d'ouverture n'est posé EN PRODUCTION — 09/09/2026, PA-184.
 *
 * ## Le risque, mesuré avant la mise en service
 *
 * `StocksSeeder` porte deux choses de nature différente : le RÉFÉRENTIEL des
 * 98 articles (utile partout, et sans lui le point de vente n'a rien à
 * vendre) et un STOCK D'OUVERTURE issu du jeu de démonstration.
 *
 * Posé sur la base du Gîte, ce stock fabriquerait de la marchandise que
 * personne n'a reçue. Le défaut ne se verrait pas le jour même : le théorique
 * partirait faux, et l'écart n'apparaîtrait qu'au premier inventaire, imputé
 * à une perte physique ou à un vol. C'est la forme la plus coûteuse d'une
 * donnée inventée — celle qui accuse quelqu'un.
 *
 * Le garde-fou vit dans le seeder, jamais dans la procédure : un
 * avertissement écrit dans un document dépend de la vigilance de
 * l'installateur, à 23 h, sur un serveur qui ne répond pas.
 *
 * ⚠ Ce cas ÉCRIT dans l'environnement (`app()->environment()`), puis le
 * restaure : sans cela il ne mesurerait que le comportement de test.
 */
final class StockDOuvertureTest extends TestCase
{
    use RefreshDatabase;

    #[Test]
    public function la_production_recoit_le_referentiel_mais_aucun_mouvement(): void
    {
        // Les roles sont semes AVANT la bascule : en environnement production,
        // la commande `db:seed` demande une confirmation que le harnais de
        // test ne sait pas donner.
        $this->seed(RolePermissionSeeder::class);

        $environnementInitial = app()->environment();

        try {
            // `app()->environment()` lit l'instance « env » du conteneur, PAS
            // `config('app.env')` : poser la seule configuration laissait le
            // seeder en environnement de test, et ce cas mesurait a cote.
            config()->set('app.env', 'production');
            app()->instance('env', 'production');
            // Le seeder est appele DIRECTEMENT, pas par `$this->seed()` : en
            // environnement production la commande `db:seed` demande une
            // confirmation, que le harnais de test ne sait pas donner. C'est
            // le SEEDER qu'on eprouve ici, pas la commande qui l'appelle.
            app(StocksSeeder::class)->run();

            $this->assertGreaterThan(
                50,
                DB::table('articles')->count(),
                'Le référentiel des articles doit être posé même en production : sans lui, le point de vente n\'a rien à vendre.',
            );

            $this->assertSame(
                0,
                DB::table('mouvements_stock')->count(),
                'Un stock d\'ouverture a été posé en production : il fabrique de la marchandise que personne n\'a reçue, '
                    .'et l\'écart n\'apparaîtra qu\'au premier inventaire, imputé à une perte.',
            );
        } finally {
            config()->set('app.env', $environnementInitial);
            app()->instance('env', $environnementInitial);
        }
    }

    /**
     * Hors production, le stock d'ouverture est bien posé : c'est ce qui rend
     * le jeu de démonstration utilisable, et c'est la contre-épreuve qui
     * empêche ce cas de passer au vert sur un seeder devenu inerte.
     */
    #[Test]
    public function hors_production_le_stock_d_ouverture_est_bien_pose(): void
    {
        $this->seed(RolePermissionSeeder::class);
        $this->seed(StocksSeeder::class);

        $this->assertGreaterThan(
            0,
            DB::table('mouvements_stock')->count(),
            'Le jeu de démonstration n\'a plus de stock : le seeder est devenu inerte partout.',
        );
    }
}
