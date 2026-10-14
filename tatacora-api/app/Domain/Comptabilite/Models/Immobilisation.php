<?php

declare(strict_types=1);

namespace App\Domain\Comptabilite\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Immobilisation (M10) — `create_immobilisations` migration.
 *
 * Ce modèle ne porte AUCUNE logique d'amortissement : le plan (linéaire,
 * prorata temporis) est calculé à la demande par `ImmobilisationService`,
 * jamais stocké — même principe que le stock théorique
 * (`03_DATABASE_ENGINEERING.md` §7).
 *
 * @see App\Domain\Comptabilite\Services\ImmobilisationService
 *
 * @property string $id
 * @property string $code
 * @property string $libelle
 * @property string $valeur_origine
 * @property int $duree_annees
 * @property \Illuminate\Support\Carbon $date_mise_service
 * @property string|null $compte_immobilisation
 */
class Immobilisation extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'immobilisations';

    protected $fillable = [
        'id', 'code', 'libelle', 'valeur_origine', 'duree_annees',
        'date_mise_service', 'compte_immobilisation',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'valeur_origine' => 'decimal:2',
            'duree_annees' => 'integer',
            'date_mise_service' => 'date',
        ];
    }
}
