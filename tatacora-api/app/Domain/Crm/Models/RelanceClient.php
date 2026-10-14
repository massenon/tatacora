<?php

declare(strict_types=1);

namespace App\Domain\Crm\Models;

use App\Models\User;
use App\Shared\Audit\Traits\Auditable;
use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Relance d'un client débiteur (M3) — PA-165.
 *
 * Un fait de gestion, jamais un mouvement d'argent : aucune écriture
 * comptable n'en découle. `montant_reclame` est figé au jour de la relance —
 * c'est ce qui a été dit au client, pas le solde vivant qui, lui, se
 * recalcule (PA-126).
 *
 * @property string $id
 * @property string $client_id
 * @property \Illuminate\Support\Carbon $date_relance
 * @property string $canal
 * @property string $montant_reclame
 * @property \Illuminate\Support\Carbon|null $promesse
 * @property string|null $commentaire
 */
class RelanceClient extends Model
{
    use Auditable;
    use HasUuids;

    protected $table = 'relances_clients';

    /**
     * Registre FERMÉ — la même liste que la contrainte CHECK du schéma.
     *
     * @var list<string>
     */
    public const CANAUX = ['telephone', 'whatsapp', 'email', 'courrier', 'visite'];

    protected $fillable = [
        'id',
        'client_id',
        'date_relance',
        'canal',
        'montant_reclame',
        'promesse',
        'commentaire',
    ];

    protected function casts(): array
    {
        return [
            'date_relance' => 'date',
            'promesse' => 'date',
            'montant_reclame' => 'decimal:2',
            'date_creation' => 'datetime',
            'date_modification' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<Client, $this>
     */
    public function client(): BelongsTo
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    /**
     * L'opérateur qui a tracé la relance — colonne d'audit du trait
     * `Auditable` (PA-165) : la colonne « Par » de l'historique des
     * relances (M3) la lit par cette relation.
     *
     * @return BelongsTo<User, $this>
     */
    public function utilisateurCreation(): BelongsTo
    {
        return $this->belongsTo(User::class, 'utilisateur_creation_id');
    }
}
