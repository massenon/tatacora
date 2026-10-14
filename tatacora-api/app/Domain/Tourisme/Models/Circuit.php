<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Circuit touristique — EF-M9-01.
 *
 * @see EF-M9-01 Catalogue de circuits par thème, zone et durée
 * @see EF-M9-04 Capacité maximale par circuit
 *
 * ## `duree` est un libellé, pas un nombre — PA-51
 *
 * La colonne est un `varchar` au schéma : elle porte « 2 jours », « Journée »,
 * « Demi-journée »… Conséquence structurelle, assumée ici : **la durée n'est
 * pas calculable**, donc l'occupation d'un guide sur un circuit de plusieurs
 * jours ne peut pas être déduite. Les vérifications de disponibilité de ce
 * domaine portent sur la seule `date_circuit`.
 *
 * @property string $id
 * @property string $nom
 * @property string $theme
 * @property string $zone
 * @property string $duree
 * @property string $prix
 * @property int $capacite_max
 */
class Circuit extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'circuits';

    protected $fillable = ['id', 'nom', 'theme', 'zone', 'duree', 'prix', 'capacite_max'];

    protected function casts(): array
    {
        return [
            // Montant : DECIMAL(15,2), jamais un flottant.
            'prix' => 'decimal:2',
            'capacite_max' => 'integer',
        ];
    }

    /**
     * @return HasMany<ReservationTour, $this>
     */
    public function reservations(): HasMany
    {
        return $this->hasMany(ReservationTour::class, 'circuit_id');
    }
}
