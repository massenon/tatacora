<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Models;

use App\Models\User;
use Database\Factories\RoleFactory;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Rôle applicatif — 11 rôles métier (01_BUSINESS_ANALYSIS_SPEC.md §3).
 *
 * @see RG-16 Contrôle d'accès basé sur les rôles
 */
class Role extends Model
{
    /** @use HasFactory<RoleFactory> */
    use HasFactory;

    use HasUuids;

    protected $table = 'roles';

    protected $fillable = ['id', 'libelle', 'description'];

    /**
     * Resolution explicite : l'arborescence par domaine (app/Shared/...) ne
     * correspond pas a la convention Database\Factories\<chemin> de Laravel.
     *
     * @return Factory<self>
     */
    protected static function newFactory(): Factory
    {
        return RoleFactory::new();
    }

    /**
     * Table pivot `permission_role` — LA matrice RBAC
     * (03_DATABASE_ENGINEERING.md §13).
     *
     * @return BelongsToMany<Permission, $this>
     */
    public function permissions(): BelongsToMany
    {
        return $this->belongsToMany(Permission::class, 'permission_role');
    }

    /**
     * @return HasMany<User, $this>
     */
    public function utilisateurs(): HasMany
    {
        return $this->hasMany(User::class, 'role_id');
    }

    /**
     * Niveau d'accès effectif de ce rôle sur un module : 'C' (complet),
     * 'L' (lecture seule) ou '-' (aucun accès).
     *
     * Dérivé des permissions réellement attachées — jamais une colonne
     * dénormalisée qui pourrait diverger de la matrice (AVOID_INSTRUCTIONS.md §3).
     */
    public function niveauSurModule(string $module): string
    {
        $actions = $this->permissions
            ->where('module', $module)
            ->pluck('action')
            ->all();

        if ($actions === []) {
            return '-';
        }

        return count($actions) > 1 ? 'C' : 'L';
    }
}
