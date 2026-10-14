<?php

declare(strict_types=1);

namespace App\Domain\Ventes\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

/**
 * Une table de salle — référentiel administrable de l'onglet « Espaces &
 * tables » (maître `tables-engine.js`, porté au schéma le 02/09/2026).
 *
 * ## `actif` n'est PAS l'occupation
 *
 * `actif` dit si la table est PROPOSÉE au point de vente (désactivée = retirée
 * du service, jamais supprimée — RG-02). L'occupation, elle, se DÉDUIT des
 * paniers ouverts (`paniers.table_id`), jamais d'un drapeau : un drapeau posé
 * à la main se désynchroniserait au premier panier clôturé depuis un autre
 * écran (tables-engine.js, `estOccupee()` — et PA-126 côté serveur).
 *
 * Toute écriture passe par {@see \App\Domain\Ventes\Services\TableSalleService},
 * l'unique auteur des règles (unicité du numéro, libellé qui suit le numéro,
 * refus de désactiver une table au panier ouvert).
 *
 * @property string $id
 * @property string $espace
 * @property int $numero
 * @property string $libelle
 * @property int $places
 * @property bool $actif
 */
class TableSalle extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'tables_salle';

    protected $fillable = [
        'id',
        'espace',
        'numero',
        'libelle',
        'places',
        'actif',
    ];

    /**
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'numero' => 'integer',
            'places' => 'integer',
            'actif' => 'boolean',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }
}
