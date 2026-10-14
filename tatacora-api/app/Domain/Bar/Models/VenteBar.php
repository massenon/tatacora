<?php

declare(strict_types=1);

namespace App\Domain\Bar\Models;

use App\Domain\Crm\Models\Client;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Vente au comptoir du bar (M5).
 *
 * `session_id` est NOT NULL : toute vente est rattachee a une session de
 * caisse. Sans ce rattachement, le rapprochement de caisse en fin de service
 * (EF-M2-07) serait impossible — on ne saurait pas quelles ventes comparer au
 * montant constate en tiroir.
 *
 * @see RG-15 Journalisation (trait Auditable)
 *
 * @property string $id
 * @property string $session_id
 * @property string|null $client_id
 * @property \Illuminate\Support\Carbon $date_vente
 * @property string $montant
 */
class VenteBar extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'ventes_bar';

    protected $fillable = ['id', 'session_id', 'client_id', 'date_vente', 'montant'];

    protected function casts(): array
    {
        return [
            'date_vente' => 'datetime',
            'montant' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return HasMany<LigneVenteBar, $this>
     */
    public function lignes(): HasMany
    {
        return $this->hasMany(LigneVenteBar::class, 'vente_id');
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }
}
