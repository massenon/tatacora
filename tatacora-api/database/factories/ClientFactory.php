<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Domain\Crm\Models\Client;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Client>
 */
class ClientFactory extends Factory
{
    protected $model = Client::class;

    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'nom' => fake()->lastName(),
            'prenom' => fake()->firstName(),
            // Format béninois, cohérent avec SEEDER_TEST_LARAVEL.md
            'telephone' => fake()->numerify('01 ## ## ## ##'),
            'email' => fake()->unique()->safeEmail(),
            'type_client' => fake()->randomElement(['particulier', 'groupe', 'agence', 'structure']),
            'solde' => '0.00',
        ];
    }

    public function particulier(): static
    {
        return $this->state(fn (array $attributes) => ['type_client' => 'particulier']);
    }
}
