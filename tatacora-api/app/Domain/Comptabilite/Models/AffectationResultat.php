<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * L'affectation du résultat d'un exercice clôturé — voir
 * `AffectationResultatService`. ACTIVE tant qu'elle n'a pas été contre-passée.
 *
 * @property string $id
 * @property string $exercice_id exercice dont le résultat est affecté (N-1)
 * @property string $cloture_id
 * @property string $resultat signé : positif bénéfice, négatif perte
 * @property \Illuminate\Support\Carbon $date_approbation
 * @property string $reserve_legale
 * @property string $autres_reserves
 * @property string $dividendes
 * @property string $report_a_nouveau_crediteur
 * @property string $report_a_nouveau_debiteur
 * @property string $piece_affectation
 * @property \Illuminate\Support\Carbon $affectee_le
 * @property string|null $affectee_par
 * @property \Illuminate\Support\Carbon|null $contrepassee_le
 */
class AffectationResultat extends Model
{
    use HasUuids;

    protected $table = 'affectations_resultat';

    protected $fillable = [
        'exercice_id', 'cloture_id', 'resultat', 'date_approbation', 'reserve_legale', 'autres_reserves',
        'dividendes', 'report_a_nouveau_crediteur', 'report_a_nouveau_debiteur', 'piece_affectation',
        'piece_origine_id', 'motif', 'affectee_par', 'affectee_le', 'contrepassee_par', 'contrepassee_le',
        'motif_contrepassation',
    ];

    protected function casts(): array
    {
        return [
            'resultat' => 'decimal:2',
            'reserve_legale' => 'decimal:2',
            'autres_reserves' => 'decimal:2',
            'dividendes' => 'decimal:2',
            'report_a_nouveau_crediteur' => 'decimal:2',
            'report_a_nouveau_debiteur' => 'decimal:2',
            'date_approbation' => 'date',
            'affectee_le' => 'datetime',
            'contrepassee_le' => 'datetime',
        ];
    }

    /** @return BelongsTo<ExerciceComptable, $this> */
    public function exercice(): BelongsTo
    {
        return $this->belongsTo(ExerciceComptable::class, 'exercice_id');
    }

    /** @return BelongsTo<\App\Models\User, $this> */
    public function auteur(): BelongsTo
    {
        return $this->belongsTo(\App\Models\User::class, 'affectee_par');
    }

    public function estActive(): bool
    {
        return $this->contrepassee_le === null;
    }
}
