<?php

declare(strict_types=1);

namespace Tests\Feature\Sync\Concerns;

use App\Models\User;
use App\Shared\Rbac\Models\Role;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;

/**
 * Les gestes communs des tests du catalogue synchronisé (lot S2, 15/10/2026) :
 * un utilisateur d'un rôle de la matrice, une opération du protocole, un lot
 * poussé sur `/api/v1/sync`.
 *
 * @mixin \Tests\TestCase
 */
trait PousseDesOperations
{
    protected function creerUtilisateur(string $role): User
    {
        return User::create([
            'login' => $role . '.' . Str::random(6),
            'mot_de_passe_hash' => Hash::make('mot-de-passe-de-test'),
            'role_id' => Role::where('libelle', $role)->firstOrFail()->id,
            'statut' => 'actif',
        ]);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    protected function creation(string $table, string $id, array $payload): array
    {
        return $this->operation($table, 'creation', $id, $payload);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    protected function operation(string $table, string $type, string $id, array $payload): array
    {
        return [
            'uuid_operation' => (string) Str::uuid(),
            'table' => $table,
            'type' => $type,
            'entite_id' => $id,
            'payload' => $payload,
            'horodatage_client' => now()->toIso8601String(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $operations
     * @return TestResponse<\Illuminate\Http\JsonResponse>
     */
    protected function pousser(array $operations, User $utilisateur, string $poste = 'poste-windows-1'): TestResponse
    {
        Sanctum::actingAs($utilisateur);

        return $this->postJson('/api/v1/sync', ['poste_id' => $poste, 'operations' => $operations])->assertOk();
    }

    protected function uuid(): string
    {
        return (string) Str::uuid();
    }
}
