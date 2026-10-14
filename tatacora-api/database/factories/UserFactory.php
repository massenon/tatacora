<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;

/**
 * Factory du compte d'acces applicatif — table `utilisateurs`.
 *
 * Reecrite depuis la factory par defaut de Laravel, qui alimentait
 * name/email/password : ces colonnes n'existent pas dans ce schema
 * (03_DATABASE_ENGINEERING.md §2). Laissee en l'etat, elle aurait echoue
 * au premier test l'utilisant, avec une erreur SQL peu parlante.
 *
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    protected $model = User::class;

    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'login' => fake()->unique()->userName(),
            // Mot de passe de test explicite : aucune valeur plausible de
            // production ne doit apparaitre dans une factory (SECURITY_STRICT.md).
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::factory(),
            'statut' => 'actif',
        ];
    }

    public function suspendu(): static
    {
        return $this->state(fn (array $attributes) => ['statut' => 'suspendu']);
    }

    public function desactive(): static
    {
        return $this->state(fn (array $attributes) => ['statut' => 'desactive']);
    }
}
