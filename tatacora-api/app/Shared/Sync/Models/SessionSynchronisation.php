<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Trace d'une session de synchronisation — LARAVEL_SYNC_FLUTTER.md §3, etape 5.
 *
 * @property string $id
 * @property string $poste_id
 * @property \Illuminate\Support\Carbon $date_sync
 * @property int $nb_enregistrements
 * @property int $conflits_detectes
 * @property string $statut
 */
class SessionSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'sessions_synchronisation';

    protected $fillable = ['id', 'poste_id', 'date_sync', 'nb_enregistrements', 'conflits_detectes', 'statut'];

    protected function casts(): array
    {
        return [
            'date_sync' => 'datetime',
            'nb_enregistrements' => 'integer',
            'conflits_detectes' => 'integer',
        ];
    }
}
