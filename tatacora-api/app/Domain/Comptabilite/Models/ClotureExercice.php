<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Une clôture d'exercice (lot 2, 20/10/2026) — voir
 * `ClotureExerciceService`. ACTIVE tant qu'elle n'a pas été rouverte.
 *
 * @property string $exercice_id
 * @property string|null $piece_cloture
 * @property string|null $piece_a_nouveaux
 * @property string $resultat
 * @property \Illuminate\Support\Carbon $cloturee_le
 * @property string|null $archive_chemin
 * @property string|null $archive_empreinte
 * @property \Illuminate\Support\Carbon|null $rouverte_le
 * @property string|null $motif_reouverture
 */
class ClotureExercice extends Model
{
    use HasUuids;

    protected $table = 'clotures_exercices';

    protected $fillable = [
        'exercice_id', 'piece_cloture', 'piece_a_nouveaux', 'resultat', 'cloturee_par', 'cloturee_le',
        'archive_chemin', 'archive_empreinte', 'rouverte_par', 'rouverte_le', 'motif_reouverture',
    ];

    protected function casts(): array
    {
        return [
            'resultat' => 'decimal:2',
            'cloturee_le' => 'datetime',
            'rouverte_le' => 'datetime',
        ];
    }

    /** @return BelongsTo<ExerciceComptable, $this> */
    public function exercice(): BelongsTo
    {
        return $this->belongsTo(ExerciceComptable::class, 'exercice_id');
    }

    public function estActive(): bool
    {
        return $this->rouverte_le === null;
    }
}
