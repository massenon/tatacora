<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de plat commande (M4).
 *
 * @property string $id
 * @property string $commande_id
 * @property string $plat_id
 * @property int $quantite
 */
class LigneCommandeRestaurant extends Model
{
    use HasUuids;

    protected $table = 'lignes_commande_restaurant';

    protected $fillable = ['id', 'commande_id', 'plat_id', 'quantite'];

    protected function casts(): array
    {
        return ['quantite' => 'integer'];
    }

    /**
     * @return BelongsTo<Plat, $this>
     */
    public function plat(): BelongsTo
    {
        return $this->belongsTo(Plat::class, 'plat_id');
    }

    /**
     * @return BelongsTo<CommandeRestaurant, $this>
     */
    public function commande(): BelongsTo
    {
        return $this->belongsTo(CommandeRestaurant::class, 'commande_id');
    }
}
