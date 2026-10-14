<?php

declare(strict_types=1);

namespace App\Domain\Restaurant\Models;

use App\Domain\Crm\Models\Client;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Commande en salle ou room-service (M4).
 *
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string|null $table_ou_chambre_id
 * @property string|null $client_id
 * @property \Illuminate\Support\Carbon $date_commande
 * @property string $statut
 */
class CommandeRestaurant extends Model
{
    use Auditable;
    use HasUuids;

    /**
     * Statuts du cycle de vie — registre FERME, aligne sur l'enum MySQL.
     *
     * `cloturee` n'est atteint par aucun chemin de ce depot : EF-M4-07
     * (transfert vers la facturation) n'est pas implemente, et
     * `CommandeRestaurantService` n'expose aucune methode de cloture. Le
     * statut reste declare parce que la colonne l'accepte ; il n'est ni
     * produit ni propose a l'ecriture.
     *
     * @var list<string>
     */
    public const STATUTS = ['en_preparation', 'transmise_cuisine', 'servie', 'cloturee', 'annulee'];

    public const PAR_PAGE_DEFAUT = 50;

    public const PAR_PAGE_MAX = 200;

    protected $table = 'commandes_restaurant';

    protected $fillable = ['id', 'table_ou_chambre_id', 'client_id', 'date_commande', 'statut'];

    protected function casts(): array
    {
        return [
            'date_commande' => 'datetime',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return HasMany<LigneCommandeRestaurant, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneCommandeRestaurant::class, 'commande_id');
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    public function estTransmise(): bool
    {
        return in_array($this->statut, ['transmise_cuisine', 'servie', 'cloturee'], true);
    }
}
