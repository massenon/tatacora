<?php

declare(strict_types=1);

namespace App\Domain\Hebergement\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Type d'unite d'hebergement : Bungalow, Chambre, Tente (M1).
 *
 * @property string $id
 * @property string $libelle
 * @property int $capacite_max
 * @property string $tarif_base
 */
class CategorieHebergement extends Model
{
    use HasUuids;

    protected $table = 'categories_hebergement';

    protected $fillable = ['id', 'libelle', 'capacite_max', 'tarif_base'];

    protected function casts(): array
    {
        return [
            'capacite_max' => 'integer',
            'tarif_base' => 'decimal:2',
        ];
    }

    /**
     * @return HasMany<UniteHebergement, $this>
     */
    public function unites(): HasMany
    {
        return $this->hasMany(UniteHebergement::class, 'categorie_id');
    }
}
