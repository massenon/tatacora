<?php

declare(strict_types=1);

namespace App\Shared\Secrets\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Un secret technique, chiffré par `APP_KEY` (cast `encrypted`). Écrit et lu
 * par `SecretsConfigurationService` SEUL ; la valeur n'est jamais sérialisée.
 *
 * @property string $cle
 * @property string $valeur
 */
class SecretConfiguration extends Model
{
    use HasUuids;

    protected $table = 'secrets_configuration';

    protected $fillable = ['cle', 'valeur', 'utilisateur_id'];

    /** La valeur ne sort jamais d'un `toArray()` ni d'un `toJson()`. */
    protected $hidden = ['valeur'];

    protected function casts(): array
    {
        return ['valeur' => 'encrypted'];
    }

    /** @return BelongsTo<User, $this> */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }
}
