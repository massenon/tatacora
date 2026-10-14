<?php

declare(strict_types=1);

namespace App\Domain\Bar\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de boisson vendue (M5).
 *
 * `prix_unitaire` est fige a la vente : il ne suit pas les evolutions
 * ulterieures du tarif de la carte. Une vente d'hier ne doit pas changer de
 * montant parce que le prix de la biere a augmente ce matin.
 *
 * @property string $id
 * @property string $vente_id
 * @property string $boisson_id
 * @property int $quantite
 * @property string $prix_unitaire
 */
class LigneVenteBar extends Model
{
    use HasUuids;

    protected $table = 'lignes_vente_bar';

    protected $fillable = ['id', 'vente_id', 'boisson_id', 'quantite', 'prix_unitaire'];

    protected function casts(): array
    {
        return ['quantite' => 'integer', 'prix_unitaire' => 'decimal:2'];
    }

    /**
     * @return BelongsTo<CarteBoisson, $this>
     */
    public function boisson(): BelongsTo
    {
        return $this->belongsTo(CarteBoisson::class, 'boisson_id');
    }
}
