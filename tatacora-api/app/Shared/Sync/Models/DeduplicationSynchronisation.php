<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Memoire d'idempotence — LARAVEL_SYNC_FLUTTER.md §5.
 *
 * @property string $id
 * @property string $uuid_operation
 * @property string $utilisateur_id
 * @property string $poste_id
 * @property string $table_concernee
 * @property string $entite_id
 * @property array<string, mixed> $resultat
 * @property \Illuminate\Support\Carbon $date_traitement
 */
class DeduplicationSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'deduplication_synchronisation';

    public $timestamps = false;

    protected $fillable = [
        'id', 'uuid_operation', 'utilisateur_id', 'poste_id',
        'table_concernee', 'entite_id', 'resultat', 'horodatage_client', 'date_traitement',
    ];

    protected function casts(): array
    {
        return ['resultat' => 'array', 'horodatage_client' => 'datetime', 'date_traitement' => 'datetime'];
    }
}
