<?php

declare(strict_types=1);

namespace App\Domain\Caisse\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Session de Caisse active ou clôturée par point de vente.
 *
 * @property string $id
 * @property string $point_vente (bar, restaurant, reception)
 * @property string $utilisateur_ouverture_id
 * @property string|null $utilisateur_cloture_id
 * @property \Illuminate\Support\Carbon $date_ouverture
 * @property \Illuminate\Support\Carbon|null $date_cloture
 * @property float $montant_fond
 * @property float|null $montant_theorique
 * @property float|null $montant_constate
 */
class SessionCaisse extends Model
{
    use HasUuids;

    protected $table = 'sessions_caisse';

    protected $fillable = [
        'id',
        'point_vente',
        'utilisateur_ouverture_id',
        'utilisateur_cloture_id',
        'date_ouverture',
        'date_cloture',
        'montant_fond',
        'montant_theorique',
        'montant_constate',
    ];

    protected function casts(): array
    {
        return [
            'date_ouverture' => 'datetime',
            'date_cloture' => 'datetime',
            'montant_fond' => 'decimal:2',
            'montant_theorique' => 'decimal:2',
            'montant_constate' => 'decimal:2',
        ];
    }
}
