<?php

declare(strict_types=1);

namespace App\Shared\Rbac\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;

/**
 * Droit unitaire sur un couple (module, action).
 *
 * Modules : M1 à M14, plus ROLES et PARAM (administration).
 * Actions : lire, creer, modifier, supprimer, valider.
 *
 * @see RG-16
 */
class Permission extends Model
{
    use HasUuids;

    protected $table = 'permissions';

    protected $fillable = ['id', 'module', 'action'];

    /**
     * @return BelongsToMany<Role, $this>
     */
    public function roles(): BelongsToMany
    {
        return $this->belongsToMany(Role::class, 'permission_role');
    }
}
