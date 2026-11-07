<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class LigneProforma extends Model
{
    use HasUuids;

    protected $table = 'lignes_proforma';

    protected $fillable = ['id', 'proforma_id', 'position', 'designation', 'quantite', 'prix_unitaire', 'montant'];

    protected function casts(): array
    {
        return ['quantite' => 'integer', 'prix_unitaire' => 'integer', 'montant' => 'integer', 'position' => 'integer'];
    }

    /** @return BelongsTo<Proforma, $this> */
    public function proforma(): BelongsTo
    {
        return $this->belongsTo(Proforma::class, 'proforma_id');
    }
}
