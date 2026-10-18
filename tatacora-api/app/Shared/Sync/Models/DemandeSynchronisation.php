<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Une demande « Synchroniser » faite au serveur (PWA) — la plus récente fait
 * foi. Voir `SuiviPostesService`.
 */
class DemandeSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'demandes_synchronisation';

    protected $fillable = ['utilisateur_id', 'demandee_le'];

    protected function casts(): array
    {
        return ['demandee_le' => 'datetime'];
    }
}
