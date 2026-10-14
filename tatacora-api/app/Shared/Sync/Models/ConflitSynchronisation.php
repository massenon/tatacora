<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * File d'arbitrage des conflits — RG-17, LARAVEL_SYNC_FLUTTER.md §4.2.
 *
 * Les deux versions sont conservees cote a cote : meme sur une table
 * non-financiere resolue automatiquement, la version perdante n'est JAMAIS
 * ecrasee sans trace.
 *
 * @property string $id
 * @property string $session_id
 * @property string $table_concernee
 * @property string $entite_id
 * @property array<string, mixed> $version_locale
 * @property array<string, mixed> $version_serveur
 * @property string $statut
 * @property string|null $arbitre_par_id
 */
class ConflitSynchronisation extends Model
{
    use HasUuids;

    protected $table = 'conflits_synchronisation';

    protected $fillable = [
        'id', 'session_id', 'table_concernee', 'entite_id',
        'version_locale', 'version_serveur', 'statut', 'arbitre_par_id', 'date_arbitrage',
    ];

    protected function casts(): array
    {
        return [
            'version_locale' => 'array',
            'version_serveur' => 'array',
            'date_arbitrage' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function arbitre(): BelongsTo
    {
        return $this->belongsTo(User::class, 'arbitre_par_id');
    }

    public function estEnAttente(): bool
    {
        return $this->statut === 'en_attente_arbitrage';
    }
}
