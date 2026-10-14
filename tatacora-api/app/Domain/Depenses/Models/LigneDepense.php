<?php

declare(strict_types=1);

namespace App\Domain\Depenses\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de ventilation d'une depense : un compte de charge, un montant.
 *
 * `compte_charge` reste le NUMERO du compte et non une cle etrangere vers
 * `plan_comptable` : c'est la valeur que l'operateur voit et que le comptable
 * relit. La resolution numero -> compte est faite une fois, au moment de
 * passer l'ecriture (`PasserEcritureService`), et un numero inconnu y est
 * refuse — la depense n'existe alors pas du tout, plutot que d'exister avec
 * une imputation invalide.
 *
 * @property string $id
 * @property string $depense_id
 * @property string|null $libelle
 * @property string $compte_charge
 * @property string $nature
 * @property string $famille
 * @property string $montant
 */
class LigneDepense extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'lignes_depense';

    protected $fillable = [
        'id',
        'depense_id',
        'libelle',
        'compte_charge',
        'nature',
        'famille',
        'montant',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'montant' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Depense, $this>
     */
    public function depense(): BelongsTo
    {
        return $this->belongsTo(Depense::class, 'depense_id');
    }
}
