<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Shared\Rbac\Models\Role;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Role>
 */
class RoleFactory extends Factory
{
    protected $model = Role::class;

    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'libelle' => fake()->unique()->word(),
            'description' => fake()->sentence(),
        ];
    }
}
