<?php

declare(strict_types=1);

namespace Tests\Feature\Seeders;

use App\Models\User;
use Database\Seeders\ComptesReelsSeeder;
use Database\Seeders\RolePermissionSeeder;
use Database\Seeders\UtilisateurSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\Test;
use RuntimeException;
use Tests\TestCase;

/**
 * L'amorçage des comptes RÉELS (PA-167) — le seeder de Production.
 *
 * Ce qui se prouve ici et nulle part ailleurs : aucun mot de passe ne vit
 * dans le code (une variable absente REFUSE tout), un mot de passe déjà posé
 * n'est JAMAIS réécrit par un rejeu, et les comptes de démonstration se
 * désactivent sans jamais disparaître (RG-15).
 *
 * ## Mutation vérifiée (01/09/2026)
 *
 * La garde « variable absente » retirée → rouge sur le premier cas (le
 * seeder créerait un compte au mot de passe vide, hashé — un compte auquel
 * PERSONNE ne peut se connecter, indistinguable d'un compte sain).
 */
final class ComptesReelsSeederTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolePermissionSeeder::class);
    }

    // Depuis le 02/09/2026 le seeder lit `config('comptes_reels...')` — le
    // pont `config/comptes_reels.php` protege la production ou `config:cache`
    // rend `env()` nul. Les tests posent donc la CONFIG, plus des variables
    // d'environnement que le processus de test ne relirait pas.
    private function poserLesVariables(): void
    {
        config()->set('comptes_reels.mots_de_passe.rodrigue', 'secret-de-test-r');
        config()->set('comptes_reels.mots_de_passe.bienvenu', 'secret-de-test-b');
        config()->set('comptes_reels.mots_de_passe.noel', 'secret-de-test-n');
        config()->set('comptes_reels.mots_de_passe.super_admin', 'secret-de-test-s');
    }

    #[Test]
    public function une_variable_absente_refuse_tout_et_rien_n_est_ecrit(): void
    {
        config()->set('comptes_reels.mots_de_passe.rodrigue', 'seul-pose');
        // L'ABSENCE se pose explicitement : le pont `config/comptes_reels.php`
        // lit le `.env` du poste au demarrage, et un developpeur qui y a pose
        // ses trois variables (c'est arrive le 02/09/2026) rendrait ce cas
        // vert ou rouge selon SA machine — un test ne lit jamais l'ambiant.
        config()->set('comptes_reels.mots_de_passe.bienvenu', '');
        config()->set('comptes_reels.mots_de_passe.noel', '');
        config()->set('comptes_reels.mots_de_passe.super_admin', '');

        try {
            $this->seed(ComptesReelsSeeder::class);
            $this->fail('Une variable absente aurait dû refuser le seeder entier.');
        } catch (RuntimeException $refus) {
            $this->assertStringContainsString('COMPTE_BIENVENU_MOT_DE_PASSE', $refus->getMessage());
        }

        $this->assertSame(0, User::count(), 'Un refus n\'écrit RIEN — pas d\'amorçage à moitié fait.');
    }

    #[Test]
    public function les_quatre_comptes_naissent_avec_leur_role_et_les_demonstrations_se_desactivent(): void
    {
        $this->seed(UtilisateurSeeder::class);
        $this->poserLesVariables();

        $this->seed(ComptesReelsSeeder::class);

        // Quatre depuis le 03/09/2026 : `super_admin` rejoint la liste (PA-177).
        foreach (['rodrigue', 'bienvenu', 'noel', 'super_admin'] as $login) {
            $compte = User::query()->where('login', $login)->firstOrFail();
            $this->assertSame('actif', $compte->statut);
        }

        $this->assertSame(
            'administrateur',
            User::query()->where('login', 'rodrigue')->firstOrFail()->role->libelle,
        );
        $this->assertSame(
            'super_admin',
            User::query()->where('login', 'super_admin')->firstOrFail()->role->libelle,
        );

        // Les onze comptes de démonstration : DÉSACTIVÉS, jamais supprimés
        // (RG-15 — une vente continue de porter le nom de qui l'a encaissée).
        $demonstration = User::query()
            ->whereIn('login', array_column(UtilisateurSeeder::COMPTES, 'login'))
            ->get();

        $this->assertCount(count(UtilisateurSeeder::COMPTES), $demonstration);
        $this->assertSame(0, $demonstration->where('statut', 'actif')->count());
    }

    #[Test]
    public function un_mot_de_passe_deja_pose_n_est_jamais_reecrit_par_un_rejeu(): void
    {
        $this->poserLesVariables();
        $this->seed(ComptesReelsSeeder::class);

        // L'utilisateur change son mot de passe…
        $rodrigue = User::query()->where('login', 'rodrigue')->firstOrFail();
        $rodrigue->update(['mot_de_passe_hash' => Hash::make('choisi-par-lui')]);

        // …et un rejeu du seeder ne le réinitialise PAS à la valeur du .env.
        $this->seed(ComptesReelsSeeder::class);

        $this->assertTrue(
            Hash::check('choisi-par-lui', User::query()->where('login', 'rodrigue')->firstOrFail()->mot_de_passe_hash),
            'Un rejeu du seeder a réécrit un mot de passe changé par son propriétaire.',
        );
    }
}
