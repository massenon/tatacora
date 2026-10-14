<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Lieu physique de stockage : magasin general, cuisine, bar, garage (M6).
 *
 * Le stock est TOUJOURS raisonne par couple (article, point) : 10 bouteilles au
 * bar et 0 au magasin n'est pas la meme situation que 10 au magasin et 0 au bar,
 * meme si le total est identique.
 *
 * @property string $id
 * @property string $libelle
 * @property string|null $type
 */
class PointStockage extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'points_stockage';

    protected $fillable = ['id', 'libelle', 'type'];

    /**
     * @return HasMany<MouvementStock, $this>
     */
    public function mouvements(): HasMany
    {
        return $this->hasMany(MouvementStock::class, 'point_id');
    }
}
