<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Note de credit — SEUL mecanisme de correction d'une facture certifiee (RG-03).
 *
 * L'avoir ne modifie pas la facture d'origine : il la neutralise en tout ou
 * partie. Les deux documents coexistent, ce qui est precisement ce qu'une
 * administration fiscale attend — une correction laisse une trace, elle
 * n'efface pas l'erreur.
 *
 * @property string $id
 * @property string $facture_id
 * @property string $motif
 * @property string $montant
 * @property \Illuminate\Support\Carbon $date_emission
 * @property string|null $utilisateur_validation_id
 */
class Avoir extends Model
{
    use HasUuids;

    protected $table = 'avoirs';

    protected $fillable = [
        'id', 'facture_id', 'motif', 'montant', 'date_emission', 'utilisateur_validation_id',
    ];

    protected function casts(): array
    {
        return [
            'montant' => 'decimal:2',
            'date_emission' => 'date',
        ];
    }

    /**
     * @return BelongsTo<Facture, $this>
     */
    public function facture(): BelongsTo
    {
        return $this->belongsTo(Facture::class, 'facture_id');
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function validateur(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_validation_id');
    }
}
