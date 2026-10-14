<?php

declare(strict_types=1);

namespace App\Domain\Rh\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Service (département RH) — M13.
 *
 * ATTENTION, collision de nom documentée (ARBORESCENCE_COMPLETE_PROJET.md,
 * « Note sur les collisions de noms ») : ce modèle entre en collision avec le
 * concept générique de « service » applicatif Laravel. Convention retenue —
 * toujours référencé par son namespace complet `App\Domain\Rh\Models\Service`,
 * jamais importé sans alias depuis un fichier hors du domaine RH.
 *
 * Table volontairement sans colonnes d'audit : simple nomenclature, sans
 * enjeu de traçabilité financière (03_DATABASE_ENGINEERING.md §12).
 *
 * @property string $id
 * @property string $libelle
 */
class Service extends Model
{
    use HasUuids;

    protected $table = 'services';

    protected $fillable = ['id', 'libelle'];

    /**
     * @return HasMany<Employe, $this>
     */
    public function employes(): HasMany
    {
        return $this->hasMany(Employe::class, 'service_id');
    }
}
