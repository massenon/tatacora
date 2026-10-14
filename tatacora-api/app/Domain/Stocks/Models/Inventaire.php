<?php

declare(strict_types=1);

namespace App\Domain\Stocks\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Inventaire physique d'un point de stockage — EF-M6-05.
 *
 * La table n'a **aucune colonne de statut** : un inventaire est ouvert, compte,
 * puis cloture par la generation des mouvements de regularisation. L'absence de
 * statut signifie qu'un inventaire cloture ne se distingue pas d'un inventaire
 * ouvert au niveau de la table — seule la presence des mouvements de
 * regularisation en temoigne. Signale en PA-54.
 *
 * @property string $id
 * @property string $point_id
 * @property \Illuminate\Support\Carbon $date_inventaire
 * @property string|null $utilisateur_id
 * @property-read PointStockage $point
 */
class Inventaire extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'inventaires';

    protected $fillable = ['id', 'point_id', 'date_inventaire', 'utilisateur_id'];

    protected function casts(): array
    {
        return ['date_inventaire' => 'date'];
    }

    /**
     * @return HasMany<LigneInventaire, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneInventaire::class, 'inventaire_id');
    }

    /**
     * @return BelongsTo<PointStockage, $this>
     */
    public function point(): BelongsTo
    {
        return $this->belongsTo(PointStockage::class, 'point_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function utilisateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_id');
    }
}
