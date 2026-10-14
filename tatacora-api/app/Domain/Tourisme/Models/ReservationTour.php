<?php

declare(strict_types=1);

namespace App\Domain\Tourisme\Models;

use App\Domain\Crm\Models\Client;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Réservation d'un circuit — EF-M9-03, EF-M9-05.
 *
 * @see EF-M9-03 Réservation avec affectation de guide
 * @see EF-M9-04 Capacité maximale par circuit
 * @see EF-M9-05 Suivi du déroulement (dates, participants, statut)
 * @see RG-15 Journalisation (trait Auditable)
 *
 * Contrairement à `contrats_location` (PA-50), cette table **porte bien un
 * `statut`** : une réservation erronée peut être annulée et libère aussitôt sa
 * place dans la capacité du départ, comme RG-02 le fait en M1.
 *
 * @property string $id
 * @property string $circuit_id
 * @property string $client_id
 * @property string $guide_id
 * @property \Illuminate\Support\Carbon $date_circuit
 * @property int $nb_participants
 * @property string $statut
 * @property-read Circuit $circuit
 */
class ReservationTour extends Model
{
    use Auditable;
    use HasUuids;

    /** Réservations qui ne consomment plus de place au départ. */
    public const STATUTS_INACTIFS = ['annulee'];

    protected $table = 'reservations_tour';

    protected $fillable = [
        'id', 'circuit_id', 'client_id', 'guide_id',
        'date_circuit', 'nb_participants', 'statut',
    ];

    protected function casts(): array
    {
        return [
            'date_circuit' => 'date',
            'nb_participants' => 'integer',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * Montant de la prestation — CALCULÉ, jamais stocké ni saisi.
     *
     * `bcmul` : `circuits.prix` est un `DECIMAL(15,2)`.
     */
    public function montant(): string
    {
        return bcmul((string) $this->circuit->prix, (string) $this->nb_participants, 2);
    }

    public function estAnnulee(): bool
    {
        return $this->statut === 'annulee';
    }

    public function estTerminee(): bool
    {
        return $this->statut === 'terminee';
    }

    /**
     * @return BelongsTo<Circuit, $this>
     */
    public function circuit(): BelongsTo
    {
        return $this->belongsTo(Circuit::class, 'circuit_id');
    }

    /**
     * @return BelongsTo<Guide, $this>
     */
    public function guide(): BelongsTo
    {
        return $this->belongsTo(Guide::class, 'guide_id');
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }
}
