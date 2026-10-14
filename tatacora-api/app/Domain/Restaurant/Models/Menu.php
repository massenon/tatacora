<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Models;

use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Carte du restaurant (M4).
 *
 * @property string $id
 * @property string $libelle
 * @property string $type
 * @property \Illuminate\Support\Carbon|null $date_debut
 * @property \Illuminate\Support\Carbon|null $date_fin
 */
class Menu extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Types de carte — registre FERME, aligne sur l'enum MySQL de la colonne.
     *
     * C'est aussi la CATEGORIE affichee par le maitre sur chaque plat
     * (`m4-restaurant-carte.html`, colonne « Categorie ») : le schema porte la
     * categorie sur le menu, pas sur le plat. La dupliquer sur `plats` ferait
     * deux verites pour un meme plat des la premiere correction.
     *
     * @var list<string>
     */
    public const TYPES = ['local', 'europeen', 'special'];

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'menus';

    protected $fillable = ['id', 'libelle', 'type', 'date_debut', 'date_fin'];

    protected function casts(): array
    {
        return ['date_debut' => 'date', 'date_fin' => 'date'];
    }

    /**
     * @return HasMany<Plat, $this>
     */
    public function plats(): HasMany
    {
        return $this->hasMany(Plat::class, 'menu_id');
    }
}
