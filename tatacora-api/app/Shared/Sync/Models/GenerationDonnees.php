<?php

declare(strict_types=1);

namespace App\Shared\Sync\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Str;

/**
 * Une génération des données du serveur — voir
 * `GenerationDonneesService`. La plus récente est la COURANTE.
 *
 * @property int $rang
 * @property string $generation
 * @property string $motif
 * @property \Illuminate\Support\Carbon $created_at
 */
class GenerationDonnees extends Model
{
    public const UPDATED_AT = null;

    protected $table = 'generations_donnees';

    protected $primaryKey = 'rang';

    protected $fillable = ['utilisateur_id', 'motif'];

    protected static function booted(): void
    {
        static::creating(static function (self $g): void {
            $g->generation ??= (string) Str::uuid();
        });
    }

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }
}
