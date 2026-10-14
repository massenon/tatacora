<?php

declare(strict_types=1);

namespace App\Domain\Vehicules\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Entretien ou carburation d'un véhicule — EF-M8-05.
 *
 * Une seule table pour les deux, distinguées par `type` : c'est le schéma
 * documenté (`FULL_MIGRATIONS_DATABASE_PART2.md` §13), et les deux partagent
 * la même structure — date, coût, chauffeur affecté.
 *
 * @property string $id
 * @property string $vehicule_id
 * @property string $type
 * @property \Illuminate\Support\Carbon $date
 * @property string $cout
 * @property string|null $chauffeur_id
 */
class EntretienVehicule extends Model
{
    use Auditable;
    use HasUuids;

    public const TYPE_ENTRETIEN = 'entretien';

    public const TYPE_CARBURATION = 'carburation';

    protected $table = 'entretiens_vehicule';

    protected $fillable = ['id', 'vehicule_id', 'type', 'date', 'cout', 'chauffeur_id'];

    protected function casts(): array
    {
        return [
            'date' => 'date',
            'cout' => 'decimal:2',
        ];
    }

    /**
     * @return BelongsTo<Vehicule, $this>
     */
    public function vehicule(): BelongsTo
    {
        return $this->belongsTo(Vehicule::class, 'vehicule_id');
    }
}
