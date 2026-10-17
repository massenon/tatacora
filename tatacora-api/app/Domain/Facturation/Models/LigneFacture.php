<?php

declare(strict_types=1);

namespace App\Domain\Facturation\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Ligne de facture rattachee a son module d'origine — RG-04.
 *
 * `source_module` + `source_id` : c'est ce couple qui permet a une facture de
 * consolider hebergement, restaurant, bar, tourisme et vehicules sur un meme
 * document. Une facture n'est jamais la "propriete" d'un seul module.
 *
 * @property string $id
 * @property string $facture_id
 * @property string $source_module
 * @property string|null $source_id
 * @property string $libelle
 * @property string $quantite
 * @property string $prix_unitaire
 * @property string $montant
 */
class LigneFacture extends Model
{
    use HasUuids;

    protected $table = 'lignes_facture';

    protected $fillable = [
        'id', 'facture_id', 'source_module', 'source_id',
        'libelle', 'quantite', 'prix_unitaire', 'prix_catalogue', 'montant',
    ];

    protected function casts(): array
    {
        return [
            'quantite' => 'decimal:2',
            'prix_unitaire' => 'decimal:2',
            'montant' => 'decimal:2',
        ];
    }

    /**
     * @return BelongsTo<Facture, $this>
     */
    public function facture(): BelongsTo
    {
        return $this->belongsTo(Facture::class, 'facture_id');
    }
}
